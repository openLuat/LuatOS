/**
 * \file ipsec_crypto.h
 *
 * \brief IKEv2/IPsec crypto helpers (PRF+, DH, key derivation, AUTH,
 *        certificate verification).
 */
#ifndef IPSEC_CRYPTO_H
#define IPSEC_CRYPTO_H

#include <stddef.h>
#include <stdint.h>

#include "mbedtls/md.h"
#include "mbedtls/dhm.h"
#include "mbedtls/pk.h"
#include "mbedtls/x509_crt.h"

#ifdef __cplusplus
extern "C" {
#endif

/* IKE proposal algorithm selectors */
#define IPSEC_PRF_SHA1        0
#define IPSEC_PRF_SHA256      1
#define IPSEC_ENC_AES128      0
#define IPSEC_ENC_AES256      1
#define IPSEC_INTEG_SHA1      0
#define IPSEC_INTEG_SHA256    1

typedef struct ipsec_ike_algs {
    uint8_t prf;       /* IPSEC_PRF_* */
    uint8_t enc;       /* IPSEC_ENC_*  */
    uint8_t integ;     /* IPSEC_INTEG_* */
} ipsec_ike_algs_t;

/* Key sizes */
#define IPSEC_AES128_KEY_LEN   16
#define IPSEC_AES256_KEY_LEN   32
#define IPSEC_SHA1_KEY_LEN     20
#define IPSEC_SHA256_KEY_LEN   32
#define IPSEC_DH_MODP2048_LEN  256

static inline mbedtls_md_type_t ipsec_prf_md(uint8_t prf)
{
    return prf == IPSEC_PRF_SHA1 ? MBEDTLS_MD_SHA1 : MBEDTLS_MD_SHA256;
}

static inline uint16_t ipsec_prf_len(uint8_t prf)
{
    return prf == IPSEC_PRF_SHA1 ? IPSEC_SHA1_KEY_LEN : IPSEC_SHA256_KEY_LEN;
}

static inline uint16_t ipsec_enc_len(uint8_t enc)
{
    return enc == IPSEC_ENC_AES128 ? IPSEC_AES128_KEY_LEN : IPSEC_AES256_KEY_LEN;
}

static inline uint16_t ipsec_integ_len(uint8_t integ)
{
    return integ == IPSEC_INTEG_SHA1 ? IPSEC_SHA1_KEY_LEN : IPSEC_SHA256_KEY_LEN;
}

/* PRF (one-shot HMAC) and prf+ (RFC 7296 §2.13) */
int ipsec_prf(uint8_t prf, const uint8_t *key, size_t key_len,
              const uint8_t *in, size_t in_len, uint8_t *out);
int ipsec_prf_plus(uint8_t prf, const uint8_t *key, size_t key_len,
                   const uint8_t *seed, size_t seed_len,
                   uint8_t *out, size_t out_len);

/* mbedTLS RNG adapter (luat_crypto_trng) */
int ipsec_rng_cb(void *ctx, unsigned char *output, size_t len);

/* DH group 14 (RFC 3526 MODP-2048) helpers */
int ipsec_dh_set_group14(mbedtls_dhm_context *dhm);
int ipsec_dh_make_public(mbedtls_dhm_context *dhm, uint8_t *pub, size_t *pub_len);
int ipsec_dh_read_public(mbedtls_dhm_context *dhm, const uint8_t *pub, size_t pub_len);
int ipsec_dh_calc_secret(mbedtls_dhm_context *dhm, uint8_t *secret, size_t *secret_len);

/**
 * Derive SKEYSEED and the seven IKE SA keys (RFC 7296 §2.14).
 *
 * \param algs      Negotiated algorithms.
 * \param ni,nr     Nonces.
 * \param ni_len, nr_len
 * \param g_ir      DH shared secret (big-endian, modulus length).
 * \param g_ir_len
 * \param spii, spir IKE SA SPIs (8 bytes each).
 * \param out       Buffer of at least 7 * ipsec_prf_len() bytes; receives
 *                  SK_d | SK_ai | SK_ar | SK_ei | SK_er | SK_pi | SK_pr.
 */
int ipsec_derive_ike_keys(const ipsec_ike_algs_t *algs,
                          const uint8_t *ni, uint16_t ni_len,
                          const uint8_t *nr, uint16_t nr_len,
                          const uint8_t *g_ir, uint16_t g_ir_len,
                          const uint8_t *spii, const uint8_t *spir,
                          uint8_t *out);

/**
 * Derive CHILD_SA KEYMAT (RFC 7296 §2.17): prf+(SK_d, Ni | Nr).
 * Keys are taken: outbound ENCR | outbound INTEG | inbound ENCR | inbound INTEG.
 */
int ipsec_derive_child_keymat(uint8_t prf, const uint8_t *sk_d, uint16_t sk_d_len,
                              const uint8_t *ni, uint16_t ni_len,
                              const uint8_t *nr, uint16_t nr_len,
                              uint8_t enc_len, uint8_t integ_len,
                              uint8_t *out); /* 2*(enc_len+integ_len) bytes */

/**
 * Compute a shared-secret style AUTH value (RFC 7296 §2.15):
 *   AUTH = prf(prf(SharedSecret, "Key Pad for IKEv2"), SignedOctets)
 */
int ipsec_compute_auth_shared(uint8_t prf,
                              const uint8_t *shared, size_t shared_len,
                              const uint8_t *signed_octets, size_t signed_len,
                              uint8_t *auth_out, size_t auth_out_len);

/**
 * Verify an RSA/ECDSA AUTH signature over SignedOctets.
 * Tries the common hash algorithms in order of likelihood.
 */
int ipsec_verify_auth_signature(const mbedtls_pk_context *pk,
                                const uint8_t *signed_octets, size_t signed_len,
                                const uint8_t *auth, size_t auth_len);

/**
 * Verify an X.509 certificate chain against a trust anchor and check the
 * leaf certificate's SAN/CN against \p san.
 *
 * \param chain     Parsed certificate chain (leaf first), from CERT payloads.
 * \param ca_pem    Optional PEM trust anchor; if NULL the server
 *                  certificate is accepted without verification.
 * \param ca_pem_len
 * \param san       Expected server name (e.g. "ipsec.air32.cn").
 * \param cacert    Optional scratch trust-store to keep allocated by the
 *                  caller (mbedtls_x509_crt_init'd).  If NULL a stack
 *                  store is used internally.
 *
 * \return 0 on success, negative on failure.
 */
int ipsec_verify_cert_chain(mbedtls_x509_crt *chain,
                            const char *ca_pem, size_t ca_pem_len,
                            const char *san,
                            mbedtls_x509_crt *cacert);

#ifdef __cplusplus
}
#endif

#endif /* IPSEC_CRYPTO_H */
