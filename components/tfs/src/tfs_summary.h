/*
 * tfs_summary.h — Block summary for TFS
 *
 * The last chunk of every data block holds a compact summary of the
 * other chunks in that block (obj_id + chunk_id + n_bytes).  During
 * mount, reading the summary avoids scanning every individual chunk.
 *
 * Layout (in the data area of the last chunk):
 *   tfs_summary_header_t  (magic, version, n_entries, seq_number)
 *   tfs_summary_tags_t[]  (one per chunk in block, except the last)
 */

#ifndef TFS_SUMMARY_H
#define TFS_SUMMARY_H

#include "../inc/tfs_types.h"
#include "tfs_dev.h"

#define TFS_SUMMARY_MAGIC     0x5346534eu   /* "NSFS" */
#define TFS_SUMMARY_GOOD_SIG  0x1234u

/*-------------------------------------------------------------------
 *  On-NAND summary structures
 *-------------------------------------------------------------------*/

typedef struct tfs_summary_tags {
    uint32_t obj_id;
    uint32_t chunk_id;
    uint16_t n_bytes;
} tfs_summary_tags_t;

typedef struct {
    uint32_t magic;
    uint16_t version;
    uint16_t n_entries;
    uint32_t seq_number;
} tfs_summary_header_t;

/*-------------------------------------------------------------------
 *  API
 *-------------------------------------------------------------------*/

/**
 * tfs_summary_init — allocate the per-device summary buffer
 */
int  tfs_summary_init  (tfs_dev_t *dev);
void tfs_summary_deinit(tfs_dev_t *dev);

/**
 * tfs_summary_write — write the summary chunk for a block that has
 * just been filled.
 * @block_in_nand: block whose last chunk should receive the summary
 * Return: TFS_OK or error
 */
int tfs_summary_write(tfs_dev_t *dev, int block_in_nand);

/**
 * tfs_summary_read — read and validate the summary chunk for a block
 * @block_in_nand: block to read
 * @tags_out: output array (caller allocates; must hold at least
 *            chunks_per_block-1 entries)
 * @n_out:    number of entries written to tags_out
 * Return: TFS_OK if valid summary found, TFS_EINVAL otherwise
 */
int tfs_summary_read(tfs_dev_t *dev, int block_in_nand,
                     tfs_summary_tags_t *tags_out, int *n_out);

/**
 * tfs_summary_entries_per_block — max entries that fit in one chunk
 */
int tfs_summary_entries_per_block(const tfs_dev_t *dev);

#endif /* TFS_SUMMARY_H */
