/*
 * nfs_inode.h — Object (inode) lifecycle for NFS
 *
 * Covers:
 *   - allocate / free nfs_obj_t
 *   - object hash table insert / lookup / remove
 *   - read / write object header from/to NAND
 *   - update header (rename, reparent, size change)
 */

#ifndef NFS_INODE_H
#define NFS_INODE_H

#include "../inc/nfs_types.h"
#include "nfs_dev.h"

/*-------------------------------------------------------------------
 *  Hash table helpers
 *-------------------------------------------------------------------*/

/** Compute the hash bucket index for an obj_id */
static inline nfs_u32 nfs_obj_hash(nfs_u32 obj_id)
{
    return obj_id % NFS_OBJ_BUCKETS;
}

/*-------------------------------------------------------------------
 *  Allocate / free
 *-------------------------------------------------------------------*/

nfs_obj_t *nfs_obj_create(nfs_dev_t *dev, nfs_u32 obj_id,
                          nfs_obj_type_t type);
void       nfs_obj_free  (nfs_dev_t *dev, nfs_obj_t *obj);

/*-------------------------------------------------------------------
 *  Hash table operations
 *-------------------------------------------------------------------*/

void       nfs_obj_insert(nfs_dev_t *dev, nfs_obj_t *obj);
void       nfs_obj_remove(nfs_dev_t *dev, nfs_obj_t *obj);
nfs_obj_t *nfs_obj_find  (nfs_dev_t *dev, nfs_u32 obj_id);

/** Allocate a new unused obj_id */
nfs_u32    nfs_obj_new_id(nfs_dev_t *dev);

/*-------------------------------------------------------------------
 *  Object header I/O
 *-------------------------------------------------------------------*/

/**
 * nfs_obj_read_hdr — read an object header from NAND
 * @chunk_in_nand:  chunk where header lives
 * @hdr:            output buffer (may be NULL to read tags only)
 * @ext:            output extended tags (may be NULL)
 * Return: NFS_OK or error
 */
int nfs_obj_read_hdr (nfs_dev_t *dev, int chunk_in_nand,
                      nfs_obj_hdr_t *hdr, nfs_ext_tags_t *ext);

/**
 * nfs_obj_write_hdr — allocate a chunk and write an object header
 * @obj:      object whose header is to be written
 * @hdr:      header data
 * @old_chunk: previous header chunk (0 = first write); deleted after write
 * Return: NFS_OK or error
 */
int nfs_obj_write_hdr(nfs_dev_t *dev, nfs_obj_t *obj,
                      nfs_obj_hdr_t *hdr, int old_chunk);

/**
 * nfs_obj_make_hdr — populate an nfs_obj_hdr_t from an in-RAM obj
 */
void nfs_obj_make_hdr(const nfs_dev_t *dev, const nfs_obj_t *obj,
                      nfs_obj_hdr_t *hdr);

/**
 * nfs_obj_load_hdr — fill in-RAM obj fields from a header + tags
 */
void nfs_obj_load_hdr(nfs_dev_t *dev, nfs_obj_t *obj,
                      const nfs_obj_hdr_t *hdr,
                      const nfs_ext_tags_t *ext,
                      int chunk_in_nand);

/**
 * nfs_obj_update_hdr — convenience: build hdr from obj and write
 */
int nfs_obj_update_hdr(nfs_dev_t *dev, nfs_obj_t *obj);

/*-------------------------------------------------------------------
 *  Object hierarchy
 *-------------------------------------------------------------------*/

/**
 * nfs_obj_add_child — add obj as a child of parent (directory)
 */
void nfs_obj_add_child   (nfs_obj_t *parent, nfs_obj_t *obj);
void nfs_obj_remove_child(nfs_obj_t *parent, nfs_obj_t *obj);

/**
 * nfs_obj_find_by_name — find a child of parent with given name
 */
nfs_obj_t *nfs_obj_find_by_name(nfs_dev_t *dev, nfs_obj_t *parent,
                                const char *name);

/*-------------------------------------------------------------------
 *  Name handling
 *-------------------------------------------------------------------*/

/** Return pointer to the object's name (short_name or NAND read) */
const char *nfs_obj_get_name(nfs_dev_t *dev, nfs_obj_t *obj);

/** Cache a name into obj->short_name if it fits */
void nfs_obj_cache_name(nfs_obj_t *obj, const char *name);

#endif /* NFS_INODE_H */
