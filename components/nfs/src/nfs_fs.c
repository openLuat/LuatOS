/*
 * nfs_fs.c — POSIX-style file descriptor layer for NFS
 *
 * Implements the public API declared in inc/nfs.h.
 *
 * Three-layer design:
 *   Handle (nfs_fd_t)   — open file descriptor, tracks position
 *   Object (nfs_obj_t)  — in-RAM inode
 *   NAND               — managed by nfs_core / nfs_block
 */

#include "../inc/nfs.h"
#include "../inc/nfs_port.h"
#include "nfs_dev.h"
#include "nfs_core.h"
#include "nfs_dir.h"
#include "nfs_inode.h"
#include "nfs_cache.h"
#include "nfs_checkpoint.h"
#include "../inc/nfs_config.h"

#include <string.h>

/*===================================================================
 *  File descriptor table
 *===================================================================*/

typedef struct {
    int        in_use;
    nfs_dev_t *dev;
    nfs_obj_t *obj;
    nfs_off_t  pos;
    int        flags;
} nfs_fd_t;

static nfs_fd_t g_fd_table[NFS_CFG_MAX_HANDLES];

/* Directory handle table */
typedef struct {
    int               in_use;
    nfs_dir_handle_t *dh;
} nfs_dfd_t;

static nfs_dfd_t g_dfd_table[NFS_CFG_MAX_HANDLES];

/* Per-thread/global error */
static int g_last_error = NFS_OK;

static nfs_dev_t *g_devices[NFS_CFG_MAX_DEVICES];
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
    for (i = 0; i < NFS_CFG_MAX_HANDLES; i++) {
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
    for (i = 0; i < NFS_CFG_MAX_HANDLES; i++) {
        if (!g_dfd_table[i].in_use) {
            g_dfd_table[i].in_use = 1;
            return i;
        }
    }
    return -1;
}

static nfs_fd_t *get_fd(int fd)
{
    if (fd < 0 || fd >= NFS_CFG_MAX_HANDLES || !g_fd_table[fd].in_use)
        return NFS_NULL;
    return &g_fd_table[fd];
}

/* Find the device for a path (first '/' → default device).
 * Paths have the form "/<devname>/rest/of/path".
 * Falls back to the first registered device for bare "/" paths. */
static nfs_dev_t *dev_for_path(const char *path, const char **path_out)
{
    nfs_dev_t *dev;

    *path_out = path;

    if (path && path[0] == '/') {
        char vol[32];
        const char *p = path + 1;
        int i = 0;
        while (*p && *p != '/' && i < 31)
            vol[i++] = *p++;
        vol[i] = '\0';
        dev = nfs_core_find_dev(vol);
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

    return NFS_NULL;
}

/*===================================================================
 *  Public API implementation
 *===================================================================*/

int nfs_init(void)
{
    memset(g_fd_table,  0, sizeof(g_fd_table));
    memset(g_dfd_table, 0, sizeof(g_dfd_table));
    g_last_error = NFS_OK;
    return NFS_OK;
}

int nfs_get_error(void)
{
    return g_last_error;
}

/*-------------------------------------------------------------------
 *  Device management
 *-------------------------------------------------------------------*/

int nfs_add_device(const char *name, const nfs_drv_t *drv,
                   const nfs_geo_t *geo)
{
    nfs_dev_t *dev;
    nfs_param_t param;

    if (g_n_devices >= NFS_CFG_MAX_DEVICES) {
        set_err(NFS_ENOMEM);
        return NFS_ENOMEM;
    }

    dev = (nfs_dev_t *)drv->malloc(drv->ctx, sizeof(nfs_dev_t));
    if (!dev) { set_err(NFS_ENOMEM); return NFS_ENOMEM; }

    memset(dev, 0, sizeof(nfs_dev_t));
    memset(&param, 0, sizeof(param));
    param.name = name;
    param.geo  = *geo;

    dev->param = param;
    dev->drv   = *drv;

    nfs_core_add_device(dev);
    g_devices[g_n_devices++] = dev;
    return NFS_OK;
}

int nfs_remove_device(const char *name)
{
    int i;
    for (i = 0; i < g_n_devices; i++) {
        if (g_devices[i] && strcmp(g_devices[i]->param.name, name) == 0) {
            nfs_core_unmount(g_devices[i]);
            nfs_core_remove_device(g_devices[i]);
            g_devices[i]->drv.free(g_devices[i]->drv.ctx, g_devices[i]);
            g_devices[i] = NFS_NULL;
            g_n_devices--;
            return NFS_OK;
        }
    }
    return NFS_ENODEV;
}

/*-------------------------------------------------------------------
 *  Mount / unmount / format / sync
 *-------------------------------------------------------------------*/

int nfs_mount(const char *dev_name)
{
    nfs_dev_t *dev = nfs_core_find_dev(dev_name);
    if (!dev) { set_err(NFS_ENODEV); return NFS_ENODEV; }

    int rc = nfs_core_mount(dev);
    if (rc != NFS_OK) set_err(rc);
    return rc;
}

int nfs_unmount(const char *dev_name)
{
    nfs_dev_t *dev = nfs_core_find_dev(dev_name);
    if (!dev) { set_err(NFS_ENODEV); return NFS_ENODEV; }

    int rc = nfs_core_unmount(dev);
    if (rc != NFS_OK) set_err(rc);
    return rc;
}

int nfs_format(const char *dev_name)
{
    nfs_dev_t *dev = nfs_core_find_dev(dev_name);
    if (!dev) { set_err(NFS_ENODEV); return NFS_ENODEV; }

    int rc = nfs_core_format(dev);
    if (rc != NFS_OK) set_err(rc);
    return rc;
}

int nfs_sync(const char *dev_name)
{
    nfs_dev_t *dev = nfs_core_find_dev(dev_name);
    if (!dev) { set_err(NFS_ENODEV); return NFS_ENODEV; }

    int rc = nfs_core_sync(dev);
    if (rc != NFS_OK) set_err(rc);
    return rc;
}

/*-------------------------------------------------------------------
 *  open / close / read / write / lseek / fsync
 *-------------------------------------------------------------------*/

int nfs_open(const char *path, int flags, nfs_u32 mode)
{
    const char *rel;
    nfs_dev_t  *dev = dev_for_path(path, &rel);
    nfs_obj_t  *obj;
    int         fd;

    if (!dev) { set_err(NFS_ENODEV); return -1; }

    /* Lock device */
    if (dev->drv.lock) dev->drv.lock(dev->drv.ctx);

    obj = nfs_resolve_path(dev, rel, dev->root_dir, 1);

    if (!obj) {
        if (!(flags & NFS_O_CREAT)) {
            if (dev->drv.unlock) dev->drv.unlock(dev->drv.ctx);
            set_err(NFS_ENOENT);
            return -1;
        }
        /* Create the file */
        char name[NFS_MAX_NAME_LEN + 1];
        nfs_obj_t *parent = nfs_resolve_parent(dev, rel, dev->root_dir, name);
        if (!parent) {
            if (dev->drv.unlock) dev->drv.unlock(dev->drv.ctx);
            set_err(NFS_ENOENT);
            return -1;
        }
        obj = nfs_create_obj(dev, parent, name, mode, NFS_OBJ_TYPE_FILE);
        if (!obj) {
            if (dev->drv.unlock) dev->drv.unlock(dev->drv.ctx);
            set_err(NFS_EIO);
            return -1;
        }
    } else {
        if ((flags & NFS_O_CREAT) && (flags & NFS_O_EXCL)) {
            if (dev->drv.unlock) dev->drv.unlock(dev->drv.ctx);
            set_err(NFS_EEXIST);
            return -1;
        }
        if ((flags & NFS_O_TRUNC) && obj->obj_type == NFS_OBJ_TYPE_FILE)
            nfs_file_resize(dev, obj, 0);
    }

    fd = alloc_fd();
    if (fd < 0) {
        if (dev->drv.unlock) dev->drv.unlock(dev->drv.ctx);
        set_err(NFS_EMFILE);
        return -1;
    }

    g_fd_table[fd].dev   = dev;
    g_fd_table[fd].obj   = obj;
    g_fd_table[fd].pos   = (flags & NFS_O_APPEND) ? obj->var.file.file_size : 0;
    g_fd_table[fd].flags = flags;

    if (dev->drv.unlock) dev->drv.unlock(dev->drv.ctx);
    return fd;
}

int nfs_close(int fd)
{
    nfs_fd_t *f = get_fd(fd);
    if (!f) { set_err(NFS_EBADF); return -1; }

    if (f->dev->drv.lock) f->dev->drv.lock(f->dev->drv.ctx);
    nfs_cache_flush_obj(f->dev, f->obj);
    if (f->dev->drv.unlock) f->dev->drv.unlock(f->dev->drv.ctx);

    memset(f, 0, sizeof(nfs_fd_t));
    return 0;
}

int nfs_read(int fd, void *buf, int n_bytes)
{
    nfs_fd_t *f = get_fd(fd);
    int       rc;

    if (!f) { set_err(NFS_EBADF); return -1; }
    if (!buf || n_bytes <= 0) return 0;

    if (f->dev->drv.lock) f->dev->drv.lock(f->dev->drv.ctx);
    rc = nfs_file_read(f->dev, f->obj, (nfs_u8 *)buf, f->pos, n_bytes);
    if (rc > 0) f->pos += rc;
    if (f->dev->drv.unlock) f->dev->drv.unlock(f->dev->drv.ctx);

    if (rc < 0) { set_err(rc); return -1; }
    return rc;
}

int nfs_write(int fd, const void *buf, int n_bytes)
{
    nfs_fd_t *f = get_fd(fd);
    int       rc;

    if (!f) { set_err(NFS_EBADF); return -1; }
    if (!buf || n_bytes <= 0) return 0;

    if (f->flags & NFS_O_RDONLY) { set_err(NFS_EACCES); return -1; }

    if (f->dev->drv.lock) f->dev->drv.lock(f->dev->drv.ctx);

    if (!nfs_gc_enough_space(f->dev))
        nfs_gc(f->dev, 0);

    rc = nfs_file_write(f->dev, f->obj, (const nfs_u8 *)buf, f->pos, n_bytes);
    if (rc > 0) f->pos += rc;

    if (f->dev->drv.unlock) f->dev->drv.unlock(f->dev->drv.ctx);

    if (rc < 0) { set_err(rc); return -1; }
    return rc;
}

nfs_off_t nfs_lseek(int fd, nfs_off_t offset, int whence)
{
    nfs_fd_t  *f = get_fd(fd);
    nfs_off_t  new_pos;

    if (!f) { set_err(NFS_EBADF); return -1; }

    switch (whence) {
    case NFS_SEEK_SET: new_pos = offset;                             break;
    case NFS_SEEK_CUR: new_pos = f->pos + offset;                   break;
    case NFS_SEEK_END: new_pos = f->obj->var.file.file_size + offset; break;
    default:           set_err(NFS_EINVAL); return -1;
    }

    if (new_pos < 0) { set_err(NFS_EINVAL); return -1; }
    f->pos = new_pos;
    return new_pos;
}

int nfs_fsync(int fd)
{
    nfs_fd_t *f = get_fd(fd);
    int       rc;

    if (!f) { set_err(NFS_EBADF); return -1; }

    if (f->dev->drv.lock) f->dev->drv.lock(f->dev->drv.ctx);
    rc = nfs_file_flush(f->dev, f->obj);
    if (f->dev->drv.unlock) f->dev->drv.unlock(f->dev->drv.ctx);

    if (rc != NFS_OK) { set_err(rc); return -1; }
    return 0;
}

int nfs_dup(int fd)
{
    nfs_fd_t *f = get_fd(fd);
    int       new_fd;

    if (!f) { set_err(NFS_EBADF); return -1; }

    new_fd = alloc_fd();
    if (new_fd < 0) { set_err(NFS_EMFILE); return -1; }

    g_fd_table[new_fd] = *f;
    return new_fd;
}

/*-------------------------------------------------------------------
 *  ftruncate / truncate
 *-------------------------------------------------------------------*/

int nfs_ftruncate(int fd, nfs_off_t length)
{
    nfs_fd_t *f = get_fd(fd);
    int       rc;

    if (!f) { set_err(NFS_EBADF); return -1; }

    if (f->dev->drv.lock) f->dev->drv.lock(f->dev->drv.ctx);
    rc = nfs_file_resize(f->dev, f->obj, length);
    if (f->dev->drv.unlock) f->dev->drv.unlock(f->dev->drv.ctx);

    if (rc != NFS_OK) { set_err(rc); return -1; }
    return 0;
}

int nfs_truncate(const char *path, nfs_off_t length)
{
    const char *rel;
    nfs_dev_t  *dev = dev_for_path(path, &rel);
    nfs_obj_t  *obj;
    int         rc;

    if (!dev) { set_err(NFS_ENODEV); return -1; }

    if (dev->drv.lock) dev->drv.lock(dev->drv.ctx);
    obj = nfs_resolve_path(dev, rel, dev->root_dir, 1);
    if (!obj || obj->obj_type != NFS_OBJ_TYPE_FILE) {
        if (dev->drv.unlock) dev->drv.unlock(dev->drv.ctx);
        set_err(NFS_ENOENT);
        return -1;
    }
    rc = nfs_file_resize(dev, obj, length);
    if (dev->drv.unlock) dev->drv.unlock(dev->drv.ctx);

    if (rc != NFS_OK) { set_err(rc); return -1; }
    return 0;
}

/*-------------------------------------------------------------------
 *  unlink / rename
 *-------------------------------------------------------------------*/

int nfs_unlink(const char *path)
{
    const char *rel;
    nfs_dev_t  *dev = dev_for_path(path, &rel);
    nfs_obj_t  *obj;
    int         rc;

    if (!dev) { set_err(NFS_ENODEV); return -1; }

    if (dev->drv.lock) dev->drv.lock(dev->drv.ctx);
    obj = nfs_resolve_path(dev, rel, dev->root_dir, 0);
    if (!obj) {
        if (dev->drv.unlock) dev->drv.unlock(dev->drv.ctx);
        set_err(NFS_ENOENT);
        return -1;
    }
    rc = nfs_unlink_obj(dev, obj);
    if (dev->drv.unlock) dev->drv.unlock(dev->drv.ctx);

    if (rc != NFS_OK) { set_err(rc); return -1; }
    return 0;
}

int nfs_rename(const char *old_path, const char *new_path)
{
    const char *old_rel, *new_rel;
    nfs_dev_t  *dev = dev_for_path(old_path, &old_rel);
    nfs_obj_t  *obj, *new_parent;
    char        new_name[NFS_MAX_NAME_LEN + 1];
    int         rc;

    if (!dev) { set_err(NFS_ENODEV); return -1; }

    if (dev->drv.lock) dev->drv.lock(dev->drv.ctx);

    /* Validate new_path is on same device */
    {
        nfs_dev_t *dev2 = dev_for_path(new_path, &new_rel);
        if (dev2 != dev) {
            if (dev->drv.unlock) dev->drv.unlock(dev->drv.ctx);
            set_err(NFS_EINVAL);
            return -1;
        }
    }

    obj = nfs_resolve_path(dev, old_rel, dev->root_dir, 0);
    if (!obj) {
        if (dev->drv.unlock) dev->drv.unlock(dev->drv.ctx);
        set_err(NFS_ENOENT);
        return -1;
    }

    new_parent = nfs_resolve_parent(dev, new_rel, dev->root_dir, new_name);
    if (!new_parent) {
        if (dev->drv.unlock) dev->drv.unlock(dev->drv.ctx);
        set_err(NFS_ENOENT);
        return -1;
    }

    rc = nfs_rename_obj(dev, obj, new_parent, new_name);
    if (dev->drv.unlock) dev->drv.unlock(dev->drv.ctx);

    if (rc != NFS_OK) { set_err(rc); return -1; }
    return 0;
}

/*-------------------------------------------------------------------
 *  stat / fstat / lstat
 *-------------------------------------------------------------------*/

static void fill_stat(const nfs_dev_t *dev, const nfs_obj_t *obj,
                      nfs_stat_t *st)
{
    nfs_u32 cpb = dev->data_bytes_per_chunk;
    (void)dev;
    memset(st, 0, sizeof(*st));
    st->st_ino    = obj->obj_id;
    st->st_mode   = obj->mode;
    st->st_uid    = obj->uid;
    st->st_gid    = obj->gid;
    st->st_atime  = obj->atime;
    st->st_mtime  = obj->mtime;
    st->st_ctime  = obj->ctime;
    st->st_rdev   = obj->rdev;
    st->st_blksize = cpb;

    if (obj->obj_type == NFS_OBJ_TYPE_FILE) {
        st->st_size   = obj->var.file.file_size;
        st->st_blocks = (nfs_u32)((st->st_size + 511) / 512);
    }
}

int nfs_stat(const char *path, nfs_stat_t *st)
{
    const char *rel;
    nfs_dev_t  *dev = dev_for_path(path, &rel);
    nfs_obj_t  *obj;

    if (!dev || !st) { set_err(NFS_ENODEV); return -1; }

    if (dev->drv.lock) dev->drv.lock(dev->drv.ctx);
    obj = nfs_resolve_path(dev, rel, dev->root_dir, 1);
    if (obj) fill_stat(dev, obj, st);
    if (dev->drv.unlock) dev->drv.unlock(dev->drv.ctx);

    if (!obj) { set_err(NFS_ENOENT); return -1; }
    return 0;
}

int nfs_fstat(int fd, nfs_stat_t *st)
{
    nfs_fd_t *f = get_fd(fd);
    if (!f || !st) { set_err(NFS_EBADF); return -1; }
    fill_stat(f->dev, f->obj, st);
    return 0;
}

int nfs_lstat(const char *path, nfs_stat_t *st)
{
    const char *rel;
    nfs_dev_t  *dev = dev_for_path(path, &rel);
    nfs_obj_t  *obj;

    if (!dev || !st) { set_err(NFS_ENODEV); return -1; }

    if (dev->drv.lock) dev->drv.lock(dev->drv.ctx);
    obj = nfs_resolve_path(dev, rel, dev->root_dir, 0);
    if (obj) fill_stat(dev, obj, st);
    if (dev->drv.unlock) dev->drv.unlock(dev->drv.ctx);

    if (!obj) { set_err(NFS_ENOENT); return -1; }
    return 0;
}

/*-------------------------------------------------------------------
 *  mkdir / rmdir
 *-------------------------------------------------------------------*/

int nfs_mkdir(const char *path, nfs_u32 mode)
{
    const char *rel;
    nfs_dev_t  *dev = dev_for_path(path, &rel);
    char        name[NFS_MAX_NAME_LEN + 1];
    nfs_obj_t  *parent, *obj;

    if (!dev) { set_err(NFS_ENODEV); return -1; }

    if (dev->drv.lock) dev->drv.lock(dev->drv.ctx);
    parent = nfs_resolve_parent(dev, rel, dev->root_dir, name);
    if (!parent) {
        if (dev->drv.unlock) dev->drv.unlock(dev->drv.ctx);
        set_err(NFS_ENOENT);
        return -1;
    }
    obj = nfs_create_obj(dev, parent, name, mode | NFS_S_IFDIR,
                         NFS_OBJ_TYPE_DIR);
    if (dev->drv.unlock) dev->drv.unlock(dev->drv.ctx);

    if (!obj) { set_err(NFS_EIO); return -1; }
    return 0;
}

int nfs_rmdir(const char *path)
{
    const char *rel;
    nfs_dev_t  *dev = dev_for_path(path, &rel);
    nfs_obj_t  *obj;
    int         rc;

    if (!dev) { set_err(NFS_ENODEV); return -1; }

    if (dev->drv.lock) dev->drv.lock(dev->drv.ctx);
    obj = nfs_resolve_path(dev, rel, dev->root_dir, 0);
    if (!obj || obj->obj_type != NFS_OBJ_TYPE_DIR) {
        if (dev->drv.unlock) dev->drv.unlock(dev->drv.ctx);
        set_err(NFS_ENOENT);
        return -1;
    }
    rc = nfs_unlink_obj(dev, obj);
    if (dev->drv.unlock) dev->drv.unlock(dev->drv.ctx);

    if (rc != NFS_OK) { set_err(rc); return -1; }
    return 0;
}

/*-------------------------------------------------------------------
 *  opendir / readdir / closedir
 *-------------------------------------------------------------------*/

int nfs_opendir(const char *path)
{
    const char *rel;
    nfs_dev_t  *dev = dev_for_path(path, &rel);
    nfs_obj_t  *obj;
    int         dfd;

    if (!dev) { set_err(NFS_ENODEV); return -1; }

    if (dev->drv.lock) dev->drv.lock(dev->drv.ctx);
    obj = nfs_resolve_path(dev, rel, dev->root_dir, 1);
    if (!obj || obj->obj_type != NFS_OBJ_TYPE_DIR) {
        if (dev->drv.unlock) dev->drv.unlock(dev->drv.ctx);
        set_err(NFS_ENOENT);
        return -1;
    }

    dfd = alloc_dfd();
    if (dfd < 0) {
        if (dev->drv.unlock) dev->drv.unlock(dev->drv.ctx);
        set_err(NFS_EMFILE);
        return -1;
    }

    g_dfd_table[dfd].dh = nfs_dir_open(dev, obj);
    if (!g_dfd_table[dfd].dh) {
        g_dfd_table[dfd].in_use = 0;
        if (dev->drv.unlock) dev->drv.unlock(dev->drv.ctx);
        set_err(NFS_ENOMEM);
        return -1;
    }

    if (dev->drv.unlock) dev->drv.unlock(dev->drv.ctx);
    return dfd;
}

int nfs_readdir(int dfd, nfs_dirent_t *de)
{
    nfs_dfd_t *d;
    int        rc;

    if (dfd < 0 || dfd >= NFS_CFG_MAX_HANDLES || !g_dfd_table[dfd].in_use) {
        set_err(NFS_EBADF);
        return -1;
    }

    d = &g_dfd_table[dfd];
    rc = nfs_dir_read(d->dh, de);
    return rc;   /* 0 = end, 1 = entry filled, -1 = error */
}

int nfs_closedir(int dfd)
{
    nfs_dfd_t *d;

    if (dfd < 0 || dfd >= NFS_CFG_MAX_HANDLES || !g_dfd_table[dfd].in_use) {
        set_err(NFS_EBADF);
        return -1;
    }

    d = &g_dfd_table[dfd];
    nfs_dir_close(d->dh);
    memset(d, 0, sizeof(*d));
    return 0;
}

/*-------------------------------------------------------------------
 *  symlink / readlink / link
 *-------------------------------------------------------------------*/

int nfs_symlink(const char *target, const char *link_path)
{
    const char *rel;
    nfs_dev_t  *dev = dev_for_path(link_path, &rel);
    char        name[NFS_MAX_NAME_LEN + 1];
    nfs_obj_t  *parent, *obj;

    if (!dev) { set_err(NFS_ENODEV); return -1; }

    if (dev->drv.lock) dev->drv.lock(dev->drv.ctx);
    parent = nfs_resolve_parent(dev, rel, dev->root_dir, name);
    if (!parent) {
        if (dev->drv.unlock) dev->drv.unlock(dev->drv.ctx);
        set_err(NFS_ENOENT);
        return -1;
    }
    obj = nfs_create_symlink(dev, parent, name, 0777, target);
    if (dev->drv.unlock) dev->drv.unlock(dev->drv.ctx);

    if (!obj) { set_err(NFS_EIO); return -1; }
    return 0;
}

int nfs_readlink(const char *path, char *buf, int buf_size)
{
    const char *rel;
    nfs_dev_t  *dev = dev_for_path(path, &rel);
    nfs_obj_t  *obj;
    int         len;

    if (!dev || !buf) { set_err(NFS_ENODEV); return -1; }

    if (dev->drv.lock) dev->drv.lock(dev->drv.ctx);
    obj = nfs_resolve_path(dev, rel, dev->root_dir, 0);
    if (!obj || obj->obj_type != NFS_OBJ_TYPE_SYMLINK) {
        if (dev->drv.unlock) dev->drv.unlock(dev->drv.ctx);
        set_err(NFS_EINVAL);
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

int nfs_link(const char *old_path, const char *new_path)
{
    const char *old_rel, *new_rel;
    nfs_dev_t  *dev = dev_for_path(old_path, &old_rel);
    char        name[NFS_MAX_NAME_LEN + 1];
    nfs_obj_t  *old_obj, *new_parent, *link;

    if (!dev) { set_err(NFS_ENODEV); return -1; }

    if (dev->drv.lock) dev->drv.lock(dev->drv.ctx);

    {
        nfs_dev_t *dev2 = dev_for_path(new_path, &new_rel);
        if (dev2 != dev) {
            if (dev->drv.unlock) dev->drv.unlock(dev->drv.ctx);
            set_err(NFS_EINVAL);
            return -1;
        }
    }

    old_obj = nfs_resolve_path(dev, old_rel, dev->root_dir, 1);
    if (!old_obj) {
        if (dev->drv.unlock) dev->drv.unlock(dev->drv.ctx);
        set_err(NFS_ENOENT);
        return -1;
    }

    new_parent = nfs_resolve_parent(dev, new_rel, dev->root_dir, name);
    if (!new_parent) {
        if (dev->drv.unlock) dev->drv.unlock(dev->drv.ctx);
        set_err(NFS_ENOENT);
        return -1;
    }

    link = nfs_create_hardlink(dev, new_parent, name, old_obj);
    if (dev->drv.unlock) dev->drv.unlock(dev->drv.ctx);

    if (!link) { set_err(NFS_EIO); return -1; }
    return 0;
}

/*-------------------------------------------------------------------
 *  freespace / totalspace
 *-------------------------------------------------------------------*/

nfs_off_t nfs_freespace(const char *dev_name)
{
    nfs_dev_t *dev = nfs_core_find_dev(dev_name);
    if (!dev) { set_err(NFS_ENODEV); return -1; }
    return nfs_core_free_space(dev);
}

nfs_off_t nfs_totalspace(const char *dev_name)
{
    nfs_dev_t *dev = nfs_core_find_dev(dev_name);
    if (!dev) { set_err(NFS_ENODEV); return -1; }
    return nfs_core_total_space(dev);
}

/*-------------------------------------------------------------------
 *  Background GC
 *-------------------------------------------------------------------*/

int nfs_bg_gc(const char *dev_name)
{
    nfs_dev_t *dev = nfs_core_find_dev(dev_name);
    int        rc;

    if (!dev) { set_err(NFS_ENODEV); return -1; }
    if (dev->drv.lock) dev->drv.lock(dev->drv.ctx);
    rc = nfs_gc(dev, 0);
    if (dev->drv.unlock) dev->drv.unlock(dev->drv.ctx);

    if (rc != NFS_OK) { set_err(rc); return -1; }
    return 0;
}
