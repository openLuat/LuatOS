/*
 * OpenVPN TLS control-channel (mbedTLS) setup, BIO callbacks and feed loop
 * for LuatOS netdrv.
 *
 * Split from the original single-file OpenVPN client core; behavior unchanged.
 */

#include "ovpn/ovpn_client.h"
#include "ovpn/ovpn_ctl.h"
#include "ovpn/ovpn_tls.h"

#include <string.h>
#include "luat_crypto.h"

#define LUAT_LOG_TAG "openvpn"
#include "luat_log.h"

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

int ovpn_tls_init(ovpn_client_t *cli, const ovpn_client_cfg_t *cfg) {
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

#if MBEDTLS_VERSION_NUMBER >= 0x04000000
    ret = mbedtls_pk_parse_key(&cli->client_key, (const unsigned char *)cfg->client_key_pem,
                                cfg->client_key_len, NULL, 0);
#elif MBEDTLS_VERSION_NUMBER >= 0x03000000
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

#if MBEDTLS_VERSION_NUMBER < 0x04000000
    mbedtls_ssl_conf_rng(&cli->conf, mbedtls_ctr_drbg_random, &cli->drbg);
#endif

#if MBEDTLS_VERSION_NUMBER >= 0x03000000
    /* Force TLS 1.2 for maximum compatibility with OpenVPN servers */
    mbedtls_ssl_conf_max_tls_version(&cli->conf, MBEDTLS_SSL_VERSION_TLS1_2);
    mbedtls_ssl_conf_min_tls_version(&cli->conf, MBEDTLS_SSL_VERSION_TLS1_2);
#endif

    ret = mbedtls_ssl_setup(&cli->ssl, &cli->conf);
    if (ret) { LLOGE("ssl setup failed: %d", ret); return ret; }

    /* Set hostname for certificate verification (use remote IP as string) */
    char ip_str[16] = {0};
    ipaddr_ntoa_r(&cli->remote_ip, ip_str, sizeof(ip_str));
    mbedtls_ssl_set_hostname(&cli->ssl, ip_str);

    mbedtls_ssl_set_bio(&cli->ssl, cli, tls_send_cb, tls_recv_cb, NULL);

    cli->tls_ready = 0;
    return 0;
}

void ovpn_tls_free(ovpn_client_t *cli) {
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
 * Drive the TLS handshake and process post-handshake application data
 * (key_method_2 exchange, PUSH_REQUEST/PUSH_REPLY).
 *
 * Reference: openvpn/src/openvpn/ssl.c tls_process_state, tls_multi_process
 */
void ovpn_feed_tls(ovpn_client_t *cli, const uint8_t *data, int len) {
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
