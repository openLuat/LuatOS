/*
 * luat_p256.h — secp256r1 (P-256) 专用常数时间快速路径
 *
 * 算法结构参考 BearSSL ec_p256_m31.c (MIT license), 域表示改为
 * 8 x 32-bit little-endian limbs (适配 Cortex-M3 Thumb-2 汇编内核).
 *
 * 字节级 API 与 mbedtls 无关, 任何平台可编译; mbedtls2 挂钩代码在
 * luat_p256_glue.c, 仅在目标配置头定义 LUAT_CONF_MBEDTLS_ECP_P256_FAST 时启用.
 *
 * 标量约定: 所有 k/u1/u2 必须为 32 字节大端, 且 1 <= k < n (曲线阶).
 * 点的约定: 64 字节 X||Y, 大端; 函数内部做在曲线校验.
 * 返回值: 0 成功; -1 输入非法(点不在曲线上/坐标 >= p/标量越界/结果为无穷远点).
 */
#ifndef LUAT_P256_H
#define LUAT_P256_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* R = k * G (固定基点, flash 预计算表 + 混合加法) */
int luat_p256_mul_g(uint8_t out_xy[64], const uint8_t k[32]);

/* R = k * P (变基点, 4-bit 窗口 + Jacobian 表; 校验 P 在曲线上) */
int luat_p256_mul(uint8_t out_xy[64], const uint8_t k[32], const uint8_t pt_xy[64]);

/* R = u1 * G + u2 * Q (ECDSA 验签用; 校验 Q 在曲线上) */
int luat_p256_muladd(uint8_t out_xy[64], const uint8_t u1[32], const uint8_t u2[32], const uint8_t q_xy[64]);

/* 点在曲线校验: 1 在曲线上, 0 不在 */
int luat_p256_on_curve(const uint8_t pt_xy[64]);

/* 基点 G 窗口表: k*G (k=1..15), 每项 16 个 u32 = X(8) || Y(8), 32-bit LE limbs */
extern const uint32_t luat_p256_gwin[15][16];

#ifdef __cplusplus
}
#endif

#endif /* LUAT_P256_H */
