/*
 * ESP tunnel mode (RFC 4303) data path for LuatOS netdrv ipsec.
 *
 * Supports AES-CBC-128/256 + HMAC-SHA1-96 / HMAC-SHA2-256-128 with a
 * 32-packet sliding anti-replay window.  The packet format is
 * ESP-in-UDP (RFC 3948): SPI | SEQ | IV | ciphertext | pad | padlen |
 * nexthdr | ICV, no UDP-encapsulation marker.
 */

#include "ipsec_esp.h"
#include "ipsec_crypto.h"

#include <string.h>

#include "luat_crypto.h"
#include "mbedtls/aes.h"
#include "mbedtls/md.h"

#define IPSEC_ESP_IPV4_PROTO 4

static int esp_hmac(const uint8_t *key, size_t key_len,
                    const uint8_t *in, size_t in_len,
                    mbedtls_md_type_t md_type, uint8_t *out)
{
    const mbedtls_md_info_t *info = mbedtls_md_info_from_type(md_type);
    if (info == NULL)
        return -1;
    return mbedtls_md_hmac(info, key, key_len, in, in_len, out);
}

static uint16_t esp_icv_len(const ipsec_esp_sa_t *sa)
{
    return sa->integ_alg == IPSEC_INTEG_SHA1 ? IPSEC_ESP_ICV_SHA1_LEN
                                             : IPSEC_ESP_ICV_SHA256_LEN;
}

void ipsec_esp_sa_init(ipsec_esp_sa_t *sa, uint32_t spi,
                       uint8_t enc_alg, uint8_t integ_alg,
                       const uint8_t *enc_key, const uint8_t *integ_key)
{
    memset(sa, 0, sizeof(*sa));
    sa->valid = 1;
    sa->spi = spi;
    sa->enc_alg = enc_alg;
    sa->integ_alg = integ_alg;
    sa->enc_key_len = enc_alg == IPSEC_ENC_AES128 ? 16 : 32;
    sa->integ_key_len = integ_alg == IPSEC_INTEG_SHA1 ? 20 : 32;
    memcpy(sa->enc_key, enc_key, sa->enc_key_len);
    memcpy(sa->integ_key, integ_key, sa->integ_key_len);
    sa->seq_out = 1;
}

int ipsec_esp_replay_check(ipsec_esp_sa_t *sa, uint32_t seq)
{
    uint32_t diff;
    uint32_t bit;

    if (seq == 0)
        return -1;
    if (sa->replay_last == 0) {
        sa->replay_last = seq;
        sa->replay_bitmap = 1;
        return 0;
    }
    if (seq > sa->replay_last) {
        diff = seq - sa->replay_last;
        if (diff >= IPSEC_ESP_REPLAY_WINDOW) {
            sa->replay_bitmap = 1;
        } else {
            sa->replay_bitmap <<= diff;
            sa->replay_bitmap |= 1;
        }
        sa->replay_last = seq;
        return 0;
    }
    diff = sa->replay_last - seq;
    if (diff >= IPSEC_ESP_REPLAY_WINDOW)
        return -1;
    bit = (uint32_t)1 << diff;
    if (sa->replay_bitmap & bit)
        return -1;
    sa->replay_bitmap |= bit;
    return 0;
}

int ipsec_esp_encrypt(ipsec_esp_sa_t *sa, const uint8_t *ip, uint16_t iplen,
                      uint8_t *out, uint16_t *outlen)
{
    uint8_t iv[IPSEC_ESP_BLOCK_LEN];
    uint8_t icv[32];
    mbedtls_aes_context aes;
    mbedtls_md_type_t md_type;
    uint16_t pad_len;
    uint16_t ct_len;
    uint16_t total;
    uint32_t seq;
    int ret;

    if (sa == NULL || !sa->valid || ip == NULL || out == NULL || iplen < 20)
        return -1;
    if (iplen > 1500)
        return -1;

    seq = sa->seq_out++;

    /* ESP header: SPI | SEQ (network byte order) */
    out[0] = (uint8_t)(sa->spi >> 24);
    out[1] = (uint8_t)(sa->spi >> 16);
    out[2] = (uint8_t)(sa->spi >> 8);
    out[3] = (uint8_t)(sa->spi);
    out[4] = (uint8_t)(seq >> 24);
    out[5] = (uint8_t)(seq >> 16);
    out[6] = (uint8_t)(seq >> 8);
    out[7] = (uint8_t)(seq);

    /* IV: 16 random bytes (CBC) */
    luat_crypto_trng((char *)iv, sizeof(iv));
    memcpy(out + 8, iv, sizeof(iv));

    /* Plaintext = inner IP | padding | pad_len | next_hdr; total multiple of 16 */
    pad_len = (uint16_t)(16 - ((iplen + 2) % 16));
    if (pad_len == 16)
        pad_len = 0;
    ct_len = (uint16_t)(iplen + pad_len + 2);

    memcpy(out + 8 + 16, ip, iplen);
    memset(out + 8 + 16 + iplen, 0, pad_len);
    out[8 + 16 + iplen + pad_len] = (uint8_t)pad_len;
    out[8 + 16 + iplen + pad_len + 1] = IPSEC_ESP_IPV4_PROTO;

    /* AES-CBC encrypt in place */
    mbedtls_aes_init(&aes);
    ret = mbedtls_aes_setkey_enc(&aes, sa->enc_key, sa->enc_key_len * 8);
    if (ret == 0)
        ret = mbedtls_aes_crypt_cbc(&aes, MBEDTLS_AES_ENCRYPT, ct_len,
                                    iv, out + 8 + 16, out + 8 + 16);
    mbedtls_aes_free(&aes);
    if (ret != 0)
        return -1;

    /* ICV over the whole ESP packet (header through pad length byte) */
    md_type = sa->integ_alg == IPSEC_INTEG_SHA1 ? MBEDTLS_MD_SHA1 : MBEDTLS_MD_SHA256;
    total = (uint16_t)(8 + 16 + ct_len);
    if (esp_hmac(sa->integ_key, sa->integ_key_len, out, total, md_type, icv) != 0)
        return -1;
    memcpy(out + total, icv, esp_icv_len(sa));
    total = (uint16_t)(total + esp_icv_len(sa));

    *outlen = total;
    return 0;
}

int ipsec_esp_decrypt(ipsec_esp_sa_t *sa, const uint8_t *in, uint16_t inlen,
                      uint8_t *out, uint16_t *outlen)
{
    uint8_t iv[IPSEC_ESP_BLOCK_LEN];
    uint8_t icv[32];
    uint8_t expected[32];
    mbedtls_aes_context aes;
    mbedtls_md_type_t md_type;
    uint16_t icv_len;
    uint16_t ct_len;
    uint16_t iplen;
    uint16_t pad_len;
    uint32_t seq;
    int ret;

    if (sa == NULL || !sa->valid || in == NULL || out == NULL)
        return -1;

    icv_len = esp_icv_len(sa);
    if (inlen < (uint16_t)(8 + 16 + 2 + icv_len))
        return -1;
    ct_len = (uint16_t)(inlen - 8 - 16 - icv_len);
    if ((ct_len % 16) != 0)
        return -1;

    /* Verify SPI */
    if (in[0] != (uint8_t)(sa->spi >> 24) || in[1] != (uint8_t)(sa->spi >> 16) ||
        in[2] != (uint8_t)(sa->spi >> 8) || in[3] != (uint8_t)(sa->spi))
        return -1;

    /* Anti-replay */
    seq = ((uint32_t)in[4] << 24) | ((uint32_t)in[5] << 16) |
          ((uint32_t)in[6] << 8) | (uint32_t)in[7];
    if (ipsec_esp_replay_check(sa, seq) != 0)
        return -1;

    /* Integrity over SPI..pad-length */
    md_type = sa->integ_alg == IPSEC_INTEG_SHA1 ? MBEDTLS_MD_SHA1 : MBEDTLS_MD_SHA256;
    memcpy(icv, in + 8 + 16 + ct_len, icv_len);
    if (esp_hmac(sa->integ_key, sa->integ_key_len, in, 8 + 16 + ct_len,
                 md_type, expected) != 0)
        return -1;
    if (memcmp(icv, expected, icv_len) != 0)
        return -1;

    /* Decrypt */
    memcpy(iv, in + 8, 16);
    mbedtls_aes_init(&aes);
    ret = mbedtls_aes_setkey_dec(&aes, sa->enc_key, sa->enc_key_len * 8);
    if (ret == 0)
        ret = mbedtls_aes_crypt_cbc(&aes, MBEDTLS_AES_DECRYPT, ct_len,
                                    iv, in + 8 + 16, out);
    mbedtls_aes_free(&aes);
    if (ret != 0)
        return -1;

    pad_len = out[ct_len - 2];
    if (out[ct_len - 1] != IPSEC_ESP_IPV4_PROTO)
        return -1;
    if (pad_len + 2 > ct_len)
        return -1;
    iplen = (uint16_t)(ct_len - pad_len - 2);
    if (iplen < 20)
        return -1;

    *outlen = iplen;
    return 0;
}
