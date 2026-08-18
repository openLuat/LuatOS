/*
 * L2TPv2 (RFC 2661) control-plane implementation for LuatOS netdrv:
 * L2TP data packet build, incoming control packet parse/dispatch and the
 * AVP senders (SCCRQ/SCCCN/ICRQ/ICCN/ZLB/StopCCN, ns/nr window).
 *
 * Split from the original single-file l2tp client core; behavior unchanged.
 */

#include "l2tp/l2tp_client.h"
#include "l2tp/l2tp_ctrl.h"

#include <string.h>
#include "lwip/def.h"
#include "lwip/pbuf.h"
#include "lwip/timeouts.h"
#include "netif/ppp/ppp_opts.h"
#include "luat_ppp_opts_override.h"
#include "netif/ppp/ppp_impl.h"
#include "netif/ppp/ppp.h"
#include "netif/ppp/magic.h"
#include "netif/ppp/pppcrypt.h"

#define LUAT_LOG_TAG "l2tp"
#include "luat_log.h"
#include "luat_network_adapter.h"

/* Forward declarations (client-local; the cross-file entries come from
 * l2tp/l2tp_client.h and l2tp/l2tp_ctrl.h) */
static void l2tp_dispatch_control_packet(l2tp_client_t *cli, u16_t port,
                                         const u8_t *inp, u16_t len, u16_t ns, u16_t nr);
static err_t l2tp_send_zlb(l2tp_client_t *cli, u16_t ns, u16_t nr);

/* Build and send one L2TP data packet from a pbuf.
 * skip: number of leading bytes to drop from the pbuf (HDLC address/control).
 * add_proto: prepend a 2-byte PPP protocol field (netif output path). */
err_t l2tp_data_send(l2tp_client_t *cli, struct pbuf *p, u16_t skip,
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
/* ========== Incoming packet processing ========== */

void l2tp_input_packet(l2tp_client_t *cli, const u8_t *data, u16_t datalen,
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

err_t l2tp_send_sccrq(l2tp_client_t *cli) {
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
err_t l2tp_send_scccn(l2tp_client_t *cli, u16_t ns) {
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
err_t l2tp_send_icrq(l2tp_client_t *cli, u16_t ns) {
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
err_t l2tp_send_iccn(l2tp_client_t *cli, u16_t ns) {
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
err_t l2tp_send_stopccn(l2tp_client_t *cli, u16_t ns) {
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
