/*
 * tfs_cache.h — Write cache for TFS
 *
 * Provides TFS_CFG_N_CACHES chunk-sized write-cache entries.
 * On a cache miss the least-recently-used clean entry is reclaimed;
 * dirty entries must be flushed first (either explicitly or by GC).
 */

#ifndef TFS_CACHE_H
#define TFS_CACHE_H

#include "../inc/tfs_types.h"
#include "tfs_dev.h"

/*-------------------------------------------------------------------
 *  Init / deinit
 *-------------------------------------------------------------------*/

int  tfs_cache_init  (tfs_dev_t *dev);
void tfs_cache_deinit(tfs_dev_t *dev);

/*-------------------------------------------------------------------
 *  Cache lookup / allocation
 *-------------------------------------------------------------------*/

/**
 * tfs_cache_find — find a cache entry for (obj, chunk_id)
 * Returns NULL if not cached.
 */
tfs_cache_entry_t *tfs_cache_find(tfs_dev_t *dev,
                                  tfs_obj_t *obj,
                                  int chunk_id);

/**
 * tfs_cache_get — find or allocate a cache entry for writing.
 * Evicts the LRU clean entry if all slots are occupied.
 * Returns NULL if all slots are dirty/locked (caller should flush first).
 */
tfs_cache_entry_t *tfs_cache_get(tfs_dev_t *dev,
                                  tfs_obj_t *obj,
                                  int chunk_id);

/*-------------------------------------------------------------------
 *  Flush
 *-------------------------------------------------------------------*/

/**
 * tfs_cache_flush_obj — write all dirty entries for obj to NAND
 */
int tfs_cache_flush_obj(tfs_dev_t *dev, tfs_obj_t *obj);

/**
 * tfs_cache_flush_all — write all dirty entries in the cache to NAND
 */
int tfs_cache_flush_all(tfs_dev_t *dev);

/**
 * tfs_cache_invalidate_obj — discard (without writing) all entries for obj
 */
void tfs_cache_invalidate_obj(tfs_dev_t *dev, tfs_obj_t *obj);

/**
 * tfs_cache_invalidate_chunk — discard one specific cached chunk
 */
void tfs_cache_invalidate_chunk(tfs_dev_t *dev, tfs_obj_t *obj,
                                int chunk_id);

#endif /* TFS_CACHE_H */
