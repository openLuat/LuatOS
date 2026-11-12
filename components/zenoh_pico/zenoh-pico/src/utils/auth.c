/* AI-MANAGED: true */
/* SPDX-License-Identifier: EPL-2.0 OR Apache-2.0 */
#include "zenoh-pico/utils/auth.h"
#include <string.h>
void _z_secure_zero(void *memory, size_t length) {
    volatile uint8_t *p = (volatile uint8_t *)memory;
    while (length--) *p++ = 0;
}
bool _z_usrpwd_credential_valid(const char *value) {
    if (!value) return false;
    size_t n = 0; while (n <= _Z_USRPWD_MAX && value[n]) ++n;
    return n && n <= _Z_USRPWD_MAX && !memchr(value, '\r', n) && !memchr(value, '\n', n);
}
/* Zenoh 1.9: key is the challenge as eight LE bytes; message is the password.
 * This is deliberately not a general-purpose, arbitrary-key HMAC API. */
z_result_t _z_usrpwd_hmac(uint8_t out[32], uint64_t nonce, const char *password) {
    if (!out) return Z_EINVAL;
    memset(out, 0, 32);
    if (!_z_usrpwd_credential_valid(password)) return _Z_ERR_AUTH_CONFIG;
    uint8_t work[136 + _Z_USRPWD_MAX], inner[32];
    size_t n = strlen(password);
    memset(work, 0x36, 136);
    for (unsigned i = 0; i < 8; ++i) work[i] ^= (uint8_t)(nonce >> (8 * i));
    memcpy(work + 136, password, n);
    _z_usrpwd_sha3_256(inner, work, 136 + n);
    memset(work, 0x5c, 136);
    for (unsigned i = 0; i < 8; ++i) work[i] ^= (uint8_t)(nonce >> (8 * i));
    memcpy(work + 136, inner, 32);
    _z_usrpwd_sha3_256(out, work, 168);
    _z_secure_zero(work, sizeof(work)); _z_secure_zero(inner, sizeof(inner));
    return _Z_RES_OK;
}
z_result_t _z_usrpwd_selftest(void) {
    static const uint8_t expected[32] = {
        0x3a,0x98,0x5d,0xa7,0x4f,0xe2,0x25,0xb2,0x04,0x5c,0x17,0x2d,0x6b,0xd3,0x90,0xbd,
        0x85,0x5f,0x08,0x6e,0x3e,0x9d,0x52,0x5b,0x46,0xbf,0xe2,0x45,0x11,0x43,0x15,0x32};
    uint8_t actual[32]; _z_usrpwd_sha3_256(actual, (const uint8_t *)"abc", 3);
    int different = memcmp(actual, expected, 32);
    static const uint8_t hmac_expected[32] = {0xf5,0x14,0xe6,0x18,0x4c,0x0b,0x98,0x91,0x44,0xab,0x43,0xb5,0x44,0xbe,0x1b,0x12,0xf2,0x00,0x9d,0xc7,0x4b,0xc1,0xac,0x69,0xfb,0x5b,0x07,0x47,0x79,0xcd,0x84,0xf7};
    if (_z_usrpwd_hmac(actual, 0, "password") != _Z_RES_OK || memcmp(actual, hmac_expected, 32)) different = 1;
    _z_secure_zero(actual, sizeof(actual));
    return different ? _Z_ERR_AUTH_CRYPTO : _Z_RES_OK;
}
