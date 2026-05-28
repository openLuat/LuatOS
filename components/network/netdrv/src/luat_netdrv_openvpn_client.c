#include "luat_netdrv_openvpn_client.h"

#include <string.h>
#include "lwip/def.h"
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
#include "mbedtls/md5.h"
#include "mbedtls/sha1.h"

#define LUAT_LOG_TAG "openvpn"
#include "luat_log.h"
#include "luat_network_adapter.h"


#if MBEDTLS_VERSION_NUMBER < 0x03000000
#define mbedtls_sha1_starts mbedtls_sha1_starts_ret
#define mbedtls_sha1_update mbedtls_sha1_update_ret
#define mbedtls_sha1_finish mbedtls_sha1_finish_ret
#define mbedtls_md5_starts mbedtls_md5_starts_ret
#define mbedtls_md5_update mbedtls_md5_update_ret
#define mbedtls_md5_finish mbedtls_md5_finish_ret
#endif

/* Forward declarations */
static void ovpn_tls_free(ovpn_client_t *cli);
static void ovpn_export_keys(ovpn_client_t *cli);
static int  ovpn_build_km2_msg(ovpn_client_t *cli, uint8_t *buf, int buflen);
static int  ovpn_parse_km2_reply(ovpn_client_t *cli, const uint8_t *data, int len);
static void ovpn_process_push_reply(ovpn_client_t *cli, const char *reply, int len);
static void ovpn_client_stop_internal(ovpn_client_t *cli, int free_buffers);
static void ovpn_process_tls_app_data(ovpn_client_t *cli);
static void ovpn_retry_timer(void *arg);
static void ovpn_periodic_timer(void *arg);

/* lwIP compatibility defines for NETIF flags */
#ifndef NETIF_FLAG_POINTTOPOINT
#define NETIF_FLAG_POINTTOPOINT 0
#endif
#ifndef NETIF_FLAG_NOARP
#define NETIF_FLAG_NOARP 0
#endif

/* ========== Low-level protocol helpers ========== */

/* Compose opcode byte: (opcode << 3) | key_id */
static inline uint8_t ovpn_op_compose(uint8_t opcode, uint8_t key_id) {
    return (opcode << OVPN_OPCODE_SHIFT) | (key_id & OVPN_KEY_ID_MASK);
}

/* Extract opcode from first byte */
static inline uint8_t ovpn_op_extract(uint8_t byte) {
    return byte >> OVPN_OPCODE_SHIFT;
}

/* Extract key_id from first byte */
static inline uint8_t ovpn_key_id_extract(uint8_t byte) {
    return byte & OVPN_KEY_ID_MASK;
}

/* Write uint32 in network byte order */
static inline void ovpn_write_u32(uint8_t *dst, uint32_t val) {
    dst[0] = (uint8_t)(val >> 24);
    dst[1] = (uint8_t)(val >> 16);
    dst[2] = (uint8_t)(val >> 8);
    dst[3] = (uint8_t)(val);
}

/* Read uint32 in network byte order */
static inline uint32_t ovpn_read_u32(const uint8_t *src) {
    return ((uint32_t)src[0] << 24) | ((uint32_t)src[1] << 16) |
           ((uint32_t)src[2] << 8)  | (uint32_t)src[3];
}

/* Copy 8-byte session ID */
static inline void ovpn_copy_sid(uint8_t *dst, const uint8_t *src) {
    memcpy(dst, src, OVPN_SID_SIZE);
}

/* Build a complete OpenVPN packet header in buf, return total header size.
 * OpenVPN2 wire format (no tls-auth):
 *   [op(1)] [sid(8)] [ack_cnt(1)] [ack_ids(N*4)] [remote_sid(8) if ack_cnt>0] [pid(4)]
 * Verified against packet hex: count → ack_ids → remote_sid order */
static int ovpn_build_hdr(uint8_t *buf, int buflen,
                          uint8_t opcode, uint8_t key_id,
                          const uint8_t *src_sid,
                          const uint8_t *peer_sid,
                          const uint32_t *acks, int ack_count,
                          uint32_t packet_id, int include_pid)
{
    int pos = 0;
    if (pos >= buflen) return -1;

    buf[pos++] = ovpn_op_compose(opcode, key_id);
    if (pos + OVPN_SID_SIZE > buflen) return -1;
    memcpy(buf + pos, src_sid, OVPN_SID_SIZE);
    pos += OVPN_SID_SIZE;

    /* ACK list: count(1) + ack_ids(count*4) + [remote_sid(8) if count>0] */
    if (pos + 1 > buflen) return -1;
    buf[pos++] = (uint8_t)ack_count;
    for (int i = 0; i < ack_count; i++) {
        if (pos + 4 > buflen) return -1;
        ovpn_write_u32(buf + pos, acks[i]);
        pos += 4;
    }
    if (ack_count > 0) {
        if (pos + OVPN_SID_SIZE > buflen) return -1;
        memcpy(buf + pos, peer_sid, OVPN_SID_SIZE);
        pos += OVPN_SID_SIZE;
    }

    /* Packet ID after ack_list */
    if (include_pid) {
        if (pos + 4 > buflen) return -1;
        ovpn_write_u32(buf + pos, packet_id);
        pos += 4;
    }

    return pos;
}

/* Parse an incoming OpenVPN packet.
 * Returns 0 on success, -1 on error.
 * Out parameters are set only for valid packets. */
static int ovpn_parse_pkt(const uint8_t *data, int datalen,
                          uint8_t *opcode, uint8_t *key_id,
                          uint8_t *peer_sid,
                          uint32_t *acks, int *ack_count,
                          uint32_t *packet_id, int *has_packet_id,
                          const uint8_t **payload, int *payload_len)
{
    int pos = 0;
    if (datalen < 1) return -1;
    uint8_t ob = data[pos++];
    *opcode = ovpn_op_extract(ob);
    *key_id = ovpn_key_id_extract(ob);

    *ack_count = 0;
    *has_packet_id = 0;

    /* OpenVPN2 wire format (no tls-auth) ref: reliable.c reliable_ack_parse:
     *   [opcode(1)] [peer_sid(8)] [ack_list] [packet_id(4)] [payload]
     * where ack_list = ack_count(1) + ack_ids(count*4) + [remote_sid(8) if count>0] */

    /* Read peer session ID */
    if (pos + OVPN_SID_SIZE > datalen) return -1;
    if (peer_sid) memcpy(peer_sid, data + pos, OVPN_SID_SIZE);
    pos += OVPN_SID_SIZE;

    /* Read ACK list: count(1) + ack_ids(count*4) + [remote_sid(8) if count>0]
     * Wire order verified against packet hex: ack_ids BEFORE remote_sid */
    if (pos < datalen) {
        int ac = data[pos++];
        if (ac < 0 || ac > OVPN_MAX_ACKS_ACK) return -1;
        *ack_count = ac;
        for (int i = 0; i < ac; i++) {
            if (pos + 4 > datalen) return -1;
            if (acks) acks[i] = ovpn_read_u32(data + pos);
            pos += 4;
        }
        /* Skip remote_sid (8 bytes) when count > 0; it echoes our session_id back */
        if (ac > 0) {
            if (pos + OVPN_SID_SIZE > datalen) return -1;
            pos += OVPN_SID_SIZE;
        }
    }

    /* Read packet_id (present for all non-ACK_V1 control packets) */
    if (*opcode != OVPN_OP_ACK_V1 && pos + 4 <= datalen) {
        if (packet_id) *packet_id = ovpn_read_u32(data + pos);
        pos += 4;
        *has_packet_id = 1;
    }

    *payload = data + pos;
    *payload_len = datalen - pos;
    return 0;
}

/* Send a raw UDP packet to the remote server */
static int ovpn_send_udp(ovpn_client_t *cli, const uint8_t *data, int len) {
    if (!cli || !cli->netc || !data || len <= 0) return -1;
    uint32_t tx_len = 0;
    int ret = network_tx(cli->netc, data, len, 0,
                         &cli->remote_ip, cli->remote_port,
                         &tx_len, 0);
    return (ret >= 0 && tx_len == (uint32_t)len) ? 0 : -1;
}

/* ========== Reliable send window ========== */

static int rel_send_find_free(ovpn_client_t *cli) {
    for (int i = 0; i < OVPN_REL_SEND_SIZE; i++) {
        if (!cli->rel_send[i].in_use) return i;
    }
    return -1;
}

static int rel_send_find_by_id(ovpn_client_t *cli, uint32_t id) {
    for (int i = 0; i < OVPN_REL_SEND_SIZE; i++) {
        if (cli->rel_send[i].in_use && cli->rel_send[i].id == id) return i;
    }
    return -1;
}

/* Store a message in the reliable send window for potential retransmission */
static int rel_send_store(ovpn_client_t *cli, uint32_t id,
                          const uint8_t *data, int len, uint32_t now_ms)
{
    int slot = rel_send_find_free(cli);
    if (slot < 0) return -1;
    uint8_t *copy = (uint8_t *)luat_heap_malloc(len);
    if (!copy) return -1;
    memcpy(copy, data, len);
    cli->rel_send[slot].in_use = 1;
    cli->rel_send[slot].id = id;
    cli->rel_send[slot].len = (uint16_t)len;
    cli->rel_send[slot].data = copy;
    cli->rel_send[slot].retransmit_at = now_ms + OVPN_RETRANSMIT_BASE_MS;
    return 0;
}

/* Remove acknowledged messages from send window */
static void rel_send_ack(ovpn_client_t *cli, uint32_t ack_id) {
    for (int i = 0; i < OVPN_REL_SEND_SIZE; i++) {
        if (cli->rel_send[i].in_use && cli->rel_send[i].id == ack_id) {
            luat_heap_free(cli->rel_send[i].data);
            cli->rel_send[i].in_use = 0;
            cli->rel_send[i].data = NULL;
            return;
        }
    }
}

/* Check and retransmit expired packets */
static void rel_send_retransmit(ovpn_client_t *cli, uint32_t now_ms) {
    uint32_t backoff = OVPN_RETRANSMIT_BASE_MS;
    for (int i = 0; i < OVPN_REL_SEND_SIZE; i++) {
        if (!cli->rel_send[i].in_use) continue;
        if (now_ms >= cli->rel_send[i].retransmit_at) {
            if (cli->debug) {
                LLOGD("retransmit seq=%lu", (unsigned long)cli->rel_send[i].id);
            }
            ovpn_send_udp(cli, cli->rel_send[i].data, cli->rel_send[i].len);
            cli->rel_send[i].retransmit_at = now_ms + backoff;
            backoff = backoff < OVPN_RETRANSMIT_MAX_MS ? backoff * 2 : OVPN_RETRANSMIT_MAX_MS;
        }
    }
}

/* ========== Reliable recv window ========== */

static int rel_recv_find_by_id(ovpn_client_t *cli, uint32_t id) {
    for (int i = 0; i < OVPN_REL_RECV_SIZE; i++) {
        if (cli->rel_recv[i].in_use && cli->rel_recv[i].id == id) return i;
    }
    return -1;
}

/* Add a received message to the recv window (if within window) */
static int rel_recv_add(ovpn_client_t *cli, uint32_t id,
                        const uint8_t *data, int len)
{
    /* Reject packets older than window */
    if (id + OVPN_REL_RECV_SIZE <= cli->rel_recv_next) return -1;
    /* Reject duplicates */
    if (rel_recv_find_by_id(cli, id) >= 0) return -1;
    /* Find free slot */
    int slot = -1;
    for (int i = 0; i < OVPN_REL_RECV_SIZE; i++) {
        if (!cli->rel_recv[i].in_use) { slot = i; break; }
    }
    if (slot < 0) return -1;
    uint8_t *copy = (uint8_t *)luat_heap_malloc(len);
    if (!copy) return -1;
    memcpy(copy, data, len);
    cli->rel_recv[slot].in_use = 1;
    cli->rel_recv[slot].id = id;
    cli->rel_recv[slot].data = copy;
    cli->rel_recv[slot].len = (uint16_t)len;
    return 0;
}

/* Get the next in-order message from recv window */
static int rel_recv_next(ovpn_client_t *cli,
                         const uint8_t **data, int *len, uint32_t *id)
{
    for (int i = 0; i < OVPN_REL_RECV_SIZE; i++) {
        if (cli->rel_recv[i].in_use && cli->rel_recv[i].id == cli->rel_recv_next) {
            *data = cli->rel_recv[i].data;
            *len = cli->rel_recv[i].len;
            *id = cli->rel_recv[i].id;
            return 1;
        }
    }
    return 0;
}

/* Advance the recv window and free consumed slots */
static void rel_recv_advance(ovpn_client_t *cli, uint32_t id) {
    for (int i = 0; i < OVPN_REL_RECV_SIZE; i++) {
        if (cli->rel_recv[i].in_use && cli->rel_recv[i].id == id) {
            luat_heap_free(cli->rel_recv[i].data);
            cli->rel_recv[i].in_use = 0;
            cli->rel_recv[i].data = NULL;
            break;
        }
    }
    if (id >= cli->rel_recv_next) {
        cli->rel_recv_next = id + 1;
    }
}

/* ========== Send an OpenVPN control packet ========== */

/* Send a control packet with optional TLS payload.
 * The packet is stored in the reliable send window for retransmission. */
static int ovpn_send_ctrl(ovpn_client_t *cli, uint8_t opcode,
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
static int ovpn_send_ack(ovpn_client_t *cli) {
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
static void ovpn_queue_ack(ovpn_client_t *cli, uint32_t seq) {
    if (cli->pending_ack_count >= OVPN_MAX_ACKS) return;
    for (int i = 0; i < cli->pending_ack_count; i++) {
        if (cli->pending_acks[i] == seq) return;
    }
    cli->pending_acks[cli->pending_ack_count++] = seq;
}

/* ========== TLS BIO callbacks ========== */

/* Called by mbedtls when it has TLS record data to send.
 * We buffer it and send as CONTROL_V1 packets from the poll loop. */
static int tls_send_cb(void *ctx, const unsigned char *buf, size_t len) {
    ovpn_client_t *cli = (ovpn_client_t *)ctx;
    if (!cli || !cli->use_tls) return 0;

    if (cli->state < OVPN_STATE_RESET_ACKED) return 0;

    if (len > 1500) len = 1500;

    int ret = ovpn_send_ctrl(cli, OVPN_OP_CONTROL_V1, buf, (int)len);
    if (ret != 0) return 0;

    cli->stats.tx_pkts++;
    cli->stats.tx_bytes += len;
    return (int)len;
}

/* Called by mbedtls when it wants to read TLS record data.
 * Reads from persistent tls_buf (accumulates across CONTROL_V1 packets).
 * Returns WANT_READ on empty (never 0, which mbedtls treats as EOF). */
static int tls_recv_cb(void *ctx, unsigned char *buf, size_t len) {
    ovpn_client_t *cli = (ovpn_client_t *)ctx;
    if (!cli || cli->tls_buf_len == 0) return MBEDTLS_ERR_SSL_WANT_READ;
    int avail = cli->tls_buf_len - cli->tls_buf_offset;
    if (avail <= 0) return MBEDTLS_ERR_SSL_WANT_READ;
    int take = (avail < (int)len) ? avail : (int)len;
    memcpy(buf, cli->tls_buf + cli->tls_buf_offset, take);
    cli->tls_buf_offset += take;
    if (cli->tls_buf_offset >= cli->tls_buf_len) {
        cli->tls_buf_len = 0; cli->tls_buf_offset = 0;
    }
    return take;
}

/* ========== TLS setup ========== */

static int ovpn_entropy_source(void *data, unsigned char *output, size_t len, size_t *olen) {
    (void)data;
    int ret = luat_crypto_trng((char *)output, len);
    if (ret != 0) return MBEDTLS_ERR_ENTROPY_SOURCE_FAILED;
    *olen = len;
    return 0;
}

static int ovpn_tls_init(ovpn_client_t *cli, const ovpn_client_cfg_t *cfg) {
    mbedtls_ssl_init(&cli->ssl);
    mbedtls_ssl_config_init(&cli->conf);
    mbedtls_x509_crt_init(&cli->ca);
    mbedtls_x509_crt_init(&cli->client_cert);
    mbedtls_pk_init(&cli->client_key);
    mbedtls_ctr_drbg_init(&cli->drbg);
    mbedtls_entropy_init(&cli->entropy);

    int ret = mbedtls_entropy_add_source(&cli->entropy, ovpn_entropy_source, NULL, 32,
                                          MBEDTLS_ENTROPY_SOURCE_STRONG);
    if (ret) { LLOGE("entropy add failed: %d", ret); return ret; }

    const char *pers = "ovpn-tls";
    ret = mbedtls_ctr_drbg_seed(&cli->drbg, mbedtls_entropy_func, &cli->entropy,
                                 (const unsigned char *)pers, strlen(pers));
    if (ret) { LLOGE("drbg seed failed: %d", ret); return ret; }

    ret = mbedtls_x509_crt_parse(&cli->ca, (const unsigned char *)cfg->ca_cert_pem, cfg->ca_cert_len);
    if (ret) { LLOGE("ca cert parse failed: %d", ret); return ret; }

    ret = mbedtls_x509_crt_parse(&cli->client_cert, (const unsigned char *)cfg->client_cert_pem,
                                  cfg->client_cert_len);
    if (ret) { LLOGE("client cert parse failed: %d", ret); return ret; }

#if MBEDTLS_VERSION_NUMBER >= 0x03000000
    ret = mbedtls_pk_parse_key(&cli->client_key, (const unsigned char *)cfg->client_key_pem,
                                cfg->client_key_len, NULL, 0, mbedtls_ctr_drbg_random, &cli->drbg);
#else
    ret = mbedtls_pk_parse_key(&cli->client_key, (const unsigned char *)cfg->client_key_pem,
                                cfg->client_key_len, NULL, 0);
#endif
    if (ret) { LLOGE("client key parse failed: %d", ret); return ret; }

    /* TLS over stream (reliable control channel) */
    ret = mbedtls_ssl_config_defaults(&cli->conf,
                                       MBEDTLS_SSL_IS_CLIENT,
                                       MBEDTLS_SSL_TRANSPORT_STREAM,
                                       MBEDTLS_SSL_PRESET_DEFAULT);
    if (ret) { LLOGE("ssl config defaults failed: %d", ret); return ret; }

    mbedtls_ssl_conf_authmode(&cli->conf, MBEDTLS_SSL_VERIFY_REQUIRED);
    mbedtls_ssl_conf_ca_chain(&cli->conf, &cli->ca, NULL);

    ret = mbedtls_ssl_conf_own_cert(&cli->conf, &cli->client_cert, &cli->client_key);
    if (ret) { LLOGE("ssl conf cert failed: %d", ret); return ret; }

    mbedtls_ssl_conf_rng(&cli->conf, mbedtls_ctr_drbg_random, &cli->drbg);

#if MBEDTLS_VERSION_NUMBER >= 0x03000000 && defined(MBEDTLS_SSL_PROTO_TLS1_3)
    mbedtls_ssl_conf_max_tls_version(&cli->conf, MBEDTLS_SSL_VERSION_TLS1_3);
#endif

    ret = mbedtls_ssl_setup(&cli->ssl, &cli->conf);
    if (ret) { LLOGE("ssl setup failed: %d", ret); return ret; }

    mbedtls_ssl_set_bio(&cli->ssl, cli, tls_send_cb, tls_recv_cb, NULL);

    cli->tls_ready = 0;
    return 0;
}

static void ovpn_tls_free(ovpn_client_t *cli) {
    if (!cli || !cli->use_tls) return;
    mbedtls_ssl_free(&cli->ssl);
    mbedtls_ssl_config_free(&cli->conf);
    mbedtls_x509_crt_free(&cli->ca);
    mbedtls_x509_crt_free(&cli->client_cert);
    mbedtls_pk_free(&cli->client_key);
    mbedtls_ctr_drbg_free(&cli->drbg);
    mbedtls_entropy_free(&cli->entropy);
}

/* Manual HMAC-MD5 using raw mbedtls_md5 API (avoids mbedtls_md PSA glue).
 * HMAC(K,m) = H((K^opad) || H((K^ipad) || m)), block size 64.
 * Used by P_hash construction: A(1)=HMAC(secret,seed), out=HMAC(secret,A(n)+seed) */
static int hmac_md5_p(const uint8_t *secret, int sec_len,
                       const uint8_t *seed, int seed_len,
                       uint8_t *out, int out_len) {
    uint8_t k[64], h[16];
    mbedtls_md5_context ctx;
    /* Pad key to block size */
    memset(k, 0, 64);
    if (sec_len <= 64) memcpy(k, secret, sec_len);
    else { mbedtls_md5_init(&ctx); mbedtls_md5_starts(&ctx); mbedtls_md5_update(&ctx, secret, sec_len); mbedtls_md5_finish(&ctx, h); mbedtls_md5_free(&ctx); memcpy(k, h, 16); }
    /* A(1) = HMAC(secret, seed) = H(k^opad || H(k^ipad || seed)) */
    uint8_t ipad[64], opad[64];
    for (int i = 0; i < 64; i++) { ipad[i] = k[i] ^ 0x36; opad[i] = k[i] ^ 0x5c; }
    mbedtls_md5_init(&ctx);
    mbedtls_md5_starts(&ctx); mbedtls_md5_update(&ctx, ipad, 64); mbedtls_md5_update(&ctx, seed, seed_len); mbedtls_md5_finish(&ctx, h); /* h = H(ipad || seed) */
    mbedtls_md5_starts(&ctx); mbedtls_md5_update(&ctx, opad, 64); mbedtls_md5_update(&ctx, h, 16); mbedtls_md5_finish(&ctx, h); /* h = H(opad || h) = A(1) */
    int pos = 0;
    while (pos < out_len) {
        uint8_t block[16];
        /* HMAC(secret, A(n) || seed) */
        mbedtls_md5_starts(&ctx); mbedtls_md5_update(&ctx, ipad, 64); mbedtls_md5_update(&ctx, h, 16); mbedtls_md5_update(&ctx, seed, seed_len); mbedtls_md5_finish(&ctx, block);
        mbedtls_md5_starts(&ctx); mbedtls_md5_update(&ctx, opad, 64); mbedtls_md5_update(&ctx, block, 16); mbedtls_md5_finish(&ctx, block);
        int chunk = (out_len - pos > 16) ? 16 : (out_len - pos);
        memcpy(out + pos, block, chunk); pos += chunk;
        if (pos >= out_len) break;
        /* A(n+1) = HMAC(secret, A(n)) */
        mbedtls_md5_starts(&ctx); mbedtls_md5_update(&ctx, ipad, 64); mbedtls_md5_update(&ctx, h, 16); mbedtls_md5_finish(&ctx, h);
        mbedtls_md5_starts(&ctx); mbedtls_md5_update(&ctx, opad, 64); mbedtls_md5_update(&ctx, h, 16); mbedtls_md5_finish(&ctx, h);
    }
    mbedtls_md5_free(&ctx);
    return 1;
}

/* Manual HMAC-SHA1 using raw mbedtls_sha1 API */
static int hmac_sha1_p(const uint8_t *secret, int sec_len,
                        const uint8_t *seed, int seed_len,
                        uint8_t *out, int out_len) {
    uint8_t k[64], h[20];
    mbedtls_sha1_context ctx;
    memset(k, 0, 64);
    if (sec_len <= 64) memcpy(k, secret, sec_len);
    else { mbedtls_sha1_init(&ctx); mbedtls_sha1_starts(&ctx); mbedtls_sha1_update(&ctx, secret, sec_len); mbedtls_sha1_finish(&ctx, h); mbedtls_sha1_free(&ctx); memcpy(k, h, 20); }
    uint8_t ipad[64], opad[64];
    for (int i = 0; i < 64; i++) { ipad[i] = k[i] ^ 0x36; opad[i] = k[i] ^ 0x5c; }
    mbedtls_sha1_init(&ctx);
    mbedtls_sha1_starts(&ctx); mbedtls_sha1_update(&ctx, ipad, 64); mbedtls_sha1_update(&ctx, seed, seed_len); mbedtls_sha1_finish(&ctx, h);
    mbedtls_sha1_starts(&ctx); mbedtls_sha1_update(&ctx, opad, 64); mbedtls_sha1_update(&ctx, h, 20); mbedtls_sha1_finish(&ctx, h);
    int pos = 0;
    while (pos < out_len) {
        uint8_t block[20];
        mbedtls_sha1_starts(&ctx); mbedtls_sha1_update(&ctx, ipad, 64); mbedtls_sha1_update(&ctx, h, 20); mbedtls_sha1_update(&ctx, seed, seed_len); mbedtls_sha1_finish(&ctx, block);
        mbedtls_sha1_starts(&ctx); mbedtls_sha1_update(&ctx, opad, 64); mbedtls_sha1_update(&ctx, block, 20); mbedtls_sha1_finish(&ctx, block);
        int chunk = (out_len - pos > 20) ? 20 : (out_len - pos);
        memcpy(out + pos, block, chunk); pos += chunk;
        if (pos >= out_len) break;
        mbedtls_sha1_starts(&ctx); mbedtls_sha1_update(&ctx, ipad, 64); mbedtls_sha1_update(&ctx, h, 20); mbedtls_sha1_finish(&ctx, h);
        mbedtls_sha1_starts(&ctx); mbedtls_sha1_update(&ctx, opad, 64); mbedtls_sha1_update(&ctx, h, 20); mbedtls_sha1_finish(&ctx, h);
    }
    mbedtls_sha1_free(&ctx);
    return 1;
}

/* TLS 1.0 PRF: P_MD5(S1, seed) XOR P_SHA1(S2, seed)
 * S1 = first half of secret, S2 = second half (one byte longer if odd).
 * Reference: openvpn/src/openvpn/crypto_mbedtls.c ssl_tls1_PRF */
static int ovpn_prf(const uint8_t *secret, int sec_len, const char *label,
                    const uint8_t *s0, int s0l, const uint8_t *s1, int s1l,
                    const uint8_t *s2, int s2l, const uint8_t *s3, int s3l,
                    uint8_t *out, int out_len)
{
    uint8_t seed[256]; int seed_len = 0; int l = strlen(label);
    if (l + s0l + s1l + s2l + s3l > (int)sizeof(seed)) return 0;
    memcpy(seed + seed_len, label, l); seed_len += l;
    if (s0 && s0l > 0) { memcpy(seed + seed_len, s0, s0l); seed_len += s0l; }
    if (s1 && s1l > 0) { memcpy(seed + seed_len, s1, s1l); seed_len += s1l; }
    if (s2 && s2l > 0) { memcpy(seed + seed_len, s2, s2l); seed_len += s2l; }
    if (s3 && s3l > 0) { memcpy(seed + seed_len, s3, s3l); seed_len += s3l; }
    int half = sec_len / 2;
    int more = sec_len & 1;
    uint8_t tmp[OVPN_EKM_LEN];
    if (out_len > (int)sizeof(tmp)) return 0;
    /* P_MD5(first_half) → out, P_SHA1(second_half) → tmp, then XOR */
    hmac_md5_p(secret, half, seed, seed_len, out, out_len);
    hmac_sha1_p(secret + half, half + more, seed, seed_len, tmp, out_len);
    for (int i = 0; i < out_len; i++) out[i] ^= tmp[i];
    return 1;
}

/* ========== Key derivation via TLS EKM (RFC 5705) ========== */

/* Derive data channel keys using TLS keying material export.
 * Reference: openvpn/src/openvpn/ssl_backend.h EXPORT_KEY_DATA_LABEL
 *            openvpn/src/openvpn/crypto.c key_ctx_update_implicit_iv
 *
 * TLS EKM exports sizeof(key2.keys) = 256 bytes.
 * key2 layout for the client:
 *   keys[0] -> encrypt (send to server)
 *     .cipher = ekm[0..63]   (AES-256 uses first 32 bytes)
 *     .hmac   = ekm[64..127]  (implicit IV source)
 *   keys[1] -> decrypt (receive from server)
 *     .cipher = ekm[128..191]
 *     .hmac   = ekm[192..255]
 *
 * For non-epoch AEAD (AES-256-GCM, 12-byte IV):
 *   implicit_iv[0..3] = 0
 *   implicit_iv[4..11] = hmac[0..7] (first 8 bytes of HMAC key material)
 *   Final IV = implicit_iv XOR [packet_id(4) + 0(8)]  (XOR with 0 is identity)
 *            = [packet_id(4)][hmac[0..7](8)]
 */
static void ovpn_export_keys(ovpn_client_t *cli) {
    if (!cli || !cli->tls_ready) return;

#if defined(MBEDTLS_SSL_KEYING_MATERIAL_EXPORT)
    uint8_t ekm[OVPN_EKM_LEN];
    int ret = mbedtls_ssl_export_keying_material(&cli->ssl,
                                                  ekm, sizeof(ekm),
                                                  "EXPORTER-OpenVPN-datakeys", 23,
                                                  NULL, 0, 0);
    if (ret != 0) {
        LLOGE("key export failed: %d", ret);
        return;
    }

    /* Set AES-256-GCM encrypt/decrypt keys */
    mbedtls_gcm_init(&cli->gcm_enc);
    mbedtls_gcm_init(&cli->gcm_dec);
    ret = mbedtls_gcm_setkey(&cli->gcm_enc, MBEDTLS_CIPHER_ID_AES, ekm, 256);
    if (ret) { LLOGE("gcm enc setkey failed: %d", ret); return; }
    ret = mbedtls_gcm_setkey(&cli->gcm_dec, MBEDTLS_CIPHER_ID_AES, ekm + 128, 256);
    if (ret) { LLOGE("gcm dec setkey failed: %d", ret); return; }

    /* Encrypt implicit IV: from keys[0].hmac[0..7] = ekm[64..71] */
    memset(cli->enc_implicit_iv, 0, OVPN_AEAD_IV_LEN);
    memcpy(cli->enc_implicit_iv + 4, ekm + 64, OVPN_NONCE_TAIL_LEN);

    /* Decrypt implicit IV: from keys[1].hmac[0..7] = ekm[192..199] */
    memset(cli->dec_implicit_iv, 0, OVPN_AEAD_IV_LEN);
    memcpy(cli->dec_implicit_iv + 4, ekm + 192, OVPN_NONCE_TAIL_LEN);

    cli->key_id = 0;
    /* Random starting seq to avoid replay issues on reconnection */
    luat_crypto_trng((char *)&cli->data_tx_seq, 4);
    cli->data_rx_seq = 0;
    cli->data_key_ready = 1;

    LLOGI("Data channel keys derived (AES-256-GCM via TLS EKM)");
#else
    LLOGI("PRF fallback: OpenVPN TLS 1.0 PRF (MD5+SHA1)");
    /* PRF fallback: reference openvpn/src/openvpn/ssl.c generate_key_expansion_openvpn_prf */
    uint8_t master[48];
    uint8_t ekm[OVPN_EKM_LEN];
    if (ovpn_prf(cli->key_src.pre_master, OVPN_PRE_MASTER_LEN, "OpenVPN master secret",
                 cli->key_src.client_random1, OVPN_RANDOM_LEN,
                 cli->key_src.server_random1, OVPN_RANDOM_LEN,
                 NULL, 0, NULL, 0, master, 48) &&
        ovpn_prf(master, 48, "OpenVPN key expansion",
                 cli->key_src.client_random2, OVPN_RANDOM_LEN,
                 cli->key_src.server_random2, OVPN_RANDOM_LEN,
                 cli->session_id, OVPN_SID_SIZE,
                 cli->peer_session_id, OVPN_SID_SIZE,
                 ekm, sizeof(ekm))) {
        mbedtls_gcm_init(&cli->gcm_enc); mbedtls_gcm_init(&cli->gcm_dec);
        mbedtls_gcm_setkey(&cli->gcm_enc, MBEDTLS_CIPHER_ID_AES, ekm, 256);
        mbedtls_gcm_setkey(&cli->gcm_dec, MBEDTLS_CIPHER_ID_AES, ekm + 128, 256);
        memset(cli->enc_implicit_iv, 0, OVPN_AEAD_IV_LEN);
        memcpy(cli->enc_implicit_iv + 4, ekm + 64, OVPN_NONCE_TAIL_LEN);
        memset(cli->dec_implicit_iv, 0, OVPN_AEAD_IV_LEN);
        memcpy(cli->dec_implicit_iv + 4, ekm + 192, OVPN_NONCE_TAIL_LEN);
        cli->key_id = 0; luat_crypto_trng((char *)&cli->data_tx_seq, 4); cli->data_rx_seq = 0;
        cli->data_key_ready = 1;
        LLOGI("Data channel keys derived (OpenVPN PRF fallback)");
    } else {
        LLOGE("PRF key derivation failed");
    }
#endif
}

/* ========== Key method 2 exchange ========== */

/* Construct the key_method_2 message sent after TLS handshake.
 * Reference: openvpn/src/openvpn/ssl.c key_method_2_write
 * Wire format: [uint32 0(4)] [uint8 method=2(1)] [key_source(112)]
 *   [options: uint16 len][data] [username: uint16 len][data]
 *   [password: uint16 len][data] [peer_info: uint16 len][data]
 * Strings are length-prefixed (write_string style), NOT null-terminated.
 * Peer info is newline-separated key=value lines (push_peer_info format). */
static int ovpn_build_km2_msg(ovpn_client_t *cli, uint8_t *buf, int buflen) {
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
static int ovpn_parse_km2_reply(ovpn_client_t *cli, const uint8_t *data, int len) {
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
            LLOGI("server options: %.*s", opt_len, data + pos);
        }
    }

    return 0;
}

/* ========== TLS application data processing ========== */

/* Drive the TLS handshake and process post-handshake application data
 * (key_method_2 exchange, PUSH_REQUEST/PUSH_REPLY).
 *
 * Reference: openvpn/src/openvpn/ssl.c tls_process_state, tls_multi_process
 */
static void ovpn_feed_tls(ovpn_client_t *cli, const uint8_t *data, int len) {
    if (!cli) return;

    /* Append data to persistent buffer */
    if (len > 0 && cli->tls_buf_len + len <= (int)sizeof(cli->tls_buf)) {
        if (cli->tls_buf_offset >= cli->tls_buf_len) {
            cli->tls_buf_len = 0; cli->tls_buf_offset = 0;
        }
        memcpy(cli->tls_buf + cli->tls_buf_len, data, len);
        cli->tls_buf_len += len;
    }

    /* Drive handshake loop: continue on WANT_WRITE, stop on WANT_READ or done */
    int ret, zero_count = 0;
    do {
        ret = mbedtls_ssl_handshake(&cli->ssl);
        if (ret == MBEDTLS_ERR_SSL_WANT_READ) break;
        if (ret == MBEDTLS_ERR_SSL_WANT_WRITE) continue;
        if (ret == 0) {
            if (!cli->tls_handshake_done) {
                cli->tls_handshake_done = 1;
                cli->tls_ready = 1;
                cli->km2_state = OVPN_KM2_SENDING;
                cli->push_sent_ms = sys_now() + 10;
                LLOGI("TLS handshake completed");
                if (cli->event_cb)
                    cli->event_cb(OVPN_EVENT_TLS_HANDSHAKE_OK, cli->user_data);
            }
            if (++zero_count > 1) break;
            continue;
        }
        LLOGE("TLS handshake error: %d", ret);
        cli->handshake_failed = 1;
        if (cli->event_cb)
            cli->event_cb(OVPN_EVENT_TLS_HANDSHAKE_FAIL, cli->user_data);
        return;
    } while (1);

    /* Post-handshake: KM2 sent from timer tick (ovpn_client_timer_tick) */
}

/* Read and process TLS application data after handshake.
 * Handles: key_method_2 reply, PUSH_REPLY, AUTH_FAILED */
static void ovpn_process_tls_app_data(ovpn_client_t *cli) {
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
        LLOGI("TLS app data (%d bytes): %s", ret, (const char *)app_buf);

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

static void ovpn_process_push_reply(ovpn_client_t *cli, const char *reply, int len) {
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

    if (!cli->push_reply.received) {
        LLOGW("PUSH_REPLY: %s", reply);  /* debug log full reply */
    }
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
 * Check whether at least one non-OpenVPN netdrv adapter is online.
 *
 * Uses luat_netdrv_is_ready() which understands per-adapter semantics:
 * GPRS → mobile registration check, ETH → link + IP, etc.
 * Returns 1 if any transport adapter is ready, 0 otherwise.
 */
static int ovpn_transport_is_online(ovpn_client_t *cli) {
    for (int i = 0; i < NW_ADAPTER_QTY; i++) {
        if (i == cli->adapter_index) continue;   /* skip our own virtual tun */
        if (luat_netdrv_is_ready(i)) return 1;
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
        LLOGW("transport offline, waiting %u ms before next retry", (unsigned)delay);
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
