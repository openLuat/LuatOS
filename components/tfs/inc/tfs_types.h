/*
 * tfs_types.h — Portable fundamental types for TFS
 *
 * TFS: Tiny File System — a portable YAFFS2-algorithm rewrite
 * Target: bare-metal / RTOS, C99, no Linux headers
 */

#ifndef TFS_TYPES_H
#define TFS_TYPES_H

#include <stdint.h>
#include <stddef.h>

/*-------------------------------------------------------------------
 *  Boolean
 *-------------------------------------------------------------------*/
#ifndef __cplusplus
#  include <stdbool.h>
#endif

/*-------------------------------------------------------------------
 *  File offset / size type (always 64-bit so large files work)
 *-------------------------------------------------------------------*/
typedef int64_t  tfs_off_t;

/*-------------------------------------------------------------------
 *  ECC result codes
 *-------------------------------------------------------------------*/
typedef enum {
    TFS_ECC_RESULT_UNKNOWN      = 0,
    TFS_ECC_RESULT_NO_ERROR     = 1,
    TFS_ECC_RESULT_FIXED        = 2,   /* 1-bit corrected */
    TFS_ECC_RESULT_UNFIXED      = 3,   /* uncorrectable   */
    TFS_ECC_RESULT_NOT_CHECKED  = 4    /* no ECC enabled  */
} tfs_ecc_result_t;

/*-------------------------------------------------------------------
 *  Object types (stored in NAND header)
 *-------------------------------------------------------------------*/
typedef enum {
    TFS_OBJ_TYPE_UNKNOWN   = 0,
    TFS_OBJ_TYPE_FILE      = 1,
    TFS_OBJ_TYPE_SYMLINK   = 2,
    TFS_OBJ_TYPE_DIR       = 3,   /* also TFS_OBJ_TYPE_DIRECTORY */
    TFS_OBJ_TYPE_HARDLINK  = 4,
    TFS_OBJ_TYPE_SPECIAL   = 5
} tfs_obj_type_t;

#define TFS_OBJ_TYPE_DIRECTORY TFS_OBJ_TYPE_DIR

/*-------------------------------------------------------------------
 *  Block states
 *-------------------------------------------------------------------*/
typedef enum {
    TFS_BLK_STATE_UNKNOWN    = 0,
    TFS_BLK_STATE_SCANNING   = 1,
    TFS_BLK_STATE_NEEDS_SCAN = 2,
    TFS_BLK_STATE_EMPTY      = 3,
    TFS_BLK_STATE_ALLOCATING = 4,
    TFS_BLK_STATE_FULL       = 5,
    TFS_BLK_STATE_DIRTY      = 6,
    TFS_BLK_STATE_CHECKPOINT = 7,
    TFS_BLK_STATE_COLLECTING = 8,
    TFS_BLK_STATE_DEAD       = 9
} tfs_block_state_t;

/*-------------------------------------------------------------------
 *  Return codes
 *-------------------------------------------------------------------*/
#define TFS_OK    0
#define TFS_FAIL  (-1)

/*-------------------------------------------------------------------
 *  Error codes (errno-compatible subset)
 *-------------------------------------------------------------------*/
#define TFS_ENOENT      2
#define TFS_EBADF       9
#define TFS_ENOMEM     12
#define TFS_EACCES     13
#define TFS_EBUSY      16
#define TFS_EEXIST     17
#define TFS_EXDEV      18
#define TFS_ENODEV     19
#define TFS_ENOTDIR    20
#define TFS_EISDIR     21
#define TFS_EINVAL     22
#define TFS_ENFILE     23
#define TFS_ENOSPC     28
#define TFS_EROFS      30
#define TFS_ENAMETOOLONG 36
#define TFS_ENOTEMPTY  39
#define TFS_ELOOP      40
#define TFS_ERANGE     34
#define TFS_ENODATA    61

/*-------------------------------------------------------------------
 *  Open flags
 *-------------------------------------------------------------------*/
#define TFS_O_RDONLY    0x0000
#define TFS_O_WRONLY    0x0001
#define TFS_O_RDWR      0x0002
#define TFS_O_CREAT     0x0040
#define TFS_O_EXCL      0x0080
#define TFS_O_TRUNC     0x0200
#define TFS_O_APPEND    0x0400

/*-------------------------------------------------------------------
 *  Seek origins
 *-------------------------------------------------------------------*/
#define TFS_SEEK_SET    0
#define TFS_SEEK_CUR    1
#define TFS_SEEK_END    2

/*-------------------------------------------------------------------
 *  File mode bits
 *-------------------------------------------------------------------*/
#define TFS_S_IFMT    0170000u
#define TFS_S_IFREG   0100000u
#define TFS_S_IFDIR   0040000u
#define TFS_S_IFLNK   0120000u
#define TFS_S_ISREG(m) (((m) & TFS_S_IFMT) == TFS_S_IFREG)
#define TFS_S_ISDIR(m) (((m) & TFS_S_IFMT) == TFS_S_IFDIR)
#define TFS_S_ISLNK(m) (((m) & TFS_S_IFMT) == TFS_S_IFLNK)

/*-------------------------------------------------------------------
 *  Directory entry type codes
 *-------------------------------------------------------------------*/
#define TFS_DT_UNKNOWN  0
#define TFS_DT_REG      8
#define TFS_DT_DIR      4
#define TFS_DT_LNK     10

/*-------------------------------------------------------------------
 *  EMFILE
 *-------------------------------------------------------------------*/
#ifndef TFS_EMFILE
#  define TFS_EMFILE  24
#endif

/*-------------------------------------------------------------------
 *  Flash / ECC error codes
 *-------------------------------------------------------------------*/
#define TFS_EIO         5
#define TFS_EFLASH      (-2)
#define TFS_EECCFIXED   (-3)
#define TFS_EECCUNFIXED (-4)

/*-------------------------------------------------------------------
 *  Directory entry (returned by tfs_readdir)
 *-------------------------------------------------------------------*/
#ifndef TFS_MAX_NAME_LEN
#  define TFS_MAX_NAME_LEN 255
#endif

typedef struct {
    uint32_t  d_ino;                     /* object id  */
    uint8_t   d_type;                    /* TFS_DT_*   */
    char     d_name[TFS_MAX_NAME_LEN + 1];
} tfs_dirent_t;

/*-------------------------------------------------------------------
 *  Stat structure (returned by tfs_stat / tfs_fstat)
 *-------------------------------------------------------------------*/
typedef struct {
    uint32_t   st_ino;
    uint32_t   st_mode;
    uint32_t   st_uid;
    uint32_t   st_gid;
    uint32_t   st_atime;
    uint32_t   st_mtime;
    uint32_t   st_ctime;
    uint32_t   st_rdev;
    tfs_off_t st_size;
    uint32_t   st_blksize;
    uint32_t   st_blocks;
} tfs_stat_t;

#endif /* TFS_TYPES_H */
