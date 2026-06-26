/*
 * nfs.h — Public POSIX-style API for TFS (Tiny File System)
 *
 * Include this header and tfs_port.h in your application.
 * All other headers are internal.
 *
 * Error handling:
 *   - Functions return 0 (TFS_OK) on success, -1 (TFS_FAIL) on error.
 *   - File I/O functions return bytes transferred (≥0) on success, -1 on error.
 *   - Call tfs_get_error() for the error code (TFS_E* constants).
 *
 * Directory iteration: integer handle ("dfd"), similar to POSIX fd.
 *   dfd = tfs_opendir(path);  tfs_readdir(dfd, &de);  tfs_closedir(dfd);
 */

#ifndef TFS_H
#define TFS_H

#include "tfs_types.h"
#include "tfs_config.h"
#include "tfs_port.h"

#ifdef __cplusplus
extern "C" {
#endif

/*===================================================================
 *  Stat and directory-entry structures defined in tfs_types.h
 *  (tfs_stat_t, tfs_dirent_t — reproduced here for documentation)
 *===================================================================*/
/* tfs_stat_t fields: st_ino, st_mode, st_uid, st_gid, st_atime,    */
/*                    st_mtime, st_ctime, st_rdev, st_size,          */
/*                    st_blksize, st_blocks                          */
/* tfs_dirent_t fields: d_ino, d_type (TFS_DT_*), d_name            */

/*===================================================================
 *  Global init
 *===================================================================*/

/** tfs_init — must be called once before any other tfs_* function */
int tfs_init(void);

/*===================================================================
 *  Device management (see also tfs_port.h for tfs_add_device)
 *===================================================================*/

/** tfs_remove_device — deregister; device must be unmounted first */
int  tfs_remove_device(const char *name);

/*===================================================================
 *  Mount / unmount / format / sync
 *===================================================================*/

int tfs_mount  (const char *dev_name);
int tfs_unmount(const char *dev_name);
int tfs_format (const char *dev_name);
int tfs_sync   (const char *dev_name);

/*===================================================================
 *  File operations
 *===================================================================*/

int       tfs_open     (const char *path, int flags, uint32_t mode);
int       tfs_close    (int fd);
int       tfs_read     (int fd, void *buf, int nbytes);
int       tfs_write    (int fd, const void *buf, int nbytes);
tfs_off_t tfs_lseek    (int fd, tfs_off_t offset, int whence);
int       tfs_fsync    (int fd);

int       tfs_ftruncate(int fd, tfs_off_t new_size);
int       tfs_truncate (const char *path, tfs_off_t new_size);

int       tfs_unlink   (const char *path);
int       tfs_rename   (const char *old_path, const char *new_path);

/*===================================================================
 *  Stat
 *===================================================================*/

int tfs_stat (const char *path, tfs_stat_t *st);
int tfs_lstat(const char *path, tfs_stat_t *st);
int tfs_fstat(int fd,           tfs_stat_t *st);

/*===================================================================
 *  Directories
 *===================================================================*/

int tfs_mkdir  (const char *path, uint32_t mode);
int tfs_rmdir  (const char *path);

/** tfs_opendir — return dir-fd (dfd) ≥ 0 on success, -1 on error */
int tfs_opendir (const char *path);
/** tfs_readdir  — fill *de; return 1 = entry, 0 = end, -1 = error */
int tfs_readdir (int dfd, tfs_dirent_t *de);
int tfs_closedir(int dfd);

/*===================================================================
 *  Symlinks and hard links
 *===================================================================*/

int tfs_symlink (const char *target,  const char *linkpath);
int tfs_readlink(const char *path, char *buf, int bufsiz);
int tfs_link    (const char *oldpath, const char *newpath);

/*===================================================================
 *  Device information
 *===================================================================*/

tfs_off_t tfs_freespace (const char *dev_name);
tfs_off_t tfs_totalspace(const char *dev_name);

/*===================================================================
 *  Background GC (call periodically from a low-priority task)
 *===================================================================*/

int tfs_bg_gc(const char *dev_name);

/*===================================================================
 *  Error reporting
 *===================================================================*/

int tfs_get_error(void);

/*===================================================================
 *  Duplicate file descriptor
 *===================================================================*/

int tfs_dup(int fd);

#ifdef __cplusplus
}
#endif

#endif /* TFS_H */
