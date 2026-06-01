/*
 * nfs_summary.h — Block summary for NFS
 *
 * The last chunk of every data block holds a compact summary of the
 * other chunks in that block (obj_id + chunk_id + n_bytes).  During
 * mount, reading the summary avoids scanning every individual chunk.
 *
 * Layout (in the data area of the last chunk):
 *   nfs_summary_header_t  (magic, version, n_entries, seq_number)
 *   nfs_summary_tags_t[]  (one per chunk in block, except the last)
 */

#ifndef NFS_SUMMARY_H
#define NFS_SUMMARY_H

#include "../inc/nfs_types.h"
#include "nfs_dev.h"

#define NFS_SUMMARY_MAGIC     0x5346534eu   /* "NSFS" */
#define NFS_SUMMARY_GOOD_SIG  0x1234u

/*-------------------------------------------------------------------
 *  On-NAND summary structures
 *-------------------------------------------------------------------*/

typedef struct nfs_summary_tags {
    nfs_u32 obj_id;
    nfs_u32 chunk_id;
    nfs_u16 n_bytes;
} nfs_summary_tags_t;

typedef struct {
    nfs_u32 magic;
    nfs_u16 version;
    nfs_u16 n_entries;
    nfs_u32 seq_number;
} nfs_summary_header_t;

/*-------------------------------------------------------------------
 *  API
 *-------------------------------------------------------------------*/

/**
 * nfs_summary_init — allocate the per-device summary buffer
 */
int  nfs_summary_init  (nfs_dev_t *dev);
void nfs_summary_deinit(nfs_dev_t *dev);

/**
 * nfs_summary_write — write the summary chunk for a block that has
 * just been filled.
 * @block_in_nand: block whose last chunk should receive the summary
 * Return: NFS_OK or error
 */
int nfs_summary_write(nfs_dev_t *dev, int block_in_nand);

/**
 * nfs_summary_read — read and validate the summary chunk for a block
 * @block_in_nand: block to read
 * @tags_out: output array (caller allocates; must hold at least
 *            chunks_per_block-1 entries)
 * @n_out:    number of entries written to tags_out
 * Return: NFS_OK if valid summary found, NFS_EINVAL otherwise
 */
int nfs_summary_read(nfs_dev_t *dev, int block_in_nand,
                     nfs_summary_tags_t *tags_out, int *n_out);

/**
 * nfs_summary_entries_per_block — max entries that fit in one chunk
 */
int nfs_summary_entries_per_block(const nfs_dev_t *dev);

#endif /* NFS_SUMMARY_H */
