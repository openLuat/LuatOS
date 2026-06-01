/*
 * nfs_checkpoint.h — Checkpoint read/write for NFS
 *
 * A checkpoint captures the complete device state (block info, object
 * table, tnode trees) so that mount can restore it without a full
 * NAND scan.
 *
 * On-NAND layout:
 *   Chunk 0 of a checkpoint block:
 *     nfs_checkpt_validity_t  (version, seq, sum, xor)
 *     nfs_checkpt_dev_t       (geometry + runtime counters)
 *   Subsequent chunks:
 *     block_info records (4 bytes each, packed)
 *     object records (variable size, terminated by NFS_OBJ_ID_NULL)
 */

#ifndef NFS_CHECKPOINT_H
#define NFS_CHECKPOINT_H

#include "../inc/nfs_types.h"
#include "nfs_dev.h"

#define NFS_CHECKPT_VERSION   4u

/*-------------------------------------------------------------------
 *  On-NAND checkpoint structures
 *-------------------------------------------------------------------*/

typedef struct {
    nfs_u32 version;
    nfs_u32 seq;
    nfs_u32 sum;
    nfs_u32 xor;
} nfs_checkpt_validity_t;

typedef struct {
    nfs_u32 n_erased_blocks;
    nfs_u32 alloc_block;
    nfs_u32 alloc_page;
    nfs_u32 n_free_chunks;
    nfs_u32 seq_number;
    nfs_u32 oldest_dirty_seq;
    nfs_u32 n_deleted_files;
    nfs_u32 n_unlinked_files;
} nfs_checkpt_dev_t;

typedef struct {
    nfs_u32 obj_id;
    nfs_u32 parent_id;
    nfs_u32 hdr_chunk;
    nfs_u32 type;
    nfs_u32 mode;
    nfs_u32 uid;
    nfs_u32 gid;
    nfs_u32 atime;
    nfs_u32 mtime;
    nfs_u32 ctime;
    nfs_u32 rdev;
    nfs_u32 n_data_chunks;
    nfs_u32 file_size_lo;
    nfs_u32 file_size_hi;
} nfs_checkpt_obj_t;

/*-------------------------------------------------------------------
 *  API
 *-------------------------------------------------------------------*/

/**
 * nfs_checkpt_write — serialise current device state to NAND
 * Return: NFS_OK on success, error otherwise
 */
int nfs_checkpt_write(nfs_dev_t *dev);

/**
 * nfs_checkpt_read — restore device state from checkpoint on NAND
 * Return: NFS_OK if valid checkpoint found and loaded, error otherwise
 */
int nfs_checkpt_read(nfs_dev_t *dev);

/**
 * nfs_checkpt_erase — invalidate (erase) all checkpoint blocks
 */
void nfs_checkpt_erase(nfs_dev_t *dev);

/**
 * nfs_checkpt_required_blocks — number of erased blocks needed for checkpoint
 */
int nfs_checkpt_required_blocks(const nfs_dev_t *dev);

#endif /* NFS_CHECKPOINT_H */
