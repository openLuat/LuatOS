/*
 * OpenVPN data-channel crypto for LuatOS netdrv: HMAC-MD5/HMAC-SHA1 PRF
 * helpers (TLS 1.0 PRF) and TLS-EKM / PRF key derivation for AES-256-GCM.
 *
 * Split from the original single-file OpenVPN client core; behavior unchanged.
 */

#include "ovpn/ovpn_client.h"
#include "ovpn/ovpn_crypto.h"

#include <string.h>
#include "luat_crypto.h"
#include "mbedtls/md5.h"
#include "mbedtls/sha1.h"

#define LUAT_LOG_TAG "openvpn"
#include "luat_log.h"

#if MBEDTLS_VERSION_NUMBER < 0x03000000
#define mbedtls_sha1_starts mbedtls_sha1_starts_ret
#define mbedtls_sha1_update mbedtls_sha1_update_ret
#define mbedtls_sha1_finish mbedtls_sha1_finish_ret
#define mbedtls_md5_starts mbedtls_md5_starts_ret
#define mbedtls_md5_update mbedtls_md5_update_ret
#define mbedtls_md5_finish mbedtls_md5_finish_ret
#endif

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
void ovpn_export_keys(ovpn_client_t *cli) {
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
