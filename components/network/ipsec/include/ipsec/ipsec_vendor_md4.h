/**
 * \file ipsec_vendor_md4.h
 *
 * \brief MD4 message digest (vendored for EAP-MSCHAPv2)
 *
 * MD4 is only used for MS-CHAPv2's NT-Hash computation (RFC 2759).
 * The mbedTLS 3.x build does not ship MD4, so the Apache-2.0 licensed
 * implementation from mbedTLS 2.x is vendored here with a renamed API.
 *
 *  Copyright The Mbed TLS Contributors
 *  SPDX-License-Identifier: Apache-2.0
 */
#ifndef IPSEC_VENDOR_MD4_H
#define IPSEC_VENDOR_MD4_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ipsec_md4_context {
    uint32_t total[2];
    uint32_t state[4];
    unsigned char buffer[64];
} ipsec_md4_context;

void ipsec_md4_init(ipsec_md4_context *ctx);
void ipsec_md4_free(ipsec_md4_context *ctx);
void ipsec_md4_clone(ipsec_md4_context *dst, const ipsec_md4_context *src);

int ipsec_md4_starts(ipsec_md4_context *ctx);
int ipsec_md4_update(ipsec_md4_context *ctx, const unsigned char *input, size_t ilen);
int ipsec_md4_finish(ipsec_md4_context *ctx, unsigned char output[16]);
int ipsec_md4(const unsigned char *input, size_t ilen, unsigned char output[16]);

#ifdef __cplusplus
}
#endif

#endif /* IPSEC_VENDOR_MD4_H */
