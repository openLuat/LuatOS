/*
 * OpenVPN client core for LuatOS netdrv: lifecycle/state machine, raw UDP
 * transport, virtual netif and data-plane (AES-256-GCM) handling, plus the
 * periodic timer/retry logic.
 *
 * Split from the original single-file OpenVPN client core; behavior unchanged.
 * Control-channel helpers live in ovpn_pkt.c / ovpn_rel.c / ovpn_ctl.c /
 * ovpn_tls.c / ovpn_crypto.c.
 */

#include "ovpn/ovpn_client.h"
#include "ovpn/ovpn_pkt.h"
#include "ovpn/ovpn_rel.h"
#include "ovpn/ovpn_ctl.h"
#include "ovpn/ovpn_tls.h"

#include <string.h>
#include <stdio.h>
#include "lwip/def.h"
#include "lwip/init.h"
#include "lwip/pbuf.h"
#include "lwip/ip4.h"
#include "lwip/ip_addr.h"
#include "lwip/dns.h"
#include "lwip/tcpip.h"
#include "lwip/timeouts.h"
#include "lwip/sys.h"
#include "net_lwip2.h"
#include "luat_netdrv.h"
#include "luat_malloc.h"
#include "luat_crypto.h"

#define LUAT_LOG_TAG "openvpn"
#include "luat_log.h"
#include "luat_network_adapter.h"

/* Forward declarations (client-local; cross-file entries come from the internal headers) */
static int32_t ovpn_netc_callback(void *pData, void *pParam);
static void ovpn_attach_netif(ovpn_client_t *cli);
static void ovpn_client_stop_internal(ovpn_client_t *cli, int free_buffers);
static void ovpn_retry_timer(void *arg);
static void ovpn_periodic_timer(void *arg);

/* lwIP compatibility defines for NETIF flags */
#ifndef NETIF_FLAG_POINTTOPOINT
#define NETIF_FLAG_POINTTOPOINT 0
#endif
#ifndef NETIF_FLAG_NOARP
#define NETIF_FLAG_NOARP 0
#endif

/* Send a raw UDP packet to the remote server */
int ovpn_send_udp(ovpn_client_t *cli, const uint8_t *data, int len) {
    if (!cli || !cli->netc || !data || len <= 0) return -1;
    uint32_t tx_len = 0;
    int ret = network_tx(cli->netc, data, len, 0,
                         &cli->remote_ip, cli->remote_port,
                         &tx_len, 0);
    return (ret >= 0 && tx_len == (uint32_t)len) ? 0 : -1;
}

/* ========== Virtual netif ========== */

/* Encrypt and send an IP packet through the VPN tunnel.
 * Uses P_DATA_V2 with AES-256-GCM AEAD.
 *
 * Reference: openvpn/src/openvpn/crypto.c openvpn_encrypt_aead
 *            openvpn/src/openvpn/ssl.c tls_prepend_opcode_v2
 *
 * Wire format:
 *   [P_DATA_V2 header(4)] [packet_id(4)] [AEAD tag(16)] [ciphertext(N)]
 *
 * P_DATA_V2 header = htonl(((P_DATA_V2 << 3) | key_id) << 24 | (peer_id & 0xFFFFFF))
 * IV = XOR(implicit_iv, [packet_id(4), 0(8)])
 * AAD = first 8 bytes of the packet (header + packet_id)
 * PT  = raw IP packet (no packet_id prepended to plaintext)
 */
static err_t ovpn_netif_output_ip4(struct netif *n, struct pbuf *p, const ip4_addr_t *addr) {
    LWIP_UNUSED_ARG(addr);
    ovpn_client_t *cli = (ovpn_client_t *)n->state;
    if (!cli || !cli->data_key_ready) return ERR_VAL;
    if (cli->debug) {
        LLOGD("VPN TX dst=%s len=%d", ip4addr_ntoa(addr), p->tot_len);
    }

    uint8_t buf[1600];
    uint32_t packet_id = cli->data_tx_seq++;
    uint32_t net_pid = lwip_htonl(packet_id);

    /* P_DATA_V2 header: 4 bytes */
    uint32_t hdr = lwip_htonl(((uint32_t)OVPN_OP_DATA_V2 << OVPN_OPCODE_SHIFT | cli->key_id) << 24
                              | (cli->peer_id & 0xFFFFFF));
    memcpy(buf, &hdr, 4);
    memcpy(buf + 4, &net_pid, 4);

    /* Construct IV: XOR implicit_iv with [packet_id, 0..0] */
    uint8_t iv[OVPN_AEAD_IV_LEN];
    memcpy(iv, &net_pid, 4);
    memset(iv + 4, 0, OVPN_AEAD_IV_LEN - 4);
    for (int i = 0; i < OVPN_AEAD_IV_LEN; i++) {
        iv[i] ^= cli->enc_implicit_iv[i];
    }

    /* Copy IP packet payload */
    int comp_off = cli->push_reply.use_comp_stub ? 1 : 0;
    uint16_t plen = p->tot_len;
    if (plen + comp_off > 1400) return ERR_VAL;
    if (comp_off) buf[4 + 4 + OVPN_AUTH_TAG_LEN] = 0xFA; /* NO_COMPRESS byte */
    pbuf_copy_partial(p, buf + 4 + 4 + OVPN_AUTH_TAG_LEN + comp_off, plen, 0);
    plen += comp_off;

    /* Encrypt with AES-256-GCM:
     *   AAD = header(4) + packet_id(4) = first 8 bytes of the buffer
     *   PT  = [comp_byte] + IP packet at buf + 24
     *   CT  = output (in-place same as PT)
     *   Tag = at buf + 8 */
    int ret = mbedtls_gcm_crypt_and_tag(&cli->gcm_enc,
                                         MBEDTLS_GCM_ENCRYPT,
                                         plen,
                                         iv, OVPN_AEAD_IV_LEN,
                                         buf, 8,              /* AAD = header + packet_id */
                                         buf + 4 + 4 + OVPN_AUTH_TAG_LEN,  /* plaintext */
                                         buf + 4 + 4 + OVPN_AUTH_TAG_LEN,  /* ciphertext (in-place) */
                                         OVPN_AUTH_TAG_LEN,
                                         buf + 4 + 4);        /* tag at offset 8 */
    if (ret != 0) return ERR_VAL;

    int total = 4 + 4 + OVPN_AUTH_TAG_LEN + plen;
    ovpn_send_udp(cli, buf, total);
    cli->stats.tx_pkts++;
    cli->stats.tx_bytes += plen;
    return ERR_OK;
}

#if LWIP_IPV6
static err_t ovpn_netif_output_ip6(struct netif *n, struct pbuf *p, const ip6_addr_t *addr) {
    LWIP_UNUSED_ARG(addr);
    return ERR_VAL;
}
#endif

static err_t ovpn_netif_init(struct netif *n) {
    ovpn_client_t *cli = (ovpn_client_t *)n->state;
    n->mtu = cli->mtu ? cli->mtu : OVPN_TUN_MTU_DEFAULT;
    n->flags = NETIF_FLAG_POINTTOPOINT | NETIF_FLAG_NOARP | NETIF_FLAG_LINK_UP;
    n->output = ovpn_netif_output_ip4;
#if LWIP_IPV6
    n->output_ip6 = ovpn_netif_output_ip6;
#endif
    n->name[0] = 'o';
    n->name[1] = 'v';
    return ERR_OK;
}

static void ovpn_attach_netif(ovpn_client_t *cli) {
    if (cli->adapter_index >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) {
        cli->adapter_index = NW_ADAPTER_INDEX_LWIP_USER0;
    }
#if LWIP_VERSION_MAJOR >= 2 && LWIP_VERSION_MINOR >= 1
    netif_add(&cli->netif, IP4_ADDR_ANY4, IP4_ADDR_ANY4, IP4_ADDR_ANY4,
              cli, ovpn_netif_init, netif_input);
#else
    ip4_addr_t ipaddr, netmask, gw;
    ip4_addr_set_zero(&ipaddr);
    ip4_addr_set_zero(&netmask);
    ip4_addr_set_zero(&gw);
    netif_add(&cli->netif, &ipaddr, &netmask, &gw, cli, ovpn_netif_init, netif_input);
#endif
    netif_set_up(&cli->netif);
    netif_set_link_up(&cli->netif);
    net_lwip2_set_netif(cli->adapter_index, &cli->netif);
    net_lwip2_register_adapter(cli->adapter_index);
}

/* ========== Incoming packet processing ========== */

void ovpn_client_udp_recv(ovpn_client_t *cli, const uint8_t *data, uint16_t len,
                          ip_addr_t *addr, uint16_t port)
{
    if (!cli || !data || !addr || len == 0) return;

    /* Filter: only accept packets from the configured remote */
    if (!ip_addr_cmp(addr, &cli->remote_ip) || port != cli->remote_port) {
        cli->stats.drop_malformed++;
        return;
    }

    uint8_t buf[1600];
    if (len > 1600) len = 1600;
    memcpy(buf, data, len);

    uint8_t opcode = buf[0] >> OVPN_OPCODE_SHIFT;
    uint8_t key_id = buf[0] & OVPN_KEY_ID_MASK;

    /* Handle data channel packets early (different format from control packets) */
    if (opcode == OVPN_OP_DATA_V1 || opcode == OVPN_OP_DATA_V2) {
        if (cli->data_key_ready) {
            int hdr_size = (opcode == OVPN_OP_DATA_V2) ? 4 : 1;
            int min_len = hdr_size + 4 + OVPN_AUTH_TAG_LEN;
            if (len >= min_len) {
                uint32_t net_pid;
                if (opcode == OVPN_OP_DATA_V2)
                    memcpy(&net_pid, buf + 4, 4);
                else
                    memcpy(&net_pid, buf + 1, 4);
                cli->data_rx_seq = lwip_ntohl(net_pid);
                uint8_t iv[OVPN_AEAD_IV_LEN];
                memcpy(iv, &net_pid, 4); memset(iv + 4, 0, OVPN_AEAD_IV_LEN - 4);
                for (int i = 0; i < OVPN_AEAD_IV_LEN; i++) iv[i] ^= cli->dec_implicit_iv[i];
                int elen = len - hdr_size - 4 - OVPN_AUTH_TAG_LEN;
                if (elen > 0) {
                    uint8_t dec[1600];
                    /* AAD per reference ssl.c:handle_data_channel_packet:
                     * V1: AAD = 4 bytes (packet_id only), starts AFTER opcode byte
                     * V2: AAD = 8 bytes (opcode + peer_id + pid), starts at byte 0 */
                    int aad_off = (opcode == OVPN_OP_DATA_V2) ? 0 : 1;
                    int aad_size = (opcode == OVPN_OP_DATA_V2) ? 8 : 4;
                    int ret = mbedtls_gcm_auth_decrypt(&cli->gcm_dec, elen, iv, OVPN_AEAD_IV_LEN,
                                buf + aad_off, aad_size, buf + hdr_size + 4, OVPN_AUTH_TAG_LEN,
                                buf + hdr_size + 4 + OVPN_AUTH_TAG_LEN, dec);
                    if (ret == 0) {
                        /* Strip NO_COMPRESS byte if server uses compression stub */
                        int pkt_off = (cli->push_reply.use_comp_stub && elen > 1 && dec[0] == 0xFA) ? 1 : 0;
                        int pkt_len = elen - pkt_off;
                        if (pkt_len > 0) {
                            struct pbuf *ip = pbuf_alloc(PBUF_IP, pkt_len, PBUF_RAM);
                            if (ip) { memcpy(ip->payload, dec + pkt_off, pkt_len); cli->netif.input(ip, &cli->netif); }
                        }
                    }
                }
            }
        }
        return;
    }

    uint8_t src_sid[OVPN_SID_SIZE];
    int ack_count, has_pid;
    uint32_t acks[OVPN_MAX_ACKS_ACK], packet_id = 0;
    const uint8_t *payload;
    int payload_len;

    if (ovpn_parse_pkt(buf, len, &opcode, &key_id, src_sid,
                        acks, &ack_count,
                        &packet_id, &has_pid, &payload, &payload_len) != 0)
    {
        cli->stats.drop_malformed++;
        if (cli->debug) {
            LLOGD("parse fail: len=%d first_byte=0x%02x", len, data[0]);
        }
        return;
    }

    if (cli->debug) {
        LLOGD("rx op=%u kid=%u pid=%d ack=%d len=%d",
              (unsigned)opcode, (unsigned)key_id, has_pid ? (int)packet_id : -1,
              ack_count, payload_len);
        if (len <= 64) {
            char hex[128] = {0};
            int hl = len > 32 ? 32 : len;
            for (int i = 0; i < hl; i++)
                sprintf(hex + i*3, "%02x ", data[i]);
            LLOGD("hex(%d): %s", len, hex);
        }
    }

    cli->last_activity_ms = sys_now();

    /* Process ACKs (implicit: seq=N frees all ≤N in send window) */
    for (int i = 0; i < ack_count; i++) {
        uint32_t maxid = acks[i];
        for (int j = 0; j < OVPN_REL_SEND_SIZE; j++)
            if (cli->rel_send[j].in_use && cli->rel_send[j].id <= maxid) {
                luat_heap_free(cli->rel_send[j].data);
                cli->rel_send[j].in_use = 0; cli->rel_send[j].data = NULL;
            }
    }

    /* Track peer session ID */
    if (!cli->peer_session_id_valid && opcode == OVPN_OP_CONTROL_HARD_RESET_SERVER_V2) {
        ovpn_copy_sid(cli->peer_session_id, src_sid);
        cli->peer_session_id_valid = 1;
        if (cli->debug) LLOGD("peer session_id established");
    }

    switch (opcode) {
    case OVPN_OP_CONTROL_HARD_RESET_SERVER_V2:
        if (cli->state == OVPN_STATE_RESET_SENT) {
            rel_send_ack(cli, 0);

            if (has_pid) {
                ovpn_queue_ack(cli, packet_id);
            }
            ovpn_send_ack(cli);
            cli->state = OVPN_STATE_RESET_ACKED;
            LLOGI("Received server reset, starting TLS");

            int ret = mbedtls_ssl_handshake(&cli->ssl);
            if (ret == 0) {
                cli->tls_handshake_done = 1;
                cli->tls_ready = 1;
                LLOGI("TLS handshake completed (immediate)");
                if (cli->event_cb) {
                    cli->event_cb(OVPN_EVENT_TLS_HANDSHAKE_OK, cli->user_data);
                }
                cli->km2_state = OVPN_KM2_WAIT_SEND;
            }
            cli->state = OVPN_STATE_HANDSHAKE;
        }
        break;

    case OVPN_OP_CONTROL_V1:
        if (cli->state >= OVPN_STATE_RESET_ACKED) {
            if (has_pid) {
                ovpn_queue_ack(cli, packet_id);
                rel_recv_add(cli, packet_id, payload, payload_len);

                const uint8_t *rdata;
                int rlen;
                uint32_t rid;
                while (rel_recv_next(cli, &rdata, &rlen, &rid)) {
                    ovpn_feed_tls(cli, rdata, rlen);
                    rel_recv_advance(cli, rid);
                }
            }

            if (cli->pending_ack_count > 0) {
                ovpn_send_ack(cli);
            }
        }
        break;

    case OVPN_OP_ACK_V1:
        if (cli->debug) {
            LLOGD("received ACK_V1, %d acks", ack_count);
        }
        break;

    case OVPN_OP_DATA_V2: {
        if (!cli->data_key_ready) {
            cli->stats.drop_malformed++;
            return;
        }
        /* P_DATA_V2: [4B header] [4B packet_id] [16B tag] [ciphertext] */
        int min_hdr = 4 + 4 + OVPN_AUTH_TAG_LEN;
        if (len < min_hdr) {
            cli->stats.drop_malformed++;
            return;
        }

        /* Read packet_id from wire */
        uint32_t net_pid;
        memcpy(&net_pid, data + 4, 4);
        cli->data_rx_seq = lwip_ntohl(net_pid);

        /* Construct IV: XOR implicit_iv with [packet_id, 0..0] */
        uint8_t iv[OVPN_AEAD_IV_LEN];
        memcpy(iv, &net_pid, 4);
        memset(iv + 4, 0, OVPN_AEAD_IV_LEN - 4);
        for (int i = 0; i < OVPN_AEAD_IV_LEN; i++) {
            iv[i] ^= cli->dec_implicit_iv[i];
        }

        int enc_len = len - 4 - 4 - OVPN_AUTH_TAG_LEN;
        if (enc_len <= 0) break;

        uint8_t dec_buf[1600];
        size_t dec_len;
        int ret = mbedtls_gcm_auth_decrypt(&cli->gcm_dec,
                                            enc_len,
                                            iv, OVPN_AEAD_IV_LEN,
                                            data, 8,              /* AAD = header + packet_id */
                                            data + 4 + 4,         /* tag at offset 8 */
                                            OVPN_AUTH_TAG_LEN,
                                            data + 4 + 4 + OVPN_AUTH_TAG_LEN, /* ciphertext */
                                            dec_buf);
        if (ret == 0) dec_len = enc_len;
        if (ret != 0) {
            cli->stats.drop_auth++;
            return;
        }

        /* Inject decrypted IP packet into netif */
        struct pbuf *ip = pbuf_alloc(PBUF_IP, dec_len, PBUF_RAM);
        if (ip) {
            memcpy(ip->payload, dec_buf, dec_len);
            err_t err = cli->netif.input(ip, &cli->netif);
            if (err != ERR_OK) pbuf_free(ip);
        }
        cli->stats.rx_pkts++;
        cli->stats.rx_bytes += dec_len;
        break;
    }

    default:
        break;
    }

    /* Flush pending ACKs */
    ovpn_client_poll(cli);
}

/* ========== Network adapter callback ========== */

static int32_t ovpn_netc_callback(void *pData, void *pParam) {
    OS_EVENT *event = (OS_EVENT *)pData;
    ovpn_client_t *cli = (ovpn_client_t *)pParam;
    if (!event || !cli || !cli->netc) return -1;

    if (event->ID == EV_NW_RESULT_EVENT) {
        uint8_t buf[1600];
        uint32_t rx_len = 0;
        luat_ip_addr_t src_addr;
        uint16_t src_port = 0;
        int ret = network_rx(cli->netc, buf, sizeof(buf), 0,
                             &src_addr, &src_port, &rx_len);
        if (ret == 0 && rx_len > 0) {
            if (cli->debug) {
                LLOGD("UDP recv from %s:%u, len=%lu",
                      ipaddr_ntoa(&src_addr), src_port, (unsigned long)rx_len);
            }
            ovpn_client_udp_recv(cli, buf, (uint16_t)rx_len,
                                 (ip_addr_t *)&src_addr, src_port);
        }
    } else if (event->ID == EV_NW_RESULT_CLOSE || event->Param1 != 0) {
        /* Transport error: socket closed, or Param1 != 0 (general failure) */
        cli->transport_err = 1;
    }
    return 0;
}

/* ========== Retry / timer logic ========== */

/**
 * Check whether at least one non-OpenVPN transport adapter is online.
 *
 * First checks netdrv layer (LwIP netif adapters) via luat_netdrv_is_ready().
 * Falls back to network adapter layer via network_check_ready() for adapters
 * that don't use netdrv (e.g. POSIX socket adapter on PC simulator).
 * Returns 1 if any transport adapter is ready, 0 otherwise.
 */
static int ovpn_transport_is_online(ovpn_client_t *cli) {
    for (int i = 0; i < NW_ADAPTER_QTY; i++) {
        if (i == cli->adapter_index) continue;   /* skip our own virtual tun */
        if (luat_netdrv_is_ready(i)) return 1;
    }
    /* Fallback: check network adapter layer (covers POSIX/HW-PS adapters) */
    int dft = network_register_get_default();
    if (dft >= 0 && dft != cli->adapter_index) {
        if (network_check_ready(NULL, (uint8_t)dft)) return 1;
    }
    return 0;
}

static uint32_t ovpn_next_backoff_ms(ovpn_client_t *cli) {
    uint32_t base = cli->retry_base_ms ? cli->retry_base_ms : 1000;
    uint32_t max = cli->retry_max_ms ? cli->retry_max_ms : 60000;
    if (max < base) max = base;
    if (cli->retry_attempt >= 31) return max;
    uint32_t delay = base << cli->retry_attempt;
    if (delay < base) return max;
    return delay > max ? max : delay;
}

static void ovpn_schedule_retry(ovpn_client_t *cli, const char *reason) {
    if (!cli || !cli->retry_enabled || cli->retry_timer_active) return;
    uint32_t delay = ovpn_next_backoff_ms(cli);
    /* Transport offline → poll at base interval for quick recovery */
    if (!ovpn_transport_is_online(cli)) {
        delay = cli->retry_base_ms ? cli->retry_base_ms : 1000;
        LLOGD("transport offline, waiting %u ms before next retry", (unsigned)delay);
    }
    cli->retry_timer_active = 1;
    cli->retry_attempt++;
    LLOGW("schedule retry in %u ms (%s)", (unsigned)delay, reason ? reason : "unknown");
    sys_timeout(delay, ovpn_retry_timer, cli);
}

static void ovpn_retry_timer(void *arg) {
    ovpn_client_t *cli = (ovpn_client_t *)arg;
    if (!cli) return;
    cli->retry_timer_active = 0;
    if (cli->started) return;
    if (cli->use_tls) {
        if (!cli->ca_cert_buf || !cli->client_cert_buf || !cli->client_key_buf) return;
        ovpn_tls_free(cli);
        ovpn_client_cfg_t cfg = {0};
        cfg.ca_cert_pem = (const char *)cli->ca_cert_buf;
        cfg.ca_cert_len = cli->ca_cert_len;
        cfg.client_cert_pem = (const char *)cli->client_cert_buf;
        cfg.client_cert_len = cli->client_cert_len;
        cfg.client_key_pem = (const char *)cli->client_key_buf;
        cfg.client_key_len = cli->client_key_len;
        if (ovpn_tls_init(cli, &cfg) != 0) {
            ovpn_schedule_retry(cli, "tls re-init");
            return;
        }
    }
    ovpn_client_start(cli);
}

/* ========== Periodic timer callback ========== */

static void ovpn_periodic_timer(void *arg) {
    ovpn_client_t *cli = (ovpn_client_t *)arg;
    if (!cli || !cli->started) return;

    ovpn_client_timer_tick(cli);

    sys_timeout(OVPN_TICK_INTERVAL_MS, ovpn_periodic_timer, cli);
}

/* ========== Public periodic poll function ========== */

void ovpn_client_timer_tick(ovpn_client_t *cli) {
    if (!cli || !cli->started) return;
    uint32_t now = sys_now();

    /* Transport socket error — stop and schedule retry */
    if (cli->transport_err) {
        cli->transport_err = 0;
        LLOGW("transport socket error, scheduling retry");
        ovpn_client_stop_internal(cli, 0);
        ovpn_schedule_retry(cli, "transport error");
        return;
    }

    /* Retransmit */
    rel_send_retransmit(cli, now);

    /* Handshake timeout */
    if (!cli->tls_handshake_done && !cli->handshake_failed &&
        (now - cli->handshake_start_ms) >= OVPN_HANDSHAKE_TIMEOUT_MS)
    {
        cli->handshake_failed = 1;
        LLOGE("handshake timeout");
        if (cli->event_cb) cli->event_cb(OVPN_EVENT_TLS_HANDSHAKE_FAIL, cli->user_data);
        ovpn_client_stop_internal(cli, 0);
        ovpn_schedule_retry(cli, "handshake timeout");
        return;
    }

    /* Deferred KM2 send (after handshake) */
    if (cli->km2_state == OVPN_KM2_SENDING && cli->tls_handshake_done) {
        cli->tls_buf_len = 0; cli->tls_buf_offset = 0;
        uint8_t km2_buf[512];
        int km2_len = ovpn_build_km2_msg(cli, km2_buf, sizeof(km2_buf));
        if (km2_len > 0) {
            int total = 0;
            while (total < km2_len) {
                int ret = mbedtls_ssl_write(&cli->ssl, km2_buf + total, km2_len - total);
                if (ret > 0) total += ret;
                else if (ret != MBEDTLS_ERR_SSL_WANT_READ && ret != MBEDTLS_ERR_SSL_WANT_WRITE) break;
            }
            LLOGI("Sent key_method_2 (%d/%d bytes)", total, km2_len);
            if (total == km2_len) {
                cli->km2_state = OVPN_KM2_WAIT_REPLY;
                cli->push_sent_ms = sys_now();
                mbedtls_ssl_write(&cli->ssl, (const unsigned char*)"PUSH_REQUEST\0", 13);
                LLOGI("Sent PUSH_REQUEST");
            }
        }
    }

    /* Read TLS app data (KM2 reply, PUSH_REPLY, etc.) */
    if (cli->km2_state >= OVPN_KM2_WAIT_REPLY && cli->tls_handshake_done) {
        ovpn_process_tls_app_data(cli);
    }

    /* Send PUSH_REQUEST periodically if we haven't received PUSH_REPLY */
    if (cli->km2_state >= OVPN_KM2_DONE && !cli->push_reply.received &&
        (now - cli->push_sent_ms) > 5000)
    {
        cli->push_sent_ms = now;
        mbedtls_ssl_write(&cli->ssl, (const unsigned char*)"PUSH_REQUEST\0", 13);
        LLOGI("Resending PUSH_REQUEST");
    }

    /* Keepalive */
    if (cli->tls_ready && (now - cli->last_activity_ms) >= OVPN_PING_INTERVAL_MS) {
        if (cli->debug) LLOGD("keepalive ping");
        cli->last_activity_ms = now;
    }

    if ((now - cli->last_activity_ms) >= OVPN_DEAD_INTERVAL_MS) {
        LLOGW("keepalive timeout");
        if (cli->event_cb) cli->event_cb(OVPN_EVENT_KEEPALIVE_TIMEOUT, cli->user_data);
        ovpn_client_stop_internal(cli, 0);
        ovpn_schedule_retry(cli, "keepalive timeout");
        return;
    }
}

void ovpn_client_poll(ovpn_client_t *cli) {
    if (cli->pending_ack_count > 0) {
        ovpn_send_ack(cli);
    }
}

int ovpn_client_is_ready(ovpn_client_t *cli) {
    return cli && cli->tls_ready && cli->push_reply.received;
}

/* ========== Main API ========== */

int ovpn_client_init(ovpn_client_t *cli, const ovpn_client_cfg_t *cfg) {
    if (!cli || !cfg) return -1;
    memset(cli, 0, sizeof(*cli));

    cli->remote_ip = cfg->remote_ip;
    cli->remote_port = cfg->remote_port;
    cli->adapter_index = cfg->adapter_index ? cfg->adapter_index : NW_ADAPTER_INDEX_LWIP_USER0;
    cli->transport_index = cfg->transport_index;
    cli->mtu = cfg->tun_mtu ? cfg->tun_mtu : OVPN_TUN_MTU_DEFAULT;
    cli->event_cb = cfg->event_cb;
    cli->user_data = cfg->user_data;
    cli->retry_enabled = cfg->retry_enable ? 1 : 0;
    cli->retry_base_ms = cfg->retry_base_ms ? cfg->retry_base_ms : 1000;
    cli->retry_max_ms = cfg->retry_max_ms ? cfg->retry_max_ms : 60000;
    cli->state = OVPN_STATE_IDLE;

    if (!cfg->ca_cert_pem || !cfg->client_cert_pem || !cfg->client_key_pem ||
        cfg->ca_cert_len == 0 || cfg->client_cert_len == 0 || cfg->client_key_len == 0) {
        LLOGE("TLS certificates required");
        return -3;
    }

    /* Copy certs to heap */
    cli->ca_cert_buf = (uint8_t *)luat_heap_malloc(cfg->ca_cert_len + 1); if (!cli->ca_cert_buf) return -2;
    memcpy(cli->ca_cert_buf, cfg->ca_cert_pem, cfg->ca_cert_len);
    cli->ca_cert_buf[cfg->ca_cert_len] = '\0';
    cli->ca_cert_len = cfg->ca_cert_len + 1;

    cli->client_cert_buf = (uint8_t *)luat_heap_malloc(cfg->client_cert_len + 1); if (!cli->client_cert_buf) goto err;
    memcpy(cli->client_cert_buf, cfg->client_cert_pem, cfg->client_cert_len);
    cli->client_cert_buf[cfg->client_cert_len] = '\0';
    cli->client_cert_len = cfg->client_cert_len + 1;

    cli->client_key_buf = (uint8_t *)luat_heap_malloc(cfg->client_key_len + 1); if (!cli->client_key_buf) goto err;
    memcpy(cli->client_key_buf, cfg->client_key_pem, cfg->client_key_len);
    cli->client_key_buf[cfg->client_key_len] = '\0';
    cli->client_key_len = cfg->client_key_len + 1;

    /* Copy username/password if provided */
    if (cfg->username && cfg->username_len > 0) {
        cli->username_buf = (uint8_t *)luat_heap_malloc(cfg->username_len + 1);
        if (!cli->username_buf) goto err;
        memcpy(cli->username_buf, cfg->username, cfg->username_len);
        cli->username_buf[cfg->username_len] = '\0';
        cli->username_len = cfg->username_len + 1;
    }
    if (cfg->password && cfg->password_len > 0) {
        cli->password_buf = (uint8_t *)luat_heap_malloc(cfg->password_len + 1);
        if (!cli->password_buf) goto err;
        memcpy(cli->password_buf, cfg->password, cfg->password_len);
        cli->password_buf[cfg->password_len] = '\0';
        cli->password_len = cfg->password_len + 1;
    }

    /* Initialize TLS */
    cli->use_tls = 1;
    ovpn_client_cfg_t cfg_copy = *cfg;
    cfg_copy.ca_cert_pem = (const char *)cli->ca_cert_buf;
    cfg_copy.ca_cert_len = cli->ca_cert_len;
    cfg_copy.client_cert_pem = (const char *)cli->client_cert_buf;
    cfg_copy.client_cert_len = cli->client_cert_len;
    cfg_copy.client_key_pem = (const char *)cli->client_key_buf;
    cfg_copy.client_key_len = cli->client_key_len;

    int tls_ret = ovpn_tls_init(cli, &cfg_copy);
    if (tls_ret != 0) {
        LLOGE("TLS init failed: %d", tls_ret);
        goto err;
    }

    cli->last_activity_ms = sys_now();
    return 0;

err:
    if (cli->ca_cert_buf) { luat_heap_free(cli->ca_cert_buf); cli->ca_cert_buf = NULL; }
    if (cli->client_cert_buf) { luat_heap_free(cli->client_cert_buf); cli->client_cert_buf = NULL; }
    if (cli->client_key_buf) { luat_heap_free(cli->client_key_buf); cli->client_key_buf = NULL; }
    if (cli->username_buf) { luat_heap_free(cli->username_buf); cli->username_buf = NULL; }
    if (cli->password_buf) { luat_heap_free(cli->password_buf); cli->password_buf = NULL; }
    return -2;
}

int ovpn_client_start(ovpn_client_t *cli) {
    if (!cli) return -1;
    if (cli->started) return 0;
    if (ip_addr_isany(&cli->remote_ip)) { LLOGE("remote ip missing"); return -2; }
    if (!cli->use_tls) { LLOGE("TLS not initialized"); return -3; }

    /* Check transport availability before allocating resources */
    if (!ovpn_transport_is_online(cli)) {
        LLOGW("transport offline, deferring start");
        ovpn_schedule_retry(cli, "transport offline");
        return -6;
    }

    /* Allocate & init network controller via luat_network_adapter */
    cli->netc = network_alloc_ctrl(cli->transport_index);
    if (!cli->netc) { LLOGE("netc alloc fail"); ovpn_schedule_retry(cli, "netc alloc"); return -3; }
    network_init_ctrl(cli->netc, NULL, ovpn_netc_callback, cli);
    network_set_base_mode(cli->netc, 0, 10000, 0, 0, 0, 0); /* UDP mode */
    network_set_local_port(cli->netc, 0);
    int netc_ret = network_connect(cli->netc, NULL, 0, &cli->remote_ip, cli->remote_port, 0);
    if (netc_ret < 0) {
        LLOGE("netc connect fail");
        network_force_close_socket(cli->netc);
        network_release_ctrl(cli->netc);
        cli->netc = NULL;
        ovpn_schedule_retry(cli, "netc connect");
        return -4;
    }
    /* UDP: socket created, set ONLINE immediately (async connect event is a no-op in ONLINE state) */
    cli->netc->state = NW_STATE_ONLINE;

    /* Attach virtual netif */
    ovpn_attach_netif(cli);

    /* Generate session ID */
    luat_crypto_trng((char *)cli->session_id, OVPN_SID_SIZE);

    /* Initialize reliable layer */
    cli->rel_next_seq = 0;
    cli->rel_recv_next = 1;
    cli->pending_ack_count = 0;
    cli->key_id = 0;
    cli->peer_id = 0;

    /* Reset states */
    cli->km2_state = OVPN_KM2_NONE;
    cli->tls_handshake_done = 0;
    cli->tls_ready = 0;
    cli->push_sent_ms = 0;

    /* Send HARD_RESET_CLIENT_V2 */
    int ret = ovpn_send_ctrl(cli, OVPN_OP_CONTROL_HARD_RESET_CLIENT_V2, NULL, 0);
    if (ret != 0) {
        LLOGE("send hard reset failed");
        network_force_close_socket(cli->netc);
        network_release_ctrl(cli->netc);
        cli->netc = NULL;
        return -5;
    }

    cli->state = OVPN_STATE_RESET_SENT;
    cli->started = 1;
    cli->handshake_start_ms = sys_now();
    cli->handshake_failed = 0;
    cli->retry_attempt = 0;
    cli->retry_timer_active = 0;
    cli->transport_err = 0;

    /* Start periodic tick */
    sys_timeout(OVPN_TICK_INTERVAL_MS, ovpn_periodic_timer, cli);

    LLOGI("OpenVPN client started, waiting for server reset...");
    return 0;
}

static void ovpn_client_stop_internal(ovpn_client_t *cli, int free_buffers) {
    if (!cli) return;
    if (cli->netc) {
        network_ctrl_t *netc = cli->netc;
        cli->netc = NULL;
        network_close(netc, 0);
        network_force_close_socket(netc);
        network_release_ctrl(netc);
    }
    sys_untimeout(ovpn_periodic_timer, cli);
    sys_untimeout(ovpn_retry_timer, cli);
    cli->retry_timer_active = 0;

    if (cli->started) {
        netif_set_down(&cli->netif);
        netif_remove(&cli->netif);
    }
    if (cli->data_key_ready) {
        mbedtls_gcm_free(&cli->gcm_enc);
        mbedtls_gcm_free(&cli->gcm_dec);
    }
    cli->data_key_ready = 0;

    cli->started = 0;
    cli->state = OVPN_STATE_IDLE;
    cli->peer_session_id_valid = 0;
    cli->tls_ready = 0;
    cli->tls_handshake_done = 0;
    cli->push_reply.received = 0;
    cli->km2_state = OVPN_KM2_NONE;

    /* Free reliable send slots */
    for (int i = 0; i < OVPN_REL_SEND_SIZE; i++) {
        if (cli->rel_send[i].data) {
            luat_heap_free(cli->rel_send[i].data);
            cli->rel_send[i].data = NULL;
        }
        cli->rel_send[i].in_use = 0;
    }

    /* Free reliable recv slots */
    for (int i = 0; i < OVPN_REL_RECV_SIZE; i++) {
        if (cli->rel_recv[i].data) {
            luat_heap_free(cli->rel_recv[i].data);
            cli->rel_recv[i].data = NULL;
        }
        cli->rel_recv[i].in_use = 0;
    }

    if (free_buffers) {
        if (cli->ca_cert_buf) { luat_heap_free(cli->ca_cert_buf); cli->ca_cert_buf = NULL; }
        if (cli->client_cert_buf) { luat_heap_free(cli->client_cert_buf); cli->client_cert_buf = NULL; }
        if (cli->client_key_buf) { luat_heap_free(cli->client_key_buf); cli->client_key_buf = NULL; }
        if (cli->username_buf) { luat_heap_free(cli->username_buf); cli->username_buf = NULL; }
        if (cli->password_buf) { luat_heap_free(cli->password_buf); cli->password_buf = NULL; }
    }

    ovpn_tls_free(cli);

    if (cli->event_cb) {
        cli->event_cb(OVPN_EVENT_DISCONNECTED, cli->user_data);
    }
}

void ovpn_client_stop(ovpn_client_t *cli) {
    ovpn_client_stop_internal(cli, 1);
}

void ovpn_client_get_stats(ovpn_client_t *cli, ovpn_client_stats_t *out) {
    if (!cli || !out) return;
    *out = cli->stats;
}

void ovpn_client_set_debug(ovpn_client_t *cli, int enable) {
    if (!cli) return;
    cli->debug = enable ? 1 : 0;
}
