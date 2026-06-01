/*
 * nfs_verify.h — Debug / integrity checks for NFS
 */

#ifndef NFS_VERIFY_H
#define NFS_VERIFY_H

#include "../inc/nfs_types.h"
#include "nfs_dev.h"

/**
 * nfs_verify_device — run a full in-RAM consistency check.
 * Checks:
 *   - block_info pages_in_use matches chunk bitmap
 *   - every object in hash table has a valid hdr_chunk
 *   - no two objects share the same obj_id
 *   - tnode trees point to used chunks
 * Return: number of errors found (0 = clean)
 */
int nfs_verify_device(nfs_dev_t *dev);

/**
 * nfs_verify_obj — check a single object's tnode tree
 */
int nfs_verify_obj(nfs_dev_t *dev, nfs_obj_t *obj);

#endif /* NFS_VERIFY_H */
