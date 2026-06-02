/*
 * tfs_tnode.h — Chunk-index tree (tnode) for TFS
 *
 * Maps chunk_id → chunk_in_nand for each file object.
 * Tree depth is determined by the maximum file size and chunk size.
 * Leaf nodes hold TFS_TNODES_LEVEL0 chunk references; internal nodes
 * hold TFS_TNODES_INTERNAL pointers to child nodes.
 */

#ifndef TFS_TNODE_H
#define TFS_TNODE_H

#include "../inc/tfs_types.h"
#include "tfs_dev.h"

/*-------------------------------------------------------------------
 *  tnode allocator init / deinit
 *-------------------------------------------------------------------*/

int  tfs_tnode_init (tfs_dev_t *dev);
void tfs_tnode_deinit(tfs_dev_t *dev);

/*-------------------------------------------------------------------
 *  Allocate / free
 *-------------------------------------------------------------------*/

tfs_tnode_t *tfs_tnode_create(tfs_dev_t *dev);
void         tfs_tnode_free  (tfs_dev_t *dev, tfs_tnode_t *tn);

/** Free an entire subtree starting at level */
void tfs_tnode_free_tree(tfs_dev_t *dev, tfs_tnode_t *tn, int level);

/*-------------------------------------------------------------------
 *  Chunk index operations
 *-------------------------------------------------------------------*/

/**
 * tfs_tnode_find_level0 — return the leaf tnode for chunk_id
 * @level0_off: set to the slot index within the leaf node
 * @alloc:      if 1, allocate missing internal nodes; 0=read-only
 * Return: pointer to leaf tfs_tnode_t, or NULL if not found/OOM
 */
tfs_tnode_t *tfs_tnode_find_level0(tfs_dev_t *dev, tfs_obj_t *obj,
                                   uint32_t chunk_id,
                                   uint32_t *level0_off,
                                   int alloc);

/**
 * tfs_tnode_get_chunk — look up chunk_in_nand for chunk_id
 * Return: chunk_in_nand or 0 if not found
 */
uint32_t tfs_tnode_get_chunk(tfs_dev_t *dev, tfs_obj_t *obj,
                            uint32_t chunk_id);

/**
 * tfs_tnode_put_chunk — store chunk_in_nand for chunk_id
 * Allocates nodes as needed.
 * Return: TFS_OK or TFS_ENOMEM
 */
int tfs_tnode_put_chunk(tfs_dev_t *dev, tfs_obj_t *obj,
                        uint32_t chunk_id, uint32_t chunk_in_nand);

/**
 * tfs_tnode_del_file_chunks — delete all data chunks of a file
 * Walks the tree and calls tfs_chunk_delete for each chunk.
 * After this call the tnode tree is also freed.
 */
void tfs_tnode_del_file_chunks(tfs_dev_t *dev, tfs_obj_t *obj,
                                tfs_off_t limit_size);

/**
 * tfs_tnode_shrink_worker — remove chunks above limit_size
 * Used during truncate and shrink.
 */
void tfs_tnode_shrink_worker(tfs_dev_t *dev, tfs_obj_t *obj,
                              tfs_off_t limit_size, int del_hdr);

/*-------------------------------------------------------------------
 *  Tree metrics
 *-------------------------------------------------------------------*/

/** Return the required tree level for an object of n_data_chunks */
int tfs_tnode_level_for_chunks(const tfs_dev_t *dev, int n_data_chunks);

/** Return the number of level-0 leaf slots for a given tree level */
uint32_t tfs_tnode_slots_at_level0(const tfs_dev_t *dev, int level);

#endif /* TFS_TNODE_H */
