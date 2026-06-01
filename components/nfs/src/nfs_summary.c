/*
 * nfs_summary.c — Block summary read/write for NFS
 */

#include "nfs_summary.h"
#include "nfs_block.h"
#include "nfs_tags.h"
#include "../inc/nfs_config.h"

#include <string.h>

/*===================================================================
 *  Init / deinit
 *===================================================================*/

int nfs_summary_init(nfs_dev_t *dev)
{
    int entries = nfs_summary_entries_per_block(dev);

    dev->chunks_per_summary = entries;

    dev->sum_tags = (nfs_summary_tags_t *)
        dev->drv.malloc(dev->drv.ctx,
                        (nfs_u32)entries * sizeof(nfs_summary_tags_t));
    if (!dev->sum_tags)
        return NFS_ENOMEM;

    return NFS_OK;
}

void nfs_summary_deinit(nfs_dev_t *dev)
{
    if (dev->sum_tags) {
        dev->drv.free(dev->drv.ctx, dev->sum_tags);
        dev->sum_tags = NFS_NULL;
    }
}

/*===================================================================
 *  Helpers
 *===================================================================*/

int nfs_summary_entries_per_block(const nfs_dev_t *dev)
{
    int chunk_sz = (int)dev->data_bytes_per_chunk;
    int hdr_sz   = (int)sizeof(nfs_summary_header_t);
    int entry_sz = (int)sizeof(nfs_summary_tags_t);
    int cpb      = (int)nfs_chunks_per_block(dev);
    int max_fit  = (chunk_sz - hdr_sz) / entry_sz;

    /* We write summary in the LAST chunk of the block, so we can
     * summarise at most (cpb-1) chunks. */
    return (max_fit < cpb - 1) ? max_fit : cpb - 1;
}

static int summary_chunk_for_block(const nfs_dev_t *dev,
                                   int block_in_nand)
{
    return block_in_nand * (int)nfs_chunks_per_block(dev)
           + (int)nfs_chunks_per_block(dev) - 1;
}

/*===================================================================
 *  Write
 *===================================================================*/

int nfs_summary_write(nfs_dev_t *dev, int block_in_nand)
{
    nfs_block_info_t *bi     = nfs_get_block_info(dev, block_in_nand);
    int               cpb    = (int)nfs_chunks_per_block(dev);
    int               n_ent  = cpb - 1;   /* last chunk is the summary */
    nfs_u8           *buf;
    nfs_summary_header_t *hdr;
    nfs_summary_tags_t   *tags;
    nfs_ext_tags_t        ext;
    int                   sum_chunk;
    int                   i, rc;

    if (dev->param.disable_summary)
        return NFS_OK;

    if (n_ent > dev->chunks_per_summary)
        n_ent = dev->chunks_per_summary;

    /* Use temp buffer */
    buf = (nfs_u8 *)dev->drv.malloc(dev->drv.ctx,
                                    dev->data_bytes_per_chunk);
    if (!buf)
        return NFS_ENOMEM;

    memset(buf, 0xff, dev->data_bytes_per_chunk);

    hdr = (nfs_summary_header_t *)buf;
    tags= (nfs_summary_tags_t  *)(buf + sizeof(nfs_summary_header_t));

    hdr->magic      = NFS_SUMMARY_MAGIC;
    hdr->version    = NFS_SUMMARY_VERSION;
    hdr->n_entries  = (nfs_u16)n_ent;
    hdr->seq_number = bi->bi.seq_number;

    /* Read tags for each chunk in the block */
    for (i = 0; i < n_ent; i++) {
        nfs_ext_tags_t ce;
        int chunk_in_nand = block_in_nand * cpb + i;

        memset(&ce, 0, sizeof(ce));
        rc = nfs_chunk_read(dev, chunk_in_nand, NFS_NULL, 0, &ce);
        if (rc != NFS_OK || !ce.chunk_used) {
            tags[i].obj_id   = 0xffffffff;
            tags[i].chunk_id = 0xffffffff;
            tags[i].n_bytes  = 0xffff;
        } else {
            tags[i].obj_id   = ce.obj_id;
            tags[i].chunk_id = ce.chunk_id;
            tags[i].n_bytes  = (nfs_u16)ce.n_bytes;
        }
    }

    /* Write summary into last chunk of block */
    sum_chunk = summary_chunk_for_block(dev, block_in_nand);

    memset(&ext, 0, sizeof(ext));
    ext.chunk_used = 1;
    ext.obj_id     = NFS_OBJ_ID_SUMMARY;
    ext.chunk_id   = 1;
    ext.n_bytes    = (nfs_u32)(sizeof(nfs_summary_header_t)
                                + (nfs_u32)n_ent * sizeof(nfs_summary_tags_t));

    rc = nfs_chunk_write(dev, sum_chunk, buf, (int)ext.n_bytes, &ext);

    dev->drv.free(dev->drv.ctx, buf);

    if (rc == NFS_OK)
        bi->bi.has_summary = 1;

    return rc;
}

/*===================================================================
 *  Read
 *===================================================================*/

int nfs_summary_read(nfs_dev_t *dev, int block_in_nand,
                     nfs_summary_tags_t *tags_out, int *n_out)
{
    int           sum_chunk = summary_chunk_for_block(dev, block_in_nand);
    nfs_ext_tags_t ext;
    nfs_u8        *buf;
    nfs_summary_header_t *hdr;
    nfs_summary_tags_t   *tags;
    int                   rc, i;

    if (dev->param.disable_summary)
        return NFS_EINVAL;

    buf = (nfs_u8 *)dev->drv.malloc(dev->drv.ctx,
                                    dev->data_bytes_per_chunk);
    if (!buf)
        return NFS_ENOMEM;

    memset(&ext, 0, sizeof(ext));
    rc = nfs_chunk_read(dev, sum_chunk, buf,
                        (int)dev->data_bytes_per_chunk, &ext);
    if (rc != NFS_OK || !ext.chunk_used ||
        ext.obj_id != NFS_OBJ_ID_SUMMARY) {
        dev->drv.free(dev->drv.ctx, buf);
        return NFS_EINVAL;
    }

    hdr = (nfs_summary_header_t *)buf;

    if (hdr->magic   != NFS_SUMMARY_MAGIC ||
        hdr->version != NFS_SUMMARY_VERSION) {
        dev->drv.free(dev->drv.ctx, buf);
        return NFS_EINVAL;
    }

    tags  = (nfs_summary_tags_t *)(buf + sizeof(nfs_summary_header_t));
    *n_out= (int)hdr->n_entries;

    for (i = 0; i < *n_out; i++)
        tags_out[i] = tags[i];

    dev->drv.free(dev->drv.ctx, buf);
    return NFS_OK;
}
