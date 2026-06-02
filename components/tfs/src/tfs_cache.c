/*
 * tfs_cache.c — Write cache for TFS
 *
 * Simple LRU write cache backed by a flat array of tfs_cache_entry_t.
 * Each entry owns a chunk-sized data buffer allocated at init time.
 * Dirty entries are written to NAND on flush; clean entries are
 * silently discarded when evicted.
 */

#include "tfs_cache.h"
#include "tfs_block.h"
#include "tfs_tnode.h"
#include "../inc/tfs_config.h"

#include <string.h>

/*===================================================================
 *  Init / deinit
 *===================================================================*/

int tfs_cache_init(tfs_dev_t *dev)
{
    int  i;
    int  n       = TFS_CFG_N_CACHES;
    int  chunk_sz = (int)dev->data_bytes_per_chunk;

    dev->cache_mgr.n_caches      = n;
    dev->cache_mgr.cache_last_use= 0;

    dev->cache_mgr.cache = (tfs_cache_entry_t *)
        dev->drv.malloc(dev->drv.ctx, (uint32_t)n * sizeof(tfs_cache_entry_t));
    if (!dev->cache_mgr.cache)
        return TFS_ENOMEM;

    memset(dev->cache_mgr.cache, 0, (size_t)n * sizeof(tfs_cache_entry_t));

    for (i = 0; i < n; i++) {
        dev->cache_mgr.cache[i].data =
            (uint8_t *)dev->drv.malloc(dev->drv.ctx, (uint32_t)chunk_sz);
        if (!dev->cache_mgr.cache[i].data) {
            /* Free what we already allocated */
            int j;
            for (j = 0; j < i; j++)
                dev->drv.free(dev->drv.ctx, dev->cache_mgr.cache[j].data);
            dev->drv.free(dev->drv.ctx, dev->cache_mgr.cache);
            dev->cache_mgr.cache = NULL;
            return TFS_ENOMEM;
        }
    }

    return TFS_OK;
}

void tfs_cache_deinit(tfs_dev_t *dev)
{
    int i;

    if (!dev->cache_mgr.cache)
        return;

    for (i = 0; i < dev->cache_mgr.n_caches; i++) {
        if (dev->cache_mgr.cache[i].data) {
            dev->drv.free(dev->drv.ctx, dev->cache_mgr.cache[i].data);
            dev->cache_mgr.cache[i].data = NULL;
        }
    }

    dev->drv.free(dev->drv.ctx, dev->cache_mgr.cache);
    dev->cache_mgr.cache   = NULL;
    dev->cache_mgr.n_caches= 0;
}

/*===================================================================
 *  Lookup
 *===================================================================*/

tfs_cache_entry_t *tfs_cache_find(tfs_dev_t *dev,
                                  tfs_obj_t *obj,
                                  int chunk_id)
{
    int i;

    for (i = 0; i < dev->cache_mgr.n_caches; i++) {
        tfs_cache_entry_t *ce = &dev->cache_mgr.cache[i];
        if (ce->object == obj && ce->chunk_id == chunk_id && ce->n_bytes > 0)
            return ce;
    }
    return NULL;
}

/*===================================================================
 *  Internal: flush one dirty entry
 *===================================================================*/

static int flush_one(tfs_dev_t *dev, tfs_cache_entry_t *ce)
{
    tfs_ext_tags_t ext;
    int            chunk_in_nand;
    int            rc;

    if (!ce->dirty || !ce->object)
        return TFS_OK;

    memset(&ext, 0, sizeof(ext));
    ext.chunk_used = 1;
    ext.obj_id     = ce->object->obj_id;
    ext.chunk_id   = (uint32_t)(ce->chunk_id + 1); /* 1-indexed: 0 is reserved for obj header */
    ext.n_bytes    = (uint32_t)ce->n_bytes;

    chunk_in_nand = tfs_alloc_chunk(dev, 0);
    if (chunk_in_nand < 0)
        return TFS_ENOSPC;

    rc = tfs_chunk_write(dev, chunk_in_nand, ce->data, ce->n_bytes, &ext);
    if (rc != TFS_OK)
        return rc;

    /* Update the tnode for this chunk */
    rc = tfs_tnode_put_chunk(dev, ce->object,
                             (uint32_t)ce->chunk_id,
                             (uint32_t)chunk_in_nand);
    if (rc != TFS_OK)
        return rc;

    ce->dirty = 0;
    return TFS_OK;
}

/*===================================================================
 *  Allocate / evict
 *===================================================================*/

tfs_cache_entry_t *tfs_cache_get(tfs_dev_t *dev,
                                  tfs_obj_t *obj,
                                  int chunk_id)
{
    int                i;
    tfs_cache_entry_t *found   = NULL;
    tfs_cache_entry_t *lru     = NULL;
    int                lru_use = dev->cache_mgr.cache_last_use + 1;

    /* Try exact match first */
    for (i = 0; i < dev->cache_mgr.n_caches; i++) {
        tfs_cache_entry_t *ce = &dev->cache_mgr.cache[i];
        if (ce->object == obj && ce->chunk_id == chunk_id) {
            found = ce;
            break;
        }
    }

    if (!found) {
        /* Find LRU clean entry to evict */
        for (i = 0; i < dev->cache_mgr.n_caches; i++) {
            tfs_cache_entry_t *ce = &dev->cache_mgr.cache[i];
            if (!ce->locked && !ce->dirty) {
                if (ce->last_use < lru_use) {
                    lru_use = ce->last_use;
                    lru     = ce;
                }
            }
        }

        if (!lru)
            return NULL;   /* all slots dirty/locked */

        found           = lru;
        found->object   = obj;
        found->chunk_id = chunk_id;
        found->n_bytes  = 0;
        found->dirty    = 0;
    }

    dev->cache_mgr.cache_last_use++;
    found->last_use = dev->cache_mgr.cache_last_use;
    return found;
}

/*===================================================================
 *  Flush
 *===================================================================*/

int tfs_cache_flush_obj(tfs_dev_t *dev, tfs_obj_t *obj)
{
    int i, rc;

    for (i = 0; i < dev->cache_mgr.n_caches; i++) {
        tfs_cache_entry_t *ce = &dev->cache_mgr.cache[i];
        if (ce->object == obj && ce->dirty) {
            rc = flush_one(dev, ce);
            if (rc != TFS_OK)
                return rc;
        }
    }
    return TFS_OK;
}

int tfs_cache_flush_all(tfs_dev_t *dev)
{
    int i, rc;

    for (i = 0; i < dev->cache_mgr.n_caches; i++) {
        tfs_cache_entry_t *ce = &dev->cache_mgr.cache[i];
        if (ce->dirty) {
            rc = flush_one(dev, ce);
            if (rc != TFS_OK)
                return rc;
        }
    }
    return TFS_OK;
}

/*===================================================================
 *  Invalidate
 *===================================================================*/

void tfs_cache_invalidate_obj(tfs_dev_t *dev, tfs_obj_t *obj)
{
    int i;

    for (i = 0; i < dev->cache_mgr.n_caches; i++) {
        tfs_cache_entry_t *ce = &dev->cache_mgr.cache[i];
        if (ce->object == obj) {
            ce->dirty   = 0;
            ce->n_bytes = 0;
            ce->object  = NULL;
        }
    }
}

void tfs_cache_invalidate_chunk(tfs_dev_t *dev, tfs_obj_t *obj,
                                int chunk_id)
{
    int i;

    for (i = 0; i < dev->cache_mgr.n_caches; i++) {
        tfs_cache_entry_t *ce = &dev->cache_mgr.cache[i];
        if (ce->object == obj && ce->chunk_id == chunk_id) {
            ce->dirty   = 0;
            ce->n_bytes = 0;
            ce->object  = NULL;
            return;
        }
    }
}
