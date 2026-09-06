/*
 * LuatOS mbedtls 增强组件统一声明:
 *  - TLS 随机源(每实例 CTR_DRBG + 裸 TRNG 回落)
 *      实现: components/crypto/luat_mbedtls_random.c
 *  - ECP G/Q comb 表进程级缓存
 *      实现: components/crypto/luat_mbedtls_ecp_cache.c
 *
 * ECP 缓存部分仅在目标 mbedtls 配置头定义了 LUAT_CONF_MBEDTLS_ECP_CACHE
 * 时参与编译(实现文件同为该宏门控); 随机源部分默认随 luat/network 组件编译.
 */
#ifndef LUAT_MBEDTLS_H
#define LUAT_MBEDTLS_H

#include "luat_base.h"

/* =====================================================================
 * mbedtls TLS 随机源
 * ---------------------------------------------------------------------
 * 每实例(每 socket)独立 CTR_DRBG: 创建时只从裸 TRNG(luat_crypto_trng)取
 * 一次种子, 之后 mbedtls 取随机数走软件 AES-CTR(裸 TRNG 每 24B 约 4ms,
 * 一次握手仅点乘随机化就要 ~99ms; DRBG 单次 ~0.3ms). DRBG 不可用
 * (mbedtls 4.x / 未开 CTR_DRBG / 分配或种子失败)时 new() 返回 NULL,
 * random 回调自动回落裸 TRNG, 行为与 mbedtls 原生默认一致.
 * ===================================================================== */
typedef struct luat_mbedtls_rng luat_mbedtls_rng_t;

/* 创建并完成一次种子化的每实例随机源; 失败/不可用返回 NULL(回落裸 TRNG) */
luat_mbedtls_rng_t *luat_mbedtls_rng_new( void );

/* mbedtls f_rng 回调; p_rng 传 new() 的返回值(允许 NULL) */
int luat_mbedtls_rng_random( void *p_rng, unsigned char *output, size_t output_len );

/* 释放; 接受 NULL */
void luat_mbedtls_rng_free( luat_mbedtls_rng_t *rng );

/* =====================================================================
 * ECP G/Q comb 表进程级缓存(ecp_mul_comb / ecp_group_free 的 hook)
 * ---------------------------------------------------------------------
 * G 缓存: 基点 G 表(2 槽, P-256/P-384), 每握手新建 group 时免重建;
 * Q 缓存: 非 G 点表(受益者=验签公钥, 跨握手恒定), 键=曲线+T_size+X||Y.
 * 仅当 LUAT_CONF_MBEDTLS_ECP_CACHE 定义(目标 mbedtls 配置头)时启用;
 * 前提: mbedtls 2.x + MBEDTLS_ECP_FIXED_POINT_OPTIM==1 + 未开 RESTARTABLE.
 * 生命周期约定: g_publish 的表仍归原 group(经 owns 在 group_free 豁免);
 * q_publish 返回 1 = 表已收养(调用方跳过释放), 0 = 未缓存(仍归调用方).
 * ===================================================================== */
#if defined(LUAT_CONF_MBEDTLS_ECP_CACHE)
#include "mbedtls/ecp.h"

/* G 槽免锁读: 命中返回表指针(不归调用方), 未命中返回 NULL */
mbedtls_ecp_point *luat_ecp_g_cache_lookup( mbedtls_ecp_group_id id,
                                            unsigned char t_size );

/* 新构建的基点 G 表: 先到先得提升为进程级静态缓存(仍归 grp->T) */
void luat_ecp_g_cache_publish( mbedtls_ecp_group_id id,
                               unsigned char t_size,
                               mbedtls_ecp_point *t );

/* Q 槽持锁查找(内部导出 X||Y 键); 命中返回表指针, 未命中/不可导出返回 NULL */
mbedtls_ecp_point *luat_ecp_q_cache_lookup( mbedtls_ecp_group_id id,
                                            unsigned char t_size,
                                            const mbedtls_ecp_point *P,
                                            unsigned nbits );

/* 新构建的非 G 点表尝试发布进 Q 缓存; 返回 1=已收养(调用方跳过释放) */
int luat_ecp_q_cache_publish( mbedtls_ecp_group_id id,
                              unsigned char t_size,
                              const mbedtls_ecp_point *P,
                              unsigned nbits,
                              mbedtls_ecp_point *t );

/* 缓存是否持有该指针(供 ecp_group_free 豁免释放; 仅 G 表可能挂在 grp->T) */
int luat_ecp_cache_owns( const mbedtls_ecp_point *t );

#endif /* LUAT_CONF_MBEDTLS_ECP_CACHE */

#endif /* LUAT_MBEDTLS_H */
