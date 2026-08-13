#include "luat_base.h"

#if defined(LUAT_USE_UTEST) && defined(LUAT_USE_NETDRV_IPSEC)

#include <string.h>

#include "ipsec/ipsec_crypto.h"
#include "ipsec/ipsec_esp.h"
#include "ipsec/ipsec_vendor_chap_ms.h"

#include "mbedtls/constant_time.h"
#include "mbedtls/platform_util.h"

static int ipsec_utest_ike_key_derivation(void)
{
    ipsec_ike_algs_t algs;
    uint8_t ni[32], nr[32], g_ir[32], spii[8], spir[8];
    uint8_t keys[5 * IPSEC_SHA256_KEY_LEN + 2 * IPSEC_AES256_KEY_LEN];
    int i;

    for (i = 0; i < (int)sizeof(ni); i++) ni[i] = (uint8_t)i;
    for (i = 0; i < (int)sizeof(nr); i++) nr[i] = (uint8_t)(0xA0 + i);
    for (i = 0; i < (int)sizeof(g_ir); i++) g_ir[i] = (uint8_t)(0x50 + i);
    for (i = 0; i < 8; i++) { spii[i] = (uint8_t)(0x30 + i); spir[i] = (uint8_t)(0x40 + i); }

    memset(&algs, 0, sizeof(algs));
    algs.prf = IPSEC_PRF_SHA1;
    algs.enc = IPSEC_ENC_AES128;
    algs.integ = IPSEC_INTEG_SHA1;
    if (ipsec_derive_ike_keys(&algs, ni, (uint16_t)sizeof(ni), nr, (uint16_t)sizeof(nr),
                              g_ir, (uint16_t)sizeof(g_ir), spii, spir, keys) != 0)
        return -1;
    mbedtls_platform_zeroize(keys, sizeof(keys));

    algs.prf = IPSEC_PRF_SHA256;
    algs.enc = IPSEC_ENC_AES256;
    algs.integ = IPSEC_INTEG_SHA256;
    if (ipsec_derive_ike_keys(&algs, ni, (uint16_t)sizeof(ni), nr, (uint16_t)sizeof(nr),
                              g_ir, (uint16_t)sizeof(g_ir), spii, spir, keys) != 0)
        return -1;
    mbedtls_platform_zeroize(keys, sizeof(keys));
    return 0;
}

static int ipsec_utest_esp_roundtrip(int aead)
{
    uint8_t ip[20];
    uint8_t enc[1600];
    uint16_t enc_len;
    uint8_t dec[1600];
    uint16_t dec_len;
    uint8_t key16[16] = {0x10,0x11,0x12,0x13,0x14,0x15,0x16,0x17,
                         0x18,0x19,0x1A,0x1B,0x1C,0x1D,0x1E,0x1F};
    uint8_t integ20[20] = {0};
    uint8_t salt4[4] = {0x21,0x22,0x23,0x24};
    ipsec_esp_sa_t sa_out, sa_in;
    int i;

    for (i = 0; i < (int)sizeof(ip); i++) ip[i] = (uint8_t)i;
    if (aead) {
        ipsec_esp_sa_init_aead(&sa_out, 0x55667788, IPSEC_ENC_AES_GCM128, key16, salt4);
        ipsec_esp_sa_init_aead(&sa_in, 0x55667788, IPSEC_ENC_AES_GCM128, key16, salt4);
    } else {
        ipsec_esp_sa_init(&sa_out, 0x11223344, IPSEC_ENC_AES128, IPSEC_INTEG_SHA1,
                          key16, integ20);
        ipsec_esp_sa_init(&sa_in, 0x11223344, IPSEC_ENC_AES128, IPSEC_INTEG_SHA1,
                          key16, integ20);
    }

    if (ipsec_esp_encrypt(&sa_out, ip, (uint16_t)sizeof(ip), enc, &enc_len) != 0)
        return -1;
    if (ipsec_esp_decrypt(&sa_in, enc, enc_len, dec, (uint16_t)sizeof(dec), &dec_len) != 0 ||
        dec_len != (uint16_t)sizeof(ip) || mbedtls_ct_memcmp(dec, ip, sizeof(ip)) != 0)
        return -1;
    /* Replay of the same ciphertext must be rejected. */
    if (ipsec_esp_decrypt(&sa_in, enc, enc_len, dec, (uint16_t)sizeof(dec), &dec_len) == 0)
        return -1;

    mbedtls_platform_zeroize(enc, sizeof(enc));
    mbedtls_platform_zeroize(dec, sizeof(dec));
    return 0;
}

int luat_ipsec_utest(lua_State *L, const char *case_name)
{
    (void)L;
    if (case_name == NULL || strcmp(case_name, "all") == 0 ||
        strcmp(case_name, "mschapv2_rfc_vectors") == 0) {
        if (ipsec_mschapv2_self_test() != 0)
            return -1;
    }
    if (case_name == NULL || strcmp(case_name, "all") == 0 ||
        strcmp(case_name, "ike_key_derivation") == 0) {
        if (ipsec_utest_ike_key_derivation() != 0)
            return -1;
    }
    if (case_name == NULL || strcmp(case_name, "all") == 0 ||
        strcmp(case_name, "esp_cbc_roundtrip_replay") == 0) {
        if (ipsec_utest_esp_roundtrip(0) != 0)
            return -1;
    }
    if (case_name == NULL || strcmp(case_name, "all") == 0 ||
        strcmp(case_name, "esp_gcm_roundtrip_replay") == 0) {
        if (ipsec_utest_esp_roundtrip(1) != 0)
            return -1;
    }
    if (case_name != NULL && strcmp(case_name, "all") != 0 &&
        strcmp(case_name, "mschapv2_rfc_vectors") != 0 &&
        strcmp(case_name, "ike_key_derivation") != 0 &&
        strcmp(case_name, "esp_cbc_roundtrip_replay") != 0 &&
        strcmp(case_name, "esp_gcm_roundtrip_replay") != 0)
        return -1;
    return 0;
}

#endif /* defined(LUAT_USE_UTEST) && defined(LUAT_USE_NETDRV_IPSEC) */
