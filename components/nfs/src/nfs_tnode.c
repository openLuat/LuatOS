/*
 * nfs_tnode.c — Chunk-index tree for NFS
 *
 * The tnode tree maps chunk_id → chunk_in_nand.
 *
 * Tree structure:
 *   - Leaf node  (level 0): array of NFS_TNODES_LEVEL0 u32 chunk references
 *   - Internal node: array of NFS_TNODES_INTERNAL pointers to children
 *   - Bits per slot:
 *       leaf:     tnode_width bits per entry (usually 16 or 32)
 *       internal: pointer-wide
 *
 * Width selection: if the total NAND chunk count fits in 16 bits we use
 * 16-bit leaf entries (saves ~50 % RAM); otherwise 32-bit.
 *
 * A chunk_id is decomposed into a sequence of NFS_TNODES_LEVEL0_BITS
 * (leaf) and NFS_TNODES_INTERNAL_BITS (internal) bit fields from LSB
 * to MSB, matching how yaffs2 traverses its tnode tree.
 */

#include "nfs_tnode.h"
#include "nfs_block.h"
#include "../inc/nfs_config.h"

#include <string.h>

/*===================================================================
 *  Tnode allocator — simple slab over the device malloc
 *===================================================================*/

int nfs_tnode_init(nfs_dev_t *dev)
{
    nfs_u32 total_chunks = (nfs_u32)nfs_total_blocks(dev)
                           * nfs_chunks_per_block(dev);

    /* Choose tnode width */
    if (total_chunks <= 0xffffu && !dev->param.wide_tnodes_disabled)
        dev->tnode_width = 16;
    else
        dev->tnode_width = 32;

    dev->tnode_mask = (dev->tnode_width == 16) ? 0xffffu : 0xffffffffu;

    /* Size in bytes for a leaf node (NFS_TNODES_LEVEL0 entries) */
    dev->tnode_size = NFS_TNODES_LEVEL0 * dev->tnode_width / 8;

    dev->n_tnodes = 0;
    return NFS_OK;
}

void nfs_tnode_deinit(nfs_dev_t *dev)
{
    (void)dev;
    /* Individual tnodes freed via nfs_tnode_free / nfs_tnode_free_tree */
}

/*===================================================================
 *  Allocate / free
 *===================================================================*/

nfs_tnode_t *nfs_tnode_create(nfs_dev_t *dev)
{
    nfs_tnode_t *tn;

    /* All nodes are the same size: max(leaf_size, internal_size).
     * Internal nodes have NFS_TNODES_INTERNAL pointers;
     * leaf nodes have tnode_size bytes. Use the larger. */
    nfs_u32 sz = dev->tnode_size;
    if (sz < sizeof(nfs_tnode_t))
        sz = sizeof(nfs_tnode_t);

    tn = (nfs_tnode_t *)dev->drv.malloc(dev->drv.ctx, sz);
    if (tn) {
        memset(tn, 0, sz);
        dev->n_tnodes++;
    }
    return tn;
}

void nfs_tnode_free(nfs_dev_t *dev, nfs_tnode_t *tn)
{
    if (!tn)
        return;
    dev->drv.free(dev->drv.ctx, tn);
    dev->n_tnodes--;
}

void nfs_tnode_free_tree(nfs_dev_t *dev, nfs_tnode_t *tn, int level)
{
    int i;

    if (!tn)
        return;

    if (level > 0) {
        for (i = 0; i < NFS_TNODES_INTERNAL; i++)
            nfs_tnode_free_tree(dev, tn->internal[i], level - 1);
    }

    nfs_tnode_free(dev, tn);
}

/*===================================================================
 *  Internal: read / write a leaf slot (width-aware)
 *===================================================================*/

static nfs_u32 leaf_get(const nfs_dev_t *dev,
                        const nfs_tnode_t *leaf, nfs_u32 slot)
{
    if (dev->tnode_width == 16) {
        const nfs_u16 *p = (const nfs_u16 *)leaf;
        return p[slot];
    } else {
        const nfs_u32 *p = (const nfs_u32 *)leaf;
        return p[slot];
    }
}

static void leaf_set(const nfs_dev_t *dev,
                     nfs_tnode_t *leaf, nfs_u32 slot, nfs_u32 val)
{
    if (dev->tnode_width == 16) {
        nfs_u16 *p = (nfs_u16 *)leaf;
        p[slot] = (nfs_u16)(val & 0xffffu);
    } else {
        nfs_u32 *p = (nfs_u32 *)leaf;
        p[slot] = val;
    }
}

/*===================================================================
 *  Tree metrics
 *===================================================================*/

int nfs_tnode_level_for_chunks(const nfs_dev_t *dev, int n_data_chunks)
{
    int level = 0;
    nfs_u32 capacity = NFS_TNODES_LEVEL0;

    while ((int)capacity < n_data_chunks + 1 &&
           level < NFS_TNODES_MAX_LEVEL) {
        capacity *= NFS_TNODES_INTERNAL;
        level++;
    }
    return level;
}

nfs_u32 nfs_tnode_slots_at_level0(const nfs_dev_t *dev, int level)
{
    nfs_u32 r = NFS_TNODES_LEVEL0;
    while (level-- > 0)
        r *= NFS_TNODES_INTERNAL;
    return r;
    (void)dev;
}

/*===================================================================
 *  Find level-0 node for chunk_id
 *===================================================================*/

nfs_tnode_t *nfs_tnode_find_level0(nfs_dev_t *dev, nfs_obj_t *obj,
                                   nfs_u32 chunk_id,
                                   nfs_u32 *level0_off,
                                   int alloc)
{
    nfs_tnode_t *tn    = obj->var.file.top;
    int          level = obj->var.file.top_level;
    nfs_u32      offset;

    /* Compute bit offset for this level */
    /* Navigate internal levels */
    while (level > 0) {
        nfs_u32 internal_slot;

        /* Bits to shift right at this level:
         *   level 1 needs bits [level0_bits + internal_bits*0 .. +int_bits)
         *   level k needs bits [level0_bits + internal_bits*(k-1) .. +int_bits)
         */
        nfs_u32 shift = NFS_TNODES_LEVEL0_BITS
                        + (nfs_u32)(level - 1) * NFS_TNODES_INTERNAL_BITS;
        internal_slot = (chunk_id >> shift) & (NFS_TNODES_INTERNAL - 1u);

        if (!tn->internal[internal_slot]) {
            if (!alloc)
                return NFS_NULL;
            tn->internal[internal_slot] = nfs_tnode_create(dev);
            if (!tn->internal[internal_slot])
                return NFS_NULL;
        }

        tn = tn->internal[internal_slot];
        level--;
    }

    /* tn is now the leaf node */
    offset = chunk_id & (NFS_TNODES_LEVEL0 - 1u);
    if (level0_off)
        *level0_off = offset;

    return tn;
}

/*===================================================================
 *  get / put chunk
 *===================================================================*/

nfs_u32 nfs_tnode_get_chunk(nfs_dev_t *dev, nfs_obj_t *obj,
                            nfs_u32 chunk_id)
{
    nfs_tnode_t *leaf;
    nfs_u32      slot;
    nfs_u32      chunk_in_nand;

    if (!obj->var.file.top)
        return 0;

    leaf = nfs_tnode_find_level0(dev, obj, chunk_id, &slot, 0);
    if (!leaf)
        return 0;

    chunk_in_nand = leaf_get(dev, leaf, slot);

    /* Convert stored offset back to absolute chunk number */
    if (chunk_in_nand) {
        chunk_in_nand += dev->chunk_offset;
    }
    return chunk_in_nand;
}

int nfs_tnode_put_chunk(nfs_dev_t *dev, nfs_obj_t *obj,
                        nfs_u32 chunk_id, nfs_u32 chunk_in_nand)
{
    nfs_tnode_t *leaf;
    nfs_u32      slot;
    int          needed_level;
    nfs_u32      stored;

    /* Grow tree if needed */
    needed_level = nfs_tnode_level_for_chunks(dev,
                       (int)chunk_id / NFS_TNODES_LEVEL0 + 1);

    while (obj->var.file.top_level < needed_level) {
        nfs_tnode_t *new_top = nfs_tnode_create(dev);
        if (!new_top)
            return NFS_ENOMEM;
        new_top->internal[0] = obj->var.file.top;
        obj->var.file.top    = new_top;
        obj->var.file.top_level++;
    }

    if (!obj->var.file.top) {
        obj->var.file.top = nfs_tnode_create(dev);
        if (!obj->var.file.top)
            return NFS_ENOMEM;
    }

    leaf = nfs_tnode_find_level0(dev, obj, chunk_id, &slot, 1);
    if (!leaf)
        return NFS_ENOMEM;

    /* Store chunk offset (relative to chunk_offset for 16-bit fit) */
    stored = chunk_in_nand ? chunk_in_nand - (nfs_u32)dev->chunk_offset : 0;
    leaf_set(dev, leaf, slot, stored);
    return NFS_OK;
}

/*===================================================================
 *  Delete all chunks in a file
 *===================================================================*/

/* Stub: decrement n_data_chunks on a file object.
 * The tnode layer doesn't have direct access to the owning object,
 * so callers (nfs_core.c) must do the actual accounting. */
static void obj_n_data_chunks_dec(nfs_dev_t *dev, nfs_u32 chunk_id)
{
    (void)dev;
    (void)chunk_id;
    /* no-op: callers handle n_data_chunks themselves */
}

static void del_chunks_recursive(nfs_dev_t *dev,
                                 nfs_tnode_t *tn, int level,
                                 nfs_u32 base_chunk_id,
                                 nfs_off_t limit_size,
                                 int del_hdr)
{
    nfs_u32 i;
    int     cpb = (int)nfs_chunks_per_block(dev);
    (void)cpb;

    if (!tn)
        return;

    if (level == 0) {
        /* Leaf node: visit each slot */
        nfs_u32 chunk_size = dev->data_bytes_per_chunk;
        for (i = 0; i < NFS_TNODES_LEVEL0; i++) {
            nfs_u32 c = leaf_get(dev, tn, i);
            if (c) {
                nfs_u32 chunk_id    = base_chunk_id + i;
                nfs_off_t file_pos  = (nfs_off_t)chunk_id * chunk_size;

                if (limit_size < 0 || file_pos >= limit_size) {
                    nfs_u32 chunk_in_nand = c + (nfs_u32)dev->chunk_offset;
                    nfs_chunk_delete(dev, (int)chunk_in_nand, 1);
                    leaf_set(dev, tn, i, 0);
                    obj_n_data_chunks_dec(dev, chunk_id);
                }
            }
        }
    } else {
        nfs_u32 span = nfs_tnode_slots_at_level0(dev, level);
        for (i = 0; i < (nfs_u32)NFS_TNODES_INTERNAL; i++) {
            nfs_u32 child_base = base_chunk_id + i * span;
            nfs_off_t child_start = (nfs_off_t)child_base
                                    * dev->data_bytes_per_chunk;
            if (limit_size < 0 || child_start >= limit_size) {
                del_chunks_recursive(dev, tn->internal[i],
                                     level - 1, child_base,
                                     limit_size, del_hdr);
                if (limit_size >= 0 && child_start >= limit_size) {
                    nfs_tnode_free_tree(dev, tn->internal[i], level - 1);
                    tn->internal[i] = NFS_NULL;
                }
            } else {
                del_chunks_recursive(dev, tn->internal[i],
                                     level - 1, child_base,
                                     limit_size, del_hdr);
            }
        }
    }
}

/* Helper: decrement n_data_chunks — handled by stub above. */

void nfs_tnode_del_file_chunks(nfs_dev_t *dev, nfs_obj_t *obj,
                                nfs_off_t limit_size)
{
    if (!obj->var.file.top)
        return;

    del_chunks_recursive(dev, obj->var.file.top,
                         obj->var.file.top_level,
                         0, limit_size, 1);

    if (limit_size < 0) {
        nfs_tnode_free_tree(dev, obj->var.file.top,
                            obj->var.file.top_level);
        obj->var.file.top       = NFS_NULL;
        obj->var.file.top_level = 0;
        obj->n_data_chunks      = 0;
    }
}

void nfs_tnode_shrink_worker(nfs_dev_t *dev, nfs_obj_t *obj,
                              nfs_off_t limit_size, int del_hdr)
{
    (void)del_hdr;
    nfs_tnode_del_file_chunks(dev, obj, limit_size);
}
