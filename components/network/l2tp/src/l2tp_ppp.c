/*
 * L2TPv2 (RFC 2661) PPP glue for LuatOS netdrv: link_callbacks bridging the
 * vendored lwIP PPP stack to the L2TP data plane (write/netif_output), and
 * the PPP link-status callback consumed by the client lifecycle.
 *
 * Split from the original single-file l2tp client core; behavior unchanged.
 */

#include "l2tp/l2tp_client.h"
#include "l2tp/l2tp_ctrl.h"
#include "l2tp/l2tp_ppp.h"

#include <string.h>
#include "lwip/def.h"
#include "lwip/pbuf.h"
#include "lwip/timeouts.h"
#include "lwip/sys.h"
#include "netif/ppp/ppp_opts.h"
#include "luat_ppp_opts_override.h"
#include "netif/ppp/ppp_impl.h"
#include "netif/ppp/ppp.h"
#include "netif/ppp/lcp.h"
#include "netif/ppp/magic.h"
#include "netif/ppp/pppcrypt.h"

#define LUAT_LOG_TAG "l2tp"
#include "luat_log.h"
#include "luat_network_adapter.h"

/* Forward declarations (PPP glue callbacks are file-local) */
static err_t l2tp_write(ppp_pcb *ppp, void *ctx, struct pbuf *p);
static err_t l2tp_netif_output(ppp_pcb *ppp, void *ctx, struct pbuf *p, u_short protocol);
static err_t l2tp_destroy(ppp_pcb *ppp, void *ctx);
static void l2tp_connect(ppp_pcb *ppp, void *ctx);
static void l2tp_disconnect(ppp_pcb *ppp, void *ctx);

/* PPP core callbacks */
const struct link_callbacks l2tp_callbacks = {
    l2tp_connect,
    l2tp_disconnect,
    l2tp_destroy,
    l2tp_write,
    l2tp_netif_output,
    NULL, /* send_config */
    NULL  /* recv_config */
};

/* Called by PPP core to send control/data PPP frames */
static err_t l2tp_write(ppp_pcb *ppp, void *ctx, struct pbuf *p) {
    l2tp_client_t *cli = (l2tp_client_t *)ctx;
    LWIP_UNUSED_ARG(ppp);
    /* Skip the 2-byte HDLC address/control (0xff 0x03), keep the protocol field */
    return l2tp_data_send(cli, p, 2, 0, 0);
}

/* Called by the PPP netif to send an IPv4 packet */
static err_t l2tp_netif_output(ppp_pcb *ppp, void *ctx, struct pbuf *p, u_short protocol) {
    l2tp_client_t *cli = (l2tp_client_t *)ctx;
    LWIP_UNUSED_ARG(ppp);
    return l2tp_data_send(cli, p, 0, 1, protocol);
}

/* Destroy lower protocol control block (l2tp_client_t is owned by netdrv glue) */
static err_t l2tp_destroy(ppp_pcb *ppp, void *ctx) {
    l2tp_client_t *cli = (l2tp_client_t *)ctx;
    LWIP_UNUSED_ARG(ppp);
    sys_untimeout(l2tp_timeout, cli);
    sys_untimeout(l2tp_periodic_timer, cli);
    return ERR_OK;
}

/* Be a LAC, connect to a LNS */
static void l2tp_connect(ppp_pcb *ppp, void *ctx) {
    l2tp_client_t *cli = (l2tp_client_t *)ctx;
    lcp_options *lcp_wo = &ppp->lcp_wantoptions;
    lcp_options *lcp_ao = &ppp->lcp_allowoptions;
    err_t err;

    cli->tunnel_port = cli->remote_port;
    cli->our_ns = 0;
    cli->peer_nr = 0;
    cli->peer_ns = 0;
    cli->source_tunnel_id = 0;
    cli->remote_tunnel_id = 0;
    cli->source_session_id = 0;
    cli->remote_session_id = 0;

    lcp_wo->mru = cli->mtu ? cli->mtu : L2TP_DEFAULT_MTU;
    lcp_wo->neg_asyncmap = 0;
    lcp_wo->neg_pcompression = 0;
    lcp_wo->neg_accompression = 0;
    lcp_wo->passive = 0;
    lcp_wo->silent = 0;

    lcp_ao->mru = cli->mtu ? cli->mtu : L2TP_DEFAULT_MTU;
    lcp_ao->neg_asyncmap = 0;
    lcp_ao->neg_pcompression = 0;
    lcp_ao->neg_accompression = 0;

    /* LCP keepalive: detect silent session loss (LNS down without StopCCN) */
    ppp->settings.lcp_echo_interval = 3;
    ppp->settings.lcp_echo_fails = 3;

    /* Generate random challenge vector for L2TP tunnel authentication */
    if (cli->secret != NULL && cli->secret_len > 0) {
        magic_random_bytes(cli->secret_rv, sizeof(cli->secret_rv));
    }

    do {
        cli->remote_tunnel_id = magic();
    } while (cli->remote_tunnel_id == 0);

    cli->sccrq_retried = 0;
    cli->phase = L2TP_STATE_SCCRQ_SENT;
    if ((err = l2tp_send_sccrq(cli)) != ERR_OK) {
        PPPDEBUG(LOG_DEBUG, ("l2tp: failed to send SCCRQ, error=%d\n", err));
    }
    sys_timeout(L2TP_CONTROL_TIMEOUT, l2tp_timeout, cli);
    sys_timeout(L2TP_TICK_INTERVAL_MS, l2tp_periodic_timer, cli);
}

/* Disconnect */
static void l2tp_disconnect(ppp_pcb *ppp, void *ctx) {
    l2tp_client_t *cli = (l2tp_client_t *)ctx;

    cli->our_ns++;
    l2tp_send_stopccn(cli, cli->our_ns);

    sys_untimeout(l2tp_timeout, cli);
    sys_untimeout(l2tp_periodic_timer, cli);
    cli->phase = L2TP_STATE_INITIAL;
    ppp_link_end(ppp); /* notify upper layers */
}

/* ========== PPP link status ========== */

void l2tp_ppp_status_cb(ppp_pcb *ppp, int err_code, void *ctx) {
    l2tp_client_t *cli = (l2tp_client_t *)ctx;
    LWIP_UNUSED_ARG(ppp);
    if (!cli) return;
    if (cli->status_cb) {
        cli->status_cb(cli, err_code, cli->user_data);
    }
    /* Link lost unexpectedly (auth fail, LCP timeout, peer terminate, ...):
     * tear the session down and schedule an automatic reconnect. */
    if (err_code != 0 /* PPPERR_NONE */ && !cli->user_close && !cli->tearing_down) {
        l2tp_stop_internal(cli);
        l2tp_schedule_retry(cli, "ppp link lost");
    }
}
