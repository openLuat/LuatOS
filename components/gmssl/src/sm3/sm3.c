/**
 *
 *
 * \file        sm3.c
 *
 * \brief       this file is header file for sm3(chinese business Digital Digest).
 *              and  compatible md framework.
 *
 * \anchor      lzj
 *
 * \date        2017/8/14
 *
 *
 */


#include <mbedtls/config.h>
#include <sm3/sm3.h>
#include <string.h>

#if defined(MBEDTLS_SELF_TEST)

#include <stdio.h>
#include <stdlib.h>

#ifdef ANDROID_LOG
#include <android/log.h>
#define mbedtls_printf(...)  __android_log_print(ANDROID_LOG_DEBUG, "SECURITY_LIBRARY", __VA_ARGS__)
#else
#define mbedtls_printf     printf
#endif

#define mbedtls_calloc    calloc
#define mbedtls_free       free
#endif /* MBEDTLS_SELF_TEST */


#define SM3_DIGEST_LENGTH    32
#define SM3_BLOCK_SIZE        64


#define cpu_to_be32(v) (((v)>>24) | (((v)>>8)&0xff00) | (((v)<<8)&0xff0000) | ((v)<<24))

#define ROTATELEFT(X, n)  (((X)<<(n&31)) | ((X)>>(32-(n&31))))

#define P0(x) ((x) ^  ROTATELEFT((x),9)  ^ ROTATELEFT((x),17))
#define P1(x) ((x) ^  ROTATELEFT((x),15) ^ ROTATELEFT((x),23))

#define FF0(x, y, z) ( (x) ^ (y) ^ (z))
#define FF1(x, y, z) (((x) & (y)) | ( (x) & (z)) | ( (y) & (z)))

#define GG0(x, y, z) ( (x) ^ (y) ^ (z))
#define GG1(x, y, z) (((x) & (y)) | ( (~(x)) & (z)) )

/* Implementation that should never be optimized out by the compiler */
static void mbedtls_zeroize(void *v, size_t n) {
    volatile unsigned char *p = v;
    while (n--) *p++ = 0;
}

void sm3_init(sm3_context *ctx) {
    memset(ctx, 0, sizeof(sm3_context));
}

void sm3_free(sm3_context *ctx) {
    if (ctx == NULL)
        return;
    mbedtls_zeroize(ctx, sizeof(sm3_context));
}

void sm3_clone(sm3_context *dst, const sm3_context *src) {
    *dst = *src;
}


void sm3_starts(sm3_context *ctx) {

    ctx->total[0] = 0;
    ctx->total[1] = 0;

    ctx->state[0] = 0x7380166F;
    ctx->state[1] = 0x4914B2B9;
    ctx->state[2] = 0x172442D7;
    ctx->state[3] = 0xDA8A0600;
    ctx->state[4] = 0xA96F30BC;
    ctx->state[5] = 0x163138AA;
    ctx->state[6] = 0xE38DEE4D;
    ctx->state[7] = 0xB0FB0E4E;
}


void sm3_process(sm3_context *ctx, const unsigned char block[64]) {


    int j;
    uint32_t W[68], W1[64];
    const uint32_t *pblock = (const uint32_t *) block;

    uint32_t A = ctx->state[0];
    uint32_t B = ctx->state[1];
    uint32_t C = ctx->state[2];
    uint32_t D = ctx->state[3];
    uint32_t E = ctx->state[4];
    uint32_t F = ctx->state[5];
    uint32_t G = ctx->state[6];
    uint32_t H = ctx->state[7];
    uint32_t SS1, SS2, TT1, TT2, T[64];

    for (j = 0; j < 16; j++) {
        W[j] = cpu_to_be32(pblock[j]);
    }
    for (j = 16; j < 68; j++) {
        W[j] = P1(W[j - 16] ^ W[j - 9] ^ ROTATELEFT(W[j - 3], 15)) ^ ROTATELEFT(W[j - 13], 7) ^
               W[j - 6];;
    }


    for (j = 0; j < 64; j++) {
        W1[j] = W[j] ^ W[j + 4];
    }

    for (j = 0; j < 16; j++) {

        T[j] = 0x79CC4519;
        SS1 = ROTATELEFT((ROTATELEFT(A, 12) + E + ROTATELEFT(T[j], j)), 7);
        SS2 = SS1 ^ ROTATELEFT(A, 12);
        TT1 = FF0(A, B, C) + D + SS2 + W1[j];
        TT2 = GG0(E, F, G) + H + SS1 + W[j];
        D = C;
        C = ROTATELEFT(B, 9);
        B = A;
        A = TT1;
        H = G;
        G = ROTATELEFT(F, 19);
        F = E;
        E = P0(TT2);
    }

    for (j = 16; j < 64; j++) {

        T[j] = 0x7A879D8A;
        SS1 = ROTATELEFT((ROTATELEFT(A, 12) + E + ROTATELEFT(T[j], j)), 7);
        SS2 = SS1 ^ ROTATELEFT(A, 12);
        TT1 = FF1(A, B, C) + D + SS2 + W1[j];
        TT2 = GG1(E, F, G) + H + SS1 + W[j];
        D = C;
        C = ROTATELEFT(B, 9);
        B = A;
        A = TT1;
        H = G;
        G = ROTATELEFT(F, 19);
        F = E;
        E = P0(TT2);
    }

    ctx->state[0] ^= A;
    ctx->state[1] ^= B;
    ctx->state[2] ^= C;
    ctx->state[3] ^= D;
    ctx->state[4] ^= E;
    ctx->state[5] ^= F;
    ctx->state[6] ^= G;
    ctx->state[7] ^= H;
}


void sm3_update(sm3_context *ctx, const unsigned char *input, size_t ilen) {
    if (ctx->total[0]) {
        unsigned int left = SM3_BLOCK_SIZE - ctx->total[0];
        if (ilen < left) {
            memcpy(ctx->buffer + ctx->total[0], input, ilen);
            ctx->total[0] += ilen;
            return;
        } else {
            memcpy(ctx->buffer + ctx->total[0], input, left);
            sm3_process(ctx, ctx->buffer);
            ctx->total[1]++;
            input += left;
            ilen -= left;
        }
    }
    while (ilen >= SM3_BLOCK_SIZE) {
        sm3_process(ctx, input);
        ctx->total[1]++;
        input += SM3_BLOCK_SIZE;
        ilen -= SM3_BLOCK_SIZE;
    }
    ctx->total[0] = ilen;
    if (ilen) {
        memcpy(ctx->buffer, input, ilen);
    }
}


void sm3_finish(sm3_context *ctx, unsigned char output[32]) {
    size_t i;
    uint32_t *pdigest = (uint32_t *) output;
    uint32_t *count = (uint32_t *) (ctx->buffer + SM3_BLOCK_SIZE - 8);

    ctx->buffer[ctx->total[0]] = 0x80;

    if (ctx->total[0] + 9 <= SM3_BLOCK_SIZE) {
        memset(ctx->buffer + ctx->total[0] + 1, 0, SM3_BLOCK_SIZE - ctx->total[0] - 9);
    } else {
        memset(ctx->buffer + ctx->total[0] + 1, 0, SM3_BLOCK_SIZE - ctx->total[0] - 1);
        sm3_process(ctx, ctx->buffer);
        memset(ctx->buffer, 0, SM3_BLOCK_SIZE - 8);
    }

    count[0] = cpu_to_be32((ctx->total[1]) >> 23);
    count[1] = cpu_to_be32((ctx->total[1] << 9) + (ctx->total[0] << 3));

    sm3_process(ctx, ctx->buffer);
    for (i = 0; i < sizeof(ctx->state) / sizeof(ctx->state[0]); i++) {
        pdigest[i] = cpu_to_be32(ctx->state[i]);
    }
}


void sm3(const unsigned char *msg, size_t msglen,
         unsigned char dgst[SM3_DIGEST_LENGTH]) {
    sm3_context ctx;

    sm3_init(&ctx);
    sm3_starts(&ctx);
    sm3_update(&ctx, msg, msglen);
    sm3_finish(&ctx, dgst);
    sm3_free(&ctx);
}


#ifdef  MBEDTLS_SELF_TEST
static const uint8_t test_buf[2][64] = {
        {"abc"},
        {"abcdabcdabcdabcdabcdabcdabcdabcdabcdabcdabcdabcdabcdabcdabcdabcd"},
};

static const int test_buflen[2] = {
        3, 64
};

static const uint8_t test_sum[2][32] = {
        /*
         * sm3 test vectors
         */
        {0x66, 0xc7, 0xf0, 0xf4, 0x62, 0xee, 0xed, 0xd9,
                0xd1, 0xf2, 0xd4, 0x6b, 0xdc, 0x10, 0xe4, 0xe2,
                0x41, 0x67, 0xc4, 0x87, 0x5c, 0xf2, 0xf7, 0xa2,
                0x29, 0x7d, 0xa0, 0x2b, 0x8f, 0x4b, 0xa8, 0xe0},

        {0xDE, 0xBE, 0x9F, 0xF9, 0x22, 0x75, 0xB8, 0xA1,
                0x38, 0x60, 0x48, 0x89, 0xC1, 0x8E, 0x5A, 0x4D,
                0x6F, 0xDB, 0x70, 0xE5, 0x38, 0x7E, 0x57, 0x65,
                0x29, 0x3D, 0xCB, 0xA3, 0x9c, 0x0c, 0x57, 0x32}

};


int sm3_self_test(int verbose) {
    int i, ret = 0;
    unsigned char sm3sum[32];
    sm3_context ctx;


    sm3_init(&ctx);

    for (i = 0; i < 2; i++) {


        if (verbose != 0)
            mbedtls_printf("  sm3 test #%s: \n ", test_buf[i]);

        sm3_starts(&ctx);


        sm3_update(&ctx, test_buf[i], (size_t) test_buflen[i]);


        sm3_finish(&ctx, sm3sum);

        if (memcmp(sm3sum, test_sum[i], 32) != 0) {
            if (verbose != 0)
                mbedtls_printf("failed\n");

            ret = 1;
            goto exit;
        }

        if (verbose != 0)
            mbedtls_printf("passed\n");
    }

    if (verbose != 0)
        mbedtls_printf("\n");

    exit:
    sm3_free(&ctx);
    return (ret);

}

#endif

