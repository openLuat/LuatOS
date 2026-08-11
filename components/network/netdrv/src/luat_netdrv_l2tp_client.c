/*
 * L2TPv2 (RFC 2661) LAC client core for LuatOS netdrv.
 *
 * Control plane (SCCRQ/SCCRP/SCCCN/ICRQ/ICRP/ICCN/ZLB/StopCCN, ns/nr window,
 * timeout retransmission) is ported from lwIP 2.2.1 netif/ppp/pppol2tp.c
 * (BSD-3-Clause, (c) the lwIP authors), with the UDP transport replaced by
 * the LuatOS network adapter (network_ctrl_t UDP mode).
 *
 * The PPP session runs on the vendored lwIP 2.2.1 PPP stack
 * (components/network/netdrv/src/ppp/).
 *
 * Threading model:
 *   - create/connect/close and ppp_input delivery are marshaled to the lwIP
 *     core thread with tcpip_callback_with_block() (same pattern as the
 *     WireGuard netdrv's exec_netif_add);
 *   - the network adapter callback only copies received bytes and posts them
 *     to the tcpip thread; the PPP state machine never runs on the adapter
 *     thread.
 */

#include "luat_netdrv_l2tp_client.h"

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

/* Forward declarations */
static void l2tp_connect(ppp_pcb *ppp, void *ctx);
static void l2tp_disconnect(ppp_pcb *ppp, void *ctx);
static err_t l2tp_destroy(ppp_pcb *ppp, void *ctx);
static err_t l2tp_write(ppp_pcb *ppp, void *ctx, struct pbuf *p);
static err_t l2tp_netif_output(ppp_pcb *ppp, void *ctx, struct pbuf *p, u_short protocol);

static void l2tp_timeout(void *arg);
static void l2tp_periodic_timer(void *arg);
static void l2tp_abort_connect(l2tp_client_t *cli);
static err_t l2tp_send_sccrq(l2tp_client_t *cli);
static err_t l2tp_send_scccn(l2tp_client_t *cli, u16_t ns);
static err_t l2tp_send_icrq(l2tp_client_t *cli, u16_t ns);
static err_t l2tp_send_iccn(l2tp_client_t *cli, u16_t ns);
static err_t l2tp_send_zlb(l2tp_client_t *cli, u16_t ns, u16_t nr);
static err_t l2tp_send_stopccn(l2tp_client_t *cli, u16_t ns);
static err_t l2tp_data_send(l2tp_client_t *cli, struct pbuf *p, u16_t skip, u8_t add_proto, u16_t protocol);
static err_t l2tp_udp_send(l2tp_client_t *cli, const u8_t *data, u16_t len);
static void l2tp_input_packet(l2tp_client_t *cli, const u8_t *data, u16_t datalen,
                              ip_addr_t *addr, u16_t port);
static void l2tp_dispatch_control_packet(l2tp_client_t *cli, u16_t port,
                                         const u8_t *inp, u16_t len, u16_t ns, u16_t nr);
static void l2tp_do_start(void *arg);
static void l2tp_do_stop(void *arg);
static void l2tp_do_rx(void *arg);
static void l2tp_stop_internal(l2tp_client_t *cli);
static void l2tp_schedule_retry(l2tp_client_t *cli, const char *reason);
static void l2tp_retry_timer(void *arg);
static int  l2tp_transport_is_online(l2tp_client_t *cli);

/* PPP core callbacks */
static const struct link_callbacks l2tp_callbacks = {
    l2tp_connect,
    l2tp_disconnect,
    l2tp_destroy,
    l2tp_write,
    l2tp_netif_output,
    NULL, /* send_config */
    NULL  /* recv_config */
};

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
static err_t l2tp_udp_send(l2tp_client_t *cli, const u8_t *data, u16_t len) {
    if (!cli || !cli->netc || !data || len == 0) return ERR_VAL;
    uint32_t tx_len = 0;
    int ret = network_tx(cli->netc, data, len, 0,
                         &cli->remote_ip, cli->tunnel_port, &tx_len, 0);
    return (ret >= 0 && tx_len == len) ? ERR_OK : ERR_IF;
}

/* Build and send one L2TP data packet from a pbuf.
 * skip: number of leading bytes to drop from the pbuf (HDLC address/control).
 * add_proto: prepend a 2-byte PPP protocol field (netif output path). */
static err_t l2tp_data_send(l2tp_client_t *cli, struct pbuf *p, u16_t skip,
                            u8_t add_proto, u16_t protocol) {
    u8_t buf[1600];
    u8_t *q = buf;
    u16_t pay_len;
    u16_t total;
    uint32_t tx_len = 0;
    int ret;

    if (!cli || !cli->netc || !p) return ERR_VAL;
    if (cli->phase != L2TP_STATE_DATA) return ERR_VAL;
    if (p->tot_len <= skip) return ERR_BUF;
    pay_len = (u16_t)(p->tot_len - skip);
    total = L2TP_OUTPUT_DATA_HEADER_LEN + (add_proto ? 2 : 0) + pay_len;
    if (total > sizeof(buf)) return ERR_BUF;

    PUTSHORT(L2TP_HEADERFLAG_DATA_MANDATORY, q);
    PUTSHORT(cli->source_tunnel_id, q);
    PUTSHORT(cli->source_session_id, q);
    if (add_proto) {
        PUTSHORT(protocol, q);
    }
    pbuf_copy_partial(p, q, pay_len, skip);

    ret = network_tx(cli->netc, buf, total, 0,
                     &cli->remote_ip, cli->tunnel_port, &tx_len, 0);
    return (ret >= 0 && tx_len == total) ? ERR_OK : ERR_IF;
}

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

/* ========== Incoming packet processing ========== */

static void l2tp_input_packet(l2tp_client_t *cli, const u8_t *data, u16_t datalen,
                              ip_addr_t *addr, u16_t port) {
    u16_t hflags, hlen, len = 0, tunnel_id = 0, session_id = 0, ns = 0, nr = 0, offset = 0;
    const u8_t *inp;
    const u8_t *payload;
    u16_t payload_len;

    if (!cli || !data || datalen == 0) return;

    /* we can still receive UDP frames after the link is closed */
    if (cli->phase < L2TP_STATE_SCCRQ_SENT) {
        return;
    }
    if (!ip_addr_eq(&cli->remote_ip, addr)) {
        return;
    }
    /* discard packet if port mismatch, but only if we received a SCCRP */
    if (cli->phase > L2TP_STATE_SCCRQ_SENT && cli->tunnel_port != port) {
        return;
    }

    /* L2TP header */
    if (datalen < 6) {
        return;
    }
    inp = data;
    GETSHORT(hflags, inp);

    if (hflags & L2TP_HEADERFLAG_CONTROL) {
        if ((hflags & L2TP_HEADERFLAG_CONTROL_MANDATORY) != L2TP_HEADERFLAG_CONTROL_MANDATORY) {
            PPPDEBUG(LOG_DEBUG, ("l2tp: mandatory header flags for control packet not set\n"));
            return;
        }
        if (hflags & L2TP_HEADERFLAG_CONTROL_FORBIDDEN) {
            PPPDEBUG(LOG_DEBUG, ("l2tp: forbidden header flags for control packet found\n"));
            return;
        }
    } else {
        if ((hflags & L2TP_HEADERFLAG_DATA_MANDATORY) != L2TP_HEADERFLAG_DATA_MANDATORY) {
            PPPDEBUG(LOG_DEBUG, ("l2tp: mandatory header flags for data packet not set\n"));
            return;
        }
    }

    /* Expected header size */
    hlen = 6;
    if (hflags & L2TP_HEADERFLAG_LENGTH) {
        hlen += 2;
    }
    if (hflags & L2TP_HEADERFLAG_SEQUENCE) {
        hlen += 4;
    }
    if (hflags & L2TP_HEADERFLAG_OFFSET) {
        hlen += 2;
    }
    if (datalen < hlen) {
        return;
    }

    if (hflags & L2TP_HEADERFLAG_LENGTH) {
        GETSHORT(len, inp);
        if (datalen < len || len < hlen) {
            return;
        }
    }
    GETSHORT(tunnel_id, inp);
    GETSHORT(session_id, inp);
    if (hflags & L2TP_HEADERFLAG_SEQUENCE) {
        GETSHORT(ns, inp);
        GETSHORT(nr, inp);
    }
    if (hflags & L2TP_HEADERFLAG_OFFSET) {
        GETSHORT(offset, inp);
        if (offset > 4096) { /* don't be fooled with large offset which might overflow hlen */
            PPPDEBUG(LOG_DEBUG, ("l2tp: strange packet received, offset=%d\n", offset));
            return;
        }
        hlen += offset;
        if (datalen < hlen) {
            return;
        }
        inp += offset;
    }

    payload = data + hlen;
    payload_len = (u16_t)(datalen - hlen);

    /* Control packet */
    if (hflags & L2TP_HEADERFLAG_CONTROL) {
        l2tp_dispatch_control_packet(cli, port, payload, payload_len, ns, nr);
        return;
    }

    /* Data packet */
    if (cli->phase != L2TP_STATE_DATA) {
        return;
    }
    if (tunnel_id != cli->remote_tunnel_id) {
        PPPDEBUG(LOG_DEBUG, ("l2tp: tunnel ID mismatch, assigned=%d, received=%d\n",
                             cli->remote_tunnel_id, tunnel_id));
        return;
    }
    if (session_id != cli->remote_session_id) {
        PPPDEBUG(LOG_DEBUG, ("l2tp: session ID mismatch, assigned=%d, received=%d\n",
                             cli->remote_session_id, session_id));
        return;
    }

    /*
     * Skip address & flags if present (RFC 2661 does not specify whether the
     * PPP frame carries the HDLC header; both behaviors are seen in the wild).
     */
    if (payload_len >= 2 && payload[0] == 0xff && payload[1] == 0x03) {
        payload += 2;
        payload_len -= 2;
    }
    if (payload_len == 0 || cli->ppp == NULL) {
        return;
    }

    struct pbuf *pb = pbuf_alloc(PBUF_RAW, payload_len, PBUF_RAM);
    if (pb == NULL) {
        return;
    }
    pbuf_take(pb, payload, payload_len);
    ppp_input((ppp_pcb *)cli->ppp, pb);
}

/* L2TP control packet entry point */
static void l2tp_dispatch_control_packet(l2tp_client_t *cli, u16_t port,
                                         const u8_t *inp, u16_t len, u16_t ns, u16_t nr) {
    u16_t avplen, avpflags, vendorid, attributetype, messagetype = 0;
    err_t err;
    const u8_t *end = inp + len;
#if L2TP_AVPTYPE_CHALLENGERESPONSE_SIZE
    lwip_md5_context md5_ctx;
    u8_t md5_hash[16];
    u8_t challenge_id = 0;
#endif

    /* Drop unexpected packet */
    if (ns != cli->peer_ns) {
        PPPDEBUG(LOG_DEBUG, ("l2tp: drop unexpected packet: received NS=%d, expected NS=%d\n",
                             ns, cli->peer_ns));
        /*
         * In order to ensure that all messages are acknowledged properly
         * (particularly in the case of a lost ZLB ACK message), receipt
         * of duplicate messages MUST be acknowledged.
         */
        if ((s16_t)(ns - cli->peer_ns) < 0) {
            l2tp_send_zlb(cli, nr, (u16_t)(ns + 1));
        }
        return;
    }

    cli->peer_nr = nr;

    /* Handle the special case of the ICCN acknowledge */
    if (cli->phase == L2TP_STATE_ICCN_SENT && (s16_t)(cli->peer_nr - cli->our_ns) > 0) {
        cli->phase = L2TP_STATE_DATA;
        sys_untimeout(l2tp_timeout, cli);
        ppp_start((ppp_pcb *)cli->ppp); /* notify upper layers */
    }

    /* ZLB packets */
    if (len == 0) {
        return;
    }
    /* A ZLB packet does not consume a NS slot thus we don't record the NS value for ZLB packets */
    cli->peer_ns = (u16_t)(ns + 1);

    /* Decode AVPs */
    while (inp < end) {
        if ((size_t)(end - inp) < 6) {
            goto packet_too_short;
        }
        GETSHORT(avpflags, inp);
        avplen = avpflags & L2TP_AVPHEADERFLAG_LENGTHMASK;
        if (avplen < 6 || (size_t)(end - inp) < (size_t)(avplen - 6)) {
            goto packet_too_short;
        }
        GETSHORT(vendorid, inp);
        GETSHORT(attributetype, inp);
        avplen -= 6;

        /* Message type must be the first AVP */
        if (messagetype == 0) {
            if (attributetype != 0 || vendorid != 0 || avplen != 2) {
                PPPDEBUG(LOG_DEBUG, ("l2tp: message type must be the first AVP\n"));
                return;
            }
            GETSHORT(messagetype, inp);
            switch (messagetype) {
                /* Start Control Connection Reply */
                case L2TP_MESSAGETYPE_SCCRP:
                    if (cli->phase != L2TP_STATE_SCCRQ_SENT) {
                        goto send_zlb;
                    }
                    break;
                /* Incoming Call Reply */
                case L2TP_MESSAGETYPE_ICRP:
                    if (cli->phase != L2TP_STATE_ICRQ_SENT) {
                        goto send_zlb;
                    }
                    break;
                /* Stop Control Connection Notification */
                case L2TP_MESSAGETYPE_STOPCCN:
                    l2tp_send_zlb(cli, (u16_t)(cli->our_ns + 1), cli->peer_ns);
                    if (cli->phase < L2TP_STATE_DATA) {
                        l2tp_abort_connect(cli);
                    } else if (cli->phase == L2TP_STATE_DATA) {
                        /* Don't disconnect here, we let the LCP Echo/Reply find
                         * the fact that PPP session is down. */
                    }
                    return;
                default:
                    break;
            }
            goto nextavp;
        }

        /* Skip proprietary L2TP extensions */
        if (vendorid != 0) {
            goto skipavp;
        }

        switch (messagetype) {
            /* Start Control Connection Reply */
            case L2TP_MESSAGETYPE_SCCRP:
                switch (attributetype) {
                    case L2TP_AVPTYPE_TUNNELID:
                        if (avplen != 2) {
                            PPPDEBUG(LOG_DEBUG, ("l2tp: AVP Assign tunnel ID length check failed\n"));
                            return;
                        }
                        GETSHORT(cli->source_tunnel_id, inp);
                        PPPDEBUG(LOG_DEBUG, ("l2tp: Assigned tunnel ID %"U16_F"\n", cli->source_tunnel_id));
                        goto nextavp;
                    case L2TP_AVPTYPE_CHALLENGE:
                        if (avplen == 0) {
                            PPPDEBUG(LOG_DEBUG, ("l2tp: Challenge length check failed\n"));
                            return;
                        }
                        if (cli->secret == NULL) {
                            PPPDEBUG(LOG_DEBUG, ("l2tp: Received challenge from peer and no secret key available\n"));
                            l2tp_abort_connect(cli);
                            return;
                        }
                        /* Generate hash of ID, secret, challenge */
                        lwip_md5_init(&md5_ctx);
                        lwip_md5_starts(&md5_ctx);
                        challenge_id = L2TP_MESSAGETYPE_SCCCN;
                        lwip_md5_update(&md5_ctx, &challenge_id, 1);
                        lwip_md5_update(&md5_ctx, (const u8_t *)cli->secret, cli->secret_len);
                        lwip_md5_update(&md5_ctx, inp, avplen);
                        lwip_md5_finish(&md5_ctx, cli->challenge_hash);
                        lwip_md5_free(&md5_ctx);
                        cli->send_challenge = 1;
                        goto skipavp;
                    case L2TP_AVPTYPE_CHALLENGERESPONSE:
                        if (avplen != L2TP_AVPTYPE_CHALLENGERESPONSE_SIZE) {
                            PPPDEBUG(LOG_DEBUG, ("l2tp: AVP Challenge Response length check failed\n"));
                            return;
                        }
                        /* Generate hash of ID, secret, challenge */
                        lwip_md5_init(&md5_ctx);
                        lwip_md5_starts(&md5_ctx);
                        challenge_id = L2TP_MESSAGETYPE_SCCRP;
                        lwip_md5_update(&md5_ctx, &challenge_id, 1);
                        lwip_md5_update(&md5_ctx, (const u8_t *)cli->secret, cli->secret_len);
                        lwip_md5_update(&md5_ctx, cli->secret_rv, sizeof(cli->secret_rv));
                        lwip_md5_finish(&md5_ctx, md5_hash);
                        lwip_md5_free(&md5_ctx);
                        if (memcmp(inp, md5_hash, sizeof(md5_hash)) != 0) {
                            PPPDEBUG(LOG_DEBUG, ("l2tp: Received challenge response from peer and secret key do not match\n"));
                            l2tp_abort_connect(cli);
                            return;
                        }
                        goto skipavp;
                    default:
                        break;
                }
                break;
            /* Incoming Call Reply */
            case L2TP_MESSAGETYPE_ICRP:
                switch (attributetype) {
                    case L2TP_AVPTYPE_SESSIONID:
                        if (avplen != 2) {
                            PPPDEBUG(LOG_DEBUG, ("l2tp: AVP Assign session ID length check failed\n"));
                            return;
                        }
                        GETSHORT(cli->source_session_id, inp);
                        PPPDEBUG(LOG_DEBUG, ("l2tp: Assigned session ID %"U16_F"\n", cli->source_session_id));
                        goto nextavp;
                    default:
                        break;
                }
                break;
            default:
                break;
        }

skipavp:
        inp += avplen;
nextavp:
        /* next AVP */
        continue;
    }

    switch (messagetype) {
        /* Start Control Connection Reply */
        case L2TP_MESSAGETYPE_SCCRP:
            do {
                cli->remote_session_id = magic();
            } while (cli->remote_session_id == 0);
            cli->tunnel_port = port; /* LNS server might have chosen its own local port */
            cli->icrq_retried = 0;
            cli->phase = L2TP_STATE_ICRQ_SENT;
            cli->our_ns++;
            if ((err = l2tp_send_scccn(cli, cli->our_ns)) != ERR_OK) {
                PPPDEBUG(LOG_DEBUG, ("l2tp: failed to send SCCCN, error=%d\n", err));
            }
            cli->our_ns++;
            if ((err = l2tp_send_icrq(cli, cli->our_ns)) != ERR_OK) {
                PPPDEBUG(LOG_DEBUG, ("l2tp: failed to send ICRQ, error=%d\n", err));
            }
            sys_untimeout(l2tp_timeout, cli);
            sys_timeout(L2TP_CONTROL_TIMEOUT, l2tp_timeout, cli);
            break;
        /* Incoming Call Reply */
        case L2TP_MESSAGETYPE_ICRP:
            cli->iccn_retried = 0;
            cli->phase = L2TP_STATE_ICCN_SENT;
            cli->our_ns++;
            if ((err = l2tp_send_iccn(cli, cli->our_ns)) != ERR_OK) {
                PPPDEBUG(LOG_DEBUG, ("l2tp: failed to send ICCN, error=%d\n", err));
            }
            sys_untimeout(l2tp_timeout, cli);
            sys_timeout(L2TP_CONTROL_TIMEOUT, l2tp_timeout, cli);
            break;
        /* Unhandled packet, send ZLB ACK */
        default:
            goto send_zlb;
    }
    return;

send_zlb:
    l2tp_send_zlb(cli, (u16_t)(cli->our_ns + 1), cli->peer_ns);
    return;
packet_too_short:
    PPPDEBUG(LOG_DEBUG, ("l2tp: packet too short\n"));
}

/* ========== Control packet builders ========== */

static err_t l2tp_send_sccrq(l2tp_client_t *cli) {
    u8_t buf[160];
    u8_t *p = buf;
    u16_t len;

    /* calculate UDP packet length */
    len = 12 + 8 + 8 + 10 + 10 + 6 + (u16_t)sizeof(L2TP_HOSTNAME) - 1 +
          6 + (u16_t)sizeof(L2TP_VENDORNAME) - 1 + 8 + 8;
    if (cli->secret != NULL && cli->secret_len > 0) {
        len += 6 + (u16_t)sizeof(cli->secret_rv);
    }
    if (len > sizeof(buf)) {
        return ERR_BUF;
    }

    /* L2TP control header */
    PUTSHORT(L2TP_HEADERFLAG_CONTROL_MANDATORY, p);
    PUTSHORT(len, p);            /* Length */
    PUTSHORT(0, p);              /* Tunnel Id */
    PUTSHORT(0, p);              /* Session Id */
    PUTSHORT(0, p);              /* NS */
    PUTSHORT(0, p);              /* NR */

    /* AVP - Message type */
    PUTSHORT(L2TP_AVPHEADERFLAG_MANDATORY + 8, p);
    PUTSHORT(0, p);
    PUTSHORT(L2TP_AVPTYPE_MESSAGE, p);
    PUTSHORT(L2TP_MESSAGETYPE_SCCRQ, p);

    /* AVP - L2TP version */
    PUTSHORT(L2TP_AVPHEADERFLAG_MANDATORY + 8, p);
    PUTSHORT(0, p);
    PUTSHORT(L2TP_AVPTYPE_VERSION, p);
    PUTSHORT(L2TP_VERSION, p);

    /* AVP - Framing capabilities */
    PUTSHORT(L2TP_AVPHEADERFLAG_MANDATORY + 10, p);
    PUTSHORT(0, p);
    PUTSHORT(L2TP_AVPTYPE_FRAMINGCAPABILITIES, p);
    PUTLONG(L2TP_FRAMINGCAPABILITIES, p);

    /* AVP - Bearer capabilities */
    PUTSHORT(L2TP_AVPHEADERFLAG_MANDATORY + 10, p);
    PUTSHORT(0, p);
    PUTSHORT(L2TP_AVPTYPE_BEARERCAPABILITIES, p);
    PUTLONG(L2TP_BEARERCAPABILITIES, p);

    /* AVP - Host name */
    PUTSHORT(L2TP_AVPHEADERFLAG_MANDATORY + 6 + (u16_t)sizeof(L2TP_HOSTNAME) - 1, p);
    PUTSHORT(0, p);
    PUTSHORT(L2TP_AVPTYPE_HOSTNAME, p);
    memcpy(p, L2TP_HOSTNAME, sizeof(L2TP_HOSTNAME) - 1);
    p += sizeof(L2TP_HOSTNAME) - 1;

    /* AVP - Vendor name */
    PUTSHORT(6 + (u16_t)sizeof(L2TP_VENDORNAME) - 1, p);
    PUTSHORT(0, p);
    PUTSHORT(L2TP_AVPTYPE_VENDORNAME, p);
    memcpy(p, L2TP_VENDORNAME, sizeof(L2TP_VENDORNAME) - 1);
    p += sizeof(L2TP_VENDORNAME) - 1;

    /* AVP - Assign tunnel ID */
    PUTSHORT(L2TP_AVPHEADERFLAG_MANDATORY + 8, p);
    PUTSHORT(0, p);
    PUTSHORT(L2TP_AVPTYPE_TUNNELID, p);
    PUTSHORT(cli->remote_tunnel_id, p);

    /* AVP - Receive window size */
    PUTSHORT(L2TP_AVPHEADERFLAG_MANDATORY + 8, p);
    PUTSHORT(0, p);
    PUTSHORT(L2TP_AVPTYPE_RECEIVEWINDOWSIZE, p);
    PUTSHORT(L2TP_RECEIVEWINDOWSIZE, p);

    /* AVP - Challenge */
    if (cli->secret != NULL && cli->secret_len > 0) {
        PUTSHORT(L2TP_AVPHEADERFLAG_MANDATORY + 6 + (u16_t)sizeof(cli->secret_rv), p);
        PUTSHORT(0, p);
        PUTSHORT(L2TP_AVPTYPE_CHALLENGE, p);
        memcpy(p, cli->secret_rv, sizeof(cli->secret_rv));
        p += sizeof(cli->secret_rv);
    }

    return l2tp_udp_send(cli, buf, len);
}

/* Complete tunnel establishment */
static err_t l2tp_send_scccn(l2tp_client_t *cli, u16_t ns) {
    u8_t buf[64];
    u8_t *p = buf;
    u16_t len = 12 + 8;
    if (cli->send_challenge) {
        len += 6 + (u16_t)sizeof(cli->challenge_hash);
    }
    if (len > sizeof(buf)) {
        return ERR_BUF;
    }

    /* L2TP control header */
    PUTSHORT(L2TP_HEADERFLAG_CONTROL_MANDATORY, p);
    PUTSHORT(len, p);
    PUTSHORT(cli->source_tunnel_id, p);
    PUTSHORT(0, p);
    PUTSHORT(ns, p);
    PUTSHORT(cli->peer_ns, p);

    /* AVP - Message type */
    PUTSHORT(L2TP_AVPHEADERFLAG_MANDATORY + 8, p);
    PUTSHORT(0, p);
    PUTSHORT(L2TP_AVPTYPE_MESSAGE, p);
    PUTSHORT(L2TP_MESSAGETYPE_SCCCN, p);

    /* AVP - Challenge response */
    if (cli->send_challenge) {
        PUTSHORT(L2TP_AVPHEADERFLAG_MANDATORY + 6 + (u16_t)sizeof(cli->challenge_hash), p);
        PUTSHORT(0, p);
        PUTSHORT(L2TP_AVPTYPE_CHALLENGERESPONSE, p);
        memcpy(p, cli->challenge_hash, sizeof(cli->challenge_hash));
        p += sizeof(cli->challenge_hash);
    }

    return l2tp_udp_send(cli, buf, len);
}

/* Initiate a new session */
static err_t l2tp_send_icrq(l2tp_client_t *cli, u16_t ns) {
    u8_t buf[64];
    u8_t *p = buf;
    u16_t len = 12 + 8 + 8 + 10;
    u32_t serialnumber;

    /* L2TP control header */
    PUTSHORT(L2TP_HEADERFLAG_CONTROL_MANDATORY, p);
    PUTSHORT(len, p);
    PUTSHORT(cli->source_tunnel_id, p);
    PUTSHORT(0, p);
    PUTSHORT(ns, p);
    PUTSHORT(cli->peer_ns, p);

    /* AVP - Message type */
    PUTSHORT(L2TP_AVPHEADERFLAG_MANDATORY + 8, p);
    PUTSHORT(0, p);
    PUTSHORT(L2TP_AVPTYPE_MESSAGE, p);
    PUTSHORT(L2TP_MESSAGETYPE_ICRQ, p);

    /* AVP - Assign session ID */
    PUTSHORT(L2TP_AVPHEADERFLAG_MANDATORY + 8, p);
    PUTSHORT(0, p);
    PUTSHORT(L2TP_AVPTYPE_SESSIONID, p);
    PUTSHORT(cli->remote_session_id, p);

    /* AVP - Call serial number */
    PUTSHORT(L2TP_AVPHEADERFLAG_MANDATORY + 10, p);
    PUTSHORT(0, p);
    PUTSHORT(L2TP_AVPTYPE_CALLSERIALNUMBER, p);
    serialnumber = magic();
    PUTLONG(serialnumber, p);

    return l2tp_udp_send(cli, buf, len);
}

/* Complete session establishment */
static err_t l2tp_send_iccn(l2tp_client_t *cli, u16_t ns) {
    u8_t buf[64];
    u8_t *p = buf;
    u16_t len = 12 + 8 + 10 + 10;

    /* L2TP control header */
    PUTSHORT(L2TP_HEADERFLAG_CONTROL_MANDATORY, p);
    PUTSHORT(len, p);
    PUTSHORT(cli->source_tunnel_id, p);
    PUTSHORT(cli->source_session_id, p);
    PUTSHORT(ns, p);
    PUTSHORT(cli->peer_ns, p);

    /* AVP - Message type */
    PUTSHORT(L2TP_AVPHEADERFLAG_MANDATORY + 8, p);
    PUTSHORT(0, p);
    PUTSHORT(L2TP_AVPTYPE_MESSAGE, p);
    PUTSHORT(L2TP_MESSAGETYPE_ICCN, p);

    /* AVP - Framing type */
    PUTSHORT(L2TP_AVPHEADERFLAG_MANDATORY + 10, p);
    PUTSHORT(0, p);
    PUTSHORT(L2TP_AVPTYPE_FRAMINGTYPE, p);
    PUTLONG(L2TP_FRAMINGTYPE, p);

    /* AVP - TX connect speed */
    PUTSHORT(L2TP_AVPHEADERFLAG_MANDATORY + 10, p);
    PUTSHORT(0, p);
    PUTSHORT(L2TP_AVPTYPE_TXCONNECTSPEED, p);
    PUTLONG(L2TP_TXCONNECTSPEED, p);

    return l2tp_udp_send(cli, buf, len);
}

/* Send a ZLB ACK packet */
static err_t l2tp_send_zlb(l2tp_client_t *cli, u16_t ns, u16_t nr) {
    u8_t buf[16];
    u8_t *p = buf;
    u16_t len = 12;

    PUTSHORT(L2TP_HEADERFLAG_CONTROL_MANDATORY, p);
    PUTSHORT(len, p);
    PUTSHORT(cli->source_tunnel_id, p);
    PUTSHORT(0, p);
    PUTSHORT(ns, p);
    PUTSHORT(nr, p);

    return l2tp_udp_send(cli, buf, len);
}

/* Send a StopCCN packet */
static err_t l2tp_send_stopccn(l2tp_client_t *cli, u16_t ns) {
    u8_t buf[64];
    u8_t *p = buf;
    u16_t len = 12 + 8 + 8 + 8;

    PUTSHORT(L2TP_HEADERFLAG_CONTROL_MANDATORY, p);
    PUTSHORT(len, p);
    PUTSHORT(cli->source_tunnel_id, p);
    PUTSHORT(0, p);
    PUTSHORT(ns, p);
    PUTSHORT(cli->peer_ns, p);

    /* AVP - Message type */
    PUTSHORT(L2TP_AVPHEADERFLAG_MANDATORY + 8, p);
    PUTSHORT(0, p);
    PUTSHORT(L2TP_AVPTYPE_MESSAGE, p);
    PUTSHORT(L2TP_MESSAGETYPE_STOPCCN, p);

    /* AVP - Assign tunnel ID */
    PUTSHORT(L2TP_AVPHEADERFLAG_MANDATORY + 8, p);
    PUTSHORT(0, p);
    PUTSHORT(L2TP_AVPTYPE_TUNNELID, p);
    PUTSHORT(cli->remote_tunnel_id, p);

    /* AVP - Result code */
    PUTSHORT(L2TP_AVPHEADERFLAG_MANDATORY + 8, p);
    PUTSHORT(0, p);
    PUTSHORT(L2TP_AVPTYPE_RESULTCODE, p);
    PUTSHORT(L2TP_RESULTCODE, p);

    return l2tp_udp_send(cli, buf, len);
}

/* ========== Timeout / retry ========== */

/* L2TP timeout handler */
static void l2tp_timeout(void *arg) {
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
static void l2tp_abort_connect(l2tp_client_t *cli) {
    PPPDEBUG(LOG_DEBUG, ("l2tp: could not establish connection\n"));
    cli->phase = L2TP_STATE_INITIAL;
    ppp_link_failed((ppp_pcb *)cli->ppp); /* notify upper layers */
}

/* Periodic tick: transport error handling */
static void l2tp_periodic_timer(void *arg) {
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

static void l2tp_schedule_retry(l2tp_client_t *cli, const char *reason) {
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

/* ========== PPP link status ========== */

static void l2tp_ppp_status_cb(ppp_pcb *ppp, int err_code, void *ctx) {
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

static void l2tp_stop_internal(l2tp_client_t *cli) {
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
