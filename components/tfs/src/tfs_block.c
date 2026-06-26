/*
 * tfs_block.c — Block-level management for TFS
 *
 * Manages the in-RAM chunk bitmap and block-info array; wraps all
 * driver-level page read/write/erase calls with bookkeeping.
 */

#include "tfs_block.h"
#include "../inc/tfs_config.h"

#include <string.h>

/*===================================================================
 *  Internal helpers
 *===================================================================*/

/* Convert absolute chunk number to (block, page-within-block) */
static inline int chunk_to_block(const tfs_dev_t *dev, int chunk)
{
    return chunk / (int)tfs_chunks_per_block(dev);
}
static inline int chunk_to_page(const tfs_dev_t *dev, int chunk)
{
    return chunk % (int)tfs_chunks_per_block(dev);
}

/* Translate external block number to internal block index */
static inline int block_ext_to_int(const tfs_dev_t *dev, int b)
{
    return b - dev->block_offset;
}
static inline int block_int_to_ext(const tfs_dev_t *dev, int b)
{
    return b + dev->block_offset;
}

/*===================================================================
 *  Chunk bitmap
 *===================================================================*/

static inline void chunk_bitmap_byte_bit(const tfs_dev_t *dev,
                                         int chunk_in_nand,
                                         int *byte_idx, uint8_t *bit_mask)
{
    int cpb   = (int)tfs_chunks_per_block(dev);
    int blk   = block_ext_to_int(dev, chunk_in_nand / cpb);
    int page  = chunk_in_nand % cpb;

    *byte_idx = blk * dev->chunk_bit_stride + (page >> 3);
    *bit_mask = (uint8_t)(1u << (page & 7));
}

void tfs_chunk_set_used(tfs_dev_t *dev, int chunk_in_nand)
{
    int     byte_idx;
    uint8_t  bit_mask;
    chunk_bitmap_byte_bit(dev, chunk_in_nand, &byte_idx, &bit_mask);
    dev->chunk_bits[byte_idx] |= bit_mask;
}

void tfs_chunk_set_free(tfs_dev_t *dev, int chunk_in_nand)
{
    int     byte_idx;
    uint8_t  bit_mask;
    chunk_bitmap_byte_bit(dev, chunk_in_nand, &byte_idx, &bit_mask);
    dev->chunk_bits[byte_idx] &= (uint8_t)~bit_mask;
}

int tfs_chunk_is_used(const tfs_dev_t *dev, int chunk_in_nand)
{
    int     byte_idx;
    uint8_t  bit_mask;
    chunk_bitmap_byte_bit(dev, chunk_in_nand, &byte_idx, &bit_mask);
    return (dev->chunk_bits[byte_idx] & bit_mask) != 0;
}

/*===================================================================
 *  Block erase
 *===================================================================*/

int tfs_block_erase(tfs_dev_t *dev, int block_in_nand)
{
    tfs_block_info_t *bi = tfs_get_block_info(dev, block_in_nand);
    int               rc;

    rc = dev->drv.erase_block(dev->drv.ctx, block_in_nand);
    dev->n_erasures++;

    if (rc != TFS_OK) {
        dev->n_erase_failures++;
        tfs_block_mark_bad(dev, block_in_nand);
        return TFS_EFLASH;
    }

    /* Reset block info */
    bi->bi.pages_in_use    = 0;
    bi->bi.soft_del_pages  = 0;
    bi->bi.block_state     = TFS_BLK_STATE_EMPTY;
    bi->bi.seq_number      = 0;
    bi->bi.gc_prioritise   = 0;
    bi->bi.has_summary     = 0;
    bi->bi.has_shrink_hdr  = 0;
    bi->bi.needs_retiring  = 0;
    bi->bi.skip_erased_chk = 0;
    bi->bi.ecc_strikes     = 0;

    /* Clear chunk bitmap for this block */
    {
        int blk_int = block_ext_to_int(dev, block_in_nand);
        memset(dev->chunk_bits + blk_int * dev->chunk_bit_stride,
               0, (size_t)dev->chunk_bit_stride);
    }

    dev->n_erased_blocks++;
    return TFS_OK;
}

/*===================================================================
 *  Bad block
 *===================================================================*/

void tfs_block_mark_bad(tfs_dev_t *dev, int block_in_nand)
{
    tfs_block_info_t *bi = tfs_get_block_info(dev, block_in_nand);

    bi->bi.block_state = TFS_BLK_STATE_DEAD;

    if (dev->param.disable_bad_block_marking)
        return;

    dev->drv.mark_bad(dev->drv.ctx, block_in_nand);
    dev->n_retired_blocks++;
}

void tfs_block_retire(tfs_dev_t *dev, int block_in_nand)
{
    tfs_block_info_t *bi = tfs_get_block_info(dev, block_in_nand);
    bi->bi.needs_retiring = 1;
}

/*===================================================================
 *  Block state
 *===================================================================*/

int tfs_block_is_erased(const tfs_dev_t *dev, int block_in_nand)
{
    return tfs_get_block_info(dev, block_in_nand)->bi.block_state
           == TFS_BLK_STATE_EMPTY;
}

int tfs_block_is_bad(const tfs_dev_t *dev, int block_in_nand)
{
    return tfs_get_block_info(dev, block_in_nand)->bi.block_state
           == TFS_BLK_STATE_DEAD;
}

void tfs_block_set_state(tfs_dev_t *dev, int block_in_nand,
                         tfs_block_state_t state)
{
    tfs_get_block_info(dev, block_in_nand)->bi.block_state = (uint32_t)state;
}

tfs_block_state_t tfs_block_get_state(const tfs_dev_t *dev,
                                      int block_in_nand)
{
    return (tfs_block_state_t)
           tfs_get_block_info(dev, block_in_nand)->bi.block_state;
}

/*===================================================================
 *  Chunk allocation
 *===================================================================*/

int tfs_alloc_chunk(tfs_dev_t *dev, int use_resvd)
{
    int   blk, page, chunk;
    int   reserved = use_resvd ? 0 : TFS_CFG_RESERVED_BLOCKS;

    /* Try current alloc block first */
    if (dev->alloc_block >= 0) {
        tfs_block_info_t *bi = tfs_get_block_info(dev, dev->alloc_block);
        if (bi->bi.block_state == TFS_BLK_STATE_ALLOCATING &&
            (int)dev->alloc_page < (int)tfs_chunks_per_block(dev)) {

            chunk = dev->alloc_block * (int)tfs_chunks_per_block(dev)
                    + (int)dev->alloc_page;
            dev->alloc_page++;
            return chunk;
        }
        /* Block is full */
        dev->alloc_block = -1;
    }

    /* Find a new erased block */
    if (dev->n_erased_blocks <= reserved)
        return -1;

    for (blk = dev->alloc_block_finder;
         blk <= (int)dev->internal_end_block;
         blk++) {

        tfs_block_info_t *bi = tfs_get_block_info(dev, blk);
        if (bi->bi.block_state == TFS_BLK_STATE_EMPTY) {
            bi->bi.block_state = TFS_BLK_STATE_ALLOCATING;
            bi->bi.seq_number  = dev->seq_number++;

            dev->alloc_block       = blk;
            dev->alloc_page        = 1;
            dev->alloc_block_finder= blk + 1;
            dev->n_erased_blocks--;

            page  = 0;
            chunk = blk * (int)tfs_chunks_per_block(dev) + page;
            return chunk;
        }
    }

    /* Wrap around */
    dev->alloc_block_finder = (int)dev->internal_start_block;
    for (blk = (int)dev->internal_start_block;
         blk <= (int)dev->internal_end_block;
         blk++) {

        tfs_block_info_t *bi = tfs_get_block_info(dev, blk);
        if (bi->bi.block_state == TFS_BLK_STATE_EMPTY) {
            bi->bi.block_state = TFS_BLK_STATE_ALLOCATING;
            bi->bi.seq_number  = dev->seq_number++;

            dev->alloc_block       = blk;
            dev->alloc_page        = 1;
            dev->alloc_block_finder= blk + 1;
            dev->n_erased_blocks--;

            page  = 0;
            chunk = blk * (int)tfs_chunks_per_block(dev) + page;
            return chunk;
        }
    }

    return -1;  /* no erased block available */
}

/*===================================================================
 *  Chunk I/O
 *===================================================================*/

int tfs_chunk_write(tfs_dev_t *dev, int chunk_in_nand,
                    const uint8_t *data, int n_bytes,
                    tfs_ext_tags_t *ext)
{
    tfs_packed_tags2_t pt;
    tfs_block_info_t  *bi;
    int                blk, rc;

    ext->seq_number = tfs_get_block_info(dev,
                           chunk_to_block(dev, chunk_in_nand))->bi.seq_number;

    tfs_tags_pack(dev, ext, &pt);

    if (dev->param.inband_tags) {
        /* Assemble a full physical page: [user data | packed_tags] */
        uint32_t phys_sz = dev->param.geo.data_bytes_per_chunk;
        uint8_t *ibuf    = dev->inband_buf;

        memset(ibuf, 0xff, phys_sz);
        if (data && n_bytes > 0) {
            uint32_t copy = ((uint32_t)n_bytes < dev->data_bytes_per_chunk)
                           ? (uint32_t)n_bytes : dev->data_bytes_per_chunk;
            memcpy(ibuf, data, copy);
        }
        memcpy(ibuf + dev->data_bytes_per_chunk, &pt, sizeof(pt));

        rc = dev->drv.write_page(dev->drv.ctx, chunk_in_nand,
                                 ibuf, phys_sz, NULL, 0);
    } else {
        rc = dev->drv.write_page(dev->drv.ctx,
                                 chunk_in_nand,
                                 data,
                                 (uint32_t)n_bytes,
                                 (const uint8_t *)&pt,
                                 sizeof(pt));
    }
    dev->n_page_writes++;

    if (rc != TFS_OK) {
        int failed_blk = chunk_to_block(dev, chunk_in_nand);

        dev->n_retried_writes++;
        tfs_block_mark_bad(dev, failed_blk);
        if (dev->alloc_block == failed_blk)
            dev->alloc_block = -1;
        return TFS_EFLASH;
    }

    /* Bookkeeping */
    tfs_chunk_set_used(dev, chunk_in_nand);
    blk = chunk_to_block(dev, chunk_in_nand);
    bi  = tfs_get_block_info(dev, blk);
    bi->bi.pages_in_use++;
    dev->n_free_chunks--;

    return TFS_OK;
}

int tfs_chunk_read(tfs_dev_t *dev, int chunk_in_nand,
                   uint8_t *data, int n_bytes,
                   tfs_ext_tags_t *ext)
{
    tfs_packed_tags2_t pt;
    int                rc;

    memset(&pt, 0xff, sizeof(pt));
    if (ext)
        memset(ext, 0, sizeof(*ext));

    if (dev->param.inband_tags) {
        /* Read full physical page; extract tags from tail */
        uint32_t phys_sz = dev->param.geo.data_bytes_per_chunk;
        uint8_t *ibuf    = dev->inband_buf;

        memset(ibuf, 0xff, phys_sz);
        rc = dev->drv.read_page(dev->drv.ctx, chunk_in_nand,
                                ibuf, phys_sz, NULL, 0);

        if (rc != TFS_OK && rc != TFS_EECCFIXED) {
            if (data && n_bytes > 0) {
                uint32_t copy = ((uint32_t)n_bytes < dev->data_bytes_per_chunk)
                               ? (uint32_t)n_bytes : dev->data_bytes_per_chunk;
                memset(data, 0xff, copy);
            }
            dev->n_page_reads++;
            if (rc == TFS_EECCUNFIXED)
                dev->n_ecc_unfixed++;
            return rc;
        }

        if (data && n_bytes > 0) {
            uint32_t copy = ((uint32_t)n_bytes < dev->data_bytes_per_chunk)
                           ? (uint32_t)n_bytes : dev->data_bytes_per_chunk;
            memcpy(data, ibuf, copy);
        }
        memcpy(&pt, ibuf + dev->data_bytes_per_chunk, sizeof(pt));
    } else {
        rc = dev->drv.read_page(dev->drv.ctx, chunk_in_nand,
                                data, (uint32_t)n_bytes,
                                (uint8_t *)&pt, sizeof(pt));
        if (rc != TFS_OK && rc != TFS_EECCFIXED) {
            if (data && n_bytes > 0)
                memset(data, 0xff, (uint32_t)n_bytes);
            dev->n_page_reads++;
            if (rc == TFS_EECCUNFIXED)
                dev->n_ecc_unfixed++;
            return rc;
        }
    }
    dev->n_page_reads++;

    if (rc == TFS_EECCFIXED)
        dev->n_ecc_fixed++;
    else if (rc == TFS_EECCUNFIXED)
        dev->n_ecc_unfixed++;

    if (ext) {
        tfs_ecc_result_t tags_ecc = tfs_tags_verify_ecc(&pt,
                                        dev->param.no_tags_ecc);
        tfs_tags_unpack(dev, &pt, ext);
        ext->ecc_result = tags_ecc;

        if (tags_ecc == TFS_ECC_RESULT_FIXED)
            dev->n_tags_ecc_fixed++;
        else if (tags_ecc == TFS_ECC_RESULT_UNFIXED)
            dev->n_tags_ecc_unfixed++;
    }

    if (rc == TFS_EECCUNFIXED)
        return TFS_EECCUNFIXED;

    return TFS_OK;
}

void tfs_chunk_delete(tfs_dev_t *dev, int chunk_in_nand,
                      int mark_flash)
{
    tfs_block_info_t *bi;
    int               blk;

    blk = chunk_to_block(dev, chunk_in_nand);
    bi  = tfs_get_block_info(dev, blk);

    tfs_chunk_set_free(dev, chunk_in_nand);
    bi->bi.soft_del_pages++;
    dev->n_free_chunks++;

    (void)mark_flash;  /* NAND pages cannot be overwritten; erase entire block */
}

/*===================================================================
 *  Init / free
 *===================================================================*/

int tfs_block_init_arrays(tfs_dev_t *dev)
{
    uint32_t n_blocks    = tfs_total_blocks(dev);
    uint32_t cpb         = tfs_chunks_per_block(dev);
    uint32_t stride      = (cpb + 7u) / 8u;
    uint32_t bitmap_size = n_blocks * stride;

    dev->chunk_bit_stride = (int)stride;

    dev->block_info = (tfs_block_info_t *)
                      dev->drv.malloc(dev->drv.ctx,
                                      n_blocks * sizeof(tfs_block_info_t));
    if (!dev->block_info)
        return TFS_ENOMEM;

    dev->chunk_bits = (uint8_t *)dev->drv.malloc(dev->drv.ctx, bitmap_size);
    if (!dev->chunk_bits) {
        dev->drv.free(dev->drv.ctx, dev->block_info);
        dev->block_info = NULL;
        return TFS_ENOMEM;
    }

    memset(dev->block_info, 0, n_blocks * sizeof(tfs_block_info_t));
    memset(dev->chunk_bits, 0, bitmap_size);

    /* Allocate inband staging buffer if needed */
    if (dev->param.inband_tags) {
        dev->inband_buf = (uint8_t *)
            dev->drv.malloc(dev->drv.ctx,
                            dev->param.geo.data_bytes_per_chunk);
        if (!dev->inband_buf) {
            dev->drv.free(dev->drv.ctx, dev->chunk_bits);
            dev->chunk_bits = NULL;
            dev->drv.free(dev->drv.ctx, dev->block_info);
            dev->block_info = NULL;
            return TFS_ENOMEM;
        }
    }

    return TFS_OK;
}

void tfs_block_free_arrays(tfs_dev_t *dev)
{
    if (dev->inband_buf) {
        dev->drv.free(dev->drv.ctx, dev->inband_buf);
        dev->inband_buf = NULL;
    }
    if (dev->block_info) {
        dev->drv.free(dev->drv.ctx, dev->block_info);
        dev->block_info = NULL;
    }
    if (dev->chunk_bits) {
        dev->drv.free(dev->drv.ctx, dev->chunk_bits);
        dev->chunk_bits = NULL;
    }
}
