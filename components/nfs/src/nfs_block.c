/*
 * nfs_block.c — Block-level management for NFS
 *
 * Manages the in-RAM chunk bitmap and block-info array; wraps all
 * driver-level page read/write/erase calls with bookkeeping.
 */

#include "nfs_block.h"
#include "../inc/nfs_config.h"

#include <string.h>

/*===================================================================
 *  Internal helpers
 *===================================================================*/

/* Convert absolute chunk number to (block, page-within-block) */
static inline int chunk_to_block(const nfs_dev_t *dev, int chunk)
{
    return chunk / (int)nfs_chunks_per_block(dev);
}
static inline int chunk_to_page(const nfs_dev_t *dev, int chunk)
{
    return chunk % (int)nfs_chunks_per_block(dev);
}

/* Translate external block number to internal block index */
static inline int block_ext_to_int(const nfs_dev_t *dev, int b)
{
    return b - dev->block_offset;
}
static inline int block_int_to_ext(const nfs_dev_t *dev, int b)
{
    return b + dev->block_offset;
}

/*===================================================================
 *  Chunk bitmap
 *===================================================================*/

static inline void chunk_bitmap_byte_bit(const nfs_dev_t *dev,
                                         int chunk_in_nand,
                                         int *byte_idx, nfs_u8 *bit_mask)
{
    int cpb   = (int)nfs_chunks_per_block(dev);
    int blk   = block_ext_to_int(dev, chunk_in_nand / cpb);
    int page  = chunk_in_nand % cpb;

    *byte_idx = blk * dev->chunk_bit_stride + (page >> 3);
    *bit_mask = (nfs_u8)(1u << (page & 7));
}

void nfs_chunk_set_used(nfs_dev_t *dev, int chunk_in_nand)
{
    int     byte_idx;
    nfs_u8  bit_mask;
    chunk_bitmap_byte_bit(dev, chunk_in_nand, &byte_idx, &bit_mask);
    dev->chunk_bits[byte_idx] |= bit_mask;
}

void nfs_chunk_set_free(nfs_dev_t *dev, int chunk_in_nand)
{
    int     byte_idx;
    nfs_u8  bit_mask;
    chunk_bitmap_byte_bit(dev, chunk_in_nand, &byte_idx, &bit_mask);
    dev->chunk_bits[byte_idx] &= (nfs_u8)~bit_mask;
}

int nfs_chunk_is_used(const nfs_dev_t *dev, int chunk_in_nand)
{
    int     byte_idx;
    nfs_u8  bit_mask;
    chunk_bitmap_byte_bit(dev, chunk_in_nand, &byte_idx, &bit_mask);
    return (dev->chunk_bits[byte_idx] & bit_mask) != 0;
}

/*===================================================================
 *  Block erase
 *===================================================================*/

int nfs_block_erase(nfs_dev_t *dev, int block_in_nand)
{
    nfs_block_info_t *bi = nfs_get_block_info(dev, block_in_nand);
    int               rc;

    rc = dev->drv.erase_block(dev->drv.ctx, block_in_nand);
    dev->n_erasures++;

    if (rc != NFS_OK) {
        dev->n_erase_failures++;
        nfs_block_mark_bad(dev, block_in_nand);
        return NFS_EFLASH;
    }

    /* Reset block info */
    bi->bi.pages_in_use    = 0;
    bi->bi.soft_del_pages  = 0;
    bi->bi.block_state     = NFS_BLK_STATE_EMPTY;
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
    return NFS_OK;
}

/*===================================================================
 *  Bad block
 *===================================================================*/

void nfs_block_mark_bad(nfs_dev_t *dev, int block_in_nand)
{
    nfs_block_info_t *bi = nfs_get_block_info(dev, block_in_nand);

    bi->bi.block_state = NFS_BLK_STATE_DEAD;

    if (dev->param.disable_bad_block_marking)
        return;

    dev->drv.mark_bad(dev->drv.ctx, block_in_nand);
    dev->n_retired_blocks++;
}

void nfs_block_retire(nfs_dev_t *dev, int block_in_nand)
{
    nfs_block_info_t *bi = nfs_get_block_info(dev, block_in_nand);
    bi->bi.needs_retiring = 1;
}

/*===================================================================
 *  Block state
 *===================================================================*/

int nfs_block_is_erased(const nfs_dev_t *dev, int block_in_nand)
{
    return nfs_get_block_info(dev, block_in_nand)->bi.block_state
           == NFS_BLK_STATE_EMPTY;
}

int nfs_block_is_bad(const nfs_dev_t *dev, int block_in_nand)
{
    return nfs_get_block_info(dev, block_in_nand)->bi.block_state
           == NFS_BLK_STATE_DEAD;
}

void nfs_block_set_state(nfs_dev_t *dev, int block_in_nand,
                         nfs_block_state_t state)
{
    nfs_get_block_info(dev, block_in_nand)->bi.block_state = (nfs_u32)state;
}

nfs_block_state_t nfs_block_get_state(const nfs_dev_t *dev,
                                      int block_in_nand)
{
    return (nfs_block_state_t)
           nfs_get_block_info(dev, block_in_nand)->bi.block_state;
}

/*===================================================================
 *  Chunk allocation
 *===================================================================*/

int nfs_alloc_chunk(nfs_dev_t *dev, int use_resvd)
{
    int   blk, page, chunk;
    int   reserved = use_resvd ? 0 : NFS_CFG_RESERVED_BLOCKS;

    /* Try current alloc block first */
    if (dev->alloc_block >= 0) {
        nfs_block_info_t *bi = nfs_get_block_info(dev, dev->alloc_block);
        if (bi->bi.block_state == NFS_BLK_STATE_ALLOCATING &&
            (int)dev->alloc_page < (int)nfs_chunks_per_block(dev)) {

            chunk = dev->alloc_block * (int)nfs_chunks_per_block(dev)
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

        nfs_block_info_t *bi = nfs_get_block_info(dev, blk);
        if (bi->bi.block_state == NFS_BLK_STATE_EMPTY) {
            bi->bi.block_state = NFS_BLK_STATE_ALLOCATING;
            bi->bi.seq_number  = dev->seq_number++;

            dev->alloc_block       = blk;
            dev->alloc_page        = 1;
            dev->alloc_block_finder= blk + 1;
            dev->n_erased_blocks--;

            page  = 0;
            chunk = blk * (int)nfs_chunks_per_block(dev) + page;
            return chunk;
        }
    }

    /* Wrap around */
    dev->alloc_block_finder = (int)dev->internal_start_block;
    for (blk = (int)dev->internal_start_block;
         blk <= (int)dev->internal_end_block;
         blk++) {

        nfs_block_info_t *bi = nfs_get_block_info(dev, blk);
        if (bi->bi.block_state == NFS_BLK_STATE_EMPTY) {
            bi->bi.block_state = NFS_BLK_STATE_ALLOCATING;
            bi->bi.seq_number  = dev->seq_number++;

            dev->alloc_block       = blk;
            dev->alloc_page        = 1;
            dev->alloc_block_finder= blk + 1;
            dev->n_erased_blocks--;

            page  = 0;
            chunk = blk * (int)nfs_chunks_per_block(dev) + page;
            return chunk;
        }
    }

    return -1;  /* no erased block available */
}

/*===================================================================
 *  Chunk I/O
 *===================================================================*/

int nfs_chunk_write(nfs_dev_t *dev, int chunk_in_nand,
                    const nfs_u8 *data, int n_bytes,
                    nfs_ext_tags_t *ext)
{
    nfs_packed_tags2_t pt;
    nfs_block_info_t  *bi;
    int                blk, rc;

    ext->seq_number = nfs_get_block_info(dev,
                           chunk_to_block(dev, chunk_in_nand))->bi.seq_number;

    nfs_tags_pack(dev, ext, &pt);

    if (dev->param.inband_tags) {
        /* Assemble a full physical page: [user data | packed_tags] */
        nfs_u32 phys_sz = dev->param.geo.data_bytes_per_chunk;
        nfs_u8 *ibuf    = dev->inband_buf;

        memset(ibuf, 0xff, phys_sz);
        if (data && n_bytes > 0) {
            nfs_u32 copy = ((nfs_u32)n_bytes < dev->data_bytes_per_chunk)
                           ? (nfs_u32)n_bytes : dev->data_bytes_per_chunk;
            memcpy(ibuf, data, copy);
        }
        memcpy(ibuf + dev->data_bytes_per_chunk, &pt, sizeof(pt));

        rc = dev->drv.write_page(dev->drv.ctx, chunk_in_nand,
                                 ibuf, phys_sz, NFS_NULL, 0);
    } else {
        rc = dev->drv.write_page(dev->drv.ctx,
                                 chunk_in_nand,
                                 data,
                                 (nfs_u32)n_bytes,
                                 (const nfs_u8 *)&pt,
                                 sizeof(pt));
    }
    dev->n_page_writes++;

    if (rc != NFS_OK) {
        dev->n_retried_writes++;
        return NFS_EFLASH;
    }

    /* Bookkeeping */
    nfs_chunk_set_used(dev, chunk_in_nand);
    blk = chunk_to_block(dev, chunk_in_nand);
    bi  = nfs_get_block_info(dev, blk);
    bi->bi.pages_in_use++;
    dev->n_free_chunks--;

    return NFS_OK;
}

int nfs_chunk_read(nfs_dev_t *dev, int chunk_in_nand,
                   nfs_u8 *data, int n_bytes,
                   nfs_ext_tags_t *ext)
{
    nfs_packed_tags2_t pt;
    int                rc;

    memset(&pt, 0xff, sizeof(pt));

    if (dev->param.inband_tags) {
        /* Read full physical page; extract tags from tail */
        nfs_u32 phys_sz = dev->param.geo.data_bytes_per_chunk;
        nfs_u8 *ibuf    = dev->inband_buf;

        rc = dev->drv.read_page(dev->drv.ctx, chunk_in_nand,
                                ibuf, phys_sz, NFS_NULL, 0);

        if (data && n_bytes > 0) {
            nfs_u32 copy = ((nfs_u32)n_bytes < dev->data_bytes_per_chunk)
                           ? (nfs_u32)n_bytes : dev->data_bytes_per_chunk;
            memcpy(data, ibuf, copy);
        }
        memcpy(&pt, ibuf + dev->data_bytes_per_chunk, sizeof(pt));
    } else {
        rc = dev->drv.read_page(dev->drv.ctx, chunk_in_nand,
                                data, (nfs_u32)n_bytes,
                                (nfs_u8 *)&pt, sizeof(pt));
    }
    dev->n_page_reads++;

    if (rc == NFS_EECCFIXED)
        dev->n_ecc_fixed++;
    else if (rc == NFS_EECCUNFIXED)
        dev->n_ecc_unfixed++;

    if (ext) {
        nfs_ecc_result_t tags_ecc = nfs_tags_verify_ecc(&pt,
                                        dev->param.no_tags_ecc);
        nfs_tags_unpack(dev, &pt, ext);
        ext->ecc_result = tags_ecc;

        if (tags_ecc == NFS_ECC_RESULT_FIXED)
            dev->n_tags_ecc_fixed++;
        else if (tags_ecc == NFS_ECC_RESULT_UNFIXED)
            dev->n_tags_ecc_unfixed++;
    }

    if (rc == NFS_EECCUNFIXED)
        return NFS_EECCUNFIXED;

    return NFS_OK;
}

void nfs_chunk_delete(nfs_dev_t *dev, int chunk_in_nand,
                      int mark_flash)
{
    nfs_block_info_t *bi;
    int               blk;

    blk = chunk_to_block(dev, chunk_in_nand);
    bi  = nfs_get_block_info(dev, blk);

    nfs_chunk_set_free(dev, chunk_in_nand);
    bi->bi.soft_del_pages++;
    dev->n_free_chunks++;

    (void)mark_flash;  /* NAND pages cannot be overwritten; erase entire block */
}

/*===================================================================
 *  Init / free
 *===================================================================*/

int nfs_block_init_arrays(nfs_dev_t *dev)
{
    nfs_u32 n_blocks    = nfs_total_blocks(dev);
    nfs_u32 cpb         = nfs_chunks_per_block(dev);
    nfs_u32 stride      = (cpb + 7u) / 8u;
    nfs_u32 bitmap_size = n_blocks * stride;

    dev->chunk_bit_stride = (int)stride;

    dev->block_info = (nfs_block_info_t *)
                      dev->drv.malloc(dev->drv.ctx,
                                      n_blocks * sizeof(nfs_block_info_t));
    if (!dev->block_info)
        return NFS_ENOMEM;

    dev->chunk_bits = (nfs_u8 *)dev->drv.malloc(dev->drv.ctx, bitmap_size);
    if (!dev->chunk_bits) {
        dev->drv.free(dev->drv.ctx, dev->block_info);
        dev->block_info = NFS_NULL;
        return NFS_ENOMEM;
    }

    memset(dev->block_info, 0, n_blocks * sizeof(nfs_block_info_t));
    memset(dev->chunk_bits, 0, bitmap_size);

    /* Allocate inband staging buffer if needed */
    if (dev->param.inband_tags) {
        dev->inband_buf = (nfs_u8 *)
            dev->drv.malloc(dev->drv.ctx,
                            dev->param.geo.data_bytes_per_chunk);
        if (!dev->inband_buf) {
            dev->drv.free(dev->drv.ctx, dev->chunk_bits);
            dev->chunk_bits = NFS_NULL;
            dev->drv.free(dev->drv.ctx, dev->block_info);
            dev->block_info = NFS_NULL;
            return NFS_ENOMEM;
        }
    }

    return NFS_OK;
}

void nfs_block_free_arrays(nfs_dev_t *dev)
{
    if (dev->inband_buf) {
        dev->drv.free(dev->drv.ctx, dev->inband_buf);
        dev->inband_buf = NFS_NULL;
    }
    if (dev->block_info) {
        dev->drv.free(dev->drv.ctx, dev->block_info);
        dev->block_info = NFS_NULL;
    }
    if (dev->chunk_bits) {
        dev->drv.free(dev->drv.ctx, dev->chunk_bits);
        dev->chunk_bits = NFS_NULL;
    }
}
