/**
 * \file ipsec_vendor_chap_ms.h
 *
 * \brief MS-CHAPv2 (RFC 2759) client-side helpers for EAP-MSCHAPv2.
 *
 * The NT-Hash / NT-Response / Authenticator-Response logic is ported from
 * lwIP 2.2.1 netif/ppp/chap_ms.c (BSD-3-Clause, (c) Eric Rosenquist and
 * Google Inc.).  Only the client (authenticatee) path is kept.
 */
#ifndef IPSEC_VENDOR_CHAP_MS_H
#define IPSEC_VENDOR_CHAP_MS_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define IPSEC_MSCHAPV2_CHALLENGE_LEN    16
#define IPSEC_MSCHAPV2_NTRESP_LEN       24
#define IPSEC_MSCHAPV2_AUTHRESP_LEN     40    /* ASCII hex, without NUL */

/**
 * Parse an EAP-MSCHAPv2 Challenge request payload.
 *
 * \param data         EAP type data (everything after the EAP Type octet).
 * \param data_len     Length of \p data.
 * \param mschap_id    Out: MS-CHAPv2 identifier.
 * \param name         Out: peer name pointer inside \p data (not NUL terminated).
 * \param name_len     Out: peer name length.
 * \param challenge    Out: 16-byte challenge (may be NULL).
 *
 * \return 0 on success, -1 on malformed input / wrong opcode.
 */
int ipsec_mschapv2_parse_challenge(const uint8_t *data, uint16_t data_len,
                                   uint8_t *mschap_id, const char **name,
                                   uint16_t *name_len, uint8_t challenge[16]);

/**
 * Build an EAP-MSCHAPv2 Response payload (opcode 2).
 *
 * \param username       User name (no domain part).
 * \param username_len   Length of \p username.
 * \param password       Password (ASCII).
 * \param password_len   Length of \p password.
 * \param rchallenge     16-byte server challenge.
 * \param peer_challenge Out: 16-byte random peer challenge.
 * \param nt_response    Out: 24-byte NT-Response.
 * \param auth_response  Optional out: 41-byte buffer receiving the 40-hex
 *                       Authenticator-Response string (NUL terminated).
 * \param msk            Optional out: 64-byte MSK (RFC 3079).
 * \param out            Out: serialized payload body (opcode + fields).
 *                       Must hold at least 1+1+1+1+1+username_len+16+8+24+1
 *                       bytes.  Returns the body length in \p out_len.
 */
int ipsec_mschapv2_make_response(const char *username, uint16_t username_len,
                                 const char *password, uint16_t password_len,
                                 const uint8_t rchallenge[16],
                                 uint8_t peer_challenge[16],
                                 uint8_t nt_response[24],
                                 char auth_response[41],
                                 uint8_t msk[64],
                                 uint8_t *out, uint16_t out_cap, uint16_t *out_len);

/**
 * Verify the Authenticator-Response in an MS-CHAPv2 Success message.
 *
 * \param auth_response  40-hex Authenticator-Response string (upper case).
 * \param data           EAP type data (opcode 3 Success message).
 * \param data_len       Length of \p data.
 *
 * \return 0 if the success message carries a matching "S=<auth>" value.
 */
int ipsec_mschapv2_verify_success(const char auth_response[41],
                                  const uint8_t *data, uint16_t data_len);

/**
 * Self test against RFC 2759 §9.2 test vectors (and RFC 1320 MD4 vectors).
 * \return 0 on success.
 */
int ipsec_mschapv2_self_test(void);

#ifdef __cplusplus
}
#endif

#endif /* IPSEC_VENDOR_CHAP_MS_H */
