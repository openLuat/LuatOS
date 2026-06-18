/*
 * tfs_checkpoint.c — Checkpoint read/write for TFS
 *
 * A checkpoint is a sequential byte stream split across one or more
 * NAND chunks.  The stream is written into a ring of pre-allocated
 * chunks allocated just like normal data.  On mount, TFS first tries
 * to restore from checkpoint; if that fails it falls back to a full
 * NAND scan.
 *
 * Stream contents (in order):
 *   1. tfs_checkpt_validity_t
 *   2. tfs_checkpt_dev_t
 *   3. block_info words (one u32 per block: pages_in_use | state | seq)
 *   4. object records (tfs_checkpt_obj_t) — terminated by record with
 *      obj_id == 0
 *   5. file chunk records (tfs_checkpt_chunk_t) — terminated by record
 *      with obj_id == 0
 *   6. Closing validity checksum (sum/xor updated)
 */

#include "tfs_checkpoint.h"
#include "tfs_block.h"
#include "tfs_core.h"
#include "tfs_inode.h"
#include "tfs_tnode.h"
#include "../inc/tfs_config.h"

#include <string.h>

static int checkpt_version_supported(uint32_t version)
{
    return version == TFS_CHECKPT_VERSION;
}

static int checkpt_anchor_read(tfs_dev_t *dev, uint32_t *chunk, uint32_t *seq)
{
    if (!dev->drv.checkpt_anchor_read)
        return TFS_EINVAL;
    return dev->drv.checkpt_anchor_read(dev->drv.ctx, chunk, seq);
}

static int checkpt_anchor_write(tfs_dev_t *dev, uint32_t chunk, uint32_t seq)
{
    if (!dev->drv.checkpt_anchor_write)
        return TFS_EINVAL;
    return dev->drv.checkpt_anchor_write(dev->drv.ctx, chunk, seq);
}

static void checkpt_recount_space(tfs_dev_t *dev)
{
    int blk;
    int cpb = (int)tfs_chunks_per_block(dev);
    int free_chunks = 0;
    int erased_blocks = 0;

    for (blk = (int)dev->internal_start_block;
         blk <= (int)dev->internal_end_block;
         blk++) {
        tfs_block_info_t *bi = tfs_get_block_info(dev, blk);

        if (bi->bi.block_state == TFS_BLK_STATE_EMPTY) {
            erased_blocks++;
            free_chunks += cpb;
        } else if (bi->bi.block_state != TFS_BLK_STATE_DEAD &&
                   bi->bi.block_state != TFS_BLK_STATE_CHECKPOINT) {
            int free_in_block = cpb - (int)bi->bi.pages_in_use +
                                (int)bi->bi.soft_del_pages;
            if (free_in_block > 0)
                free_chunks += free_in_block;
        }
    }

    dev->n_erased_blocks = erased_blocks;
    dev->n_free_chunks = free_chunks;
}

static int checkpt_make_space(tfs_dev_t *dev, int required_blocks)
{
    int pass;
    int max_passes;

    if (required_blocks <= 0)
        return TFS_OK;

    if (dev->n_erased_blocks >= required_blocks)
        return TFS_OK;

    max_passes = (int)tfs_total_blocks(dev);
    for (pass = 0; pass < max_passes; pass++) {
        int before_erased = dev->n_erased_blocks;
        int before_free = dev->n_free_chunks;
        uint32_t before_gc = dev->n_gc_blocks;
        int rc = tfs_gc(dev, 1);

        if (rc != TFS_OK)
            return rc;

        if (dev->n_erased_blocks >= required_blocks)
            return TFS_OK;

        if (dev->n_erased_blocks == before_erased &&
            dev->n_free_chunks == before_free &&
            dev->n_gc_blocks == before_gc) {
            break;
        }
    }

    return dev->n_erased_blocks >= required_blocks ? TFS_OK : TFS_ENOSPC;
}

static int checkpt_list_ensure(tfs_dev_t *dev)
{
    uint32_t n_blocks = dev->internal_end_block - dev->internal_start_block + 1;

    if (dev->checkpt_block_list && dev->checkpt_max_blocks >= n_blocks)
        return TFS_OK;

    if (dev->checkpt_block_list) {
        dev->drv.free(dev->drv.ctx, dev->checkpt_block_list);
        dev->checkpt_block_list = NULL;
        dev->checkpt_max_blocks = 0;
    }

    dev->checkpt_block_list = (int *)
        dev->drv.malloc(dev->drv.ctx, n_blocks * (uint32_t)sizeof(int));
    if (!dev->checkpt_block_list)
        return TFS_ENOMEM;

    dev->checkpt_max_blocks = n_blocks;
    return TFS_OK;
}

static int checkpt_remember_block(tfs_dev_t *dev, int blk)
{
    uint32_t i;
    int rc;

    if (blk < (int)dev->internal_start_block ||
        blk > (int)dev->internal_end_block)
        return TFS_EINVAL;

    rc = checkpt_list_ensure(dev);
    if (rc != TFS_OK)
        return rc;

    for (i = 0; i < dev->blocks_in_checkpt; i++) {
        if (dev->checkpt_block_list[i] == blk)
            return TFS_OK;
    }

    if (dev->blocks_in_checkpt >= dev->checkpt_max_blocks)
        return TFS_ENOSPC;

    dev->checkpt_block_list[dev->blocks_in_checkpt++] = blk;
    return TFS_OK;
}

static int checkpt_block_in_list(const int *blocks, uint32_t count, int blk)
{
    uint32_t i;

    if (!blocks)
        return 0;

    for (i = 0; i < count; i++) {
        if (blocks[i] == blk)
            return 1;
    }

    return 0;
}

static void checkpt_make_empty_block_info(tfs_block_info_t *bi)
{
    memset(bi, 0, sizeof(*bi));
    bi->bi.block_state = TFS_BLK_STATE_EMPTY;
}

static void checkpt_erase_block_list(tfs_dev_t *dev,
                                     const int *blocks,
                                     uint32_t count)
{
    uint32_t i;
    int erased_any = 0;

    for (i = 0; i < count; i++) {
        int blk = blocks[i];

        if (blk < (int)dev->internal_start_block ||
            blk > (int)dev->internal_end_block)
            continue;

        if (tfs_block_get_state(dev, blk) == TFS_BLK_STATE_CHECKPOINT) {
            (void)tfs_block_erase(dev, blk);
            erased_any = 1;
        }
    }

    if (erased_any)
        checkpt_recount_space(dev);
}

static int checkpt_save_current_blocks(tfs_dev_t *dev,
                                       int **blocks_out,
                                       uint32_t *count_out)
{
    int *blocks = NULL;
    uint32_t count = dev->blocks_in_checkpt;

    if (!blocks_out || !count_out)
        return TFS_EINVAL;

    *blocks_out = NULL;
    *count_out = 0;

    if (count == 0)
        return TFS_OK;

    blocks = (int *)dev->drv.malloc(dev->drv.ctx,
                                    count * (uint32_t)sizeof(int));
    if (!blocks)
        return TFS_ENOMEM;

    memcpy(blocks, dev->checkpt_block_list,
           count * (uint32_t)sizeof(int));
    *blocks_out = blocks;
    *count_out = count;
    return TFS_OK;
}

static void checkpt_restore_saved_blocks(tfs_dev_t *dev,
                                         const int *blocks,
                                         uint32_t count)
{
    if (!blocks || count == 0) {
        dev->blocks_in_checkpt = 0;
        return;
    }

    if (dev->checkpt_block_list && dev->checkpt_max_blocks >= count) {
        memcpy(dev->checkpt_block_list, blocks,
               count * (uint32_t)sizeof(int));
        dev->blocks_in_checkpt = count;
    } else {
        dev->blocks_in_checkpt = 0;
    }
}

static int checkpt_alloc_block(tfs_dev_t *dev)
{
    int blk;
    int start = dev->alloc_block_finder;

    if (dev->n_erased_blocks <= 0)
        return TFS_ENOSPC;

    if (start < (int)dev->internal_start_block ||
        start > (int)dev->internal_end_block)
        start = (int)dev->internal_start_block;

    for (blk = start; blk <= (int)dev->internal_end_block; blk++) {
        if (tfs_block_get_state(dev, blk) == TFS_BLK_STATE_EMPTY)
            goto found;
    }

    for (blk = (int)dev->internal_start_block; blk < start; blk++) {
        if (tfs_block_get_state(dev, blk) == TFS_BLK_STATE_EMPTY)
            goto found;
    }

    return TFS_ENOSPC;

found:
    {
        tfs_block_info_t *bi = tfs_get_block_info(dev, blk);
        int rc = tfs_block_prepare_empty(dev, blk);

        if (rc != TFS_OK)
            return (dev->n_erased_blocks > 0) ? checkpt_alloc_block(dev)
                                              : TFS_ENOSPC;

        bi->bi.block_state = TFS_BLK_STATE_CHECKPOINT;
        bi->bi.seq_number = dev->seq_number++;
    }

    dev->n_erased_blocks--;
    dev->alloc_block_finder = blk + 1;
    if (dev->alloc_block_finder > (int)dev->internal_end_block)
        dev->alloc_block_finder = (int)dev->internal_start_block;

    dev->checkpt_cur_block = blk;
    dev->checkpt_next_block = (blk == 0) ? 1 : 0;
    return checkpt_remember_block(dev, blk);
}

static int checkpt_alloc_chunk(tfs_dev_t *dev, int *chunk_out)
{
    int cpb = (int)tfs_chunks_per_block(dev);
    int rc;

    if (!chunk_out)
        return TFS_EINVAL;

    if (dev->checkpt_cur_block < 0 ||
        dev->checkpt_next_block >= cpb) {
        rc = checkpt_alloc_block(dev);
        if (rc != TFS_OK)
            return rc;
    }

    *chunk_out = dev->checkpt_cur_block * cpb + dev->checkpt_next_block++;
    return TFS_OK;
}

/*===================================================================
 *  Byte-stream write helpers
 *===================================================================*/

static int wr_flush(tfs_dev_t *dev);

static int wr_byte(tfs_dev_t *dev, uint8_t b)
{
    uint32_t *sum = &dev->checkpt_sum;
    uint32_t *xor = &dev->checkpt_xor;

    *sum += b;
    *xor ^= b;

    dev->checkpt_buffer[dev->checkpt_byte_offs++] = b;
    dev->checkpt_byte_count++;

    if (dev->checkpt_byte_offs >= (int)dev->data_bytes_per_chunk)
        return wr_flush(dev);

    return TFS_OK;
}

static int wr_bytes(tfs_dev_t *dev, const void *data, int n)
{
    const uint8_t *p = (const uint8_t *)data;
    int i;
    for (i = 0; i < n; i++) {
        int rc = wr_byte(dev, p[i]);
        if (rc != TFS_OK)
            return rc;
    }
    return TFS_OK;
}

static int wr_u32(tfs_dev_t *dev, uint32_t v)
{
    return wr_bytes(dev, &v, 4);
}

static int wr_flush(tfs_dev_t *dev)
{
    tfs_ext_tags_t ext;
    int chunk, rc;

    if (dev->checkpt_byte_offs == 0)
        return TFS_OK;

    rc = checkpt_alloc_chunk(dev, &chunk);
    if (rc != TFS_OK)
        return rc;

    memset(&ext, 0, sizeof(ext));
    ext.chunk_used  = 1;
    ext.obj_id      = TFS_OBJ_ID_CHECKPT;
    ext.chunk_id    = (uint32_t)dev->checkpt_page_seq++;
    ext.n_bytes     = (uint32_t)dev->checkpt_byte_offs;

    rc = tfs_chunk_write(dev, chunk,
                         dev->checkpt_buffer,
                         dev->checkpt_byte_offs, &ext);
    if (rc != TFS_OK)
        return rc;

    if (ext.chunk_id == 0)
        dev->checkpt_cur_chunk = chunk;

    memset(dev->checkpt_buffer, 0xff, dev->data_bytes_per_chunk);
    dev->checkpt_byte_offs = 0;
    return TFS_OK;
}

/*===================================================================
 *  Byte-stream read helpers
 *===================================================================*/

static int rd_next_chunk(tfs_dev_t *dev);

static int rd_byte(tfs_dev_t *dev, uint8_t *b)
{
    if (dev->checkpt_byte_offs >= dev->checkpt_byte_count) {
        int rc = rd_next_chunk(dev);
        if (rc != TFS_OK)
            return rc;
    }

    *b = dev->checkpt_buffer[dev->checkpt_byte_offs++];
    dev->checkpt_sum += *b;
    dev->checkpt_xor ^= *b;
    return TFS_OK;
}

static int rd_bytes(tfs_dev_t *dev, void *data, int n)
{
    uint8_t *p = (uint8_t *)data;
    int i;
    for (i = 0; i < n; i++) {
        int rc = rd_byte(dev, &p[i]);
        if (rc != TFS_OK)
            return rc;
    }
    return TFS_OK;
}

static int rd_u32(tfs_dev_t *dev, uint32_t *v)
{
    return rd_bytes(dev, v, 4);
}

static int checkpoint_chunk_in_range(tfs_dev_t *dev, uint32_t chunk)
{
    uint32_t cpb = tfs_chunks_per_block(dev);
    uint32_t first = dev->internal_start_block * cpb;
    uint32_t last = (dev->internal_end_block + 1u) * cpb;

    return chunk >= first && chunk < last;
}

static int file_chunk_id_in_range(tfs_dev_t *dev, tfs_obj_t *obj,
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

static void mark_restored_chunk_used(tfs_dev_t *dev, uint32_t chunk)
{
    if (checkpoint_chunk_in_range(dev, chunk))
        tfs_chunk_set_used(dev, (int)chunk);
}

static void mark_block_unavailable(tfs_dev_t *dev, int blk,
                                   tfs_block_state_t state)
{
    int cpb = (int)tfs_chunks_per_block(dev);
    int page;
    tfs_block_info_t *bi = tfs_get_block_info(dev, blk);

    if ((int)bi->bi.pages_in_use < cpb) {
        int free_in_block = cpb - (int)bi->bi.pages_in_use;
        dev->n_free_chunks -= free_in_block;
        if (dev->n_free_chunks < 0)
            dev->n_free_chunks = 0;
    }

    if (bi->bi.block_state == TFS_BLK_STATE_EMPTY &&
        dev->n_erased_blocks > 0)
        dev->n_erased_blocks--;

    bi->bi.block_state = (uint32_t)state;
    bi->bi.pages_in_use = cpb;
    bi->bi.soft_del_pages = 0;

    for (page = 0; page < cpb; page++)
        tfs_chunk_set_used(dev, blk * cpb + page);
}

static int mark_restored_checkpt_blocks(tfs_dev_t *dev)
{
    uint32_t i;

    for (i = 0; i < dev->blocks_in_checkpt; i++) {
        int blk = dev->checkpt_block_list[i];

        if (blk < (int)dev->internal_start_block ||
            blk > (int)dev->internal_end_block)
            return TFS_EINVAL;

        mark_block_unavailable(dev, blk, TFS_BLK_STATE_CHECKPOINT);
    }

    return TFS_OK;
}

static int count_restored_live_chunks(const tfs_dev_t *dev, int blk)
{
    int cpb = (int)tfs_chunks_per_block(dev);
    int page;
    int count = 0;

    for (page = 0; page < cpb; page++) {
        if (tfs_chunk_is_used(dev, blk * cpb + page))
            count++;
    }

    return count;
}

static int reconcile_restored_space(tfs_dev_t *dev)
{
    int blk;
    int cpb = (int)tfs_chunks_per_block(dev);
    int free_chunks = 0;
    int erased_blocks = 0;

    for (blk = (int)dev->internal_start_block;
         blk <= (int)dev->internal_end_block;
         blk++) {
        tfs_block_info_t *bi = tfs_get_block_info(dev, blk);
        int live;

        if (bi->bi.block_state == TFS_BLK_STATE_DEAD ||
            bi->bi.block_state == TFS_BLK_STATE_CHECKPOINT) {
            continue;
        }

        if ((int)bi->bi.pages_in_use < 0 ||
            (int)bi->bi.pages_in_use > cpb) {
            return TFS_EINVAL;
        }

        live = count_restored_live_chunks(dev, blk);
        if (live > (int)bi->bi.pages_in_use)
            return TFS_EINVAL;

        if (bi->bi.block_state == TFS_BLK_STATE_EMPTY) {
            if (bi->bi.pages_in_use != 0 || live != 0)
                return TFS_EINVAL;
            bi->bi.soft_del_pages = 0;
            erased_blocks++;
            free_chunks += cpb;
            continue;
        }

        bi->bi.soft_del_pages = (int)bi->bi.pages_in_use - live;
        free_chunks += cpb - (int)bi->bi.pages_in_use +
                       (int)bi->bi.soft_del_pages;
    }

    dev->n_erased_blocks = erased_blocks;
    dev->n_free_chunks = free_chunks;
    return TFS_OK;
}

static int checkpt_read_candidate(tfs_dev_t *dev, int chunk,
                                  tfs_ext_tags_t *ext)
{
    int rc;
    int cpb = (int)tfs_chunks_per_block(dev);
    int blk = chunk / cpb;

    memset(ext, 0, sizeof(*ext));
    rc = tfs_chunk_read(dev, chunk, dev->checkpt_buffer,
                        (int)dev->data_bytes_per_chunk, ext);
    if (rc == TFS_OK)
        return TFS_OK;

    if (chunk % cpb == 0 &&
        blk >= (int)dev->internal_start_block &&
        blk <= (int)dev->internal_end_block) {
        tfs_block_mark_bad(dev, blk);
        mark_block_unavailable(dev, blk, TFS_BLK_STATE_DEAD);
    }

    return rc;
}

static int rd_next_chunk(tfs_dev_t *dev)
{
    tfs_ext_tags_t ext;
    int            blk, chunk, pass, found = 0;
    int            cpb = (int)tfs_chunks_per_block(dev);
    int            start_blk = dev->checkpt_cur_block;

    chunk = dev->checkpt_cur_chunk + 1;
    if (chunk / cpb == dev->checkpt_cur_block) {
        int rc = checkpt_read_candidate(dev, chunk, &ext);

        if (rc != TFS_OK)
            return TFS_EINVAL;

        if (ext.chunk_used &&
            ext.obj_id == TFS_OBJ_ID_CHECKPT &&
            (int)ext.chunk_id == dev->checkpt_page_seq &&
            ext.seq_number >= (uint32_t)dev->checkpt_next_block &&
            ext.n_bytes <= dev->data_bytes_per_chunk) {

            dev->checkpt_cur_chunk  = chunk;
            dev->checkpt_byte_count = (int)ext.n_bytes;
            dev->checkpt_byte_offs  = 0;
            dev->checkpt_page_seq++;
            if (ext.seq_number > dev->checkpt_max_seq)
                dev->checkpt_max_seq = ext.seq_number;
            return TFS_OK;
        }

        return TFS_EINVAL;
    }

    /* Checkpoint blocks start at page 0; search block-first only. */
    for (pass = 0; pass < 2 && !found; pass++) {
        int first_blk = pass == 0 ? start_blk + 1 : (int)dev->internal_start_block;
        int last_blk = pass == 0 ? (int)dev->internal_end_block : start_blk - 1;

        for (blk = first_blk; blk <= last_blk && !found; blk++) {
            int rc;

            if (dev->drv.check_bad && dev->drv.check_bad(dev->drv.ctx, blk))
                continue;

            chunk = blk * cpb;
            rc = checkpt_read_candidate(dev, chunk, &ext);
            if (rc != TFS_OK)
                continue;

            if (ext.chunk_used &&
                ext.obj_id == TFS_OBJ_ID_CHECKPT &&
                (int)ext.chunk_id == dev->checkpt_page_seq &&
                ext.seq_number >= (uint32_t)dev->checkpt_next_block &&
                ext.n_bytes <= dev->data_bytes_per_chunk) {

                dev->checkpt_cur_chunk  = chunk;
                dev->checkpt_cur_block  = blk;
                dev->checkpt_byte_count = (int)ext.n_bytes;
                dev->checkpt_byte_offs  = 0;
                dev->checkpt_page_seq++;
                if (ext.seq_number > dev->checkpt_max_seq)
                    dev->checkpt_max_seq = ext.seq_number;
                rc = checkpt_remember_block(dev, blk);
                if (rc != TFS_OK)
                    return rc;
                found = 1;
            }
        }
    }

    return found ? TFS_OK : TFS_EINVAL;
}

static int load_checkpoint_start(tfs_dev_t *dev, int chunk,
                                 tfs_checkpt_validity_t *val_out,
                                 uint32_t *tag_seq_out,
                                 int activate)
{
    tfs_ext_tags_t ext;
    tfs_checkpt_validity_t val;
    int cpb = (int)tfs_chunks_per_block(dev);
    int blk = chunk / cpb;
    int rc;

    if (chunk < (int)dev->internal_start_block * cpb ||
        blk < (int)dev->internal_start_block ||
        blk > (int)dev->internal_end_block)
        return TFS_EINVAL;

    memset(&ext, 0, sizeof(ext));
    rc = tfs_chunk_read(dev, chunk, dev->checkpt_buffer,
                        (int)dev->data_bytes_per_chunk, &ext);
    if (rc != TFS_OK) {
        if (chunk % cpb == 0) {
            tfs_block_mark_bad(dev, blk);
            mark_block_unavailable(dev, blk, TFS_BLK_STATE_DEAD);
        }
        return TFS_EINVAL;
    }

    if (!ext.chunk_used ||
        ext.obj_id != TFS_OBJ_ID_CHECKPT ||
        ext.chunk_id != 0 ||
        ext.n_bytes < sizeof(val) ||
        ext.n_bytes > dev->data_bytes_per_chunk)
        return TFS_EINVAL;

    memcpy(&val, dev->checkpt_buffer, sizeof(val));
    if (!checkpt_version_supported(val.version))
        return TFS_EINVAL;

    if (val_out)
        *val_out = val;
    if (tag_seq_out)
        *tag_seq_out = ext.seq_number;

    if (activate) {
        dev->checkpt_page_seq  = 1;
        dev->checkpt_cur_block = blk;
        dev->checkpt_cur_chunk = chunk;
        dev->checkpt_byte_offs = 0;
        dev->checkpt_byte_count= (int)ext.n_bytes;
        dev->checkpt_sum       = 0;
        dev->checkpt_xor       = 0;
        dev->checkpt_next_block= (int)ext.seq_number;
        dev->checkpt_max_seq   = ext.seq_number;
        rc = checkpt_remember_block(dev, blk);
        if (rc != TFS_OK)
            return rc;
    }

    return TFS_OK;
}

static int find_latest_checkpoint_start(tfs_dev_t *dev)
{
    int blk;
    int cpb = (int)tfs_chunks_per_block(dev);
    int best_chunk = -1;
    uint32_t best_tag_seq = 0;
    uint32_t best_val_seq = 0;
    uint32_t anchor_chunk = 0;
    uint32_t anchor_seq = 0;

    if (checkpt_anchor_read(dev, &anchor_chunk, &anchor_seq) == TFS_OK) {
        tfs_checkpt_validity_t val;

        if (load_checkpoint_start(dev, (int)anchor_chunk,
                                  &val, NULL, 0) == TFS_OK &&
            val.seq == anchor_seq) {
            return load_checkpoint_start(dev, (int)anchor_chunk,
                                         NULL, NULL, 1);
        }
    }

    for (blk = (int)dev->internal_start_block;
         blk <= (int)dev->internal_end_block;
         blk++) {
        int first_page = (blk == 0) ? 1 : 0;
        int pass;

        if (dev->drv.check_bad && dev->drv.check_bad(dev->drv.ctx, blk))
            continue;

        for (pass = 0; pass < 2; pass++) {
            int page = pass == 0 ? first_page : 0;
            int chunk;
            tfs_checkpt_validity_t val;
            uint32_t tag_seq;

            if (pass == 1 && page == first_page)
                continue;

            chunk = blk * cpb + page;
            if (load_checkpoint_start(dev, chunk, &val, &tag_seq, 0) != TFS_OK)
                continue;

            if (best_chunk < 0 ||
                val.seq > best_val_seq ||
                (val.seq == best_val_seq &&
                 (tag_seq > best_tag_seq ||
                  (tag_seq == best_tag_seq && chunk > best_chunk)))) {
                best_chunk = chunk;
                best_tag_seq = tag_seq;
                best_val_seq = val.seq;
            }
        }
    }

    if (best_chunk < 0)
        return TFS_EINVAL;

    return load_checkpoint_start(dev, best_chunk, NULL, NULL, 1);
}

/*===================================================================
 *  Checkpoint required blocks
 *===================================================================*/

int tfs_checkpt_required_blocks(const tfs_dev_t *dev)
{
    uint64_t bytes;
    uint64_t block_payload;
    uint32_t i;
    uint32_t block_count;
    uint32_t cpb;
    int      blocks;

    if (!dev)
        return TFS_CFG_CHECKPOINT_RESERVED_BLOCKS;

    cpb = tfs_chunks_per_block(dev);
    if (cpb <= 1 || dev->data_bytes_per_chunk == 0)
        return TFS_CFG_CHECKPOINT_RESERVED_BLOCKS;

    block_count = dev->internal_end_block - dev->internal_start_block + 1u;
    bytes = sizeof(tfs_checkpt_validity_t) +
            sizeof(tfs_checkpt_dev_t) +
            ((uint64_t)block_count * 2u * sizeof(uint32_t)) +
            sizeof(tfs_checkpt_obj_t) +
            sizeof(tfs_checkpt_chunk_t);

    for (i = 0; i < TFS_OBJ_BUCKETS; i++) {
        tfs_obj_t *obj;

        tfs_list_for_each_entry(obj, &dev->obj_bucket[i].list, hash_link) {
            if (obj->fake)
                continue;

            bytes += sizeof(tfs_checkpt_obj_t);
            if (obj->obj_type == TFS_OBJ_TYPE_FILE &&
                obj->n_data_chunks > 0) {
                bytes += (uint64_t)obj->n_data_chunks *
                         sizeof(tfs_checkpt_chunk_t);
            }
        }
    }

    block_payload = (uint64_t)(cpb - 1u) * dev->data_bytes_per_chunk;
    blocks = (int)((bytes + block_payload - 1u) / block_payload);
    blocks += TFS_CFG_CHECKPOINT_SPARE_BLOCKS;

    if (blocks < TFS_CFG_CHECKPOINT_RESERVED_BLOCKS)
        blocks = TFS_CFG_CHECKPOINT_RESERVED_BLOCKS;

    return blocks;
}

/*===================================================================
 *  Checkpoint write
 *===================================================================*/

static int write_obj_record(tfs_dev_t *dev, tfs_obj_t *obj)
{
    tfs_checkpt_obj_t rec;
    const char *name;
    memset(&rec, 0, sizeof(rec));

    rec.obj_id       = obj->obj_id;
    rec.parent_id    = obj->parent ? obj->parent->obj_id : 0;
    rec.hdr_chunk    = (uint32_t)obj->hdr_chunk;
    rec.type         = obj->obj_type;
    rec.mode         = obj->mode;
    rec.uid          = obj->uid;
    rec.gid          = obj->gid;
    rec.atime        = obj->atime;
    rec.mtime        = obj->mtime;
    rec.ctime        = obj->ctime;
    rec.rdev         = obj->rdev;
    rec.n_data_chunks= (uint32_t)obj->n_data_chunks;

    if (obj->obj_type == TFS_OBJ_TYPE_FILE) {
        rec.file_size_lo = (uint32_t)(obj->var.file.stored_size & 0xffffffffu);
        rec.file_size_hi = (uint32_t)(obj->var.file.stored_size >> 32);
    }

    name = tfs_obj_get_name(dev, obj);
    if (name) {
        strncpy(rec.name, name, TFS_MAX_NAME_LEN);
        rec.name[TFS_MAX_NAME_LEN] = '\0';
    }

    return wr_bytes(dev, &rec, sizeof(rec));
}

static int write_obj_chunks(tfs_dev_t *dev, tfs_obj_t *obj)
{
    uint32_t chunk_id;
    uint32_t n_chunks;
    tfs_off_t n_chunks64;

    if (obj->obj_type != TFS_OBJ_TYPE_FILE ||
        obj->var.file.stored_size <= 0)
        return TFS_OK;

    n_chunks64 = (obj->var.file.stored_size +
                  (tfs_off_t)dev->data_bytes_per_chunk - 1) /
                 (tfs_off_t)dev->data_bytes_per_chunk;
    if (n_chunks64 > (tfs_off_t)0xffffffffu)
        return TFS_ERANGE;

    n_chunks = (uint32_t)n_chunks64;
    for (chunk_id = 0; chunk_id < n_chunks; chunk_id++) {
        uint32_t chunk = tfs_tnode_get_chunk(dev, obj, chunk_id);
        if (chunk > 0) {
            tfs_checkpt_chunk_t rec;
            int rc;

            memset(&rec, 0, sizeof(rec));
            rec.obj_id = obj->obj_id;
            rec.chunk_id = chunk_id;
            rec.chunk_in_nand = chunk;

            rc = wr_bytes(dev, &rec, sizeof(rec));
            if (rc != TFS_OK)
                return rc;
        }
    }

    return TFS_OK;
}

static int tfs_checkpt_write_once(tfs_dev_t *dev)
{
    tfs_checkpt_validity_t val;
    tfs_checkpt_dev_t      cdev;
    uint32_t                i, blk;
    int                    *old_blocks = NULL;
    uint32_t                old_count = 0;
    int                     required_blocks;
    int                    rc;

    if (dev->param.skip_checkpt_wr)
        return TFS_OK;

    /* Alloc checkpoint buffer */
    if (!dev->checkpt_buffer) {
        dev->checkpt_buffer = (uint8_t *)
            dev->drv.malloc(dev->drv.ctx, dev->data_bytes_per_chunk);
        if (!dev->checkpt_buffer)
            return TFS_ENOMEM;
    }

    rc = checkpt_list_ensure(dev);
    if (rc != TFS_OK)
        return rc;

    rc = checkpt_save_current_blocks(dev, &old_blocks, &old_count);
    if (rc != TFS_OK)
        return rc;

    /*
     * Keep the previous checkpoint and anchor valid until the replacement is
     * fully written.  With an old checkpoint present, do not run GC before
     * publishing the new anchor: GC could erase chunks referenced by that old
     * checkpoint and make a mid-sync power loss unrecoverable from the anchor.
     */
    required_blocks = tfs_checkpt_required_blocks(dev);
    if (old_count > 0) {
        if (dev->n_erased_blocks < required_blocks) {
            if (dev->drv.trace) {
                dev->drv.trace("tfs: checkpoint no space old=%u erased=%d required=%d free=%d",
                               (unsigned int)old_count,
                               dev->n_erased_blocks,
                               required_blocks,
                               dev->n_free_chunks);
            }
            rc = TFS_ENOSPC;
            goto out;
        }
    } else {
        rc = checkpt_make_space(dev, required_blocks);
        if (rc != TFS_OK)
            goto out;
    }

    dev->blocks_in_checkpt = 0;

    memset(dev->checkpt_buffer, 0xff, dev->data_bytes_per_chunk);
    dev->checkpt_byte_offs  = 0;
    dev->checkpt_byte_count = 0;
    dev->checkpt_page_seq   = 0;
    dev->checkpt_cur_chunk  = -1;
    dev->checkpt_cur_block  = -1;
    dev->checkpt_next_block = 0;
    dev->checkpt_sum        = 0;
    dev->checkpt_xor        = 0;

    /* 1. Validity header */
    memset(&val, 0, sizeof(val));
    val.version = TFS_CHECKPT_VERSION;
    val.seq     = dev->seq_number;
    rc = wr_bytes(dev, &val, sizeof(val));
    if (rc != TFS_OK) goto fail_new;

    /* 2. Device state */
    memset(&cdev, 0, sizeof(cdev));
    cdev.n_erased_blocks  = (uint32_t)(dev->n_erased_blocks +
                                       (int)old_count);
    cdev.alloc_block      = (uint32_t)dev->alloc_block;
    cdev.alloc_page       = (uint32_t)dev->alloc_page;
    cdev.n_free_chunks    = (uint32_t)(dev->n_free_chunks +
                                       (int)old_count *
                                       (int)tfs_chunks_per_block(dev));
    cdev.seq_number       = dev->seq_number;
    cdev.oldest_dirty_seq = dev->oldest_dirty_seq;
    cdev.n_deleted_files  = (uint32_t)dev->n_deleted_files;
    cdev.n_unlinked_files = (uint32_t)dev->n_unlinked_files;
    rc = wr_bytes(dev, &cdev, sizeof(cdev));
    if (rc != TFS_OK) goto fail_new;

    /* 3. Block info */
    for (blk = dev->internal_start_block; blk <= dev->internal_end_block; blk++) {
        tfs_block_info_t bi;

        if (checkpt_block_in_list(old_blocks, old_count, (int)blk)) {
            checkpt_make_empty_block_info(&bi);
        } else {
            bi = *tfs_get_block_info(dev, (int)blk);
        }

        rc = wr_u32(dev, bi.as_u32[0]);
        if (rc != TFS_OK) goto fail_new;
        rc = wr_u32(dev, bi.as_u32[1]);
        if (rc != TFS_OK) goto fail_new;
    }

    /* 4. Objects */
    for (i = 0; i < TFS_OBJ_BUCKETS; i++) {
        tfs_obj_t *obj;
        tfs_list_for_each_entry(obj, &dev->obj_bucket[i].list, hash_link) {
            if (!obj->fake) {
                rc = write_obj_record(dev, obj);
                if (rc != TFS_OK) goto fail_new;
            }
        }
    }

    /* Terminator */
    {
        tfs_checkpt_obj_t term;
        memset(&term, 0, sizeof(term));
        rc = wr_bytes(dev, &term, sizeof(term));
        if (rc != TFS_OK) goto fail_new;
    }

    /* 5. File chunk mappings */
    for (i = 0; i < TFS_OBJ_BUCKETS; i++) {
        tfs_obj_t *obj;
        tfs_list_for_each_entry(obj, &dev->obj_bucket[i].list, hash_link) {
            if (!obj->fake) {
                rc = write_obj_chunks(dev, obj);
                if (rc != TFS_OK) goto fail_new;
            }
        }
    }

    /* Chunk mapping terminator */
    {
        tfs_checkpt_chunk_t term;
        memset(&term, 0, sizeof(term));
        rc = wr_bytes(dev, &term, sizeof(term));
        if (rc != TFS_OK) goto fail_new;
    }

    /* Flush final partial chunk */
    rc = wr_flush(dev);
    if (rc != TFS_OK) goto fail_new;

    rc = mark_restored_checkpt_blocks(dev);
    if (rc != TFS_OK)
        goto fail_new;

    if (dev->checkpt_cur_chunk >= 0) {
        rc = checkpt_anchor_write(dev,
                                  (uint32_t)dev->checkpt_cur_chunk,
                                  val.seq);
        if (rc != TFS_OK && rc != TFS_EINVAL)
            goto fail_new;
    }

    checkpt_erase_block_list(dev, old_blocks, old_count);

    dev->is_checkpointed = 1;
    rc = TFS_OK;
    goto out;

fail_new:
    if (dev->drv.trace) {
        dev->drv.trace("tfs: checkpoint replacement failed rc=%d old=%u new=%u erased=%d required=%d free=%d",
                       rc,
                       (unsigned int)old_count,
                       (unsigned int)dev->blocks_in_checkpt,
                       dev->n_erased_blocks,
                       required_blocks,
                       dev->n_free_chunks);
    }
    checkpt_erase_block_list(dev, dev->checkpt_block_list,
                             dev->blocks_in_checkpt);
    checkpt_restore_saved_blocks(dev, old_blocks, old_count);
    dev->is_checkpointed = 0;

out:
    if (old_blocks)
        dev->drv.free(dev->drv.ctx, old_blocks);
    return rc;
}

int tfs_checkpt_write(tfs_dev_t *dev)
{
    int rc = TFS_OK;
    int attempt;

    if (dev->param.skip_checkpt_wr)
        return TFS_OK;

    for (attempt = 0; attempt < 3; attempt++) {
        dev->checkpt_open_write = 1;
        rc = tfs_checkpt_write_once(dev);
        dev->checkpt_open_write = 0;

        if (rc == TFS_OK)
            return TFS_OK;

        /*
         * tfs_checkpt_write_once() preserves the previous checkpoint and
         * erases only the failed replacement stream.  Retry flash failures so
         * the next allocation can choose a different block.
         */
        dev->checkpt_cur_chunk  = -1;
        dev->checkpt_cur_block  = -1;
        dev->checkpt_next_block = 0;
        dev->checkpt_byte_offs  = 0;
        dev->checkpt_byte_count = 0;
        dev->checkpt_page_seq   = 0;

        if (rc != TFS_EFLASH)
            break;
    }

    dev->checkpt_open_write = 0;
    dev->is_checkpointed = 0;
    return rc;
}

/*===================================================================
 *  Checkpoint read
 *===================================================================*/

/*===================================================================
 *  Post-restore fixup: advance alloc_page past any checkpoint chunks
 *  that were written AFTER the cdev record was serialised.
 *===================================================================*/

static void fixup_alloc_after_checkpt(tfs_dev_t *dev)
{
    int blk, cpb;
    tfs_ext_tags_t ext;

    if (dev->alloc_block < 0)
        return;

    blk = dev->alloc_block;
    cpb = (int)tfs_chunks_per_block(dev);

    /* Scan forward from saved alloc_page; mark any written chunks as used
     * (these are checkpoint chunks written after the cdev record was saved). */
    while ((int)dev->alloc_page < cpb) {
        int chunk = blk * cpb + (int)dev->alloc_page;

        memset(&ext, 0, sizeof(ext));
        tfs_chunk_read(dev, chunk, NULL, 0, &ext);

        if (!ext.chunk_used)
            break;  /* found first genuinely erased page */

        if (!tfs_chunk_is_used(dev, chunk)) {
            tfs_chunk_set_used(dev, chunk);
            tfs_get_block_info(dev, blk)->bi.pages_in_use++;
            dev->n_free_chunks--;
        }
        dev->alloc_page++;
    }

    /* Update block state to match reality */
    {
        tfs_block_info_t *bi = tfs_get_block_info(dev, blk);
        if ((int)dev->alloc_page >= cpb) {
            bi->bi.block_state = TFS_BLK_STATE_FULL;
            dev->alloc_block   = -1;
        } else {
            bi->bi.block_state = TFS_BLK_STATE_ALLOCATING;
        }
    }
}

int tfs_checkpt_read(tfs_dev_t *dev)
{
    tfs_checkpt_validity_t val;
    tfs_checkpt_dev_t      cdev;
    tfs_checkpt_obj_t      orec;
    tfs_checkpt_chunk_t    crec;
    uint32_t                blk, n_blocks;
    int                    cpb;
    int                    total_chunks;
    int                    free_from_blocks = 0;
    int                    erased_from_blocks = 0;
    int                    restored_objects = 0;
    int                    restored_chunks = 0;
    int                    rc;

    if (dev->param.skip_checkpt_rd)
        return TFS_EINVAL;

    if (!dev->checkpt_buffer) {
        dev->checkpt_buffer = (uint8_t *)
            dev->drv.malloc(dev->drv.ctx, dev->data_bytes_per_chunk);
        if (!dev->checkpt_buffer)
            return TFS_ENOMEM;
    }

    rc = checkpt_list_ensure(dev);
    if (rc != TFS_OK)
        return rc;
    dev->blocks_in_checkpt = 0;
    dev->checkpt_has_tnodes = 0;
    dev->checkpt_max_seq = 0;

    if (find_latest_checkpoint_start(dev) != TFS_OK)
        return TFS_EINVAL;

    /* 1. Validity header */
    rc = rd_bytes(dev, &val, sizeof(val));
    if (rc != TFS_OK || val.version != TFS_CHECKPT_VERSION)
        return TFS_EINVAL;

    /* 2. Device state */
    rc = rd_bytes(dev, &cdev, sizeof(cdev));
    if (rc != TFS_OK) return TFS_EINVAL;

    dev->n_erased_blocks  = (int)cdev.n_erased_blocks;
    dev->alloc_block      = (int)cdev.alloc_block;
    dev->alloc_page       = (uint32_t)cdev.alloc_page;
    dev->n_free_chunks    = (int)cdev.n_free_chunks;
    dev->seq_number       = cdev.seq_number;
    dev->oldest_dirty_seq = cdev.oldest_dirty_seq;
    dev->n_deleted_files  = (int)cdev.n_deleted_files;
    dev->n_unlinked_files = (int)cdev.n_unlinked_files;
    dev->checkpt_base_seq = cdev.seq_number;
    dev->checkpt_base_alloc_block = (int)cdev.alloc_block;
    dev->checkpt_base_alloc_page = (uint32_t)cdev.alloc_page;
    dev->checkpt_delta_chunks = 0;

    /* 3. Block info */
    n_blocks = dev->internal_end_block - dev->internal_start_block + 1;
    cpb = (int)tfs_chunks_per_block(dev);
    total_chunks = (int)n_blocks * cpb;
    for (blk = 0; blk < n_blocks; blk++) {
        tfs_block_info_t *bi = &dev->block_info[blk];
        rc  = rd_u32(dev, &bi->as_u32[0]);
        rc |= rd_u32(dev, &bi->as_u32[1]);
        if (rc != TFS_OK) return TFS_EINVAL;
        if ((int)bi->bi.pages_in_use > cpb)
            return TFS_EINVAL;
        if ((int)bi->bi.soft_del_pages > (int)bi->bi.pages_in_use)
            return TFS_EINVAL;
        if (bi->bi.block_state == TFS_BLK_STATE_DEAD ||
            bi->bi.block_state == TFS_BLK_STATE_CHECKPOINT)
            free_from_blocks += 0;
        else
            free_from_blocks += cpb - (int)bi->bi.pages_in_use +
                                (int)bi->bi.soft_del_pages;
        if (bi->bi.block_state == TFS_BLK_STATE_EMPTY)
            erased_from_blocks++;
    }
    if (free_from_blocks < 0 || free_from_blocks > total_chunks)
        return TFS_EINVAL;

    /*
     * n_free_chunks/n_erased_blocks are derived values.  Older experimental
     * checkpoints could restore object mappings while keeping stale counters,
     * which made fsstat report used=0.  Rebuild them from block_info instead.
     */
    dev->n_free_chunks = free_from_blocks;
    dev->n_erased_blocks = erased_from_blocks;

    /* 4. Objects */
    for (;;) {
        rc = rd_bytes(dev, &orec, sizeof(orec));
        if (rc != TFS_OK) return TFS_EINVAL;
        if (orec.obj_id == 0) break;   /* terminator */

        tfs_obj_t *obj = tfs_obj_create(dev, orec.obj_id,
                                        (tfs_obj_type_t)orec.type);
        if (!obj) return TFS_ENOMEM;
        restored_objects++;

        if (!checkpoint_chunk_in_range(dev, orec.hdr_chunk))
            return TFS_EINVAL;

        obj->hdr_chunk    = (int)orec.hdr_chunk;
        obj->mode         = orec.mode;
        obj->uid          = orec.uid;
        obj->gid          = orec.gid;
        obj->atime        = orec.atime;
        obj->mtime        = orec.mtime;
        obj->ctime        = orec.ctime;
        obj->rdev         = orec.rdev;
        obj->n_data_chunks= (int)orec.n_data_chunks;
        obj->checkpt_parent_id = orec.parent_id;
        if (orec.name[0] != '\0')
            tfs_obj_cache_name(obj, orec.name);

        if (orec.type == TFS_OBJ_TYPE_FILE) {
            obj->var.file.stored_size =
                (tfs_off_t)orec.file_size_hi << 32 | orec.file_size_lo;
            obj->var.file.file_size   = obj->var.file.stored_size;
        }

        obj->valid = 1;
        tfs_obj_insert(dev, obj);
        if (obj->hdr_chunk >= 0)
            mark_restored_chunk_used(dev, (uint32_t)obj->hdr_chunk);

        /* Re-wire parent link after all objects are loaded. */
    }
    if (restored_objects > 0 && free_from_blocks == total_chunks)
        return TFS_EINVAL;

    /* 5. File chunk mappings */
    for (;;) {
        rc = rd_bytes(dev, &crec, sizeof(crec));
        if (rc != TFS_OK) return TFS_EINVAL;
        if (crec.obj_id == 0) break;

        {
            tfs_obj_t *obj = tfs_obj_find(dev, crec.obj_id);
            if (!obj ||
                obj->obj_type != TFS_OBJ_TYPE_FILE ||
                !checkpoint_chunk_in_range(dev, crec.chunk_in_nand) ||
                !file_chunk_id_in_range(dev, obj, crec.chunk_id))
                return TFS_EINVAL;

            rc = tfs_tnode_put_chunk(dev, obj, crec.chunk_id,
                                     crec.chunk_in_nand);
            if (rc != TFS_OK)
                return rc;
            mark_restored_chunk_used(dev, crec.chunk_in_nand);
            restored_chunks++;
        }
    }
    if (restored_chunks > 0 && free_from_blocks == total_chunks)
        return TFS_EINVAL;
    dev->checkpt_has_tnodes = 1;

    rc = mark_restored_checkpt_blocks(dev);
    if (rc != TFS_OK)
        return rc;

    if (dev->checkpt_max_seq >= dev->checkpt_base_seq &&
        dev->checkpt_max_seq < TFS_HIGHEST_SEQ_NUMBER) {
        dev->checkpt_base_seq = dev->checkpt_max_seq + 1;
        if (dev->seq_number < dev->checkpt_base_seq)
            dev->seq_number = dev->checkpt_base_seq;
    }

    /* The cdev record saved alloc_page BEFORE checkpoint chunks were written.
     * Advance past any checkpoint chunks that now occupy those pages. */
    fixup_alloc_after_checkpt(dev);

    rc = reconcile_restored_space(dev);
    if (rc != TFS_OK)
        return rc;

    dev->is_checkpointed = 1;
    return TFS_OK;
}

/*===================================================================
 *  Erase checkpoint blocks
 *===================================================================*/

void tfs_checkpt_erase(tfs_dev_t *dev)
{
    int blk;
    int erased_any = 0;

    for (blk = (int)dev->internal_start_block;
         blk <= (int)dev->internal_end_block;
         blk++) {

        if (tfs_block_get_state(dev, blk) == TFS_BLK_STATE_CHECKPOINT) {
            (void)tfs_block_erase(dev, blk);
            erased_any = 1;
        }
    }
    if (erased_any)
        checkpt_recount_space(dev);
    dev->is_checkpointed = 0;
    dev->blocks_in_checkpt = 0;
}
