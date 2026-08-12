/**
 * \file ipsec_esp.h
 *
 * \brief ESP tunnel-mode data path (RFC 4303) with AES-CBC + HMAC or
 *        AES-GCM (RFC 4106 AEAD) and a 32-packet anti-replay window.
 */
#ifndef IPSEC_ESP_H
#define IPSEC_ESP_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define IPSEC_ESP_ICV_SHA1_LEN    12   /* HMAC-SHA1-96 truncation */
#define IPSEC_ESP_ICV_SHA256_LEN  16   /* HMAC-SHA2-256-128 truncation */
#define IPSEC_ESP_GCM_IV_LEN      8    /* explicit 8-octet IV (RFC 4106) */
#define IPSEC_ESP_GCM_TAG_LEN     16   /* 128-bit GCM ICV */
#define IPSEC_ESP_GCM_SALT_LEN    4
#define IPSEC_ESP_BLOCK_LEN       16   /* AES block size */
#define IPSEC_ESP_REPLAY_WINDOW   32

typedef struct ipsec_esp_sa {
    uint8_t  valid;
    uint8_t  dying;              /* old SA kept for RX during rekey grace */
    uint32_t spi;                /* network byte order */
    uint8_t  enc_alg;            /* IPSEC_ENC_AES128 / IPSEC_ENC_AES256 */
    uint8_t  integ_alg;          /* IPSEC_INTEG_SHA1 / IPSEC_INTEG_SHA256 */
    uint8_t  aead;               /* AES-GCM AEAD SA */
    uint8_t  enc_key[32];
    uint8_t  integ_key[32];
    uint8_t  salt[IPSEC_ESP_GCM_SALT_LEN];
    uint8_t  enc_key_len;
    uint8_t  integ_key_len;
    uint32_t seq_out;
    uint32_t seq_in;
    uint32_t replay_last;        /* highest accepted inbound seq */
    uint32_t replay_bitmap;      /* bits for the previous 31 seqs */
    uint32_t installed_ms;       /* sys_now() timestamp */
} ipsec_esp_sa_t;

/**
 * Install a unidirectional ESP SA.
 *
 * \param sa      SA to fill.
 * \param spi     SPI in network byte order.
 * \param enc_alg IPSEC_ENC_AES128 / IPSEC_ENC_AES256.
 * \param integ_alg IPSEC_INTEG_SHA1 / IPSEC_INTEG_SHA256.
 * \param enc_key Encryption key (16/32 bytes).
 * \param integ_key Integrity key (20/32 bytes).
 */
void ipsec_esp_sa_init(ipsec_esp_sa_t *sa, uint32_t spi,
                       uint8_t enc_alg, uint8_t integ_alg,
                       const uint8_t *enc_key, const uint8_t *integ_key);

/**
 * Install an AES-GCM AEAD ESP SA (RFC 4106). The key material is the
 * encryption key followed by the 4-octet salt.
 */
void ipsec_esp_sa_init_aead(ipsec_esp_sa_t *sa, uint32_t spi,
                            uint8_t enc_alg,
                            const uint8_t *enc_key, const uint8_t *salt);

/**
 * Encapsulate an inner IPv4 packet into an ESP-in-UDP payload.
 *
 * \param sa     Outbound SA.
 * \param ip     Inner IP packet.
 * \param iplen  Inner packet length (>= 20).
 * \param out    Output buffer (at least iplen + 64 bytes).
 * \param outlen Out: total ESP payload length.
 *
 * \return 0 on success.
 */
int ipsec_esp_encrypt(ipsec_esp_sa_t *sa, const uint8_t *ip, uint16_t iplen,
                      uint8_t *out, uint16_t *outlen);

/**
 * Decapsulate an ESP-in-UDP payload back into an inner IPv4 packet.
 *
 * \param sa      Inbound SA.
 * \param in      ESP payload (starts with SPI).
 * \param inlen   ESP payload length.
 * \param out     Output buffer for the inner packet.
 * \param out_cap Capacity of \p out; oversized payloads are rejected before
 *                any byte is written.
 * \param outlen  Out: inner packet length.
 *
 * \return 0 on success (integrity OK, seq accepted), negative otherwise.
 */
int ipsec_esp_decrypt(ipsec_esp_sa_t *sa, const uint8_t *in, uint16_t inlen,
                      uint8_t *out, uint16_t out_cap, uint16_t *outlen);

/* Anti-replay window helpers (32 packets) */
int ipsec_esp_replay_check(ipsec_esp_sa_t *sa, uint32_t seq);

#ifdef __cplusplus
}
#endif

#endif /* IPSEC_ESP_H */
