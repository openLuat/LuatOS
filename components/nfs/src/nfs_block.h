/*
 * nfs_block.h — Block-level management for NFS
 *
 * Covers:
 *   - chunk-use bitmap (in-RAM)
 *   - block info array (nfs_block_info_t, in-RAM)
 *   - erase, mark-bad, allocate-chunk, retire-block
 *   - chunk read/write/delete wrappers (call driver + manage bookkeeping)
 */

#ifndef NFS_BLOCK_H
#define NFS_BLOCK_H

#include "../inc/nfs_types.h"
#include "nfs_dev.h"
#include "nfs_tags.h"

/*-------------------------------------------------------------------
 *  Chunk bitmap helpers
 *-------------------------------------------------------------------*/

/** Mark chunk as in-use */
void nfs_chunk_set_used(nfs_dev_t *dev, int chunk_in_nand);

/** Mark chunk as free */
void nfs_chunk_set_free(nfs_dev_t *dev, int chunk_in_nand);

/** Return 1 if chunk is in-use, 0 if free */
int  nfs_chunk_is_used(const nfs_dev_t *dev, int chunk_in_nand);

/*-------------------------------------------------------------------
 *  Block erase / bad-block management
 *-------------------------------------------------------------------*/

/**
 * nfs_block_erase — erase one block and reset block-info
 * Return: NFS_OK or NFS_EFLASH
 */
int nfs_block_erase(nfs_dev_t *dev, int block_in_nand);

/**
 * nfs_block_mark_bad — call driver mark_bad and update block state
 */
void nfs_block_mark_bad(nfs_dev_t *dev, int block_in_nand);

/**
 * nfs_block_retire — mark block as needing retirement, schedule GC
 */
void nfs_block_retire(nfs_dev_t *dev, int block_in_nand);

/*-------------------------------------------------------------------
 *  Chunk allocation
 *-------------------------------------------------------------------*/

/**
 * nfs_alloc_chunk — find a free chunk for writing
 * @use_resvd:  1=allow use of reserved erased blocks
 * Return: chunk number in NAND (≥0) or -1 on failure
 */
int nfs_alloc_chunk(nfs_dev_t *dev, int use_resvd);

/*-------------------------------------------------------------------
 *  Chunk I/O
 *-------------------------------------------------------------------*/

/**
 * nfs_chunk_write — write data + tags to a free chunk
 * @chunk_in_nand:  absolute chunk number
 * @data:           data bytes (may be NULL for tags-only writes)
 * @n_bytes:        bytes of useful data (<= chunk_data_size)
 * @ext:            tags (seq, obj_id, chunk_id set by caller)
 * Return: NFS_OK or NFS_EFLASH
 */
int nfs_chunk_write(nfs_dev_t *dev, int chunk_in_nand,
                    const nfs_u8 *data, int n_bytes,
                    nfs_ext_tags_t *ext);

/**
 * nfs_chunk_read — read data and/or tags from a chunk
 * @data:    destination buffer (may be NULL to read tags only)
 * @ext:     destination tags struct
 * Return: NFS_OK or error code; ext->ecc_result populated
 */
int nfs_chunk_read(nfs_dev_t *dev, int chunk_in_nand,
                   nfs_u8 *data, int n_bytes,
                   nfs_ext_tags_t *ext);

/**
 * nfs_chunk_delete — logically delete a chunk (update bookkeeping)
 * The block-level soft_del counter is incremented; the NAND page is
 * NOT erased here (GC erases entire blocks).
 */
void nfs_chunk_delete(nfs_dev_t *dev, int chunk_in_nand,
                      int mark_flash);

/*-------------------------------------------------------------------
 *  Block state queries
 *-------------------------------------------------------------------*/

int  nfs_block_is_erased(const nfs_dev_t *dev, int block_in_nand);
int  nfs_block_is_bad   (const nfs_dev_t *dev, int block_in_nand);
void nfs_block_set_state(nfs_dev_t *dev, int block_in_nand,
                         nfs_block_state_t state);
nfs_block_state_t nfs_block_get_state(const nfs_dev_t *dev,
                                      int block_in_nand);

/*-------------------------------------------------------------------
 *  Init / free
 *-------------------------------------------------------------------*/

/**
 * nfs_block_init_arrays — allocate block_info and chunk_bits arrays
 * Called during nfs_mount before any NAND access.
 * Return: NFS_OK or NFS_ENOMEM
 */
int  nfs_block_init_arrays(nfs_dev_t *dev);
void nfs_block_free_arrays(nfs_dev_t *dev);

#endif /* NFS_BLOCK_H */
