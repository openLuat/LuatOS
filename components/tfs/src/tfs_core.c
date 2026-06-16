/*
 * tfs_core.c — Mount, unmount, NAND scan, GC, file I/O for TFS
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

#include "tfs_core.h"
#include "tfs_block.h"
#include "tfs_tnode.h"
#include "tfs_inode.h"
#include "tfs_cache.h"
#include "tfs_summary.h"
#include "tfs_checkpoint.h"
#include "tfs_tags.h"
#include "../inc/tfs_config.h"

#include <string.h>

/*===================================================================
 *  Global device list
 *===================================================================*/

static tfs_list_t g_dev_list = { &g_dev_list, &g_dev_list };

/*===================================================================
 *  Internal helpers
 *===================================================================*/

static void init_dev_geometry(tfs_dev_t *dev)
{
    tfs_geo_t *g = &dev->param.geo;

    /* Sync inband_tags flag from geometry (geo takes precedence) */
    if (g->inband_tags)
        dev->param.inband_tags = 1;

    if (dev->param.inband_tags) {
        /*
         * Inband mode: the last sizeof(tfs_packed_tags2_t) bytes of each
         * physical page store the packed tags.  The effective user data
         * area is reduced accordingly.
         */
        dev->data_bytes_per_chunk = g->data_bytes_per_chunk
                                    - (uint32_t)sizeof(tfs_packed_tags2_t);
    } else {
        dev->data_bytes_per_chunk = g->data_bytes_per_chunk;
    }

    dev->internal_start_block = (uint32_t)g->start_block;
    dev->internal_end_block   = (uint32_t)g->end_block;
    dev->block_offset         = g->start_block;
    dev->chunk_offset         = (int)(g->start_block * g->chunks_per_block);

    dev->n_free_chunks = (int)((dev->internal_end_block
                                - dev->internal_start_block + 1)
                               * g->chunks_per_block);
}

static void reset_runtime_state(tfs_dev_t *dev)
{
    dev->is_checkpointed = 0;
    dev->checkpt_has_tnodes = 0;
    dev->swap_endian = 0;

    dev->block_info = NULL;
    dev->chunk_bits = NULL;
    dev->chunk_bit_stride = 0;
    dev->n_erased_blocks = 0;
    dev->alloc_block = -1;
    dev->alloc_page = 0;
    dev->alloc_block_finder = 0;

    dev->allocator = NULL;
    dev->n_obj = 0;
    dev->n_tnodes = 0;
    dev->n_hardlinks = 0;
    dev->bucket_finder = TFS_OBJ_ID_FIRST_USER;
    dev->n_free_chunks = 0;

    dev->gc_cleanup_list = NULL;
    dev->n_clean_ups = 0;
    dev->has_pending_prioritised_gc = 0;
    dev->gc_disable = 0;
    dev->gc_block_finder = 0;
    dev->gc_dirtiest = 0;
    dev->gc_pages_in_use = 0;
    dev->gc_not_done = 0;
    dev->gc_block = 0;
    dev->gc_chunk = 0;
    dev->gc_skip = 0;
    dev->gc_sum_tags = NULL;

    dev->root_dir = NULL;
    dev->lost_n_found = NULL;
    dev->unlinked_dir = NULL;
    dev->del_dir = NULL;
    dev->unlinked_deletion = NULL;
    dev->n_deleted_files = 0;
    dev->n_unlinked_files = 0;
    dev->n_bg_deletions = 0;

    memset(&dev->cache_mgr, 0, sizeof(dev->cache_mgr));
    memset(dev->temp_buffer, 0, sizeof(dev->temp_buffer));
    dev->max_temp = 0;
    dev->temp_in_use = 0;

    dev->seq_number = TFS_SEQ_LOWEST;
    dev->oldest_dirty_seq = 0;
    dev->oldest_dirty_block = 0;
    dev->refresh_skip = 0;

    tfs_list_init(&dev->dirty_dirs);

    dev->chunks_per_summary = 0;
    dev->sum_tags = NULL;

    dev->checkpt_page_seq = 0;
    dev->checkpt_byte_count = 0;
    dev->checkpt_byte_offs = 0;
    dev->checkpt_buffer = NULL;
    dev->checkpt_open_write = 0;
    dev->blocks_in_checkpt = 0;
    dev->checkpt_cur_chunk = -1;
    dev->checkpt_cur_block = -1;
    dev->checkpt_next_block = 0;
    dev->checkpt_block_list = NULL;
    dev->checkpt_max_blocks = 0;
    dev->checkpt_sum = 0;
    dev->checkpt_xor = 0;
    dev->checkpoint_blocks_required = 0;
    dev->checkpt_max_seq = 0;
    dev->checkpt_base_seq = 0;
    dev->checkpt_base_alloc_block = -1;
    dev->checkpt_base_alloc_page = 0;
    dev->checkpt_delta_chunks = 0;

    dev->tn_swap_buffer = NULL;
    dev->inband_buf = NULL;
}

static void init_special_objects(tfs_dev_t *dev)
{
    uint32_t i;
    for (i = 0; i < TFS_OBJ_BUCKETS; i++) {
        tfs_list_init(&dev->obj_bucket[i].list);
        dev->obj_bucket[i].count = 0;
    }
    tfs_list_init(&dev->dirty_dirs);
}

static void free_object_table(tfs_dev_t *dev)
{
    uint32_t i;

    for (i = 0; i < TFS_OBJ_BUCKETS; i++) {
        tfs_obj_t *obj, *tmp;

        tfs_list_for_each_entry_safe(obj, tmp,
                                     &dev->obj_bucket[i].list, hash_link) {
            tfs_obj_remove(dev, obj);
            tfs_obj_free(dev, obj);
        }
    }
}

static void free_checkpoint_runtime(tfs_dev_t *dev)
{
    if (dev->checkpt_buffer) {
        dev->drv.free(dev->drv.ctx, dev->checkpt_buffer);
        dev->checkpt_buffer = NULL;
    }
    if (dev->checkpt_block_list) {
        dev->drv.free(dev->drv.ctx, dev->checkpt_block_list);
        dev->checkpt_block_list = NULL;
        dev->checkpt_max_blocks = 0;
        dev->blocks_in_checkpt = 0;
    }
}

static int mount_reset_for_full_scan(tfs_dev_t *dev)
{
    int rc;

    free_object_table(dev);
    tfs_cache_deinit(dev);
    tfs_summary_deinit(dev);
    tfs_tnode_deinit(dev);
    tfs_block_free_arrays(dev);
    free_checkpoint_runtime(dev);

    reset_runtime_state(dev);
    init_dev_geometry(dev);
    init_special_objects(dev);

    rc = tfs_block_init_arrays(dev);
    if (rc != TFS_OK)
        return rc;

    rc = tfs_tnode_init(dev);
    if (rc != TFS_OK)
        goto fail;

    rc = tfs_cache_init(dev);
    if (rc != TFS_OK)
        goto fail;

    rc = tfs_summary_init(dev);
    if (rc != TFS_OK)
        goto fail;

    dev->alloc_block        = -1;
    dev->alloc_page         = 0;
    dev->alloc_block_finder = (int)dev->internal_start_block;
    dev->bucket_finder      = TFS_OBJ_ID_FIRST_USER;

    return TFS_OK;

fail:
    tfs_cache_deinit(dev);
    tfs_summary_deinit(dev);
    tfs_tnode_deinit(dev);
    tfs_block_free_arrays(dev);
    free_checkpoint_runtime(dev);
    return rc;
}

/*===================================================================
 *  Special pseudo-directory setup
 *===================================================================*/

static tfs_obj_t *make_special_dir(tfs_dev_t *dev, uint32_t obj_id,
                                   const char *name, tfs_obj_t *parent)
{
    tfs_obj_t *obj = tfs_obj_create(dev, obj_id, TFS_OBJ_TYPE_DIR);
    if (!obj) return NULL;

    obj->fake = 1;
    obj->mode = TFS_S_IFDIR | 0755u;
    tfs_obj_cache_name(obj, name);

    if (parent)
        tfs_obj_add_child(parent, obj);

    tfs_obj_insert(dev, obj);
    return obj;
}

static int valid_obj_type(uint32_t type)
{
    return type == TFS_OBJ_TYPE_FILE ||
           type == TFS_OBJ_TYPE_SYMLINK ||
           type == TFS_OBJ_TYPE_DIR ||
           type == TFS_OBJ_TYPE_HARDLINK ||
           type == TFS_OBJ_TYPE_SPECIAL;
}

static int valid_obj_id(uint32_t obj_id)
{
    if (obj_id == TFS_OBJ_ID_ROOT ||
        obj_id == TFS_OBJ_ID_LOSTNFOUND ||
        obj_id == TFS_OBJ_ID_UNLINKED ||
        obj_id == TFS_OBJ_ID_DEL)
        return 1;

    return obj_id >= TFS_OBJ_ID_FIRST_USER && obj_id < TFS_MAX_OBJ_ID;
}

static int tags_usable_for_scan(tfs_dev_t *dev, const tfs_ext_tags_t *ext)
{
    uint32_t max_chunks = tfs_total_blocks(dev) * tfs_chunks_per_block(dev);

    if (!ext->chunk_used)
        return 1;

    if (ext->ecc_result == TFS_ECC_RESULT_UNFIXED)
        return 0;

    if (ext->obj_id == TFS_OBJ_ID_CHECKPT ||
        ext->obj_id == TFS_OBJ_ID_SUMMARY)
        return 1;

    if (!valid_obj_id(ext->obj_id))
        return 0;

    if (ext->chunk_id > 0) {
        if (ext->chunk_id > max_chunks)
            return 0;
        if (ext->n_bytes > dev->data_bytes_per_chunk)
            return 0;
    } else if (ext->n_bytes != 0xffffu &&
               ext->n_bytes > dev->data_bytes_per_chunk) {
        return 0;
    }

    if (ext->extra_available && !valid_obj_type(ext->extra_obj_type))
        return 0;

    return 1;
}

static int bounded_has_nul(const char *s, uint32_t n)
{
    return memchr(s, 0, n) != NULL;
}

static int obj_hdr_usable_for_scan(tfs_dev_t *dev,
                                   const tfs_obj_hdr_t *hdr)
{
    uint32_t max_chunks = tfs_total_blocks(dev) * tfs_chunks_per_block(dev);
    tfs_off_t max_file_size = (tfs_off_t)max_chunks *
                              (tfs_off_t)dev->data_bytes_per_chunk;

    if (!valid_obj_type(hdr->type))
        return 0;

    if (!bounded_has_nul(hdr->name, TFS_MAX_NAME_LEN + 1u))
        return 0;

    if (hdr->type == TFS_OBJ_TYPE_SYMLINK &&
        !bounded_has_nul(hdr->alias, TFS_MAX_ALIAS_LEN + 1u))
        return 0;

    if (hdr->type == TFS_OBJ_TYPE_FILE) {
        tfs_off_t sz = ((tfs_off_t)hdr->file_size_high << 32) |
                       (tfs_off_t)hdr->file_size_low;
        if (sz < 0 || sz > max_file_size)
            return 0;
    }

    return 1;
}

static void scan_note_dirty_chunk(tfs_dev_t *dev, int chunk_in_nand,
                                  const tfs_ext_tags_t *ext)
{
    tfs_block_info_t *bi;
    int blk = chunk_in_nand / (int)tfs_chunks_per_block(dev);

    bi = tfs_get_block_info(dev, blk);
    if (ext && ext->seq_number > bi->bi.seq_number)
        bi->bi.seq_number = ext->seq_number;

    tfs_chunk_set_used(dev, chunk_in_nand);
    bi->bi.pages_in_use++;
    dev->n_free_chunks--;
    tfs_chunk_delete(dev, chunk_in_nand, 0);
}

static int data_chunk_prefer_new(tfs_dev_t *dev, int new_chunk,
                                 const tfs_ext_tags_t *new_ext,
                                 uint32_t old_chunk)
{
    tfs_ext_tags_t old_ext;
    tfs_ext_tags_t actual_new_ext;
    const tfs_ext_tags_t *ne = new_ext;

    if (old_chunk == 0)
        return 1;

    if (!ne || ne->seq_number == 0) {
        memset(&actual_new_ext, 0, sizeof(actual_new_ext));
        if (tfs_chunk_read(dev, new_chunk, NULL, 0, &actual_new_ext) != TFS_OK)
            return 0;
        ne = &actual_new_ext;
    }

    memset(&old_ext, 0, sizeof(old_ext));
    if (tfs_chunk_read(dev, (int)old_chunk, NULL, 0, &old_ext) != TFS_OK)
        return 1;
    if (!old_ext.chunk_used)
        return 1;

    if (ne->seq_number != old_ext.seq_number)
        return ne->seq_number > old_ext.seq_number;

    return (uint32_t)new_chunk > old_chunk;
}

static int file_chunk_live_for_scan(tfs_dev_t *dev, tfs_obj_t *obj,
                                    uint32_t chunk_id)
{
    tfs_off_t n_chunks;

    if (!obj || obj->obj_type != TFS_OBJ_TYPE_FILE ||
        obj->var.file.stored_size <= 0)
        return 0;

    n_chunks = (obj->var.file.stored_size +
                (tfs_off_t)dev->data_bytes_per_chunk - 1) /
               (tfs_off_t)dev->data_bytes_per_chunk;

    return (tfs_off_t)chunk_id < n_chunks;
}

static void scan_restore_live_chunk(tfs_dev_t *dev, int chunk_in_nand)
{
    tfs_block_info_t *bi;
    int blk;

    if (tfs_chunk_is_used(dev, chunk_in_nand))
        return;

    blk = chunk_in_nand / (int)tfs_chunks_per_block(dev);
    bi = tfs_get_block_info(dev, blk);

    tfs_chunk_set_used(dev, chunk_in_nand);
    if (bi->bi.soft_del_pages > 0) {
        bi->bi.soft_del_pages--;
        if (dev->n_free_chunks > 0)
            dev->n_free_chunks--;
    }
}

/*===================================================================
 *  Scan: process one chunk found during mount scan
 *===================================================================*/

static void scan_chunk(tfs_dev_t *dev, int chunk_in_nand,
                       const tfs_ext_tags_t *ext)
{
    tfs_obj_t    *obj;
    tfs_block_info_t *bi;
    int           blk = chunk_in_nand / (int)tfs_chunks_per_block(dev);

    bi = tfs_get_block_info(dev, blk);

    if (!ext->chunk_used) {
        return;  /* erased chunk */
    }

    if (!tags_usable_for_scan(dev, ext)) {
        scan_note_dirty_chunk(dev, chunk_in_nand, ext);
        return;
    }

    /* Update block sequence number */
    if (ext->seq_number > bi->bi.seq_number)
        bi->bi.seq_number = ext->seq_number;

    /* Mark chunk as in-use */
    tfs_chunk_set_used(dev, chunk_in_nand);
    bi->bi.pages_in_use++;
    dev->n_free_chunks--;

    if (ext->obj_id == TFS_OBJ_ID_CHECKPT) {
        /*
         * Legacy checkpoints were allocated through the normal chunk
         * allocator and may share a block with live user data.  During a full
         * scan the checkpoint is stale by definition, so treat only this page
         * as garbage and let GC reclaim the containing block when it is safe.
         */
        bi->bi.gc_prioritise = 1;
        tfs_chunk_delete(dev, chunk_in_nand, 0);
        return;
    }

    if (ext->obj_id == TFS_OBJ_ID_SUMMARY) {
        return;
    }

    if (ext->chunk_id > 0) {
        /* Data chunk: just record presence; tnode loaded lazily */
        obj = tfs_obj_find(dev, ext->obj_id);
        if (obj && obj->obj_type == TFS_OBJ_TYPE_FILE) {
            uint32_t chunk_id = ext->chunk_id - 1;
            uint32_t old_chunk = tfs_tnode_get_chunk(dev, obj, chunk_id);

            if (!file_chunk_live_for_scan(dev, obj, chunk_id)) {
                tfs_chunk_delete(dev, chunk_in_nand, 0);
            } else if (data_chunk_prefer_new(dev, chunk_in_nand, ext,
                                             old_chunk)) {
                if (tfs_tnode_put_chunk(dev, obj, chunk_id,
                                        (uint32_t)chunk_in_nand) == TFS_OK) {
                    if (old_chunk > 0 && old_chunk != (uint32_t)chunk_in_nand)
                        tfs_chunk_delete(dev, (int)old_chunk, 0);
                    else if (old_chunk == 0)
                        obj->n_data_chunks++;
                }
            } else {
                tfs_chunk_delete(dev, chunk_in_nand, 0);
            }
        }
    } else {
        /* Object header chunk */
        tfs_obj_hdr_t hdr;
        int prefer_new = 1;
        int hdr_rc;

        hdr_rc = tfs_obj_read_hdr(dev, chunk_in_nand, &hdr, NULL);
        if (hdr_rc != TFS_OK)
            return;
        if (!obj_hdr_usable_for_scan(dev, &hdr))
            return;

        obj = tfs_obj_find(dev, ext->obj_id);
        if (obj && obj->valid && obj->obj_type != hdr.type)
            return;

        if (!obj) {
            obj = tfs_obj_create(dev, ext->obj_id,
                                 (tfs_obj_type_t)hdr.type);
            if (!obj) return;
            tfs_obj_insert(dev, obj);
        }

        if (obj->hdr_chunk > 0) {
            tfs_ext_tags_t old_ext;
            memset(&old_ext, 0, sizeof(old_ext));
            if (tfs_obj_read_hdr(dev, obj->hdr_chunk, NULL, &old_ext) == TFS_OK) {
                prefer_new = (ext->seq_number > old_ext.seq_number) ||
                             (ext->seq_number == old_ext.seq_number &&
                              chunk_in_nand > obj->hdr_chunk);
            }
        }

        if (prefer_new) {
            int old_hdr = obj->hdr_chunk;
            tfs_obj_load_hdr(dev, obj, &hdr, ext, chunk_in_nand);
            obj->valid = 1;
            if (old_hdr > 0 && old_hdr != chunk_in_nand)
                tfs_chunk_delete(dev, old_hdr, 0);
        } else {
            /* Older duplicate — delete */
            tfs_chunk_delete(dev, chunk_in_nand, 0);
        }
    }
}

static void scan_account_delta_chunk(tfs_dev_t *dev, int chunk_in_nand,
                                     const tfs_ext_tags_t *ext)
{
    tfs_block_info_t *bi;
    int blk = chunk_in_nand / (int)tfs_chunks_per_block(dev);

    bi = tfs_get_block_info(dev, blk);
    if (ext && ext->seq_number > bi->bi.seq_number)
        bi->bi.seq_number = ext->seq_number;

    if (!tfs_chunk_is_used(dev, chunk_in_nand)) {
        tfs_chunk_set_used(dev, chunk_in_nand);
        bi->bi.pages_in_use++;
        if (dev->n_free_chunks > 0)
            dev->n_free_chunks--;
        dev->checkpt_delta_chunks++;
    }
}

static void scan_delta_header_pass(tfs_dev_t *dev, int chunk_in_nand,
                                   const tfs_ext_tags_t *ext)
{
    tfs_obj_t *obj;
    tfs_block_info_t *bi;
    int blk = chunk_in_nand / (int)tfs_chunks_per_block(dev);

    bi = tfs_get_block_info(dev, blk);

    if (!ext->chunk_used)
        return;

    if (!tags_usable_for_scan(dev, ext)) {
        scan_note_dirty_chunk(dev, chunk_in_nand, ext);
        dev->checkpt_delta_chunks++;
        return;
    }

    scan_account_delta_chunk(dev, chunk_in_nand, ext);

    if (ext->obj_id == TFS_OBJ_ID_CHECKPT) {
        bi->bi.gc_prioritise = 1;
        tfs_chunk_delete(dev, chunk_in_nand, 0);
        return;
    }

    if (ext->obj_id == TFS_OBJ_ID_SUMMARY)
        return;

    if (ext->chunk_id > 0)
        return;

    {
        tfs_obj_hdr_t hdr;
        int prefer_new = 1;
        int hdr_rc;

        hdr_rc = tfs_obj_read_hdr(dev, chunk_in_nand, &hdr, NULL);
        if (hdr_rc != TFS_OK)
            return;
        if (!obj_hdr_usable_for_scan(dev, &hdr))
            return;

        obj = tfs_obj_find(dev, ext->obj_id);
        if (obj && obj->valid && obj->obj_type != hdr.type)
            return;

        if (!obj) {
            obj = tfs_obj_create(dev, ext->obj_id,
                                 (tfs_obj_type_t)hdr.type);
            if (!obj)
                return;
            tfs_obj_insert(dev, obj);
        }

        if (obj->hdr_chunk > 0) {
            tfs_ext_tags_t old_ext;
            memset(&old_ext, 0, sizeof(old_ext));
            if (tfs_obj_read_hdr(dev, obj->hdr_chunk, NULL, &old_ext) == TFS_OK) {
                prefer_new = (ext->seq_number > old_ext.seq_number) ||
                             (ext->seq_number == old_ext.seq_number &&
                              chunk_in_nand > obj->hdr_chunk);
            }
        }

        if (prefer_new) {
            int old_hdr = obj->hdr_chunk;
            tfs_obj_load_hdr(dev, obj, &hdr, ext, chunk_in_nand);
            obj->valid = 1;
            if (old_hdr > 0 && old_hdr != chunk_in_nand)
                tfs_chunk_delete(dev, old_hdr, 0);
        } else {
            tfs_chunk_delete(dev, chunk_in_nand, 0);
        }
    }
}

static void scan_delta_data_pass(tfs_dev_t *dev, int chunk_in_nand,
                                 const tfs_ext_tags_t *ext)
{
    tfs_obj_t *obj;

    if (!ext->chunk_used ||
        !tags_usable_for_scan(dev, ext) ||
        ext->chunk_id == 0 ||
        ext->obj_id == TFS_OBJ_ID_CHECKPT ||
        ext->obj_id == TFS_OBJ_ID_SUMMARY) {
        return;
    }

    obj = tfs_obj_find(dev, ext->obj_id);
    if (obj && obj->obj_type == TFS_OBJ_TYPE_FILE) {
        uint32_t chunk_id = ext->chunk_id - 1;
        uint32_t old_chunk = tfs_tnode_get_chunk(dev, obj, chunk_id);

        if (!file_chunk_live_for_scan(dev, obj, chunk_id)) {
            if (tfs_chunk_is_used(dev, chunk_in_nand))
                tfs_chunk_delete(dev, chunk_in_nand, 0);
        } else if (data_chunk_prefer_new(dev, chunk_in_nand, ext,
                                         old_chunk)) {
            if (tfs_tnode_put_chunk(dev, obj, chunk_id,
                                    (uint32_t)chunk_in_nand) == TFS_OK) {
                if (old_chunk > 0 && old_chunk != (uint32_t)chunk_in_nand)
                    tfs_chunk_delete(dev, (int)old_chunk, 0);
                else if (old_chunk == 0)
                    obj->n_data_chunks++;
            }
        } else {
            if (tfs_chunk_is_used(dev, chunk_in_nand))
                tfs_chunk_delete(dev, chunk_in_nand, 0);
        }
    } else if (tfs_chunk_is_used(dev, chunk_in_nand)) {
        tfs_chunk_delete(dev, chunk_in_nand, 0);
    }
}

static void scan_mark_block_unusable(tfs_dev_t *dev, int blk, int persist)
{
    int cpb = (int)tfs_chunks_per_block(dev);
    int page;
    tfs_block_info_t *bi = tfs_get_block_info(dev, blk);
    int already_dead = (bi->bi.block_state == TFS_BLK_STATE_DEAD);

    if ((int)bi->bi.pages_in_use < cpb) {
        int free_in_block = cpb - (int)bi->bi.pages_in_use;
        dev->n_free_chunks -= free_in_block;
        if (dev->n_free_chunks < 0)
            dev->n_free_chunks = 0;
    }

    if (persist && !already_dead)
        tfs_block_mark_bad(dev, blk);
    else
        bi->bi.block_state = TFS_BLK_STATE_DEAD;

    bi->bi.pages_in_use = cpb;
    bi->bi.soft_del_pages = 0;
    bi->bi.needs_retiring = 1;
    bi->bi.has_summary = 0;

    for (page = 0; page < cpb; page++)
        tfs_chunk_set_used(dev, blk * cpb + page);
}

static void scan_finish_delta_block(tfs_dev_t *dev, int blk)
{
    int cpb = (int)tfs_chunks_per_block(dev);
    tfs_block_info_t *bi = tfs_get_block_info(dev, blk);

    if (bi->bi.block_state == TFS_BLK_STATE_DEAD ||
        bi->bi.block_state == TFS_BLK_STATE_CHECKPOINT) {
        return;
    }

    if (bi->bi.pages_in_use == 0) {
        bi->bi.block_state = TFS_BLK_STATE_EMPTY;
    } else if (bi->bi.pages_in_use >= cpb) {
        bi->bi.block_state = TFS_BLK_STATE_FULL;
    } else {
        bi->bi.block_state = TFS_BLK_STATE_ALLOCATING;
    }
}

static int scan_delta_probe_block(tfs_dev_t *dev, int blk,
                                  uint16_t *scan_from)
{
    int cpb = (int)tfs_chunks_per_block(dev);
    int first_page = (blk == 0) ? 1 : 0;
    int idx = blk - (int)dev->internal_start_block;
    tfs_block_info_t *bi = tfs_get_block_info(dev, blk);
    tfs_ext_tags_t ext;
    int probe_chunk;
    int rc;

    if (bi->bi.block_state == TFS_BLK_STATE_DEAD ||
        bi->bi.block_state == TFS_BLK_STATE_CHECKPOINT) {
        return TFS_OK;
    }

    if (blk == dev->checkpt_base_alloc_block &&
        dev->checkpt_base_alloc_page < (uint32_t)cpb) {
        scan_from[idx] = (uint16_t)dev->checkpt_base_alloc_page;
        return TFS_OK;
    }

    probe_chunk = blk * cpb + first_page;
    memset(&ext, 0, sizeof(ext));
    rc = tfs_chunk_read(dev, probe_chunk, NULL, 0, &ext);
    if (rc != TFS_OK) {
        scan_mark_block_unusable(dev, blk, 1);
        return TFS_OK;
    }

    if (!ext.chunk_used)
        return TFS_OK;

    if (bi->bi.block_state == TFS_BLK_STATE_EMPTY) {
        if (dev->n_erased_blocks > 0)
            dev->n_erased_blocks--;
        scan_from[idx] = (uint16_t)first_page;
        return TFS_OK;
    }

    if (ext.seq_number >= dev->checkpt_base_seq) {
        scan_from[idx] = (uint16_t)first_page;
    }

    return TFS_OK;
}

static int scan_delta_pass(tfs_dev_t *dev, uint16_t *scan_from, int data_pass)
{
    int blk, page;
    int cpb = (int)tfs_chunks_per_block(dev);

    for (blk = (int)dev->internal_start_block;
         blk <= (int)dev->internal_end_block;
         blk++) {
        int idx = blk - (int)dev->internal_start_block;
        int start = scan_from[idx];

        if (start == 0xffff)
            continue;

        for (page = start; page < cpb; page++) {
            int chunk = blk * cpb + page;
            tfs_ext_tags_t ext;
            int rc;

            memset(&ext, 0, sizeof(ext));
            rc = tfs_chunk_read(dev, chunk, NULL, 0, &ext);
            if (rc != TFS_OK) {
                scan_mark_block_unusable(dev, blk, 1);
                break;
            }
            if (!ext.chunk_used)
                break;

            if (data_pass)
                scan_delta_data_pass(dev, chunk, &ext);
            else
                scan_delta_header_pass(dev, chunk, &ext);
        }

        if (!data_pass)
            scan_finish_delta_block(dev, blk);
    }

    return TFS_OK;
}

static int scan_delta_after_checkpt(tfs_dev_t *dev)
{
    uint32_t n_blocks;
    uint16_t *scan_from;
    int blk;
    int rc = TFS_OK;

    if (dev->checkpt_base_seq == 0)
        return TFS_OK;

    n_blocks = dev->internal_end_block - dev->internal_start_block + 1;
    scan_from = (uint16_t *)dev->drv.malloc(dev->drv.ctx,
                                            n_blocks * sizeof(uint16_t));
    if (!scan_from)
        return TFS_ENOMEM;
    memset(scan_from, 0xff, n_blocks * sizeof(uint16_t));

    for (blk = (int)dev->internal_start_block;
         blk <= (int)dev->internal_end_block;
         blk++) {
        rc = scan_delta_probe_block(dev, blk, scan_from);
        if (rc != TFS_OK)
            goto out;
    }

    rc = scan_delta_pass(dev, scan_from, 0);
    if (rc != TFS_OK)
        goto out;

    rc = scan_delta_pass(dev, scan_from, 1);
    if (rc != TFS_OK)
        goto out;

    if (dev->checkpt_delta_chunks > 0)
        dev->is_checkpointed = 0;

out:
    dev->drv.free(dev->drv.ctx, scan_from);
    return rc;
}

/*===================================================================
 *  Full NAND scan
 *===================================================================*/

static void rebuild_tnodes_after_checkpt(tfs_dev_t *dev);

static int full_scan(tfs_dev_t *dev)
{
    int          blk, chunk;
    int          cpb = (int)tfs_chunks_per_block(dev);
    uint32_t     max_seq = TFS_SEQ_LOWEST;
    tfs_ext_tags_t ext;

    for (blk = (int)dev->internal_start_block;
         blk <= (int)dev->internal_end_block;
         blk++) {

        tfs_block_info_t *bi = tfs_get_block_info(dev, blk);

        /* Skip known-bad blocks */
        if (dev->drv.check_bad && dev->drv.check_bad(dev->drv.ctx, blk)) {
            scan_mark_block_unusable(dev, blk, 0);
            continue;
        }

        /* Try reading block summary first */
        if (!dev->param.disable_summary) {
            tfs_summary_tags_t *stags = dev->sum_tags;
            int n = 0;
            if (tfs_summary_read(dev, blk, stags, &n) == TFS_OK) {
                int i;
                bi->bi.block_state = TFS_BLK_STATE_FULL;
                bi->bi.has_summary = 1;
                for (i = 0; i < n; i++) {
                    tfs_ext_tags_t se;
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
            int rc;

            memset(&ext, 0, sizeof(ext));
            rc = tfs_chunk_read(dev, chunk, NULL, 0, &ext);
            if (rc != TFS_OK) {
                scan_mark_block_unusable(dev, blk, 1);
                break;
            }
            scan_chunk(dev, chunk, &ext);
        }

        if (bi->bi.block_state == TFS_BLK_STATE_DEAD)
            continue;

        /* Determine block state */
        if (bi->bi.pages_in_use == 0) {
            bi->bi.block_state = TFS_BLK_STATE_EMPTY;
            dev->n_erased_blocks++;
        } else if (bi->bi.pages_in_use >= cpb)
            bi->bi.block_state = TFS_BLK_STATE_FULL;
        else
            bi->bi.block_state = TFS_BLK_STATE_ALLOCATING;

        if (bi->bi.seq_number > max_seq)
            max_seq = bi->bi.seq_number;
    }

    dev->seq_number = max_seq + 1;
    if (dev->seq_number < TFS_SEQ_LOWEST)
        dev->seq_number = TFS_SEQ_LOWEST;

    rebuild_tnodes_after_checkpt(dev);

    return TFS_OK;
}

/*===================================================================
 *  Post-scan: wire parent links
 *===================================================================*/

static void wire_parents(tfs_dev_t *dev)
{
    uint32_t    i;
    tfs_obj_t *obj;

    for (i = 0; i < TFS_OBJ_BUCKETS; i++) {
        tfs_list_for_each_entry(obj, &dev->obj_bucket[i].list, hash_link) {
            uint32_t parent_id = obj->checkpt_parent_id;
            tfs_obj_t *parent;
            tfs_obj_hdr_t hdr;
            int have_hdr;

            if (obj->fake || obj->parent)
                continue;

            have_hdr = (tfs_obj_read_hdr(dev, obj->hdr_chunk,
                                         &hdr, NULL) == TFS_OK);

            /* Populate name and other fields from the on-NAND header.
             * Checkpoint v7 also stores name/parent so a valid checkpoint can
             * still wire paths if the header page is no longer readable. */
            if (have_hdr) {
                parent_id = hdr.parent_obj_id;
                tfs_obj_load_hdr(dev, obj, &hdr, NULL, obj->hdr_chunk);
            } else if (!tfs_obj_get_name(dev, obj)) {
                continue;
            }

            parent = tfs_obj_find(dev, parent_id);
            if (parent && parent->obj_type == TFS_OBJ_TYPE_DIR)
                tfs_obj_add_child(parent, obj);
            else
                tfs_obj_add_child(dev->lost_n_found, obj);
        }
    }
}

/*===================================================================
 *  Post-checkpoint: rebuild tnodes and chunk_bits from NAND
 *
 *  Old/incomplete checkpoints may not restore tnode trees
 *  (chunk_id -> NAND address mappings) or chunk_bits directly.
 *  Keep this as a safety fallback.
 *===================================================================*/

static void rebuild_tnodes_after_checkpt(tfs_dev_t *dev)
{
    int            blk, chunk;
    int            cpb  = (int)tfs_chunks_per_block(dev);
    uint32_t       i;
    tfs_obj_t     *obj;
    tfs_ext_tags_t ext;

    for (i = 0; i < TFS_OBJ_BUCKETS; i++) {
        tfs_list_for_each_entry(obj, &dev->obj_bucket[i].list, hash_link) {
            if (obj->obj_type != TFS_OBJ_TYPE_FILE)
                continue;
            tfs_tnode_free_tree(dev, obj->var.file.top,
                                obj->var.file.top_level);
            obj->var.file.top = NULL;
            obj->var.file.top_level = 0;
            obj->n_data_chunks = 0;
        }
    }

    for (blk = (int)dev->internal_start_block;
         blk <= (int)dev->internal_end_block;
         blk++) {

        tfs_block_info_t *bi    = tfs_get_block_info(dev, blk);
        int               state = bi->bi.block_state;

        /* Skip blocks that hold no file data */
        if (state == TFS_BLK_STATE_EMPTY     ||
            state == TFS_BLK_STATE_CHECKPOINT ||
            state == TFS_BLK_STATE_DEAD)
            continue;

        for (chunk = blk * cpb; chunk < (blk + 1) * cpb; chunk++) {
            int rc;

            memset(&ext, 0, sizeof(ext));
            rc = tfs_chunk_read(dev, chunk, NULL, 0, &ext);
            if (rc != TFS_OK) {
                scan_mark_block_unusable(dev, blk, 1);
                break;
            }

            if (!ext.chunk_used)
                continue;

            if (ext.chunk_id > 0) {
                /* Data chunk: rebuild tnode mapping */
                obj = tfs_obj_find(dev, ext.obj_id);
                if (obj && obj->obj_type == TFS_OBJ_TYPE_FILE) {
                    uint32_t chunk_id = ext.chunk_id - 1;
                    uint32_t old_chunk;

                    if (!file_chunk_live_for_scan(dev, obj, chunk_id)) {
                        if (tfs_chunk_is_used(dev, chunk))
                            tfs_chunk_delete(dev, chunk, 0);
                        continue;
                    }

                    /*
                     * A data page can be scanned before its object header and
                     * later soft-deleted by duplicate/header ordering logic.
                     * If the newest object header says the page is still in
                     * range, restore the bitmap before rebuilding the tnode.
                     */
                    scan_restore_live_chunk(dev, chunk);

                    old_chunk = tfs_tnode_get_chunk(dev, obj, chunk_id);
                    if (data_chunk_prefer_new(dev, chunk, &ext, old_chunk)) {
                        if (tfs_tnode_put_chunk(dev, obj, chunk_id,
                                                (uint32_t)chunk) == TFS_OK) {
                            if (old_chunk > 0 &&
                                old_chunk != (uint32_t)chunk) {
                                tfs_chunk_delete(dev, (int)old_chunk, 0);
                            } else if (old_chunk == 0) {
                                obj->n_data_chunks++;
                            }
                        }
                    } else {
                        if (tfs_chunk_is_used(dev, chunk))
                            tfs_chunk_delete(dev, chunk, 0);
                    }
                }
            }
        }
    }
}



int tfs_core_add_device(tfs_dev_t *dev)
{
    tfs_list_init(&dev->dev_list);
    tfs_list_add_tail(&dev->dev_list, &g_dev_list);
    return TFS_OK;
}

void tfs_core_remove_device(tfs_dev_t *dev)
{
    tfs_list_del(&dev->dev_list);
    tfs_list_init(&dev->dev_list);
}

tfs_dev_t *tfs_core_find_dev(const char *name)
{
    tfs_dev_t *dev;
    tfs_list_for_each_entry(dev, &g_dev_list, dev_list) {
        if (strcmp(dev->param.name, name) == 0)
            return dev;
    }
    return NULL;
}

/*===================================================================
 *  Format
 *===================================================================*/

int tfs_core_format(tfs_dev_t *dev)
{
    int blk;
    int rc;

    if (dev->is_mounted) {
        rc = tfs_core_unmount(dev);
        if (rc != TFS_OK)
            return rc;
    }

    reset_runtime_state(dev);
    init_dev_geometry(dev);

    if (tfs_block_init_arrays(dev) != TFS_OK)
        return TFS_ENOMEM;

    if (dev->drv.init)
        dev->drv.init(dev->drv.ctx);

    /* Erase all non-bad blocks. A single-page blank probe is not enough for
     * NAND: later pages can still contain stale checkpoint or file data. */
    for (blk = (int)dev->internal_start_block;
         blk <= (int)dev->internal_end_block;
         blk++) {

        if (dev->drv.check_bad && dev->drv.check_bad(dev->drv.ctx, blk)) {
            scan_mark_block_unusable(dev, blk, 0);
            continue;
        }

        if (tfs_block_erase(dev, blk) != TFS_OK)
            scan_mark_block_unusable(dev, blk, 0);
    }

    dev->alloc_block        = -1;
    dev->alloc_page         = 0;
    dev->alloc_block_finder = (int)dev->internal_start_block;
    dev->seq_number         = TFS_SEQ_LOWEST;
    dev->bucket_finder      = TFS_OBJ_ID_FIRST_USER;

    init_special_objects(dev);
    if (tfs_tnode_init(dev)    != TFS_OK) goto fail;
    if (tfs_cache_init(dev)    != TFS_OK) goto fail;
    if (tfs_summary_init(dev)  != TFS_OK) goto fail;

    /* Create root and special directories */
    dev->root_dir      = make_special_dir(dev, TFS_OBJ_ID_ROOT,        ".",        NULL);
    dev->lost_n_found  = make_special_dir(dev, TFS_OBJ_ID_LOSTNFOUND,  "lost+found", dev->root_dir);
    dev->unlinked_dir  = make_special_dir(dev, TFS_OBJ_ID_UNLINKED,    ".unlinked",  NULL);
    dev->del_dir       = make_special_dir(dev, TFS_OBJ_ID_DEL,         ".deleted",   NULL);

    if (!dev->root_dir || !dev->lost_n_found)
        goto fail;

    /* Write initial headers */
    tfs_obj_update_hdr(dev, dev->root_dir);
    tfs_obj_update_hdr(dev, dev->lost_n_found);

    dev->is_mounted = 1;
    return TFS_OK;

fail:
    tfs_block_free_arrays(dev);
    return TFS_ENOMEM;
}

/*===================================================================
 *  Mount
 *===================================================================*/

int tfs_core_mount(tfs_dev_t *dev)
{
    int rc;

    reset_runtime_state(dev);
    init_dev_geometry(dev);
    init_special_objects(dev);

    rc = tfs_block_init_arrays(dev);
    if (rc != TFS_OK) return rc;

    if (dev->drv.init)
        dev->drv.init(dev->drv.ctx);

    rc = tfs_tnode_init(dev);
    if (rc != TFS_OK) goto fail;

    rc = tfs_cache_init(dev);
    if (rc != TFS_OK) goto fail;

    rc = tfs_summary_init(dev);
    if (rc != TFS_OK) goto fail;

    dev->alloc_block        = -1;
    dev->alloc_page         = 0;
    dev->alloc_block_finder = (int)dev->internal_start_block;
    dev->bucket_finder      = TFS_OBJ_ID_FIRST_USER;

    /* Try checkpoint restore */
    rc = tfs_checkpt_read(dev);
    if (rc != TFS_OK) {
        rc = mount_reset_for_full_scan(dev);
        if (rc != TFS_OK) goto fail;

        /* Fall back to full scan from a clean state. */
        rc = full_scan(dev);
        if (rc != TFS_OK) goto fail;
    } else {
        if (!dev->checkpt_has_tnodes) {
            /* Incomplete checkpoint: rebuild tnodes from NAND tags. */
            rebuild_tnodes_after_checkpt(dev);
        }
        rc = scan_delta_after_checkpt(dev);
        if (rc != TFS_OK) goto fail;
    }

    /* Resolve special objects first — wire_parents needs them in the hash table */
    dev->root_dir      = tfs_obj_find(dev, TFS_OBJ_ID_ROOT);
    dev->lost_n_found  = tfs_obj_find(dev, TFS_OBJ_ID_LOSTNFOUND);
    dev->unlinked_dir  = tfs_obj_find(dev, TFS_OBJ_ID_UNLINKED);
    dev->del_dir       = tfs_obj_find(dev, TFS_OBJ_ID_DEL);

    if (!dev->root_dir)
        dev->root_dir = make_special_dir(dev, TFS_OBJ_ID_ROOT, ".", NULL);
    if (!dev->lost_n_found)
        dev->lost_n_found = make_special_dir(dev, TFS_OBJ_ID_LOSTNFOUND,
                                             "lost+found", dev->root_dir);
    if (!dev->unlinked_dir)
        dev->unlinked_dir = make_special_dir(dev, TFS_OBJ_ID_UNLINKED,
                                             ".unlinked", NULL);
    if (!dev->del_dir)
        dev->del_dir = make_special_dir(dev, TFS_OBJ_ID_DEL,
                                        ".deleted", NULL);

    /* Wire up parent links (root_dir now in hash table) */
    wire_parents(dev);

    dev->is_mounted = 1;
    return TFS_OK;

fail:
    tfs_cache_deinit(dev);
    tfs_summary_deinit(dev);
    if (dev->checkpt_buffer) {
        dev->drv.free(dev->drv.ctx, dev->checkpt_buffer);
        dev->checkpt_buffer = NULL;
    }
    if (dev->checkpt_block_list) {
        dev->drv.free(dev->drv.ctx, dev->checkpt_block_list);
        dev->checkpt_block_list = NULL;
        dev->checkpt_max_blocks = 0;
        dev->blocks_in_checkpt = 0;
    }
    tfs_block_free_arrays(dev);
    return rc;
}

/*===================================================================
 *  Sync
 *===================================================================*/

int tfs_core_sync(tfs_dev_t *dev)
{
    int rc;

    rc = tfs_cache_flush_all(dev);
    if (rc != TFS_OK) return rc;

    if (!dev->param.skip_checkpt_wr) {
        rc = tfs_checkpt_write(dev);
    }

    return rc;
}

/*===================================================================
 *  Unmount
 *===================================================================*/

int tfs_core_unmount(tfs_dev_t *dev)
{
    uint32_t i;
    int rc;

    if (!dev->is_mounted)
        return TFS_OK;

    rc = tfs_core_sync(dev);
    if (rc != TFS_OK)
        return rc;

    /* Free all objects */
    for (i = 0; i < TFS_OBJ_BUCKETS; i++) {
        tfs_obj_t *obj, *tmp;
        tfs_list_for_each_entry_safe(obj, tmp,
                                     &dev->obj_bucket[i].list, hash_link) {
            tfs_obj_remove(dev, obj);
            tfs_obj_free(dev, obj);
        }
    }

    tfs_cache_deinit(dev);
    tfs_summary_deinit(dev);
    tfs_tnode_deinit(dev);
    tfs_block_free_arrays(dev);

    if (dev->checkpt_buffer) {
        dev->drv.free(dev->drv.ctx, dev->checkpt_buffer);
        dev->checkpt_buffer = NULL;
    }
    if (dev->checkpt_block_list) {
        dev->drv.free(dev->drv.ctx, dev->checkpt_block_list);
        dev->checkpt_block_list = NULL;
        dev->checkpt_max_blocks = 0;
        dev->blocks_in_checkpt = 0;
    }

    if (dev->drv.deinit)
        dev->drv.deinit(dev->drv.ctx);

    dev->is_mounted = 0;
    return rc;
}

/*===================================================================
 *  GC — select candidate block
 *===================================================================*/

static int gc_find_candidate(tfs_dev_t *dev, int aggressive)
{
    int   blk, best = -1;
    int   most_dirty = -1;

    for (blk = (int)dev->internal_start_block;
         blk <= (int)dev->internal_end_block;
         blk++) {

        tfs_block_info_t *bi = tfs_get_block_info(dev, blk);
        int dirty;

        if (bi->bi.block_state != TFS_BLK_STATE_FULL &&
            bi->bi.block_state != TFS_BLK_STATE_ALLOCATING)
            continue;

        if (blk == dev->alloc_block)
            continue;

        if (bi->bi.gc_prioritise) {
            best = blk;
            break;
        }

        dirty = (int)bi->bi.soft_del_pages;
        if (aggressive)
            dirty += (int)tfs_chunks_per_block(dev)
                     - (int)bi->bi.pages_in_use;

        if (dirty <= 0)
            continue;

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

static int gc_copy_block(tfs_dev_t *dev, int blk)
{
    int   cpb   = (int)tfs_chunks_per_block(dev);
    int   chunk, rc;
    uint8_t *buf;

    buf = (uint8_t *)dev->drv.malloc(dev->drv.ctx, dev->data_bytes_per_chunk);
    if (!buf) return TFS_ENOMEM;

    for (chunk = blk * cpb; chunk < blk * cpb + cpb; chunk++) {
        tfs_ext_tags_t ext;

        if (!tfs_chunk_is_used(dev, chunk))
            continue;

        memset(&ext, 0, sizeof(ext));
        rc = tfs_chunk_read(dev, chunk, buf,
                            (int)dev->data_bytes_per_chunk, &ext);
        if (rc != TFS_OK || !ext.chunk_used) {
            tfs_chunk_set_free(dev, chunk);
            continue;
        }

        /* Write live chunk to new location */
        {
            int new_chunk = tfs_alloc_chunk(dev, 1);
            if (new_chunk < 0) {
                dev->drv.free(dev->drv.ctx, buf);
                return TFS_ENOSPC;
            }

            rc = tfs_chunk_write(dev, new_chunk, buf, (int)ext.n_bytes, &ext);
            if (rc != TFS_OK) {
                dev->drv.free(dev->drv.ctx, buf);
                return rc;
            }

            /* Update tnode if this is a data chunk */
            if (ext.chunk_id > 0) {
                tfs_obj_t *obj = tfs_obj_find(dev, ext.obj_id);
                if (obj && obj->obj_type == TFS_OBJ_TYPE_FILE)
                    tfs_tnode_put_chunk(dev, obj, ext.chunk_id - 1,
                                        (uint32_t)new_chunk);
            } else {
                /* Header chunk: update hdr_chunk pointer */
                tfs_obj_t *obj = tfs_obj_find(dev, ext.obj_id);
                if (obj)
                    obj->hdr_chunk = new_chunk;
            }

            tfs_chunk_delete(dev, chunk, 0);
            dev->n_gc_copies++;
        }
    }

    dev->drv.free(dev->drv.ctx, buf);
    return TFS_OK;
}

/*===================================================================
 *  tfs_gc
 *===================================================================*/

int tfs_gc(tfs_dev_t *dev, int aggressive)
{
    int blk, rc;

    if (dev->gc_disable)
        return TFS_OK;

    blk = gc_find_candidate(dev, aggressive);
    if (blk < 0)
        return TFS_OK;  /* nothing to collect */

    rc = gc_copy_block(dev, blk);
    if (rc != TFS_OK)
        return rc;

    rc = tfs_block_erase(dev, blk);
    if (rc != TFS_OK)
        return rc;

    dev->n_gc_blocks++;
    return TFS_OK;
}

int tfs_gc_enough_space(tfs_dev_t *dev)
{
    int reserved = tfs_user_reserved_blocks(dev);

    return dev->n_erased_blocks > reserved &&
           dev->n_free_chunks > reserved * (int)tfs_chunks_per_block(dev);
}

int tfs_alloc_chunk_or_gc(tfs_dev_t *dev, int use_resvd, int *chunk_out)
{
    int chunk;
    int passes;
    int max_passes;

    if (!chunk_out)
        return TFS_EINVAL;

    chunk = tfs_alloc_chunk(dev, use_resvd);
    if (chunk >= 0) {
        *chunk_out = chunk;
        return TFS_OK;
    }

    if (use_resvd || dev->gc_disable) {
        *chunk_out = -1;
        return TFS_ENOSPC;
    }

    max_passes = (int)tfs_total_blocks(dev);
    for (passes = 0; passes < max_passes; passes++) {
        int before_erased = dev->n_erased_blocks;
        int before_free = dev->n_free_chunks;
        uint32_t before_gc = dev->n_gc_blocks;
        int rc = tfs_gc(dev, 1);

        if (rc != TFS_OK) {
            *chunk_out = -1;
            return rc;
        }

        chunk = tfs_alloc_chunk(dev, 0);
        if (chunk >= 0) {
            *chunk_out = chunk;
            return TFS_OK;
        }

        if (dev->n_erased_blocks == before_erased &&
            dev->n_free_chunks == before_free &&
            dev->n_gc_blocks == before_gc) {
            break;
        }
    }

    *chunk_out = -1;
    return TFS_ENOSPC;
}

/*===================================================================
 *  File read / write
 *===================================================================*/

int tfs_file_read(tfs_dev_t *dev, tfs_obj_t *obj,
                  uint8_t *buf, tfs_off_t offset, int n_bytes)
{
    int  chunk_sz  = (int)dev->data_bytes_per_chunk;
    int  copied    = 0;
    tfs_off_t pos  = offset;

    while (copied < n_bytes) {
        uint32_t  chunk_id    = (uint32_t)(pos / chunk_sz);
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
            tfs_cache_entry_t *ce = tfs_cache_find(dev, obj, (int)chunk_id);
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

        chunk_in_nand = (int)tfs_tnode_get_chunk(dev, obj, chunk_id);
        if (chunk_in_nand == 0) {
            /* Hole in file */
            memset(buf + copied, 0, (size_t)to_copy);
        } else {
            uint8_t *tmp = (uint8_t *)dev->drv.malloc(dev->drv.ctx,
                                                     (uint32_t)chunk_sz);
            int rc;
            if (!tmp) return TFS_ENOMEM;

            rc = tfs_chunk_read(dev, chunk_in_nand, tmp, chunk_sz, NULL);
            if (rc != TFS_OK) {
                dev->drv.free(dev->drv.ctx, tmp);
                return rc;
            }
            memcpy(buf + copied, tmp + chunk_off, (size_t)to_copy);
            dev->drv.free(dev->drv.ctx, tmp);
        }

        copied += to_copy;
        pos    += to_copy;
    }

    return copied;
}

int tfs_file_write(tfs_dev_t *dev, tfs_obj_t *obj,
                   const uint8_t *buf, tfs_off_t offset, int n_bytes)
{
    int      chunk_sz = (int)dev->data_bytes_per_chunk;
    int      written  = 0;
    tfs_off_t pos     = offset;

    while (written < n_bytes) {
        uint32_t  chunk_id  = (uint32_t)(pos / chunk_sz);
        int      chunk_off = (int)(pos % chunk_sz);
        int      to_write  = chunk_sz - chunk_off;

        if (written + to_write > n_bytes)
            to_write = n_bytes - written;

        /* Get or create a cache entry */
        tfs_cache_entry_t *ce = tfs_cache_get(dev, obj, (int)chunk_id);
        if (!ce) {
            /* Cache full — flush then retry */
            int rc = tfs_cache_flush_all(dev);
            if (rc != TFS_OK) return rc;

            ce = tfs_cache_get(dev, obj, (int)chunk_id);
            if (!ce) return TFS_ENOMEM;
        }

        /* Seed cache entry from NAND if a partial chunk may leave a hole. */
        if (ce->n_bytes == 0 && (chunk_off > 0 || to_write < chunk_sz)) {
            int cinn = (int)tfs_tnode_get_chunk(dev, obj, chunk_id);
            if (cinn > 0) {
                int rc = tfs_chunk_read(dev, cinn, ce->data, chunk_sz, NULL);
                if (rc != TFS_OK) {
                    return rc;
                }
                ce->n_bytes = chunk_sz;
            } else {
                memset(ce->data, 0, (size_t)chunk_sz);
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

int tfs_file_flush(tfs_dev_t *dev, tfs_obj_t *obj)
{
    int rc = tfs_cache_flush_obj(dev, obj);
    if (rc != TFS_OK) return rc;

    if (obj->dirty) {
        rc = tfs_obj_update_hdr(dev, obj);
        if (rc == TFS_OK)
            obj->dirty = 0;
    }

    return rc;
}

int tfs_file_resize(tfs_dev_t *dev, tfs_obj_t *obj, tfs_off_t new_size)
{
    if (new_size < obj->var.file.file_size) {
        int rc = tfs_cache_flush_obj(dev, obj);
        if (rc != TFS_OK) return rc;
        tfs_tnode_shrink_worker(dev, obj, new_size, 0);
        obj->var.file.file_size   = new_size;
        obj->var.file.stored_size = new_size;
    } else {
        obj->var.file.file_size = new_size;
    }

    obj->dirty = 1;
    return tfs_obj_update_hdr(dev, obj);
}

/*===================================================================
 *  Object creation / deletion / rename
 *===================================================================*/

tfs_obj_t *tfs_create_obj(tfs_dev_t *dev, tfs_obj_t *parent,
                          const char *name, uint32_t mode,
                          tfs_obj_type_t type)
{
    tfs_obj_t *obj;
    uint32_t    obj_id;
    int        rc;

    if (!dev->is_mounted || !parent)
        return NULL;

    if (tfs_obj_find_by_name(dev, parent, name))
        return NULL;  /* already exists */

    obj_id = tfs_obj_new_id(dev);
    if (!obj_id) return NULL;

    obj = tfs_obj_create(dev, obj_id, type);
    if (!obj) return NULL;

    obj->mode = mode;
    if (dev->drv.get_time)
        obj->atime = obj->mtime = obj->ctime = dev->drv.get_time();

    tfs_obj_cache_name(obj, name);
    tfs_obj_add_child(parent, obj);
    tfs_obj_insert(dev, obj);

    rc = tfs_obj_update_hdr(dev, obj);
    if (rc != TFS_OK) {
        tfs_obj_remove_child(parent, obj);
        tfs_obj_remove(dev, obj);
        tfs_obj_free(dev, obj);
        return NULL;
    }

    /* Mark parent dirty */
    parent->dirty = 1;
    tfs_obj_update_hdr(dev, parent);

    return obj;
}

static int tfs_obj_write_delete_marker(tfs_dev_t *dev, tfs_obj_t *obj)
{
    tfs_obj_t *old_parent;
    tfs_off_t old_file_size = 0;
    tfs_off_t old_stored_size = 0;
    int rc;

    if (!dev || !obj || !dev->del_dir)
        return TFS_EINVAL;

    old_parent = obj->parent;
    if (obj->obj_type == TFS_OBJ_TYPE_FILE) {
        old_file_size = obj->var.file.file_size;
        old_stored_size = obj->var.file.stored_size;
        obj->var.file.file_size = 0;
        obj->var.file.stored_size = 0;
    }

    obj->parent = dev->del_dir;
    obj->deleted = 1;
    obj->unlinked = 1;
    obj->dirty = 1;

    rc = tfs_obj_update_hdr(dev, obj);

    obj->parent = old_parent;
    if (rc != TFS_OK && obj->obj_type == TFS_OBJ_TYPE_FILE) {
        obj->var.file.file_size = old_file_size;
        obj->var.file.stored_size = old_stored_size;
    }

    return rc;
}

int tfs_unlink_obj(tfs_dev_t *dev, tfs_obj_t *obj)
{
    tfs_obj_t *parent = obj->parent;
    int rc;

    if (!obj || !dev->is_mounted)
        return TFS_EINVAL;

    if (obj->obj_type == TFS_OBJ_TYPE_DIR) {
        /* Directory must be empty */
        if (!tfs_list_empty(&obj->var.dir.children))
            return TFS_ENOTEMPTY;
    }

    /* Decrement hardlink ref count on the equivalent file */
    if (obj->obj_type == TFS_OBJ_TYPE_HARDLINK) {
        tfs_obj_t *equiv = obj->var.hardlink.equiv_obj;
        if (equiv && equiv->n_hard_links > 0)
            equiv->n_hard_links--;
        /* If equiv was unlinked and all hardlinks are gone, clean up data */
        if (equiv && equiv->unlinked && equiv->n_hard_links == 0) {
            tfs_cache_invalidate_obj(dev, equiv);
            tfs_tnode_del_file_chunks(dev, equiv, -1);
            if (equiv->hdr_chunk > 0) {
                tfs_chunk_delete(dev, equiv->hdr_chunk, 1);
                equiv->hdr_chunk = 0;
            }
            tfs_obj_remove(dev, equiv);
            tfs_obj_free(dev, equiv);
        }
    }

    /* For files with active hardlinks: preserve data, just mark unlinked */
    if (obj->obj_type == TFS_OBJ_TYPE_FILE && obj->n_hard_links > 0) {
        if (parent) tfs_obj_remove_child(parent, obj);
        obj->unlinked = 1;
        if (obj->hdr_chunk > 0) {
            tfs_chunk_delete(dev, obj->hdr_chunk, 1);
            obj->hdr_chunk = 0;
        }
        if (parent) {
            parent->dirty = 1;
            tfs_obj_update_hdr(dev, parent);
        }
        dev->n_deleted_files++;
        return TFS_OK;
    }

    /*
     * Persist a tombstone header before freeing old chunks.  A power loss
     * between unlink and checkpoint must not let a full scan resurrect the
     * previous object header and data pages.
     */
    rc = tfs_obj_write_delete_marker(dev, obj);
    if (rc != TFS_OK)
        return rc;

    /* Remove from parent directory */
    if (parent) tfs_obj_remove_child(parent, obj);

    /* Delete all data chunks for files */
    if (obj->obj_type == TFS_OBJ_TYPE_FILE) {
        tfs_cache_invalidate_obj(dev, obj);
        tfs_tnode_del_file_chunks(dev, obj, -1);
    }

    tfs_obj_remove(dev, obj);
    tfs_obj_free(dev, obj);

    if (parent) {
        parent->dirty = 1;
        tfs_obj_update_hdr(dev, parent);
    }

    dev->n_deleted_files++;
    return TFS_OK;
}

int tfs_rename_obj(tfs_dev_t *dev, tfs_obj_t *obj,
                   tfs_obj_t *new_parent, const char *new_name)
{
    tfs_obj_t *old_parent = obj->parent;

    if (!obj || !new_parent || !dev->is_mounted)
        return TFS_EINVAL;

    /* Atomically replace existing target (POSIX rename semantics) */
    {
        tfs_obj_t *existing = tfs_obj_find_by_name(dev, new_parent, new_name);
        if (existing && existing != obj) {
            if (existing->obj_type == TFS_OBJ_TYPE_DIR)
                return TFS_EISDIR;
            (void)tfs_unlink_obj(dev, existing);
        } else if (existing == obj) {
            return TFS_OK; /* rename to itself is a no-op */
        }
    }

    if (old_parent) tfs_obj_remove_child(old_parent, obj);
    tfs_obj_add_child(new_parent, obj);
    tfs_obj_cache_name(obj, new_name);

    obj->dirty = 1;
    tfs_obj_update_hdr(dev, obj);

    if (old_parent) {
        old_parent->dirty = 1;
        tfs_obj_update_hdr(dev, old_parent);
    }
    if (new_parent != old_parent) {
        new_parent->dirty = 1;
        tfs_obj_update_hdr(dev, new_parent);
    }

    return TFS_OK;
}

tfs_obj_t *tfs_create_symlink(tfs_dev_t *dev, tfs_obj_t *parent,
                              const char *name, uint32_t mode,
                              const char *alias)
{
    tfs_obj_t *obj = tfs_create_obj(dev, parent, name, mode,
                                    TFS_OBJ_TYPE_SYMLINK);
    if (!obj) return NULL;

    size_t len = strlen(alias) + 1;
    obj->var.symlink.alias = (char *)dev->drv.malloc(dev->drv.ctx, len);
    if (!obj->var.symlink.alias) {
        tfs_unlink_obj(dev, obj);
        return NULL;
    }
    memcpy(obj->var.symlink.alias, alias, len);
    obj->dirty = 1;
    tfs_obj_update_hdr(dev, obj);
    return obj;
}

tfs_obj_t *tfs_create_hardlink(tfs_dev_t *dev, tfs_obj_t *parent,
                               const char *name, tfs_obj_t *equiv)
{
    tfs_obj_t *obj;
    uint32_t    obj_id;

    obj_id = tfs_obj_new_id(dev);
    if (!obj_id) return NULL;

    obj = tfs_obj_create(dev, obj_id, TFS_OBJ_TYPE_HARDLINK);
    if (!obj) return NULL;

    obj->var.hardlink.equiv_obj = equiv;
    obj->var.hardlink.equiv_id  = equiv->obj_id;
    obj->mode = equiv->mode;

    tfs_obj_cache_name(obj, name);
    tfs_obj_add_child(parent, obj);
    tfs_obj_insert(dev, obj);

    equiv->n_hard_links++;

    tfs_obj_update_hdr(dev, obj);
    return obj;
}

/*===================================================================
 *  Path lookup
 *===================================================================*/

tfs_obj_t *tfs_core_find_by_name(tfs_dev_t *dev, tfs_obj_t *dir,
                                  const char *name)
{
    return tfs_obj_find_by_name(dev, dir, name);
}

/*===================================================================
 *  Statistics
 *===================================================================*/

tfs_off_t tfs_core_free_space(const tfs_dev_t *dev)
{
    return (tfs_off_t)dev->n_free_chunks * dev->data_bytes_per_chunk;
}

tfs_off_t tfs_core_total_space(const tfs_dev_t *dev)
{
    return (tfs_off_t)tfs_total_blocks(dev)
           * tfs_chunks_per_block(dev)
           * dev->data_bytes_per_chunk;
}
