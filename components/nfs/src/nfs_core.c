/*
 * nfs_core.c — Mount, unmount, NAND scan, GC, file I/O for NFS
 *
 * This is the largest source file.  It wires together all the
 * lower-level layers (block, tnode, inode, cache, summary, checkpoint)
 * to implement:
 *
 *   - format: erase all blocks, write root/lnf/unlinked/del directories
 *   - mount:  try checkpoint restore, else scan all NAND blocks
 *   - GC:     select a dirty block, copy live chunks, erase block
 *   - file read/write: cache-first, chunk-granular I/O
 *   - object CRUD: create, delete, rename
 */

#include "nfs_core.h"
#include "nfs_block.h"
#include "nfs_tnode.h"
#include "nfs_inode.h"
#include "nfs_cache.h"
#include "nfs_summary.h"
#include "nfs_checkpoint.h"
#include "nfs_tags.h"
#include "../inc/nfs_config.h"

#include <string.h>

/*===================================================================
 *  Global device list
 *===================================================================*/

static nfs_list_t g_dev_list = { &g_dev_list, &g_dev_list };

/*===================================================================
 *  Internal helpers
 *===================================================================*/

static void init_dev_geometry(nfs_dev_t *dev)
{
    nfs_geo_t *g = &dev->param.geo;

    /* Sync inband_tags flag from geometry (geo takes precedence) */
    if (g->inband_tags)
        dev->param.inband_tags = 1;

    if (dev->param.inband_tags) {
        /*
         * Inband mode: the last sizeof(nfs_packed_tags2_t) bytes of each
         * physical page store the packed tags.  The effective user data
         * area is reduced accordingly.
         */
        dev->data_bytes_per_chunk = g->data_bytes_per_chunk
                                    - (nfs_u32)sizeof(nfs_packed_tags2_t);
    } else {
        dev->data_bytes_per_chunk = g->data_bytes_per_chunk;
    }

    dev->internal_start_block = (nfs_u32)g->start_block;
    dev->internal_end_block   = (nfs_u32)g->end_block;
    dev->block_offset         = g->start_block;
    dev->chunk_offset         = (int)(g->start_block * g->chunks_per_block);

    dev->n_free_chunks = (int)((dev->internal_end_block
                                - dev->internal_start_block + 1)
                               * g->chunks_per_block);
}

static void init_special_objects(nfs_dev_t *dev)
{
    nfs_u32 i;
    for (i = 0; i < NFS_OBJ_BUCKETS; i++) {
        nfs_list_init(&dev->obj_bucket[i].list);
        dev->obj_bucket[i].count = 0;
    }
    nfs_list_init(&dev->dirty_dirs);
}

/*===================================================================
 *  Special pseudo-directory setup
 *===================================================================*/

static nfs_obj_t *make_special_dir(nfs_dev_t *dev, nfs_u32 obj_id,
                                   const char *name, nfs_obj_t *parent)
{
    nfs_obj_t *obj = nfs_obj_create(dev, obj_id, NFS_OBJ_TYPE_DIR);
    if (!obj) return NFS_NULL;

    obj->fake = 1;
    obj->mode = NFS_S_IFDIR | 0755u;
    nfs_obj_cache_name(obj, name);

    if (parent)
        nfs_obj_add_child(parent, obj);

    nfs_obj_insert(dev, obj);
    return obj;
}

/*===================================================================
 *  Scan: process one chunk found during mount scan
 *===================================================================*/

static void scan_chunk(nfs_dev_t *dev, int chunk_in_nand,
                       const nfs_ext_tags_t *ext)
{
    nfs_obj_t    *obj;
    nfs_block_info_t *bi;
    int           blk = chunk_in_nand / (int)nfs_chunks_per_block(dev);

    bi = nfs_get_block_info(dev, blk);

    if (!ext->chunk_used) {
        return;  /* erased chunk */
    }

    /* Update block sequence number */
    if (ext->seq_number > bi->bi.seq_number)
        bi->bi.seq_number = ext->seq_number;

    /* Mark chunk as in-use */
    nfs_chunk_set_used(dev, chunk_in_nand);
    bi->bi.pages_in_use++;
    dev->n_free_chunks--;

    if (ext->chunk_id > 0) {
        /* Data chunk: just record presence; tnode loaded lazily */
        obj = nfs_obj_find(dev, ext->obj_id);
        if (obj && obj->obj_type == NFS_OBJ_TYPE_FILE) {
            nfs_tnode_put_chunk(dev, obj, ext->chunk_id - 1,
                                (nfs_u32)chunk_in_nand);
            obj->n_data_chunks++;
        }
    } else {
        /* Object header chunk */
        nfs_obj_hdr_t hdr;

        if (nfs_obj_read_hdr(dev, chunk_in_nand, &hdr, NFS_NULL) != NFS_OK)
            return;

        obj = nfs_obj_find(dev, ext->obj_id);

        if (!obj) {
            obj = nfs_obj_create(dev, ext->obj_id,
                                 (nfs_obj_type_t)hdr.type);
            if (!obj) return;
            nfs_obj_insert(dev, obj);
        }

        /* Always prefer the header with the higher seq_number */
        if ((int)ext->seq_number >= obj->hdr_chunk) {
            nfs_obj_load_hdr(dev, obj, &hdr, ext, chunk_in_nand);
            obj->valid = 1;
        } else {
            /* Older duplicate — delete */
            nfs_chunk_delete(dev, chunk_in_nand, 0);
        }
    }
}

/*===================================================================
 *  Full NAND scan
 *===================================================================*/

static int full_scan(nfs_dev_t *dev)
{
    int          blk, chunk;
    int          cpb = (int)nfs_chunks_per_block(dev);
    nfs_ext_tags_t ext;

    for (blk = (int)dev->internal_start_block;
         blk <= (int)dev->internal_end_block;
         blk++) {

        nfs_block_info_t *bi = nfs_get_block_info(dev, blk);

        /* Skip known-bad blocks */
        if (dev->drv.check_bad && dev->drv.check_bad(dev->drv.ctx, blk)) {
            bi->bi.block_state = NFS_BLK_STATE_DEAD;
            continue;
        }

        /* Try reading block summary first */
        if (!dev->param.disable_summary) {
            nfs_summary_tags_t *stags = dev->sum_tags;
            int n = 0;
            if (nfs_summary_read(dev, blk, stags, &n) == NFS_OK) {
                int i;
                bi->bi.block_state = NFS_BLK_STATE_FULL;
                bi->bi.has_summary = 1;
                for (i = 0; i < n; i++) {
                    nfs_ext_tags_t se;
                    memset(&se, 0, sizeof(se));
                    se.chunk_used = (stags[i].obj_id != 0xffffffff);
                    if (se.chunk_used) {
                        se.obj_id   = stags[i].obj_id;
                        se.chunk_id = stags[i].chunk_id;
                        se.n_bytes  = stags[i].n_bytes;
                        scan_chunk(dev, blk * cpb + i, &se);
                    }
                }
                continue;
            }
        }

        /* No summary: scan each chunk individually */
        for (chunk = blk * cpb; chunk < blk * cpb + cpb; chunk++) {
            memset(&ext, 0, sizeof(ext));
            nfs_chunk_read(dev, chunk, NFS_NULL, 0, &ext);
            scan_chunk(dev, chunk, &ext);
        }

        /* Determine block state */
        if (bi->bi.pages_in_use == 0) {
            bi->bi.block_state = NFS_BLK_STATE_EMPTY;
            dev->n_erased_blocks++;
        } else if (bi->bi.pages_in_use >= cpb)
            bi->bi.block_state = NFS_BLK_STATE_FULL;
        else
            bi->bi.block_state = NFS_BLK_STATE_ALLOCATING;
    }

    return NFS_OK;
}

/*===================================================================
 *  Post-scan: wire parent links
 *===================================================================*/

static void wire_parents(nfs_dev_t *dev)
{
    nfs_u32    i;
    nfs_obj_t *obj;

    for (i = 0; i < NFS_OBJ_BUCKETS; i++) {
        nfs_list_for_each_entry(obj, &dev->obj_bucket[i].list, hash_link) {
            if (obj->fake || obj->parent)
                continue;

            nfs_obj_hdr_t hdr;
            if (nfs_obj_read_hdr(dev, obj->hdr_chunk, &hdr, NFS_NULL) != NFS_OK)
                continue;

            /* Populate name and other fields from the on-NAND header.
             * After checkpoint restore, these aren't in the saved record. */
            nfs_obj_load_hdr(dev, obj, &hdr, NFS_NULL, obj->hdr_chunk);

            nfs_obj_t *parent = nfs_obj_find(dev, hdr.parent_obj_id);
            if (parent && parent->obj_type == NFS_OBJ_TYPE_DIR)
                nfs_obj_add_child(parent, obj);
            else
                nfs_obj_add_child(dev->lost_n_found, obj);
        }
    }
}

/*===================================================================
 *  Post-checkpoint: rebuild tnodes and chunk_bits from NAND
 *
 *  The checkpoint saves object metadata but NOT the tnode trees
 *  (chunk_id → NAND address mappings) or chunk_bits.  After a
 *  successful checkpoint restore, scan only the non-empty blocks to
 *  rebuild these in-RAM structures cheaply.
 *===================================================================*/

static void rebuild_tnodes_after_checkpt(nfs_dev_t *dev)
{
    int            blk, chunk;
    int            cpb  = (int)nfs_chunks_per_block(dev);
    nfs_ext_tags_t ext;

    for (blk = (int)dev->internal_start_block;
         blk <= (int)dev->internal_end_block;
         blk++) {

        nfs_block_info_t *bi    = nfs_get_block_info(dev, blk);
        int               state = bi->bi.block_state;

        /* Skip blocks that hold no file data */
        if (state == NFS_BLK_STATE_EMPTY     ||
            state == NFS_BLK_STATE_CHECKPOINT ||
            state == NFS_BLK_STATE_DEAD)
            continue;

        for (chunk = blk * cpb; chunk < (blk + 1) * cpb; chunk++) {
            memset(&ext, 0, sizeof(ext));
            nfs_chunk_read(dev, chunk, NFS_NULL, 0, &ext);

            if (!ext.chunk_used)
                continue;

            /* Rebuild chunk_bits (checkpoint doesn't save them) */
            if (!nfs_chunk_is_used(dev, chunk))
                nfs_chunk_set_used(dev, chunk);

            if (ext.chunk_id > 0) {
                /* Data chunk: rebuild tnode mapping */
                nfs_obj_t *obj = nfs_obj_find(dev, ext.obj_id);
                if (obj && obj->obj_type == NFS_OBJ_TYPE_FILE)
                    nfs_tnode_put_chunk(dev, obj, ext.chunk_id - 1,
                                        (nfs_u32)chunk);
            }
        }
    }
}



int nfs_core_add_device(nfs_dev_t *dev)
{
    nfs_list_init(&dev->dev_list);
    nfs_list_add_tail(&g_dev_list, &dev->dev_list);
    return NFS_OK;
}

void nfs_core_remove_device(nfs_dev_t *dev)
{
    nfs_list_del(&dev->dev_list);
    nfs_list_init(&dev->dev_list);
}

nfs_dev_t *nfs_core_find_dev(const char *name)
{
    nfs_dev_t *dev;
    nfs_list_for_each_entry(dev, &g_dev_list, dev_list) {
        if (strcmp(dev->param.name, name) == 0)
            return dev;
    }
    return NFS_NULL;
}

/*===================================================================
 *  Format
 *===================================================================*/

int nfs_core_format(nfs_dev_t *dev)
{
    int blk;

    init_dev_geometry(dev);

    if (nfs_block_init_arrays(dev) != NFS_OK)
        return NFS_ENOMEM;

    if (dev->drv.init)
        dev->drv.init(dev->drv.ctx);

    /* Erase all non-bad blocks (skip if already blank) */
    for (blk = (int)dev->internal_start_block;
         blk <= (int)dev->internal_end_block;
         blk++) {

        if (dev->drv.check_bad && dev->drv.check_bad(dev->drv.ctx, blk)) {
            nfs_block_set_state(dev, blk, NFS_BLK_STATE_DEAD);
            continue;
        }

        if (!dev->param.always_check_erased && dev->inband_buf) {
            /*
             * Fast path: read the first page of the block.
             * If it is all 0xFF the block is already erased — skip erase.
             */
            nfs_u32 phys_sz    = dev->param.geo.data_bytes_per_chunk;
            nfs_u32 first_chunk = (nfs_u32)blk
                                  * dev->param.geo.chunks_per_block;
            nfs_u32 i;
            int     maybe_blank = 1;

            dev->drv.read_page(dev->drv.ctx, first_chunk,
                               dev->inband_buf, phys_sz, NFS_NULL, 0);
            for (i = 0; i < phys_sz; i++) {
                if (dev->inband_buf[i] != 0xff) {
                    maybe_blank = 0;
                    break;
                }
            }
            if (maybe_blank) {
                nfs_block_set_state(dev, blk, NFS_BLK_STATE_EMPTY);
                dev->n_erased_blocks++;
                continue;
            }
        }

        nfs_block_erase(dev, blk);
    }

    dev->alloc_block        = -1;
    dev->alloc_page         = 0;
    dev->alloc_block_finder = (int)dev->internal_start_block;
    dev->seq_number         = NFS_SEQ_LOWEST;
    dev->bucket_finder      = NFS_OBJ_ID_FIRST_USER;

    init_special_objects(dev);
    if (nfs_tnode_init(dev)    != NFS_OK) goto fail;
    if (nfs_cache_init(dev)    != NFS_OK) goto fail;
    if (nfs_summary_init(dev)  != NFS_OK) goto fail;

    /* Create root and special directories */
    dev->root_dir      = make_special_dir(dev, NFS_OBJ_ID_ROOT,        ".",        NFS_NULL);
    dev->lost_n_found  = make_special_dir(dev, NFS_OBJ_ID_LOSTNFOUND,  "lost+found", dev->root_dir);
    dev->unlinked_dir  = make_special_dir(dev, NFS_OBJ_ID_UNLINKED,    ".unlinked",  NFS_NULL);
    dev->del_dir       = make_special_dir(dev, NFS_OBJ_ID_DEL,         ".deleted",   NFS_NULL);

    if (!dev->root_dir || !dev->lost_n_found)
        goto fail;

    /* Write initial headers */
    nfs_obj_update_hdr(dev, dev->root_dir);
    nfs_obj_update_hdr(dev, dev->lost_n_found);

    dev->is_mounted = 1;
    return NFS_OK;

fail:
    nfs_block_free_arrays(dev);
    return NFS_ENOMEM;
}

/*===================================================================
 *  Mount
 *===================================================================*/

int nfs_core_mount(nfs_dev_t *dev)
{
    int rc;

    init_dev_geometry(dev);
    init_special_objects(dev);

    rc = nfs_block_init_arrays(dev);
    if (rc != NFS_OK) return rc;

    if (dev->drv.init)
        dev->drv.init(dev->drv.ctx);

    rc = nfs_tnode_init(dev);
    if (rc != NFS_OK) goto fail;

    rc = nfs_cache_init(dev);
    if (rc != NFS_OK) goto fail;

    rc = nfs_summary_init(dev);
    if (rc != NFS_OK) goto fail;

    dev->alloc_block        = -1;
    dev->alloc_page         = 0;
    dev->alloc_block_finder = (int)dev->internal_start_block;
    dev->bucket_finder      = NFS_OBJ_ID_FIRST_USER;

    /* Try checkpoint restore */
    rc = nfs_checkpt_read(dev);
    if (rc != NFS_OK) {
        /* Fall back to full scan */
        rc = full_scan(dev);
        if (rc != NFS_OK) goto fail;
    } else {
        /* Checkpoint doesn't store tnodes or chunk_bits; rebuild them */
        rebuild_tnodes_after_checkpt(dev);
    }

    /* Resolve special objects first — wire_parents needs them in the hash table */
    dev->root_dir      = nfs_obj_find(dev, NFS_OBJ_ID_ROOT);
    dev->lost_n_found  = nfs_obj_find(dev, NFS_OBJ_ID_LOSTNFOUND);
    dev->unlinked_dir  = nfs_obj_find(dev, NFS_OBJ_ID_UNLINKED);
    dev->del_dir       = nfs_obj_find(dev, NFS_OBJ_ID_DEL);

    if (!dev->root_dir)
        dev->root_dir = make_special_dir(dev, NFS_OBJ_ID_ROOT, ".", NFS_NULL);
    if (!dev->lost_n_found)
        dev->lost_n_found = make_special_dir(dev, NFS_OBJ_ID_LOSTNFOUND,
                                             "lost+found", dev->root_dir);
    if (!dev->unlinked_dir)
        dev->unlinked_dir = make_special_dir(dev, NFS_OBJ_ID_UNLINKED,
                                             ".unlinked", NFS_NULL);
    if (!dev->del_dir)
        dev->del_dir = make_special_dir(dev, NFS_OBJ_ID_DEL,
                                        ".deleted", NFS_NULL);

    /* Wire up parent links (root_dir now in hash table) */
    wire_parents(dev);

    dev->is_mounted = 1;
    return NFS_OK;

fail:
    nfs_cache_deinit(dev);
    nfs_summary_deinit(dev);
    nfs_block_free_arrays(dev);
    return rc;
}

/*===================================================================
 *  Sync
 *===================================================================*/

int nfs_core_sync(nfs_dev_t *dev)
{
    int rc;

    rc = nfs_cache_flush_all(dev);
    if (rc != NFS_OK) return rc;

    if (!dev->param.skip_checkpt_wr) {
        rc = nfs_checkpt_write(dev);
    }

    return rc;
}

/*===================================================================
 *  Unmount
 *===================================================================*/

int nfs_core_unmount(nfs_dev_t *dev)
{
    nfs_u32 i;

    if (!dev->is_mounted)
        return NFS_OK;

    nfs_core_sync(dev);

    /* Free all objects */
    for (i = 0; i < NFS_OBJ_BUCKETS; i++) {
        nfs_obj_t *obj, *tmp;
        nfs_list_for_each_entry_safe(obj, tmp,
                                     &dev->obj_bucket[i].list, hash_link) {
            nfs_obj_remove(dev, obj);
            nfs_obj_free(dev, obj);
        }
    }

    nfs_cache_deinit(dev);
    nfs_summary_deinit(dev);
    nfs_tnode_deinit(dev);
    nfs_block_free_arrays(dev);

    if (dev->checkpt_buffer) {
        dev->drv.free(dev->drv.ctx, dev->checkpt_buffer);
        dev->checkpt_buffer = NFS_NULL;
    }

    if (dev->drv.deinit)
        dev->drv.deinit(dev->drv.ctx);

    dev->is_mounted = 0;
    return NFS_OK;
}

/*===================================================================
 *  GC — select candidate block
 *===================================================================*/

static int gc_find_candidate(nfs_dev_t *dev, int aggressive)
{
    int   blk, best = -1;
    int   most_dirty = -1;

    for (blk = (int)dev->internal_start_block;
         blk <= (int)dev->internal_end_block;
         blk++) {

        nfs_block_info_t *bi = nfs_get_block_info(dev, blk);

        if (bi->bi.block_state != NFS_BLK_STATE_FULL &&
            bi->bi.block_state != NFS_BLK_STATE_ALLOCATING)
            continue;

        if (bi->bi.gc_prioritise) {
            best = blk;
            break;
        }

        int dirty = (int)bi->bi.soft_del_pages;
        if (aggressive)
            dirty += (int)nfs_chunks_per_block(dev)
                     - (int)bi->bi.pages_in_use;

        if (dirty > most_dirty) {
            most_dirty = dirty;
            best = blk;
        }
    }

    return best;
}

/*===================================================================
 *  GC — copy live chunks from a block
 *===================================================================*/

static int gc_copy_block(nfs_dev_t *dev, int blk)
{
    int   cpb   = (int)nfs_chunks_per_block(dev);
    int   chunk, rc;
    nfs_u8 *buf;

    buf = (nfs_u8 *)dev->drv.malloc(dev->drv.ctx, dev->data_bytes_per_chunk);
    if (!buf) return NFS_ENOMEM;

    for (chunk = blk * cpb; chunk < blk * cpb + cpb; chunk++) {
        nfs_ext_tags_t ext;

        if (!nfs_chunk_is_used(dev, chunk))
            continue;

        memset(&ext, 0, sizeof(ext));
        rc = nfs_chunk_read(dev, chunk, buf,
                            (int)dev->data_bytes_per_chunk, &ext);
        if (rc != NFS_OK || !ext.chunk_used) {
            nfs_chunk_set_free(dev, chunk);
            continue;
        }

        /* Write live chunk to new location */
        {
            int new_chunk = nfs_alloc_chunk(dev, 0);
            if (new_chunk < 0) {
                dev->drv.free(dev->drv.ctx, buf);
                return NFS_ENOSPC;
            }

            rc = nfs_chunk_write(dev, new_chunk, buf, (int)ext.n_bytes, &ext);
            if (rc != NFS_OK) {
                dev->drv.free(dev->drv.ctx, buf);
                return rc;
            }

            /* Update tnode if this is a data chunk */
            if (ext.chunk_id > 0) {
                nfs_obj_t *obj = nfs_obj_find(dev, ext.obj_id);
                if (obj && obj->obj_type == NFS_OBJ_TYPE_FILE)
                    nfs_tnode_put_chunk(dev, obj, ext.chunk_id - 1,
                                        (nfs_u32)new_chunk);
            } else {
                /* Header chunk: update hdr_chunk pointer */
                nfs_obj_t *obj = nfs_obj_find(dev, ext.obj_id);
                if (obj)
                    obj->hdr_chunk = new_chunk;
            }

            nfs_chunk_delete(dev, chunk, 0);
            dev->n_gc_copies++;
        }
    }

    dev->drv.free(dev->drv.ctx, buf);
    return NFS_OK;
}

/*===================================================================
 *  nfs_gc
 *===================================================================*/

int nfs_gc(nfs_dev_t *dev, int aggressive)
{
    int blk, rc;

    if (dev->gc_disable)
        return NFS_OK;

    blk = gc_find_candidate(dev, aggressive);
    if (blk < 0)
        return NFS_OK;  /* nothing to collect */

    rc = gc_copy_block(dev, blk);
    if (rc != NFS_OK)
        return rc;

    rc = nfs_block_erase(dev, blk);
    if (rc != NFS_OK)
        return rc;

    dev->n_gc_blocks++;
    return NFS_OK;
}

int nfs_gc_enough_space(nfs_dev_t *dev)
{
    return dev->n_free_chunks > NFS_CFG_RESERVED_BLOCKS
                                * (int)nfs_chunks_per_block(dev);
}

/*===================================================================
 *  File read / write
 *===================================================================*/

int nfs_file_read(nfs_dev_t *dev, nfs_obj_t *obj,
                  nfs_u8 *buf, nfs_off_t offset, int n_bytes)
{
    int  chunk_sz  = (int)dev->data_bytes_per_chunk;
    int  copied    = 0;
    nfs_off_t pos  = offset;

    while (copied < n_bytes) {
        nfs_u32  chunk_id    = (nfs_u32)(pos / chunk_sz);
        int      chunk_off   = (int)(pos % chunk_sz);
        int      to_copy     = chunk_sz - chunk_off;
        int      chunk_in_nand;

        if (copied + to_copy > n_bytes)
            to_copy = n_bytes - copied;

        if (pos >= obj->var.file.file_size)
            break;

        if (to_copy > (int)(obj->var.file.file_size - pos))
            to_copy = (int)(obj->var.file.file_size - pos);

        /* Check write cache first */
        {
            nfs_cache_entry_t *ce = nfs_cache_find(dev, obj, (int)chunk_id);
            if (ce) {
                int avail = ce->n_bytes - chunk_off;
                if (avail <= 0) {
                    memset(buf + copied, 0, (size_t)to_copy);
                } else {
                    if (to_copy > avail) to_copy = avail;
                    memcpy(buf + copied,
                           ce->data + chunk_off, (size_t)to_copy);
                }
                copied += to_copy;
                pos    += to_copy;
                continue;
            }
        }

        chunk_in_nand = (int)nfs_tnode_get_chunk(dev, obj, chunk_id);
        if (chunk_in_nand == 0) {
            /* Hole in file */
            memset(buf + copied, 0, (size_t)to_copy);
        } else {
            nfs_u8 *tmp = (nfs_u8 *)dev->drv.malloc(dev->drv.ctx,
                                                     (nfs_u32)chunk_sz);
            if (!tmp) return NFS_ENOMEM;

            nfs_chunk_read(dev, chunk_in_nand, tmp, chunk_sz, NFS_NULL);
            memcpy(buf + copied, tmp + chunk_off, (size_t)to_copy);
            dev->drv.free(dev->drv.ctx, tmp);
        }

        copied += to_copy;
        pos    += to_copy;
    }

    return copied;
}

int nfs_file_write(nfs_dev_t *dev, nfs_obj_t *obj,
                   const nfs_u8 *buf, nfs_off_t offset, int n_bytes)
{
    int      chunk_sz = (int)dev->data_bytes_per_chunk;
    int      written  = 0;
    nfs_off_t pos     = offset;

    while (written < n_bytes) {
        nfs_u32  chunk_id  = (nfs_u32)(pos / chunk_sz);
        int      chunk_off = (int)(pos % chunk_sz);
        int      to_write  = chunk_sz - chunk_off;

        if (written + to_write > n_bytes)
            to_write = n_bytes - written;

        /* Get or create a cache entry */
        nfs_cache_entry_t *ce = nfs_cache_get(dev, obj, (int)chunk_id);
        if (!ce) {
            /* Cache full — flush then retry */
            int rc = nfs_cache_flush_all(dev);
            if (rc != NFS_OK) return rc;

            ce = nfs_cache_get(dev, obj, (int)chunk_id);
            if (!ce) return NFS_ENOMEM;
        }

        /* Seed cache entry from NAND if partial write */
        if (ce->n_bytes == 0 && chunk_off > 0) {
            int cinn = (int)nfs_tnode_get_chunk(dev, obj, chunk_id);
            if (cinn > 0) {
                nfs_chunk_read(dev, cinn, ce->data, chunk_sz, NFS_NULL);
                ce->n_bytes = chunk_sz;
            } else {
                memset(ce->data, 0xff, (size_t)chunk_sz);
                ce->n_bytes = chunk_sz;
            }
        }

        memcpy(ce->data + chunk_off, buf + written, (size_t)to_write);
        int new_end = chunk_off + to_write;
        if (new_end > ce->n_bytes)
            ce->n_bytes = new_end;
        ce->dirty = 1;

        written += to_write;
        pos     += to_write;
    }

    /* Update file size */
    if (offset + n_bytes > obj->var.file.file_size)
        obj->var.file.file_size = offset + n_bytes;

    if (offset + n_bytes > obj->var.file.stored_size)
        obj->var.file.stored_size = offset + n_bytes;

    obj->dirty = 1;
    return written;
}

int nfs_file_flush(nfs_dev_t *dev, nfs_obj_t *obj)
{
    int rc = nfs_cache_flush_obj(dev, obj);
    if (rc != NFS_OK) return rc;

    if (obj->dirty) {
        rc = nfs_obj_update_hdr(dev, obj);
        obj->dirty = 0;
    }

    return rc;
}

int nfs_file_resize(nfs_dev_t *dev, nfs_obj_t *obj, nfs_off_t new_size)
{
    if (new_size < obj->var.file.file_size) {
        nfs_cache_flush_obj(dev, obj);
        nfs_tnode_shrink_worker(dev, obj, new_size, 0);
        obj->var.file.file_size   = new_size;
        obj->var.file.stored_size = new_size;
    } else {
        obj->var.file.file_size = new_size;
    }

    obj->dirty = 1;
    return nfs_obj_update_hdr(dev, obj);
}

/*===================================================================
 *  Object creation / deletion / rename
 *===================================================================*/

nfs_obj_t *nfs_create_obj(nfs_dev_t *dev, nfs_obj_t *parent,
                          const char *name, nfs_u32 mode,
                          nfs_obj_type_t type)
{
    nfs_obj_t *obj;
    nfs_u32    obj_id;
    int        rc;

    if (!dev->is_mounted || !parent)
        return NFS_NULL;

    if (nfs_obj_find_by_name(dev, parent, name))
        return NFS_NULL;  /* already exists */

    obj_id = nfs_obj_new_id(dev);
    if (!obj_id) return NFS_NULL;

    obj = nfs_obj_create(dev, obj_id, type);
    if (!obj) return NFS_NULL;

    obj->mode = mode;
    if (dev->drv.get_time)
        obj->atime = obj->mtime = obj->ctime = dev->drv.get_time();

    nfs_obj_cache_name(obj, name);
    nfs_obj_add_child(parent, obj);
    nfs_obj_insert(dev, obj);

    rc = nfs_obj_update_hdr(dev, obj);
    if (rc != NFS_OK) {
        nfs_obj_remove_child(parent, obj);
        nfs_obj_remove(dev, obj);
        nfs_obj_free(dev, obj);
        return NFS_NULL;
    }

    /* Mark parent dirty */
    parent->dirty = 1;
    nfs_obj_update_hdr(dev, parent);

    return obj;
}

int nfs_unlink_obj(nfs_dev_t *dev, nfs_obj_t *obj)
{
    nfs_obj_t *parent = obj->parent;

    if (!obj || !dev->is_mounted)
        return NFS_EINVAL;

    if (obj->obj_type == NFS_OBJ_TYPE_DIR) {
        /* Directory must be empty */
        if (!nfs_list_empty(&obj->var.dir.children))
            return NFS_ENOTEMPTY;
    }

    /* Move to deleted dir */
    if (parent) nfs_obj_remove_child(parent, obj);
    nfs_obj_add_child(dev->del_dir, obj);

    obj->unlinked = 1;
    obj->dirty    = 1;

    /* Delete all data chunks for files */
    if (obj->obj_type == NFS_OBJ_TYPE_FILE) {
        nfs_cache_invalidate_obj(dev, obj);
        nfs_tnode_del_file_chunks(dev, obj, -1);
    }

    /* Delete header */
    if (obj->hdr_chunk > 0) {
        nfs_chunk_delete(dev, obj->hdr_chunk, 1);
        obj->hdr_chunk = 0;
    }

    nfs_obj_remove(dev, obj);
    nfs_obj_free(dev, obj);

    if (parent) {
        parent->dirty = 1;
        nfs_obj_update_hdr(dev, parent);
    }

    dev->n_deleted_files++;
    return NFS_OK;
}

int nfs_rename_obj(nfs_dev_t *dev, nfs_obj_t *obj,
                   nfs_obj_t *new_parent, const char *new_name)
{
    nfs_obj_t *old_parent = obj->parent;

    if (!obj || !new_parent || !dev->is_mounted)
        return NFS_EINVAL;

    /* Check new name doesn't already exist */
    if (nfs_obj_find_by_name(dev, new_parent, new_name))
        return NFS_EEXIST;

    if (old_parent) nfs_obj_remove_child(old_parent, obj);
    nfs_obj_add_child(new_parent, obj);
    nfs_obj_cache_name(obj, new_name);

    obj->dirty = 1;
    nfs_obj_update_hdr(dev, obj);

    if (old_parent) {
        old_parent->dirty = 1;
        nfs_obj_update_hdr(dev, old_parent);
    }
    if (new_parent != old_parent) {
        new_parent->dirty = 1;
        nfs_obj_update_hdr(dev, new_parent);
    }

    return NFS_OK;
}

nfs_obj_t *nfs_create_symlink(nfs_dev_t *dev, nfs_obj_t *parent,
                              const char *name, nfs_u32 mode,
                              const char *alias)
{
    nfs_obj_t *obj = nfs_create_obj(dev, parent, name, mode,
                                    NFS_OBJ_TYPE_SYMLINK);
    if (!obj) return NFS_NULL;

    size_t len = strlen(alias) + 1;
    obj->var.symlink.alias = (char *)dev->drv.malloc(dev->drv.ctx, len);
    if (!obj->var.symlink.alias) {
        nfs_unlink_obj(dev, obj);
        return NFS_NULL;
    }
    memcpy(obj->var.symlink.alias, alias, len);
    obj->dirty = 1;
    nfs_obj_update_hdr(dev, obj);
    return obj;
}

nfs_obj_t *nfs_create_hardlink(nfs_dev_t *dev, nfs_obj_t *parent,
                               const char *name, nfs_obj_t *equiv)
{
    nfs_obj_t *obj;
    nfs_u32    obj_id;

    obj_id = nfs_obj_new_id(dev);
    if (!obj_id) return NFS_NULL;

    obj = nfs_obj_create(dev, obj_id, NFS_OBJ_TYPE_HARDLINK);
    if (!obj) return NFS_NULL;

    obj->var.hardlink.equiv_obj = equiv;
    obj->var.hardlink.equiv_id  = equiv->obj_id;
    obj->mode = equiv->mode;

    nfs_obj_cache_name(obj, name);
    nfs_obj_add_child(parent, obj);
    nfs_obj_insert(dev, obj);

    nfs_list_add_tail(&equiv->hard_links, &obj->siblings);

    nfs_obj_update_hdr(dev, obj);
    return obj;
}

/*===================================================================
 *  Path lookup
 *===================================================================*/

nfs_obj_t *nfs_core_find_by_name(nfs_dev_t *dev, nfs_obj_t *dir,
                                  const char *name)
{
    return nfs_obj_find_by_name(dev, dir, name);
}

/*===================================================================
 *  Statistics
 *===================================================================*/

nfs_off_t nfs_core_free_space(const nfs_dev_t *dev)
{
    return (nfs_off_t)dev->n_free_chunks * dev->data_bytes_per_chunk;
}

nfs_off_t nfs_core_total_space(const nfs_dev_t *dev)
{
    return (nfs_off_t)nfs_total_blocks(dev)
           * nfs_chunks_per_block(dev)
           * dev->data_bytes_per_chunk;
}
