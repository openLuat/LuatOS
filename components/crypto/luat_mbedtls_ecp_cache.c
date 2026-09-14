/*
 * mbedtls ECP comb 表进程级缓存组件 (G 缓存 + Q 缓存)
 *
 * 背景: EC7xx 上 TLS 每次握手都新建 ecp_group, mbedtls 原生的 grp->T
 * 缓存随 group 释放, 同一条曲线的基点 G 表每握手要全量重建 2 次
 * (密钥生成 + 验签, M3@300MHz: P-256 每次 ~63ms); 验签公钥 Q 的
 * comb 表每握手重建 ~62ms. 本组件把这两类表提升为进程级静态缓存:
 *   - G 缓存: 2 槽按曲线 id 索引(覆盖 P-256 / P-384; P-521 已裁剪),
 *     表由 mbedtls 自身代码构建, 只增不删(无泄漏/重复释放风险);
 *   - Q 缓存: 键 = (曲线 id, T_size, X||Y 大端字节), 8 槽指针数组,
 *     条目按需分配; 驱逐策略: 空槽优先 -> 只逐出 hits==0 的槽 ->
 *     全热表则放弃缓存.
 *
 * 启用开关: LUAT_CONF_MBEDTLS_ECP_CACHE(在目标 mbedtls 配置头中定义,
 * 与 pool 的 MBEDTLS_PLATFORM_CALLOC_MACRO 同处). 未定义时本文件为
 * 空编译单元, 零开销.
 * 前提: mbedtls 2.x + MBEDTLS_ECP_FIXED_POINT_OPTIM==1 + 未开
 * MBEDTLS_ECP_RESTARTABLE.
 *
 * 并发/生命周期不变式(勿破坏):
 *   1. G 槽条目 tbl 最后发布(先写 id/size, 屏障, 再写 tbl), lookup 仅读;
 *      G 表发布后永不被释放 -> 免锁读无悬垂.
 *   2. Q 槽查找/驱逐/发布在临界区内互斥; 驱逐只允许 hits==0 的槽
 *      (命中过的表必然有并发读者持有, 禁驱逐); 命中时在临界区内记 hits.
 *   3. 条目/表在临界区外分配与释放(pool/系统分配可能带锁).
 *   4. 逐出旧表的释放顺序: 先逐槽释放 mbedtls_ecp_point, 再 free 数组
 *      与条目, 均在临界区外执行.
 *   5. 锁: ARM(v7M/7EM) 用 PRIMASK 关中断; 其它平台(PC 模拟/测试)用
 *      luat_rtos 递归互斥锁(与 luat_mbedtls_pool.c 同款策略).
 *   6. Q 发布返回 1 表示本组件已收养该表, 调用方(ecp.c)须跳过释放;
 *      返回 0 时表仍归调用方, 走正常释放.
 *
 * 注意: LUAT_CONF_MBEDTLS_ECP_CACHE 定义在 mbedtls 配置头中, 因此本文件
 * 必须先 include mbedtls 头(使配置宏可见), 再判 #if.
 */
#include <stdint.h>
#include <string.h>

#include "mbedtls/platform.h"
#include "mbedtls/ecp.h"
#include "mbedtls/bignum.h"
#include "luat_mbedtls.h"

#if defined(LUAT_CONF_MBEDTLS_ECP_CACHE)

#if defined(__ARM_ARCH_7M__) || defined(__ARM_ARCH_7EM__)
#define LUAT_ECP_TCACHE_ARM 1
#else
#define LUAT_ECP_TCACHE_ARM 0
#endif

#if !LUAT_ECP_TCACHE_ARM
#include "luat_rtos.h"
#endif

#define LUAT_ECP_G_TCACHE_MAX   2    /* 覆盖 P-256 / P-384 */
#define LUAT_ECP_Q_TCACHE_MAX   8
#define LUAT_ECP_Q_XY_MAX       48   /* 单坐标最大字节数(P-384; 超宽导出失败即不缓存) */

/* ---------- G 缓存: 基点 G 的 comb 表(进程级静态, 只增不删) ---------- */

typedef struct
{
    mbedtls_ecp_point *tbl;     /* NULL=空槽; 发布时最后写 */
    mbedtls_ecp_group_id id;
    unsigned char size;
} luat_ecp_gt_cache_entry;

static luat_ecp_gt_cache_entry luat_ecp_gt_cache[LUAT_ECP_G_TCACHE_MAX];

/* ---------- Q 缓存: 非 G 点 comb 表(按 X||Y 键命中) ---------- */

typedef struct
{
    mbedtls_ecp_point *tbl;     /* 表本体(堆) */
    uint32_t last_use;          /* LRU/调试用时钟 */
    uint32_t hits;              /* 命中次数, 0=从未复用 */
    mbedtls_ecp_group_id id;
    unsigned char size;         /* T_size */
    unsigned char xy_len;       /* 单坐标字节数 */
    unsigned char xy[];         /* X||Y 大端键, 2*xy_len 字节 */
} luat_ecp_qt_cache_entry;

static luat_ecp_qt_cache_entry *luat_ecp_qt_cache[LUAT_ECP_Q_TCACHE_MAX];
static uint32_t luat_ecp_qt_clock;

/* ---------- 临界区原语: ARM=PRIMASK, 其它=luat_rtos 递归锁 ---------- */

#if LUAT_ECP_TCACHE_ARM

typedef uint32_t luat_ecp_tcache_lock_t;

static luat_ecp_tcache_lock_t luat_ecp_tcache_enter( void )
{
    uint32_t primask;
    __asm volatile ( "mrs %0, primask\n cpsid i" : "=r"( primask ) :: "memory" );
    return( primask );
}

static void luat_ecp_tcache_exit( luat_ecp_tcache_lock_t primask )
{
    __asm volatile ( "msr primask, %0" :: "r"( primask ) : "memory" );
}

/* 发布顺序屏障: 保证 id/size 先于 tbl 可见 */
static void luat_ecp_tcache_fence( void )
{
    __asm volatile ( "" ::: "memory" );
}

#else /* 非 ARM: PC 模拟/测试路径, 实际调用方只在主动开启后出现 */

typedef int luat_ecp_tcache_lock_t;
static luat_rtos_mutex_t s_ecp_tcache_mtx = NULL;

static luat_ecp_tcache_lock_t luat_ecp_tcache_enter( void )
{
    if( s_ecp_tcache_mtx == NULL )
    {
        uint32_t cri = luat_rtos_entry_critical();
        if( s_ecp_tcache_mtx == NULL )
            luat_rtos_mutex_create( &s_ecp_tcache_mtx );
        luat_rtos_exit_critical( cri );
    }
    if( s_ecp_tcache_mtx != NULL )
        luat_rtos_mutex_lock( s_ecp_tcache_mtx, LUAT_WAIT_FOREVER );
    return( 0 );
}

static void luat_ecp_tcache_exit( luat_ecp_tcache_lock_t st )
{
    (void) st;
    if( s_ecp_tcache_mtx != NULL )
        luat_rtos_mutex_unlock( s_ecp_tcache_mtx );
}

static void luat_ecp_tcache_fence( void )
{
    /* 互斥锁自带次序保证, 空实现 */
}

#endif /* LUAT_ECP_TCACHE_ARM */

/* ---------- G 缓存 API ---------- */

mbedtls_ecp_point *luat_ecp_g_cache_lookup( mbedtls_ecp_group_id id,
                                            unsigned char t_size )
{
    int i;
    for( i = 0; i < LUAT_ECP_G_TCACHE_MAX; i++ )
        if( luat_ecp_gt_cache[i].tbl != NULL &&
            luat_ecp_gt_cache[i].id == id &&
            luat_ecp_gt_cache[i].size == t_size )
            return( luat_ecp_gt_cache[i].tbl );
    return( NULL );
}

void luat_ecp_g_cache_publish( mbedtls_ecp_group_id id,
                               unsigned char t_size,
                               mbedtls_ecp_point *t )
{
    int ci, empty = -1, dup = 0;
    luat_ecp_tcache_lock_t st = luat_ecp_tcache_enter();

    for( ci = 0; ci < LUAT_ECP_G_TCACHE_MAX; ci++ )
    {
        if( luat_ecp_gt_cache[ci].tbl == NULL )
        {
            if( empty < 0 )
                empty = ci;
        }
        else if( luat_ecp_gt_cache[ci].id == id )
        {
            dup = 1;            /* 同曲线已被别的线程先发布 */
            break;
        }
    }
    if( !dup && empty >= 0 )
    {
        luat_ecp_gt_cache[empty].id = id;
        luat_ecp_gt_cache[empty].size = t_size;
        luat_ecp_tcache_fence();
        luat_ecp_gt_cache[empty].tbl = t;   /* tbl 最后发布 */
    }
    luat_ecp_tcache_exit( st );
}

/* 判断缓存是否持有该指针(供 ecp_group_free 豁免释放; 仅 G 表可能挂在 grp->T) */
int luat_ecp_cache_owns( const mbedtls_ecp_point *t )
{
    int i;
    for( i = 0; i < LUAT_ECP_G_TCACHE_MAX; i++ )
        if( luat_ecp_gt_cache[i].tbl == t )
            return( 1 );
    return( 0 );
}

/* ---------- Q 缓存内部辅助 ---------- */

/* 导出点 X||Y 大端字节, 返回单坐标字节数; 曲线超宽/失败返回 0(不缓存) */
static unsigned char luat_ecp_q_export_xy( const mbedtls_ecp_point *P,
                                           unsigned nbits,
                                           unsigned char *xy )
{
    size_t len = ( nbits + 7 ) / 8;
    if( len == 0 || len > LUAT_ECP_Q_XY_MAX )
        return( 0 );
    if( mbedtls_mpi_write_binary( &P->X, xy, len ) != 0 ||
        mbedtls_mpi_write_binary( &P->Y, xy + len, len ) != 0 )
        return( 0 );
    return( (unsigned char) len );
}

/* ---------- Q 缓存 API ---------- */

mbedtls_ecp_point *luat_ecp_q_cache_lookup( mbedtls_ecp_group_id id,
                                            unsigned char t_size,
                                            const mbedtls_ecp_point *P,
                                            unsigned nbits )
{
    unsigned char xy[2 * LUAT_ECP_Q_XY_MAX];
    unsigned char xy_len;
    mbedtls_ecp_point *hit = NULL;
    int i;
    luat_ecp_qt_cache_entry *e;
    luat_ecp_tcache_lock_t st;

    xy_len = luat_ecp_q_export_xy( P, nbits, xy );
    if( xy_len == 0 )
        return( NULL );

    st = luat_ecp_tcache_enter();
    for( i = 0; i < LUAT_ECP_Q_TCACHE_MAX; i++ )
    {
        e = luat_ecp_qt_cache[i];
        if( e != NULL &&
            e->id == id &&
            e->size == t_size &&
            e->xy_len == xy_len &&
            memcmp( e->xy, xy, 2u * xy_len ) == 0 )
        {
            e->hits++;
            e->last_use = ++luat_ecp_qt_clock;
            hit = e->tbl;
            break;
        }
    }
    luat_ecp_tcache_exit( st );
    return( hit );
}

/*
 * 发布新构建的非 G 点表. 返回 1=已收养(表归缓存所有, 调用方跳过释放);
 * 0=放弃缓存(表仍归调用方). 驱逐策略: 空槽优先 -> 只逐出 hits==0 的槽
 * -> 全热表放弃. 被逐出条目的释放发生在临界区外.
 */
int luat_ecp_q_cache_publish( mbedtls_ecp_group_id id,
                              unsigned char t_size,
                              const mbedtls_ecp_point *P,
                              unsigned nbits,
                              mbedtls_ecp_point *t )
{
    unsigned char xy[2 * LUAT_ECP_Q_XY_MAX];
    unsigned char xy_len;
    int ci, pick = -1, ei;
    int adopted = 0;
    luat_ecp_qt_cache_entry *evict = NULL;
    luat_ecp_qt_cache_entry *ne;
    luat_ecp_tcache_lock_t st;

    xy_len = luat_ecp_q_export_xy( P, nbits, xy );
    if( xy_len == 0 )
        return( 0 );

    /* 条目在临界区外分配(池分配可能带锁); 键长按实际坐标宽度定长 */
    ne = mbedtls_calloc( 1, sizeof( *ne ) + 2u * xy_len );
    if( ne == NULL )
        return( 0 );

    st = luat_ecp_tcache_enter();
    for( ci = 0; ci < LUAT_ECP_Q_TCACHE_MAX; ci++ )
    {
        if( luat_ecp_qt_cache[ci] == NULL )
        {
            pick = ci;
            break;
        }
        if( pick < 0 && luat_ecp_qt_cache[ci]->hits == 0 )
            pick = ci;
    }
    if( pick >= 0 )
    {
        evict = luat_ecp_qt_cache[pick];
        ne->id      = id;
        ne->size    = t_size;
        ne->xy_len  = xy_len;
        memcpy( ne->xy, xy, 2u * xy_len );
        ne->hits     = 0;
        ne->last_use = ++luat_ecp_qt_clock;
        ne->tbl      = t;
        luat_ecp_tcache_fence();
        luat_ecp_qt_cache[pick] = ne;   /* 槽指针最后发布 */
        ne = NULL;
        adopted = 1;
    }
    luat_ecp_tcache_exit( st );

    /* 槽位全是热表而放弃缓存时, 丢弃备好的条目(T 走调用方正常释放) */
    mbedtls_free( ne );
    /* 被逐出的旧条目与旧表在临界区外正常释放 */
    if( evict != NULL )
    {
        for( ei = 0; ei < (int) evict->size; ei++ )
            mbedtls_ecp_point_free( &evict->tbl[ei] );
        mbedtls_free( evict->tbl );
        mbedtls_free( evict );
    }

    return( adopted );
}

#endif /* LUAT_CONF_MBEDTLS_ECP_CACHE */
