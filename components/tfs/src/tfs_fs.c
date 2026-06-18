/*
 * tfs_fs.c — POSIX-style file descriptor layer for TFS
 *
 * Implements the public API declared in inc/nfs.h.
 *
 * Three-layer design:
 *   Handle (tfs_fd_t)   — open file descriptor, tracks position
 *   Object (tfs_obj_t)  — in-RAM inode
 *   NAND               — managed by tfs_core / tfs_block
 */

#include "../inc/tfs.h"
#include "../inc/tfs_port.h"
#include "tfs_dev.h"
#include "tfs_core.h"
#include "tfs_dir.h"
#include "tfs_inode.h"
#include "tfs_cache.h"
#include "tfs_checkpoint.h"
#include "../inc/tfs_config.h"

#include <string.h>

/*===================================================================
 *  File descriptor table
 *===================================================================*/

typedef struct {
    int        in_use;
    tfs_dev_t *dev;
    tfs_obj_t *obj;
    tfs_off_t  pos;
    int        flags;
} tfs_fd_t;

static tfs_fd_t g_fd_table[TFS_CFG_MAX_HANDLES];

/* Directory handle table */
typedef struct {
    int               in_use;
    tfs_dir_handle_t *dh;
} tfs_dfd_t;

static tfs_dfd_t g_dfd_table[TFS_CFG_MAX_HANDLES];

/* Per-thread/global error */
static int g_last_error = TFS_OK;

static tfs_dev_t *g_devices[TFS_CFG_MAX_DEVICES];
static int        g_n_devices = 0;

/*===================================================================
 *  Helpers
 *===================================================================*/

static void set_err(int err)
{
    g_last_error = err;
}

static int alloc_fd(void)
{
    int i;
    for (i = 0; i < TFS_CFG_MAX_HANDLES; i++) {
        if (!g_fd_table[i].in_use) {
            g_fd_table[i].in_use = 1;
            return i;
        }
    }
    return -1;
}

static int alloc_dfd(void)
{
    int i;
    for (i = 0; i < TFS_CFG_MAX_HANDLES; i++) {
        if (!g_dfd_table[i].in_use) {
            g_dfd_table[i].in_use = 1;
            return i;
        }
    }
    return -1;
}

static tfs_fd_t *get_fd(int fd)
{
    if (fd < 0 || fd >= TFS_CFG_MAX_HANDLES || !g_fd_table[fd].in_use)
        return NULL;
    return &g_fd_table[fd];
}

static int open_accmode(int flags)
{
    return flags & (TFS_O_WRONLY | TFS_O_RDWR);
}

static int open_accmode_valid(int flags)
{
    return open_accmode(flags) != (TFS_O_WRONLY | TFS_O_RDWR);
}

/* Find the device for a path (first '/' → default device).
 * Paths have the form "/<devname>/rest/of/path".
 * Falls back to the first registered device for bare "/" paths. */
static tfs_dev_t *dev_for_path(const char *path, const char **path_out)
{
    tfs_dev_t *dev;

    *path_out = path;

    if (path && path[0] == '/') {
        char vol[32];
        const char *p = path + 1;
        int i = 0;
        while (*p && *p != '/' && i < 31)
            vol[i++] = *p++;
        vol[i] = '\0';
        dev = tfs_core_find_dev(vol);
        if (dev) {
            *path_out = (*p == '/') ? p : "/";
            return dev;
        }
    }

    /* Fall back to first registered mounted device */
    {
        int i;
        for (i = 0; i < g_n_devices; i++) {
            if (g_devices[i] && g_devices[i]->is_mounted)
                return g_devices[i];
        }
    }

    return NULL;
}

/*===================================================================
 *  Public API implementation
 *===================================================================*/

int tfs_init(void)
{
    memset(g_fd_table,  0, sizeof(g_fd_table));
    memset(g_dfd_table, 0, sizeof(g_dfd_table));
    g_last_error = TFS_OK;
    return TFS_OK;
}

int tfs_get_error(void)
{
    return g_last_error;
}

/*-------------------------------------------------------------------
 *  Device management
 *-------------------------------------------------------------------*/

int tfs_add_device(const char *name, const tfs_drv_t *drv,
                   const tfs_geo_t *geo)
{
    tfs_dev_t *dev;
    tfs_param_t param;

    if (g_n_devices >= TFS_CFG_MAX_DEVICES) {
        set_err(TFS_ENOMEM);
        return TFS_ENOMEM;
    }

    dev = (tfs_dev_t *)drv->malloc(drv->ctx, sizeof(tfs_dev_t));
    if (!dev) { set_err(TFS_ENOMEM); return TFS_ENOMEM; }

    memset(dev, 0, sizeof(tfs_dev_t));
    memset(&param, 0, sizeof(param));
    param.name = name;
    param.geo  = *geo;

    dev->param = param;
    dev->drv   = *drv;

    tfs_core_add_device(dev);
    g_devices[g_n_devices++] = dev;
    return TFS_OK;
}

int tfs_remove_device(const char *name)
{
    int i;
    for (i = 0; i < g_n_devices; i++) {
        if (g_devices[i] && strcmp(g_devices[i]->param.name, name) == 0) {
            int rc = tfs_core_unmount(g_devices[i]);
            if (rc != TFS_OK) {
                set_err(rc);
                return rc;
            }
            tfs_core_remove_device(g_devices[i]);
            g_devices[i]->drv.free(g_devices[i]->drv.ctx, g_devices[i]);
            g_devices[i] = NULL;
            g_n_devices--;
            return TFS_OK;
        }
    }
    return TFS_ENODEV;
}

/*-------------------------------------------------------------------
 *  Mount / unmount / format / sync
 *-------------------------------------------------------------------*/

int tfs_mount(const char *dev_name)
{
    tfs_dev_t *dev = tfs_core_find_dev(dev_name);
    if (!dev) { set_err(TFS_ENODEV); return TFS_ENODEV; }

    int rc = tfs_core_mount(dev);
    if (rc != TFS_OK) set_err(rc);
    return rc;
}

int tfs_unmount(const char *dev_name)
{
    tfs_dev_t *dev = tfs_core_find_dev(dev_name);
    if (!dev) { set_err(TFS_ENODEV); return TFS_ENODEV; }

    int rc = tfs_core_unmount(dev);
    if (rc != TFS_OK) set_err(rc);
    return rc;
}

int tfs_format(const char *dev_name)
{
    tfs_dev_t *dev = tfs_core_find_dev(dev_name);
    if (!dev) { set_err(TFS_ENODEV); return TFS_ENODEV; }

    int rc = tfs_core_format(dev);
    if (rc != TFS_OK) set_err(rc);
    return rc;
}

int tfs_sync(const char *dev_name)
{
    tfs_dev_t *dev = tfs_core_find_dev(dev_name);
    if (!dev) { set_err(TFS_ENODEV); return TFS_ENODEV; }

    int rc = tfs_core_sync(dev);
    if (rc != TFS_OK) set_err(rc);
    return rc;
}

/*-------------------------------------------------------------------
 *  open / close / read / write / lseek / fsync
 *-------------------------------------------------------------------*/

int tfs_open(const char *path, int flags, uint32_t mode)
{
    const char *rel;
    tfs_dev_t  *dev = dev_for_path(path, &rel);
    tfs_obj_t  *obj;
    int         fd;

    if (!dev) { set_err(TFS_ENODEV); return -1; }
    if (!open_accmode_valid(flags)) { set_err(TFS_EINVAL); return -1; }
    if ((flags & TFS_O_TRUNC) && open_accmode(flags) == TFS_O_RDONLY) {
        set_err(TFS_EACCES);
        return -1;
    }

    /* Lock device */
    if (dev->drv.lock) dev->drv.lock(dev->drv.ctx);

    obj = tfs_resolve_path(dev, rel, dev->root_dir, 1);

    if (!obj) {
        if (!(flags & TFS_O_CREAT)) {
            if (dev->drv.unlock) dev->drv.unlock(dev->drv.ctx);
            set_err(TFS_ENOENT);
            return -1;
        }
        /* Create the file */
        char name[TFS_MAX_NAME_LEN + 1];
        tfs_obj_t *parent = tfs_resolve_parent(dev, rel, dev->root_dir, name);
        if (!parent) {
            if (dev->drv.unlock) dev->drv.unlock(dev->drv.ctx);
            set_err(TFS_ENOENT);
            return -1;
        }
        obj = tfs_create_obj(dev, parent, name, mode | TFS_S_IFREG, TFS_OBJ_TYPE_FILE);
        if (!obj) {
            if (dev->drv.unlock) dev->drv.unlock(dev->drv.ctx);
            set_err(TFS_EIO);
            return -1;
        }
    } else {
        if ((flags & TFS_O_CREAT) && (flags & TFS_O_EXCL)) {
            if (dev->drv.unlock) dev->drv.unlock(dev->drv.ctx);
            set_err(TFS_EEXIST);
            return -1;
        }
        if ((flags & TFS_O_TRUNC) && obj->obj_type == TFS_OBJ_TYPE_FILE) {
            int rc = tfs_file_resize(dev, obj, 0);
            if (rc != TFS_OK) {
                if (dev->drv.unlock) dev->drv.unlock(dev->drv.ctx);
                set_err(rc);
                return -1;
            }
        }
    }

    /* Redirect hard link to the equivalent file object */
    if (obj && obj->obj_type == TFS_OBJ_TYPE_HARDLINK && obj->var.hardlink.equiv_obj)
        obj = obj->var.hardlink.equiv_obj;

    if (!obj || obj->obj_type != TFS_OBJ_TYPE_FILE) {
        if (dev->drv.unlock) dev->drv.unlock(dev->drv.ctx);
        set_err(obj && obj->obj_type == TFS_OBJ_TYPE_DIR ? TFS_EISDIR : TFS_EINVAL);
        return -1;
    }

    fd = alloc_fd();
    if (fd < 0) {
        if (dev->drv.unlock) dev->drv.unlock(dev->drv.ctx);
        set_err(TFS_EMFILE);
        return -1;
    }

    g_fd_table[fd].dev   = dev;
    g_fd_table[fd].obj   = obj;
    g_fd_table[fd].pos   = (flags & TFS_O_APPEND) ? obj->var.file.file_size : 0;
    g_fd_table[fd].flags = flags;

    if (dev->drv.unlock) dev->drv.unlock(dev->drv.ctx);
    return fd;
}

int tfs_close(int fd)
{
    tfs_fd_t *f = get_fd(fd);
    int       rc;
    if (!f) { set_err(TFS_EBADF); return -1; }

    if (f->dev->drv.lock) f->dev->drv.lock(f->dev->drv.ctx);
    rc = tfs_file_flush(f->dev, f->obj);
    if (f->dev->drv.unlock) f->dev->drv.unlock(f->dev->drv.ctx);

    memset(f, 0, sizeof(tfs_fd_t));
    if (rc != TFS_OK) { set_err(rc); return -1; }
    return 0;
}

int tfs_read(int fd, void *buf, int n_bytes)
{
    tfs_fd_t *f = get_fd(fd);
    int       rc;

    if (!f) { set_err(TFS_EBADF); return -1; }
    if (!buf || n_bytes <= 0) return 0;
    if (open_accmode(f->flags) == TFS_O_WRONLY) {
        set_err(TFS_EACCES);
        return -1;
    }

    if (f->dev->drv.lock) f->dev->drv.lock(f->dev->drv.ctx);
    rc = tfs_file_read(f->dev, f->obj, (uint8_t *)buf, f->pos, n_bytes);
    if (rc > 0) f->pos += rc;
    if (f->dev->drv.unlock) f->dev->drv.unlock(f->dev->drv.ctx);

    if (rc < 0) { set_err(rc); return -1; }
    return rc;
}

int tfs_write(int fd, const void *buf, int n_bytes)
{
    tfs_fd_t *f = get_fd(fd);
    int       rc;

    if (!f) { set_err(TFS_EBADF); return -1; }
    if (!buf || n_bytes <= 0) return 0;

    if (open_accmode(f->flags) == TFS_O_RDONLY) {
        set_err(TFS_EACCES);
        return -1;
    }

    if (f->dev->drv.lock) f->dev->drv.lock(f->dev->drv.ctx);

    if (!tfs_gc_enough_space(f->dev))
        tfs_gc(f->dev, 0);

    if (f->flags & TFS_O_APPEND)
        f->pos = f->obj->var.file.file_size;

    rc = tfs_file_write(f->dev, f->obj, (const uint8_t *)buf, f->pos, n_bytes);
    if (rc > 0) f->pos += rc;

    if (f->dev->drv.unlock) f->dev->drv.unlock(f->dev->drv.ctx);

    if (rc < 0) { set_err(rc); return -1; }
    return rc;
}

tfs_off_t tfs_lseek(int fd, tfs_off_t offset, int whence)
{
    tfs_fd_t  *f = get_fd(fd);
    tfs_off_t  new_pos;

    if (!f) { set_err(TFS_EBADF); return -1; }

    switch (whence) {
    case TFS_SEEK_SET: new_pos = offset;                             break;
    case TFS_SEEK_CUR: new_pos = f->pos + offset;                   break;
    case TFS_SEEK_END: new_pos = f->obj->var.file.file_size + offset; break;
    default:           set_err(TFS_EINVAL); return -1;
    }

    if (new_pos < 0) { set_err(TFS_EINVAL); return -1; }
    f->pos = new_pos;
    return new_pos;
}

int tfs_fsync(int fd)
{
    tfs_fd_t *f = get_fd(fd);
    int       rc;

    if (!f) { set_err(TFS_EBADF); return -1; }

    if (f->dev->drv.lock) f->dev->drv.lock(f->dev->drv.ctx);
    rc = tfs_file_flush(f->dev, f->obj);
    if (f->dev->drv.unlock) f->dev->drv.unlock(f->dev->drv.ctx);

    if (rc != TFS_OK) { set_err(rc); return -1; }
    return 0;
}

int tfs_dup(int fd)
{
    tfs_fd_t *f = get_fd(fd);
    int       new_fd;

    if (!f) { set_err(TFS_EBADF); return -1; }

    new_fd = alloc_fd();
    if (new_fd < 0) { set_err(TFS_EMFILE); return -1; }

    g_fd_table[new_fd] = *f;
    return new_fd;
}

/*-------------------------------------------------------------------
 *  ftruncate / truncate
 *-------------------------------------------------------------------*/

int tfs_ftruncate(int fd, tfs_off_t length)
{
    tfs_fd_t *f = get_fd(fd);
    int       rc;

    if (!f) { set_err(TFS_EBADF); return -1; }
    if (length < 0) { set_err(TFS_EINVAL); return -1; }
    if (open_accmode(f->flags) == TFS_O_RDONLY) {
        set_err(TFS_EACCES);
        return -1;
    }

    if (f->dev->drv.lock) f->dev->drv.lock(f->dev->drv.ctx);
    rc = tfs_file_resize(f->dev, f->obj, length);
    if (f->dev->drv.unlock) f->dev->drv.unlock(f->dev->drv.ctx);

    if (rc != TFS_OK) { set_err(rc); return -1; }
    return 0;
}

int tfs_truncate(const char *path, tfs_off_t length)
{
    const char *rel;
    tfs_dev_t  *dev = dev_for_path(path, &rel);
    tfs_obj_t  *obj;
    int         rc;

    if (!dev) { set_err(TFS_ENODEV); return -1; }
    if (length < 0) { set_err(TFS_EINVAL); return -1; }

    if (dev->drv.lock) dev->drv.lock(dev->drv.ctx);
    obj = tfs_resolve_path(dev, rel, dev->root_dir, 1);
    if (!obj || obj->obj_type != TFS_OBJ_TYPE_FILE) {
        if (dev->drv.unlock) dev->drv.unlock(dev->drv.ctx);
        set_err(TFS_ENOENT);
        return -1;
    }
    rc = tfs_file_resize(dev, obj, length);
    if (dev->drv.unlock) dev->drv.unlock(dev->drv.ctx);

    if (rc != TFS_OK) { set_err(rc); return -1; }
    return 0;
}

/*-------------------------------------------------------------------
 *  unlink / rename
 *-------------------------------------------------------------------*/

int tfs_unlink(const char *path)
{
    const char *rel;
    tfs_dev_t  *dev = dev_for_path(path, &rel);
    tfs_obj_t  *obj;
    int         rc;

    if (!dev) { set_err(TFS_ENODEV); return -1; }

    if (dev->drv.lock) dev->drv.lock(dev->drv.ctx);
    obj = tfs_resolve_path(dev, rel, dev->root_dir, 0);
    if (!obj) {
        if (dev->drv.unlock) dev->drv.unlock(dev->drv.ctx);
        set_err(TFS_ENOENT);
        return -1;
    }
    rc = tfs_unlink_obj(dev, obj);
    if (dev->drv.unlock) dev->drv.unlock(dev->drv.ctx);

    if (rc != TFS_OK) { set_err(rc); return -1; }
    return 0;
}

int tfs_rename(const char *old_path, const char *new_path)
{
    const char *old_rel, *new_rel;
    tfs_dev_t  *dev = dev_for_path(old_path, &old_rel);
    tfs_obj_t  *obj, *new_parent;
    char        new_name[TFS_MAX_NAME_LEN + 1];
    int         rc;

    if (!dev) { set_err(TFS_ENODEV); return -1; }

    if (dev->drv.lock) dev->drv.lock(dev->drv.ctx);

    /* Validate new_path is on same device */
    {
        tfs_dev_t *dev2 = dev_for_path(new_path, &new_rel);
        if (dev2 != dev) {
            if (dev->drv.unlock) dev->drv.unlock(dev->drv.ctx);
            set_err(TFS_EINVAL);
            return -1;
        }
    }

    obj = tfs_resolve_path(dev, old_rel, dev->root_dir, 0);
    if (!obj) {
        if (dev->drv.unlock) dev->drv.unlock(dev->drv.ctx);
        set_err(TFS_ENOENT);
        return -1;
    }

    new_parent = tfs_resolve_parent(dev, new_rel, dev->root_dir, new_name);
    if (!new_parent) {
        if (dev->drv.unlock) dev->drv.unlock(dev->drv.ctx);
        set_err(TFS_ENOENT);
        return -1;
    }

    rc = tfs_rename_obj(dev, obj, new_parent, new_name);
    if (dev->drv.unlock) dev->drv.unlock(dev->drv.ctx);

    if (rc != TFS_OK) { set_err(rc); return -1; }
    return 0;
}

/*-------------------------------------------------------------------
 *  stat / fstat / lstat
 *-------------------------------------------------------------------*/

static void fill_stat(const tfs_dev_t *dev, const tfs_obj_t *obj,
                      tfs_stat_t *st)
{
    uint32_t cpb = dev->data_bytes_per_chunk;
    (void)dev;
    memset(st, 0, sizeof(*st));
    st->st_ino    = (obj->obj_type == TFS_OBJ_TYPE_HARDLINK &&
                     obj->var.hardlink.equiv_obj)
                   ? obj->var.hardlink.equiv_obj->obj_id
                   : obj->obj_id;
    st->st_mode   = obj->mode;
    st->st_uid    = obj->uid;
    st->st_gid    = obj->gid;
    st->st_atime  = obj->atime;
    st->st_mtime  = obj->mtime;
    st->st_ctime  = obj->ctime;
    st->st_rdev   = obj->rdev;
    st->st_blksize = cpb;

    if (obj->obj_type == TFS_OBJ_TYPE_FILE) {
        st->st_size   = obj->var.file.file_size;
        st->st_blocks = (uint32_t)((st->st_size + 511) / 512);
    }
}

int tfs_stat(const char *path, tfs_stat_t *st)
{
    const char *rel;
    tfs_dev_t  *dev = dev_for_path(path, &rel);
    tfs_obj_t  *obj;

    if (!dev || !st) { set_err(TFS_ENODEV); return -1; }

    if (dev->drv.lock) dev->drv.lock(dev->drv.ctx);
    obj = tfs_resolve_path(dev, rel, dev->root_dir, 1);
    if (obj) fill_stat(dev, obj, st);
    if (dev->drv.unlock) dev->drv.unlock(dev->drv.ctx);

    if (!obj) { set_err(TFS_ENOENT); return -1; }
    return 0;
}

int tfs_fstat(int fd, tfs_stat_t *st)
{
    tfs_fd_t *f = get_fd(fd);
    if (!f || !st) { set_err(TFS_EBADF); return -1; }
    fill_stat(f->dev, f->obj, st);
    return 0;
}

int tfs_lstat(const char *path, tfs_stat_t *st)
{
    const char *rel;
    tfs_dev_t  *dev = dev_for_path(path, &rel);
    tfs_obj_t  *obj;

    if (!dev || !st) { set_err(TFS_ENODEV); return -1; }

    if (dev->drv.lock) dev->drv.lock(dev->drv.ctx);
    obj = tfs_resolve_path(dev, rel, dev->root_dir, 0);
    if (obj) fill_stat(dev, obj, st);
    if (dev->drv.unlock) dev->drv.unlock(dev->drv.ctx);

    if (!obj) { set_err(TFS_ENOENT); return -1; }
    return 0;
}

/*-------------------------------------------------------------------
 *  mkdir / rmdir
 *-------------------------------------------------------------------*/

int tfs_mkdir(const char *path, uint32_t mode)
{
    const char *rel;
    tfs_dev_t  *dev = dev_for_path(path, &rel);
    char        name[TFS_MAX_NAME_LEN + 1];
    tfs_obj_t  *parent, *obj;

    if (!dev) { set_err(TFS_ENODEV); return -1; }

    if (dev->drv.lock) dev->drv.lock(dev->drv.ctx);
    parent = tfs_resolve_parent(dev, rel, dev->root_dir, name);
    if (!parent) {
        if (dev->drv.unlock) dev->drv.unlock(dev->drv.ctx);
        set_err(TFS_ENOENT);
        return -1;
    }
    obj = tfs_create_obj(dev, parent, name, mode | TFS_S_IFDIR,
                         TFS_OBJ_TYPE_DIR);
    if (dev->drv.unlock) dev->drv.unlock(dev->drv.ctx);

    if (!obj) { set_err(TFS_EIO); return -1; }
    return 0;
}

int tfs_rmdir(const char *path)
{
    const char *rel;
    tfs_dev_t  *dev = dev_for_path(path, &rel);
    tfs_obj_t  *obj;
    int         rc;

    if (!dev) { set_err(TFS_ENODEV); return -1; }

    if (dev->drv.lock) dev->drv.lock(dev->drv.ctx);
    obj = tfs_resolve_path(dev, rel, dev->root_dir, 0);
    if (!obj || obj->obj_type != TFS_OBJ_TYPE_DIR) {
        if (dev->drv.unlock) dev->drv.unlock(dev->drv.ctx);
        set_err(TFS_ENOENT);
        return -1;
    }
    rc = tfs_unlink_obj(dev, obj);
    if (dev->drv.unlock) dev->drv.unlock(dev->drv.ctx);

    if (rc != TFS_OK) { set_err(rc); return -1; }
    return 0;
}

/*-------------------------------------------------------------------
 *  opendir / readdir / closedir
 *-------------------------------------------------------------------*/

int tfs_opendir(const char *path)
{
    const char *rel;
    tfs_dev_t  *dev = dev_for_path(path, &rel);
    tfs_obj_t  *obj;
    int         dfd;

    if (!dev) { set_err(TFS_ENODEV); return -1; }

    if (dev->drv.lock) dev->drv.lock(dev->drv.ctx);
    obj = tfs_resolve_path(dev, rel, dev->root_dir, 1);
    if (!obj || obj->obj_type != TFS_OBJ_TYPE_DIR) {
        if (dev->drv.unlock) dev->drv.unlock(dev->drv.ctx);
        set_err(TFS_ENOENT);
        return -1;
    }

    dfd = alloc_dfd();
    if (dfd < 0) {
        if (dev->drv.unlock) dev->drv.unlock(dev->drv.ctx);
        set_err(TFS_EMFILE);
        return -1;
    }

    g_dfd_table[dfd].dh = tfs_dir_open(dev, obj);
    if (!g_dfd_table[dfd].dh) {
        g_dfd_table[dfd].in_use = 0;
        if (dev->drv.unlock) dev->drv.unlock(dev->drv.ctx);
        set_err(TFS_ENOMEM);
        return -1;
    }

    if (dev->drv.unlock) dev->drv.unlock(dev->drv.ctx);
    return dfd;
}

int tfs_readdir(int dfd, tfs_dirent_t *de)
{
    tfs_dfd_t *d;
    int        rc;

    if (dfd < 0 || dfd >= TFS_CFG_MAX_HANDLES || !g_dfd_table[dfd].in_use) {
        set_err(TFS_EBADF);
        return -1;
    }

    d = &g_dfd_table[dfd];
    rc = tfs_dir_read(d->dh, de);
    return rc;   /* 0 = end, 1 = entry filled, -1 = error */
}

int tfs_closedir(int dfd)
{
    tfs_dfd_t *d;

    if (dfd < 0 || dfd >= TFS_CFG_MAX_HANDLES || !g_dfd_table[dfd].in_use) {
        set_err(TFS_EBADF);
        return -1;
    }

    d = &g_dfd_table[dfd];
    tfs_dir_close(d->dh);
    memset(d, 0, sizeof(*d));
    return 0;
}

/*-------------------------------------------------------------------
 *  symlink / readlink / link
 *-------------------------------------------------------------------*/

int tfs_symlink(const char *target, const char *link_path)
{
    const char *rel;
    tfs_dev_t  *dev = dev_for_path(link_path, &rel);
    char        name[TFS_MAX_NAME_LEN + 1];
    tfs_obj_t  *parent, *obj;

    if (!dev) { set_err(TFS_ENODEV); return -1; }

    if (dev->drv.lock) dev->drv.lock(dev->drv.ctx);
    parent = tfs_resolve_parent(dev, rel, dev->root_dir, name);
    if (!parent) {
        if (dev->drv.unlock) dev->drv.unlock(dev->drv.ctx);
        set_err(TFS_ENOENT);
        return -1;
    }
    obj = tfs_create_symlink(dev, parent, name, 0777 | TFS_S_IFLNK, target);
    if (dev->drv.unlock) dev->drv.unlock(dev->drv.ctx);

    if (!obj) { set_err(TFS_EIO); return -1; }
    return 0;
}

int tfs_readlink(const char *path, char *buf, int buf_size)
{
    const char *rel;
    tfs_dev_t  *dev = dev_for_path(path, &rel);
    tfs_obj_t  *obj;
    int         len;

    if (!dev || !buf) { set_err(TFS_ENODEV); return -1; }

    if (dev->drv.lock) dev->drv.lock(dev->drv.ctx);
    obj = tfs_resolve_path(dev, rel, dev->root_dir, 0);
    if (!obj || obj->obj_type != TFS_OBJ_TYPE_SYMLINK) {
        if (dev->drv.unlock) dev->drv.unlock(dev->drv.ctx);
        set_err(TFS_EINVAL);
        return -1;
    }

    len = obj->var.symlink.alias
          ? (int)strlen(obj->var.symlink.alias) : 0;
    if (len >= buf_size) len = buf_size - 1;
    if (obj->var.symlink.alias)
        memcpy(buf, obj->var.symlink.alias, (size_t)len);
    buf[len] = '\0';

    if (dev->drv.unlock) dev->drv.unlock(dev->drv.ctx);
    return len;
}

int tfs_link(const char *old_path, const char *new_path)
{
    const char *old_rel, *new_rel;
    tfs_dev_t  *dev = dev_for_path(old_path, &old_rel);
    char        name[TFS_MAX_NAME_LEN + 1];
    tfs_obj_t  *old_obj, *new_parent, *link;

    if (!dev) { set_err(TFS_ENODEV); return -1; }

    if (dev->drv.lock) dev->drv.lock(dev->drv.ctx);

    {
        tfs_dev_t *dev2 = dev_for_path(new_path, &new_rel);
        if (dev2 != dev) {
            if (dev->drv.unlock) dev->drv.unlock(dev->drv.ctx);
            set_err(TFS_EINVAL);
            return -1;
        }
    }

    old_obj = tfs_resolve_path(dev, old_rel, dev->root_dir, 1);
    if (!old_obj) {
        if (dev->drv.unlock) dev->drv.unlock(dev->drv.ctx);
        set_err(TFS_ENOENT);
        return -1;
    }

    new_parent = tfs_resolve_parent(dev, new_rel, dev->root_dir, name);
    if (!new_parent) {
        if (dev->drv.unlock) dev->drv.unlock(dev->drv.ctx);
        set_err(TFS_ENOENT);
        return -1;
    }

    link = tfs_create_hardlink(dev, new_parent, name, old_obj);
    if (dev->drv.unlock) dev->drv.unlock(dev->drv.ctx);

    if (!link) { set_err(TFS_EIO); return -1; }
    return 0;
}

/*-------------------------------------------------------------------
 *  freespace / totalspace
 *-------------------------------------------------------------------*/

tfs_off_t tfs_freespace(const char *dev_name)
{
    tfs_dev_t *dev = tfs_core_find_dev(dev_name);
    if (!dev) { set_err(TFS_ENODEV); return -1; }
    return tfs_core_free_space(dev);
}

tfs_off_t tfs_totalspace(const char *dev_name)
{
    tfs_dev_t *dev = tfs_core_find_dev(dev_name);
    if (!dev) { set_err(TFS_ENODEV); return -1; }
    return tfs_core_total_space(dev);
}

/*-------------------------------------------------------------------
 *  Background GC
 *-------------------------------------------------------------------*/

int tfs_bg_gc(const char *dev_name)
{
    tfs_dev_t *dev = tfs_core_find_dev(dev_name);
    int        rc;

    if (!dev) { set_err(TFS_ENODEV); return -1; }
    if (dev->drv.lock) dev->drv.lock(dev->drv.ctx);
    rc = tfs_gc(dev, 0);
    if (dev->drv.unlock) dev->drv.unlock(dev->drv.ctx);

    if (rc != TFS_OK) { set_err(rc); return -1; }
    return 0;
}
