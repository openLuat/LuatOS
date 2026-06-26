/*
 * tfs_verify.h — Debug / integrity checks for TFS
 */

#ifndef TFS_VERIFY_H
#define TFS_VERIFY_H

#include "../inc/tfs_types.h"
#include "tfs_dev.h"

/**
 * tfs_verify_device — run a full in-RAM consistency check.
 * Checks:
 *   - block_info pages_in_use matches chunk bitmap
 *   - every object in hash table has a valid hdr_chunk
 *   - no two objects share the same obj_id
 *   - tnode trees point to used chunks
 * Return: number of errors found (0 = clean)
 */
int tfs_verify_device(tfs_dev_t *dev);

/**
 * tfs_verify_obj — check a single object's tnode tree
 */
int tfs_verify_obj(tfs_dev_t *dev, tfs_obj_t *obj);

#endif /* TFS_VERIFY_H */
