/*
 * nfs_cache.c — Write cache for NFS
 *
 * Simple LRU write cache backed by a flat array of nfs_cache_entry_t.
 * Each entry owns a chunk-sized data buffer allocated at init time.
 * Dirty entries are written to NAND on flush; clean entries are
 * silently discarded when evicted.
 */

#include "nfs_cache.h"
#include "nfs_block.h"
#include "nfs_tnode.h"
#include "../inc/nfs_config.h"

#include <string.h>

/*===================================================================
 *  Init / deinit
 *===================================================================*/

int nfs_cache_init(nfs_dev_t *dev)
{
    int  i;
    int  n       = NFS_CFG_N_CACHES;
    int  chunk_sz = (int)dev->data_bytes_per_chunk;

    dev->cache_mgr.n_caches      = n;
    dev->cache_mgr.cache_last_use= 0;

    dev->cache_mgr.cache = (nfs_cache_entry_t *)
        dev->drv.malloc(dev->drv.ctx, (nfs_u32)n * sizeof(nfs_cache_entry_t));
    if (!dev->cache_mgr.cache)
        return NFS_ENOMEM;

    memset(dev->cache_mgr.cache, 0, (size_t)n * sizeof(nfs_cache_entry_t));

    for (i = 0; i < n; i++) {
        dev->cache_mgr.cache[i].data =
            (nfs_u8 *)dev->drv.malloc(dev->drv.ctx, (nfs_u32)chunk_sz);
        if (!dev->cache_mgr.cache[i].data) {
            /* Free what we already allocated */
            int j;
            for (j = 0; j < i; j++)
                dev->drv.free(dev->drv.ctx, dev->cache_mgr.cache[j].data);
            dev->drv.free(dev->drv.ctx, dev->cache_mgr.cache);
            dev->cache_mgr.cache = NFS_NULL;
            return NFS_ENOMEM;
        }
    }

    return NFS_OK;
}

void nfs_cache_deinit(nfs_dev_t *dev)
{
    int i;

    if (!dev->cache_mgr.cache)
        return;

    for (i = 0; i < dev->cache_mgr.n_caches; i++) {
        if (dev->cache_mgr.cache[i].data) {
            dev->drv.free(dev->drv.ctx, dev->cache_mgr.cache[i].data);
            dev->cache_mgr.cache[i].data = NFS_NULL;
        }
    }

    dev->drv.free(dev->drv.ctx, dev->cache_mgr.cache);
    dev->cache_mgr.cache   = NFS_NULL;
    dev->cache_mgr.n_caches= 0;
}

/*===================================================================
 *  Lookup
 *===================================================================*/

nfs_cache_entry_t *nfs_cache_find(nfs_dev_t *dev,
                                  nfs_obj_t *obj,
                                  int chunk_id)
{
    int i;

    for (i = 0; i < dev->cache_mgr.n_caches; i++) {
        nfs_cache_entry_t *ce = &dev->cache_mgr.cache[i];
        if (ce->object == obj && ce->chunk_id == chunk_id && ce->n_bytes > 0)
            return ce;
    }
    return NFS_NULL;
}

/*===================================================================
 *  Internal: flush one dirty entry
 *===================================================================*/

static int flush_one(nfs_dev_t *dev, nfs_cache_entry_t *ce)
{
    nfs_ext_tags_t ext;
    int            chunk_in_nand;
    int            rc;

    if (!ce->dirty || !ce->object)
        return NFS_OK;

    memset(&ext, 0, sizeof(ext));
    ext.chunk_used = 1;
    ext.obj_id     = ce->object->obj_id;
    ext.chunk_id   = (nfs_u32)(ce->chunk_id + 1); /* 1-indexed: 0 is reserved for obj header */
    ext.n_bytes    = (nfs_u32)ce->n_bytes;

    chunk_in_nand = nfs_alloc_chunk(dev, 0);
    if (chunk_in_nand < 0)
        return NFS_ENOSPC;

    rc = nfs_chunk_write(dev, chunk_in_nand, ce->data, ce->n_bytes, &ext);
    if (rc != NFS_OK)
        return rc;

    /* Update the tnode for this chunk */
    rc = nfs_tnode_put_chunk(dev, ce->object,
                             (nfs_u32)ce->chunk_id,
                             (nfs_u32)chunk_in_nand);
    if (rc != NFS_OK)
        return rc;

    ce->dirty = 0;
    return NFS_OK;
}

/*===================================================================
 *  Allocate / evict
 *===================================================================*/

nfs_cache_entry_t *nfs_cache_get(nfs_dev_t *dev,
                                  nfs_obj_t *obj,
                                  int chunk_id)
{
    int                i;
    nfs_cache_entry_t *found   = NFS_NULL;
    nfs_cache_entry_t *lru     = NFS_NULL;
    int                lru_use = dev->cache_mgr.cache_last_use + 1;

    /* Try exact match first */
    for (i = 0; i < dev->cache_mgr.n_caches; i++) {
        nfs_cache_entry_t *ce = &dev->cache_mgr.cache[i];
        if (ce->object == obj && ce->chunk_id == chunk_id) {
            found = ce;
            break;
        }
    }

    if (!found) {
        /* Find LRU clean entry to evict */
        for (i = 0; i < dev->cache_mgr.n_caches; i++) {
            nfs_cache_entry_t *ce = &dev->cache_mgr.cache[i];
            if (!ce->locked && !ce->dirty) {
                if (ce->last_use < lru_use) {
                    lru_use = ce->last_use;
                    lru     = ce;
                }
            }
        }

        if (!lru)
            return NFS_NULL;   /* all slots dirty/locked */

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

int nfs_cache_flush_obj(nfs_dev_t *dev, nfs_obj_t *obj)
{
    int i, rc;

    for (i = 0; i < dev->cache_mgr.n_caches; i++) {
        nfs_cache_entry_t *ce = &dev->cache_mgr.cache[i];
        if (ce->object == obj && ce->dirty) {
            rc = flush_one(dev, ce);
            if (rc != NFS_OK)
                return rc;
        }
    }
    return NFS_OK;
}

int nfs_cache_flush_all(nfs_dev_t *dev)
{
    int i, rc;

    for (i = 0; i < dev->cache_mgr.n_caches; i++) {
        nfs_cache_entry_t *ce = &dev->cache_mgr.cache[i];
        if (ce->dirty) {
            rc = flush_one(dev, ce);
            if (rc != NFS_OK)
                return rc;
        }
    }
    return NFS_OK;
}

/*===================================================================
 *  Invalidate
 *===================================================================*/

void nfs_cache_invalidate_obj(nfs_dev_t *dev, nfs_obj_t *obj)
{
    int i;

    for (i = 0; i < dev->cache_mgr.n_caches; i++) {
        nfs_cache_entry_t *ce = &dev->cache_mgr.cache[i];
        if (ce->object == obj) {
            ce->dirty   = 0;
            ce->n_bytes = 0;
            ce->object  = NFS_NULL;
        }
    }
}

void nfs_cache_invalidate_chunk(nfs_dev_t *dev, nfs_obj_t *obj,
                                int chunk_id)
{
    int i;

    for (i = 0; i < dev->cache_mgr.n_caches; i++) {
        nfs_cache_entry_t *ce = &dev->cache_mgr.cache[i];
        if (ce->object == obj && ce->chunk_id == chunk_id) {
            ce->dirty   = 0;
            ce->n_bytes = 0;
            ce->object  = NFS_NULL;
            return;
        }
    }
}
