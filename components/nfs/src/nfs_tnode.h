/*
 * nfs_tnode.h — Chunk-index tree (tnode) for NFS
 *
 * Maps chunk_id → chunk_in_nand for each file object.
 * Tree depth is determined by the maximum file size and chunk size.
 * Leaf nodes hold NFS_TNODES_LEVEL0 chunk references; internal nodes
 * hold NFS_TNODES_INTERNAL pointers to child nodes.
 */

#ifndef NFS_TNODE_H
#define NFS_TNODE_H

#include "../inc/nfs_types.h"
#include "nfs_dev.h"

/*-------------------------------------------------------------------
 *  tnode allocator init / deinit
 *-------------------------------------------------------------------*/

int  nfs_tnode_init (nfs_dev_t *dev);
void nfs_tnode_deinit(nfs_dev_t *dev);

/*-------------------------------------------------------------------
 *  Allocate / free
 *-------------------------------------------------------------------*/

nfs_tnode_t *nfs_tnode_create(nfs_dev_t *dev);
void         nfs_tnode_free  (nfs_dev_t *dev, nfs_tnode_t *tn);

/** Free an entire subtree starting at level */
void nfs_tnode_free_tree(nfs_dev_t *dev, nfs_tnode_t *tn, int level);

/*-------------------------------------------------------------------
 *  Chunk index operations
 *-------------------------------------------------------------------*/

/**
 * nfs_tnode_find_level0 — return the leaf tnode for chunk_id
 * @level0_off: set to the slot index within the leaf node
 * @alloc:      if 1, allocate missing internal nodes; 0=read-only
 * Return: pointer to leaf nfs_tnode_t, or NULL if not found/OOM
 */
nfs_tnode_t *nfs_tnode_find_level0(nfs_dev_t *dev, nfs_obj_t *obj,
                                   nfs_u32 chunk_id,
                                   nfs_u32 *level0_off,
                                   int alloc);

/**
 * nfs_tnode_get_chunk — look up chunk_in_nand for chunk_id
 * Return: chunk_in_nand or 0 if not found
 */
nfs_u32 nfs_tnode_get_chunk(nfs_dev_t *dev, nfs_obj_t *obj,
                            nfs_u32 chunk_id);

/**
 * nfs_tnode_put_chunk — store chunk_in_nand for chunk_id
 * Allocates nodes as needed.
 * Return: NFS_OK or NFS_ENOMEM
 */
int nfs_tnode_put_chunk(nfs_dev_t *dev, nfs_obj_t *obj,
                        nfs_u32 chunk_id, nfs_u32 chunk_in_nand);

/**
 * nfs_tnode_del_file_chunks — delete all data chunks of a file
 * Walks the tree and calls nfs_chunk_delete for each chunk.
 * After this call the tnode tree is also freed.
 */
void nfs_tnode_del_file_chunks(nfs_dev_t *dev, nfs_obj_t *obj,
                                nfs_off_t limit_size);

/**
 * nfs_tnode_shrink_worker — remove chunks above limit_size
 * Used during truncate and shrink.
 */
void nfs_tnode_shrink_worker(nfs_dev_t *dev, nfs_obj_t *obj,
                              nfs_off_t limit_size, int del_hdr);

/*-------------------------------------------------------------------
 *  Tree metrics
 *-------------------------------------------------------------------*/

/** Return the required tree level for an object of n_data_chunks */
int nfs_tnode_level_for_chunks(const nfs_dev_t *dev, int n_data_chunks);

/** Return the number of level-0 leaf slots for a given tree level */
nfs_u32 nfs_tnode_slots_at_level0(const nfs_dev_t *dev, int level);

#endif /* NFS_TNODE_H */
