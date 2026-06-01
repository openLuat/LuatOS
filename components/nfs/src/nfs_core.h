/*
 * nfs_core.h — Mount, scan, GC and device management for NFS
 */

#ifndef NFS_CORE_H
#define NFS_CORE_H

#include "../inc/nfs_types.h"
#include "nfs_dev.h"

/*-------------------------------------------------------------------
 *  Global device list
 *-------------------------------------------------------------------*/

/** Register a device and initialise all in-RAM structures */
int  nfs_core_add_device   (nfs_dev_t *dev);
void nfs_core_remove_device(nfs_dev_t *dev);

/** Find a mounted device by name */
nfs_dev_t *nfs_core_find_dev(const char *name);

/*-------------------------------------------------------------------
 *  Mount / unmount / format
 *-------------------------------------------------------------------*/

int nfs_core_mount  (nfs_dev_t *dev);
int nfs_core_unmount(nfs_dev_t *dev);
int nfs_core_format (nfs_dev_t *dev);
int nfs_core_sync   (nfs_dev_t *dev);

/*-------------------------------------------------------------------
 *  Garbage collection
 *-------------------------------------------------------------------*/

/**
 * nfs_gc — run one GC pass
 * @aggressive: 1 = force collection even when plenty of space exists
 * Return: NFS_OK or error
 */
int nfs_gc(nfs_dev_t *dev, int aggressive);

/**
 * nfs_gc_enough_space — return 1 if there are enough free chunks for
 * the next write (subject to NFS_CFG_RESERVED_BLOCKS).
 */
int nfs_gc_enough_space(nfs_dev_t *dev);

/*-------------------------------------------------------------------
 *  File data I/O (used by nfs_fs.c)
 *-------------------------------------------------------------------*/

int nfs_file_read  (nfs_dev_t *dev, nfs_obj_t *obj,
                    nfs_u8 *buf, nfs_off_t offset, int n_bytes);

int nfs_file_write (nfs_dev_t *dev, nfs_obj_t *obj,
                    const nfs_u8 *buf, nfs_off_t offset, int n_bytes);

int nfs_file_flush (nfs_dev_t *dev, nfs_obj_t *obj);

int nfs_file_resize(nfs_dev_t *dev, nfs_obj_t *obj, nfs_off_t new_size);

/*-------------------------------------------------------------------
 *  Object creation / deletion
 *-------------------------------------------------------------------*/

nfs_obj_t *nfs_create_obj(nfs_dev_t *dev, nfs_obj_t *parent,
                          const char *name, nfs_u32 mode,
                          nfs_obj_type_t type);

int nfs_unlink_obj  (nfs_dev_t *dev, nfs_obj_t *obj);
int nfs_rename_obj  (nfs_dev_t *dev, nfs_obj_t *obj,
                     nfs_obj_t *new_parent, const char *new_name);

nfs_obj_t *nfs_create_symlink(nfs_dev_t *dev, nfs_obj_t *parent,
                              const char *name, nfs_u32 mode,
                              const char *alias);

nfs_obj_t *nfs_create_hardlink(nfs_dev_t *dev, nfs_obj_t *parent,
                               const char *name, nfs_obj_t *equiv);

/*-------------------------------------------------------------------
 *  Path resolution
 *-------------------------------------------------------------------*/

nfs_obj_t *nfs_core_find_by_name(nfs_dev_t *dev, nfs_obj_t *dir,
                                  const char *name);

/*-------------------------------------------------------------------
 *  Statistics
 *-------------------------------------------------------------------*/

nfs_off_t nfs_core_free_space (const nfs_dev_t *dev);
nfs_off_t nfs_core_total_space(const nfs_dev_t *dev);

#endif /* NFS_CORE_H */
