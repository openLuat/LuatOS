/* Copyright (C) 2018 RDA Technologies Limited and/or its affiliates("RDA").
 * All rights reserved.
 *
 * This software is supplied "AS IS" without any warranties.
 * RDA assumes no responsibility or liability for the use of the software,
 * conveys no license or title under any patent, copyright, or mask work
 * right to the product. RDA reserves the right to make changes in the
 * software without notification.  RDA also make no representation or
 * warranty that such application will be suitable for the specified use
 * without further testing or modification.
 */

#ifndef __OSI_MEM_H__
#define __OSI_MEM_H__

#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * opaque data structure for memory pool
 */
typedef struct osiMemPool osiMemPool_t;

/**
 * memory pool information
 */
typedef struct
{
    void *start;             ///< memory pool start pointer
    uint32_t size;           ///< memory pool total size
    uint32_t index;          ///< memory pool internal index
    uint32_t avail_size;     ///< available size. The actual allocatable size may be less than this
    uint32_t max_block_size; ///< maximum allocatable block size
} osiMemPoolStat_t;

/**
 * initialize a fixed pool
 *
 * Initialize and register a fixed size block pool. The pool management data
 * structure will be located inside the provided memory, Due to alignment
 * it may exist an offset.
 *
 * @note Due to there are management overhead, the available block count is
 * not `pool_size/block_size`.
 *
 * @param ptr   starting pointer of the memory
 * @param size  memory total size
 * @param block_size    block size
 * @return
 *      - the pool pointer on success
 *      - NULL on failure
 */
osiMemPool_t *osiFixedPoolInit(void *ptr, size_t size, size_t block_size);

/**
 * initialize a block pool
 *
 * Initialize and register a block pool pool. The variadic parameters should
 * be ended with a zero. Each pair of (size_t count, size_t size) indicates
 * to create a fixed pool child for the block pool. When allocating from
 * the block pool, fixed pool children will be checked automatically. It
 * may be helpful to reduce memory fragmentation.
 *
 * The management data structure of block pool and all children will be
 * located inside the provided memory.
 *
 * @note The feature of fixed block pool inside is experimental.
 *
 * @param ptr   starting pointer of the memory pool.
 * @param size  memory pool size
 * @return
 *      - the pool pointer on success
 *      - NULL on failure
 */
osiMemPool_t *osiBlockPoolInit(void *ptr, size_t size, ...);

/**
 * set the default pool
 *
 * Default pool will be used by malloc/calloc, and it must be block pool.
 * The first created block pool will be set to default automatically.
 * And this API will change default pool.
 *
 * When \a pool is NULL or invalid, it will return silently.
 *
 * @param pool  pool to be set as default.
 */
void osiPoolSetDefault(osiMemPool_t *pool);

/**
 * allocate from specified pool
 *
 * When \a pool is NULL or invalid, or \a size is zero, NULL will be
 * returned.
 *
 * Refer to malloc(3).
 *
 * @param pool  the pool
 * @param size  size to be allocated
 * @return
 *      - allocated memory pointer on success
 *      - NULL at failure
 */
void *osiPoolMalloc(osiMemPool_t *pool, size_t size);

/**
 * allocate from specified pool, which is unlikely to be freed
 *
 * Comparing to \a osiPoolMalloc, allocator will try to allocate
 * from location with less fragmentation impact.
 *
 * Usually, it only be called at system initialization. It is a replacement
 * of global variable (either DATA or BSS).
 *
 * @param pool  the pool
 * @param size  size to be allocated
 * @return
 *      - allocated memory pointer on success
 *      - NULL at failure
 */
void *osiPoolMallocUnlikelyFree(osiMemPool_t *pool, size_t size);

/**
 * allocate from specified pool, and clear to zero
 *
 * It is the exact same as `osiPoolMalloc(pool, nmemb*size)` and clear
 * memory to zero.
 *
 * Refer to calloc(3).
 *
 * @param pool  the pool.
 * @param nmemb member count to be allocated.
 * @param size  size of each member.
 * @return
 *      - allocated memory pointer on success
 *      - NULL at failure
 */
void *osiPoolCalloc(osiMemPool_t *pool, size_t nmemb, size_t size);

/**
 * change size of memory block
 *
 * Refer to realloc(3).
 *
 * @param pool  the pool.
 * @param ptr   pointer to be changed.
 * @param size  changed size.
 * @return
 *      - allocated memory pointer on success
 *      - NULL at failure
 */
void *osiPoolRealloc(osiMemPool_t *pool, void *ptr, size_t size);

/**
 * allocate from specified pool with specified alignment
 *
 * The pool must be block pool.
 *
 * \a alignment should be power of 2. When \a alignment is less than
 * default alignment, it will behavior the same as `osiPoolMalloc`.
 *
 * Refer to memalign(3).
 *
 * @param[in] pool The pool
 * @param[in] alignment Requested alignment
 * @param[in] size Size to be allocated
 * @return
 *      - allocated memory pointer on success
 *      - NULL at failure
 */
void *osiPoolMemalign(osiMemPool_t *pool, size_t alignment, size_t size);

/**
 * set memory block caller address
 *
 * Caller address is for debug only. And won't affect behavior. All APIs
 * in this module will set caller automatically. Only for memory management
 * wrappers, and it is wanted to set caller to the caller of wrapper,
 * this function may be called.
 *
 * @param ptr       pointer of memory block.
 * @param caller    caller address
 */
void osiMemSetCaller(void *ptr, void *caller);

/**
 * get the allocated size for the pointer
 *
 * The size is allocated by memory management. The size may be larger than
 * the size requested, due to tail padding.
 *
 * @param ptr       pointer of memory block
 * @return
 *      - allocated memory block size
 *      - 0 if \p ptr is NULL
 *      - -1 if \p ptr is invalid
 */
int osiMemAllocSize(void *ptr);

/**
 * increase reference count of the pointer
 *
 * When the reference count reach the maximum allowed reference count,
 * system will panic.
 *
 * When \p ptr is NULL, nothing will be done.
 *
 * @param ptr       pointer of memory block
 */
void osiMemRef(void *ptr);

/**
 * get reference count of the pointer
 *
 * When \p ptr is NULL, 0 will be returned.
 *
 * @param ptr       pointer of memory block
 * @return  reference count of the pointer
 */
size_t osiMemRefCount(void *ptr);

/**
 * decrease reference if the reference count is not 1
 *
 * At object oriented design with refrence count, it is not enough to
 * consider memory reference count only. Rather, it is needed to
 * consider the object reference count. So, the *delete* function of
 * object should be:
 *
 * \code{.cpp}
 * void objectDelete(void *object)
 * {
 *     if (osiMemUnrefNotLast(object))
 *         return;
 *
 *     objectCleanup(object);
 *     free(object);
 * }
 * \endcode
 *
 * When the reference count of the object, which is stored inside memory
 * management, is not 1, only decrease the reference count. Only when
 * it is the last reference, the cleanup shall be called.
 *
 * When \p ptr is NULL, it will return true, and do nothing. Conceptually,
 * NULL pointer can be regarded as reference count of 0. So, it is not
 * the last reference.
 *
 * When reference count of \p ptr is greater than 1, the reference count
 * will be decreased by 1, and it is the same as \p free.
 *
 * @param ptr       pointer of memory block
 * @return
 *      - true if it is not the last reference, or \p ptr is NULL
 *      - false if it is the last reference
 */
bool osiMemUnrefNotLast(void *ptr);

/**
 * refer to malloc(3).
 */
void *osiMalloc(size_t size);

/**
 * refer to calloc(3).
 */
void *osiCalloc(size_t nmemb, size_t size);

/**
 * refer to realloc(3).
 */
void *osiRealloc(void *ptr, size_t size);

/**
 * refer to memalign(3).
 */
void *osiMemalign(size_t alignment, size_t size);

/**
 * refer to free(3).
 */
void osiFree(void *ptr);

/**
 * get memory pool information
 *
 * \a max_block_size is the maximum allocatable size. \a realloc and
 * \a memalign will use more extra spaces, they may fail with that size.
 *
 * \code{.cpp}
 * malloc(stat->max_block_size);        // will success
 * realloc(ptr, stat->max_block_size);  // may fail
 * memalign(32, stat->max_block_size);  // may fail
 * \endcode
 *
 * @param pool      the memory pool. \a NULL for default memory pool
 * @param stat      output memory pool information
 * @return
 *      - true on success
 *      - false if there are no memory pool, or \a stat is NULL
 */
bool osiMemPoolStat(osiMemPool_t *pool, osiMemPoolStat_t *stat);

#ifdef __cplusplus
}
#endif
#endif
