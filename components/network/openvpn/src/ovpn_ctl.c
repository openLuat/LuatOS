/*
 * OpenVPN control-channel logic for LuatOS netdrv: reliable control packet
 * send/ack, key_method_2 exchange, TLS app-data processing and PUSH_REPLY
 * parsing.
 *
 * Split from the original single-file OpenVPN client core; behavior unchanged.
 */

#include "ovpn/ovpn_client.h"
#include "ovpn/ovpn_pkt.h"
#include "ovpn/ovpn_rel.h"
#include "ovpn/ovpn_ctl.h"
#include "ovpn/ovpn_crypto.h"

#include <string.h>
#include <stdio.h>
#include "lwip/timeouts.h"
#include "luat_malloc.h"
#include "luat_crypto.h"

#define LUAT_LOG_TAG "openvpn"
#include "luat_log.h"

/* ========== Send an OpenVPN control packet ========== */

/* Send a control packet with optional TLS payload.
 * The packet is stored in the reliable send window for retransmission. */
int ovpn_send_ctrl(ovpn_client_t *cli, uint8_t opcode,
                   const uint8_t *payload, int payload_len)
{
    uint8_t buf[1600];
    uint32_t seq = cli->rel_next_seq++;
    int ack_count = 0;
    uint32_t acks[OVPN_MAX_ACKS] = {0};

    /* Piggyback pending ACKs */
    if (cli->pending_ack_count > 0 && opcode != OVPN_OP_ACK_V1) {
        ack_count = cli->pending_ack_count;
        memcpy(acks, cli->pending_acks, ack_count * sizeof(uint32_t));
        cli->pending_ack_count = 0;
    }

    /* tls_pre_decrypt matches header sid against ks->session_id_remote (our sid).
     * reliable_ack_read verifies ACK remote_sid against session->session_id (peer's sid).
     * Ref: openvpn/src/openvpn/ssl.c:3666, 3873; reliable.c:reliable_ack_parse */
    const uint8_t *ack_remote_sid = cli->peer_session_id_valid
                                    ? cli->peer_session_id : cli->session_id;
    int hdr_len = ovpn_build_hdr(buf, sizeof(buf),
                                  opcode, 0,
                                  cli->session_id,
                                  ack_remote_sid,
                                  acks, ack_count,
                                  seq, (opcode != OVPN_OP_ACK_V1));
    if (hdr_len < 0) return -1;

    int total = hdr_len + payload_len;
    if (total > sizeof(buf)) return -1;
    if (payload_len > 0) memcpy(buf + hdr_len, payload, payload_len);

    if (ovpn_send_udp(cli, buf, total) != 0) return -1;

    /* Store for retransmit (not for standalone ACKs) */
    if (opcode != OVPN_OP_ACK_V1) {
        uint32_t now = sys_now();
        rel_send_store(cli, seq, buf, total, now);
    }

    cli->last_activity_ms = sys_now();
    if (cli->debug) {
        LLOGD("tx op=%u seq=%lu len=%d ack=%d",
              (unsigned)opcode, (unsigned long)seq, total, ack_count);
        if (total <= 64) {
            char hex[128] = {0};
            for (int i = 0; i < total; i++)
                sprintf(hex + i*3, "%02x ", buf[i]);
            LLOGD("tx hex(%d): %s", total, hex);
        }
    }
    return 0;
}

/* Send standalone ACK via ovpn_build_hdr (standard wire format) */
int ovpn_send_ack(ovpn_client_t *cli) {
    if (cli->pending_ack_count == 0) return 0;
    int ack_count = cli->pending_ack_count;
    uint32_t acks[OVPN_MAX_ACKS_ACK];
    memcpy(acks, cli->pending_acks, ack_count * sizeof(uint32_t));
    cli->pending_ack_count = 0;

    const uint8_t *ack_remote_sid = cli->peer_session_id_valid
                                    ? cli->peer_session_id : cli->session_id;
    uint8_t buf[64];
    int hdr_len = ovpn_build_hdr(buf, sizeof(buf),
                                  OVPN_OP_ACK_V1, 0,
                                  cli->session_id,
                                  ack_remote_sid,
                                  acks, ack_count,
                                  0, 0); /* ACK_V1 has no packet_id */
    if (hdr_len < 0) return -1;

    int ret = ovpn_send_udp(cli, buf, hdr_len);
    cli->last_activity_ms = sys_now();
    if (cli->debug) {
        LLOGD("tx standalone_ack count=%d len=%d", ack_count, hdr_len);
    }
    return ret;
}

/* Queue an ACK to be sent (piggybacked on next control packet or standalone) */
void ovpn_queue_ack(ovpn_client_t *cli, uint32_t seq) {
    if (cli->pending_ack_count >= OVPN_MAX_ACKS) return;
    for (int i = 0; i < cli->pending_ack_count; i++) {
        if (cli->pending_acks[i] == seq) return;
    }
    cli->pending_acks[cli->pending_ack_count++] = seq;
}

/* ========== Key method 2 exchange ========== */

/* Construct the key_method_2 message sent after TLS handshake.
 * Reference: openvpn/src/openvpn/ssl.c key_method_2_write
 * Wire format: [uint32 0(4)] [uint8 method=2(1)] [key_source(112)]
 *   [options: uint16 len][data] [username: uint16 len][data]
 *   [password: uint16 len][data] [peer_info: uint16 len][data]
 * Strings are length-prefixed (write_string style), NOT null-terminated.
 * Peer info is newline-separated key=value lines (push_peer_info format). */
int ovpn_build_km2_msg(ovpn_client_t *cli, uint8_t *buf, int buflen) {
    int pos = 0;

    /* Leading uint32 zero (padding) */
    if (pos + 4 > buflen) return -1;
    memset(buf + pos, 0, 4);
    pos += 4;

    /* Key method = 2 */
    if (pos + 1 > buflen) return -1;
    buf[pos++] = OVPN_KEY_METHOD_2;

    /* Generate random key source material */
    luat_crypto_trng((char *)cli->key_src.pre_master, OVPN_PRE_MASTER_LEN);
    luat_crypto_trng((char *)cli->key_src.client_random1, OVPN_RANDOM_LEN);
    luat_crypto_trng((char *)cli->key_src.client_random2, OVPN_RANDOM_LEN);

    if (pos + OVPN_PRE_MASTER_LEN + OVPN_RANDOM_LEN + OVPN_RANDOM_LEN > buflen) return -1;
    memcpy(buf + pos, cli->key_src.pre_master, OVPN_PRE_MASTER_LEN); pos += OVPN_PRE_MASTER_LEN;
    memcpy(buf + pos, cli->key_src.client_random1, OVPN_RANDOM_LEN); pos += OVPN_RANDOM_LEN;
    memcpy(buf + pos, cli->key_src.client_random2, OVPN_RANDOM_LEN); pos += OVPN_RANDOM_LEN;

    /* Options: write_string style = [uint16 len][data] */
    const char *options =
        "V4,dev-type tun,link-mtu 1541,tun-mtu 1500,proto UDPv4,"
        "auth SHA1,keysize 128,key-method 2,tls-client";
    int optlen = strlen(options) + 1; /* include null terminator in length */
    if (pos + 2 + optlen > buflen) return -1;
    buf[pos++] = optlen >> 8; buf[pos++] = optlen & 0xFF;
    memcpy(buf + pos, options, optlen); pos += optlen;

    /* Username (length-prefixed) */
    if (cli->username_buf && cli->username_len > 0) {
        int ulen = cli->username_len;
        if (pos + 2 + ulen > buflen) return -1;
        buf[pos++] = ulen >> 8; buf[pos++] = ulen & 0xFF;
        memcpy(buf + pos, cli->username_buf, ulen); pos += ulen;
    } else {
        if (pos + 2 > buflen) return -1;
        buf[pos++] = 0; buf[pos++] = 0; /* empty string: uint16 0 */
    }

    /* Password (length-prefixed) */
    if (cli->password_buf && cli->password_len > 0) {
        int plen = cli->password_len;
        if (pos + 2 + plen > buflen) return -1;
        buf[pos++] = plen >> 8; buf[pos++] = plen & 0xFF;
        memcpy(buf + pos, cli->password_buf, plen); pos += plen;
    } else {
        if (pos + 2 > buflen) return -1;
        buf[pos++] = 0; buf[pos++] = 0;
    }

    /* Peer info: advertise AES-256-GCM via NCP (IV_PROTO=2 = DATA_V2 only, no EKM) */
    const char *peer_info = "IV_VER=2.6.12\nIV_PLAT=linux\nIV_PROTO=2\nIV_NCP=2\nIV_CIPHERS=AES-256-GCM:AES-128-GCM";
    int pilen = strlen(peer_info);
    if (pos + 2 + pilen > buflen) return -1;
    buf[pos++] = pilen >> 8; buf[pos++] = pilen & 0xFF;
    memcpy(buf + pos, peer_info, pilen); pos += pilen;

    return pos;
}

/* Parse the server's key_method_2 response.
 * Reference: openvpn/src/openvpn/ssl.c key_method_2_read
 *
 * Server response format:
 *   [uint32 0(4)] [uint8 method=2(1)]
 *   [random1(32)] [random2(32)]           <- no pre_master from server
 *   [options_string(null-term)]
 */
int ovpn_parse_km2_reply(ovpn_client_t *cli, const uint8_t *data, int len) {
    int pos = 0;

    /* Skip leading uint32 0 */
    if (pos + 4 > len) return -1;
    pos += 4;

    /* Key method */
    if (pos + 1 > len) return -1;
    uint8_t method = data[pos++];
    if (method != OVPN_KEY_METHOD_2) {
        LLOGE("unexpected key method: %u", (unsigned)method);
        return -1;
    }

    /* Read server random1 */
    if (pos + OVPN_RANDOM_LEN > len) return -1;
    memcpy(cli->key_src.server_random1, data + pos, OVPN_RANDOM_LEN);
    pos += OVPN_RANDOM_LEN;

    /* Read server random2 */
    if (pos + OVPN_RANDOM_LEN > len) return -1;
    memcpy(cli->key_src.server_random2, data + pos, OVPN_RANDOM_LEN);
    pos += OVPN_RANDOM_LEN;

    /* Options string (null-terminated) — log for debugging */
    if (pos < len) {
        int opt_len = 0;
        while (pos + opt_len < len && data[pos + opt_len] != '\0') opt_len++;
        if (opt_len > 0) {
            if (cli->debug) {
                LLOGD("server options: %.*s", opt_len, data + pos);
            }
        }
    }

    return 0;
}

/* Read and process TLS application data after handshake.
 * Handles: key_method_2 reply, PUSH_REPLY, AUTH_FAILED */
void ovpn_process_tls_app_data(ovpn_client_t *cli) {
    uint8_t app_buf[1024];

    while (1) {
        int ret = mbedtls_ssl_read(&cli->ssl, app_buf, sizeof(app_buf) - 1);
        if (ret <= 0) {
            if (ret != MBEDTLS_ERR_SSL_WANT_READ && ret != MBEDTLS_ERR_SSL_WANT_WRITE) {
                if (ret != 0) {
                    LLOGD("TLS read returned %d", ret);
                }
            }
            break;
        }

        app_buf[ret] = '\0';

        /* State-dependent processing */
        switch (cli->km2_state) {
        case OVPN_KM2_WAIT_REPLY:
            /* Expecting server's key_method_2 response */
            if (ovpn_parse_km2_reply(cli, app_buf, ret) == 0) {
                cli->km2_state = OVPN_KM2_DONE;
                LLOGI("Key method 2 exchange complete");

                /* Derive data channel keys */
                ovpn_export_keys(cli);

                if (cli->event_cb && cli->data_key_ready) {
                    cli->event_cb(OVPN_EVENT_CONNECTED, cli->user_data);
                }

                /* Send PUSH_REQUEST (12 chars + null = 13 bytes) */
                cli->push_sent_ms = sys_now();
                mbedtls_ssl_write(&cli->ssl, (const unsigned char*)"PUSH_REQUEST\0", 13);
                LLOGI("Sent PUSH_REQUEST");
            } else {
                LLOGE("Failed to parse key_method_2 reply");
            }
            break;

        case OVPN_KM2_DONE:
            /* Expecting PUSH_REPLY (or AUTH_FAILED) */
            if (memcmp(app_buf, "PUSH_REPLY,", 11) == 0) {
                ovpn_process_push_reply(cli, (const char *)app_buf, ret);
                cli->state = OVPN_STATE_ACTIVE;
                if (cli->debug) {
                    LLOGD("Tunnel established, state=ACTIVE");
                }
            } else if (memcmp(app_buf, "AUTH_FAILED", 11) == 0) {
                LLOGE("Authentication failed");
                if (cli->event_cb) cli->event_cb(OVPN_EVENT_AUTH_FAILED, cli->user_data);
            } else if (memcmp(app_buf, "PUSH_REPLY", 10) == 0) {
                /* Some servers send "PUSH_REPLY" without comma + data, then
                 * the actual options follow.  Accept either form. */
                ovpn_process_push_reply(cli, (const char *)app_buf, ret);
                cli->state = OVPN_STATE_ACTIVE;
            }
            break;

        default:
            LLOGW("Unexpected TLS data in km2_state=%d", cli->km2_state);
            break;
        }
    }
}

/* ========== Key export ========== */

void ovpn_process_push_reply(ovpn_client_t *cli, const char *reply, int len) {
    if (!cli || !reply || len <= 0) return;

    /* Walk comma-separated options in the PUSH_REPLY message.
     * Format: "PUSH_REPLY,opt1,opt2,...,ifconfig a.b.c.d e.f.g.h,..." */
    const char *p = reply;
    while (p < reply + len) {
        /* Skip to next comma */
        const char *start = p;
        while (p < reply + len && *p != ',') p++;
        int opt_len = (int)(p - start);

        /* Check for ifconfig <ip> <gw> */
        if (opt_len > 9 && memcmp(start, "ifconfig", 8) == 0 && (start[8] == ' ' || start[8] == '\t')) {
            const char *val = start + 9;
            char ip_str[32] = {0}, gw_str[32] = {0};
            /* Copy to temp buf and null-terminate at option boundary */
            int remain = (int)(p - val);
            char tmp[64]; int tmplen = remain < 63 ? remain : 63;
            memcpy(tmp, val, tmplen); tmp[tmplen] = '\0';
            if (sscanf(tmp, "%31s %31s", ip_str, gw_str) >= 1) {
                ip4_addr_t ip_addr, gw_addr;
                if (ip4addr_aton(ip_str, &ip_addr)) {
                    ip4_addr_t mask;
                    IP4_ADDR(&mask, 255, 255, 255, 252); /* net30 topology */
                    if (ip4addr_aton(gw_str, &gw_addr)) {
                        netif_set_addr(&cli->netif, &ip_addr, &mask, &gw_addr);
                    } else {
                        ip4_addr_t def_gw;
                        IP4_ADDR(&def_gw, ip4_addr1(&ip_addr), ip4_addr2(&ip_addr), ip4_addr3(&ip_addr), 1);
                        netif_set_addr(&cli->netif, &ip_addr, &mask, &def_gw);
                    }
                    cli->push_reply.received = 1;
                    LLOGI("Tunnel IP: %s gw: %s", ip_str, gw_str);
                }
            }
            break; /* ifconfig should appear at most once */
        }

        /* Detect compression expectation */
        if (opt_len >= 8 && memcmp(start, "comp-lzo", 8) == 0) {
            cli->push_reply.use_comp_stub = 1;
        }
        if (opt_len >= 9 && memcmp(start, "compress ", 9) == 0) {
            cli->push_reply.use_comp_stub = 1;
        }

        /* Parse peer-id */
        if (opt_len > 8 && memcmp(start, "peer-id ", 8) == 0) {
            int pid = atoi(start + 8);
            if (pid >= 0 && pid <= 0xFFFFFF) {
                cli->peer_id = (uint32_t)pid;
                LLOGI("PUSH peer-id: %d", pid);
            }
        }

        /* Extract DNS servers from dhcp-option DNS and set per-adapter */
        if (opt_len > 16 && memcmp(start, "dhcp-option DNS ", 16) == 0) {
            const char *dns_str = start + 16;
            char dns_buf[32]; int dns_len = (int)(p - dns_str);
            if (dns_len > 0 && dns_len < (int)sizeof(dns_buf)) {
                memcpy(dns_buf, dns_str, dns_len); dns_buf[dns_len] = '\0';
                ip_addr_t dns_ip;
                if (ipaddr_aton(dns_buf, &dns_ip)) {
                    network_set_dns_server(cli->adapter_index, 0, (luat_ip_addr_t*)&dns_ip);
                    LLOGI("PUSH DNS[%d]: %s", cli->adapter_index, dns_buf);
                }
            }
        }

        /* Skip to next comma-delimited option */
        if (p < reply + len) p++;
    }

    if (cli->debug && !cli->push_reply.received) {
        LLOGD("PUSH_REPLY: %s", reply);  /* debug log full reply */
    }
}
