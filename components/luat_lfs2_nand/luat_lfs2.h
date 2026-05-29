/*
 * The little filesystem
 *
 * Copyright (c) 2022, The littlefs authors.
 * Copyright (c) 2017, Arm Limited. All rights reserved.
 * SPDX-License-Identifier: BSD-3-Clause
 */
#ifndef LUAT_LFS2_H
#define LUAT_LFS2_H

#include "luat_lfs2_util.h"

#ifdef __cplusplus
extern "C"
{
#endif


/// Version info ///

// Software library version
// Major (top-nibble), incremented on backwards incompatible changes
// Minor (bottom-nibble), incremented on feature additions
#define LFS_VERSION 0x00020009
#define LFS_VERSION_MAJOR (0xffff & (LFS_VERSION >> 16))
#define LFS_VERSION_MINOR (0xffff & (LFS_VERSION >>  0))

// Version of On-disk data structures
// Major (top-nibble), incremented on backwards incompatible changes
// Minor (bottom-nibble), incremented on feature additions
#define LFS_DISK_VERSION 0x00020001
#define LFS_DISK_VERSION_MAJOR (0xffff & (LFS_DISK_VERSION >> 16))
#define LFS_DISK_VERSION_MINOR (0xffff & (LFS_DISK_VERSION >>  0))


/// Definitions ///

// Type definitions
typedef uint32_t luat_lfs2_size_t;
typedef uint32_t luat_lfs2_off_t;

typedef int32_t  luat_lfs2_ssize_t;
typedef int32_t  luat_lfs2_soff_t;

typedef uint32_t luat_lfs2_block_t;

// Maximum name size in bytes, may be redefined to reduce the size of the
// info struct. Limited to <= 1022. Stored in superblock and must be
// respected by other littlefs drivers.
#ifndef LFS_NAME_MAX
#define LFS_NAME_MAX 255
#endif

// Maximum size of a file in bytes, may be redefined to limit to support other
// drivers. Limited on disk to <= 2147483647. Stored in superblock and must be
// respected by other littlefs drivers.
#ifndef LFS_FILE_MAX
#define LFS_FILE_MAX 2147483647
#endif

// Maximum size of custom attributes in bytes, may be redefined, but there is
// no real benefit to using a smaller LFS_ATTR_MAX. Limited to <= 1022. Stored
// in superblock and must be respected by other littlefs drivers.
#ifndef LFS_ATTR_MAX
#define LFS_ATTR_MAX 1022
#endif

// Possible error codes, these are negative to allow
// valid positive return values
enum luat_lfs2_error {
    LFS_ERR_OK          = 0,    // No error
    LFS_ERR_IO          = -5,   // Error during device operation
    LFS_ERR_CORRUPT     = -84,  // Corrupted
    LFS_ERR_NOENT       = -2,   // No directory entry
    LFS_ERR_EXIST       = -17,  // Entry already exists
    LFS_ERR_NOTDIR      = -20,  // Entry is not a dir
    LFS_ERR_ISDIR       = -21,  // Entry is a dir
    LFS_ERR_NOTEMPTY    = -39,  // Dir is not empty
    LFS_ERR_BADF        = -9,   // Bad file number
    LFS_ERR_FBIG        = -27,  // File too large
    LFS_ERR_INVAL       = -22,  // Invalid parameter
    LFS_ERR_NOSPC       = -28,  // No space left on device
    LFS_ERR_NOMEM       = -12,  // No more memory available
    LFS_ERR_NOATTR      = -61,  // No data/attr available
    LFS_ERR_NAMETOOLONG = -36,  // File name too long
};

// File types
enum luat_lfs2_type {
    // file types
    LFS_TYPE_REG            = 0x001,
    LFS_TYPE_DIR            = 0x002,

    // internally used types
    LFS_TYPE_SPLICE         = 0x400,
    LFS_TYPE_NAME           = 0x000,
    LFS_TYPE_STRUCT         = 0x200,
    LFS_TYPE_USERATTR       = 0x300,
    LFS_TYPE_FROM           = 0x100,
    LFS_TYPE_TAIL           = 0x600,
    LFS_TYPE_GLOBALS        = 0x700,
    LFS_TYPE_CRC            = 0x500,

    // internally used type specializations
    LFS_TYPE_CREATE         = 0x401,
    LFS_TYPE_DELETE         = 0x4ff,
    LFS_TYPE_SUPERBLOCK     = 0x0ff,
    LFS_TYPE_DIRSTRUCT      = 0x200,
    LFS_TYPE_CTZSTRUCT      = 0x202,
    LFS_TYPE_INLINESTRUCT   = 0x201,
    LFS_TYPE_SOFTTAIL       = 0x600,
    LFS_TYPE_HARDTAIL       = 0x601,
    LFS_TYPE_MOVESTATE      = 0x7ff,
    LFS_TYPE_CCRC           = 0x500,
    LFS_TYPE_FCRC           = 0x5ff,

    // internal chip sources
    LFS_FROM_NOOP           = 0x000,
    LFS_FROM_MOVE           = 0x101,
    LFS_FROM_USERATTRS      = 0x102,
};

// File open flags
enum luat_lfs2_open_flags {
    // open flags
    LFS_O_RDONLY = 1,         // Open a file as read only
#ifndef LFS_READONLY
    LFS_O_WRONLY = 2,         // Open a file as write only
    LFS_O_RDWR   = 3,         // Open a file as read and write
    LFS_O_CREAT  = 0x0100,    // Create a file if it does not exist
    LFS_O_EXCL   = 0x0200,    // Fail if a file already exists
    LFS_O_TRUNC  = 0x0400,    // Truncate the existing file to zero size
    LFS_O_APPEND = 0x0800,    // Move to end of file on every write
#endif

    // internally used flags
#ifndef LFS_READONLY
    LFS_F_DIRTY   = 0x010000, // File does not match storage
    LFS_F_WRITING = 0x020000, // File has been written since last flush
#endif
    LFS_F_READING = 0x040000, // File has been read since last flush
#ifndef LFS_READONLY
    LFS_F_ERRED   = 0x080000, // An error occurred during write
#endif
    LFS_F_INLINE  = 0x100000, // Currently inlined in directory entry
};

// File seek flags
enum luat_lfs2_whence_flags {
    LFS_SEEK_SET = 0,   // Seek relative to an absolute position
    LFS_SEEK_CUR = 1,   // Seek relative to the current file position
    LFS_SEEK_END = 2,   // Seek relative to the end of the file
};


// Configuration provided during initialization of the littlefs
struct luat_lfs2_config {
    // Opaque user provided context that can be used to pass
    // information to the block device operations
    void *context;

    // Read a region in a block. Negative error codes are propagated
    // to the user.
    int (*read)(const struct luat_lfs2_config *c, luat_lfs2_block_t block,
            luat_lfs2_off_t off, void *buffer, luat_lfs2_size_t size);

    // Program a region in a block. The block must have previously
    // been erased. Negative error codes are propagated to the user.
    // May return LFS_ERR_CORRUPT if the block should be considered bad.
    int (*prog)(const struct luat_lfs2_config *c, luat_lfs2_block_t block,
            luat_lfs2_off_t off, const void *buffer, luat_lfs2_size_t size);

    // Erase a block. A block must be erased before being programmed.
    // The state of an erased block is undefined. Negative error codes
    // are propagated to the user.
    // May return LFS_ERR_CORRUPT if the block should be considered bad.
    int (*erase)(const struct luat_lfs2_config *c, luat_lfs2_block_t block);

    // Sync the state of the underlying block device. Negative error codes
    // are propagated to the user.
    int (*sync)(const struct luat_lfs2_config *c);

#ifdef LFS_THREADSAFE
    // Lock the underlying block device. Negative error codes
    // are propagated to the user.
    int (*lock)(const struct luat_lfs2_config *c);

    // Unlock the underlying block device. Negative error codes
    // are propagated to the user.
    int (*unlock)(const struct luat_lfs2_config *c);
#endif

    // Minimum size of a block read in bytes. All read operations will be a
    // multiple of this value.
    luat_lfs2_size_t read_size;

    // Minimum size of a block program in bytes. All program operations will be
    // a multiple of this value.
    luat_lfs2_size_t prog_size;

    // Size of an erasable block in bytes. This does not impact ram consumption
    // and may be larger than the physical erase size. However, non-inlined
    // files take up at minimum one block. Must be a multiple of the read and
    // program sizes.
    luat_lfs2_size_t block_size;

    // Number of erasable blocks on the device. Defaults to block_count stored
    // on disk when zero.
    luat_lfs2_size_t block_count;

    // Number of erase cycles before littlefs evicts metadata logs and moves
    // the metadata to another block. Suggested values are in the
    // range 100-1000, with large values having better performance at the cost
    // of less consistent wear distribution.
    //
    // Set to -1 to disable block-level wear-leveling.
    int32_t block_cycles;

    // Size of block caches in bytes. Each cache buffers a portion of a block in
    // RAM. The littlefs needs a read cache, a program cache, and one additional
    // cache per file. Larger caches can improve performance by storing more
    // data and reducing the number of disk accesses. Must be a multiple of the
    // read and program sizes, and a factor of the block size.
    luat_lfs2_size_t cache_size;

    // Size of the lookahead buffer in bytes. A larger lookahead buffer
    // increases the number of blocks found during an allocation pass. The
    // lookahead buffer is stored as a compact bitmap, so each byte of RAM
    // can track 8 blocks.
    luat_lfs2_size_t lookahead_size;

    // Threshold for metadata compaction during luat_lfs2_fs_gc in bytes. Metadata
    // pairs that exceed this threshold will be compacted during luat_lfs2_fs_gc.
    // Defaults to ~88% block_size when zero, though the default may change
    // in the future.
    //
    // Note this only affects luat_lfs2_fs_gc. Normal compactions still only occur
    // when full.
    //
    // Set to -1 to disable metadata compaction during luat_lfs2_fs_gc.
    luat_lfs2_size_t compact_thresh;

    // Optional statically allocated read buffer. Must be cache_size.
    // By default luat_lfs2_malloc is used to allocate this buffer.
    void *read_buffer;

    // Optional statically allocated program buffer. Must be cache_size.
    // By default luat_lfs2_malloc is used to allocate this buffer.
    void *prog_buffer;

    // Optional statically allocated lookahead buffer. Must be lookahead_size.
    // By default luat_lfs2_malloc is used to allocate this buffer.
    void *lookahead_buffer;

    // Optional upper limit on length of file names in bytes. No downside for
    // larger names except the size of the info struct which is controlled by
    // the LFS_NAME_MAX define. Defaults to LFS_NAME_MAX or name_max stored on
    // disk when zero.
    luat_lfs2_size_t name_max;

    // Optional upper limit on files in bytes. No downside for larger files
    // but must be <= LFS_FILE_MAX. Defaults to LFS_FILE_MAX or file_max stored
    // on disk when zero.
    luat_lfs2_size_t file_max;

    // Optional upper limit on custom attributes in bytes. No downside for
    // larger attributes size but must be <= LFS_ATTR_MAX. Defaults to
    // LFS_ATTR_MAX or attr_max stored on disk when zero.
    luat_lfs2_size_t attr_max;

    // Optional upper limit on total space given to metadata pairs in bytes. On
    // devices with large blocks (e.g. 128kB) setting this to a low size (2-8kB)
    // can help bound the metadata compaction time. Must be <= block_size.
    // Defaults to block_size when zero.
    luat_lfs2_size_t metadata_max;

    // Optional upper limit on inlined files in bytes. Inlined files live in
    // metadata and decrease storage requirements, but may be limited to
    // improve metadata-related performance. Must be <= cache_size, <=
    // attr_max, and <= block_size/8. Defaults to the largest possible
    // inline_max when zero.
    //
    // Set to -1 to disable inlined files.
    luat_lfs2_size_t inline_max;

#ifdef LFS_MULTIVERSION
    // On-disk version to use when writing in the form of 16-bit major version
    // + 16-bit minor version. This limiting metadata to what is supported by
    // older minor versions. Note that some features will be lost. Defaults to 
    // to the most recent minor version when zero.
    uint32_t disk_version;
#endif
};

// File info structure
struct luat_lfs2_info {
    // Type of the file, either LFS_TYPE_REG or LFS_TYPE_DIR
    uint8_t type;

    // Size of the file, only valid for REG files. Limited to 32-bits.
    luat_lfs2_size_t size;

    // Name of the file stored as a null-terminated string. Limited to
    // LFS_NAME_MAX+1, which can be changed by redefining LFS_NAME_MAX to
    // reduce RAM. LFS_NAME_MAX is stored in superblock and must be
    // respected by other littlefs drivers.
    char name[LFS_NAME_MAX+1];
};

// Filesystem info structure
struct luat_lfs2_fsinfo {
    // On-disk version.
    uint32_t disk_version;

    // Size of a logical block in bytes.
    luat_lfs2_size_t block_size;

    // Number of logical blocks in filesystem.
    luat_lfs2_size_t block_count;

    // Upper limit on the length of file names in bytes.
    luat_lfs2_size_t name_max;

    // Upper limit on the size of files in bytes.
    luat_lfs2_size_t file_max;

    // Upper limit on the size of custom attributes in bytes.
    luat_lfs2_size_t attr_max;
};

// Custom attribute structure, used to describe custom attributes
// committed atomically during file writes.
struct luat_lfs2_attr {
    // 8-bit type of attribute, provided by user and used to
    // identify the attribute
    uint8_t type;

    // Pointer to buffer containing the attribute
    void *buffer;

    // Size of attribute in bytes, limited to LFS_ATTR_MAX
    luat_lfs2_size_t size;
};

// Optional configuration provided during luat_lfs2_file_opencfg
struct luat_lfs2_file_config {
    // Optional statically allocated file buffer. Must be cache_size.
    // By default luat_lfs2_malloc is used to allocate this buffer.
    void *buffer;

    // Optional list of custom attributes related to the file. If the file
    // is opened with read access, these attributes will be read from disk
    // during the open call. If the file is opened with write access, the
    // attributes will be written to disk every file sync or close. This
    // write occurs atomically with update to the file's contents.
    //
    // Custom attributes are uniquely identified by an 8-bit type and limited
    // to LFS_ATTR_MAX bytes. When read, if the stored attribute is smaller
    // than the buffer, it will be padded with zeros. If the stored attribute
    // is larger, then it will be silently truncated. If the attribute is not
    // found, it will be created implicitly.
    struct luat_lfs2_attr *attrs;

    // Number of custom attributes in the list
    luat_lfs2_size_t attr_count;
};


/// internal littlefs data structures ///
typedef struct luat_lfs2_cache {
    luat_lfs2_block_t block;
    luat_lfs2_off_t off;
    luat_lfs2_size_t size;
    uint8_t *buffer;
} luat_lfs2_cache_t;

typedef struct luat_lfs2_mdir {
    luat_lfs2_block_t pair[2];
    uint32_t rev;
    luat_lfs2_off_t off;
    uint32_t etag;
    uint16_t count;
    bool erased;
    bool split;
    luat_lfs2_block_t tail[2];
} luat_lfs2_mdir_t;

// littlefs directory type
typedef struct luat_lfs2_dir {
    struct luat_lfs2_dir *next;
    uint16_t id;
    uint8_t type;
    luat_lfs2_mdir_t m;

    luat_lfs2_off_t pos;
    luat_lfs2_block_t head[2];
} luat_lfs2_dir_t;

// littlefs file type
typedef struct luat_lfs2_file {
    struct luat_lfs2_file *next;
    uint16_t id;
    uint8_t type;
    luat_lfs2_mdir_t m;

    struct luat_lfs2_ctz {
        luat_lfs2_block_t head;
        luat_lfs2_size_t size;
    } ctz;

    uint32_t flags;
    luat_lfs2_off_t pos;
    luat_lfs2_block_t block;
    luat_lfs2_off_t off;
    luat_lfs2_cache_t cache;

    const struct luat_lfs2_file_config *cfg;
} luat_lfs2_file_t;

typedef struct luat_lfs2_superblock {
    uint32_t version;
    luat_lfs2_size_t block_size;
    luat_lfs2_size_t block_count;
    luat_lfs2_size_t name_max;
    luat_lfs2_size_t file_max;
    luat_lfs2_size_t attr_max;
} luat_lfs2_superblock_t;

typedef struct luat_lfs2_gstate {
    uint32_t tag;
    luat_lfs2_block_t pair[2];
} luat_lfs2_gstate_t;

#ifndef LFS_READONLY
typedef struct {
    uint32_t reserve_hit_count;
    uint32_t foreground_erase_count;
    uint32_t refill_erase_count;
    uint32_t refill_fail_count;
    uint32_t emergency_fallback_count;
    uint32_t reserve_peak_count;
    uint32_t reserve_current_count;
} luat_lfs2_preerase_stats_t;
#endif

// The littlefs filesystem type
typedef struct lfs {
    luat_lfs2_cache_t rcache;
    luat_lfs2_cache_t pcache;

    luat_lfs2_block_t root[2];
    struct luat_lfs2_mlist {
        struct luat_lfs2_mlist *next;
        uint16_t id;
        uint8_t type;
        luat_lfs2_mdir_t m;
    } *mlist;
    uint32_t seed;

    luat_lfs2_gstate_t gstate;
    luat_lfs2_gstate_t gdisk;
    luat_lfs2_gstate_t gdelta;

    struct luat_lfs2_lookahead {
        luat_lfs2_block_t start;
        luat_lfs2_block_t size;
        luat_lfs2_block_t next;
        luat_lfs2_block_t ckpoint;
        uint8_t *buffer;
    } lookahead;

    const struct luat_lfs2_config *cfg;
    luat_lfs2_size_t block_count;
    luat_lfs2_size_t name_max;
    luat_lfs2_size_t file_max;
    luat_lfs2_size_t attr_max;
    luat_lfs2_size_t inline_max;

#ifdef LFS_MIGRATE
    struct lfs1 *lfs1;
#endif

#ifndef LFS_READONLY
    uint8_t preerase_enabled;
    uint8_t preerase_reserve_low;
    uint8_t preerase_reserve_high;
    uint8_t preerase_reserve_count;
    uint8_t preerase_reserve_head;
    uint8_t preerase_reserve_tail;
    uint8_t preerase_reserve_peak;
    luat_lfs2_block_t preerase_reserve[8];
    luat_lfs2_preerase_stats_t preerase_stats;
#endif
} luat_lfs2_t;


/// Filesystem functions ///

#ifndef LFS_READONLY
// Format a block device with the littlefs
//
// Requires a littlefs object and config struct. This clobbers the littlefs
// object, and does not leave the filesystem mounted. The config struct must
// be zeroed for defaults and backwards compatibility.
//
// Returns a negative error code on failure.
int luat_lfs2_format(luat_lfs2_t *lfs, const struct luat_lfs2_config *config);
#endif

// Mounts a littlefs
//
// Requires a littlefs object and config struct. Multiple filesystems
// may be mounted simultaneously with multiple littlefs objects. Both
// lfs and config must be allocated while mounted. The config struct must
// be zeroed for defaults and backwards compatibility.
//
// Returns a negative error code on failure.
int luat_lfs2_mount(luat_lfs2_t *lfs, const struct luat_lfs2_config *config);

// Unmounts a littlefs
//
// Does nothing besides releasing any allocated resources.
// Returns a negative error code on failure.
int luat_lfs2_unmount(luat_lfs2_t *lfs);

/// General operations ///

#ifndef LFS_READONLY
// Removes a file or directory
//
// If removing a directory, the directory must be empty.
// Returns a negative error code on failure.
int luat_lfs2_remove(luat_lfs2_t *lfs, const char *path);
#endif

#ifndef LFS_READONLY
// Rename or move a file or directory
//
// If the destination exists, it must match the source in type.
// If the destination is a directory, the directory must be empty.
//
// Returns a negative error code on failure.
int luat_lfs2_rename(luat_lfs2_t *lfs, const char *oldpath, const char *newpath);
#endif

// Find info about a file or directory
//
// Fills out the info structure, based on the specified file or directory.
// Returns a negative error code on failure.
int luat_lfs2_stat(luat_lfs2_t *lfs, const char *path, struct luat_lfs2_info *info);

// Get a custom attribute
//
// Custom attributes are uniquely identified by an 8-bit type and limited
// to LFS_ATTR_MAX bytes. When read, if the stored attribute is smaller than
// the buffer, it will be padded with zeros. If the stored attribute is larger,
// then it will be silently truncated. If no attribute is found, the error
// LFS_ERR_NOATTR is returned and the buffer is filled with zeros.
//
// Returns the size of the attribute, or a negative error code on failure.
// Note, the returned size is the size of the attribute on disk, irrespective
// of the size of the buffer. This can be used to dynamically allocate a buffer
// or check for existence.
luat_lfs2_ssize_t luat_lfs2_getattr(luat_lfs2_t *lfs, const char *path,
        uint8_t type, void *buffer, luat_lfs2_size_t size);

#ifndef LFS_READONLY
// Set custom attributes
//
// Custom attributes are uniquely identified by an 8-bit type and limited
// to LFS_ATTR_MAX bytes. If an attribute is not found, it will be
// implicitly created.
//
// Returns a negative error code on failure.
int luat_lfs2_setattr(luat_lfs2_t *lfs, const char *path,
        uint8_t type, const void *buffer, luat_lfs2_size_t size);
#endif

#ifndef LFS_READONLY
// Removes a custom attribute
//
// If an attribute is not found, nothing happens.
//
// Returns a negative error code on failure.
int luat_lfs2_removeattr(luat_lfs2_t *lfs, const char *path, uint8_t type);
#endif


/// File operations ///

#ifndef LFS_NO_MALLOC
// Open a file
//
// The mode that the file is opened in is determined by the flags, which
// are values from the enum luat_lfs2_open_flags that are bitwise-ored together.
//
// Returns a negative error code on failure.
int luat_lfs2_file_open(luat_lfs2_t *lfs, luat_lfs2_file_t *file,
        const char *path, int flags);

// if LFS_NO_MALLOC is defined, luat_lfs2_file_open() will fail with LFS_ERR_NOMEM
// thus use luat_lfs2_file_opencfg() with config.buffer set.
#endif

// Open a file with extra configuration
//
// The mode that the file is opened in is determined by the flags, which
// are values from the enum luat_lfs2_open_flags that are bitwise-ored together.
//
// The config struct provides additional config options per file as described
// above. The config struct must remain allocated while the file is open, and
// the config struct must be zeroed for defaults and backwards compatibility.
//
// Returns a negative error code on failure.
int luat_lfs2_file_opencfg(luat_lfs2_t *lfs, luat_lfs2_file_t *file,
        const char *path, int flags,
        const struct luat_lfs2_file_config *config);

// Close a file
//
// Any pending writes are written out to storage as though
// sync had been called and releases any allocated resources.
//
// Returns a negative error code on failure.
int luat_lfs2_file_close(luat_lfs2_t *lfs, luat_lfs2_file_t *file);

// Synchronize a file on storage
//
// Any pending writes are written out to storage.
// Returns a negative error code on failure.
int luat_lfs2_file_sync(luat_lfs2_t *lfs, luat_lfs2_file_t *file);

// Read data from file
//
// Takes a buffer and size indicating where to store the read data.
// Returns the number of bytes read, or a negative error code on failure.
luat_lfs2_ssize_t luat_lfs2_file_read(luat_lfs2_t *lfs, luat_lfs2_file_t *file,
        void *buffer, luat_lfs2_size_t size);

#ifndef LFS_READONLY
// Write data to file
//
// Takes a buffer and size indicating the data to write. The file will not
// actually be updated on the storage until either sync or close is called.
//
// Returns the number of bytes written, or a negative error code on failure.
luat_lfs2_ssize_t luat_lfs2_file_write(luat_lfs2_t *lfs, luat_lfs2_file_t *file,
        const void *buffer, luat_lfs2_size_t size);
#endif

// Change the position of the file
//
// The change in position is determined by the offset and whence flag.
// Returns the new position of the file, or a negative error code on failure.
luat_lfs2_soff_t luat_lfs2_file_seek(luat_lfs2_t *lfs, luat_lfs2_file_t *file,
        luat_lfs2_soff_t off, int whence);

#ifndef LFS_READONLY
// Truncates the size of the file to the specified size
//
// Returns a negative error code on failure.
int luat_lfs2_file_truncate(luat_lfs2_t *lfs, luat_lfs2_file_t *file, luat_lfs2_off_t size);
#endif

// Return the position of the file
//
// Equivalent to luat_lfs2_file_seek(lfs, file, 0, LFS_SEEK_CUR)
// Returns the position of the file, or a negative error code on failure.
luat_lfs2_soff_t luat_lfs2_file_tell(luat_lfs2_t *lfs, luat_lfs2_file_t *file);

// Change the position of the file to the beginning of the file
//
// Equivalent to luat_lfs2_file_seek(lfs, file, 0, LFS_SEEK_SET)
// Returns a negative error code on failure.
int luat_lfs2_file_rewind(luat_lfs2_t *lfs, luat_lfs2_file_t *file);

// Return the size of the file
//
// Similar to luat_lfs2_file_seek(lfs, file, 0, LFS_SEEK_END)
// Returns the size of the file, or a negative error code on failure.
luat_lfs2_soff_t luat_lfs2_file_size(luat_lfs2_t *lfs, luat_lfs2_file_t *file);


/// Directory operations ///

#ifndef LFS_READONLY
// Create a directory
//
// Returns a negative error code on failure.
int luat_lfs2_mkdir(luat_lfs2_t *lfs, const char *path);
#endif

// Open a directory
//
// Once open a directory can be used with read to iterate over files.
// Returns a negative error code on failure.
int luat_lfs2_dir_open(luat_lfs2_t *lfs, luat_lfs2_dir_t *dir, const char *path);

// Close a directory
//
// Releases any allocated resources.
// Returns a negative error code on failure.
int luat_lfs2_dir_close(luat_lfs2_t *lfs, luat_lfs2_dir_t *dir);

// Read an entry in the directory
//
// Fills out the info structure, based on the specified file or directory.
// Returns a positive value on success, 0 at the end of directory,
// or a negative error code on failure.
int luat_lfs2_dir_read(luat_lfs2_t *lfs, luat_lfs2_dir_t *dir, struct luat_lfs2_info *info);

// Change the position of the directory
//
// The new off must be a value previous returned from tell and specifies
// an absolute offset in the directory seek.
//
// Returns a negative error code on failure.
int luat_lfs2_dir_seek(luat_lfs2_t *lfs, luat_lfs2_dir_t *dir, luat_lfs2_off_t off);

// Return the position of the directory
//
// The returned offset is only meant to be consumed by seek and may not make
// sense, but does indicate the current position in the directory iteration.
//
// Returns the position of the directory, or a negative error code on failure.
luat_lfs2_soff_t luat_lfs2_dir_tell(luat_lfs2_t *lfs, luat_lfs2_dir_t *dir);

// Change the position of the directory to the beginning of the directory
//
// Returns a negative error code on failure.
int luat_lfs2_dir_rewind(luat_lfs2_t *lfs, luat_lfs2_dir_t *dir);


/// Filesystem-level filesystem operations

// Find on-disk info about the filesystem
//
// Fills out the fsinfo structure based on the filesystem found on-disk.
// Returns a negative error code on failure.
int luat_lfs2_fs_stat(luat_lfs2_t *lfs, struct luat_lfs2_fsinfo *fsinfo);

// Finds the current size of the filesystem
//
// Note: Result is best effort. If files share COW structures, the returned
// size may be larger than the filesystem actually is.
//
// Returns the number of allocated blocks, or a negative error code on failure.
luat_lfs2_ssize_t luat_lfs2_fs_size(luat_lfs2_t *lfs);

// Traverse through all blocks in use by the filesystem
//
// The provided callback will be called with each block address that is
// currently in use by the filesystem. This can be used to determine which
// blocks are in use or how much of the storage is available.
//
// Returns a negative error code on failure.
int luat_lfs2_fs_traverse(luat_lfs2_t *lfs, int (*cb)(void*, luat_lfs2_block_t), void *data);

#ifndef LFS_READONLY
void luat_lfs2_preerase_configure(luat_lfs2_t *lfs, uint8_t enabled, uint8_t low_watermark, uint8_t high_watermark);
void luat_lfs2_preerase_get_stats(luat_lfs2_t *lfs, luat_lfs2_preerase_stats_t *out_stats);
int luat_lfs2_preerase_refill(luat_lfs2_t *lfs, uint8_t budget);

// Attempt to make the filesystem consistent and ready for writing
//
// Calling this function is not required, consistency will be implicitly
// enforced on the first operation that writes to the filesystem, but this
// function allows the work to be performed earlier and without other
// filesystem changes.
//
// Returns a negative error code on failure.
int luat_lfs2_fs_mkconsistent(luat_lfs2_t *lfs);
#endif

#ifndef LFS_READONLY
// Attempt any janitorial work
//
// This currently:
// 1. Calls mkconsistent if not already consistent
// 2. Compacts metadata > compact_thresh
// 3. Populates the block allocator
//
// Though additional janitorial work may be added in the future.
//
// Calling this function is not required, but may allow the offloading of
// expensive janitorial work to a less time-critical code path.
//
// Returns a negative error code on failure. Accomplishing nothing is not
// an error.
int luat_lfs2_fs_gc(luat_lfs2_t *lfs);
#endif

#ifndef LFS_READONLY
// Grows the filesystem to a new size, updating the superblock with the new
// block count.
//
// Note: This is irreversible.
//
// Returns a negative error code on failure.
int luat_lfs2_fs_grow(luat_lfs2_t *lfs, luat_lfs2_size_t block_count);
#endif

#ifndef LFS_READONLY
#ifdef LFS_MIGRATE
// Attempts to migrate a previous version of littlefs
//
// Behaves similarly to the luat_lfs2_format function. Attempts to mount
// the previous version of littlefs and update the filesystem so it can be
// mounted with the current version of littlefs.
//
// Requires a littlefs object and config struct. This clobbers the littlefs
// object, and does not leave the filesystem mounted. The config struct must
// be zeroed for defaults and backwards compatibility.
//
// Returns a negative error code on failure.
int luat_lfs2_migrate(luat_lfs2_t *lfs, const struct luat_lfs2_config *cfg);
#endif
#endif


#ifdef __cplusplus
} /* extern "C" */
#endif

#endif
