/*
 * tfs_verify.c — Debug / integrity checks for TFS
 */

#include "tfs_verify.h"
#include "tfs_block.h"
#include "tfs_tnode.h"

static int verify_bitmap_vs_block_info(tfs_dev_t *dev)
{
    int errors = 0;
    int blk, chunk;
    int cpb = (int)tfs_chunks_per_block(dev);

    for (blk = (int)dev->internal_start_block;
         blk <= (int)dev->internal_end_block;
         blk++) {

        tfs_block_info_t *bi = tfs_get_block_info(dev, blk);
        int count = 0;

        for (chunk = blk * cpb; chunk < blk * cpb + cpb; chunk++) {
            if (tfs_chunk_is_used(dev, chunk))
                count++;
        }

        /* pages_in_use counts active + soft-deleted pages; bitmap only
         * counts active pages.  The invariant is:
         *   bitmap_count + soft_del_pages == pages_in_use  */
        if (count + (int)bi->bi.soft_del_pages != (int)bi->bi.pages_in_use) {
            if (dev->drv.trace)
                dev->drv.trace("verify: block %d bitmap mismatch "
                               "(bitmap=%d soft_del=%d pages_in_use=%d)",
                               blk, count,
                               (int)bi->bi.soft_del_pages,
                               (int)bi->bi.pages_in_use);
            errors++;
        }
    }
    return errors;
}

static int verify_objects(tfs_dev_t *dev)
{
    int       errors = 0;
    uint32_t   i;
    tfs_obj_t *obj;

    for (i = 0; i < TFS_OBJ_BUCKETS; i++) {
        tfs_list_for_each_entry(obj, &dev->obj_bucket[i].list, hash_link) {
            /* Must have a header chunk or be a fake object */
            if (!obj->fake && obj->hdr_chunk <= 0) {
                if (dev->drv.trace)
                    dev->drv.trace("verify: object %u has no header chunk",
                                   obj->obj_id);
                errors++;
            }

            /* Check tnode for files */
            if (obj->obj_type == TFS_OBJ_TYPE_FILE)
                errors += tfs_verify_obj(dev, obj);
        }
    }
    return errors;
}

int tfs_verify_device(tfs_dev_t *dev)
{
    int errors = 0;

    errors += verify_bitmap_vs_block_info(dev);
    errors += verify_objects(dev);

    return errors;
}

int tfs_verify_obj(tfs_dev_t *dev, tfs_obj_t *obj)
{
    int      errors = 0;
    uint32_t  chunk_id;

    if (obj->obj_type != TFS_OBJ_TYPE_FILE)
        return 0;

    /* Walk all chunk IDs and verify they point to in-use chunks */
    for (chunk_id = 0; chunk_id < (uint32_t)obj->n_data_chunks; chunk_id++) {
        uint32_t cinn = tfs_tnode_get_chunk(dev, obj, chunk_id);
        if (cinn == 0) continue;

        if (!tfs_chunk_is_used(dev, (int)cinn)) {
            if (dev->drv.trace)
                dev->drv.trace("verify: obj %u tnode chunk_id %u "
                               "points to free chunk %u",
                               obj->obj_id, chunk_id, cinn);
            errors++;
        }
    }

    return errors;
}
