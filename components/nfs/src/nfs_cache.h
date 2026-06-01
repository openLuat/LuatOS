/*
 * nfs_cache.h — Write cache for NFS
 *
 * Provides NFS_CFG_N_CACHES chunk-sized write-cache entries.
 * On a cache miss the least-recently-used clean entry is reclaimed;
 * dirty entries must be flushed first (either explicitly or by GC).
 */

#ifndef NFS_CACHE_H
#define NFS_CACHE_H

#include "../inc/nfs_types.h"
#include "nfs_dev.h"

/*-------------------------------------------------------------------
 *  Init / deinit
 *-------------------------------------------------------------------*/

int  nfs_cache_init  (nfs_dev_t *dev);
void nfs_cache_deinit(nfs_dev_t *dev);

/*-------------------------------------------------------------------
 *  Cache lookup / allocation
 *-------------------------------------------------------------------*/

/**
 * nfs_cache_find — find a cache entry for (obj, chunk_id)
 * Returns NULL if not cached.
 */
nfs_cache_entry_t *nfs_cache_find(nfs_dev_t *dev,
                                  nfs_obj_t *obj,
                                  int chunk_id);

/**
 * nfs_cache_get — find or allocate a cache entry for writing.
 * Evicts the LRU clean entry if all slots are occupied.
 * Returns NULL if all slots are dirty/locked (caller should flush first).
 */
nfs_cache_entry_t *nfs_cache_get(nfs_dev_t *dev,
                                  nfs_obj_t *obj,
                                  int chunk_id);

/*-------------------------------------------------------------------
 *  Flush
 *-------------------------------------------------------------------*/

/**
 * nfs_cache_flush_obj — write all dirty entries for obj to NAND
 */
int nfs_cache_flush_obj(nfs_dev_t *dev, nfs_obj_t *obj);

/**
 * nfs_cache_flush_all — write all dirty entries in the cache to NAND
 */
int nfs_cache_flush_all(nfs_dev_t *dev);

/**
 * nfs_cache_invalidate_obj — discard (without writing) all entries for obj
 */
void nfs_cache_invalidate_obj(nfs_dev_t *dev, nfs_obj_t *obj);

/**
 * nfs_cache_invalidate_chunk — discard one specific cached chunk
 */
void nfs_cache_invalidate_chunk(nfs_dev_t *dev, nfs_obj_t *obj,
                                int chunk_id);

#endif /* NFS_CACHE_H */
