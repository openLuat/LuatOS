/*
 * tfs_block.h — Block-level management for TFS
 *
 * Covers:
 *   - chunk-use bitmap (in-RAM)
 *   - block info array (tfs_block_info_t, in-RAM)
 *   - erase, mark-bad, allocate-chunk, retire-block
 *   - chunk read/write/delete wrappers (call driver + manage bookkeeping)
 */

#ifndef TFS_BLOCK_H
#define TFS_BLOCK_H

#include "../inc/tfs_types.h"
#include "tfs_dev.h"
#include "tfs_tags.h"

/*-------------------------------------------------------------------
 *  Chunk bitmap helpers
 *-------------------------------------------------------------------*/

/** Mark chunk as in-use */
void tfs_chunk_set_used(tfs_dev_t *dev, int chunk_in_nand);

/** Mark chunk as free */
void tfs_chunk_set_free(tfs_dev_t *dev, int chunk_in_nand);

/** Return 1 if chunk is in-use, 0 if free */
int  tfs_chunk_is_used(const tfs_dev_t *dev, int chunk_in_nand);

/*-------------------------------------------------------------------
 *  Block erase / bad-block management
 *-------------------------------------------------------------------*/

/**
 * tfs_block_erase — erase one block and reset block-info
 * Return: TFS_OK or TFS_EFLASH
 */
int tfs_block_erase(tfs_dev_t *dev, int block_in_nand);

/**
 * tfs_block_mark_bad — call driver mark_bad and update block state
 */
void tfs_block_mark_bad(tfs_dev_t *dev, int block_in_nand);

/**
 * tfs_block_retire — mark block as needing retirement, schedule GC
 */
void tfs_block_retire(tfs_dev_t *dev, int block_in_nand);

/*-------------------------------------------------------------------
 *  Chunk allocation
 *-------------------------------------------------------------------*/

/**
 * tfs_alloc_chunk — find a free chunk for writing
 * @use_resvd:  1=allow use of reserved erased blocks
 * Return: chunk number in NAND (≥0) or -1 on failure
 */
int tfs_alloc_chunk(tfs_dev_t *dev, int use_resvd);

/*-------------------------------------------------------------------
 *  Chunk I/O
 *-------------------------------------------------------------------*/

/**
 * tfs_chunk_write — write data + tags to a free chunk
 * @chunk_in_nand:  absolute chunk number
 * @data:           data bytes (may be NULL for tags-only writes)
 * @n_bytes:        bytes of useful data (<= chunk_data_size)
 * @ext:            tags (seq, obj_id, chunk_id set by caller)
 * Return: TFS_OK or TFS_EFLASH
 */
int tfs_chunk_write(tfs_dev_t *dev, int chunk_in_nand,
                    const uint8_t *data, int n_bytes,
                    tfs_ext_tags_t *ext);

/**
 * tfs_chunk_read — read data and/or tags from a chunk
 * @data:    destination buffer (may be NULL to read tags only)
 * @ext:     destination tags struct
 * Return: TFS_OK or error code; ext->ecc_result populated
 */
int tfs_chunk_read(tfs_dev_t *dev, int chunk_in_nand,
                   uint8_t *data, int n_bytes,
                   tfs_ext_tags_t *ext);

/**
 * tfs_chunk_delete — logically delete a chunk (update bookkeeping)
 * The block-level soft_del counter is incremented; the NAND page is
 * NOT erased here (GC erases entire blocks).
 */
void tfs_chunk_delete(tfs_dev_t *dev, int chunk_in_nand,
                      int mark_flash);

/*-------------------------------------------------------------------
 *  Block state queries
 *-------------------------------------------------------------------*/

int  tfs_block_is_erased(const tfs_dev_t *dev, int block_in_nand);
int  tfs_block_is_bad   (const tfs_dev_t *dev, int block_in_nand);
void tfs_block_set_state(tfs_dev_t *dev, int block_in_nand,
                         tfs_block_state_t state);
tfs_block_state_t tfs_block_get_state(const tfs_dev_t *dev,
                                      int block_in_nand);

/*-------------------------------------------------------------------
 *  Init / free
 *-------------------------------------------------------------------*/

/**
 * tfs_block_init_arrays — allocate block_info and chunk_bits arrays
 * Called during tfs_mount before any NAND access.
 * Return: TFS_OK or TFS_ENOMEM
 */
int  tfs_block_init_arrays(tfs_dev_t *dev);
void tfs_block_free_arrays(tfs_dev_t *dev);

#endif /* TFS_BLOCK_H */
