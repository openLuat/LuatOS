/*
 * nfs_dir.c — Path resolution and directory enumeration for NFS
 */

#include "nfs_dir.h"
#include "nfs_inode.h"
#include "nfs_core.h"
#include "../inc/nfs_config.h"

#include <string.h>

/*===================================================================
 *  Internal helpers
 *===================================================================*/

/* Copy path component from src into buf, return pointer past component */
static const char *next_component(const char *path, char *buf, int buf_sz)
{
    int i = 0;

    while (*path == '/')
        path++;

    while (*path && *path != '/' && i < buf_sz - 1)
        buf[i++] = *path++;

    buf[i] = '\0';

    while (*path == '/')
        path++;

    return path;
}

/* Symlink depth counter (prevent loops) */
#define NFS_SYMLINK_DEPTH_MAX  8

static nfs_obj_t *resolve_internal(nfs_dev_t *dev, const char *path,
                                   nfs_obj_t *cwd, int follow, int depth);

static nfs_obj_t *follow_symlink(nfs_dev_t *dev, nfs_obj_t *link,
                                  int depth)
{
    if (depth >= NFS_SYMLINK_DEPTH_MAX)
        return NFS_NULL;   /* loop detected */

    if (!link->var.symlink.alias)
        return NFS_NULL;

    return resolve_internal(dev, link->var.symlink.alias,
                            dev->root_dir, 1, depth + 1);
}

static nfs_obj_t *resolve_internal(nfs_dev_t *dev, const char *path,
                                   nfs_obj_t *cwd, int follow, int depth)
{
    char       comp[NFS_MAX_NAME_LEN + 1];
    nfs_obj_t *cur;

    if (!path || !*path)
        return cwd;

    cur = (*path == '/') ? dev->root_dir : cwd;
    if (!cur) return NFS_NULL;

    while (*path) {
        path = next_component(path, comp, sizeof(comp));

        if (comp[0] == '\0')
            break;

        if (strcmp(comp, ".") == 0)
            continue;

        if (strcmp(comp, "..") == 0) {
            if (cur->parent)
                cur = cur->parent;
            continue;
        }

        if (cur->obj_type != NFS_OBJ_TYPE_DIR)
            return NFS_NULL;

        nfs_obj_t *child = nfs_obj_find_by_name(dev, cur, comp);
        if (!child)
            return NFS_NULL;

        /* Follow intermediate symlinks always */
        if (child->obj_type == NFS_OBJ_TYPE_SYMLINK && *path) {
            child = follow_symlink(dev, child, depth);
            if (!child) return NFS_NULL;
        }

        cur = child;
    }

    /* Follow final component only if requested */
    if (follow && cur && cur->obj_type == NFS_OBJ_TYPE_SYMLINK)
        cur = follow_symlink(dev, cur, depth);

    return cur;
}

/*===================================================================
 *  Public path resolution
 *===================================================================*/

nfs_obj_t *nfs_resolve_path(nfs_dev_t *dev, const char *path,
                             nfs_obj_t *cwd, int follow)
{
    return resolve_internal(dev, path, cwd, follow, 0);
}

nfs_obj_t *nfs_resolve_parent(nfs_dev_t *dev, const char *path,
                               nfs_obj_t *cwd, char *name_out)
{
    /* Find the last '/' in path */
    const char *last = path;
    const char *p    = path;

    while (*p) {
        if (*p == '/')
            last = p;
        p++;
    }

    if (last == path && *path != '/') {
        /* No slash: parent is cwd */
        strncpy(name_out, path, NFS_MAX_NAME_LEN);
        name_out[NFS_MAX_NAME_LEN] = '\0';
        return cwd;
    }

    /* Copy parent portion */
    {
        char parent_path[NFS_MAX_PATH_LEN + 1];
        size_t plen = (size_t)(last - path);
        if (plen == 0) plen = 1;  /* root "/" */
        if (plen >= sizeof(parent_path)) plen = sizeof(parent_path) - 1;
        memcpy(parent_path, path, plen);
        parent_path[plen] = '\0';

        strncpy(name_out, last + 1, NFS_MAX_NAME_LEN);
        name_out[NFS_MAX_NAME_LEN] = '\0';

        return nfs_resolve_path(dev, parent_path, cwd, 1);
    }
}

/*===================================================================
 *  Directory handle
 *===================================================================*/

nfs_dir_handle_t *nfs_dir_open(nfs_dev_t *dev, nfs_obj_t *dir)
{
    nfs_dir_handle_t *dh;

    if (!dir || dir->obj_type != NFS_OBJ_TYPE_DIR)
        return NFS_NULL;

    dh = (nfs_dir_handle_t *)dev->drv.malloc(dev->drv.ctx,
                                              sizeof(nfs_dir_handle_t));
    if (!dh)
        return NFS_NULL;

    dh->dev        = dev;
    dh->dir        = dir;
    dh->next_child = dir->var.dir.children.next;
    return dh;
}

int nfs_dir_read(nfs_dir_handle_t *dh, nfs_dirent_t *de)
{
    nfs_obj_t    *child;
    nfs_obj_t    *dir = dh->dir;
    const char   *name;

    if (dh->next_child == &dir->var.dir.children)
        return 0;  /* end of directory */

    child = nfs_list_entry(dh->next_child, nfs_obj_t, siblings);
    dh->next_child = dh->next_child->next;

    name = nfs_obj_get_name(dh->dev, child);
    if (!name) name = "";

    strncpy(de->d_name, name, NFS_MAX_NAME_LEN);
    de->d_name[NFS_MAX_NAME_LEN] = '\0';
    de->d_ino  = child->obj_id;

    switch (child->obj_type) {
    case NFS_OBJ_TYPE_FILE:     de->d_type = NFS_DT_REG;     break;
    case NFS_OBJ_TYPE_DIR:      de->d_type = NFS_DT_DIR;     break;
    case NFS_OBJ_TYPE_SYMLINK:  de->d_type = NFS_DT_LNK;     break;
    default:                    de->d_type = NFS_DT_UNKNOWN;  break;
    }

    return 1;
}

void nfs_dir_close(nfs_dir_handle_t *dh)
{
    if (dh)
        dh->dev->drv.free(dh->dev->drv.ctx, dh);
}
