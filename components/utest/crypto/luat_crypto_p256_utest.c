/*
 * P-256 快速路径 (components/crypto/p256/) C 层 utest — 仅 PC.
 *
 * case "p256_fast":
 *   1) KAT 固定向量 (k*G, 含边界标量 k=1/2/n-1);
 *   2) 与 PC 上 mbedtls 原生 ECP 交叉比对 (mul_g / mul / muladd / ECDH),
 *      确定性 xorshift PRNG 驱动, 可复现;
 *   3) 非法输入拒绝 (k=0 / k=n / 点不在曲线上 / 坐标>=p).
 *
 * PC 默认 mbedtls 3.x; 交叉比对部分要求 MBEDTLS_ECP_C 且版本 < 4
 * (mbedtls 4 移除/变更了 legacy ECP API), 不满足时只做 KAT 并记日志.
 */
/* mbedtls 3.x 结构体成员私有化, 交叉比对需要直接访问 ecp_point 的 X/Y/Z */
#define MBEDTLS_ALLOW_PRIVATE_ACCESS

#include "luat_base.h"
#include "luat_log.h"
#include <string.h>
#include <stdint.h>

#include "luat_p256.h"
#include "mbedtls/version.h"

#if defined(MBEDTLS_ECP_C) && (MBEDTLS_VERSION_MAJOR < 4)
#define P256_UTEST_XCHECK 1
#include "mbedtls/ecp.h"
#endif

#define LUAT_LOG_TAG "p256ut"

/* n (大端) */
static const uint8_t P256N_BE[32] = {
    0xFF,0xFF,0xFF,0xFF,0x00,0x00,0x00,0x00,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,
    0xBC,0xE6,0xFA,0xAD,0xA7,0x17,0x9E,0x84,0xF3,0xB9,0xCA,0xC2,0xFC,0x63,0x25,0x51
};

static uint64_t s_rng = 0x9E3779B97F4A7C15ull;

static uint64_t xr64(void)
{
    uint64_t x = s_rng;
    x ^= x >> 12; x ^= x << 25; x ^= x >> 27;
    s_rng = x;
    return x * 0x2545F4914F6CDD1Dull;
}

/* 生成 [1, n) 的 32 字节大端标量 (拒绝采样) */
static void gen_scalar(uint8_t k[32])
{
    for (;;) {
        int i;
        uint32_t zero = 0;
        for (i = 0; i < 32; i += 8) {
            uint64_t r = xr64();
            memcpy(k + i, &r, 8);
        }
        for (i = 0; i < 32; i++) zero |= k[i];
        if (!zero) continue;
        if (memcmp(k, P256N_BE, 32) < 0) return;
    }
}

/* ---------------- KAT ---------------- */

static const char *KAT_K[] = {
    /* k = 1 */
    "0000000000000000000000000000000000000000000000000000000000000001",
    /* k = 2 */
    "0000000000000000000000000000000000000000000000000000000000000002",
    /* k = n-1 */
    "FFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632550",
};
static const char *KAT_XY[] = {
    "6B17D1F2E12C4247F8BCE6E563A440F277037D812DEB33A0F4A13945D898C296"
    "4FE342E2FE1A7F9B8EE7EB4A7C0F9E162BCE33576B315ECECBB6406837BF51F5",
    "7CF27B188D034F7E8A52380304B51AC3C08969E277F21B35A60B48FC47669978"
    "07775510DB8ED040293D9AC69F7430DBBA7DADE63CE982299E04B79D227873D1",
    /* (n-1)*G = (Gx, p - Gy) */
    "6B17D1F2E12C4247F8BCE6E563A440F277037D812DEB33A0F4A13945D898C296"
    "B01CBD1C01E58065711814B583F061E9D431CCA994CEA1313449BF97C840AE0A",
};

static int hex_nibble(char c)
{
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    return -1;
}

static int hex2bin(const char *hex, uint8_t *out, int len)
{
    int i;
    if ((int)strlen(hex) != len * 2) return -1;
    for (i = 0; i < len; i++) {
        int hi = hex_nibble(hex[2 * i]), lo = hex_nibble(hex[2 * i + 1]);
        if (hi < 0 || lo < 0) return -1;
        out[i] = (uint8_t)((hi << 4) | lo);
    }
    return 0;
}

static int test_kat(void)
{
    uint8_t k[32], out[64], exp[64];
    int i, fails = 0;

    for (i = 0; i < 3; i++) {
        if (hex2bin(KAT_K[i], k, 32) || hex2bin(KAT_XY[i], exp, 64)) {
            LLOGE("KAT hex decode error %d", i);
            return -1;
        }
        if (luat_p256_mul_g(out, k) != 0 || memcmp(out, exp, 64) != 0) {
            LLOGE("KAT %d mismatch", i);
            fails++;
        }
    }
    return fails ? -1 : 0;
}

static int test_reject(void)
{
    uint8_t k[32], pt[64], out[64];
    int fails = 0;

    /* k = 0 → -1 */
    memset(k, 0, 32);
    if (luat_p256_mul_g(out, k) != -1) { LLOGE("k=0 not rejected"); fails++; }
    /* k = n → -1 */
    memcpy(k, P256N_BE, 32);
    if (luat_p256_mul_g(out, k) != -1) { LLOGE("k=n not rejected"); fails++; }
    /* k = n+1 → -1 */
    k[31]++;
    if (luat_p256_mul_g(out, k) != -1) { LLOGE("k=n+1 not rejected"); fails++; }

    /* 合法点 */
    gen_scalar(k);
    if (luat_p256_mul_g(pt, k) != 0) { LLOGE("gen point failed"); return -1; }
    if (luat_p256_on_curve(pt) != 1) { LLOGE("on_curve(G) != 1"); fails++; }
    /* 点不在曲线上 (翻转 y 最低位) → -1 */
    pt[63] ^= 1;
    if (luat_p256_on_curve(pt) != 0) { LLOGE("bad point accepted"); fails++; }
    if (luat_p256_mul(out, k, pt) != -1) { LLOGE("bad point mul accepted"); fails++; }
    /* 坐标 >= p → -1 */
    memset(pt, 0xFF, 64);
    if (luat_p256_on_curve(pt) != 0) { LLOGE(">=p point accepted"); fails++; }

    return fails ? -1 : 0;
}

/* ---------------- 与 mbedtls 交叉比对 ---------------- */

#if defined(P256_UTEST_XCHECK)

static int mpi_from_bytes(mbedtls_mpi *m, const uint8_t *b)
{
    mbedtls_mpi_init(m);
    return mbedtls_mpi_read_binary(m, b, 32);
}

static int pt_from_bytes(mbedtls_ecp_point *P, const uint8_t *xy)
{
    mbedtls_ecp_point_init(P);
    if (mbedtls_mpi_read_binary(&P->X, xy, 32)) return -1;
    if (mbedtls_mpi_read_binary(&P->Y, xy + 32, 32)) return -1;
    if (mbedtls_mpi_lset(&P->Z, 1)) return -1;
    return 0;
}

/* PC mbedtls3 配置未开 CTR_DRBG, ecp_mul 的盲化随机源由本回调(确定性 PRNG)提供 */
static int ut_f_rng(void *ctx, unsigned char *out, size_t len)
{
    size_t i;
    (void)ctx;
    for (i = 0; i < len; i += 8) {
        uint64_t r = xr64();
        size_t n = (len - i < 8) ? len - i : 8;
        memcpy(out + i, &r, n);
    }
    return 0;
}

static int pt_to_bytes(uint8_t *xy, const mbedtls_ecp_point *P)
{
    if (mbedtls_mpi_write_binary(&P->X, xy, 32)) return -1;
    if (mbedtls_mpi_write_binary(&P->Y, xy + 32, 32)) return -1;
    return 0;
}

static int test_xcheck(void)
{
    mbedtls_ecp_group grp;
    mbedtls_ecp_point R, P;
    mbedtls_mpi m, m2;
    uint8_t d1[32], d2[32], fast[64], ref[64], q[64];
    int i, fails = 0;

    mbedtls_ecp_group_init(&grp);
    mbedtls_ecp_point_init(&R);
    mbedtls_ecp_point_init(&P);
    mbedtls_mpi_init(&m);
    mbedtls_mpi_init(&m2);

    if (mbedtls_ecp_group_load(&grp, MBEDTLS_ECP_DP_SECP256R1) != 0) {
        LLOGE("group_load failed");
        return -1;
    }

    for (i = 0; i < 32; i++) {
        /* mul_g 交叉比对 */
        gen_scalar(d1);
        if (mpi_from_bytes(&m, d1)) { fails++; break; }
        if (mbedtls_ecp_mul(&grp, &R, &m, &grp.G, ut_f_rng, NULL) != 0) {
            LLOGE("mbedtls mul failed %d", i); fails++; break;
        }
        if (pt_to_bytes(ref, &R) || luat_p256_mul_g(fast, d1) != 0 || memcmp(fast, ref, 64)) {
            LLOGE("mul_g mismatch %d", i); fails++;
        }

        /* 变基点交叉比对: P = d2*G, R = d1*P */
        gen_scalar(d2);
        if (mpi_from_bytes(&m2, d2)) { fails++; break; }
        if (mbedtls_ecp_mul(&grp, &P, &m2, &grp.G, ut_f_rng, NULL) != 0) { fails++; break; }
        if (pt_to_bytes(q, &P)) { fails++; break; }
        if (mbedtls_ecp_mul(&grp, &R, &m, &P, ut_f_rng, NULL) != 0) { fails++; break; }
        if (pt_to_bytes(ref, &R) || luat_p256_mul(fast, d1, q) != 0 || memcmp(fast, ref, 64)) {
            LLOGE("mul mismatch %d", i); fails++;
        }

        /* muladd 交叉比对: R = d1*G + d2*P */
        if (mbedtls_ecp_muladd(&grp, &R, &m, &grp.G, &m2, &P) != 0) { fails++; break; }
        if (pt_to_bytes(ref, &R) || luat_p256_muladd(fast, d1, d2, q) != 0 || memcmp(fast, ref, 64)) {
            LLOGE("muladd mismatch %d", i); fails++;
        }

        /* ECDH 对称性: z1 = d1*(d2*G) == z2 = d2*(d1*G) */
        {
            uint8_t q1[64], z1[64], z2[64];
            if (luat_p256_mul_g(q1, d1) != 0) { fails++; break; }
            if (luat_p256_mul(z1, d1, q) != 0 || luat_p256_mul(z2, d2, q1) != 0 || memcmp(z1, z2, 64)) {
                LLOGE("ecdh mismatch %d", i); fails++;
            }
        }
        mbedtls_mpi_free(&m);
        mbedtls_mpi_free(&m2);
    }

    mbedtls_mpi_free(&m);
    mbedtls_mpi_free(&m2);
    mbedtls_ecp_point_free(&R);
    mbedtls_ecp_point_free(&P);
    mbedtls_ecp_group_free(&grp);
    return fails ? -1 : 0;
}

#endif /* P256_UTEST_XCHECK */

int luat_crypto_p256_utest(lua_State *L)
{
    int fails = 0;
    (void)L;

    if (test_kat() != 0) fails++;
    if (test_reject() != 0) fails++;
#if defined(P256_UTEST_XCHECK)
    if (test_xcheck() != 0) fails++;
#else
    LLOGI("mbedtls ECP 不可用, 仅执行 KAT/拒绝用例");
#endif

    if (fails) {
        LLOGE("FAILED (%d suites)", fails);
        return -1;
    }
    LLOGI("all pass");
    return 0;
}
