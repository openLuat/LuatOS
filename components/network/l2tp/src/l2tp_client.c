/*
 * L2TPv2 (RFC 2661) LAC client core for LuatOS netdrv.
 *
 * Control plane (SCCRQ/SCCRP/SCCCN/ICRQ/ICRP/ICCN/ZLB/StopCCN, ns/nr window,
 * timeout retransmission) is ported from lwIP 2.2.1 netif/ppp/pppol2tp.c
 * (BSD-3-Clause, (c) the lwIP authors), with the UDP transport replaced by
 * the LuatOS network adapter (network_ctrl_t UDP mode).
 *
 * The PPP session runs on the vendored lwIP 2.2.1 PPP stack
 * (components/network/l2tp/src/ppp/).
 *
 * Threading model:
 *   - create/connect/close and ppp_input delivery are marshaled to the lwIP
 *     core thread with tcpip_callback_with_block() (same pattern as the
 *     WireGuard netdrv's exec_netif_add);
 *   - the network adapter callback only copies received bytes and posts them
 *     to the tcpip thread; the PPP state machine never runs on the adapter
 *     thread.
 */

#include "l2tp/l2tp_client.h"
#include "l2tp/l2tp_ctrl.h"
#include "l2tp/l2tp_ppp.h"

#include <string.h>
#include "lwip/def.h"
#include "lwip/mem.h"
#include "lwip/pbuf.h"
#include "lwip/tcpip.h"
#include "lwip/timeouts.h"
#include "lwip/sys.h"
#include "net_lwip2.h"
#include "luat_netdrv.h"
#include "luat_mem.h"

/* Vendored lwIP PPP stack (ppp.c/lcp.c/ipcp.c/auth.c/fsm.c/upap.c/
 * chap-new.c/chap-md5.c/magic.c/utils.c).  Compile with PPP_SUPPORT=1,
 * PAP_SUPPORT=1, CHAP_SUPPORT=1, LWIP_USE_EXTERNAL_MBEDTLS=1, ... */
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

/* Forward declarations (client-local, non-static entries come from
 * l2tp/l2tp_client.h, l2tp/l2tp_ctrl.h and l2tp/l2tp_ppp.h) */
static void l2tp_do_start(void *arg);
static void l2tp_do_stop(void *arg);
static void l2tp_do_rx(void *arg);
static void l2tp_retry_timer(void *arg);
static int  l2tp_transport_is_online(l2tp_client_t *cli);

/* Received datagram (adapter thread -> tcpip thread) */
typedef struct l2tp_rx_msg {
    l2tp_client_t *cli;
    luat_ip_addr_t src_addr;
    uint16_t src_port;
    uint16_t len;
    uint8_t data[4];
} l2tp_rx_msg_t;

/* ========== Low-level helpers ========== */

/* Send a raw UDP packet to the remote LNS */
err_t l2tp_udp_send(l2tp_client_t *cli, const u8_t *data, u16_t len) {
    if (!cli || !cli->netc || !data || len == 0) return ERR_VAL;
    uint32_t tx_len = 0;
    int ret = network_tx(cli->netc, data, len, 0,
                         &cli->remote_ip, cli->tunnel_port, &tx_len, 0);
    return (ret >= 0 && tx_len == len) ? ERR_OK : ERR_IF;
}

/* ========== Timeout / retry ========== */

/* L2TP timeout handler */
void l2tp_timeout(void *arg) {
    l2tp_client_t *cli = (l2tp_client_t *)arg;
    err_t err;
    u32_t retry_wait;

    switch (cli->phase) {
        case L2TP_STATE_SCCRQ_SENT:
            if (cli->sccrq_retried < 0xff) {
                cli->sccrq_retried++;
            }
            if (cli->sccrq_retried >= L2TP_MAXSCCRQ) {
                l2tp_abort_connect(cli);
                return;
            }
            retry_wait = LWIP_MIN(L2TP_CONTROL_TIMEOUT * cli->sccrq_retried, L2TP_SLOW_RETRY);
            if ((err = l2tp_send_sccrq(cli)) != ERR_OK) {
                PPPDEBUG(LOG_DEBUG, ("l2tp: failed to send SCCRQ, error=%d\n", err));
            }
            sys_timeout(retry_wait, l2tp_timeout, cli);
            break;

        case L2TP_STATE_ICRQ_SENT:
            cli->icrq_retried++;
            if (cli->icrq_retried >= L2TP_MAXICRQ) {
                l2tp_abort_connect(cli);
                return;
            }
            if ((s16_t)(cli->peer_nr - cli->our_ns) < 0) { /* the SCCCN was not acknowledged */
                if ((err = l2tp_send_scccn(cli, (u16_t)(cli->our_ns - 1))) != ERR_OK) {
                    PPPDEBUG(LOG_DEBUG, ("l2tp: failed to send SCCCN, error=%d\n", err));
                    sys_timeout(L2TP_CONTROL_TIMEOUT, l2tp_timeout, cli);
                    break;
                }
            }
            if ((err = l2tp_send_icrq(cli, cli->our_ns)) != ERR_OK) {
                PPPDEBUG(LOG_DEBUG, ("l2tp: failed to send ICRQ, error=%d\n", err));
            }
            sys_timeout(L2TP_CONTROL_TIMEOUT, l2tp_timeout, cli);
            break;

        case L2TP_STATE_ICCN_SENT:
            cli->iccn_retried++;
            if (cli->iccn_retried >= L2TP_MAXICCN) {
                l2tp_abort_connect(cli);
                return;
            }
            if ((err = l2tp_send_iccn(cli, cli->our_ns)) != ERR_OK) {
                PPPDEBUG(LOG_DEBUG, ("l2tp: failed to send ICCN, error=%d\n", err));
            }
            sys_timeout(L2TP_CONTROL_TIMEOUT, l2tp_timeout, cli);
            break;

        default:
            return; /* all done, work in peace */
    }
}

/* Connection attempt aborted */
void l2tp_abort_connect(l2tp_client_t *cli) {
    PPPDEBUG(LOG_DEBUG, ("l2tp: could not establish connection\n"));
    cli->phase = L2TP_STATE_INITIAL;
    ppp_link_failed((ppp_pcb *)cli->ppp); /* notify upper layers */
}

/* Periodic tick: transport error handling */
void l2tp_periodic_timer(void *arg) {
    l2tp_client_t *cli = (l2tp_client_t *)arg;
    if (!cli || !cli->started) return;

    if (cli->transport_err) {
        cli->transport_err = 0;
        LLOGW("transport socket error, scheduling retry");
        l2tp_stop_internal(cli);
        l2tp_schedule_retry(cli, "transport error");
        return;
    }

    sys_timeout(L2TP_TICK_INTERVAL_MS, l2tp_periodic_timer, cli);
}

/* ========== Network adapter transport ========== */

static int32_t l2tp_netc_callback(void *pData, void *pParam) {
    OS_EVENT *event = (OS_EVENT *)pData;
    l2tp_client_t *cli = (l2tp_client_t *)pParam;
    if (!event || !cli || !cli->netc) return -1;

    if (event->ID == EV_NW_RESULT_EVENT) {
        uint8_t buf[1600];
        uint32_t rx_len = 0;
        luat_ip_addr_t src_addr;
        uint16_t src_port = 0;
        int ret = network_rx(cli->netc, buf, sizeof(buf), 0,
                             &src_addr, &src_port, &rx_len);
        if (ret == 0 && rx_len > 0) {
            l2tp_rx_msg_t *msg = (l2tp_rx_msg_t *)luat_heap_malloc(sizeof(l2tp_rx_msg_t) + rx_len);
            if (msg == NULL) {
                return 0;
            }
            msg->cli = cli;
            msg->src_addr = src_addr;
            msg->src_port = src_port;
            msg->len = (uint16_t)rx_len;
            memcpy(msg->data, buf, rx_len);
            if (tcpip_callback_with_block(l2tp_do_rx, msg, 0) != ERR_OK) {
                luat_heap_free(msg);
            }
        }
    } else if (event->ID == EV_NW_RESULT_CLOSE || event->Param1 != 0) {
        /* Transport error: socket closed, or Param1 != 0 (general failure) */
        cli->transport_err = 1;
    }
    return 0;
}

/* Received datagram processed on the tcpip thread */
static void l2tp_do_rx(void *arg) {
    l2tp_rx_msg_t *msg = (l2tp_rx_msg_t *)arg;
    if (msg && msg->cli) {
        l2tp_client_t *cli = msg->cli;
        if (cli->started) {
            l2tp_input_packet(cli, msg->data, msg->len,
                              (ip_addr_t *)&msg->src_addr, msg->src_port);
        }
    }
    luat_heap_free(msg);
}

/**
 * Check whether at least one non-L2TP transport adapter is online.
 * First checks netdrv layer, then falls back to network adapter layer.
 */
static int l2tp_transport_is_online(l2tp_client_t *cli) {
    int i;
    for (i = 0; i < NW_ADAPTER_QTY; i++) {
        if (i == cli->adapter_index) continue; /* skip our own virtual tun */
        if (luat_netdrv_is_ready(i)) return 1;
    }
    /* The configured transport adapter (captured at setup) */
    if (cli->transport_index < NW_ADAPTER_QTY
        && cli->transport_index != cli->adapter_index) {
        if (network_check_ready(NULL, cli->transport_index)) return 1;
    }
    /* Fallback: last/default adapter */
    int dft = network_register_get_default();
    if (dft >= 0 && dft != cli->adapter_index) {
        if (network_check_ready(NULL, (uint8_t)dft)) return 1;
    }
    return 0;
}

static uint32_t l2tp_next_backoff_ms(l2tp_client_t *cli) {
    uint32_t base = cli->retry_base_ms ? cli->retry_base_ms : 1000;
    uint32_t max = cli->retry_max_ms ? cli->retry_max_ms : 60000;
    uint32_t delay;
    if (max < base) max = base;
    if (cli->retry_attempt >= 31) return max;
    delay = base << cli->retry_attempt;
    if (delay < base) return max;
    return delay > max ? max : delay;
}

void l2tp_schedule_retry(l2tp_client_t *cli, const char *reason) {
    uint32_t delay;
    if (!cli || !cli->retry_enable || cli->retry_timer_active || cli->user_close) return;
    delay = l2tp_next_backoff_ms(cli);
    if (!l2tp_transport_is_online(cli)) {
        delay = cli->retry_base_ms ? cli->retry_base_ms : 1000;
        LLOGD("transport offline, waiting %u ms before next retry", (unsigned)delay);
    }
    cli->retry_timer_active = 1;
    cli->retry_attempt++;
    LLOGW("schedule retry in %u ms (%s)", (unsigned)delay, reason ? reason : "unknown");
    sys_timeout(delay, l2tp_retry_timer, cli);
}

static void l2tp_retry_timer(void *arg) {
    l2tp_client_t *cli = (l2tp_client_t *)arg;
    if (!cli) return;
    cli->retry_timer_active = 0;
    if (cli->started) return;
    l2tp_client_start(cli);
}

/* ========== Lifecycle ========== */

static int l2tp_start_internal(l2tp_client_t *cli) {
    ppp_pcb *ppp;
    err_t err;

    /* If a previous session is still terminating, wait for it to settle */
    if (cli->ppp) {
        ppp = (ppp_pcb *)cli->ppp;
        if (ppp->phase != PPP_PHASE_DEAD) {
            ppp_close(ppp, 1);
        }
        if (ppp->phase == PPP_PHASE_DEAD) {
            ppp_free(ppp);
            cli->ppp = NULL;
        } else {
            LLOGE("previous PPP session not terminated");
            return -7;
        }
    }

    /* Check transport availability before allocating resources */
    if (!l2tp_transport_is_online(cli)) {
        LLOGW("transport offline, deferring start");
        return -6;
    }

    /* Allocate & init network controller via luat_network_adapter */
    cli->netc = network_alloc_ctrl(cli->transport_index);
    if (!cli->netc) {
        LLOGE("netc alloc fail");
        return -3;
    }
    network_init_ctrl(cli->netc, NULL, l2tp_netc_callback, cli);
    network_set_base_mode(cli->netc, 0, 10000, 0, 0, 0, 0); /* UDP mode */
    network_set_local_port(cli->netc, 0);
    err = network_connect(cli->netc, NULL, 0, &cli->remote_ip, cli->remote_port, 0);
    if (err < 0) {
        LLOGE("netc connect fail");
        network_force_close_socket(cli->netc);
        network_release_ctrl(cli->netc);
        cli->netc = NULL;
        return -4;
    }
    /* UDP: socket created, set ONLINE immediately (async connect is a no-op in ONLINE state) */
    cli->netc->state = NW_STATE_ONLINE;

    /* Reset L2TP state */
    cli->phase = L2TP_STATE_INITIAL;
    cli->tunnel_port = cli->remote_port;
    cli->our_ns = 0;
    cli->peer_nr = 0;
    cli->peer_ns = 0;
    cli->source_tunnel_id = 0;
    cli->remote_tunnel_id = 0;
    cli->source_session_id = 0;
    cli->remote_session_id = 0;
    cli->send_challenge = 0;
    cli->transport_err = 0;

    /* Create PPP session (netif_add happens inside ppp_new) */
    ppp = ppp_new(&cli->netif, &l2tp_callbacks, cli, l2tp_ppp_status_cb, cli);
    if (ppp == NULL) {
        LLOGE("ppp_new failed");
        network_force_close_socket(cli->netc);
        network_release_ctrl(cli->netc);
        cli->netc = NULL;
        return -5;
    }
    cli->ppp = ppp;

    /* Register the virtual netif with the lwip2 adapter */
    if (cli->adapter_index >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) {
        cli->adapter_index = NW_ADAPTER_INDEX_LWIP_USER0;
    }
    net_lwip2_set_netif(cli->adapter_index, &cli->netif);
    net_lwip2_register_adapter(cli->adapter_index);

    /* Authentication (PAP + CHAP-MD5) */
    if (cli->username && cli->username_len > 0) {
        ppp_set_auth(ppp, PPPAUTHTYPE_ANY, cli->username, cli->password ? cli->password : "");
    }

    /* Use the PPP interface as the default route */
    ppp_set_default(ppp);

    /* Start LCP, which triggers l2tp_connect() -> SCCRQ */
    err = ppp_connect(ppp, 0);
    if (err != ERR_OK) {
        LLOGE("ppp_connect failed: %d", err);
        return -8;
    }

    cli->started = 1;
    cli->retry_attempt = 0;
    cli->user_close = 0;
    LLOGI("L2TP client started, waiting for LNS %s:%d ...",
          ipaddr_ntoa(&cli->remote_ip), cli->remote_port);
    return 0;
}

static void l2tp_do_start(void *arg) {
    l2tp_client_t *cli = (l2tp_client_t *)arg;
    int ret = l2tp_start_internal(cli);
    if (ret != 0) {
        LLOGE("l2tp start internal failed: %d", ret);
        l2tp_stop_internal(cli);
        l2tp_schedule_retry(cli, "start failed");
    }
}

int l2tp_client_start(l2tp_client_t *cli) {
    err_t err;
    if (!cli) return -1;
    if (cli->started) return 0;
    if (cli->retry_timer_active) return -2;
    if (ip_addr_isany(&cli->remote_ip)) {
        LLOGE("l2tp remote ip missing");
        return -3;
    }
    if (!cli->ppp_inited) {
        ppp_init();
        cli->ppp_inited = 1;
    }

    /* Marshal setup to the lwIP core thread (same as WG exec_netif_add) */
    cli->started = 1;
    err = tcpip_callback_with_block(l2tp_do_start, cli, 0);
    if (err != ERR_OK) {
        cli->started = 0;
        LLOGE("tcpip callback fail: %d", err);
        return -5;
    }
    return 0;
}

void l2tp_stop_internal(l2tp_client_t *cli) {
    if (!cli) return;
    cli->tearing_down = 1;

    if (cli->netc) {
        network_ctrl_t *netc = cli->netc;
        cli->netc = NULL;
        network_close(netc, 0);
        network_force_close_socket(netc);
        network_release_ctrl(netc);
    }
    sys_untimeout(l2tp_timeout, cli);
    sys_untimeout(l2tp_periodic_timer, cli);
    sys_untimeout(l2tp_retry_timer, cli);
    cli->retry_timer_active = 0;

    if (cli->ppp) {
        ppp_pcb *ppp = (ppp_pcb *)cli->ppp;
        if (ppp->phase != PPP_PHASE_DEAD) {
            ppp_close(ppp, 1);
        }
        if (ppp->phase == PPP_PHASE_DEAD) {
            ppp_free(ppp);
            cli->ppp = NULL;
        }
    }

    cli->phase = L2TP_STATE_INITIAL;
    cli->started = 0;
    cli->tearing_down = 0;
}

static void l2tp_do_stop(void *arg) {
    l2tp_client_t *cli = (l2tp_client_t *)arg;
    if (!cli) return;
    l2tp_stop_internal(cli);
    cli->user_close = 0;
}

void l2tp_client_stop(l2tp_client_t *cli) {
    if (!cli) return;
    cli->user_close = 1;
    tcpip_callback_with_block(l2tp_do_stop, cli, 0);
}

/* ========== Public API ========== */

int l2tp_client_init(l2tp_client_t *cli, const l2tp_client_cfg_t *cfg) {
    char *copy;

    if (!cli || !cfg) return -1;
    memset(cli, 0, sizeof(l2tp_client_t));

    cli->remote_ip = cfg->remote_ip;
    cli->remote_port = cfg->remote_port ? cfg->remote_port : L2TP_DEFAULT_PORT;
    cli->mtu = cfg->mtu ? cfg->mtu : L2TP_DEFAULT_MTU;
    cli->adapter_index = cfg->adapter_index;
    cli->transport_index = cfg->transport_index;
    cli->retry_enable = cfg->retry_enable;
    cli->retry_base_ms = cfg->retry_base_ms;
    cli->retry_max_ms = cfg->retry_max_ms;
    cli->status_cb = cfg->status_cb;
    cli->user_data = cfg->user_data;

    /* Copy strings to client-owned heap memory (Lua strings die after setup) */
    if (cfg->username && cfg->username_len > 0) {
        copy = (char *)luat_heap_malloc(cfg->username_len + 1);
        if (!copy) goto nomem;
        memcpy(copy, cfg->username, cfg->username_len);
        copy[cfg->username_len] = '\0';
        cli->username = copy;
        cli->username_len = cfg->username_len;
    }
    if (cfg->password && cfg->password_len > 0) {
        copy = (char *)luat_heap_malloc(cfg->password_len + 1);
        if (!copy) goto nomem;
        memcpy(copy, cfg->password, cfg->password_len);
        copy[cfg->password_len] = '\0';
        cli->password = copy;
        cli->password_len = cfg->password_len;
    }
    if (cfg->secret && cfg->secret_len > 0) {
        copy = (char *)luat_heap_malloc(cfg->secret_len + 1);
        if (!copy) goto nomem;
        memcpy(copy, cfg->secret, cfg->secret_len);
        copy[cfg->secret_len] = '\0';
        cli->secret = copy;
        cli->secret_len = cfg->secret_len;
    }
    return 0;

nomem:
    if (cli->username) { luat_heap_free(cli->username); cli->username = NULL; }
    if (cli->password) { luat_heap_free(cli->password); cli->password = NULL; }
    if (cli->secret) { luat_heap_free(cli->secret); cli->secret = NULL; }
    return -2;
}

void l2tp_client_set_debug(l2tp_client_t *cli, int enable) {
    if (!cli) return;
    cli->debug = enable ? 1 : 0;
}

int l2tp_client_is_ready(l2tp_client_t *cli) {
    ppp_pcb *ppp;
    if (!cli) return 0;
    if (!cli->started) return 0;
    ppp = (ppp_pcb *)cli->ppp;
    if (!ppp) return 0;
    /* sifup() calls the link status callback with PPPERR_NONE before
     * np_up() advances the phase to RUNNING, so use if4_up as the signal. */
    return ppp->if4_up ? 1 : 0;
}
