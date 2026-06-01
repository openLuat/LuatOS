/*
 * nfs.h — Public POSIX-style API for NFS (NAND File System)
 *
 * Include this header and nfs_port.h in your application.
 * All other headers are internal.
 *
 * Error handling:
 *   - Functions return 0 (NFS_OK) on success, -1 (NFS_FAIL) on error.
 *   - File I/O functions return bytes transferred (≥0) on success, -1 on error.
 *   - Call nfs_get_error() for the error code (NFS_E* constants).
 *
 * Directory iteration: integer handle ("dfd"), similar to POSIX fd.
 *   dfd = nfs_opendir(path);  nfs_readdir(dfd, &de);  nfs_closedir(dfd);
 */

#ifndef NFS_H
#define NFS_H

#include "nfs_types.h"
#include "nfs_config.h"
#include "nfs_port.h"

#ifdef __cplusplus
extern "C" {
#endif

/*===================================================================
 *  Stat and directory-entry structures defined in nfs_types.h
 *  (nfs_stat_t, nfs_dirent_t — reproduced here for documentation)
 *===================================================================*/
/* nfs_stat_t fields: st_ino, st_mode, st_uid, st_gid, st_atime,    */
/*                    st_mtime, st_ctime, st_rdev, st_size,          */
/*                    st_blksize, st_blocks                          */
/* nfs_dirent_t fields: d_ino, d_type (NFS_DT_*), d_name            */

/*===================================================================
 *  Global init
 *===================================================================*/

/** nfs_init — must be called once before any other nfs_* function */
int nfs_init(void);

/*===================================================================
 *  Device management (see also nfs_port.h for nfs_add_device)
 *===================================================================*/

/** nfs_remove_device — deregister; device must be unmounted first */
int  nfs_remove_device(const char *name);

/*===================================================================
 *  Mount / unmount / format / sync
 *===================================================================*/

int nfs_mount  (const char *dev_name);
int nfs_unmount(const char *dev_name);
int nfs_format (const char *dev_name);
int nfs_sync   (const char *dev_name);

/*===================================================================
 *  File operations
 *===================================================================*/

int       nfs_open     (const char *path, int flags, nfs_u32 mode);
int       nfs_close    (int fd);
int       nfs_read     (int fd, void *buf, int nbytes);
int       nfs_write    (int fd, const void *buf, int nbytes);
nfs_off_t nfs_lseek    (int fd, nfs_off_t offset, int whence);
int       nfs_fsync    (int fd);

int       nfs_ftruncate(int fd, nfs_off_t new_size);
int       nfs_truncate (const char *path, nfs_off_t new_size);

int       nfs_unlink   (const char *path);
int       nfs_rename   (const char *old_path, const char *new_path);

/*===================================================================
 *  Stat
 *===================================================================*/

int nfs_stat (const char *path, nfs_stat_t *st);
int nfs_lstat(const char *path, nfs_stat_t *st);
int nfs_fstat(int fd,           nfs_stat_t *st);

/*===================================================================
 *  Directories
 *===================================================================*/

int nfs_mkdir  (const char *path, nfs_u32 mode);
int nfs_rmdir  (const char *path);

/** nfs_opendir — return dir-fd (dfd) ≥ 0 on success, -1 on error */
int nfs_opendir (const char *path);
/** nfs_readdir  — fill *de; return 1 = entry, 0 = end, -1 = error */
int nfs_readdir (int dfd, nfs_dirent_t *de);
int nfs_closedir(int dfd);

/*===================================================================
 *  Symlinks and hard links
 *===================================================================*/

int nfs_symlink (const char *target,  const char *linkpath);
int nfs_readlink(const char *path, char *buf, int bufsiz);
int nfs_link    (const char *oldpath, const char *newpath);

/*===================================================================
 *  Device information
 *===================================================================*/

nfs_off_t nfs_freespace (const char *dev_name);
nfs_off_t nfs_totalspace(const char *dev_name);

/*===================================================================
 *  Background GC (call periodically from a low-priority task)
 *===================================================================*/

int nfs_bg_gc(const char *dev_name);

/*===================================================================
 *  Error reporting
 *===================================================================*/

int nfs_get_error(void);

/*===================================================================
 *  Duplicate file descriptor
 *===================================================================*/

int nfs_dup(int fd);

#ifdef __cplusplus
}
#endif

#endif /* NFS_H */
