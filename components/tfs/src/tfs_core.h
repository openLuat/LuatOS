/*
 * tfs_core.h — Mount, scan, GC and device management for TFS
 */

#ifndef TFS_CORE_H
#define TFS_CORE_H

#include "../inc/tfs_types.h"
#include "tfs_dev.h"

/*-------------------------------------------------------------------
 *  Global device list
 *-------------------------------------------------------------------*/

/** Register a device and initialise all in-RAM structures */
int  tfs_core_add_device   (tfs_dev_t *dev);
void tfs_core_remove_device(tfs_dev_t *dev);

/** Find a mounted device by name */
tfs_dev_t *tfs_core_find_dev(const char *name);

/*-------------------------------------------------------------------
 *  Mount / unmount / format
 *-------------------------------------------------------------------*/

int tfs_core_mount  (tfs_dev_t *dev);
int tfs_core_unmount(tfs_dev_t *dev);
int tfs_core_format (tfs_dev_t *dev);
int tfs_core_sync   (tfs_dev_t *dev);

/*-------------------------------------------------------------------
 *  Garbage collection
 *-------------------------------------------------------------------*/

/**
 * tfs_gc — run one GC pass
 * @aggressive: 1 = force collection even when plenty of space exists
 * Return: TFS_OK or error
 */
int tfs_gc(tfs_dev_t *dev, int aggressive);

/**
 * tfs_gc_enough_space — return 1 if there are enough free chunks for
 * the next write (subject to TFS_CFG_RESERVED_BLOCKS).
 */
int tfs_gc_enough_space(tfs_dev_t *dev);

/*-------------------------------------------------------------------
 *  File data I/O (used by tfs_fs.c)
 *-------------------------------------------------------------------*/

int tfs_file_read  (tfs_dev_t *dev, tfs_obj_t *obj,
                    uint8_t *buf, tfs_off_t offset, int n_bytes);

int tfs_file_write (tfs_dev_t *dev, tfs_obj_t *obj,
                    const uint8_t *buf, tfs_off_t offset, int n_bytes);

int tfs_file_flush (tfs_dev_t *dev, tfs_obj_t *obj);

int tfs_file_resize(tfs_dev_t *dev, tfs_obj_t *obj, tfs_off_t new_size);

/*-------------------------------------------------------------------
 *  Object creation / deletion
 *-------------------------------------------------------------------*/

tfs_obj_t *tfs_create_obj(tfs_dev_t *dev, tfs_obj_t *parent,
                          const char *name, uint32_t mode,
                          tfs_obj_type_t type);

int tfs_unlink_obj  (tfs_dev_t *dev, tfs_obj_t *obj);
int tfs_rename_obj  (tfs_dev_t *dev, tfs_obj_t *obj,
                     tfs_obj_t *new_parent, const char *new_name);

tfs_obj_t *tfs_create_symlink(tfs_dev_t *dev, tfs_obj_t *parent,
                              const char *name, uint32_t mode,
                              const char *alias);

tfs_obj_t *tfs_create_hardlink(tfs_dev_t *dev, tfs_obj_t *parent,
                               const char *name, tfs_obj_t *equiv);

/*-------------------------------------------------------------------
 *  Path resolution
 *-------------------------------------------------------------------*/

tfs_obj_t *tfs_core_find_by_name(tfs_dev_t *dev, tfs_obj_t *dir,
                                  const char *name);

/*-------------------------------------------------------------------
 *  Statistics
 *-------------------------------------------------------------------*/

tfs_off_t tfs_core_free_space (const tfs_dev_t *dev);
tfs_off_t tfs_core_total_space(const tfs_dev_t *dev);

#endif /* TFS_CORE_H */
