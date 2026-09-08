/*
 * luat_p256_glue.c — P-256 快速路径与 mbedtls 2.x 的胶水层.
 *
 * 仅在目标 mbedtls 配置头定义 LUAT_CONF_MBEDTLS_ECP_P256_FAST 时编译出内容
 * (当前为 luatos-soc-2024 interface/include/mbedtls_ec7xx_config.h, mbedtls 2.28).
 * PC 模拟器 (mbedtls3) 不定义该宏, 本文件为空翻译单元.
 *
 * 挂钩点: components/mbedtls/library/ecp.c mbedtls_ecp_mul_restartable().
 * 语义保证:
 *  - 返回 0: R 已写入, 与原 ecp_mul_comb 结果一致;
 *  - 返回 1: 本路径不适用(非 P-256/点非仿射/标量或点异常/结果为无穷远),
 *    调用方落回原 comb 路径, 行为与未挂钩完全一致;
 *  - 返回 <0: mbedtls 错误码.
 * 前置条件由 mbedtls_ecp_mul_restartable 的 check_privkey/check_pubkey 保证:
 * 1 <= m < n 且 P 在曲线上.
 */
#include "luat_p256.h"

/* LUAT_CONF_MBEDTLS_ECP_P256_FAST 定义在目标 mbedtls 配置头里,
 * 必须先包含 mbedtls 头(经 MBEDTLS_CONFIG_FILE 拉入)再判断宏 */
#include "mbedtls/ecp.h"

#if defined(LUAT_CONF_MBEDTLS_ECP_P256_FAST)

#include <string.h>

int luat_mbedtls_p256_mul( mbedtls_ecp_group *grp, mbedtls_ecp_point *R,
                           const mbedtls_mpi *m, const mbedtls_ecp_point *P )
{
    uint8_t k[32], pt[64], out[64];
    int ret, rc;

    if( grp->id != MBEDTLS_ECP_DP_SECP256R1 )
        return( 1 );
    /* 需要仿射输入点 (check_pubkey 之后 Z 必为 1, 防御性判断) */
    if( mbedtls_mpi_cmp_int( &P->Z, 1 ) != 0 )
        return( 1 );
    if( mbedtls_mpi_size( m ) > 32 ||
        mbedtls_mpi_size( &P->X ) > 32 || mbedtls_mpi_size( &P->Y ) > 32 )
        return( 1 );

    if( ( ret = mbedtls_mpi_write_binary( m, k, 32 ) ) != 0 )
        return( ret );
    if( ( ret = mbedtls_mpi_write_binary( &P->X, pt, 32 ) ) != 0 )
        return( ret );
    if( ( ret = mbedtls_mpi_write_binary( &P->Y, pt + 32, 32 ) ) != 0 )
        return( ret );

    /* 基点走 flash 表快速路径 */
    if( mbedtls_mpi_cmp_mpi( &P->X, &grp->G.X ) == 0 &&
        mbedtls_mpi_cmp_mpi( &P->Y, &grp->G.Y ) == 0 )
        rc = luat_p256_mul_g( out, k );
    else
        rc = luat_p256_mul( out, k, pt );

    if( rc != 0 )
    {
        /* 无穷远结果或意外输入: 回退原实现, 保持完全一致的行为 */
        return( 1 );
    }

    if( ( ret = mbedtls_mpi_read_binary( &R->X, out, 32 ) ) != 0 )
        return( ret );
    if( ( ret = mbedtls_mpi_read_binary( &R->Y, out + 32, 32 ) ) != 0 )
        return( ret );
    if( ( ret = mbedtls_mpi_lset( &R->Z, 1 ) ) != 0 )
        return( ret );
    return( 0 );
}

#endif /* LUAT_CONF_MBEDTLS_ECP_P256_FAST */
