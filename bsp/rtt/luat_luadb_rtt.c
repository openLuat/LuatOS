
#include <rtdevice.h>
#include <rtthread.h>
#include <luat_base.h>

#include <dfs_file.h>
#include <dfs_fs.h>

#include <stdio.h>
#include <string.h>

#include "luat_luadb.h"

#define LUAT_LOG_TAG "luadb.dfs"
#include "luat_log.h"

// 注意: rtt的dfs文件路径是/开头的,而luadb的路径是不带/的,需要转一下

static int _dfs_luadb_open     (struct dfs_fd *fd) {
    int _fd = luat_luadb_open((luadb_fs_t*)fd->fs->data, fd->path + 1, fd->flags, 0);
    if (_fd != 0) {
        fd->data = (void*) _fd;
    }
    return _fd;
}
static int _dfs_luadb_close    (struct dfs_fd *fd) {
    return luat_luadb_close((luadb_fs_t*)fd->fs->data, (int)fd->data);
}
static int _dfs_luadb_ioctl    (struct dfs_fd *fd, int cmd, void *args) {
    return -EIO;
}
static int _dfs_luadb_read     (struct dfs_fd *fd, void *buf, size_t count) {
    return luat_luadb_read((luadb_fs_t*)fd->fs->data, (int)fd->data, buf, count);
}
//static int _dfs_luadb_write    (struct dfs_fd *fd, const void *buf, size_t count);
//static int _dfs_luadb_flush    (struct dfs_fd *fd);
static int _dfs_luadb_lseek    (struct dfs_fd *fd, off_t offset) {
    return luat_luadb_lseek((luadb_fs_t*)fd->fs->data, (int)fd->data, offset, SEEK_SET);
}
//static int _dfs_luadb_getdents (struct dfs_fd *fd, struct dirent *dirp, uint32_t count);

static const struct dfs_file_ops _dfs_luadb_fops = {
    _dfs_luadb_open,
    _dfs_luadb_close,
    _dfs_luadb_ioctl,
    _dfs_luadb_read,
    NULL,
    NULL,
    _dfs_luadb_lseek,
    NULL,
    //    RT_NULL, /* poll interface */
};

static int _dfs_luadb_mount    (struct dfs_filesystem *fs, unsigned long rwflag, const void *data) {
    if (data == NULL) {
        LLOGE("luadb mount data == NULL");
        return -EIO;
    }
    const char* ptr = (const char*) data;
    luadb_fs_t* _fs = luat_luadb_mount(ptr);
    if (_fs == NULL) {
        LLOGE("luat_luadb_mount return NULL");
        return -EIO;
    }
    fs->data = _fs;
    return 0;
}
static int _dfs_luadb_unmount  (struct dfs_filesystem *fs) {
    if (fs->data == NULL) {
        return 0;
    }
    luat_luadb_umount((luadb_fs_t *)fs->data);
    return 0;
}

/* make a file system */
// static int _dfs_luadb_mkfs     (rt_device_t devid) {
//     return -EIO;
// }
static int _dfs_luadb_statfs   (struct dfs_filesystem *fs, struct statfs *buf) {
    buf->f_bsize = 1024;
    buf->f_blocks = 64;
    buf->f_bfree = 0;
    return 0;
}

//static int _dfs_luadb_unlink   (struct dfs_filesystem *fs, const char *pathname);
static int _dfs_luadb_stat     (struct dfs_filesystem *fs, const char *filename, struct stat *buf) {
    luadb_file_t* f = luat_luadb_stat((luadb_fs_t *)fs->data, filename + 1);
    if (f == NULL) {
        return -EIO;
    }
    buf->st_size = f->size;
    return 0;
}
//static int _dfs_luadb_rename   (struct dfs_filesystem *fs, const char *oldpath, const char *newpath);

static const struct dfs_filesystem_ops _dfs_luadb_ops = {
    "luadb",
    DFS_FS_FLAG_DEFAULT,
    &_dfs_luadb_fops,

    _dfs_luadb_mount,
    _dfs_luadb_unmount,

    NULL,
    _dfs_luadb_statfs,
    NULL,
    _dfs_luadb_stat,
    NULL,
};

int dfs_luadb_init(void)
{
    /* register luadb file system */
    return dfs_register(&_dfs_luadb_ops);
}
INIT_COMPONENT_EXPORT(dfs_luadb_init);
