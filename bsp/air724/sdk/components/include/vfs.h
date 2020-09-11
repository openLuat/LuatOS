/* Copyright (C) 2018 RDA Technologies Limited and/or its affiliates("RDA").
 * All rights reserved.
 *
 * This software is supplied "AS IS" without any warranties.
 * RDA assumes no responsibility or liability for the use of the software,
 * conveys no license or title under any patent, copyright, or mask work
 * right to the product. RDA reserves the right to make changes in the
 * software without notification.  RDA also make no representation or
 * warranty that such application will be suitable for the specified use
 * without further testing or modification.
 */

#ifndef _VFS_H_
#define _VFS_H_

#include <fcntl.h>
#include <sys/stat.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * the maximum absolute file path including mount point, terminate \0
 */
#define VFS_PATH_MAX (192)

#define DT_UNKOWN 0 ///< unknown type
#define DT_DIR 4    ///< directory
#define DT_REG 8    ///< regular file

/**
 * read only flag used in \p vfs_remount
 */
#define MS_RDONLY 1

/**
 * DIR data structure
 */
typedef struct
{
    int16_t fs_index;  ///< internal fs index
    int16_t _reserved; ///< reserved
} DIR;

/**
 * dirent data structure
 */
struct dirent
{
    int d_ino;            ///< inode number, file system implementation can use it for any purpose
    unsigned char d_type; ///< type of file
    char d_name[256];     ///< file name
};

struct statvfs
{
    unsigned long f_bsize;   /* file system block size */
    unsigned long f_frsize;  /* fragment size */
    unsigned long f_blocks;  /* size of fs in f_frsize units */
    unsigned long f_bfree;   /* free blocks in fs */
    unsigned long f_bavail;  /* free blocks avail to non-superuser */
    unsigned long f_files;   /* total file nodes in file system */
    unsigned long f_ffree;   /* free file nodes in fs */
    unsigned long f_favail;  /* avail file nodes in fs */
    unsigned long f_fsid;    /* file system id */
    unsigned long f_flag;    /* mount flags */
    unsigned long f_namemax; /* maximum length of filenames */
};

/**
 * unmount file system by file path
 *
 * \p path must be absolute path, starting with '/'. It can be mount point
 * or arbitrary file or directory under the mount point.
 *
 * \param [in] path     file path
 * \return
 *      - 0 on success
 *      - -1 on error
 *          - EINVAL: invalid parameter
 *          - ENOENT: there are no mount points
 */
int vfs_umount(const char *path);

/**
 * remount file system with flags
 *
 * The only supported flags are \p MS_READONLY.
 *
 * \p path must be a mount point.
 *
 * \param [in] path     mount point path
 * \param [in] flags    file system mount flags
 * \return
 *      - 0 on success
 *      - -1 on error
 *          - ENOENT: \p path is not a mount point
 *          - ENOSYS: the file system doesn't support remount
 *          - others: refer to file system implementation
 */
int vfs_remount(const char *path, unsigned flags);

/**
 * open and possibly create a file
 *
 * It is the same as open a file with O_WRONLY, O_CREAT, O_TRUNC.
 *
 * Refer to man (2) creat.
 *
 * \param [in] path     file path
 * \param [in] mode     file mode, may be ignored by file system
 *                      implementation
 * \return
 *      - file descriptor on success on success
 *      - -1 on error. Refer to file system implementation for errno.
 */
int vfs_creat(const char *path, mode_t mode);

/**
 * open and possibly create a file
 *
 * Refer to man (2) open
 *
 * \param [in] path     file path
 * \param [in] flags    O_CREAT, O_ACCMODE, O_TRUNC
 * \param [in] mode     file mode, may be ignored by file system
 *                      implementation
 * \return
 *      - file descriptor on success on success
 *      - -1 on error. Refer to file system implementation for errno.
 */
int vfs_open(const char *path, int flags, ...);

/**
 * close a file descriptor
 *
 * Refer to man (2) close
 *
 * \param [in] fd       file descriptor
 * \return
 *      - 0 on success
 *      - -1 on error. Refer to file system implementation for errno.
 */
int vfs_close(int fd);

/**
 * read from a file descriptor
 *
 * Refer to man (2) read
 *
 * \param [in] fd       file descriptor
 * \param [out] buf     buf for read
 * \param [in] count    byte count
 * \return
 *      - the number of bytes read on success
 *      - -1 on error. Refer to file system implementation for errno.
 */
ssize_t vfs_read(int fd, void *buf, size_t count);

/**
 * write to a file descriptor
 *
 * Refer to man (2) write
 *
 * \param [in] fd       file descriptor
 * \param [in] buf      buf for write
 * \param [in] count    byte count
 * \return
 *      - the number of bytes written on success
 *      - -1 on error. Refer to file system implementation for errno.
 */
ssize_t vfs_write(int fd, const void *buf, size_t count);

/**
 * reposition read/write file offset
 *
 * Refer to man (2) lseek
 *
 * \param [in] fd       file descriptor
 * \param [in] offset   offset according to the directive whence
 * \param [in] whence   SEEK_SET, SEEK_CUR, SEEK_END
 * \return
 *      - offset location as measured in bytes from the beginning of
 *        the file on success.
 *      - -1 on error. Refer to file system implementation for errno.
 */
long vfs_lseek(int fd, long offset, int whence);

/**
 * get file status
 *
 * Refer to man (2) fstat
 *
 * \param [in] fd       file descriptor
 * \param [out] st      file status
 * \return
 *      - 0 on success
 *      - -1 on error. Refer to file system implementation for errno.
 */
int vfs_fstat(int fd, struct stat *st);

/**
 * get file status
 *
 * Refer to man (2) stat
 *
 * \param [in] path     file path
 * \param [out] st      file status
 * \return
 *      - 0 on success
 *      - -1 on error. Refer to file system implementation for errno.
 */
int vfs_stat(const char *path, struct stat *st);

/**
 * truncate a file to a specified length
 *
 * Refer to man (2) truncate
 *
 * \param [in] path     file path
 * \param [in] length   file length
 * \return
 *      - 0 on success
 *      - -1 on error. Refer to file system implementation for errno.
 */
int vfs_truncate(const char *path, long length);

/**
 * truncate a file to a specified length
 *
 * Refer to man (2) ftruncate
 *
 * \param [in] fd       file descriptor
 * \param [in] length   file length
 * \return
 *      - 0 on success
 *      - -1 on error. Refer to file system implementation for errno.
 */
int vfs_ftruncate(int fd, long length);

/**
 * truncate a file to a specified length
 *
 * Refer to man (2) link. It is just a placeholder, and no file systems
 * support it now.
 *
 * \param [in] oldpath  old file path
 * \param [in] newpath  new file path
 * \return
 *      - -1 on error, errno is ENOSYS
 */
int vfs_link(const char *oldpath, const char *newpath);

/**
 * delete a name and possibly the file it refers to
 *
 * Refer to man (2) unlink
 *
 * \param [in] pathname file path name
 * \return
 *      - 0 on success
 *      - -1 on error. Refer to file system implementation for errno.
 */
int vfs_unlink(const char *pathname);

/**
 * change the name or location of a file
 *
 * Refer to man (2) rename
 *
 * \p oldpath and \p newpath must be on the same mounted file system.
 *
 * \param [in] oldpath  old file path
 * \param [in] newpath  new file path
 * \return
 *      - 0 on success
 *      - -1 on error. Refer to file system implementation for errno.
 *          - EXDEV: oldpath and newpath are not on the same mounted
 *            file system.
 */
int vfs_rename(const char *oldpath, const char *newpath);

/**
 * synchronize a file's in-core state with storage device
 *
 * Refer to man (2) fsync
 *
 * \param [in] fd       file descriptor
 * \return
 *      - 0 on success
 *      - -1 on error. Refer to file system implementation for errno.
 */
int vfs_fsync(int fd);

/**
 * manipulate file descriptor
 *
 * Refer to man (2) fcntl. It is just a placeholder, and no file systems
 * support it now.
 *
 * \param [in] fd       file descriptor
 * \param [in] cmd      command
 * \return
 *      - -1 on error, errno is ENOSYS
 */
int vfs_fcntl(int fd, int cmd, ...);

/**
 * control device
 *
 * Refer to man (2) ioctl. It is just a placeholder, and no file systems
 * support it now.
 *
 * \param [in] fd       file descriptor
 * \param [in] cmd      command
 * \return
 *      - -1 on error, errno is ENOSYS
 */
int vfs_ioctl(int fd, unsigned long request, ...);

/**
 * open a directory
 *
 * Refer to man (3) opendir
 *
 * \param [in] name     directory name
 * \return
 *      - 0 on success
 *      - -1 on error. Refer to file system implementation for errno.
 */
DIR *vfs_opendir(const char *name);

/**
 * read a directory
 *
 * Refer to man (3) readdir
 *
 * \param [in] dirp     directory pointer returned by \p vfs_opendir
 * \return
 *      - 0 on success
 *      - -1 on error. Refer to file system implementation for errno.
 */
struct dirent *vfs_readdir(DIR *dirp);

/**
 * read a directory
 *
 * Refer to man (3) readdir_r
 *
 * \param [in] dirp     directory pointer returned by \p vfs_opendir
 * \param [out] entry   dirent buffer
 * \param [out] result  pointer to dirent buffer
 * \return
 *      - 0 on success
 *      - -1 on error. Refer to file system implementation for errno.
 */
int vfs_readdir_r(DIR *dirp, struct dirent *entry, struct dirent **result);

/**
 * return current location in directory stream
 *
 * Refer to man (3) telldir
 *
 * \param [in] dirp     directory pointer returned by \p vfs_opendir
 * \return
 *      - 0 on success
 *      - -1 on error. Refer to file system implementation for errno.
 */
long vfs_telldir(DIR *pdir);

/**
 * set the position of the next readdir() call in the directory stream
 *
 * Refer to man (3) seekdir
 *
 * \param [in] dirp     directory pointer returned by \p vfs_opendir
 * \param [in] loc      location returned by \p vfs_telldir
 * \return
 *      - 0 on success
 *      - -1 on error. Refer to file system implementation for errno.
 */
void vfs_seekdir(DIR *pdir, long loc);

/**
 * reset directory stream
 *
 * Refer to man (3) rewinddir
 *
 * \param [in] dirp     directory pointer returned by \p vfs_opendir
 * \return
 *      - 0 on success
 *      - -1 on error. Refer to file system implementation for errno.
 */
void vfs_rewinddir(DIR *pdir);

/**
 * close a directory
 *
 * Refer to man (3) closedir
 *
 * \param [in] dirp     directory pointer returned by \p vfs_opendir
 * \return
 *      - 0 on success
 *      - -1 on error. Refer to file system implementation for errno.
 */
int vfs_closedir(DIR *pdir);

/**
 * create a directory
 *
 * Refer to man (2) mkdir
 *
 * \param [in] pathname directory path name
 * \param [in] mode     create mode
 * \return
 *      - 0 on success
 *      - -1 on error. Refer to file system implementation for errno.
 */
int vfs_mkdir(const char *pathname, mode_t mode);

/**
 * delete a directory
 *
 * Refer to man (2) rmdir
 *
 * \param [in] pathname directory path name
 * \return
 *      - 0 on success
 *      - -1 on error. Refer to file system implementation for errno.
 */
int vfs_rmdir(const char *pathname);

/**
 * change working directory
 *
 * Refer to man (2) chdir
 *
 * NOTE: in RTOS system, working directory is a global concept. It is
 * dangerous to change working directory. Don't call \p vfs_chdir
 * unless it is absolutely needed, and you really know what you are
 * doing.
 *
 * \param [in] path     directory path name
 * \return
 *      - 0 on success
 *      - -1 on error
 */
int vfs_chdir(const char *path);

/**
 * get current working directory
 *
 * Refer to man (3) getcwd
 *
 * \param [out] buf     buffer for result
 * \param [in] size     buffer size
 * \return
 *      - current working directory on success
 *      - NULL on error
 */
char *vfs_getcwd(char *buf, size_t size);

/**
 * return the canonicalized absolute pathname
 *
 * Refer to man (3) realpath
 *
 * \param [in] path     file path
 * \param [in] resolved_path    buffer for canonicalized absolute pathname
 * \return
 *      - \p resolved_path on success
 *      - NULL on error
 */
char *vfs_realpath(const char *path, char *resolved_path);

/**
 * get filesystem statistics
 *
 * Refer to man (3) statvfs
 *
 * \param [in] path     file path
 * \param [in] buf      filesystem statistics
 * \return
 *      - 0 on success
 *      - -1 on error
 */
int vfs_statvfs(const char *path, struct statvfs *buf);

/**
 * get filesystem statistics
 *
 * Refer to man (3) fstatvfs
 *
 * \param [in] fd       file descriptor
 * \param [in] buf      filesystem statistics
 * \return
 *      - 0 on success
 *      - -1 on error
 */
int vfs_fstatvfs(int fd, struct statvfs *buf);

/**
 * get mounted file system count
 *
 * \return  mounted file system count
 */
int vfs_mount_count(void);

/**
 * get mounted file system mount points
 *
 * \param [in] mp       buffer for mount points
 * \param [in] count    buffer count
 * \return  count of get mount points
 */
int vfs_mount_points(char **mp, size_t count);

/**
 * helper to get canonicalized absolute pathname
 *
 * It is similar to \p vfs_realpath, just with specified base path name.
 *
 * \param [in] base_path    base path name
 * \param [in] path         path related to base_path
 * \param [in] resolved_path    buffer for canonicalized absolute pathname
 * \return
 *      - \p resolved_path on success
 *      - NULL on error
 */
char *vfs_resolve_path(const char *base_path, const char *path, char *resolved_path);

/**
 * create directory with all parents
 *
 * \param [in] path         path of directory to be created
 * \param [in] mode     create mode
 * \return
 *      - 0 on succes
 *      - -1 on error
 */
int vfs_mkpath(const char *path, mode_t mode);

/**
 * create directory with all parents of a file
 *
 * \param [in] path         path of file
 * \param [in] mode     create mode
 * \return
 *      - 0 on succes
 *      - -1 on error
 */
int vfs_mkfilepath(const char *path, mode_t mode);

/**
 * helper to get file size
 *
 * It calls \p vfs_stat to get file status, and return file size only.
 *
 * \param [in] path     file path
 * \return
 *      - file size on success
 *      - -1 on error
 */
ssize_t vfs_file_size(const char *path);

/**
 * helper to read file
 *
 * It calls \p vfs_open, \p vfs_read and \p vfs_close to read bytes from file.
 *
 * \param [in] path     file path
 * \param [in] buf      buf for read
 * \param [in] count    byte count
 * \return
 *      - the number of bytes read on success
 *      - -1 on error
 */
ssize_t vfs_file_read(const char *path, void *buf, size_t count);

/**
 * helper to write file
 *
 * It calls \p vfs_open, \p vfs_write and \p vfs_close to write bytes to file.
 *
 * \param [in] path     file path
 * \param [in] buf      buf for write
 * \param [in] count    byte count
 * \return
 *      - the number of bytes written on success
 *      - -1 on error
 */
ssize_t vfs_file_write(const char *path, const void *buf, size_t count);

/**
 * initial check for safe file
 *
 * *safe file* is just a normal file, just write is special designed for power
 * failure safe write. That is, when there is power failure during file write,
 * the file on file system will either be the original content, or the new
 * content.
 *
 * It is needed to write the whole content in one call. Partial write is not
 * supported.
 *
 * When there is power failure during write, there may exist garbages on file
 * system. \p vfs_sfile_init will clean up the garbages.
 *
 * \param [in] path     safe file path
 * \return
 *      - 0 on success
 *      - -1 if the safe file isn't exist or invalid
 */
int vfs_sfile_init(const char *path);

/**
 * get safe file size
 *
 * It is the same as \p vfs_file_size.
 *
 * \param [in] path     file path
 * \return
 *      - file size on success
 *      - -1 on error
 */
ssize_t vfs_sfile_size(const char *path);

/**
 * read safe file
 *
 * \param [in] path     file path
 * \param [in] buf      buf for read
 * \param [in] count    byte count
 * \return
 *      - the number of bytes read on success
 *      - -1 on error
 */
ssize_t vfs_sfile_read(const char *path, void *buf, size_t count);

/**
 * write safe file
 *
 * \param [in] path     file path
 * \param [in] buf      buf for write
 * \param [in] count    byte count
 * \return
 *      - the number of bytes written on success
 *      - -1 on error
 */
ssize_t vfs_sfile_write(const char *path, const void *buf, size_t count);

/**
 * delete files and subdirectories under a directory
 *
 * \param [in] path     directory path
 * \return
 *      - the number of bytes read on success
 *      - -1 on error
 */
int vfs_rmchildren(const char *path);

/**
 * delete directory and children under the directory
 *
 * \param [in] path     directory path
 * \return
 *      - the number of bytes read on success
 *      - -1 on error
 */
int vfs_rmdir_recursive(const char *path);

/**
 * umount all mounted file system
 *
 * It should only be called in FDL now. And in application, the
 * implementation is empty.
 */
void vfs_umount_all(void);

/**
 * fs handle of a path
 *
 * It is for debug only, get the file system implementation handler.
 *
 * \param [in] path     file path
 * \return
 *      - the file system implementation handler
 */
void *vfs_fs_handle(const char *path);

#ifdef __cplusplus
}
#endif

#endif // H
