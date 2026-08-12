/*
 * IKEv2/IPsec crypto helpers for LuatOS netdrv.
 *
 * Implements RFC 7296 §2.13/§2.14/§2.15/§2.17 building blocks on top of
 * mbedTLS, plus X.509 chain/SAN verification for server authentication.
 */

#include "ipsec/ipsec_crypto.h"

#include <string.h>

#include "luat_crypto.h"

#define LUAT_LOG_TAG "ipsec_crypto"
#include "luat_log.h"

/* ========== PRF / prf+ ========== */

int ipsec_prf(uint8_t prf, const uint8_t *key, size_t key_len,
              const uint8_t *in, size_t in_len, uint8_t *out)
{
    const mbedtls_md_info_t *info = mbedtls_md_info_from_type(ipsec_prf_md(prf));
    if (info == NULL)
        return -1;
    return mbedtls_md_hmac(info, key, key_len, in, in_len, out);
}

int ipsec_prf_plus(uint8_t prf, const uint8_t *key, size_t key_len,
                   const uint8_t *seed, size_t seed_len,
                   uint8_t *out, size_t out_len)
{
    const mbedtls_md_info_t *info = mbedtls_md_info_from_type(ipsec_prf_md(prf));
    mbedtls_md_context_t md_ctx;
    uint8_t t[IPSEC_SHA256_KEY_LEN];
    uint16_t hlen = ipsec_prf_len(prf);
    uint8_t counter = 1;
    size_t off = 0;
    int first = 1;
    int ret = -1;

    if (info == NULL || out_len > 255 * (size_t)hlen)
        return -1;

    mbedtls_md_init(&md_ctx);
    if (mbedtls_md_setup(&md_ctx, info, 1) != 0)
        return -1;

    while (off < out_len) {
        size_t take = out_len - off;
        if (take > hlen)
            take = hlen;
        if (first) {
            if (mbedtls_md_hmac_starts(&md_ctx, key, key_len) != 0)
                goto out;
            if (mbedtls_md_hmac_update(&md_ctx, seed, seed_len) != 0)
                goto out;
            if (mbedtls_md_hmac_update(&md_ctx, &counter, 1) != 0)
                goto out;
            first = 0;
        } else {
            if (mbedtls_md_hmac_reset(&md_ctx) != 0)
                goto out;
            if (mbedtls_md_hmac_update(&md_ctx, t, hlen) != 0)
                goto out;
            if (mbedtls_md_hmac_update(&md_ctx, seed, seed_len) != 0)
                goto out;
            if (mbedtls_md_hmac_update(&md_ctx, &counter, 1) != 0)
                goto out;
        }
        if (mbedtls_md_hmac_finish(&md_ctx, t) != 0)
            goto out;
        memcpy(out + off, t, take);
        off += take;
        counter++;
    }
    ret = 0;

out:
    mbedtls_md_free(&md_ctx);
    memset(t, 0, sizeof(t));
    return ret;
}

/* ========== RNG ========== */

int ipsec_rng_cb(void *ctx, unsigned char *output, size_t len)
{
    (void)ctx;
    return luat_crypto_trng((char *)output, len);
}

/* ========== DH group 14 ========== */

/*
 * RFC 3526 MODP-2048 (group 14) prime and generator 2.
 */
static const char ipsec_modp2048_p[] =
    "FFFFFFFFFFFFFFFFC90FDAA22168C234C4C6628B80DC1CD1"
    "29024E088A67CC74020BBEA63B139B22514A08798E3404DD"
    "EF9519B3CD3A431B302B0A6DF25F14374FE1356D6D51C245"
    "E485B576625E7EC6F44C42E9A637ED6B0BFF5CB6F406B7ED"
    "EE386BFB5A899FA5AE9F24117C4B1FE649286651ECE45B3D"
    "C2007CB8A163BF0598DA48361C55D39A69163FA8FD24CF5F"
    "83655D23DCA3AD961C62F356208552BB9ED529077096966D"
    "670C354E4ABC9804F1746C08CA18217C32905E462E36CE3B"
    "E39E772C180E86039B2783A2EC07A28FB5C55DF06F4C52C9"
    "DE2BCBF6955817183995497CEA956AE515D2261898FA0510"
    "15728E5A8AACAA68FFFFFFFFFFFFFFFF";
static const char ipsec_modp2048_g[] = "02";

int ipsec_dh_set_group14(mbedtls_dhm_context *dhm)
{
    mbedtls_mpi P, G;
    int ret;

    mbedtls_mpi_init(&P);
    mbedtls_mpi_init(&G);
    if (mbedtls_mpi_read_string(&P, 16, ipsec_modp2048_p) != 0 ||
        mbedtls_mpi_read_string(&G, 16, ipsec_modp2048_g) != 0) {
        mbedtls_mpi_free(&P);
        mbedtls_mpi_free(&G);
        return -1;
    }
    ret = mbedtls_dhm_set_group(dhm, &P, &G);
    mbedtls_mpi_free(&P);
    mbedtls_mpi_free(&G);
    return ret;
}

int ipsec_dh_make_public(mbedtls_dhm_context *dhm, uint8_t *pub, size_t *pub_len)
{
    return mbedtls_dhm_make_public(dhm, IPSEC_DH_MODP2048_LEN, pub, *pub_len,
                                   ipsec_rng_cb, NULL);
}

int ipsec_dh_read_public(mbedtls_dhm_context *dhm, const uint8_t *pub, size_t pub_len)
{
    return mbedtls_dhm_read_public(dhm, pub, pub_len);
}

int ipsec_dh_calc_secret(mbedtls_dhm_context *dhm, uint8_t *secret, size_t *secret_len)
{
    size_t len = IPSEC_DH_MODP2048_LEN;
    int ret = mbedtls_dhm_calc_secret(dhm, secret, len, &len, ipsec_rng_cb, NULL);
    if (ret == 0)
        *secret_len = len;
    return ret;
}

/* ========== Key derivation ========== */

int ipsec_derive_ike_keys(const ipsec_ike_algs_t *algs,
                          const uint8_t *ni, uint16_t ni_len,
                          const uint8_t *nr, uint16_t nr_len,
                          const uint8_t *g_ir, uint16_t g_ir_len,
                          const uint8_t *spii, const uint8_t *spir,
                          uint8_t *out)
{
    uint8_t seed[64 + 16];
    uint8_t skeyseed[IPSEC_SHA256_KEY_LEN];
    uint16_t plen = ipsec_prf_len(algs->prf);
    uint16_t seed_len = 0;
    int ret = -1;

    /* SKEYSEED = prf(Ni | Nr, g^ir) */
    memcpy(seed, ni, ni_len);
    memcpy(seed + ni_len, nr, nr_len);
    if (ipsec_prf(algs->prf, seed, (size_t)ni_len + nr_len,
                  g_ir, g_ir_len, skeyseed) != 0)
        return -1;

    /* {SK_d..SK_pr} = prf+(SKEYSEED, Ni | Nr | SPIi | SPIr) */
    memcpy(seed, ni, ni_len);
    memcpy(seed + ni_len, nr, nr_len);
    seed_len = (uint16_t)(ni_len + nr_len);
    memcpy(seed + seed_len, spii, 8);
    memcpy(seed + seed_len + 8, spir, 8);
    seed_len = (uint16_t)(seed_len + 16);
    ret = ipsec_prf_plus(algs->prf, skeyseed, plen,
                         seed, seed_len, out, (size_t)plen * 7);

    memset(skeyseed, 0, sizeof(skeyseed));
    return ret;
}

int ipsec_derive_child_keymat(uint8_t prf, const uint8_t *sk_d, uint16_t sk_d_len,
                              const uint8_t *ni, uint16_t ni_len,
                              const uint8_t *nr, uint16_t nr_len,
                              uint8_t enc_len, uint8_t integ_len,
                              uint8_t *out)
{
    uint8_t seed[64];
    uint16_t total = (uint16_t)(2 * ((uint16_t)enc_len + (uint16_t)integ_len));

    memcpy(seed, ni, ni_len);
    memcpy(seed + ni_len, nr, nr_len);
    return ipsec_prf_plus(prf, sk_d, sk_d_len, seed, (size_t)ni_len + nr_len,
                          out, total);
}

/* ========== AUTH ========== */

int ipsec_compute_auth_shared(uint8_t prf,
                              const uint8_t *shared, size_t shared_len,
                              const uint8_t *signed_octets, size_t signed_len,
                              uint8_t *auth_out, size_t auth_out_len)
{
    static const char pad[] = "Key Pad for IKEv2"; /* 17 ASCII chars, no NUL */
    uint8_t k[IPSEC_SHA256_KEY_LEN];
    uint16_t plen = ipsec_prf_len(prf);

    if (auth_out_len < plen)
        return -1;
    if (ipsec_prf(prf, shared, shared_len,
                  (const uint8_t *)pad, sizeof(pad) - 1, k) != 0)
        return -1;
    if (ipsec_prf(prf, k, plen, signed_octets, signed_len, auth_out) != 0) {
        memset(k, 0, sizeof(k));
        return -1;
    }
    memset(k, 0, sizeof(k));
    return 0;
}

/* Convert raw ECDSA r||s to DER SEQUENCE { INTEGER r, INTEGER s } */
static int ecdsa_raw_to_der(const uint8_t *raw, size_t raw_len,
                            uint8_t *der, size_t *der_len)
{
    size_t half = raw_len / 2;
    const uint8_t *r = raw;
    const uint8_t *s = raw + half;
    size_t r_len = half, s_len = half;
    size_t total, rpad, spad;
    uint8_t *p = der;

    /* Skip leading zero bytes in each integer */
    while (r_len > 1 && *r == 0) {
        r++;
        r_len--;
    }
    while (s_len > 1 && *s == 0) {
        s++;
        s_len--;
    }

    rpad = (*r & 0x80) ? 1 : 0;
    spad = (*s & 0x80) ? 1 : 0;
    /* SEQUENCE(2) + INTEGER r(2 + r_len + rpad) + INTEGER s(2 + s_len + spad) */
    total = 6 + r_len + s_len + rpad + spad;

    if (total > 140)
        return -1;

    *p++ = 0x30;
    *p++ = (uint8_t)(total - 2);
    *p++ = 0x02;
    *p++ = (uint8_t)(r_len + rpad);
    if (rpad) *p++ = 0x00;
    memcpy(p, r, r_len);
    p += r_len;
    *p++ = 0x02;
    *p++ = (uint8_t)(s_len + spad);
    if (spad) *p++ = 0x00;
    memcpy(p, s, s_len);
    p += s_len;

    *der_len = (size_t)(p - der);
    return 0;
}

int ipsec_verify_auth_signature(const mbedtls_pk_context *pk,
                                const uint8_t *signed_octets, size_t signed_len,
                                const uint8_t *auth, size_t auth_len)
{
    static const mbedtls_md_type_t candidates[] = {
        MBEDTLS_MD_SHA256, MBEDTLS_MD_SHA1, MBEDTLS_MD_SHA384, MBEDTLS_MD_SHA512
    };
    uint8_t hash[64];
    uint8_t der[140];
    size_t der_len;
    const uint8_t *sig;
    size_t sig_len;
    unsigned int i;
    mbedtls_pk_type_t pk_type = mbedtls_pk_get_type(pk);

    if (pk_type == MBEDTLS_PK_ECKEY || pk_type == MBEDTLS_PK_ECKEY_DH) {
        /* IKEv2 ECDSA AUTH data is raw r||s */
        if (auth_len != 96 && auth_len != 64 && auth_len != 48) {
            LLOGE("auth sig len %u not ECDSA-sized", (unsigned)auth_len);
            return -1;
        }
        if (ecdsa_raw_to_der(auth, auth_len, der, &der_len) != 0) {
            LLOGE("ecdsa raw->der conversion failed");
            return -1;
        }
        LLOGD("pk type=ECKEY sig_der_len=%u", (unsigned)der_len);
        sig = der;
        sig_len = der_len;
    } else {
        /* RSA (and other) signatures are verified as-is */
        sig = auth;
        sig_len = auth_len;
    }

    for (i = 0; i < sizeof(candidates) / sizeof(candidates[0]); i++) {
        const mbedtls_md_info_t *info = mbedtls_md_info_from_type(candidates[i]);
        size_t hlen;
        if (info == NULL)
            continue;
        hlen = mbedtls_md_get_size(info);
        if (hlen > sizeof(hash))
            continue;
        if (mbedtls_md(info, signed_octets, signed_len, hash) != 0)
            continue;
        {
            int vret = mbedtls_pk_verify((mbedtls_pk_context *)pk, candidates[i],
                                         hash, hlen, sig, sig_len);
            if (vret == 0)
                return 0;
            LLOGD("pk_verify md=%d ret=-0x%04X", (int)candidates[i],
                  (unsigned)(vret > 0 ? vret : -vret));
        }
    }
    return -1;
}

/* ========== Certificate verification ========== */

/* Check the leaf certificate's SAN list for \p san (DNS name) */
static int ipsec_check_san(mbedtls_x509_crt *crt, const char *san)
{
    mbedtls_x509_sequence *cur;
    size_t san_len = strlen(san);

    for (cur = &crt->subject_alt_names; cur != NULL; cur = cur->next) {
        mbedtls_x509_subject_alternative_name alt;
        if (mbedtls_x509_parse_subject_alt_name(&cur->buf, &alt) != 0)
            continue;
        if (alt.type == MBEDTLS_X509_SAN_DNS_NAME &&
            alt.san.unstructured_name.len == san_len &&
            memcmp(alt.san.unstructured_name.p, san, san_len) == 0)
            return 0;
    }
    return -1;
}

int ipsec_verify_cert_chain(mbedtls_x509_crt *chain,
                            const char *ca_pem, size_t ca_pem_len,
                            const char *san,
                            mbedtls_x509_crt *cacert)
{
    mbedtls_x509_crt local_cacert;
    mbedtls_x509_crt *store;
    uint32_t flags = 0;
    int ret;
    int use_local;

    if (chain == NULL)
        return -1;

    /* No trust anchor configured: accept the server certificate as-is.
     * The gateway certificate is operator-managed (e.g. ipsec.air32.cn
     * private CA), so no built-in anchors are pinned in the firmware. */
    if (ca_pem == NULL || ca_pem_len == 0) {
        LLOGW("no ca_cert configured, accepting server certificate without verification");
        return 0;
    }
    if (san == NULL)
        return -1;

    use_local = (cacert == NULL);
    if (use_local) {
        mbedtls_x509_crt_init(&local_cacert);
        store = &local_cacert;
    } else {
        mbedtls_x509_crt_init(cacert);
        store = cacert;
    }

    ret = mbedtls_x509_crt_parse(store, (const unsigned char *)ca_pem, ca_pem_len);
    if (ret != 0) {
        LLOGE("trust anchor parse failed: -0x%04X", (unsigned)(-ret));
        ret = -1;
        goto out;
    }

    ret = mbedtls_x509_crt_verify_with_profile(chain, store, NULL,
                                               &mbedtls_x509_crt_profile_default,
                                               NULL, &flags, NULL, NULL);
    LLOGD("cert verify: ret=-0x%04X flags=0x%lX", (unsigned)(ret > 0 ? ret : -ret),
          (unsigned long)flags);
    if (ret != 0 || flags != 0) {
        LLOGE("cert chain verify failed: ret=-0x%04X flags=0x%lX",
              (unsigned)(ret > 0 ? ret : -ret), (unsigned long)flags);
        ret = -1;
        goto out;
    }
    {
        int san_ret = ipsec_check_san(chain, san);
        LLOGD("cert SAN check: %d", san_ret);
        if (san_ret != 0) {
            LLOGE("cert SAN does not match %s", san);
            ret = -1;
            goto out;
        }
    }
    ret = 0;

out:
    if (use_local)
        mbedtls_x509_crt_free(&local_cacert);
    return ret;
}
