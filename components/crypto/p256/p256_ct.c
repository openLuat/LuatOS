/*
 * p256_ct.c — secp256r1 (P-256) 常数时间实现, 8 x 32-bit little-endian limbs.
 *
 * 算法结构参考 BearSSL ec_p256_m31.c (MIT license, (c) Thomas Pornin):
 *  - 点加法/倍点公式与其 p256_add/p256_add_mixed/p256_double 一致;
 *  - 求逆用 Fermat 小指数 (z^(p-2)), 加法链直接沿用 BearSSL 的调度;
 *  - 窗口点乘的 qz 标志 + CCOPY 选择结构沿用 BearSSL.
 * 域运算改为 32-bit limb (BearSSL 为 30-bit), 模约减采用与 mbedtls
 * ecp_curves.c ecp_mod_p256 相同的 Solinas 配方, 便于后续替换为
 * Cortex-M3 Thumb-2 汇编内核 (p256_field_armm3.S, 由 LUAT_CONF_MBEDTLS_ECP_P256_ASM 控制).
 *
 * 常数时间约定: 所有秘密(标量)相关数据无分支、无秘密索引内存访问;
 * 窗口查表用 CT select. 进位传播轮数固定(不随数据提前退出).
 */

#include "luat_p256.h"
#include <string.h>

/*
 * 设备构建里 MBEDTLS_CONFIG_FILE 是全局 -D, 由此拿到产品 mbedtls 配置头,
 * 其中定义 LUAT_CONF_MBEDTLS_ECP_P256_FAST / _ASM 开关.
 * PC 模拟器 / 独立测试环境没有该宏时, 域运算自动使用纯 C 实现.
 * 必须在下面的条件编译之前包含.
 */
#if defined(MBEDTLS_CONFIG_FILE)
#include MBEDTLS_CONFIG_FILE
#endif

/* ------------------------------------------------------------------ */
/* 基础类型与常数                                                      */
/* ------------------------------------------------------------------ */

typedef uint32_t fe[8];          /* 域元素, [0, p) 完全约减 */

typedef struct {
    fe x, y, z;                  /* Jacobian: affine = (x/z^2, y/z^3); z=0 为无穷远点 */
} p256_pt;

/* p = 2^256 - 2^224 + 2^192 + 2^96 - 1 (LE limbs) */
static const fe P256_P = {
    0xFFFFFFFFu, 0xFFFFFFFFu, 0xFFFFFFFFu, 0x00000000u,
    0x00000000u, 0x00000000u, 0x00000001u, 0xFFFFFFFFu
};

/* n (曲线阶, LE limbs) */
static const fe P256_N = {
    0xFC632551u, 0xF3B9CAC2u, 0xA7179E84u, 0xBCE6FAADu,
    0xFFFFFFFFu, 0xFFFFFFFFu, 0x00000000u, 0xFFFFFFFFu
};

/* b (LE limbs) */
static const fe P256_B = {
    0x27D2604Bu, 0x3BCE3C3Eu, 0xCC53B0F6u, 0x651D06B0u,
    0x769886BCu, 0xB3EBBD55u, 0xAA3A93E7u, 0x5AC635D8u
};

/* ------------------------------------------------------------------ */
/* CT 工具                                                             */
/* ------------------------------------------------------------------ */

/* x == y ? 1 : 0 (无分支) */
static uint32_t ct_eq(uint32_t x, uint32_t y)
{
    uint32_t d = x ^ y;
    return (uint32_t)(((uint64_t)d - 1u) >> 32) & 1u;
}

/* a == 0 ? 1 : 0 */
static uint32_t fe_iszero(const fe a)
{
    uint32_t v = 0;
    int i;
    for (i = 0; i < 8; i++) v |= a[i];
    return ct_eq(v, 0);
}

/* ctl ? a = b : 不变 */
static void fe_cmov(fe a, const fe b, uint32_t ctl)
{
    uint32_t m = 0u - ctl;
    int i;
    for (i = 0; i < 8; i++) a[i] ^= m & (a[i] ^ b[i]);
}

static void pt_cmov(p256_pt *a, const p256_pt *b, uint32_t ctl)
{
    fe_cmov(a->x, b->x, ctl);
    fe_cmov(a->y, b->y, ctl);
    fe_cmov(a->z, b->z, ctl);
}

/* ------------------------------------------------------------------ */
/* 域运算 (纯 C 参考实现; P2 阶段由 p256_field_armm3.S 同名符号替换)     */
/* ------------------------------------------------------------------ */

#if !defined(LUAT_CONF_MBEDTLS_ECP_P256_ASM) || !defined(__ARM_ARCH_7M__)
#define LUAT_P256_FIELD_C 1
#endif

#if defined(LUAT_P256_FIELD_C)

/* d = a + b mod p, 输入 < p, 输出 < p */
static void fe_add(fe d, const fe a, const fe b)
{
    uint64_t s;
    uint32_t cc;
    fe t;
    int64_t q;
    uint32_t borrow, sel, m;
    int i;

    cc = 0;
    for (i = 0; i < 8; i++) {
        s = (uint64_t)a[i] + b[i] + cc;
        d[i] = (uint32_t)s;
        cc = (uint32_t)(s >> 32);
    }
    /* value = d + cc*2^256, 且 < 2p; 试减 p */
    q = 0;
    for (i = 0; i < 8; i++) {
        q += (int64_t)d[i] - P256_P[i];
        t[i] = (uint32_t)q;
        q >>= 32;   /* 算术右移, 保留借位 */
    }
    borrow = (uint32_t)q & 1u;
    /* cc==1 时真值 >= 2^256 > p, t 缠绕后恰为正确结果; cc==0 且未借位 => d >= p */
    sel = cc | (borrow ^ 1u);
    m = 0u - sel;
    for (i = 0; i < 8; i++) d[i] ^= m & (d[i] ^ t[i]);
}

/* d = a - b mod p, 输入 < p, 输出 < p */
static void fe_sub(fe d, const fe a, const fe b)
{
    int64_t q;
    uint64_t s;
    uint32_t borrow, cc, m;
    fe t;
    int i;

    q = 0;
    for (i = 0; i < 8; i++) {
        q += (int64_t)a[i] - b[i];
        d[i] = (uint32_t)q;
        q >>= 32;
    }
    borrow = (uint32_t)q & 1u;
    /* 借位则加 p (a-b+p ∈ (0, p), 进位自动抵消借位) */
    cc = 0;
    for (i = 0; i < 8; i++) {
        s = (uint64_t)d[i] + P256_P[i] + cc;
        t[i] = (uint32_t)s;
        cc = (uint32_t)(s >> 32);
    }
    m = 0u - borrow;
    for (i = 0; i < 8; i++) d[i] ^= m & (d[i] ^ t[i]);
}

#endif /* LUAT_P256_FIELD_C */

/* Solinas 约减与最终条件减 p 两种模式共用 (ASM 模式下仍走 C) */

/*
 * 512-bit 乘积的 Solinas 快速约减 (配方同 mbedtls ecp_mod_p256):
 *   2^256 ≡ 2^224 - 2^192 - 2^96 + 1 (mod p)
 * 输出 [0, 2^256), 由调用方再做一次条件减 p.
 */
static void fe_reduce512(fe d, const uint32_t c[16])
{
    int64_t t, carry;
    int round;

    /* 第 1 遍: A0..A7 逐 limb 有符号累加, 进位前传 */
    carry = 0;
#define RED_LIMB(idx, expr)                       \
    t = (int64_t)(expr) + carry;                  \
    d[idx] = (uint32_t)t;                         \
    carry = t >> 32
    RED_LIMB(0, (int64_t)c[0] + c[8] + c[9] - c[11] - c[12] - c[13] - c[14]);
    RED_LIMB(1, (int64_t)c[1] + c[9] + c[10] - c[12] - c[13] - c[14] - c[15]);
    RED_LIMB(2, (int64_t)c[2] + c[10] + c[11] - c[13] - c[14] - c[15]);
    RED_LIMB(3, (int64_t)c[3] + 2 * (int64_t)c[11] + 2 * (int64_t)c[12] + c[13] - c[15] - c[8] - c[9]);
    RED_LIMB(4, (int64_t)c[4] + 2 * (int64_t)c[12] + 2 * (int64_t)c[13] + c[14] - c[9] - c[10]);
    RED_LIMB(5, (int64_t)c[5] + 2 * (int64_t)c[13] + 2 * (int64_t)c[14] + c[15] - c[10] - c[11]);
    RED_LIMB(6, (int64_t)c[6] + 3 * (int64_t)c[14] + 2 * (int64_t)c[15] + c[13] - c[8] - c[9]);
    RED_LIMB(7, (int64_t)c[7] + 3 * (int64_t)c[15] + c[8] - c[10] - c[11] - c[12] - c[13]);
#undef RED_LIMB

    /*
     * carry ∈ [-4, 6] 代表 carry*2^256. 折叠: c*2^256 ≡ c*(2^224 - 2^192 - 2^96 + 1),
     * 即 limb0 += c, limb3 -= c, limb6 -= c, limb7 += c, 同时串行传播进位.
     * 分析: 每轮折叠后 |carry| <= 1, 且负 carry 等价于整体加 p, 至多 2 轮收敛到 0;
     * 固定跑 3 轮留余量(不随数据提前退出).
     */
    for (round = 0; round < 3; round++) {
        int64_t cf = carry;
        carry = 0;
#define FOLD_LIMB(idx, adj)                       \
    t = (int64_t)d[idx] + (adj) + carry;          \
    d[idx] = (uint32_t)t;                         \
    carry = t >> 32
        FOLD_LIMB(0, cf);
        FOLD_LIMB(1, 0);
        FOLD_LIMB(2, 0);
        FOLD_LIMB(3, -cf);
        FOLD_LIMB(4, 0);
        FOLD_LIMB(5, 0);
        FOLD_LIMB(6, -cf);
        FOLD_LIMB(7, cf);
#undef FOLD_LIMB
    }
    /* 结果 ∈ [0, 2^256) ⊂ [0, 2p) */
}

/* d >= p ? d -= p : 不变; 返回 1 表示发生了减法. 输入必须 < 2^256. */
static uint32_t fe_reduce_once(fe d)
{
    int64_t q;
    fe t;
    uint32_t sel, m;
    int i;

    q = 0;
    for (i = 0; i < 8; i++) {
        q += (int64_t)d[i] - P256_P[i];
        t[i] = (uint32_t)q;
        q >>= 32;
    }
    sel = ((uint32_t)q & 1u) ^ 1u;   /* 未借位 => d >= p */
    m = 0u - sel;
    for (i = 0; i < 8; i++) d[i] ^= m & (d[i] ^ t[i]);
    return sel;
}

/* d = a * b mod p (schoolbook + Solinas) */
#if defined(LUAT_P256_FIELD_C)
static void fe_mul(fe d, const fe a, const fe b)
{
    uint32_t c[16];
    uint64_t t, carry;
    int i, j;

    memset(c, 0, sizeof c);
    for (i = 0; i < 8; i++) {
        carry = 0;
        for (j = 0; j < 8; j++) {
            t = (uint64_t)a[i] * b[j] + c[i + j] + carry;
            c[i + j] = (uint32_t)t;
            carry = t >> 32;
        }
        c[i + 8] = (uint32_t)carry;   /* 该位置此前未被本算法写过 */
    }
    fe_reduce512(d, c);
    fe_reduce_once(d);
}

/* d = a^2 mod p (C 版直接复用乘法; 汇编版有独立平方) */
static void fe_sqr(fe d, const fe a)
{
    fe_mul(d, a, a);
}

#else /* !LUAT_P256_FIELD_C: Cortex-M3 Thumb-2 汇编内核 (p256_field_armm3.S) */

extern void p256_fe_add_m3(uint32_t d[8], const uint32_t a[8], const uint32_t b[8]);
extern void p256_fe_sub_m3(uint32_t d[8], const uint32_t a[8], const uint32_t b[8]);
extern void p256_mul256_m3(uint32_t c[16], const uint32_t a[8], const uint32_t b[8]);

#define fe_add p256_fe_add_m3
#define fe_sub p256_fe_sub_m3

/* d = a * b mod p (汇编 512-bit 乘积 + C 侧 Solinas 约减) */
static void fe_mul(fe d, const fe a, const fe b)
{
    uint32_t c[16];
    memset(c, 0, sizeof c);
    p256_mul256_m3(c, a, b);
    fe_reduce512(d, c);
    fe_reduce_once(d);
}

static void fe_sqr(fe d, const fe a)
{
    fe_mul(d, a, a);
}

#endif /* LUAT_P256_FIELD_C */

/* d = a^(p-2) mod p — Fermat 求逆, 加法链沿用 BearSSL p256_to_affine */
static void fe_inv(fe d, const fe z)
{
    fe t1, t2;
    int i;

    /* t1 = z^(2^31 - 1) */
    memcpy(t1, z, sizeof(fe));
    for (i = 0; i < 30; i++) {
        fe_sqr(t1, t1);
        fe_mul(t1, t1, z);
    }

    /* t2 = z^(p-2), 指数位型(高到低): 32x1, 31x0, 1, 96x0, 94x1, 0, 1 */
    memcpy(t2, z, sizeof(fe));
    for (i = 1; i < 256; i++) {
        fe_sqr(t2, t2);
        switch (i) {
        case 31:
        case 190:
        case 221:
        case 252:
            fe_mul(t2, t2, t1);
            break;
        case 63:
        case 253:
        case 255:
            fe_mul(t2, t2, z);
            break;
        default:
            break;
        }
    }
    memcpy(d, t2, sizeof(fe));
}

/* ------------------------------------------------------------------ */
/* 字节转换                                                            */
/* ------------------------------------------------------------------ */

/* 大端 32 字节 -> fe; 值 >= p 返回 -1, 否则 0 */
static int fe_from_be(fe d, const uint8_t *in)
{
    int i, j;
    for (i = 0; i < 8; i++) {
        uint32_t w = 0;
        const uint8_t *p = in + (7 - i) * 4;
        for (j = 0; j < 4; j++) w = (w << 8) | p[j];
        d[i] = w;
    }
    return fe_reduce_once(d) ? -1 : 0;
}

static void fe_to_be(uint8_t *out, const fe a)
{
    int i, j;
    for (i = 0; i < 8; i++) {
        uint8_t *p = out + (7 - i) * 4;
        uint32_t w = a[i];
        for (j = 3; j >= 0; j--) { p[j] = (uint8_t)w; w >>= 8; }
    }
}

/* 标量合法性: 1 <= k < n; 合法 0 / 非法 -1 */
static int scalar_check(const uint8_t k[32])
{
    fe v;
    int64_t q;
    int i, j;
    uint32_t iszero;

    for (i = 0; i < 8; i++) {
        uint32_t w = 0;
        const uint8_t *p = k + (7 - i) * 4;
        for (j = 0; j < 4; j++) w = (w << 8) | p[j];
        v[i] = w;
    }
    iszero = fe_iszero(v);
    q = 0;
    for (i = 0; i < 8; i++) {
        q += (int64_t)v[i] - P256_N[i];
        q >>= 32;
    }
    /* 未借位 => v >= n */
    if ((((uint32_t)q & 1u) ^ 1u) || iszero)
        return -1;
    return 0;
}

/* ------------------------------------------------------------------ */
/* 点运算 (公式与 BearSSL p256_double/p256_add/p256_add_mixed 一致)      */
/* ------------------------------------------------------------------ */

static void pt_double(p256_pt *Q)
{
    fe t1, t2, t3, t4;

    fe_sqr(t1, Q->z);              /* z^2 */
    fe_add(t2, Q->x, t1);          /* x + z^2 */
    fe_sub(t1, Q->x, t1);          /* x - z^2 */
    fe_mul(t3, t1, t2);
    fe_add(t1, t3, t3);
    fe_add(t1, t3, t1);            /* m = 3(x+z^2)(x-z^2) */
    fe_sqr(t3, Q->y);
    fe_add(t3, t3, t3);            /* 2y^2 */
    fe_mul(t2, Q->x, t3);
    fe_add(t2, t2, t2);            /* s = 4xy^2 */
    fe_sqr(Q->x, t1);
    fe_sub(Q->x, Q->x, t2);
    fe_sub(Q->x, Q->x, t2);        /* x' = m^2 - 2s */
    fe_mul(t4, Q->y, Q->z);
    fe_add(Q->z, t4, t4);          /* z' = 2yz */
    fe_sub(t2, t2, Q->x);          /* s - x' */
    fe_mul(Q->y, t1, t2);          /* m(s - x') */
    fe_sqr(t4, t3);
    fe_add(t4, t4, t4);            /* 8y^4 */
    fe_sub(Q->y, Q->y, t4);
}

/*
 * P1 += P2 (一般 Jacobian 加法).
 * 特殊输入 (P1==0, P2==0, P1==±P2) 会把 P1 置为无穷远;
 * 返回 1 表示确切为 P1+P2==0, 返回 0 且结果为无穷远表示 P1==P2(应改用倍点).
 */
static uint32_t pt_add(p256_pt *P1, const p256_pt *P2)
{
    fe t1, t2, t3, t4, t5, t6, t7;
    uint32_t ret;

    fe_sqr(t3, P2->z);
    fe_mul(t1, P1->x, t3);         /* u1 = x1*z2^2 */
    fe_mul(t4, P2->z, t3);
    fe_mul(t3, P1->y, t4);         /* s1 = y1*z2^3 */
    fe_sqr(t4, P1->z);
    fe_mul(t2, P2->x, t4);         /* u2 = x2*z1^2 */
    fe_mul(t5, P1->z, t4);
    fe_mul(t4, P2->y, t5);         /* s2 = y2*z1^3 */
    fe_sub(t2, t2, t1);            /* h = u2 - u1 */
    fe_sub(t4, t4, t3);            /* r = s2 - s1 (已完全约减) */
    /* 语义同 BearSSL: 1 = r 非零; 若结果同时为无穷远则确切为 P1+P2==0 */
    ret = fe_iszero(t4) ^ 1u;

    fe_sqr(t7, t2);                /* h^2 */
    fe_mul(t6, t1, t7);            /* u1*h^2 */
    fe_mul(t5, t7, t2);            /* h^3 */
    fe_sqr(P1->x, t4);
    fe_sub(P1->x, P1->x, t5);
    fe_sub(P1->x, P1->x, t6);
    fe_sub(P1->x, P1->x, t6);      /* x3 = r^2 - h^3 - 2u1h^2 */
    fe_sub(t6, t6, P1->x);
    fe_mul(P1->y, t4, t6);         /* r(u1h^2 - x3) */
    fe_mul(t1, t5, t3);
    fe_sub(P1->y, P1->y, t1);      /* - s1*h^3 */
    fe_mul(t1, P1->z, P2->z);
    fe_mul(P1->z, t1, t2);         /* z3 = h*z1*z2 */

    return ret;
}

/* P1 += P2, P2 为仿射点 (z=1); 返回值语义同 pt_add */
static uint32_t pt_add_mixed(p256_pt *P1, const p256_pt *P2)
{
    fe t1, t2, t3, t4, t5, t6, t7;
    uint32_t ret;

    memcpy(t1, P1->x, sizeof(fe)); /* u1 = x1 */
    memcpy(t3, P1->y, sizeof(fe)); /* s1 = y1 */
    fe_sqr(t4, P1->z);
    fe_mul(t2, P2->x, t4);         /* u2 = x2*z1^2 */
    fe_mul(t5, P1->z, t4);
    fe_mul(t4, P2->y, t5);         /* s2 = y2*z1^3 */
    fe_sub(t2, t2, t1);            /* h */
    fe_sub(t4, t4, t3);            /* r */
    ret = fe_iszero(t4) ^ 1u;      /* 语义同 pt_add */

    fe_sqr(t7, t2);
    fe_mul(t6, t1, t7);
    fe_mul(t5, t7, t2);
    fe_sqr(P1->x, t4);
    fe_sub(P1->x, P1->x, t5);
    fe_sub(P1->x, P1->x, t6);
    fe_sub(P1->x, P1->x, t6);
    fe_sub(t6, t6, P1->x);
    fe_mul(P1->y, t4, t6);
    fe_mul(t1, t5, t3);
    fe_sub(P1->y, P1->y, t1);
    fe_mul(P1->z, P1->z, t2);      /* z3 = h*z1 */

    return ret;
}

/* 转仿射; 无穷远点输出 x=y=z=0 */
static void pt_to_affine(p256_pt *P)
{
    fe iz, t1;

    fe_inv(iz, P->z);              /* 1/z (z=0 时得 0) */
    fe_sqr(t1, iz);                /* 1/z^2 */
    fe_mul(P->x, P->x, t1);
    fe_mul(t1, t1, iz);            /* 1/z^3 */
    fe_mul(P->y, P->y, t1);
    fe_mul(P->z, P->z, iz);
    fe_reduce_once(P->x);
    fe_reduce_once(P->y);
    fe_reduce_once(P->z);
}

/* ------------------------------------------------------------------ */
/* 点解码/校验                                                         */
/* ------------------------------------------------------------------ */

/* 64 字节 X||Y -> Jacobian; 坐标越界/不在曲线上返回 -1 */
static int pt_decode(p256_pt *P, const uint8_t xy[64])
{
    fe t1, t2;

    if (fe_from_be(P->x, xy) != 0) return -1;
    if (fe_from_be(P->y, xy + 32) != 0) return -1;

    /* 校验 y^2 == x^3 - 3x + b */
    fe_sqr(t1, P->x);
    fe_mul(t1, t1, P->x);          /* x^3 */
    fe_sub(t1, t1, P->x);
    fe_sub(t1, t1, P->x);
    fe_sub(t1, t1, P->x);          /* x^3 - 3x */
    fe_add(t1, t1, P256_B);        /* x^3 - 3x + b */
    fe_sqr(t2, P->y);              /* y^2 */
    fe_sub(t1, t1, t2);
    if (!fe_iszero(t1)) return -1;

    memset(P->z, 0, sizeof(fe));
    P->z[0] = 1;
    return 0;
}

/* ------------------------------------------------------------------ */
/* 标量乘                                                              */
/* ------------------------------------------------------------------ */

/*
 * 变基点: R = k * P, 4-bit 窗口 + Jacobian 预计算表 (T[w] = w*P, w=1..15).
 *
 * 无特殊点分析 (P-256 cofactor = 1, P 已在曲线校验, 1 <= k < n):
 * 设处理到第 i 个窗口时累加器值为 prefix*P (prefix 为 k 的高 4i 位, prefix <= k < n);
 * 本步计算 16*prefix + w <= k < n, 故 16*prefix ≢ ±w (mod n) 不可能发生
 * (16*prefix = w 需 prefix=0 或 >= 16/16=w/16 矛盾; 16*prefix+w = n 与 < n 矛盾),
 * 即 pt_add 的 P1==±P2 特例不会触发; 仅剩 Q==0 由 qz 标志处理.
 * w==0 时查表得到全零点, 加法结果被 CCOPY 丢弃.
 */
static void p256_mul_core(p256_pt *R, const p256_pt *P, const uint8_t k[32])
{
    p256_pt tbl[15];
    p256_pt Q, T, U;
    uint32_t qz;
    int i, j;

    /* 建表: T[w] = w*P, w = 1..15 */
    tbl[0] = *P;
    tbl[1] = *P;
    pt_double(&tbl[1]);
    for (i = 2; i < 15; i++) {
        tbl[i] = tbl[i - 1];
        pt_add(&tbl[i], P);
    }

    memset(&Q, 0, sizeof Q);
    qz = 1;
    for (i = 0; i < 64; i++) {
        uint32_t w = (k[i >> 1] >> ((i & 1) ? 0 : 4)) & 0x0F;
        uint32_t bnz = ct_eq(w, 0) ^ 1u;

        for (j = 0; j < 4; j++) pt_double(&Q);

        /* CT 查表: T = tbl[w-1] (w==0 时得全零点) */
        memset(&T, 0, sizeof T);
        for (j = 0; j < 15; j++)
            pt_cmov(&T, &tbl[j], ct_eq(w, (uint32_t)(j + 1)));

        U = Q;
        pt_add(&U, &T);
        pt_cmov(&Q, &T, bnz & qz);
        pt_cmov(&Q, &U, bnz & (qz ^ 1u));
        qz &= bnz ^ 1u;
    }
    *R = Q;
}

/* CT 查 flash 表: T = w*G (w==0 时 x=y=0, z=1 的伪点, 结果被丢弃) */
static void select_gwin(p256_pt *T, uint32_t w)
{
    uint32_t xy[16];
    int j, u;

    memset(xy, 0, sizeof xy);
    for (j = 0; j < 15; j++) {
        uint32_t m = 0u - ct_eq(w, (uint32_t)(j + 1));
        for (u = 0; u < 16; u++)
            xy[u] |= m & luat_p256_gwin[j][u];
    }
    memcpy(T->x, &xy[0], sizeof(fe));
    memcpy(T->y, &xy[8], sizeof(fe));
    memset(T->z, 0, sizeof(fe));
    T->z[0] = 1;
}

/* 固定基点: R = k * G, 4-bit 窗口 + flash 仿射表 + 混合加法 */
static void p256_mulgen_core(p256_pt *R, const uint8_t k[32])
{
    p256_pt Q, T, U;
    uint32_t qz;
    int i, j;

    memset(&Q, 0, sizeof Q);
    qz = 1;
    for (i = 0; i < 64; i++) {
        uint32_t w = (k[i >> 1] >> ((i & 1) ? 0 : 4)) & 0x0F;
        uint32_t bnz = ct_eq(w, 0) ^ 1u;

        for (j = 0; j < 4; j++) pt_double(&Q);

        select_gwin(&T, w);
        U = Q;
        pt_add_mixed(&U, &T);
        pt_cmov(&Q, &T, bnz & qz);
        pt_cmov(&Q, &U, bnz & (qz ^ 1u));
        qz &= bnz ^ 1u;
    }
    *R = Q;
}

/* 结果编码: 0 正常; 1 结果为无穷远点 */
static int pt_encode(uint8_t out_xy[64], p256_pt *P)
{
    pt_to_affine(P);
    if (fe_iszero(P->z))
        return 1;
    fe_to_be(out_xy, P->x);
    fe_to_be(out_xy + 32, P->y);
    return 0;
}

/* ------------------------------------------------------------------ */
/* 对外 API                                                            */
/* ------------------------------------------------------------------ */

int luat_p256_mul_g(uint8_t out_xy[64], const uint8_t k[32])
{
    p256_pt R;

    if (scalar_check(k) != 0)
        return -1;
    p256_mulgen_core(&R, k);
    return pt_encode(out_xy, &R) ? -1 : 0;
}

int luat_p256_mul(uint8_t out_xy[64], const uint8_t k[32], const uint8_t pt_xy[64])
{
    p256_pt P, R;

    if (scalar_check(k) != 0)
        return -1;
    if (pt_decode(&P, pt_xy) != 0)
        return -1;
    p256_mul_core(&R, &P, k);
    return pt_encode(out_xy, &R) ? -1 : 0;
}

int luat_p256_on_curve(const uint8_t pt_xy[64])
{
    p256_pt P;
    return pt_decode(&P, pt_xy) == 0 ? 1 : 0;
}

/*
 * R = u1*G + u2*Q (ECDSA 验签). 允许 u1/u2 为 0 (结果为对方或无穷远).
 * 返回 0 正常; -1 输入非法或结果为无穷远(验签应判失败).
 */
int luat_p256_muladd(uint8_t out_xy[64], const uint8_t u1[32], const uint8_t u2[32], const uint8_t q_xy[64])
{
    static const uint8_t zero32[32] = {0};
    p256_pt P1, P2, Q2;
    uint32_t t, z;
    int u1z, u2z;

    /* 标量: 允许 0, 但非零时必须 < n */
    u1z = (memcmp(u1, zero32, 32) == 0);
    u2z = (memcmp(u2, zero32, 32) == 0);
    if (!u1z && scalar_check(u1) != 0)
        return -1;
    if (!u2z && scalar_check(u2) != 0)
        return -1;
    if (pt_decode(&P2, q_xy) != 0)
        return -1;
    if (u1z && u2z)
        return -1;

    /* 零标量情形: pt_add 不接受无穷远操作数, 单独直通 */
    if (u1z) {                              /* R = u2*Q */
        p256_mul_core(&P1, &P2, u2);
        return pt_encode(out_xy, &P1) ? -1 : 0;
    }
    if (u2z) {                              /* R = u1*G */
        p256_mulgen_core(&P1, u1);
        return pt_encode(out_xy, &P1) ? -1 : 0;
    }

    p256_mulgen_core(&P1, u1);              /* u1*G, 非零 */
    Q2 = P2;
    p256_mul_core(&P2, &Q2, u2);            /* u2*Q, 非零 */

    /*
     * 末次加法的特殊情形 (同 BearSSL api_muladd):
     *   z==0:        P1+P2 正常
     *   z==1, t==0:  P1==P2, 应取 2*P2
     *   z==1, t==1:  P1==-P2, 结果为无穷远 → 验签失败
     */
    t = pt_add(&P1, &P2);
    z = fe_iszero(P1.z);
    pt_double(&P2);
    pt_cmov(&P1, &P2, z & (t ^ 1u));
    if (z & t)
        return -1;
    return pt_encode(out_xy, &P1) ? -1 : 0;
}
