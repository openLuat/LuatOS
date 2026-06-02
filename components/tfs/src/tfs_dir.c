/*
 * tfs_dir.c — Path resolution and directory enumeration for TFS
 */

#include "tfs_dir.h"
#include "tfs_inode.h"
#include "tfs_core.h"
#include "../inc/tfs_config.h"

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
#define TFS_SYMLINK_DEPTH_MAX  8

static tfs_obj_t *resolve_internal(tfs_dev_t *dev, const char *path,
                                   tfs_obj_t *cwd, int follow, int depth);

static tfs_obj_t *follow_symlink(tfs_dev_t *dev, tfs_obj_t *link,
                                  int depth)
{
    if (depth >= TFS_SYMLINK_DEPTH_MAX)
        return NULL;   /* loop detected */

    if (!link->var.symlink.alias)
        return NULL;

    return resolve_internal(dev, link->var.symlink.alias,
                            dev->root_dir, 1, depth + 1);
}

static tfs_obj_t *resolve_internal(tfs_dev_t *dev, const char *path,
                                   tfs_obj_t *cwd, int follow, int depth)
{
    char       comp[TFS_MAX_NAME_LEN + 1];
    tfs_obj_t *cur;

    if (!path || !*path)
        return cwd;

    cur = (*path == '/') ? dev->root_dir : cwd;
    if (!cur) return NULL;

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

        if (cur->obj_type != TFS_OBJ_TYPE_DIR)
            return NULL;

        tfs_obj_t *child = tfs_obj_find_by_name(dev, cur, comp);
        if (!child)
            return NULL;

        /* Follow intermediate symlinks always */
        if (child->obj_type == TFS_OBJ_TYPE_SYMLINK && *path) {
            child = follow_symlink(dev, child, depth);
            if (!child) return NULL;
        }

        cur = child;
    }

    /* Follow final component only if requested */
    if (follow && cur && cur->obj_type == TFS_OBJ_TYPE_SYMLINK)
        cur = follow_symlink(dev, cur, depth);

    return cur;
}

/*===================================================================
 *  Public path resolution
 *===================================================================*/

tfs_obj_t *tfs_resolve_path(tfs_dev_t *dev, const char *path,
                             tfs_obj_t *cwd, int follow)
{
    return resolve_internal(dev, path, cwd, follow, 0);
}

tfs_obj_t *tfs_resolve_parent(tfs_dev_t *dev, const char *path,
                               tfs_obj_t *cwd, char *name_out)
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
        strncpy(name_out, path, TFS_MAX_NAME_LEN);
        name_out[TFS_MAX_NAME_LEN] = '\0';
        return cwd;
    }

    /* Copy parent portion */
    {
        char parent_path[TFS_MAX_PATH_LEN + 1];
        size_t plen = (size_t)(last - path);
        if (plen == 0) plen = 1;  /* root "/" */
        if (plen >= sizeof(parent_path)) plen = sizeof(parent_path) - 1;
        memcpy(parent_path, path, plen);
        parent_path[plen] = '\0';

        strncpy(name_out, last + 1, TFS_MAX_NAME_LEN);
        name_out[TFS_MAX_NAME_LEN] = '\0';

        return tfs_resolve_path(dev, parent_path, cwd, 1);
    }
}

/*===================================================================
 *  Directory handle
 *===================================================================*/

tfs_dir_handle_t *tfs_dir_open(tfs_dev_t *dev, tfs_obj_t *dir)
{
    tfs_dir_handle_t *dh;

    if (!dir || dir->obj_type != TFS_OBJ_TYPE_DIR)
        return NULL;

    dh = (tfs_dir_handle_t *)dev->drv.malloc(dev->drv.ctx,
                                              sizeof(tfs_dir_handle_t));
    if (!dh)
        return NULL;

    dh->dev        = dev;
    dh->dir        = dir;
    dh->next_child = dir->var.dir.children.next;
    return dh;
}

int tfs_dir_read(tfs_dir_handle_t *dh, tfs_dirent_t *de)
{
    tfs_obj_t    *child;
    tfs_obj_t    *dir = dh->dir;
    const char   *name;

    if (dh->next_child == &dir->var.dir.children)
        return 0;  /* end of directory */

    child = tfs_list_entry(dh->next_child, tfs_obj_t, siblings);
    dh->next_child = dh->next_child->next;

    name = tfs_obj_get_name(dh->dev, child);
    if (!name) name = "";

    strncpy(de->d_name, name, TFS_MAX_NAME_LEN);
    de->d_name[TFS_MAX_NAME_LEN] = '\0';
    de->d_ino  = child->obj_id;

    switch (child->obj_type) {
    case TFS_OBJ_TYPE_FILE:     de->d_type = TFS_DT_REG;     break;
    case TFS_OBJ_TYPE_DIR:      de->d_type = TFS_DT_DIR;     break;
    case TFS_OBJ_TYPE_SYMLINK:  de->d_type = TFS_DT_LNK;     break;
    default:                    de->d_type = TFS_DT_UNKNOWN;  break;
    }

    return 1;
}

void tfs_dir_close(tfs_dir_handle_t *dh)
{
    if (dh)
        dh->dev->drv.free(dh->dev->drv.ctx, dh);
}
