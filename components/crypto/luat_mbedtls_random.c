/*
 * mbedtls TLS 随机源: 每实例 CTR_DRBG + 裸 TRNG 回落 (跨 mbedtls 2.x/3.x/4.x)
 *
 * 背景: EC7xx 裸 TRNG 每 24B 约 4ms, 一次 TLS-ECDHE 握手仅点乘随机化就要
 * ~99ms; 创建时做一次种子、之后走 CTR_DRBG(AES-256) 单次约 ~0.3ms.
 *
 * 行为(与原 luat_network_adapter.c 内联实现完全一致, 仅位置/命名变化):
 *  - mbedtls < 4.x 且启用 MBEDTLS_CTR_DRBG_C 时, 每个实例(每 socket)
 *    独立分配一个 CTR_DRBG 并完成一次种子, 互不共享, 免锁;
 *  - 种子不用 mbedtls_entropy: ec7xx 配置未注册任何默认熵源
 *    (MBEDTLS_ENTROPY_HARDWARE_ALT 未开), entropy 会返回 NO_SOURCES
 *    导致 seed 失败, 因此种子回调直接取 luat_crypto_trng(platform_random);
 *  - 分配失败/种子失败/DRBG reseed 异常一律回落裸 TRNG, 行为等价;
 *  - mbedtls 4.x 或无 CTR_DRBG 的配置保持原裸 TRNG 行为
 *    (luat_mbedtls_rng_new() 返回 NULL).
 *
 * 接线示例(网络适配器, 每 socket 一次):
 *   ctrl->tls_rng = luat_mbedtls_rng_new();
 *   mbedtls_ssl_conf_rng( config, luat_mbedtls_rng_random, ctrl->tls_rng );
 *   ...
 *   luat_mbedtls_rng_free( ctrl->tls_rng );
 */
#include "luat_base.h"
#include "luat_mem.h"
#include "luat_malloc.h"
#include "luat_crypto.h"
#include "luat_mbedtls.h"

#include "mbedtls/version.h"

#if MBEDTLS_VERSION_NUMBER < 0x04000000 && defined(MBEDTLS_CTR_DRBG_C)
#define LUAT_MBEDTLS_RNG_USE_DRBG 1
#else
#define LUAT_MBEDTLS_RNG_USE_DRBG 0
#endif

#if LUAT_MBEDTLS_RNG_USE_DRBG
#include "mbedtls/ctr_drbg.h"

struct luat_mbedtls_rng
{
    mbedtls_ctr_drbg_context drbg;
};

/* DRBG 种子回调: 直接取裸 TRNG, 不依赖 mbedtls_entropy(该配置下无可用熵源) */
static int luat_mbedtls_rng_entropy( void *p, unsigned char *out, size_t len )
{
    (void)p;
    luat_crypto_trng( (char*)out, len );
    return 0;
}
#endif /* LUAT_MBEDTLS_RNG_USE_DRBG */

/*
 * 创建并完成一次种子化的每实例随机源.
 * 返回 NULL 表示不可用(mbedtls 4.x / 无 CTR_DRBG / 分配或种子失败),
 * 调用方把 NULL 传给 luat_mbedtls_rng_random 即回落裸 TRNG.
 */
luat_mbedtls_rng_t *luat_mbedtls_rng_new( void )
{
#if LUAT_MBEDTLS_RNG_USE_DRBG
    luat_mbedtls_rng_t *rng = (luat_mbedtls_rng_t *)luat_heap_zalloc( sizeof( luat_mbedtls_rng_t ) );
    if( rng == NULL )
        return NULL;
    mbedtls_ctr_drbg_init( &rng->drbg );
    if( mbedtls_ctr_drbg_seed( &rng->drbg, luat_mbedtls_rng_entropy, NULL, NULL, 0 ) != 0 )
    {
        /* 种子失败保持 NULL, random 回落裸 TRNG */
        mbedtls_ctr_drbg_free( &rng->drbg );
        luat_heap_free( rng );
        return NULL;
    }
    return rng;
#else
    return NULL;
#endif
}

/*
 * mbedtls f_rng 回调; p_rng = luat_mbedtls_rng_new() 的返回值(允许 NULL).
 * DRBG 可用时走软件 AES-CTR; reseed 失败等异常或 NULL 时回落裸 TRNG.
 */
int luat_mbedtls_rng_random( void *p_rng, unsigned char *output, size_t output_len )
{
#if LUAT_MBEDTLS_RNG_USE_DRBG
    luat_mbedtls_rng_t *rng = (luat_mbedtls_rng_t *)p_rng;
    if( rng != NULL && mbedtls_ctr_drbg_random( &rng->drbg, output, output_len ) == 0 )
        return 0;
    /* reseed 失败等异常情况回落裸 TRNG */
#endif
    luat_crypto_trng( (char*)output, output_len );
    return 0;
}

void luat_mbedtls_rng_free( luat_mbedtls_rng_t *rng )
{
    if( rng == NULL )
        return;
#if LUAT_MBEDTLS_RNG_USE_DRBG
    mbedtls_ctr_drbg_free( &rng->drbg );
#endif
    luat_heap_free( rng );
}
