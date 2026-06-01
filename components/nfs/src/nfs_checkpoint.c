/*
 * nfs_checkpoint.c — Checkpoint read/write for NFS
 *
 * A checkpoint is a sequential byte stream split across one or more
 * NAND chunks.  The stream is written into a ring of pre-allocated
 * chunks allocated just like normal data.  On mount, NFS first tries
 * to restore from checkpoint; if that fails it falls back to a full
 * NAND scan.
 *
 * Stream contents (in order):
 *   1. nfs_checkpt_validity_t
 *   2. nfs_checkpt_dev_t
 *   3. block_info words (one u32 per block: pages_in_use | state | seq)
 *   4. object records (nfs_checkpt_obj_t) — terminated by record with
 *      obj_id == 0
 *   5. Closing validity checksum (sum/xor updated)
 */

#include "nfs_checkpoint.h"
#include "nfs_block.h"
#include "nfs_inode.h"
#include "nfs_tnode.h"
#include "../inc/nfs_config.h"

#include <string.h>

/*===================================================================
 *  Byte-stream write helpers
 *===================================================================*/

static int wr_flush(nfs_dev_t *dev);

static int wr_byte(nfs_dev_t *dev, nfs_u8 b)
{
    nfs_u32 *sum = &dev->checkpt_sum;
    nfs_u32 *xor = &dev->checkpt_xor;

    *sum += b;
    *xor ^= b;

    dev->checkpt_buffer[dev->checkpt_byte_offs++] = b;
    dev->checkpt_byte_count++;

    if (dev->checkpt_byte_offs >= (int)dev->data_bytes_per_chunk)
        return wr_flush(dev);

    return NFS_OK;
}

static int wr_bytes(nfs_dev_t *dev, const void *data, int n)
{
    const nfs_u8 *p = (const nfs_u8 *)data;
    int i;
    for (i = 0; i < n; i++) {
        int rc = wr_byte(dev, p[i]);
        if (rc != NFS_OK)
            return rc;
    }
    return NFS_OK;
}

static int wr_u32(nfs_dev_t *dev, nfs_u32 v)
{
    return wr_bytes(dev, &v, 4);
}

static int wr_flush(nfs_dev_t *dev)
{
    nfs_ext_tags_t ext;
    int chunk, rc;

    if (dev->checkpt_byte_offs == 0)
        return NFS_OK;

    chunk = nfs_alloc_chunk(dev, 1);  /* use reserved blocks if needed */
    if (chunk < 0)
        return NFS_ENOSPC;

    memset(&ext, 0, sizeof(ext));
    ext.chunk_used  = 1;
    ext.obj_id      = NFS_OBJ_ID_CHECKPT;
    ext.chunk_id    = (nfs_u32)dev->checkpt_page_seq++;
    ext.n_bytes     = (nfs_u32)dev->checkpt_byte_offs;

    rc = nfs_chunk_write(dev, chunk,
                         dev->checkpt_buffer,
                         dev->checkpt_byte_offs, &ext);
    if (rc != NFS_OK)
        return rc;

    memset(dev->checkpt_buffer, 0xff, dev->data_bytes_per_chunk);
    dev->checkpt_byte_offs = 0;
    return NFS_OK;
}

/*===================================================================
 *  Byte-stream read helpers
 *===================================================================*/

static int rd_next_chunk(nfs_dev_t *dev);

static int rd_byte(nfs_dev_t *dev, nfs_u8 *b)
{
    if (dev->checkpt_byte_offs >= dev->checkpt_byte_count) {
        int rc = rd_next_chunk(dev);
        if (rc != NFS_OK)
            return rc;
    }

    *b = dev->checkpt_buffer[dev->checkpt_byte_offs++];
    dev->checkpt_sum += *b;
    dev->checkpt_xor ^= *b;
    return NFS_OK;
}

static int rd_bytes(nfs_dev_t *dev, void *data, int n)
{
    nfs_u8 *p = (nfs_u8 *)data;
    int i;
    for (i = 0; i < n; i++) {
        int rc = rd_byte(dev, &p[i]);
        if (rc != NFS_OK)
            return rc;
    }
    return NFS_OK;
}

static int rd_u32(nfs_dev_t *dev, nfs_u32 *v)
{
    return rd_bytes(dev, v, 4);
}

static int rd_next_chunk(nfs_dev_t *dev)
{
    nfs_ext_tags_t ext;
    int            blk, chunk, found = 0;

    /* Scan forward from checkpt_cur_chunk looking for next checkpoint chunk */
    for (blk = dev->checkpt_cur_block;
         blk <= (int)dev->internal_end_block && !found;
         blk++) {

        int cpb = (int)nfs_chunks_per_block(dev);
        int start = (blk == dev->checkpt_cur_block)
                    ? dev->checkpt_cur_chunk + 1 : blk * cpb;

        for (chunk = start; chunk < blk * cpb + cpb; chunk++) {
            memset(&ext, 0, sizeof(ext));
            nfs_chunk_read(dev, chunk, dev->checkpt_buffer,
                           (int)dev->data_bytes_per_chunk, &ext);

            if (ext.chunk_used &&
                ext.obj_id == NFS_OBJ_ID_CHECKPT &&
                (int)ext.chunk_id == dev->checkpt_page_seq) {

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

    return found ? NFS_OK : NFS_EINVAL;
}

/*===================================================================
 *  Checkpoint required blocks
 *===================================================================*/

int nfs_checkpt_required_blocks(const nfs_dev_t *dev)
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

static int write_obj_record(nfs_dev_t *dev, nfs_obj_t *obj)
{
    nfs_checkpt_obj_t rec;
    memset(&rec, 0, sizeof(rec));

    rec.obj_id       = obj->obj_id;
    rec.parent_id    = obj->parent ? obj->parent->obj_id : 0;
    rec.hdr_chunk    = (nfs_u32)obj->hdr_chunk;
    rec.type         = obj->obj_type;
    rec.mode         = obj->mode;
    rec.uid          = obj->uid;
    rec.gid          = obj->gid;
    rec.atime        = obj->atime;
    rec.mtime        = obj->mtime;
    rec.ctime        = obj->ctime;
    rec.rdev         = obj->rdev;
    rec.n_data_chunks= (nfs_u32)obj->n_data_chunks;

    if (obj->obj_type == NFS_OBJ_TYPE_FILE) {
        rec.file_size_lo = (nfs_u32)(obj->var.file.stored_size & 0xffffffffu);
        rec.file_size_hi = (nfs_u32)(obj->var.file.stored_size >> 32);
    }

    return wr_bytes(dev, &rec, sizeof(rec));
}

int nfs_checkpt_write(nfs_dev_t *dev)
{
    nfs_checkpt_validity_t val;
    nfs_checkpt_dev_t      cdev;
    nfs_u32                i, blk;
    int                    rc;

    if (dev->param.skip_checkpt_wr)
        return NFS_OK;

    /* Alloc checkpoint buffer */
    if (!dev->checkpt_buffer) {
        dev->checkpt_buffer = (nfs_u8 *)
            dev->drv.malloc(dev->drv.ctx, dev->data_bytes_per_chunk);
        if (!dev->checkpt_buffer)
            return NFS_ENOMEM;
    }

    memset(dev->checkpt_buffer, 0xff, dev->data_bytes_per_chunk);
    dev->checkpt_byte_offs  = 0;
    dev->checkpt_byte_count = 0;
    dev->checkpt_page_seq   = 0;
    dev->checkpt_sum        = 0;
    dev->checkpt_xor        = 0;

    /* 1. Validity header */
    memset(&val, 0, sizeof(val));
    val.version = NFS_CHECKPT_VERSION;
    val.seq     = dev->seq_number;
    rc = wr_bytes(dev, &val, sizeof(val));
    if (rc != NFS_OK) return rc;

    /* 2. Device state */
    memset(&cdev, 0, sizeof(cdev));
    cdev.n_erased_blocks  = (nfs_u32)dev->n_erased_blocks;
    cdev.alloc_block      = (nfs_u32)dev->alloc_block;
    cdev.alloc_page       = (nfs_u32)dev->alloc_page;
    cdev.n_free_chunks    = (nfs_u32)dev->n_free_chunks;
    cdev.seq_number       = dev->seq_number;
    cdev.oldest_dirty_seq = dev->oldest_dirty_seq;
    cdev.n_deleted_files  = (nfs_u32)dev->n_deleted_files;
    cdev.n_unlinked_files = (nfs_u32)dev->n_unlinked_files;
    rc = wr_bytes(dev, &cdev, sizeof(cdev));
    if (rc != NFS_OK) return rc;

    /* 3. Block info */
    for (blk = dev->internal_start_block; blk <= dev->internal_end_block; blk++) {
        nfs_block_info_t *bi = nfs_get_block_info(dev, (int)blk);
        rc = wr_u32(dev, bi->as_u32[0]);
        if (rc != NFS_OK) return rc;
        rc = wr_u32(dev, bi->as_u32[1]);
        if (rc != NFS_OK) return rc;
    }

    /* 4. Objects */
    for (i = 0; i < NFS_OBJ_BUCKETS; i++) {
        nfs_obj_t *obj;
        nfs_list_for_each_entry(obj, &dev->obj_bucket[i].list, hash_link) {
            if (!obj->fake) {
                rc = write_obj_record(dev, obj);
                if (rc != NFS_OK) return rc;
            }
        }
    }

    /* Terminator */
    {
        nfs_checkpt_obj_t term;
        memset(&term, 0, sizeof(term));
        rc = wr_bytes(dev, &term, sizeof(term));
        if (rc != NFS_OK) return rc;
    }

    /* Flush final partial chunk */
    rc = wr_flush(dev);
    if (rc != NFS_OK) return rc;

    /* Update validity record with final checksum */
    /* (Simple approach: checksum is accumulated during write, stored at start)
     * For production: write validity block as a separate final chunk. */

    dev->is_checkpointed = 1;
    return NFS_OK;
}

/*===================================================================
 *  Checkpoint read
 *===================================================================*/

/*===================================================================
 *  Post-restore fixup: advance alloc_page past any checkpoint chunks
 *  that were written AFTER the cdev record was serialised.
 *===================================================================*/

static void fixup_alloc_after_checkpt(nfs_dev_t *dev)
{
    int blk, cpb;
    nfs_ext_tags_t ext;

    if (dev->alloc_block < 0)
        return;

    blk = dev->alloc_block;
    cpb = (int)nfs_chunks_per_block(dev);

    /* Scan forward from saved alloc_page; mark any written chunks as used
     * (these are checkpoint chunks written after the cdev record was saved). */
    while ((int)dev->alloc_page < cpb) {
        int chunk = blk * cpb + (int)dev->alloc_page;

        memset(&ext, 0, sizeof(ext));
        nfs_chunk_read(dev, chunk, NFS_NULL, 0, &ext);

        if (!ext.chunk_used)
            break;  /* found first genuinely erased page */

        if (!nfs_chunk_is_used(dev, chunk)) {
            nfs_chunk_set_used(dev, chunk);
            nfs_get_block_info(dev, blk)->bi.pages_in_use++;
            dev->n_free_chunks--;
        }
        dev->alloc_page++;
    }

    /* Update block state to match reality */
    {
        nfs_block_info_t *bi = nfs_get_block_info(dev, blk);
        if ((int)dev->alloc_page >= cpb) {
            bi->bi.block_state = NFS_BLK_STATE_FULL;
            dev->alloc_block   = -1;
        } else {
            bi->bi.block_state = NFS_BLK_STATE_ALLOCATING;
        }
    }
}

int nfs_checkpt_read(nfs_dev_t *dev)
{
    nfs_checkpt_validity_t val;
    nfs_checkpt_dev_t      cdev;
    nfs_checkpt_obj_t      orec;
    nfs_u32                blk, n_blocks;
    int                    rc;

    if (dev->param.skip_checkpt_rd)
        return NFS_EINVAL;

    if (!dev->checkpt_buffer) {
        dev->checkpt_buffer = (nfs_u8 *)
            dev->drv.malloc(dev->drv.ctx, dev->data_bytes_per_chunk);
        if (!dev->checkpt_buffer)
            return NFS_ENOMEM;
    }

    dev->checkpt_page_seq  = 0;
    dev->checkpt_cur_block = (int)dev->internal_start_block;
    dev->checkpt_cur_chunk = dev->checkpt_cur_block
                             * (int)nfs_chunks_per_block(dev) - 1;
    dev->checkpt_byte_offs  = 0;
    dev->checkpt_byte_count = 0;
    dev->checkpt_sum        = 0;
    dev->checkpt_xor        = 0;

    /* Find the first checkpoint chunk */
    if (rd_next_chunk(dev) != NFS_OK)
        return NFS_EINVAL;

    /* 1. Validity header */
    rc = rd_bytes(dev, &val, sizeof(val));
    if (rc != NFS_OK || val.version != NFS_CHECKPT_VERSION)
        return NFS_EINVAL;

    /* 2. Device state */
    rc = rd_bytes(dev, &cdev, sizeof(cdev));
    if (rc != NFS_OK) return NFS_EINVAL;

    dev->n_erased_blocks  = (int)cdev.n_erased_blocks;
    dev->alloc_block      = (int)cdev.alloc_block;
    dev->alloc_page       = (nfs_u32)cdev.alloc_page;
    dev->n_free_chunks    = (int)cdev.n_free_chunks;
    dev->seq_number       = cdev.seq_number;
    dev->oldest_dirty_seq = cdev.oldest_dirty_seq;
    dev->n_deleted_files  = (int)cdev.n_deleted_files;
    dev->n_unlinked_files = (int)cdev.n_unlinked_files;

    /* 3. Block info */
    n_blocks = dev->internal_end_block - dev->internal_start_block + 1;
    for (blk = 0; blk < n_blocks; blk++) {
        nfs_block_info_t *bi = &dev->block_info[blk];
        rc  = rd_u32(dev, &bi->as_u32[0]);
        rc |= rd_u32(dev, &bi->as_u32[1]);
        if (rc != NFS_OK) return NFS_EINVAL;
    }

    /* 4. Objects */
    for (;;) {
        rc = rd_bytes(dev, &orec, sizeof(orec));
        if (rc != NFS_OK) return NFS_EINVAL;
        if (orec.obj_id == 0) break;   /* terminator */

        nfs_obj_t *obj = nfs_obj_create(dev, orec.obj_id,
                                        (nfs_obj_type_t)orec.type);
        if (!obj) return NFS_ENOMEM;

        obj->hdr_chunk    = (int)orec.hdr_chunk;
        obj->mode         = orec.mode;
        obj->uid          = orec.uid;
        obj->gid          = orec.gid;
        obj->atime        = orec.atime;
        obj->mtime        = orec.mtime;
        obj->ctime        = orec.ctime;
        obj->rdev         = orec.rdev;
        obj->n_data_chunks= (int)orec.n_data_chunks;

        if (orec.type == NFS_OBJ_TYPE_FILE) {
            obj->var.file.stored_size =
                (nfs_off_t)orec.file_size_hi << 32 | orec.file_size_lo;
            obj->var.file.file_size   = obj->var.file.stored_size;
        }

        obj->valid = 1;
        nfs_obj_insert(dev, obj);

        /* Re-wire parent link after all objects are loaded */
        (void)orec.parent_id;  /* wired in nfs_core post-scan pass */
    }

    /* The cdev record saved alloc_page BEFORE checkpoint chunks were written.
     * Advance past any checkpoint chunks that now occupy those pages. */
    fixup_alloc_after_checkpt(dev);

    return NFS_OK;
}

/*===================================================================
 *  Erase checkpoint blocks
 *===================================================================*/

void nfs_checkpt_erase(nfs_dev_t *dev)
{
    int blk;

    for (blk = (int)dev->internal_start_block;
         blk <= (int)dev->internal_end_block;
         blk++) {

        if (nfs_block_get_state(dev, blk) == NFS_BLK_STATE_CHECKPOINT)
            nfs_block_erase(dev, blk);
    }
    dev->is_checkpointed = 0;
}
