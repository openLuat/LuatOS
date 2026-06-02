/*
 * tfs_summary.c — Block summary read/write for TFS
 */

#include "tfs_summary.h"
#include "tfs_block.h"
#include "tfs_tags.h"
#include "../inc/tfs_config.h"

#include <string.h>

/*===================================================================
 *  Init / deinit
 *===================================================================*/

int tfs_summary_init(tfs_dev_t *dev)
{
    int entries = tfs_summary_entries_per_block(dev);

    dev->chunks_per_summary = entries;

    dev->sum_tags = (tfs_summary_tags_t *)
        dev->drv.malloc(dev->drv.ctx,
                        (uint32_t)entries * sizeof(tfs_summary_tags_t));
    if (!dev->sum_tags)
        return TFS_ENOMEM;

    return TFS_OK;
}

void tfs_summary_deinit(tfs_dev_t *dev)
{
    if (dev->sum_tags) {
        dev->drv.free(dev->drv.ctx, dev->sum_tags);
        dev->sum_tags = NULL;
    }
}

/*===================================================================
 *  Helpers
 *===================================================================*/

int tfs_summary_entries_per_block(const tfs_dev_t *dev)
{
    int chunk_sz = (int)dev->data_bytes_per_chunk;
    int hdr_sz   = (int)sizeof(tfs_summary_header_t);
    int entry_sz = (int)sizeof(tfs_summary_tags_t);
    int cpb      = (int)tfs_chunks_per_block(dev);
    int max_fit  = (chunk_sz - hdr_sz) / entry_sz;

    /* We write summary in the LAST chunk of the block, so we can
     * summarise at most (cpb-1) chunks. */
    return (max_fit < cpb - 1) ? max_fit : cpb - 1;
}

static int summary_chunk_for_block(const tfs_dev_t *dev,
                                   int block_in_nand)
{
    return block_in_nand * (int)tfs_chunks_per_block(dev)
           + (int)tfs_chunks_per_block(dev) - 1;
}

/*===================================================================
 *  Write
 *===================================================================*/

int tfs_summary_write(tfs_dev_t *dev, int block_in_nand)
{
    tfs_block_info_t *bi     = tfs_get_block_info(dev, block_in_nand);
    int               cpb    = (int)tfs_chunks_per_block(dev);
    int               n_ent  = cpb - 1;   /* last chunk is the summary */
    uint8_t           *buf;
    tfs_summary_header_t *hdr;
    tfs_summary_tags_t   *tags;
    tfs_ext_tags_t        ext;
    int                   sum_chunk;
    int                   i, rc;

    if (dev->param.disable_summary)
        return TFS_OK;

    if (n_ent > dev->chunks_per_summary)
        n_ent = dev->chunks_per_summary;

    /* Use temp buffer */
    buf = (uint8_t *)dev->drv.malloc(dev->drv.ctx,
                                    dev->data_bytes_per_chunk);
    if (!buf)
        return TFS_ENOMEM;

    memset(buf, 0xff, dev->data_bytes_per_chunk);

    hdr = (tfs_summary_header_t *)buf;
    tags= (tfs_summary_tags_t  *)(buf + sizeof(tfs_summary_header_t));

    hdr->magic      = TFS_SUMMARY_MAGIC;
    hdr->version    = TFS_SUMMARY_VERSION;
    hdr->n_entries  = (uint16_t)n_ent;
    hdr->seq_number = bi->bi.seq_number;

    /* Read tags for each chunk in the block */
    for (i = 0; i < n_ent; i++) {
        tfs_ext_tags_t ce;
        int chunk_in_nand = block_in_nand * cpb + i;

        memset(&ce, 0, sizeof(ce));
        rc = tfs_chunk_read(dev, chunk_in_nand, NULL, 0, &ce);
        if (rc != TFS_OK || !ce.chunk_used) {
            tags[i].obj_id   = 0xffffffff;
            tags[i].chunk_id = 0xffffffff;
            tags[i].n_bytes  = 0xffff;
        } else {
            tags[i].obj_id   = ce.obj_id;
            tags[i].chunk_id = ce.chunk_id;
            tags[i].n_bytes  = (uint16_t)ce.n_bytes;
        }
    }

    /* Write summary into last chunk of block */
    sum_chunk = summary_chunk_for_block(dev, block_in_nand);

    memset(&ext, 0, sizeof(ext));
    ext.chunk_used = 1;
    ext.obj_id     = TFS_OBJ_ID_SUMMARY;
    ext.chunk_id   = 1;
    ext.n_bytes    = (uint32_t)(sizeof(tfs_summary_header_t)
                                + (uint32_t)n_ent * sizeof(tfs_summary_tags_t));

    rc = tfs_chunk_write(dev, sum_chunk, buf, (int)ext.n_bytes, &ext);

    dev->drv.free(dev->drv.ctx, buf);

    if (rc == TFS_OK)
        bi->bi.has_summary = 1;

    return rc;
}

/*===================================================================
 *  Read
 *===================================================================*/

int tfs_summary_read(tfs_dev_t *dev, int block_in_nand,
                     tfs_summary_tags_t *tags_out, int *n_out)
{
    int           sum_chunk = summary_chunk_for_block(dev, block_in_nand);
    tfs_ext_tags_t ext;
    uint8_t        *buf;
    tfs_summary_header_t *hdr;
    tfs_summary_tags_t   *tags;
    int                   rc, i;

    if (dev->param.disable_summary)
        return TFS_EINVAL;

    buf = (uint8_t *)dev->drv.malloc(dev->drv.ctx,
                                    dev->data_bytes_per_chunk);
    if (!buf)
        return TFS_ENOMEM;

    memset(&ext, 0, sizeof(ext));
    rc = tfs_chunk_read(dev, sum_chunk, buf,
                        (int)dev->data_bytes_per_chunk, &ext);
    if (rc != TFS_OK || !ext.chunk_used ||
        ext.obj_id != TFS_OBJ_ID_SUMMARY) {
        dev->drv.free(dev->drv.ctx, buf);
        return TFS_EINVAL;
    }

    hdr = (tfs_summary_header_t *)buf;

    if (hdr->magic   != TFS_SUMMARY_MAGIC ||
        hdr->version != TFS_SUMMARY_VERSION) {
        dev->drv.free(dev->drv.ctx, buf);
        return TFS_EINVAL;
    }

    tags  = (tfs_summary_tags_t *)(buf + sizeof(tfs_summary_header_t));
    *n_out= (int)hdr->n_entries;

    for (i = 0; i < *n_out; i++)
        tags_out[i] = tags[i];

    dev->drv.free(dev->drv.ctx, buf);
    return TFS_OK;
}
