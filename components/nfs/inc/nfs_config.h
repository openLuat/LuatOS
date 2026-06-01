/*
 * nfs_config.h — Compile-time configuration knobs for NFS
 *
 * Override any value by defining it before including this header
 * (e.g. in your build system or in port/nfs_port_cfg.h).
 */

#ifndef NFS_CONFIG_H
#define NFS_CONFIG_H

/*-------------------------------------------------------------------
 *  Device table
 *-------------------------------------------------------------------*/

#ifndef NFS_CFG_MAX_DEVICES
#  define NFS_CFG_MAX_DEVICES   4
#endif

/*-------------------------------------------------------------------
 *  Handle / descriptor table sizes
 *-------------------------------------------------------------------*/

/* Maximum simultaneously open file/dir handles */
#ifndef NFS_CFG_MAX_HANDLES
#  define NFS_CFG_MAX_HANDLES       32
#endif

/* Maximum simultaneously open directory search contexts */
#ifndef NFS_CFG_MAX_DSC
#  define NFS_CFG_MAX_DSC           8
#endif

/*-------------------------------------------------------------------
 *  Write cache
 *-------------------------------------------------------------------*/

/* Number of short-op write cache entries (0 = disabled) */
#ifndef NFS_CFG_N_CACHES
#  define NFS_CFG_N_CACHES          10
#endif

/* Bypass the cache for writes that are chunk-aligned */
#ifndef NFS_CFG_CACHE_BYPASS_ALIGNED
#  define NFS_CFG_CACHE_BYPASS_ALIGNED 0
#endif

/*-------------------------------------------------------------------
 *  Block reservation
 *-------------------------------------------------------------------*/

/* Blocks reserved for GC headroom (not available for user data) */
#ifndef NFS_CFG_RESERVED_BLOCKS
#  define NFS_CFG_RESERVED_BLOCKS   5
#endif

/*-------------------------------------------------------------------
 *  ECC
 *-------------------------------------------------------------------*/

/* 0 = use software Hamming ECC; 1 = trust hardware ECC from driver */
#ifndef NFS_CFG_HW_ECC
#  define NFS_CFG_HW_ECC            0
#endif

/* 0 = add ECC to packed tags2; 1 = no ECC on tags (trust HW) */
#ifndef NFS_CFG_NO_TAGS_ECC
#  define NFS_CFG_NO_TAGS_ECC       0
#endif

/*-------------------------------------------------------------------
 *  Fast mount features
 *-------------------------------------------------------------------*/

/* Enable checkpoint write on unmount / sync */
#ifndef NFS_CFG_CHECKPOINT
#  define NFS_CFG_CHECKPOINT        1
#endif

/* Enable per-block summary chunk for fast scan */
#ifndef NFS_CFG_SUMMARY
#  define NFS_CFG_SUMMARY           1
#endif

/*-------------------------------------------------------------------
 *  Name limits
 *-------------------------------------------------------------------*/

#ifndef NFS_MAX_NAME_LEN
#  define NFS_MAX_NAME_LEN          255
#endif

/* Short names cached in RAM to avoid header reads */
#ifndef NFS_SHORT_NAME_LEN
#  define NFS_SHORT_NAME_LEN        15
#endif

#ifndef NFS_MAX_ALIAS_LEN
#  define NFS_MAX_ALIAS_LEN         159
#endif

/*-------------------------------------------------------------------
 *  Path / symlink
 *-------------------------------------------------------------------*/

#ifndef NFS_MAX_PATH_LEN
#  define NFS_MAX_PATH_LEN 512
#endif

#ifndef NFS_MAX_SYMLINK_DEPTH
#  define NFS_MAX_SYMLINK_DEPTH     5
#endif

/*-------------------------------------------------------------------
 *  Object table
 *-------------------------------------------------------------------*/

/* Must be power of 2 */
#ifndef NFS_OBJ_BUCKETS
#  define NFS_OBJ_BUCKETS           256
#endif

#ifndef NFS_MAX_OBJ_ID
#  define NFS_MAX_OBJ_ID            0x3ffffu
#endif

/*-------------------------------------------------------------------
 *  Sequence numbers
 *-------------------------------------------------------------------*/

#define NFS_LOWEST_SEQ_NUMBER       0x00001000u
#define NFS_HIGHEST_SEQ_NUMBER      0xefffff00u
#define NFS_SEQ_BAD_BLOCK           0xffff0000u

/*-------------------------------------------------------------------
 *  GC thresholds
 *-------------------------------------------------------------------*/

#define NFS_GC_PASSIVE_THRESHOLD    4   /* start passive GC below this */
#define NFS_GC_GOOD_ENOUGH          2   /* stop passive GC above this */

/*-------------------------------------------------------------------
 *  Write attempt limit
 *-------------------------------------------------------------------*/

#define NFS_WR_ATTEMPTS             (5 * 64)

/*-------------------------------------------------------------------
 *  Well-known object IDs
 *-------------------------------------------------------------------*/

#define NFS_OBJ_ID_ROOT         1u
#define NFS_OBJ_ID_LOSTNFOUND   2u
#define NFS_OBJ_ID_UNLINKED     3u
#define NFS_OBJ_ID_DEL          4u
#define NFS_OBJ_ID_SUMMARY      0x10u
#define NFS_OBJ_ID_CHECKPT      0x20u
#define NFS_OBJ_ID_FIRST_USER   0x100u

/* Legacy aliases */
#define NFS_OBJID_ROOT            NFS_OBJ_ID_ROOT
#define NFS_OBJID_LOSTNFOUND      NFS_OBJ_ID_LOSTNFOUND
#define NFS_OBJID_UNLINKED        NFS_OBJ_ID_UNLINKED
#define NFS_OBJID_DELETED         NFS_OBJ_ID_DEL
#define NFS_OBJID_SUMMARY         NFS_OBJ_ID_SUMMARY
#define NFS_OBJID_CHECKPOINT_DATA NFS_OBJ_ID_CHECKPT

/* Starting sequence number */
#define NFS_SEQ_LOWEST  NFS_LOWEST_SEQ_NUMBER

/*-------------------------------------------------------------------
 *  xattr (extended attributes) — disabled by default
 *-------------------------------------------------------------------*/

#ifndef NFS_CFG_XATTR
#  define NFS_CFG_XATTR             0
#endif

/*-------------------------------------------------------------------
 *  Trace / debug verbosity bitmask
 *-------------------------------------------------------------------*/

#define NFS_TRACE_ERROR             0x00000001u
#define NFS_TRACE_OS                0x00000002u
#define NFS_TRACE_NANDACCESS        0x00000004u
#define NFS_TRACE_GC                0x00000008u
#define NFS_TRACE_SCAN              0x00000010u
#define NFS_TRACE_CHECKPOINT        0x00000020u
#define NFS_TRACE_ALWAYS            0x80000000u

#ifndef NFS_CFG_TRACE_MASK
#  define NFS_CFG_TRACE_MASK        0u
#endif

/*-------------------------------------------------------------------
 *  Temporary buffers per device
 *-------------------------------------------------------------------*/
#define NFS_N_TEMP_BUFFERS          6

/*-------------------------------------------------------------------
 *  Checkpoint version stamp
 *-------------------------------------------------------------------*/
#define NFS_CHECKPOINT_VERSION      4

/*-------------------------------------------------------------------
 *  Summary version stamp
 *-------------------------------------------------------------------*/
#define NFS_SUMMARY_VERSION         1

#endif /* NFS_CONFIG_H */
