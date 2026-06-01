/*
 * nfs_dir.h — Path resolution and directory enumeration for NFS
 */

#ifndef NFS_DIR_H
#define NFS_DIR_H

#include "../inc/nfs_types.h"
#include "nfs_dev.h"

/*-------------------------------------------------------------------
 *  Path resolution
 *-------------------------------------------------------------------*/

/**
 * nfs_resolve_path — walk a path string and return the target object
 * @dev:    device
 * @path:   absolute or relative path (absolute assumed if starts with '/')
 * @cwd:    current working directory (used when path is relative)
 * @follow: 1 = follow symlinks; 0 = return symlink object itself
 * Return:  object pointer or NULL (sets errno equivalent)
 */
nfs_obj_t *nfs_resolve_path(nfs_dev_t *dev, const char *path,
                             nfs_obj_t *cwd, int follow);

/**
 * nfs_resolve_parent — resolve path up to the last component, return
 * the parent directory and set *name_out to the final component.
 * name_out must point to a buffer of at least NFS_MAX_NAME_LEN+1 bytes.
 */
nfs_obj_t *nfs_resolve_parent(nfs_dev_t *dev, const char *path,
                               nfs_obj_t *cwd, char *name_out);

/*-------------------------------------------------------------------
 *  Directory handle (for opendir / readdir / closedir)
 *-------------------------------------------------------------------*/

typedef struct {
    nfs_dev_t  *dev;
    nfs_obj_t  *dir;
    nfs_list_t *next_child;     /* pointer into dir.children list */
} nfs_dir_handle_t;

nfs_dir_handle_t *nfs_dir_open (nfs_dev_t *dev, nfs_obj_t *dir);
int               nfs_dir_read (nfs_dir_handle_t *dh, nfs_dirent_t *de);
void              nfs_dir_close(nfs_dir_handle_t *dh);

#endif /* NFS_DIR_H */
