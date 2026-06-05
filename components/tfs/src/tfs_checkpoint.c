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
#include "tfs_inode.h"
#include "tfs_tnode.h"
#include "../inc/tfs_config.h"

#include <string.h>

static int checkpt_version_supported(uint32_t version)
{
    return version == TFS_CHECKPT_VERSION;
}

#if defined(__GNUC__)
__attribute__((weak)) int tfs_checkpoint_anchor_read(void *drv_ctx,
                                                     uint32_t *chunk,
                                                     uint32_t *seq)
{
    (void)drv_ctx;
    (void)chunk;
    (void)seq;
    return TFS_EINVAL;
}

__attribute__((weak)) int tfs_checkpoint_anchor_write(void *drv_ctx,
                                                      uint32_t chunk,
                                                      uint32_t seq)
{
    (void)drv_ctx;
    (void)chunk;
    (void)seq;
    return TFS_EINVAL;
}
#endif

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

    chunk = tfs_alloc_chunk(dev, 1);  /* use reserved blocks if needed */
    if (chunk < 0)
        return TFS_ENOSPC;

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

static int rd_next_chunk(tfs_dev_t *dev)
{
    tfs_ext_tags_t ext;
    int            blk, chunk, found = 0;

    /* Scan forward from checkpt_cur_chunk looking for next checkpoint chunk */
    for (blk = dev->checkpt_cur_block;
         blk <= (int)dev->internal_end_block && !found;
         blk++) {

        int cpb = (int)tfs_chunks_per_block(dev);
        int start = (blk == dev->checkpt_cur_block)
                    ? dev->checkpt_cur_chunk + 1 : blk * cpb;

        for (chunk = start; chunk < blk * cpb + cpb; chunk++) {
            memset(&ext, 0, sizeof(ext));
            int rc = tfs_chunk_read(dev, chunk, dev->checkpt_buffer,
                                    (int)dev->data_bytes_per_chunk, &ext);

            if (rc == TFS_OK &&
                ext.chunk_used &&
                ext.obj_id == TFS_OBJ_ID_CHECKPT &&
                (int)ext.chunk_id == dev->checkpt_page_seq &&
                ext.n_bytes <= dev->data_bytes_per_chunk) {

                dev->checkpt_cur_chunk  = chunk;
                dev->checkpt_cur_block  = blk;
                dev->checkpt_byte_count = (int)ext.n_bytes;
                dev->checkpt_byte_offs  = 0;
                dev->checkpt_page_seq++;
                found = 1;
                break;
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
    if (rc != TFS_OK ||
        !ext.chunk_used ||
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
    }

    return TFS_OK;
}

static int find_latest_checkpoint_start(tfs_dev_t *dev)
{
    int blk, chunk;
    int cpb = (int)tfs_chunks_per_block(dev);
    int best_chunk = -1;
    uint32_t best_tag_seq = 0;
    uint32_t best_val_seq = 0;
    uint32_t anchor_chunk = 0;
    uint32_t anchor_seq = 0;

    if (tfs_checkpoint_anchor_read(dev->drv.ctx,
                                   &anchor_chunk,
                                   &anchor_seq) == TFS_OK) {
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
        for (chunk = blk * cpb; chunk < (blk + 1) * cpb; chunk++) {
            tfs_checkpt_validity_t val;
            uint32_t tag_seq;

            if (load_checkpoint_start(dev, chunk, &val, &tag_seq, 0) != TFS_OK)
                continue;

            if (best_chunk < 0 ||
                tag_seq > best_tag_seq ||
                (tag_seq == best_tag_seq &&
                 (val.seq > best_val_seq ||
                  (val.seq == best_val_seq && chunk > best_chunk)))) {
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
    /* Very rough estimate: 1 block for validity + device info,
     * plus 1 block per 1024 objects, minimum 2. */
    int n_obj_blocks = (dev->n_obj + 1023) / 1024;
    int total = 2 + n_obj_blocks;
    if (total < 2) total = 2;
    return total;
}

/*===================================================================
 *  Checkpoint write
 *===================================================================*/

static int write_obj_record(tfs_dev_t *dev, tfs_obj_t *obj)
{
    tfs_checkpt_obj_t rec;
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

int tfs_checkpt_write(tfs_dev_t *dev)
{
    tfs_checkpt_validity_t val;
    tfs_checkpt_dev_t      cdev;
    uint32_t                i, blk;
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

    memset(dev->checkpt_buffer, 0xff, dev->data_bytes_per_chunk);
    dev->checkpt_byte_offs  = 0;
    dev->checkpt_byte_count = 0;
    dev->checkpt_page_seq   = 0;
    dev->checkpt_cur_chunk  = -1;
    dev->checkpt_sum        = 0;
    dev->checkpt_xor        = 0;

    /* 1. Validity header */
    memset(&val, 0, sizeof(val));
    val.version = TFS_CHECKPT_VERSION;
    val.seq     = dev->seq_number;
    rc = wr_bytes(dev, &val, sizeof(val));
    if (rc != TFS_OK) return rc;

    /* 2. Device state */
    memset(&cdev, 0, sizeof(cdev));
    cdev.n_erased_blocks  = (uint32_t)dev->n_erased_blocks;
    cdev.alloc_block      = (uint32_t)dev->alloc_block;
    cdev.alloc_page       = (uint32_t)dev->alloc_page;
    cdev.n_free_chunks    = (uint32_t)dev->n_free_chunks;
    cdev.seq_number       = dev->seq_number;
    cdev.oldest_dirty_seq = dev->oldest_dirty_seq;
    cdev.n_deleted_files  = (uint32_t)dev->n_deleted_files;
    cdev.n_unlinked_files = (uint32_t)dev->n_unlinked_files;
    rc = wr_bytes(dev, &cdev, sizeof(cdev));
    if (rc != TFS_OK) return rc;

    /* 3. Block info */
    for (blk = dev->internal_start_block; blk <= dev->internal_end_block; blk++) {
        tfs_block_info_t *bi = tfs_get_block_info(dev, (int)blk);
        rc = wr_u32(dev, bi->as_u32[0]);
        if (rc != TFS_OK) return rc;
        rc = wr_u32(dev, bi->as_u32[1]);
        if (rc != TFS_OK) return rc;
    }

    /* 4. Objects */
    for (i = 0; i < TFS_OBJ_BUCKETS; i++) {
        tfs_obj_t *obj;
        tfs_list_for_each_entry(obj, &dev->obj_bucket[i].list, hash_link) {
            if (!obj->fake) {
                rc = write_obj_record(dev, obj);
                if (rc != TFS_OK) return rc;
            }
        }
    }

    /* Terminator */
    {
        tfs_checkpt_obj_t term;
        memset(&term, 0, sizeof(term));
        rc = wr_bytes(dev, &term, sizeof(term));
        if (rc != TFS_OK) return rc;
    }

    /* 5. File chunk mappings */
    for (i = 0; i < TFS_OBJ_BUCKETS; i++) {
        tfs_obj_t *obj;
        tfs_list_for_each_entry(obj, &dev->obj_bucket[i].list, hash_link) {
            if (!obj->fake) {
                rc = write_obj_chunks(dev, obj);
                if (rc != TFS_OK) return rc;
            }
        }
    }

    /* Chunk mapping terminator */
    {
        tfs_checkpt_chunk_t term;
        memset(&term, 0, sizeof(term));
        rc = wr_bytes(dev, &term, sizeof(term));
        if (rc != TFS_OK) return rc;
    }

    /* Flush final partial chunk */
    rc = wr_flush(dev);
    if (rc != TFS_OK) return rc;

    if (dev->checkpt_cur_chunk >= 0) {
        rc = tfs_checkpoint_anchor_write(dev->drv.ctx,
                                         (uint32_t)dev->checkpt_cur_chunk,
                                         val.seq);
        if (rc != TFS_OK && rc != TFS_EINVAL)
            return rc;
    }

    dev->is_checkpointed = 1;
    return TFS_OK;
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

    dev->checkpt_has_tnodes = 0;

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
        free_from_blocks += cpb - (int)bi->bi.pages_in_use;
        if (bi->bi.pages_in_use == 0)
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

        if (orec.type == TFS_OBJ_TYPE_FILE) {
            obj->var.file.stored_size =
                (tfs_off_t)orec.file_size_hi << 32 | orec.file_size_lo;
            obj->var.file.file_size   = obj->var.file.stored_size;
        }

        obj->valid = 1;
        tfs_obj_insert(dev, obj);
        if (obj->hdr_chunk >= 0)
            mark_restored_chunk_used(dev, (uint32_t)obj->hdr_chunk);

        /* Re-wire parent link after all objects are loaded */
        (void)orec.parent_id;  /* wired in tfs_core post-scan pass */
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

    /* The cdev record saved alloc_page BEFORE checkpoint chunks were written.
     * Advance past any checkpoint chunks that now occupy those pages. */
    fixup_alloc_after_checkpt(dev);

    return TFS_OK;
}

/*===================================================================
 *  Erase checkpoint blocks
 *===================================================================*/

void tfs_checkpt_erase(tfs_dev_t *dev)
{
    int blk;

    for (blk = (int)dev->internal_start_block;
         blk <= (int)dev->internal_end_block;
         blk++) {

        if (tfs_block_get_state(dev, blk) == TFS_BLK_STATE_CHECKPOINT)
            tfs_block_erase(dev, blk);
    }
    dev->is_checkpointed = 0;
}
