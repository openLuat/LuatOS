/*
 * chap_ms.c - Microsoft MS-CHAP compatible implementation (client side).
 *
 * Copyright (c) 1995 Eric Rosenquist.  All rights reserved.
 * Copyright (c) 2002 Google, Inc.  All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in
 *    the documentation and/or other materials provided with the
 *    distribution.
 *
 * 3. The name(s) of the authors of this software must not be used to
 *    endorse or promote products derived from this software without
 *    prior written permission.
 *
 * THE AUTHORS OF THIS SOFTWARE DISCLAIM ALL WARRANTIES WITH REGARD TO
 * THIS SOFTWARE, INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY
 * AND FITNESS, IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY
 * SPECIAL, INDIRECT OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN
 * AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING
 * OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *
 * Ported for LuatOS netdrv ipsec EAP-MSCHAPv2:
 *   - only the authenticatee (client) path is kept;
 *   - crypto primitives map to the vendored ipsec_md4 and mbedTLS
 *     (SHA-1 via mbedtls_md, DES via mbedtls_des);
 *   - MSK derivation (RFC 3079) added for IKEv2 §2.16 key-generating EAP.
 */

#include "ipsec/ipsec_vendor_chap_ms.h"
#include "ipsec/ipsec_vendor_md4.h"

#include <string.h>
#include <stdio.h>

#include "luat_crypto.h"
#include "mbedtls/md.h"
#include "mbedtls/des.h"

#define IPSEC_SHA1_LEN       20
#define IPSEC_MAX_NT_PASSWORD 256

/* MS-CHAPv2 opcodes */
#define IPSEC_MSCHAP2_CHALLENGE  1
#define IPSEC_MSCHAP2_RESPONSE   2
#define IPSEC_MSCHAP2_SUCCESS    3
#define IPSEC_MSCHAP2_FAILURE    4

/* Offsets within the 49-byte MS-CHAPv2 response field */
#define MS_CHAP2_PEER_CHALLENGE  0
#define MS_CHAP2_PEER_CHAL_LEN   16
#define MS_CHAP2_RESERVED_LEN    8
#define MS_CHAP2_NTRESP          24
#define MS_CHAP2_NTRESP_LEN      24
#define MS_CHAP2_FLAGS           48

/* RFC 3079 "Magic" constants */
static const uint8_t mschap_magic_masterkey[27] =
    { 0x54, 0x68, 0x69, 0x73, 0x20, 0x69, 0x73, 0x20, 0x74, 0x68,
      0x65, 0x20, 0x4d, 0x50, 0x50, 0x45, 0x20, 0x4d, 0x61, 0x73,
      0x74, 0x65, 0x72, 0x20, 0x4b, 0x65, 0x79 };
/* "On the client side, this is the send key; on the server side, it is the receive key." */
static const uint8_t mschap_magic_send[84] =
    { 0x4f, 0x6e, 0x20, 0x74, 0x68, 0x65, 0x20, 0x63, 0x6c, 0x69,
      0x65, 0x6e, 0x74, 0x20, 0x73, 0x69, 0x64, 0x65, 0x2c, 0x20,
      0x74, 0x68, 0x69, 0x73, 0x20, 0x69, 0x73, 0x20, 0x74, 0x68,
      0x65, 0x20, 0x73, 0x65, 0x6e, 0x64, 0x20, 0x6b, 0x65, 0x79,
      0x3b, 0x20, 0x6f, 0x6e, 0x20, 0x74, 0x68, 0x65, 0x20, 0x73,
      0x65, 0x72, 0x76, 0x65, 0x72, 0x20, 0x73, 0x69, 0x64, 0x65,
      0x2c, 0x20, 0x69, 0x74, 0x20, 0x69, 0x73, 0x20, 0x74, 0x68,
      0x65, 0x20, 0x72, 0x65, 0x63, 0x65, 0x69, 0x76, 0x65, 0x20,
      0x6b, 0x65, 0x79, 0x2e };
/* "On the client side, this is the receive key; on the server side, it is the send key." */
static const uint8_t mschap_magic_recv[84] =
    { 0x4f, 0x6e, 0x20, 0x74, 0x68, 0x65, 0x20, 0x63, 0x6c, 0x69,
      0x65, 0x6e, 0x74, 0x20, 0x73, 0x69, 0x64, 0x65, 0x2c, 0x20,
      0x74, 0x68, 0x69, 0x73, 0x20, 0x69, 0x73, 0x20, 0x74, 0x68,
      0x65, 0x20, 0x72, 0x65, 0x63, 0x65, 0x69, 0x76, 0x65, 0x20,
      0x6b, 0x65, 0x79, 0x3b, 0x20, 0x6f, 0x6e, 0x20, 0x74, 0x68,
      0x65, 0x20, 0x73, 0x65, 0x72, 0x76, 0x65, 0x72, 0x20, 0x73,
      0x69, 0x64, 0x65, 0x2c, 0x20, 0x69, 0x74, 0x20, 0x69, 0x73,
      0x20, 0x74, 0x68, 0x65, 0x20, 0x73, 0x65, 0x6e, 0x64, 0x20,
      0x6b, 0x65, 0x79, 0x2e };

/* RFC 2759 §4.3 magic strings */
static const uint8_t mschap_magic1[39] =
    { 0x4d, 0x61, 0x67, 0x69, 0x63, 0x20, 0x73, 0x65, 0x72, 0x76,
      0x65, 0x72, 0x20, 0x74, 0x6f, 0x20, 0x63, 0x6c, 0x69, 0x65,
      0x6e, 0x74, 0x20, 0x73, 0x69, 0x67, 0x6e, 0x69, 0x6e, 0x67,
      0x20, 0x63, 0x6f, 0x6e, 0x73, 0x74, 0x61, 0x6e, 0x74 };
static const uint8_t mschap_magic2[41] =
    { 0x50, 0x61, 0x64, 0x20, 0x74, 0x6f, 0x20, 0x6d, 0x61, 0x6b,
      0x65, 0x20, 0x69, 0x74, 0x20, 0x64, 0x6f, 0x20, 0x6d, 0x6f,
      0x72, 0x65, 0x20, 0x74, 0x68, 0x61, 0x6e, 0x20, 0x6f, 0x6e,
      0x65, 0x20, 0x69, 0x74, 0x65, 0x72, 0x61, 0x74, 0x69, 0x6f,
      0x6e };

static int mschap_sha1(const uint8_t *input, size_t ilen, uint8_t output[20])
{
    const mbedtls_md_info_t *info = mbedtls_md_info_from_type(MBEDTLS_MD_SHA1);
    if (info == NULL)
        return -1;
    return mbedtls_md(info, input, ilen, output);
}

/* Extract 7 bits starting at startBit of the 56-bit key stream */
static uint8_t mschap_get_7bits(const uint8_t *input, int startBit)
{
    unsigned int word;
    word = (unsigned int)input[startBit / 8] << 8;
    word |= (unsigned int)input[startBit / 8 + 1];
    word >>= 15 - (startBit % 8 + 7);
    return (uint8_t)(word & 0xFE);
}

/* Expand 56-bit (7x8) key into 64-bit DES key with parity bits */
static void mschap_56_to_64_bit_key(const uint8_t *key, uint8_t *des_key)
{
    int i;
    for (i = 0; i < 8; i++)
        des_key[i] = mschap_get_7bits(key, i * 7);
}

/* DES encrypt one 8-byte block with a 7-byte key taken from PasswordHash */
static int des_encrypt_block(const uint8_t *key7, const uint8_t input[8],
                             uint8_t output[8])
{
    uint8_t des_key[8];
    mbedtls_des_context ctx;
    int ret;

    mschap_56_to_64_bit_key(key7, des_key);
    mbedtls_des_init(&ctx);
    ret = mbedtls_des_setkey_enc(&ctx, des_key);
    if (ret == 0)
        ret = mbedtls_des_crypt_ecb(&ctx, input, output);
    mbedtls_des_free(&ctx);
    return ret;
}

/* RFC 2759 ChallengeResponse */
static void mschap_challenge_response(const uint8_t *challenge,
                                      const uint8_t password_hash[16],
                                      uint8_t response[24])
{
    uint8_t zpassword_hash[21];

    memset(zpassword_hash, 0, sizeof(zpassword_hash));
    memcpy(zpassword_hash, password_hash, 16);

    des_encrypt_block(zpassword_hash + 0,  challenge, response + 0);
    des_encrypt_block(zpassword_hash + 7,  challenge, response + 8);
    des_encrypt_block(zpassword_hash + 14, challenge, response + 16);
}

/* RFC 2759 ChallengeHash: SHA1(PeerChallenge|ServerChallenge|User)[0..7] */
static void mschap_challenge_hash(const uint8_t peer_challenge[16],
                                  const uint8_t *rchallenge,
                                  const char *username, uint16_t username_len,
                                  uint8_t challenge[8])
{
    uint8_t sha1_hash[IPSEC_SHA1_LEN];
    mbedtls_md_context_t md_ctx;
    const mbedtls_md_info_t *info = mbedtls_md_info_from_type(MBEDTLS_MD_SHA1);

    mbedtls_md_init(&md_ctx);
    if (info && mbedtls_md_setup(&md_ctx, info, 0) == 0) {
        mbedtls_md_starts(&md_ctx);
        mbedtls_md_update(&md_ctx, peer_challenge, 16);
        mbedtls_md_update(&md_ctx, rchallenge, 16);
        mbedtls_md_update(&md_ctx, (const unsigned char *)username, username_len);
        mbedtls_md_finish(&md_ctx, sha1_hash);
        memcpy(challenge, sha1_hash, 8);
    } else {
        memset(challenge, 0, 8);
    }
    mbedtls_md_free(&md_ctx);
}

/* ASCII -> UTF-16LE, little-endian byte order (MS-CHAP requires this) */
static void mschap_ascii2unicode(const char *ascii, int ascii_len,
                                 uint8_t *unicode)
{
    int i;
    memset(unicode, 0, (size_t)ascii_len * 2);
    for (i = 0; i < ascii_len; i++)
        unicode[i * 2] = (uint8_t)ascii[i];
}

static void mschap_nt_password_hash(const uint8_t *secret, int secret_len,
                                    uint8_t hash[16])
{
    ipsec_md4(secret, (size_t)secret_len, hash);
}

/* Strip "DOMAIN\" prefix, MS-CHAPv2 uses the bare user name. */
static const char *mschap_user(const char *username, uint16_t username_len,
                               uint16_t *user_len)
{
    const char *p = NULL;
    uint16_t i;

    for (i = 0; i < username_len; i++) {
        if (username[i] == '\\')
            p = username + i;
    }
    if (p != NULL) {
        if (user_len)
            *user_len = (uint16_t)(username_len - (uint16_t)(p - username) - 1);
        return p + 1;
    }
    if (user_len)
        *user_len = username_len;
    return username;
}

int ipsec_mschapv2_parse_challenge(const uint8_t *data, uint16_t data_len,
                                   uint8_t *mschap_id, const char **name,
                                   uint16_t *name_len, uint8_t challenge[16])
{
    /* strongSwan wire format (also used by Windows clients):
     *   opcode(1) | ms-chapv2-id(1) | ms-length(2, = EAP len - 5)
     *   | value-size(1) | challenge(16) | name(variable)
     */
    if (data_len < 4 + 1 + 16)
        return -1;
    if (data[0] != IPSEC_MSCHAP2_CHALLENGE)
        return -1;
    if (mschap_id)
        *mschap_id = data[1];
    if (data[4] != 16)
        return -1;
    if (name)
        *name = (const char *)(data + 5 + 16);
    if (name_len)
        *name_len = (uint16_t)(data_len - 5 - 16);
    if (challenge)
        memcpy(challenge, data + 5, 16);
    return 0;
}

int ipsec_mschapv2_make_response(const char *username, uint16_t username_len,
                                 const char *password, uint16_t password_len,
                                 const uint8_t rchallenge[16],
                                 uint8_t peer_challenge[16],
                                 uint8_t nt_response[24],
                                 char auth_response[41],
                                 uint8_t msk[64],
                                 uint8_t *out, uint16_t out_cap, uint16_t *out_len)
{
    uint8_t unicode_password[IPSEC_MAX_NT_PASSWORD * 2];
    uint8_t nt_hash[16];
    uint8_t password_hash_hash[16];
    uint8_t challenge[8];
    uint8_t master_key[IPSEC_SHA1_LEN];
    uint8_t digest[IPSEC_SHA1_LEN];
    uint8_t send_key[32], recv_key[32];
    uint8_t inner[79];
    uint8_t key_buf[16 + 40 + 84 + 40];
    const char *user;
    uint16_t nlen;
    uint8_t *p = out;
    int i;

    if (peer_challenge == NULL || out == NULL || out_len == NULL)
        return -1;
    if (username_len > 255 || password_len > IPSEC_MAX_NT_PASSWORD)
        return -1;
    user = mschap_user(username, username_len, &nlen);
    if (nlen > 255)
        return -1;
    /* strongSwan layout: opcode(1) id(1) ms_length(2) value_size(1)
     * response(49) name(nlen) */
    if (out_cap < (uint16_t)(4 + 1 + 49 + nlen))
        return -1;
    /* Peer challenge: 16 random bytes */
    luat_crypto_trng((char *)peer_challenge, 16);

    /* NT hash: MD4(UTF-16LE password) */
    mschap_ascii2unicode(password, password_len, unicode_password);
    mschap_nt_password_hash(unicode_password, password_len * 2, nt_hash);
    mschap_nt_password_hash(nt_hash, 16, password_hash_hash);

    /* Challenge(8) = SHA1(PeerChallenge|ServerChallenge|User)[0:8] */
    mschap_challenge_hash(peer_challenge, rchallenge, user, nlen, challenge);
    mschap_challenge_response(challenge, nt_hash, nt_response);

    /* Authenticator Response (RFC 2759 §4.3) */
    if (auth_response) {
        memcpy(inner, password_hash_hash, 16);
        memcpy(inner + 16, nt_response, 24);
        memcpy(inner + 40, mschap_magic1, 39);
        mschap_sha1(inner, sizeof(inner), digest);
        memcpy(inner, digest, 20);
        memcpy(inner + 20, challenge, 8);
        memcpy(inner + 28, mschap_magic2, 41);
        mschap_sha1(inner, 20 + 8 + 41, digest);
        for (i = 0; i < 20; i++)
            sprintf(auth_response + i * 2, "%02X", digest[i]);
    }

    /* MSK (RFC 3079 as implemented by strongSwan):
     *   master = SHA1(PasswordHashHash | NT-Response | Magic1)
     *   recv   = SHA1(master[0:16] | 0x00*40 | Magic2 | 0xF2*40)
     *   send   = SHA1(master[0:16] | 0x00*40 | Magic3 | 0xF2*40)
     *   MSK    = recv[0:16] | send[0:16] | 0x00*16 | 0x00*16
     * Magic2 = "client side send key" (peer->server),
     * Magic3 = "client side receive key" (server->peer). */
    if (msk) {
        uint8_t pad1[40];
        uint8_t pad2[40];
        uint8_t keypad[16];
        uint16_t key_len = (uint16_t)(16 + 40 + 84 + 40);

        memset(pad1, 0x00, sizeof(pad1));
        memset(pad2, 0xF2, sizeof(pad2));
        memset(keypad, 0x00, sizeof(keypad));

        memcpy(inner, password_hash_hash, 16);
        memcpy(inner + 16, nt_response, 24);
        memcpy(inner + 40, mschap_magic_masterkey, 27);
        mschap_sha1(inner, 16 + 24 + 27, master_key);

        memcpy(key_buf, master_key, 16);
        memcpy(key_buf + 16, pad1, sizeof(pad1));
        memcpy(key_buf + 16 + 40, mschap_magic_send, 84);
        memcpy(key_buf + 16 + 40 + 84, pad2, sizeof(pad2));
        mschap_sha1(key_buf, key_len, digest);
        memcpy(recv_key, digest, 16);

        memcpy(key_buf + 16 + 40, mschap_magic_recv, 84);
        mschap_sha1(key_buf, key_len, digest);
        memcpy(send_key, digest, 16);

        memcpy(msk, recv_key, 16);
        memcpy(msk + 16, send_key, 16);
        memcpy(msk + 32, keypad, 16);
        memcpy(msk + 48, keypad, 16);
    }

    /* Serialize opcode 2 response body (strongSwan wire format) */
    p[0] = IPSEC_MSCHAP2_RESPONSE;
    p[1] = 0; /* ms-chapv2 id set by caller */
    {
        uint16_t total = (uint16_t)(5 + 4 + 1 + 49 + nlen);
        uint16_t ms_len = (uint16_t)(total - 5);
        p[2] = (uint8_t)(ms_len >> 8);
        p[3] = (uint8_t)(ms_len);
    }
    p[4] = 49; /* value-size */
    memcpy(p + 5, peer_challenge, 16);
    memset(p + 5 + 16, 0, 8);
    memcpy(p + 5 + 24, nt_response, 24);
    p[5 + 48] = 0x00; /* flags */
    memcpy(p + 5 + 49, user, nlen);
    *out_len = (uint16_t)(5 + 49 + nlen);

    return 0;
}

int ipsec_mschapv2_verify_success(const char auth_response[41],
                                  const uint8_t *data, uint16_t data_len)
{
    /* strongSwan success: opcode(1) id(1) ms_length(2) "S=<40hex> M=..." */
    if (data_len < 4 + 2 + IPSEC_MSCHAPV2_AUTHRESP_LEN ||
        data[0] != IPSEC_MSCHAP2_SUCCESS)
        return -1;
    if (data[4] != 'S' || data[5] != '=')
        return -1;
    if (memcmp(data + 6, auth_response, IPSEC_MSCHAPV2_AUTHRESP_LEN) != 0)
        return -1;
    return 0;
}

int ipsec_mschapv2_self_test(void)
{
    /* RFC 1320: MD4("abc") */
    static const uint8_t md4_abc[16] =
        { 0xA4, 0x48, 0x01, 0x7A, 0xAF, 0x21, 0xD8, 0x52,
          0x5F, 0xC1, 0x0A, 0xE8, 0x7A, 0xA6, 0x72, 0x9D };
    /* RFC 2759 §9.2 vectors */
    static const uint8_t auth_challenge[16] =
        { 0x5B, 0x5D, 0x7C, 0x7D, 0x7B, 0x3F, 0x2F, 0x3E,
          0x3C, 0x2C, 0x60, 0x21, 0x32, 0x26, 0x26, 0x28 };
    static const uint8_t peer_challenge[16] =
        { 0x21, 0x40, 0x23, 0x24, 0x25, 0x5E, 0x26, 0x2A,
          0x28, 0x29, 0x5F, 0x2B, 0x3A, 0x33, 0x7C, 0x7E };
    static const uint8_t exp_nt_hash[16] =
        { 0x44, 0xEB, 0xBA, 0x8D, 0x53, 0x12, 0xB8, 0xD6,
          0x11, 0x47, 0x44, 0x11, 0xF5, 0x69, 0x89, 0xAE };
    static const uint8_t exp_nt_response[24] =
        { 0x82, 0x30, 0x9E, 0xCD, 0x8D, 0x70, 0x8B, 0x5E,
          0xA0, 0x8F, 0xAA, 0x39, 0x81, 0xCD, 0x83, 0x54,
          0x42, 0x33, 0x11, 0x4A, 0x3D, 0x85, 0xD6, 0xDF };
    const char *username = "User";
    const char *password = "clientPass";
    uint8_t unicode[32];
    uint8_t nt_hash[16];
    uint8_t challenge[8];
    uint8_t nt_response[24];
    char auth_response[41];
    uint8_t md4_out[16];

    if (ipsec_md4((const unsigned char *)"abc", 3, md4_out) != 0 ||
        memcmp(md4_out, md4_abc, 16) != 0)
        return -1;

    mschap_ascii2unicode(password, (int)strlen(password), unicode);
    mschap_nt_password_hash(unicode, (int)strlen(password) * 2, nt_hash);
    if (memcmp(nt_hash, exp_nt_hash, 16) != 0)
        return -2;

    mschap_challenge_hash(peer_challenge, auth_challenge, username,
                          (uint16_t)strlen(username), challenge);
    mschap_challenge_response(challenge, nt_hash, nt_response);
    if (memcmp(nt_response, exp_nt_response, 24) != 0)
        return -3;

    /* Authenticator Response: "S=407A5589115FD0D6209F510FE9C04566932CDA56" */
    {
        uint8_t hash_hash[16];
        uint8_t digest[20];
        uint8_t inner[79];
        char expect[41] = "407A5589115FD0D6209F510FE9C04566932CDA56";
        int i;
        mschap_nt_password_hash(nt_hash, 16, hash_hash);
        memcpy(inner, hash_hash, 16);
        memcpy(inner + 16, nt_response, 24);
        memcpy(inner + 40, mschap_magic1, 39);
        mschap_sha1(inner, sizeof(inner), digest);
        memcpy(inner, digest, 20);
        memcpy(inner + 20, challenge, 8);
        memcpy(inner + 28, mschap_magic2, 41);
        mschap_sha1(inner, 20 + 8 + 41, digest);
        for (i = 0; i < 20; i++)
            sprintf(auth_response + i * 2, "%02X", digest[i]);
        if (memcmp(auth_response, expect, 40) != 0)
            return -4;
    }
    return 0;
}
