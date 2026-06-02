/*
 * tfs_tnode.c — Chunk-index tree for TFS
 *
 * The tnode tree maps chunk_id → chunk_in_nand.
 *
 * Tree structure:
 *   - Leaf node  (level 0): array of TFS_TNODES_LEVEL0 u32 chunk references
 *   - Internal node: array of TFS_TNODES_INTERNAL pointers to children
 *   - Bits per slot:
 *       leaf:     tnode_width bits per entry (usually 16 or 32)
 *       internal: pointer-wide
 *
 * Width selection: if the total NAND chunk count fits in 16 bits we use
 * 16-bit leaf entries (saves ~50 % RAM); otherwise 32-bit.
 *
 * A chunk_id is decomposed into a sequence of TFS_TNODES_LEVEL0_BITS
 * (leaf) and TFS_TNODES_INTERNAL_BITS (internal) bit fields from LSB
 * to MSB, matching how yaffs2 traverses its tnode tree.
 */

#include "tfs_tnode.h"
#include "tfs_block.h"
#include "../inc/tfs_config.h"

#include <string.h>

/*===================================================================
 *  Tnode allocator — simple slab over the device malloc
 *===================================================================*/

int tfs_tnode_init(tfs_dev_t *dev)
{
    uint32_t total_chunks = (uint32_t)tfs_total_blocks(dev)
                           * tfs_chunks_per_block(dev);

    /* Choose tnode width */
    if (total_chunks <= 0xffffu && !dev->param.wide_tnodes_disabled)
        dev->tnode_width = 16;
    else
        dev->tnode_width = 32;

    dev->tnode_mask = (dev->tnode_width == 16) ? 0xffffu : 0xffffffffu;

    /* Size in bytes for a leaf node (TFS_TNODES_LEVEL0 entries) */
    dev->tnode_size = TFS_TNODES_LEVEL0 * dev->tnode_width / 8;

    dev->n_tnodes = 0;
    return TFS_OK;
}

void tfs_tnode_deinit(tfs_dev_t *dev)
{
    (void)dev;
    /* Individual tnodes freed via tfs_tnode_free / tfs_tnode_free_tree */
}

/*===================================================================
 *  Allocate / free
 *===================================================================*/

tfs_tnode_t *tfs_tnode_create(tfs_dev_t *dev)
{
    tfs_tnode_t *tn;

    /* All nodes are the same size: max(leaf_size, internal_size).
     * Internal nodes have TFS_TNODES_INTERNAL pointers;
     * leaf nodes have tnode_size bytes. Use the larger. */
    uint32_t sz = dev->tnode_size;
    if (sz < sizeof(tfs_tnode_t))
        sz = sizeof(tfs_tnode_t);

    tn = (tfs_tnode_t *)dev->drv.malloc(dev->drv.ctx, sz);
    if (tn) {
        memset(tn, 0, sz);
        dev->n_tnodes++;
    }
    return tn;
}

void tfs_tnode_free(tfs_dev_t *dev, tfs_tnode_t *tn)
{
    if (!tn)
        return;
    dev->drv.free(dev->drv.ctx, tn);
    dev->n_tnodes--;
}

void tfs_tnode_free_tree(tfs_dev_t *dev, tfs_tnode_t *tn, int level)
{
    int i;

    if (!tn)
        return;

    if (level > 0) {
        for (i = 0; i < TFS_TNODES_INTERNAL; i++)
            tfs_tnode_free_tree(dev, tn->internal[i], level - 1);
    }

    tfs_tnode_free(dev, tn);
}

/*===================================================================
 *  Internal: read / write a leaf slot (width-aware)
 *===================================================================*/

static uint32_t leaf_get(const tfs_dev_t *dev,
                        const tfs_tnode_t *leaf, uint32_t slot)
{
    if (dev->tnode_width == 16) {
        const uint16_t *p = (const uint16_t *)leaf;
        return p[slot];
    } else {
        const uint32_t *p = (const uint32_t *)leaf;
        return p[slot];
    }
}

static void leaf_set(const tfs_dev_t *dev,
                     tfs_tnode_t *leaf, uint32_t slot, uint32_t val)
{
    if (dev->tnode_width == 16) {
        uint16_t *p = (uint16_t *)leaf;
        p[slot] = (uint16_t)(val & 0xffffu);
    } else {
        uint32_t *p = (uint32_t *)leaf;
        p[slot] = val;
    }
}

/*===================================================================
 *  Tree metrics
 *===================================================================*/

int tfs_tnode_level_for_chunks(const tfs_dev_t *dev, int n_data_chunks)
{
    int level = 0;
    uint32_t capacity = TFS_TNODES_LEVEL0;

    while ((int)capacity < n_data_chunks + 1 &&
           level < TFS_TNODES_MAX_LEVEL) {
        capacity *= TFS_TNODES_INTERNAL;
        level++;
    }
    return level;
}

uint32_t tfs_tnode_slots_at_level0(const tfs_dev_t *dev, int level)
{
    uint32_t r = TFS_TNODES_LEVEL0;
    while (level-- > 0)
        r *= TFS_TNODES_INTERNAL;
    return r;
    (void)dev;
}

/*===================================================================
 *  Find level-0 node for chunk_id
 *===================================================================*/

tfs_tnode_t *tfs_tnode_find_level0(tfs_dev_t *dev, tfs_obj_t *obj,
                                   uint32_t chunk_id,
                                   uint32_t *level0_off,
                                   int alloc)
{
    tfs_tnode_t *tn    = obj->var.file.top;
    int          level = obj->var.file.top_level;
    uint32_t      offset;

    /* Compute bit offset for this level */
    /* Navigate internal levels */
    while (level > 0) {
        uint32_t internal_slot;

        /* Bits to shift right at this level:
         *   level 1 needs bits [level0_bits + internal_bits*0 .. +int_bits)
         *   level k needs bits [level0_bits + internal_bits*(k-1) .. +int_bits)
         */
        uint32_t shift = TFS_TNODES_LEVEL0_BITS
                        + (uint32_t)(level - 1) * TFS_TNODES_INTERNAL_BITS;
        internal_slot = (chunk_id >> shift) & (TFS_TNODES_INTERNAL - 1u);

        if (!tn->internal[internal_slot]) {
            if (!alloc)
                return NULL;
            tn->internal[internal_slot] = tfs_tnode_create(dev);
            if (!tn->internal[internal_slot])
                return NULL;
        }

        tn = tn->internal[internal_slot];
        level--;
    }

    /* tn is now the leaf node */
    offset = chunk_id & (TFS_TNODES_LEVEL0 - 1u);
    if (level0_off)
        *level0_off = offset;

    return tn;
}

/*===================================================================
 *  get / put chunk
 *===================================================================*/

uint32_t tfs_tnode_get_chunk(tfs_dev_t *dev, tfs_obj_t *obj,
                            uint32_t chunk_id)
{
    tfs_tnode_t *leaf;
    uint32_t      slot;
    uint32_t      chunk_in_nand;

    if (!obj->var.file.top)
        return 0;

    leaf = tfs_tnode_find_level0(dev, obj, chunk_id, &slot, 0);
    if (!leaf)
        return 0;

    chunk_in_nand = leaf_get(dev, leaf, slot);

    /* Convert 1-indexed relative address back to absolute chunk number */
    if (chunk_in_nand) {
        chunk_in_nand += (uint32_t)dev->chunk_offset - 1u;
    }
    return chunk_in_nand;
}

int tfs_tnode_put_chunk(tfs_dev_t *dev, tfs_obj_t *obj,
                        uint32_t chunk_id, uint32_t chunk_in_nand)
{
    tfs_tnode_t *leaf;
    uint32_t      slot;
    int          needed_level;
    uint32_t      stored;

    /* Grow tree if needed */
    needed_level = tfs_tnode_level_for_chunks(dev,
                       (int)chunk_id / TFS_TNODES_LEVEL0 + 1);

    while (obj->var.file.top_level < needed_level) {
        tfs_tnode_t *new_top = tfs_tnode_create(dev);
        if (!new_top)
            return TFS_ENOMEM;
        new_top->internal[0] = obj->var.file.top;
        obj->var.file.top    = new_top;
        obj->var.file.top_level++;
    }

    if (!obj->var.file.top) {
        obj->var.file.top = tfs_tnode_create(dev);
        if (!obj->var.file.top)
            return TFS_ENOMEM;
    }

    leaf = tfs_tnode_find_level0(dev, obj, chunk_id, &slot, 1);
    if (!leaf)
        return TFS_ENOMEM;

    /*
     * Store 1-indexed relative address so that 0 always means "not found".
     * chunk_in_nand is always a valid NAND address (>= chunk_offset) here;
     * delete operations go directly through leaf_set(0) in del_chunks_recursive,
     * not through this function.  Using +1 ensures NAND chunk 0 (when
     * start_block=0 and chunk_offset=0) is stored as 1, not 0.
     */
    stored = chunk_in_nand - (uint32_t)dev->chunk_offset + 1u;
    leaf_set(dev, leaf, slot, stored);
    return TFS_OK;
}

/*===================================================================
 *  Delete all chunks in a file
 *===================================================================*/

static void del_chunks_recursive(tfs_dev_t *dev,
                                 tfs_tnode_t *tn, int level,
                                 uint32_t base_chunk_id,
                                 tfs_off_t limit_size,
                                 int del_hdr,
                                 int *deleted_count)
{
    uint32_t i;
    int     cpb = (int)tfs_chunks_per_block(dev);
    (void)cpb;

    if (!tn)
        return;

    if (level == 0) {
        /* Leaf node: visit each slot */
        uint32_t chunk_size = dev->data_bytes_per_chunk;
        for (i = 0; i < TFS_TNODES_LEVEL0; i++) {
            uint32_t c = leaf_get(dev, tn, i);
            if (c) {
                uint32_t chunk_id    = base_chunk_id + i;
                tfs_off_t file_pos  = (tfs_off_t)chunk_id * chunk_size;

                if (limit_size < 0 || file_pos >= limit_size) {
                    uint32_t chunk_in_nand = c - 1u + (uint32_t)dev->chunk_offset;
                    tfs_chunk_delete(dev, (int)chunk_in_nand, 1);
                    leaf_set(dev, tn, i, 0);
                    if (deleted_count)
                        (*deleted_count)++;
                }
            }
        }
    } else {
        uint32_t span = tfs_tnode_slots_at_level0(dev, level);
        for (i = 0; i < (uint32_t)TFS_TNODES_INTERNAL; i++) {
            uint32_t child_base = base_chunk_id + i * span;
            tfs_off_t child_start = (tfs_off_t)child_base
                                    * dev->data_bytes_per_chunk;
            if (limit_size < 0 || child_start >= limit_size) {
                del_chunks_recursive(dev, tn->internal[i],
                                     level - 1, child_base,
                                     limit_size, del_hdr,
                                     deleted_count);
                if (limit_size >= 0 && child_start >= limit_size) {
                    tfs_tnode_free_tree(dev, tn->internal[i], level - 1);
                    tn->internal[i] = NULL;
                }
            } else {
                del_chunks_recursive(dev, tn->internal[i],
                                     level - 1, child_base,
                                     limit_size, del_hdr,
                                     deleted_count);
            }
        }
    }
}

void tfs_tnode_del_file_chunks(tfs_dev_t *dev, tfs_obj_t *obj,
                                tfs_off_t limit_size)
{
    int deleted_count = 0;

    if (!obj->var.file.top)
        return;

    del_chunks_recursive(dev, obj->var.file.top,
                         obj->var.file.top_level,
                         0, limit_size, 1,
                         &deleted_count);

    if (limit_size < 0) {
        tfs_tnode_free_tree(dev, obj->var.file.top,
                            obj->var.file.top_level);
        obj->var.file.top       = NULL;
        obj->var.file.top_level = 0;
        obj->n_data_chunks      = 0;
    } else if (deleted_count > 0) {
        if (obj->n_data_chunks > deleted_count)
            obj->n_data_chunks -= deleted_count;
        else
            obj->n_data_chunks = 0;
    }
}

void tfs_tnode_shrink_worker(tfs_dev_t *dev, tfs_obj_t *obj,
                              tfs_off_t limit_size, int del_hdr)
{
    (void)del_hdr;
    tfs_tnode_del_file_chunks(dev, obj, limit_size);
}
