/*
 * tfs_checkpoint.h — Checkpoint read/write for TFS
 *
 * A checkpoint captures the complete device state (block info, object
 * table, tnode trees) so that mount can restore it without a full
 * NAND scan.
 *
 * On-NAND layout:
 *   Chunk 0 of a checkpoint block:
 *     tfs_checkpt_validity_t  (version, seq, sum, xor)
 *     tfs_checkpt_dev_t       (geometry + runtime counters)
 *   Subsequent chunks:
 *     block_info records (4 bytes each, packed)
 *     object records (variable size, terminated by TFS_OBJ_ID_NULL)
 */

#ifndef TFS_CHECKPOINT_H
#define TFS_CHECKPOINT_H

#include "../inc/tfs_types.h"
#include "tfs_dev.h"

#define TFS_CHECKPT_VERSION   4u

/*-------------------------------------------------------------------
 *  On-NAND checkpoint structures
 *-------------------------------------------------------------------*/

typedef struct {
    uint32_t version;
    uint32_t seq;
    uint32_t sum;
    uint32_t xor;
} tfs_checkpt_validity_t;

typedef struct {
    uint32_t n_erased_blocks;
    uint32_t alloc_block;
    uint32_t alloc_page;
    uint32_t n_free_chunks;
    uint32_t seq_number;
    uint32_t oldest_dirty_seq;
    uint32_t n_deleted_files;
    uint32_t n_unlinked_files;
} tfs_checkpt_dev_t;

typedef struct {
    uint32_t obj_id;
    uint32_t parent_id;
    uint32_t hdr_chunk;
    uint32_t type;
    uint32_t mode;
    uint32_t uid;
    uint32_t gid;
    uint32_t atime;
    uint32_t mtime;
    uint32_t ctime;
    uint32_t rdev;
    uint32_t n_data_chunks;
    uint32_t file_size_lo;
    uint32_t file_size_hi;
} tfs_checkpt_obj_t;

/*-------------------------------------------------------------------
 *  API
 *-------------------------------------------------------------------*/

/**
 * tfs_checkpt_write — serialise current device state to NAND
 * Return: TFS_OK on success, error otherwise
 */
int tfs_checkpt_write(tfs_dev_t *dev);

/**
 * tfs_checkpt_read — restore device state from checkpoint on NAND
 * Return: TFS_OK if valid checkpoint found and loaded, error otherwise
 */
int tfs_checkpt_read(tfs_dev_t *dev);

/**
 * tfs_checkpt_erase — invalidate (erase) all checkpoint blocks
 */
void tfs_checkpt_erase(tfs_dev_t *dev);

/**
 * tfs_checkpt_required_blocks — number of erased blocks needed for checkpoint
 */
int tfs_checkpt_required_blocks(const tfs_dev_t *dev);

#endif /* TFS_CHECKPOINT_H */
