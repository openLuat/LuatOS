/* AI-MANAGED: true */
/* SPDX-License-Identifier: EPL-2.0 OR Apache-2.0 */
#ifndef ZENOH_PICO_UTILS_AUTH_H
#define ZENOH_PICO_UTILS_AUTH_H
#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>
#include "zenoh-pico/utils/result.h"
#include "zenoh-pico/config.h"
#define ZP_LUATOS_PATCH_ABI 20261111
#define _Z_USRPWD_MAX 128
#ifdef ZP_AUTH_OBSERVER
void ZP_AUTH_OBSERVER(int stage, int remote_reason);
#define _Z_AUTH_OBSERVE(stage, reason) ZP_AUTH_OBSERVER(stage, reason)
#else
#define _Z_AUTH_OBSERVE(stage, reason) ((void)0)
#endif
/* A synchronous view of the config owned by z_open. Never retained by transport. */
typedef struct { const char *user; const char *password; } _z_usrpwd_view_t;
void _z_secure_zero(void *memory, size_t length);
bool _z_usrpwd_credential_valid(const char *value);
void _z_usrpwd_sha3_256(uint8_t out[32], const uint8_t *input, size_t length);
z_result_t _z_usrpwd_hmac(uint8_t out[32], uint64_t nonce, const char *password);
z_result_t _z_usrpwd_selftest(void);
#endif
