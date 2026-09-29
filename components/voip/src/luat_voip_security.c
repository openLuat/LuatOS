/* SDES and DTLS-SRTP share one authenticated SRTP packet path.
 * The VoIP task owns runtime state; Lua owns only reference-counted handles. */
#include "luat_base.h"
#include "luat_voip_security.h"

#ifdef LUAT_USE_SRTP
#include "luat_malloc.h"
#include "luat_crypto.h"
#include "luat_mcu.h"
#include "luat_voip_event.h"
#include "srtp.h"
#include "mbedtls/base64.h"
#include "mbedtls/platform_util.h"
#include <limits.h>
#include <string.h>

#ifdef LUAT_USE_DTLS_SRTP
#include "mbedtls/version.h"
#include "mbedtls/ssl.h"
#include "mbedtls/ssl_ciphersuites.h"
#include "mbedtls/ctr_drbg.h"
#include "mbedtls/ecp.h"
#include "mbedtls/pk.h"
#include "mbedtls/x509_crt.h"
#include "mbedtls/md.h"
#endif

struct luat_voip_security_identity {
    volatile uint32_t references;
#ifdef LUAT_USE_DTLS_SRTP
    mbedtls_pk_context key;
    mbedtls_x509_crt certificate;
    uint8_t fingerprint[32];
#endif
};

struct luat_voip_security {
    volatile uint32_t references;
    volatile uint32_t state;
    luat_voip_security_mode_t mode;
    int error;
    uint8_t remote_configured;
    uint8_t local_key[LUAT_VOIP_SECURITY_KEY_BYTES];
    uint8_t remote_key[LUAT_VOIP_SECURITY_KEY_BYTES];
    srtp_t outbound;
    srtp_t inbound;
#ifdef LUAT_USE_DTLS_SRTP
    luat_voip_security_identity_t *identity;
    mbedtls_ssl_context ssl;
    mbedtls_ssl_config config;
    mbedtls_ctr_drbg_context drbg;
    luat_voip_security_send_t send;
    void *send_opaque;
    uint8_t *rx_datagram;
    size_t rx_length;
    size_t rx_offset;
    uint64_t started_ms;
    uint64_t timer_started_ms;
    uint32_t timer_intermediate_ms;
    uint32_t timer_final_ms;
    uint8_t remote_fingerprint[32];
    uint8_t exported_keys[60];
    uint8_t dtls_client;
    uint8_t peer_verified;
    uint8_t keys_exported;
    uint8_t tls_initialized;
#endif
};

/* Initialization is process-wide; individual sessions are never shared. */
static volatile uint32_t s_srtp_initialization;

static void security_retain(volatile uint32_t *references)
{
#ifdef _MSC_VER
    _InterlockedIncrement((volatile long *)references);
#else
    __sync_add_and_fetch(references, 1U);
#endif
}

static int security_release(volatile uint32_t *references)
{
#ifdef _MSC_VER
    return _InterlockedDecrement((volatile long *)references) == 0;
#else
    return __sync_sub_and_fetch(references, 1U) == 0;
#endif
}

static void security_state_set(luat_voip_security_t *ctx, luat_voip_security_state_t state)
{
    uint32_t old;
    do { old = voip_event_load(&ctx->state); }
    while (voip_event_cas(&ctx->state, old, (uint32_t)state) != old);
}

static int security_fail(luat_voip_security_t *ctx, int error)
{
    ctx->error = error;
    security_state_set(ctx, LUAT_VOIP_SECURITY_FAILED);
    return error;
}

static int security_srtp_init(void)
{
    uint32_t state = voip_event_cas(&s_srtp_initialization, 0, 1);
    if (state == 0) {
        state = srtp_init() == srtp_err_status_ok ? 2U : 3U;
        voip_event_cas(&s_srtp_initialization, 1, state);
    }
    if (state == 2) return LUAT_VOIP_SECURITY_OK;
    return state == 1 ? LUAT_VOIP_SECURITY_E_STATE : LUAT_VOIP_SECURITY_E_CRYPTO;
}

static int security_srtp_start(luat_voip_security_t *ctx)
{
    srtp_policy_t policy;
    int result = security_srtp_init();
    if (result) return result;
    memset(&policy, 0, sizeof(policy));
    srtp_crypto_policy_set_aes_cm_128_hmac_sha1_80(&policy.rtp);
    srtp_crypto_policy_set_aes_cm_128_hmac_sha1_80(&policy.rtcp);
    policy.ssrc.type = ssrc_any_outbound;
    policy.key = ctx->local_key;
    policy.window_size = 128;
    policy.allow_repeat_tx = 0;
    if (srtp_create(&ctx->outbound, &policy) != srtp_err_status_ok)
        return LUAT_VOIP_SECURITY_E_CRYPTO;
    policy.ssrc.type = ssrc_any_inbound;
    policy.key = ctx->remote_key;
    if (srtp_create(&ctx->inbound, &policy) != srtp_err_status_ok) {
        srtp_dealloc(ctx->outbound);
        ctx->outbound = NULL;
        return LUAT_VOIP_SECURITY_E_CRYPTO;
    }
    return LUAT_VOIP_SECURITY_OK;
}

#ifdef LUAT_USE_DTLS_SRTP
static int security_entropy(void *opaque, unsigned char *output, size_t length)
{
    (void)opaque;
    return luat_crypto_trng((char *)output, length) == 0 ? 0 : MBEDTLS_ERR_CTR_DRBG_ENTROPY_SOURCE_FAILED;
}

static int security_sha256(const uint8_t *data, size_t length, uint8_t digest[32])
{
    const mbedtls_md_info_t *algorithm = mbedtls_md_info_from_type(MBEDTLS_MD_SHA256);
    return algorithm ? mbedtls_md(algorithm, data, length, digest) : -1;
}

static void security_fingerprint_text(const uint8_t digest[32], char *text)
{
    static const char hex[] = "0123456789ABCDEF";
    unsigned i;
    for (i = 0; i < 32; i++) {
        text[i * 3] = hex[digest[i] >> 4];
        text[i * 3 + 1] = hex[digest[i] & 15];
        text[i * 3 + 2] = i == 31 ? '\0' : ':';
    }
}

static int security_hex(char c)
{
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    return -1;
}

static int security_parse_fingerprint(const char *text, uint8_t digest[32])
{
    unsigned i;
    if (!text || strlen(text) != 95) return LUAT_VOIP_SECURITY_E_INVALID;
    for (i = 0; i < 32; i++) {
        int high = security_hex(text[i * 3]);
        int low = security_hex(text[i * 3 + 1]);
        if (high < 0 || low < 0 || (i < 31 && text[i * 3 + 2] != ':'))
            return LUAT_VOIP_SECURITY_E_INVALID;
        digest[i] = (uint8_t)((high << 4) | low);
    }
    return LUAT_VOIP_SECURITY_OK;
}

static int security_identity_generate(luat_voip_security_identity_t *identity)
{
    mbedtls_ctr_drbg_context *drbg;
    mbedtls_x509write_cert certificate;
    mbedtls_mpi serial;
    uint8_t serial_bytes[16];
    uint8_t *der;
    int result = LUAT_VOIP_SECURITY_E_MEMORY;
    static const unsigned char personalization[] = "LuatOS DTLS-SRTP identity";

    drbg = luat_heap_calloc(1, sizeof(*drbg));
    der = luat_heap_malloc(2048);
    if (!drbg || !der) {
        if (drbg) luat_heap_free(drbg);
        if (der) luat_heap_free(der);
        return result;
    }
    mbedtls_ctr_drbg_init(drbg);
    mbedtls_x509write_crt_init(&certificate);
    mbedtls_mpi_init(&serial);
    result = LUAT_VOIP_SECURITY_E_CRYPTO;
    if (mbedtls_ctr_drbg_seed(drbg, security_entropy, NULL,
            personalization, sizeof(personalization) - 1)) goto done;
    if (mbedtls_pk_setup(&identity->key, mbedtls_pk_info_from_type(MBEDTLS_PK_ECKEY))) goto done;
    if (mbedtls_ecp_gen_key(MBEDTLS_ECP_DP_SECP256R1, mbedtls_pk_ec(identity->key),
            mbedtls_ctr_drbg_random, drbg)) goto done;
    if (mbedtls_ctr_drbg_random(drbg, serial_bytes, sizeof(serial_bytes))) goto done;
    serial_bytes[0] = (uint8_t)((serial_bytes[0] & 0x7FU) | 1U);
    if (mbedtls_mpi_read_binary(&serial, serial_bytes, sizeof(serial_bytes))) goto done;
    mbedtls_x509write_crt_set_version(&certificate, MBEDTLS_X509_CRT_VERSION_3);
    mbedtls_x509write_crt_set_md_alg(&certificate, MBEDTLS_MD_SHA256);
    mbedtls_x509write_crt_set_subject_key(&certificate, &identity->key);
    mbedtls_x509write_crt_set_issuer_key(&certificate, &identity->key);
    if (mbedtls_x509write_crt_set_serial(&certificate, &serial) ||
            mbedtls_x509write_crt_set_subject_name(&certificate, "CN=LuatOS DTLS-SRTP") ||
            mbedtls_x509write_crt_set_issuer_name(&certificate, "CN=LuatOS DTLS-SRTP") ||
            mbedtls_x509write_crt_set_validity(&certificate, "20000101000000", "20991231235959") ||
            mbedtls_x509write_crt_set_basic_constraints(&certificate, 0, -1) ||
            mbedtls_x509write_crt_set_key_usage(&certificate, MBEDTLS_X509_KU_DIGITAL_SIGNATURE)) goto done;
    {
        int length = mbedtls_x509write_crt_der(&certificate, der, 2048,
                mbedtls_ctr_drbg_random, drbg);
        if (length <= 0 || mbedtls_x509_crt_parse_der(&identity->certificate,
                der + 2048 - length, (size_t)length)) goto done;
        if (security_sha256(der + 2048 - length, (size_t)length, identity->fingerprint)) goto done;
    }
    result = LUAT_VOIP_SECURITY_OK;
done:
    mbedtls_platform_zeroize(serial_bytes, sizeof(serial_bytes));
    mbedtls_platform_zeroize(der, 2048);
    luat_heap_free(der);
    mbedtls_mpi_free(&serial);
    mbedtls_x509write_crt_free(&certificate);
    mbedtls_ctr_drbg_free(drbg);
    luat_heap_free(drbg);
    return result;
}

static void security_set_timer(void *opaque, uint32_t intermediate, uint32_t final)
{
    luat_voip_security_t *ctx = opaque;
    ctx->timer_started_ms = luat_mcu_tick64_ms();
    ctx->timer_intermediate_ms = intermediate;
    ctx->timer_final_ms = final;
}

static int security_get_timer(void *opaque)
{
    luat_voip_security_t *ctx = opaque;
    uint64_t elapsed;
    if (!ctx->timer_final_ms) return -1;
    elapsed = luat_mcu_tick64_ms() - ctx->timer_started_ms;
    if (elapsed >= ctx->timer_final_ms) return 2;
    if (elapsed >= ctx->timer_intermediate_ms) return 1;
    return 0;
}

static int security_send(void *opaque, const unsigned char *data, size_t length)
{
    luat_voip_security_t *ctx = opaque;
    int result;
    if (!ctx->send || length > INT_MAX) return MBEDTLS_ERR_SSL_INTERNAL_ERROR;
    result = ctx->send(ctx->send_opaque, data, length);
    if (result == 0) return MBEDTLS_ERR_SSL_WANT_WRITE;
    return result == (int)length ? result : MBEDTLS_ERR_SSL_INTERNAL_ERROR;
}

static int security_receive(void *opaque, unsigned char *data, size_t capacity)
{
    luat_voip_security_t *ctx = opaque;
    size_t length;
    if (!ctx->rx_length) return MBEDTLS_ERR_SSL_WANT_READ;
    length = ctx->rx_length - ctx->rx_offset;
    /* A DTLS BIO returns a whole datagram, never truncates it to a valid prefix. */
    if (length > capacity) {
        ctx->rx_length = ctx->rx_offset = 0;
        return MBEDTLS_ERR_SSL_BUFFER_TOO_SMALL;
    }
    memcpy(data, ctx->rx_datagram + ctx->rx_offset, length);
    ctx->rx_length = ctx->rx_offset = 0;
    return (int)length;
}

static int security_verify_peer(void *opaque, mbedtls_x509_crt *certificate,
        int depth, uint32_t *flags)
{
    luat_voip_security_t *ctx = opaque;
    uint8_t digest[32];
    unsigned difference = 0, i;
    /* The authenticated SDP fingerprint, rather than a CA chain, is our trust
     * anchor. The worker also requires a matching leaf before enabling SRTP. */
    *flags = 0;
    if (depth != 0) return 0;
    ctx->peer_verified = 0;
    if (security_sha256(certificate->raw.p, certificate->raw.len, digest)) {
        *flags = MBEDTLS_X509_BADCERT_OTHER;
        return MBEDTLS_ERR_X509_FATAL_ERROR;
    }
    for (i = 0; i < sizeof(digest); i++) difference |= digest[i] ^ ctx->remote_fingerprint[i];
    mbedtls_platform_zeroize(digest, sizeof(digest));
    if (difference) {
        ctx->error = LUAT_VOIP_SECURITY_E_FINGERPRINT;
        *flags = MBEDTLS_X509_BADCERT_OTHER;
        return MBEDTLS_ERR_X509_FATAL_ERROR;
    }
    ctx->peer_verified = 1;
    return 0;
}

static int security_export(luat_voip_security_t *ctx, const unsigned char *secret,
        size_t secret_length, const unsigned char client_random[32],
        const unsigned char server_random[32], mbedtls_tls_prf_types prf)
{
    unsigned char randoms[64];
    int result;
    memcpy(randoms, client_random, 32);
    memcpy(randoms + 32, server_random, 32);
    /* RFC 5764 / RFC 5705: no context is supplied (not an encoded empty context). */
    result = mbedtls_ssl_tls_prf(prf, secret, secret_length, "EXTRACTOR-dtls_srtp",
            randoms, sizeof(randoms), ctx->exported_keys, sizeof(ctx->exported_keys));
    mbedtls_platform_zeroize(randoms, sizeof(randoms));
    ctx->keys_exported = result == 0;
    return result;
}

#if MBEDTLS_VERSION_MAJOR >= 3
static void security_export_callback(void *opaque, mbedtls_ssl_key_export_type type,
        const unsigned char *secret, size_t secret_length,
        const unsigned char client_random[32], const unsigned char server_random[32],
        mbedtls_tls_prf_types prf)
{
    luat_voip_security_t *ctx = opaque;
    if (type != MBEDTLS_SSL_KEY_EXPORT_TLS12_MASTER_SECRET) return;
    if (security_export(ctx, secret, secret_length, client_random, server_random, prf))
        ctx->error = LUAT_VOIP_SECURITY_E_CRYPTO;
}
#else
static int security_export_callback(void *opaque, const unsigned char *secret,
        const unsigned char *key_block, size_t mac_length, size_t key_length,
        size_t iv_length, const unsigned char client_random[32],
        const unsigned char server_random[32], mbedtls_tls_prf_types prf)
{
    (void)key_block; (void)mac_length; (void)key_length; (void)iv_length;
    return security_export(opaque, secret, 48, client_random, server_random, prf);
}
#endif

static int security_dtls_start(luat_voip_security_t *ctx)
{
    static const unsigned char personalization[] = "LuatOS DTLS-SRTP session";
    static const mbedtls_ssl_srtp_profile profiles[] = {
        MBEDTLS_TLS_SRTP_AES128_CM_HMAC_SHA1_80, MBEDTLS_TLS_SRTP_UNSET
    };
    static const int ciphersuites[] = {
        MBEDTLS_TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256,
        MBEDTLS_TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256, 0
    };
    int result;
    if (!ctx->identity || !ctx->send) return LUAT_VOIP_SECURITY_E_INVALID;
    ctx->rx_datagram = luat_heap_malloc(LUAT_VOIP_SECURITY_DATAGRAM_MAX);
    if (!ctx->rx_datagram) return LUAT_VOIP_SECURITY_E_MEMORY;
    if (mbedtls_ctr_drbg_seed(&ctx->drbg, security_entropy, NULL,
            personalization, sizeof(personalization) - 1)) return LUAT_VOIP_SECURITY_E_CRYPTO;
    result = mbedtls_ssl_config_defaults(&ctx->config,
            ctx->dtls_client ? MBEDTLS_SSL_IS_CLIENT : MBEDTLS_SSL_IS_SERVER,
            MBEDTLS_SSL_TRANSPORT_DATAGRAM, MBEDTLS_SSL_PRESET_DEFAULT);
    if (result) return LUAT_VOIP_SECURITY_E_CRYPTO;
#if MBEDTLS_VERSION_MAJOR >= 3
    mbedtls_ssl_conf_min_tls_version(&ctx->config, MBEDTLS_SSL_VERSION_TLS1_2);
    mbedtls_ssl_conf_max_tls_version(&ctx->config, MBEDTLS_SSL_VERSION_TLS1_2);
#else
    mbedtls_ssl_conf_min_version(&ctx->config, MBEDTLS_SSL_MAJOR_VERSION_3, MBEDTLS_SSL_MINOR_VERSION_3);
    mbedtls_ssl_conf_max_version(&ctx->config, MBEDTLS_SSL_MAJOR_VERSION_3, MBEDTLS_SSL_MINOR_VERSION_3);
#endif
    mbedtls_ssl_conf_ciphersuites(&ctx->config, ciphersuites);
    mbedtls_ssl_conf_rng(&ctx->config, mbedtls_ctr_drbg_random, &ctx->drbg);
    /* OPTIONAL makes self-signed certificates reach our fingerprint verifier
     * without a CA trust store. Missing or mismatching leaf never becomes READY. */
    mbedtls_ssl_conf_authmode(&ctx->config, MBEDTLS_SSL_VERIFY_OPTIONAL);
    mbedtls_ssl_conf_verify(&ctx->config, security_verify_peer, ctx);
    if (mbedtls_ssl_conf_own_cert(&ctx->config, &ctx->identity->certificate, &ctx->identity->key))
        return LUAT_VOIP_SECURITY_E_CRYPTO;
    if (mbedtls_ssl_conf_dtls_srtp_protection_profiles(&ctx->config, profiles))
        return LUAT_VOIP_SECURITY_E_PROFILE;
    mbedtls_ssl_conf_srtp_mki_value_supported(&ctx->config, MBEDTLS_SSL_DTLS_SRTP_MKI_UNSUPPORTED);
    mbedtls_ssl_conf_handshake_timeout(&ctx->config, 500, 4000);
#if defined(MBEDTLS_SSL_SESSION_TICKETS) && defined(MBEDTLS_SSL_CLI_C)
    mbedtls_ssl_conf_session_tickets(&ctx->config, MBEDTLS_SSL_SESSION_TICKETS_DISABLED);
#endif
#if defined(MBEDTLS_SSL_RENEGOTIATION)
    mbedtls_ssl_conf_renegotiation(&ctx->config, MBEDTLS_SSL_RENEGOTIATION_DISABLED);
#endif
#if defined(MBEDTLS_SSL_SRV_C) && defined(MBEDTLS_SSL_DTLS_HELLO_VERIFY)
    /* A dialog has exactly one SIP-authenticated remote media endpoint. No UDP
     * listener allocates sessions here, so cookie-based admission is unnecessary. */
    mbedtls_ssl_conf_dtls_cookies(&ctx->config, NULL, NULL, NULL);
#endif
#if MBEDTLS_VERSION_MAJOR < 3
    mbedtls_ssl_conf_export_keys_ext_cb(&ctx->config, security_export_callback, ctx);
#endif
    if (mbedtls_ssl_setup(&ctx->ssl, &ctx->config)) return LUAT_VOIP_SECURITY_E_CRYPTO;
    ctx->tls_initialized = 1;
#if MBEDTLS_VERSION_MAJOR >= 3
    mbedtls_ssl_set_export_keys_cb(&ctx->ssl, security_export_callback, ctx);
#endif
    mbedtls_ssl_set_bio(&ctx->ssl, ctx, security_send, security_receive, NULL);
    mbedtls_ssl_set_timer_cb(&ctx->ssl, ctx, security_set_timer, security_get_timer);
    mbedtls_ssl_set_mtu(&ctx->ssl, 1200);
    ctx->started_ms = luat_mcu_tick64_ms();
    security_state_set(ctx, LUAT_VOIP_SECURITY_HANDSHAKING);
    return LUAT_VOIP_SECURITY_PENDING;
}

static int security_dtls_keys(luat_voip_security_t *ctx)
{
    mbedtls_dtls_srtp_info negotiation;
    const unsigned char *client_key = ctx->exported_keys;
    const unsigned char *server_key = ctx->exported_keys + 16;
    const unsigned char *client_salt = ctx->exported_keys + 32;
    const unsigned char *server_salt = ctx->exported_keys + 46;
    int result;
    memset(&negotiation, 0, sizeof(negotiation));
    mbedtls_ssl_get_dtls_srtp_negotiation_result(&ctx->ssl, &negotiation);
    if (!ctx->peer_verified) return LUAT_VOIP_SECURITY_E_FINGERPRINT;
#if MBEDTLS_VERSION_MAJOR >= 3
    if (negotiation.MBEDTLS_PRIVATE(chosen_dtls_srtp_profile) != MBEDTLS_TLS_SRTP_AES128_CM_HMAC_SHA1_80 ||
            negotiation.MBEDTLS_PRIVATE(mki_len) != 0) return LUAT_VOIP_SECURITY_E_PROFILE;
#else
    if (negotiation.chosen_dtls_srtp_profile != MBEDTLS_TLS_SRTP_AES128_CM_HMAC_SHA1_80 ||
            negotiation.mki_len != 0) return LUAT_VOIP_SECURITY_E_PROFILE;
#endif
    if (!ctx->keys_exported) return LUAT_VOIP_SECURITY_E_CRYPTO;
    memcpy(ctx->local_key, ctx->dtls_client ? client_key : server_key, 16);
    memcpy(ctx->local_key + 16, ctx->dtls_client ? client_salt : server_salt, 14);
    memcpy(ctx->remote_key, ctx->dtls_client ? server_key : client_key, 16);
    memcpy(ctx->remote_key + 16, ctx->dtls_client ? server_salt : client_salt, 14);
    mbedtls_platform_zeroize(ctx->exported_keys, sizeof(ctx->exported_keys));
    ctx->keys_exported = 0;
    result = security_srtp_start(ctx);
    /* DTLS-derived master material is no longer needed after libsrtp copies it. */
    mbedtls_platform_zeroize(ctx->local_key, sizeof(ctx->local_key));
    mbedtls_platform_zeroize(ctx->remote_key, sizeof(ctx->remote_key));
    return result;
}
#endif /* LUAT_USE_DTLS_SRTP */

luat_voip_security_identity_t *luat_voip_security_identity_create(int *error)
{
#ifdef LUAT_USE_DTLS_SRTP
    luat_voip_security_identity_t *identity = luat_heap_calloc(1, sizeof(*identity));
    int result;
    if (!identity) { if (error) *error = LUAT_VOIP_SECURITY_E_MEMORY; return NULL; }
    identity->references = 1;
    mbedtls_pk_init(&identity->key);
    mbedtls_x509_crt_init(&identity->certificate);
    result = security_identity_generate(identity);
    if (error) *error = result;
    if (result) { luat_voip_security_identity_release(identity); return NULL; }
    return identity;
#else
    if (error) *error = LUAT_VOIP_SECURITY_E_UNSUPPORTED;
    return NULL;
#endif
}

void luat_voip_security_identity_retain(luat_voip_security_identity_t *identity)
{
    if (identity) security_retain(&identity->references);
}

void luat_voip_security_identity_release(luat_voip_security_identity_t *identity)
{
    if (!identity || !security_release(&identity->references)) return;
#ifdef LUAT_USE_DTLS_SRTP
    mbedtls_x509_crt_free(&identity->certificate);
    mbedtls_pk_free(&identity->key);
#endif
    mbedtls_platform_zeroize(identity, sizeof(*identity));
    luat_heap_free(identity);
}

static luat_voip_security_t *security_alloc(luat_voip_security_mode_t mode, int *error)
{
    luat_voip_security_t *ctx;
    if (mode != LUAT_VOIP_SECURITY_SDES && mode != LUAT_VOIP_SECURITY_DTLS) {
        if (error) *error = LUAT_VOIP_SECURITY_E_INVALID;
        return NULL;
    }
#ifndef LUAT_USE_DTLS_SRTP
    if (mode == LUAT_VOIP_SECURITY_DTLS) {
        if (error) *error = LUAT_VOIP_SECURITY_E_UNSUPPORTED;
        return NULL;
    }
#endif
    ctx = luat_heap_calloc(1, sizeof(*ctx));
    if (!ctx) { if (error) *error = LUAT_VOIP_SECURITY_E_MEMORY; return NULL; }
    ctx->references = 1;
    ctx->mode = mode;
#ifdef LUAT_USE_DTLS_SRTP
    mbedtls_ssl_init(&ctx->ssl);
    mbedtls_ssl_config_init(&ctx->config);
    mbedtls_ctr_drbg_init(&ctx->drbg);
#endif
    if (error) *error = LUAT_VOIP_SECURITY_OK;
    return ctx;
}

luat_voip_security_t *luat_voip_security_create(luat_voip_security_mode_t mode,
        luat_voip_security_identity_t *identity, int *error)
{
    int result = LUAT_VOIP_SECURITY_OK;
    luat_voip_security_t *ctx = security_alloc(mode, error);
    if (!ctx) return NULL;
    if (mode == LUAT_VOIP_SECURITY_SDES) {
        if (luat_crypto_trng((char *)ctx->local_key, sizeof(ctx->local_key)) != 0)
            result = LUAT_VOIP_SECURITY_E_CRYPTO;
    }
#ifdef LUAT_USE_DTLS_SRTP
    else {
        if (identity) luat_voip_security_identity_retain(identity);
        else identity = luat_voip_security_identity_create(&result);
        ctx->identity = identity;
    }
#else
    (void)identity;
#endif
    if (error) *error = result;
    if (result) { luat_voip_security_release(ctx); return NULL; }
    return ctx;
}

luat_voip_security_t *luat_voip_security_clone_local(const luat_voip_security_t *source, int *error)
{
    luat_voip_security_t *ctx;
    if (!source) { if (error) *error = LUAT_VOIP_SECURITY_E_INVALID; return NULL; }
    ctx = security_alloc(source->mode, error);
    if (!ctx) return NULL;
    if (source->mode == LUAT_VOIP_SECURITY_SDES)
        memcpy(ctx->local_key, source->local_key, sizeof(ctx->local_key));
#ifdef LUAT_USE_DTLS_SRTP
    else {
        ctx->identity = source->identity;
        luat_voip_security_identity_retain(ctx->identity);
    }
#endif
    return ctx;
}

void luat_voip_security_retain(luat_voip_security_t *ctx)
{
    if (ctx) security_retain(&ctx->references);
}

void luat_voip_security_release(luat_voip_security_t *ctx)
{
    if (!ctx || !security_release(&ctx->references)) return;
    if (ctx->outbound) srtp_dealloc(ctx->outbound);
    if (ctx->inbound) srtp_dealloc(ctx->inbound);
#ifdef LUAT_USE_DTLS_SRTP
    mbedtls_ssl_free(&ctx->ssl);
    mbedtls_ssl_config_free(&ctx->config);
    mbedtls_ctr_drbg_free(&ctx->drbg);
    luat_voip_security_identity_release(ctx->identity);
    if (ctx->rx_datagram) {
        mbedtls_platform_zeroize(ctx->rx_datagram, LUAT_VOIP_SECURITY_DATAGRAM_MAX);
        luat_heap_free(ctx->rx_datagram);
    }
#endif
    mbedtls_platform_zeroize(ctx, sizeof(*ctx));
    luat_heap_free(ctx);
}

int luat_voip_security_info(const luat_voip_security_t *ctx, luat_voip_security_info_t *info)
{
    if (!ctx || !info) return LUAT_VOIP_SECURITY_E_INVALID;
    memset(info, 0, sizeof(*info));
    info->mode = ctx->mode;
    if (ctx->mode == LUAT_VOIP_SECURITY_SDES) {
        size_t length = 0;
        if (mbedtls_base64_encode((unsigned char *)info->key, sizeof(info->key), &length,
                ctx->local_key, sizeof(ctx->local_key)) || length != 40)
            return LUAT_VOIP_SECURITY_E_CRYPTO;
        info->key[length] = '\0';
        return LUAT_VOIP_SECURITY_OK;
    }
#ifdef LUAT_USE_DTLS_SRTP
    if (ctx->identity) {
        security_fingerprint_text(ctx->identity->fingerprint, info->fingerprint);
        return LUAT_VOIP_SECURITY_OK;
    }
#endif
    return LUAT_VOIP_SECURITY_E_UNSUPPORTED;
}

int luat_voip_security_set_remote(luat_voip_security_t *ctx, const luat_voip_security_remote_t *remote)
{
    if (!ctx || !remote) return LUAT_VOIP_SECURITY_E_INVALID;
    if (luat_voip_security_state(ctx) != LUAT_VOIP_SECURITY_NEW || ctx->remote_configured)
        return LUAT_VOIP_SECURITY_E_STATE;
    if (ctx->mode == LUAT_VOIP_SECURITY_SDES) {
        size_t length = 0;
        if (!remote->suite || strcmp(remote->suite, LUAT_VOIP_SECURITY_SUITE))
            return LUAT_VOIP_SECURITY_E_PROFILE;
        if (!remote->key || strlen(remote->key) != 40 ||
                mbedtls_base64_decode(ctx->remote_key, sizeof(ctx->remote_key), &length,
                (const unsigned char *)remote->key, 40) || length != sizeof(ctx->remote_key)) {
            mbedtls_platform_zeroize(ctx->remote_key, sizeof(ctx->remote_key));
            return LUAT_VOIP_SECURITY_E_INVALID;
        }
    }
#ifdef LUAT_USE_DTLS_SRTP
    else {
        int result = security_parse_fingerprint(remote->fingerprint, ctx->remote_fingerprint);
        if (result || remote->dtls_client > 1) return LUAT_VOIP_SECURITY_E_INVALID;
        ctx->dtls_client = remote->dtls_client;
    }
#endif
    ctx->remote_configured = 1;
    return LUAT_VOIP_SECURITY_OK;
}

int luat_voip_security_configured(const luat_voip_security_t *ctx)
{
    return ctx && ctx->remote_configured;
}

int luat_voip_security_start(luat_voip_security_t *ctx, luat_voip_security_send_t send, void *opaque)
{
    int result;
    if (!ctx || !ctx->remote_configured) return LUAT_VOIP_SECURITY_E_INVALID;
    if (luat_voip_security_state(ctx) != LUAT_VOIP_SECURITY_NEW) return LUAT_VOIP_SECURITY_E_STATE;
    if (ctx->mode == LUAT_VOIP_SECURITY_SDES) {
        result = security_srtp_start(ctx);
        if (result) return security_fail(ctx, result);
        security_state_set(ctx, LUAT_VOIP_SECURITY_READY);
        return LUAT_VOIP_SECURITY_OK;
    }
#ifdef LUAT_USE_DTLS_SRTP
    ctx->send = send;
    ctx->send_opaque = opaque;
    result = security_dtls_start(ctx);
    if (result < 0) return security_fail(ctx, result);
    return result;
#else
    (void)send; (void)opaque;
    return security_fail(ctx, LUAT_VOIP_SECURITY_E_UNSUPPORTED);
#endif
}

int luat_voip_security_is_dtls(const uint8_t *data, size_t len)
{
    /* RFC 7983 packet classification; record parsing remains Mbed TLS's job. */
    return data && len >= 13 && data[0] >= 20 && data[0] <= 63;
}

int luat_voip_security_feed(luat_voip_security_t *ctx, const uint8_t *data, size_t len)
{
#ifdef LUAT_USE_DTLS_SRTP
    if (!ctx || ctx->mode != LUAT_VOIP_SECURITY_DTLS || !ctx->tls_initialized ||
            !luat_voip_security_is_dtls(data, len) || len > LUAT_VOIP_SECURITY_DATAGRAM_MAX)
        return LUAT_VOIP_SECURITY_E_INVALID;
    if (luat_voip_security_state(ctx) == LUAT_VOIP_SECURITY_FAILED) return ctx->error;
    if (ctx->rx_length) return LUAT_VOIP_SECURITY_E_STATE;
    memcpy(ctx->rx_datagram, data, len);
    ctx->rx_length = len;
    ctx->rx_offset = 0;
    return LUAT_VOIP_SECURITY_OK;
#else
    (void)ctx; (void)data; (void)len;
    return LUAT_VOIP_SECURITY_E_UNSUPPORTED;
#endif
}

int luat_voip_security_step(luat_voip_security_t *ctx)
{
    luat_voip_security_state_t state;
    if (!ctx) return LUAT_VOIP_SECURITY_E_INVALID;
    state = luat_voip_security_state(ctx);
    if (state == LUAT_VOIP_SECURITY_FAILED) return ctx->error;
    if (state == LUAT_VOIP_SECURITY_NEW) return LUAT_VOIP_SECURITY_E_STATE;
#ifdef LUAT_USE_DTLS_SRTP
    if (ctx->mode == LUAT_VOIP_SECURITY_DTLS) {
        int result;
        if (state == LUAT_VOIP_SECURITY_HANDSHAKING) {
            if (luat_mcu_tick64_ms() - ctx->started_ms >= LUAT_VOIP_SECURITY_TIMEOUT_MS)
                return security_fail(ctx, LUAT_VOIP_SECURITY_E_TIMEOUT);
            result = mbedtls_ssl_handshake(&ctx->ssl);
            if (result == MBEDTLS_ERR_SSL_WANT_READ || result == MBEDTLS_ERR_SSL_WANT_WRITE)
                return LUAT_VOIP_SECURITY_PENDING;
            if (result) return security_fail(ctx, ctx->error ? ctx->error :
                    (result == MBEDTLS_ERR_SSL_TIMEOUT ? LUAT_VOIP_SECURITY_E_TIMEOUT : LUAT_VOIP_SECURITY_E_CRYPTO));
            result = security_dtls_keys(ctx);
            if (result) return security_fail(ctx, result);
            security_state_set(ctx, LUAT_VOIP_SECURITY_READY);
        } else if (ctx->rx_length) {
            unsigned char unused;
            /* Process final-flight retransmissions and peer close alerts. RTP
             * is never accepted as DTLS application data. */
            result = mbedtls_ssl_read(&ctx->ssl, &unused, sizeof(unused));
            if (result == 0 || result == MBEDTLS_ERR_SSL_PEER_CLOSE_NOTIFY)
                return security_fail(ctx, LUAT_VOIP_SECURITY_E_IO);
            if (result < 0 && result != MBEDTLS_ERR_SSL_WANT_READ && result != MBEDTLS_ERR_SSL_WANT_WRITE)
                return security_fail(ctx, LUAT_VOIP_SECURITY_E_CRYPTO);
        }
    }
#endif
    return LUAT_VOIP_SECURITY_OK;
}

luat_voip_security_state_t luat_voip_security_state(const luat_voip_security_t *ctx)
{
    if (!ctx) return LUAT_VOIP_SECURITY_FAILED;
    return (luat_voip_security_state_t)voip_event_load((volatile uint32_t *)&ctx->state);
}

luat_voip_security_mode_t luat_voip_security_mode(const luat_voip_security_t *ctx)
{
    return ctx ? ctx->mode : LUAT_VOIP_SECURITY_NONE;
}

int luat_voip_security_error(const luat_voip_security_t *ctx)
{
    if (!ctx) return LUAT_VOIP_SECURITY_E_INVALID;
    /* State load provides the publication barrier for the terminal error. */
    return luat_voip_security_state(ctx) == LUAT_VOIP_SECURITY_FAILED ? ctx->error : 0;
}

static int security_packet_error(srtp_err_status_t error)
{
    if (error == srtp_err_status_ok) return LUAT_VOIP_SECURITY_OK;
    if (error == srtp_err_status_auth_fail) return LUAT_VOIP_SECURITY_E_AUTH;
    if (error == srtp_err_status_replay_fail || error == srtp_err_status_replay_old)
        return LUAT_VOIP_SECURITY_E_REPLAY;
    return LUAT_VOIP_SECURITY_E_CRYPTO;
}

int luat_voip_security_protect(luat_voip_security_t *ctx, uint8_t *packet, size_t *length, size_t capacity)
{
    int bytes, result;
    if (!ctx || !packet || !length || *length < 12 || *length > (size_t)INT_MAX - LUAT_VOIP_SECURITY_TAG_BYTES ||
            capacity < *length || capacity - *length < LUAT_VOIP_SECURITY_TAG_BYTES)
        return LUAT_VOIP_SECURITY_E_INVALID;
    if (luat_voip_security_state(ctx) != LUAT_VOIP_SECURITY_READY || !ctx->outbound)
        return LUAT_VOIP_SECURITY_E_STATE;
    bytes = (int)*length;
    result = security_packet_error(srtp_protect(ctx->outbound, packet, &bytes));
    if (!result) *length = (size_t)bytes;
    return result;
}

int luat_voip_security_unprotect(luat_voip_security_t *ctx, uint8_t *packet, size_t *length)
{
    int bytes, result;
    if (!ctx || !packet || !length || *length < 12 + LUAT_VOIP_SECURITY_TAG_BYTES || *length > INT_MAX)
        return LUAT_VOIP_SECURITY_E_INVALID;
    if (luat_voip_security_state(ctx) != LUAT_VOIP_SECURITY_READY || !ctx->inbound)
        return LUAT_VOIP_SECURITY_E_STATE;
    bytes = (int)*length;
    result = security_packet_error(srtp_unprotect(ctx->inbound, packet, &bytes));
    if (!result) *length = (size_t)bytes;
    return result;
}

const char *luat_voip_security_error_name(int error)
{
    switch (error) {
    case LUAT_VOIP_SECURITY_OK: return "ok";
    case LUAT_VOIP_SECURITY_PENDING: return "security_pending";
    case LUAT_VOIP_SECURITY_E_INVALID: return "invalid_security";
    case LUAT_VOIP_SECURITY_E_MEMORY: return "security_memory";
    case LUAT_VOIP_SECURITY_E_UNSUPPORTED: return "security_unsupported";
    case LUAT_VOIP_SECURITY_E_CRYPTO: return "security_crypto";
    case LUAT_VOIP_SECURITY_E_STATE: return "security_state";
    case LUAT_VOIP_SECURITY_E_TIMEOUT: return "dtls_timeout";
    case LUAT_VOIP_SECURITY_E_FINGERPRINT: return "dtls_fingerprint";
    case LUAT_VOIP_SECURITY_E_PROFILE: return "security_profile";
    case LUAT_VOIP_SECURITY_E_AUTH: return "srtp_auth";
    case LUAT_VOIP_SECURITY_E_REPLAY: return "srtp_replay";
    case LUAT_VOIP_SECURITY_E_IO: return "security_io";
    default: return "security_error";
    }
}
#endif /* LUAT_USE_SRTP */
