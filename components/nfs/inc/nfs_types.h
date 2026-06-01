/*
 * nfs_types.h — Portable fundamental types for NFS
 *
 * NFS: NAND File System — a portable YAFFS2-algorithm rewrite
 * Target: bare-metal / RTOS, C99, no Linux headers
 */

#ifndef NFS_TYPES_H
#define NFS_TYPES_H

#include <stdint.h>
#include <stddef.h>

/*-------------------------------------------------------------------
 *  Boolean
 *-------------------------------------------------------------------*/
#ifndef __cplusplus
#  include <stdbool.h>
#endif

/*-------------------------------------------------------------------
 *  Convenience shorthands (internal use)
 *-------------------------------------------------------------------*/
typedef uint8_t  nfs_u8;
typedef uint16_t nfs_u16;
typedef uint32_t nfs_u32;
typedef uint64_t nfs_u64;
typedef int8_t   nfs_s8;
typedef int16_t  nfs_s16;
typedef int32_t  nfs_s32;
typedef int64_t  nfs_s64;

/*-------------------------------------------------------------------
 *  File offset / size type (always 64-bit so large files work)
 *-------------------------------------------------------------------*/
typedef int64_t  nfs_off_t;

/*-------------------------------------------------------------------
 *  ECC result codes
 *-------------------------------------------------------------------*/
typedef enum {
    NFS_ECC_RESULT_UNKNOWN      = 0,
    NFS_ECC_RESULT_NO_ERROR     = 1,
    NFS_ECC_RESULT_FIXED        = 2,   /* 1-bit corrected */
    NFS_ECC_RESULT_UNFIXED      = 3,   /* uncorrectable   */
    NFS_ECC_RESULT_NOT_CHECKED  = 4    /* no ECC enabled  */
} nfs_ecc_result_t;

/*-------------------------------------------------------------------
 *  Object types (stored in NAND header)
 *-------------------------------------------------------------------*/
typedef enum {
    NFS_OBJ_TYPE_UNKNOWN   = 0,
    NFS_OBJ_TYPE_FILE      = 1,
    NFS_OBJ_TYPE_SYMLINK   = 2,
    NFS_OBJ_TYPE_DIR       = 3,   /* also NFS_OBJ_TYPE_DIRECTORY */
    NFS_OBJ_TYPE_HARDLINK  = 4,
    NFS_OBJ_TYPE_SPECIAL   = 5
} nfs_obj_type_t;

#define NFS_OBJ_TYPE_DIRECTORY NFS_OBJ_TYPE_DIR

/*-------------------------------------------------------------------
 *  Block states
 *-------------------------------------------------------------------*/
typedef enum {
    NFS_BLK_STATE_UNKNOWN    = 0,
    NFS_BLK_STATE_SCANNING   = 1,
    NFS_BLK_STATE_NEEDS_SCAN = 2,
    NFS_BLK_STATE_EMPTY      = 3,
    NFS_BLK_STATE_ALLOCATING = 4,
    NFS_BLK_STATE_FULL       = 5,
    NFS_BLK_STATE_DIRTY      = 6,
    NFS_BLK_STATE_CHECKPOINT = 7,
    NFS_BLK_STATE_COLLECTING = 8,
    NFS_BLK_STATE_DEAD       = 9
} nfs_block_state_t;

/*-------------------------------------------------------------------
 *  Return codes
 *-------------------------------------------------------------------*/
#define NFS_OK    0
#define NFS_FAIL  (-1)

/*-------------------------------------------------------------------
 *  Error codes (errno-compatible subset)
 *-------------------------------------------------------------------*/
#define NFS_ENOENT      2
#define NFS_EBADF       9
#define NFS_ENOMEM     12
#define NFS_EACCES     13
#define NFS_EBUSY      16
#define NFS_EEXIST     17
#define NFS_EXDEV      18
#define NFS_ENODEV     19
#define NFS_ENOTDIR    20
#define NFS_EISDIR     21
#define NFS_EINVAL     22
#define NFS_ENFILE     23
#define NFS_ENOSPC     28
#define NFS_EROFS      30
#define NFS_ENAMETOOLONG 36
#define NFS_ENOTEMPTY  39
#define NFS_ELOOP      40
#define NFS_ERANGE     34
#define NFS_ENODATA    61

/*-------------------------------------------------------------------
 *  Open flags
 *-------------------------------------------------------------------*/
#define NFS_O_RDONLY    0x0000
#define NFS_O_WRONLY    0x0001
#define NFS_O_RDWR      0x0002
#define NFS_O_CREAT     0x0040
#define NFS_O_EXCL      0x0080
#define NFS_O_TRUNC     0x0200
#define NFS_O_APPEND    0x0400

/*-------------------------------------------------------------------
 *  Seek origins
 *-------------------------------------------------------------------*/
#define NFS_SEEK_SET    0
#define NFS_SEEK_CUR    1
#define NFS_SEEK_END    2

/*-------------------------------------------------------------------
 *  File mode bits
 *-------------------------------------------------------------------*/
#define NFS_S_IFMT    0170000u
#define NFS_S_IFREG   0100000u
#define NFS_S_IFDIR   0040000u
#define NFS_S_IFLNK   0120000u
#define NFS_S_ISREG(m) (((m) & NFS_S_IFMT) == NFS_S_IFREG)
#define NFS_S_ISDIR(m) (((m) & NFS_S_IFMT) == NFS_S_IFDIR)
#define NFS_S_ISLNK(m) (((m) & NFS_S_IFMT) == NFS_S_IFLNK)

/*-------------------------------------------------------------------
 *  Directory entry type codes
 *-------------------------------------------------------------------*/
#define NFS_DT_UNKNOWN  0
#define NFS_DT_REG      8
#define NFS_DT_DIR      4
#define NFS_DT_LNK     10

/*-------------------------------------------------------------------
 *  Null pointer
 *-------------------------------------------------------------------*/
#ifndef NFS_NULL
#  define NFS_NULL ((void *)0)
#endif

/*-------------------------------------------------------------------
 *  EMFILE
 *-------------------------------------------------------------------*/
#ifndef NFS_EMFILE
#  define NFS_EMFILE  24
#endif

/*-------------------------------------------------------------------
 *  Flash / ECC error codes
 *-------------------------------------------------------------------*/
#define NFS_EIO         5
#define NFS_EFLASH      (-2)
#define NFS_EECCFIXED   (-3)
#define NFS_EECCUNFIXED (-4)

/*-------------------------------------------------------------------
 *  Directory entry (returned by nfs_readdir)
 *-------------------------------------------------------------------*/
#ifndef NFS_MAX_NAME_LEN
#  define NFS_MAX_NAME_LEN 255
#endif

typedef struct {
    nfs_u32  d_ino;                     /* object id  */
    nfs_u8   d_type;                    /* NFS_DT_*   */
    char     d_name[NFS_MAX_NAME_LEN + 1];
} nfs_dirent_t;

/*-------------------------------------------------------------------
 *  Stat structure (returned by nfs_stat / nfs_fstat)
 *-------------------------------------------------------------------*/
typedef struct {
    nfs_u32   st_ino;
    nfs_u32   st_mode;
    nfs_u32   st_uid;
    nfs_u32   st_gid;
    nfs_u32   st_atime;
    nfs_u32   st_mtime;
    nfs_u32   st_ctime;
    nfs_u32   st_rdev;
    nfs_off_t st_size;
    nfs_u32   st_blksize;
    nfs_u32   st_blocks;
} nfs_stat_t;

#endif /* NFS_TYPES_H */
