/*
 * mbedtls 小对象固定块内存池 (跨平台: ARMv7-M/ARMv7E-M + 其它平台)
 *
 * 背景: EC7xx 实测系统 calloc/free 单次约 2000~2900 周期(300MHz 下 ~7-10us),
 * 一次 TLS-ECDHE-ECDSA 握手产生 3 万+ 次 MPI 堆操作, 仅堆开销约 280ms.
 * mbedtls 的 MPI limb 缓冲绝大多数 <= 176B(P-521 乘积 34 limb = 136B),
 * 固定块池 + 位图分配可把单次分配压到百周期级; 大块或池耗尽时回落系统
 * calloc/free, 行为完全等价, 无功能风险.
 *
 * 接线方式: mbedtls_ec7xx_config.h 中
 *   #define MBEDTLS_PLATFORM_CALLOC_MACRO  luat_mbedtls_pool_calloc
 *   #define MBEDTLS_PLATFORM_FREE_MACRO    luat_mbedtls_pool_free
 * (配置里 MBEDTLS_PLATFORM_MEMORY 已开, 宏覆盖路径生效)
 *
 * 并发模型:
 *  - ARMv7-M/ARMv7E-M (Cortex-M3/M4): 关中断临界区(PRIMASK), 不依赖
 *    RTOS/CMSIS 头文件, 线程/中断上下文均可安全调用.
 *  - 其它平台: luat_rtos.h 的递归互斥锁(luat_rtos_mutex_*). 锁在首次
 *    使用时创建; PC 上 entry_critical 为空实现, 但 mbedtls 调用发生在
 *    主线程/消息回调里, 实际为单线程语义, 不会出现并发建锁.
 *    需要在中断里调用 mbedtls_calloc 的裸机平台请走 ARM 关中断路径.
 *
 * 静态 RAM 开销: 0. 池内存(块数组+位图)不再是 22KB 静态数组, 而是首次
 * 使用时通过 luat_heap_opt_calloc(LUAT_HEAP_PSRAM) 一次性从 PSRAM 分配
 * (无 PSRAM 的弱实现自动回落系统堆). 分配失败/锁不可用时本池自动禁用,
 * 全部走系统堆, 功能等价. luat_mbedtls_pool_init() 提供幂等的预初始化
 * 入口(可选), 供平台在启动早期主动建立池、避免首次握手的分配抖动.
 */
#include "luat_base.h"
#include "luat_mem.h"
#ifdef TYPE_EC718M
#include "platform_def.h"
#endif
#include "luat_rtos.h"


#if defined(_MSC_VER)
#include <intrin.h>          /* _BitScanForward (MSVC 无 __builtin_ctz) */
#endif

#define LUAT_MB_POOL_BLOCK   176u   /* 44 limbs, 覆盖 P-521 乘积(34 limb=136B) */
#define LUAT_MB_POOL_COUNT   128u   /* 128 * 176B = 22KB, 首次使用时从 PSRAM 分配 */
#define LUAT_MB_POOL_WORDS   ( LUAT_MB_POOL_COUNT / 32u )

/* 池内存整体结构: 块数组(保证 8 字节对齐) + 分配位图, 一次 calloc 完成 */
typedef struct
{
    uint64_t blocks[LUAT_MB_POOL_COUNT][LUAT_MB_POOL_BLOCK / 8u];
    uint32_t map[LUAT_MB_POOL_WORDS];   /* 1=已用; calloc 清零后即全空闲 */
} luat_mb_pool_mem_t;

/* NULL = 池未建立(首次使用才分配) */
static luat_mb_pool_mem_t *s_pool = NULL;
/* 建立失败置 1: 池永久禁用, 避免每次 calloc 都重试 22KB 分配 */
static int s_pool_off = 0;

typedef uint32_t luat_mb_pool_lock_t;

static inline luat_mb_pool_lock_t luat_mb_pool_enter( void )
{
    return luat_rtos_entry_critical();
}

static inline void luat_mb_pool_exit( luat_mb_pool_lock_t primask )
{
    luat_rtos_exit_critical( primask );
}

static inline uint32_t luat_mb_pool_ctz( uint32_t v )
{
#if defined(_MSC_VER)
    unsigned long idx;
    _BitScanForward( &idx, (unsigned long)v );
    return( (uint32_t) idx );
#else
    return( (uint32_t) __builtin_ctz( v ) );
#endif
}

/*
 * 幂等初始化: 建锁(非 ARM)+分配池内存, 均只执行一次.
 * 分配动作放在锁外执行, 避免 22KB PSRAM calloc 长时间关中断(ARM)
 * 或持锁(其它平台); 发布时二次确认, 并发初始化丢失的一方释放自建副本.
 * 返回 0 成功 / -1 失败(调用方回落系统堆, 本池保持禁用).
 */
int luat_mbedtls_pool_init( void )
{
    luat_mb_pool_mem_t *mem;
    luat_mb_pool_lock_t st;

    if( s_pool != NULL )
        return( 0 );
    if( s_pool_off )                           /* 上次建立失败, 已永久禁用 */
        return( -1 );

    mem = (luat_mb_pool_mem_t *) luat_heap_opt_calloc(
              LUAT_HEAP_PSRAM, 1, sizeof( luat_mb_pool_mem_t ) );
    if( mem == NULL )
    {
        s_pool_off = 1;                        /* PSRAM 不可用, 永久回落系统堆 */
        return( -1 );
    }

    st = luat_mb_pool_enter();                 /* 发布, 并只保留一份 */
    if( s_pool == NULL )
        s_pool = mem;
    luat_mb_pool_exit( st );

    if( s_pool != mem )                        /* 并发初始化: 释放自己的副本 */
        luat_heap_opt_free(LUAT_HEAP_PSRAM, mem );

    return( 0 );
}

void *luat_mbedtls_pool_calloc( size_t n, size_t size )
{
    size_t total;
    luat_mb_pool_lock_t st;
    uint32_t w;

    if( size != 0 && n > ( (size_t) -1 ) / size )
        return( NULL );                     /* 乘法溢出 */
    total = n * size;
    if( total == 0 || total > LUAT_MB_POOL_BLOCK )
        return( luat_heap_opt_calloc(LUAT_HEAP_PSRAM, n, size ) );        /* 大块直接走系统堆 */

    if( s_pool == NULL && luat_mbedtls_pool_init() != 0 )
        return( luat_heap_opt_calloc(LUAT_HEAP_PSRAM, n, size ) );        /* 池不可用回落 */

    st = luat_mb_pool_enter();
    for( w = 0; w < LUAT_MB_POOL_WORDS; w++ )
    {
        uint32_t freebits = ~s_pool->map[w];
        if( freebits != 0 )
        {
            uint32_t bit = luat_mb_pool_ctz( freebits );
            s_pool->map[w] |= ( 1u << bit );
            luat_mb_pool_exit( st );
            memset( s_pool->blocks[w * 32u + bit], 0, LUAT_MB_POOL_BLOCK );
            return( s_pool->blocks[w * 32u + bit] );
        }
    }
    luat_mb_pool_exit( st );

    return( luat_heap_opt_calloc(LUAT_HEAP_PSRAM, n, size ) );            /* 池耗尽回落系统堆 */
}

void luat_mbedtls_pool_free( void *ptr )
{
    luat_mb_pool_lock_t st;
    uintptr_t base, p;
    size_t idx;

    if( ptr == NULL )
        return;

    if( s_pool == NULL )
    {
        /* 池从未建立: 池内不可能有指针, 直接回落系统堆 */
        luat_heap_opt_free(LUAT_HEAP_PSRAM, ptr );
        return;
    }

    base = (uintptr_t) s_pool->blocks;
    p    = (uintptr_t) ptr;
    if( p >= base && p < base + sizeof( s_pool->blocks ) )
    {
        idx = (size_t)( ( p - base ) / LUAT_MB_POOL_BLOCK );
        st = luat_mb_pool_enter();
        s_pool->map[idx >> 5] &= ~( 1u << ( idx & 31u ) );
        luat_mb_pool_exit( st );
        return;
    }
    luat_heap_opt_free(LUAT_HEAP_PSRAM, ptr );
}
