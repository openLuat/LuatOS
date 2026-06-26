/*
 * tfs_inode.h — Object (inode) lifecycle for TFS
 *
 * Covers:
 *   - allocate / free tfs_obj_t
 *   - object hash table insert / lookup / remove
 *   - read / write object header from/to NAND
 *   - update header (rename, reparent, size change)
 */

#ifndef TFS_INODE_H
#define TFS_INODE_H

#include "../inc/tfs_types.h"
#include "tfs_dev.h"

/*-------------------------------------------------------------------
 *  Hash table helpers
 *-------------------------------------------------------------------*/

/** Compute the hash bucket index for an obj_id */
static inline uint32_t tfs_obj_hash(uint32_t obj_id)
{
    return obj_id % TFS_OBJ_BUCKETS;
}

/*-------------------------------------------------------------------
 *  Allocate / free
 *-------------------------------------------------------------------*/

tfs_obj_t *tfs_obj_create(tfs_dev_t *dev, uint32_t obj_id,
                          tfs_obj_type_t type);
void       tfs_obj_free  (tfs_dev_t *dev, tfs_obj_t *obj);

/*-------------------------------------------------------------------
 *  Hash table operations
 *-------------------------------------------------------------------*/

void       tfs_obj_insert(tfs_dev_t *dev, tfs_obj_t *obj);
void       tfs_obj_remove(tfs_dev_t *dev, tfs_obj_t *obj);
tfs_obj_t *tfs_obj_find  (tfs_dev_t *dev, uint32_t obj_id);

/** Allocate a new unused obj_id */
uint32_t    tfs_obj_new_id(tfs_dev_t *dev);

/*-------------------------------------------------------------------
 *  Object header I/O
 *-------------------------------------------------------------------*/

/**
 * tfs_obj_read_hdr — read an object header from NAND
 * @chunk_in_nand:  chunk where header lives
 * @hdr:            output buffer (may be NULL to read tags only)
 * @ext:            output extended tags (may be NULL)
 * Return: TFS_OK or error
 */
int tfs_obj_read_hdr (tfs_dev_t *dev, int chunk_in_nand,
                      tfs_obj_hdr_t *hdr, tfs_ext_tags_t *ext);

/**
 * tfs_obj_write_hdr — allocate a chunk and write an object header
 * @obj:      object whose header is to be written
 * @hdr:      header data
 * @old_chunk: previous header chunk (0 = first write); deleted after write
 * Return: TFS_OK or error
 */
int tfs_obj_write_hdr(tfs_dev_t *dev, tfs_obj_t *obj,
                      tfs_obj_hdr_t *hdr, int old_chunk);

/**
 * tfs_obj_make_hdr — populate an tfs_obj_hdr_t from an in-RAM obj
 */
void tfs_obj_make_hdr(const tfs_dev_t *dev, const tfs_obj_t *obj,
                      tfs_obj_hdr_t *hdr);

/**
 * tfs_obj_load_hdr — fill in-RAM obj fields from a header + tags
 */
void tfs_obj_load_hdr(tfs_dev_t *dev, tfs_obj_t *obj,
                      const tfs_obj_hdr_t *hdr,
                      const tfs_ext_tags_t *ext,
                      int chunk_in_nand);

/**
 * tfs_obj_update_hdr — convenience: build hdr from obj and write
 */
int tfs_obj_update_hdr(tfs_dev_t *dev, tfs_obj_t *obj);

/*-------------------------------------------------------------------
 *  Object hierarchy
 *-------------------------------------------------------------------*/

/**
 * tfs_obj_add_child — add obj as a child of parent (directory)
 */
void tfs_obj_add_child   (tfs_obj_t *parent, tfs_obj_t *obj);
void tfs_obj_remove_child(tfs_obj_t *parent, tfs_obj_t *obj);

/**
 * tfs_obj_find_by_name — find a child of parent with given name
 */
tfs_obj_t *tfs_obj_find_by_name(tfs_dev_t *dev, tfs_obj_t *parent,
                                const char *name);

/*-------------------------------------------------------------------
 *  Name handling
 *-------------------------------------------------------------------*/

/** Return pointer to the object's name (short_name or NAND read) */
const char *tfs_obj_get_name(tfs_dev_t *dev, tfs_obj_t *obj);

/** Cache a name into obj->short_name, and keep full_name for long names */
void tfs_obj_cache_name(tfs_obj_t *obj, const char *name);

#endif /* TFS_INODE_H */
