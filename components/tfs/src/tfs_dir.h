/*
 * tfs_dir.h — Path resolution and directory enumeration for TFS
 */

#ifndef TFS_DIR_H
#define TFS_DIR_H

#include "../inc/tfs_types.h"
#include "tfs_dev.h"

/*-------------------------------------------------------------------
 *  Path resolution
 *-------------------------------------------------------------------*/

/**
 * tfs_resolve_path — walk a path string and return the target object
 * @dev:    device
 * @path:   absolute or relative path (absolute assumed if starts with '/')
 * @cwd:    current working directory (used when path is relative)
 * @follow: 1 = follow symlinks; 0 = return symlink object itself
 * Return:  object pointer or NULL (sets errno equivalent)
 */
tfs_obj_t *tfs_resolve_path(tfs_dev_t *dev, const char *path,
                             tfs_obj_t *cwd, int follow);

/**
 * tfs_resolve_parent — resolve path up to the last component, return
 * the parent directory and set *name_out to the final component.
 * name_out must point to a buffer of at least TFS_MAX_NAME_LEN+1 bytes.
 */
tfs_obj_t *tfs_resolve_parent(tfs_dev_t *dev, const char *path,
                               tfs_obj_t *cwd, char *name_out);

/*-------------------------------------------------------------------
 *  Directory handle (for opendir / readdir / closedir)
 *-------------------------------------------------------------------*/

typedef struct {
    tfs_dev_t  *dev;
    tfs_obj_t  *dir;
    tfs_list_t *next_child;     /* pointer into dir.children list */
} tfs_dir_handle_t;

tfs_dir_handle_t *tfs_dir_open (tfs_dev_t *dev, tfs_obj_t *dir);
int               tfs_dir_read (tfs_dir_handle_t *dh, tfs_dirent_t *de);
void              tfs_dir_close(tfs_dir_handle_t *dh);

#endif /* TFS_DIR_H */
