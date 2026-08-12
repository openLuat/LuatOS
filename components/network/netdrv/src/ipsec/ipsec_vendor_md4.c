/*
 *  RFC 1186/1320 compliant MD4 implementation (vendored from mbedTLS 2.x)
 *
 *  Copyright The Mbed TLS Contributors
 *  SPDX-License-Identifier: Apache-2.0
 *
 *  Licensed under the Apache License, Version 2.0 (the "License"); you may
 *  not use this file except in compliance with the License.
 *  You may obtain a copy of the License at
 *
 *  http://www.apache.org/licenses/LICENSE-2.0
 *
 *  Unless required by applicable law or agreed to in writing, software
 *  distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
 *  WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *  See the License for the specific language governing permissions and
 *  limitations under the License.
 */
/*
 *  The MD4 algorithm was designed by Ron Rivest in 1990.
 *  http://www.ietf.org/rfc/rfc1186.txt
 *  http://www.ietf.org/rfc/rfc1320.txt
 *
 *  Adaptations for LuatOS netdrv ipsec:
 *    - API renamed ipsec_md4_* to avoid clashing with mbedTLS 2.x builds.
 *    - Removed mbedTLS dependency shims (GET/PUT_UINT32_LE, platform_zeroize)
 *      so this file is fully self-contained.
 */

#include "ipsec_vendor_md4.h"

#include <string.h>

static uint32_t get_u32le(const unsigned char *b, size_t off)
{
    return ((uint32_t)b[off]) | ((uint32_t)b[off + 1] << 8) |
           ((uint32_t)b[off + 2] << 16) | ((uint32_t)b[off + 3] << 24);
}

static void put_u32le(uint32_t v, unsigned char *b, size_t off)
{
    b[off] = (unsigned char)(v);
    b[off + 1] = (unsigned char)(v >> 8);
    b[off + 2] = (unsigned char)(v >> 16);
    b[off + 3] = (unsigned char)(v >> 24);
}

void ipsec_md4_init(ipsec_md4_context *ctx)
{
    memset(ctx, 0, sizeof(ipsec_md4_context));
}

void ipsec_md4_free(ipsec_md4_context *ctx)
{
    if (ctx == NULL)
        return;
    memset(ctx, 0, sizeof(ipsec_md4_context));
}

void ipsec_md4_clone(ipsec_md4_context *dst, const ipsec_md4_context *src)
{
    *dst = *src;
}

int ipsec_md4_starts(ipsec_md4_context *ctx)
{
    ctx->total[0] = 0;
    ctx->total[1] = 0;

    ctx->state[0] = 0x67452301;
    ctx->state[1] = 0xEFCDAB89;
    ctx->state[2] = 0x98BADCFE;
    ctx->state[3] = 0x10325476;

    return 0;
}

static int md4_process(ipsec_md4_context *ctx, const unsigned char data[64])
{
    struct
    {
        uint32_t X[16], A, B, C, D;
    } local;

    local.X[0]  = get_u32le(data,  0);
    local.X[1]  = get_u32le(data,  4);
    local.X[2]  = get_u32le(data,  8);
    local.X[3]  = get_u32le(data, 12);
    local.X[4]  = get_u32le(data, 16);
    local.X[5]  = get_u32le(data, 20);
    local.X[6]  = get_u32le(data, 24);
    local.X[7]  = get_u32le(data, 28);
    local.X[8]  = get_u32le(data, 32);
    local.X[9]  = get_u32le(data, 36);
    local.X[10] = get_u32le(data, 40);
    local.X[11] = get_u32le(data, 44);
    local.X[12] = get_u32le(data, 48);
    local.X[13] = get_u32le(data, 52);
    local.X[14] = get_u32le(data, 56);
    local.X[15] = get_u32le(data, 60);

#define S(x, n) (((x) << (n)) | (((x) & 0xFFFFFFFF) >> (32 - (n))))

    local.A = ctx->state[0];
    local.B = ctx->state[1];
    local.C = ctx->state[2];
    local.D = ctx->state[3];

#define F(x, y, z) (((x) & (y)) | ((~(x)) & (z)))
#define P(a, b, c, d, x, s)                    \
    do {                                       \
        (a) += F((b), (c), (d)) + (x);         \
        (a) = S((a), (s));                     \
    } while (0)

    P(local.A, local.B, local.C, local.D, local.X[ 0],  3);
    P(local.D, local.A, local.B, local.C, local.X[ 1],  7);
    P(local.C, local.D, local.A, local.B, local.X[ 2], 11);
    P(local.B, local.C, local.D, local.A, local.X[ 3], 19);
    P(local.A, local.B, local.C, local.D, local.X[ 4],  3);
    P(local.D, local.A, local.B, local.C, local.X[ 5],  7);
    P(local.C, local.D, local.A, local.B, local.X[ 6], 11);
    P(local.B, local.C, local.D, local.A, local.X[ 7], 19);
    P(local.A, local.B, local.C, local.D, local.X[ 8],  3);
    P(local.D, local.A, local.B, local.C, local.X[ 9],  7);
    P(local.C, local.D, local.A, local.B, local.X[10], 11);
    P(local.B, local.C, local.D, local.A, local.X[11], 19);
    P(local.A, local.B, local.C, local.D, local.X[12],  3);
    P(local.D, local.A, local.B, local.C, local.X[13],  7);
    P(local.C, local.D, local.A, local.B, local.X[14], 11);
    P(local.B, local.C, local.D, local.A, local.X[15], 19);

#undef P
#undef F

#define F(x, y, z) (((x) & (y)) | ((x) & (z)) | ((y) & (z)))
#define P(a, b, c, d, x, s)                            \
    do {                                               \
        (a) += F((b), (c), (d)) + (x) + 0x5A827999;    \
        (a) = S((a), (s));                             \
    } while (0)

    P(local.A, local.B, local.C, local.D, local.X[ 0],  3);
    P(local.D, local.A, local.B, local.C, local.X[ 4],  5);
    P(local.C, local.D, local.A, local.B, local.X[ 8],  9);
    P(local.B, local.C, local.D, local.A, local.X[12], 13);
    P(local.A, local.B, local.C, local.D, local.X[ 1],  3);
    P(local.D, local.A, local.B, local.C, local.X[ 5],  5);
    P(local.C, local.D, local.A, local.B, local.X[ 9],  9);
    P(local.B, local.C, local.D, local.A, local.X[13], 13);
    P(local.A, local.B, local.C, local.D, local.X[ 2],  3);
    P(local.D, local.A, local.B, local.C, local.X[ 6],  5);
    P(local.C, local.D, local.A, local.B, local.X[10],  9);
    P(local.B, local.C, local.D, local.A, local.X[14], 13);
    P(local.A, local.B, local.C, local.D, local.X[ 3],  3);
    P(local.D, local.A, local.B, local.C, local.X[ 7],  5);
    P(local.C, local.D, local.A, local.B, local.X[11],  9);
    P(local.B, local.C, local.D, local.A, local.X[15], 13);

#undef P
#undef F

#define F(x, y, z) ((x) ^ (y) ^ (z))
#define P(a, b, c, d, x, s)                                  \
    do {                                                     \
        (a) += F((b), (c), (d)) + (x) + 0x6ED9EBA1;          \
        (a) = S((a), (s));                                   \
    } while (0)

    P(local.A, local.B, local.C, local.D, local.X[ 0],  3);
    P(local.D, local.A, local.B, local.C, local.X[ 8],  9);
    P(local.C, local.D, local.A, local.B, local.X[ 4], 11);
    P(local.B, local.C, local.D, local.A, local.X[12], 15);
    P(local.A, local.B, local.C, local.D, local.X[ 2],  3);
    P(local.D, local.A, local.B, local.C, local.X[10],  9);
    P(local.C, local.D, local.A, local.B, local.X[ 6], 11);
    P(local.B, local.C, local.D, local.A, local.X[14], 15);
    P(local.A, local.B, local.C, local.D, local.X[ 1],  3);
    P(local.D, local.A, local.B, local.C, local.X[ 9],  9);
    P(local.C, local.D, local.A, local.B, local.X[ 5], 11);
    P(local.B, local.C, local.D, local.A, local.X[13], 15);
    P(local.A, local.B, local.C, local.D, local.X[ 3],  3);
    P(local.D, local.A, local.B, local.C, local.X[11],  9);
    P(local.C, local.D, local.A, local.B, local.X[ 7], 11);
    P(local.B, local.C, local.D, local.A, local.X[15], 15);

#undef F
#undef P

    ctx->state[0] += local.A;
    ctx->state[1] += local.B;
    ctx->state[2] += local.C;
    ctx->state[3] += local.D;

    memset(&local, 0, sizeof(local));
    return 0;
}

int ipsec_md4_update(ipsec_md4_context *ctx, const unsigned char *input, size_t ilen)
{
    size_t fill;
    uint32_t left;

    if (ilen == 0)
        return 0;

    left = ctx->total[0] & 0x3F;
    fill = 64 - left;

    ctx->total[0] += (uint32_t)ilen;
    ctx->total[0] &= 0xFFFFFFFF;

    if (ctx->total[0] < (uint32_t)ilen)
        ctx->total[1]++;

    if (left && ilen >= fill)
    {
        memcpy(ctx->buffer + left, input, fill);
        if (md4_process(ctx, ctx->buffer) != 0)
            return -1;
        input += fill;
        ilen  -= fill;
        left = 0;
    }

    while (ilen >= 64)
    {
        if (md4_process(ctx, input) != 0)
            return -1;
        input += 64;
        ilen  -= 64;
    }

    if (ilen > 0)
        memcpy(ctx->buffer + left, input, ilen);

    return 0;
}

static const unsigned char md4_padding[64] = {
    0x80, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
};

int ipsec_md4_finish(ipsec_md4_context *ctx, unsigned char output[16])
{
    uint32_t last, padn;
    uint32_t high, low;
    unsigned char msglen[8];

    high = (ctx->total[0] >> 29) | (ctx->total[1] << 3);
    low  = (ctx->total[0] << 3);

    put_u32le(low,  msglen, 0);
    put_u32le(high, msglen, 4);

    last = ctx->total[0] & 0x3F;
    padn = (last < 56) ? (56 - last) : (120 - last);

    if (ipsec_md4_update(ctx, md4_padding, padn) != 0)
        return -1;
    if (ipsec_md4_update(ctx, msglen, 8) != 0)
        return -1;

    put_u32le(ctx->state[0], output,  0);
    put_u32le(ctx->state[1], output,  4);
    put_u32le(ctx->state[2], output,  8);
    put_u32le(ctx->state[3], output, 12);

    return 0;
}

int ipsec_md4(const unsigned char *input, size_t ilen, unsigned char output[16])
{
    ipsec_md4_context ctx;
    int ret;

    ipsec_md4_init(&ctx);
    ret = ipsec_md4_starts(&ctx);
    if (ret == 0)
        ret = ipsec_md4_update(&ctx, input, ilen);
    if (ret == 0)
        ret = ipsec_md4_finish(&ctx, output);
    ipsec_md4_free(&ctx);
    return ret;
}
