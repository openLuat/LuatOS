/*
 * tfs_config.h — Compile-time configuration knobs for TFS
 *
 * Override any value by defining it before including this header
 * (e.g. in your build system or in port/tfs_port_cfg.h).
 */

#ifndef TFS_CONFIG_H
#define TFS_CONFIG_H

/*-------------------------------------------------------------------
 *  Device table
 *-------------------------------------------------------------------*/

#ifndef TFS_CFG_MAX_DEVICES
#  define TFS_CFG_MAX_DEVICES   4
#endif

/*-------------------------------------------------------------------
 *  Handle / descriptor table sizes
 *-------------------------------------------------------------------*/

/* Maximum simultaneously open file/dir handles */
#ifndef TFS_CFG_MAX_HANDLES
#  define TFS_CFG_MAX_HANDLES       32
#endif

/* Maximum simultaneously open directory search contexts */
#ifndef TFS_CFG_MAX_DSC
#  define TFS_CFG_MAX_DSC           8
#endif

/*-------------------------------------------------------------------
 *  Write cache
 *-------------------------------------------------------------------*/

/* Number of short-op write cache entries (0 = disabled) */
#ifndef TFS_CFG_N_CACHES
#  define TFS_CFG_N_CACHES          10
#endif

/* Bypass the cache for writes that are chunk-aligned */
#ifndef TFS_CFG_CACHE_BYPASS_ALIGNED
#  define TFS_CFG_CACHE_BYPASS_ALIGNED 0
#endif

/*-------------------------------------------------------------------
 *  Block reservation
 *-------------------------------------------------------------------*/

/* Blocks reserved for GC headroom (not available for user data) */
#ifndef TFS_CFG_RESERVED_BLOCKS
#  define TFS_CFG_RESERVED_BLOCKS   5
#endif

/*-------------------------------------------------------------------
 *  ECC
 *-------------------------------------------------------------------*/

/* 0 = use software Hamming ECC; 1 = trust hardware ECC from driver */
#ifndef TFS_CFG_HW_ECC
#  define TFS_CFG_HW_ECC            0
#endif

/* 0 = add ECC to packed tags2; 1 = no ECC on tags (trust HW) */
#ifndef TFS_CFG_NO_TAGS_ECC
#  define TFS_CFG_NO_TAGS_ECC       0
#endif

/*-------------------------------------------------------------------
 *  Fast mount features
 *-------------------------------------------------------------------*/

/* Enable checkpoint write on unmount / sync */
#ifndef TFS_CFG_CHECKPOINT
#  define TFS_CFG_CHECKPOINT        1
#endif

/* Enable per-block summary chunk for fast scan */
#ifndef TFS_CFG_SUMMARY
#  define TFS_CFG_SUMMARY           1
#endif

/*-------------------------------------------------------------------
 *  Name limits
 *-------------------------------------------------------------------*/

#ifndef TFS_MAX_NAME_LEN
#  define TFS_MAX_NAME_LEN          255
#endif

/* Short names cached in RAM to avoid header reads */
#ifndef TFS_SHORT_NAME_LEN
#  define TFS_SHORT_NAME_LEN        15
#endif

#ifndef TFS_MAX_ALIAS_LEN
#  define TFS_MAX_ALIAS_LEN         159
#endif

/*-------------------------------------------------------------------
 *  Path / symlink
 *-------------------------------------------------------------------*/

#ifndef TFS_MAX_PATH_LEN
#  define TFS_MAX_PATH_LEN 512
#endif

#ifndef TFS_MAX_SYMLINK_DEPTH
#  define TFS_MAX_SYMLINK_DEPTH     5
#endif

/*-------------------------------------------------------------------
 *  Object table
 *-------------------------------------------------------------------*/

/* Must be power of 2 */
#ifndef TFS_OBJ_BUCKETS
#  define TFS_OBJ_BUCKETS           256
#endif

#ifndef TFS_MAX_OBJ_ID
#  define TFS_MAX_OBJ_ID            0x3ffffu
#endif

/*-------------------------------------------------------------------
 *  Sequence numbers
 *-------------------------------------------------------------------*/

#define TFS_LOWEST_SEQ_NUMBER       0x00001000u
#define TFS_HIGHEST_SEQ_NUMBER      0xefffff00u
#define TFS_SEQ_BAD_BLOCK           0xffff0000u

/*-------------------------------------------------------------------
 *  GC thresholds
 *-------------------------------------------------------------------*/

#define TFS_GC_PASSIVE_THRESHOLD    4   /* start passive GC below this */
#define TFS_GC_GOOD_ENOUGH          2   /* stop passive GC above this */

/*-------------------------------------------------------------------
 *  Write attempt limit
 *-------------------------------------------------------------------*/

#define TFS_WR_ATTEMPTS             (5 * 64)

/*-------------------------------------------------------------------
 *  Well-known object IDs
 *-------------------------------------------------------------------*/

#define TFS_OBJ_ID_ROOT         1u
#define TFS_OBJ_ID_LOSTNFOUND   2u
#define TFS_OBJ_ID_UNLINKED     3u
#define TFS_OBJ_ID_DEL          4u
#define TFS_OBJ_ID_SUMMARY      0x10u
#define TFS_OBJ_ID_CHECKPT      0x20u
#define TFS_OBJ_ID_FIRST_USER   0x100u

/* Legacy aliases */
#define TFS_OBJID_ROOT            TFS_OBJ_ID_ROOT
#define TFS_OBJID_LOSTNFOUND      TFS_OBJ_ID_LOSTNFOUND
#define TFS_OBJID_UNLINKED        TFS_OBJ_ID_UNLINKED
#define TFS_OBJID_DELETED         TFS_OBJ_ID_DEL
#define TFS_OBJID_SUMMARY         TFS_OBJ_ID_SUMMARY
#define TFS_OBJID_CHECKPOINT_DATA TFS_OBJ_ID_CHECKPT

/* Starting sequence number */
#define TFS_SEQ_LOWEST  TFS_LOWEST_SEQ_NUMBER

/*-------------------------------------------------------------------
 *  xattr (extended attributes) — disabled by default
 *-------------------------------------------------------------------*/

#ifndef TFS_CFG_XATTR
#  define TFS_CFG_XATTR             0
#endif

/*-------------------------------------------------------------------
 *  Trace / debug verbosity bitmask
 *-------------------------------------------------------------------*/

#define TFS_TRACE_ERROR             0x00000001u
#define TFS_TRACE_OS                0x00000002u
#define TFS_TRACE_NANDACCESS        0x00000004u
#define TFS_TRACE_GC                0x00000008u
#define TFS_TRACE_SCAN              0x00000010u
#define TFS_TRACE_CHECKPOINT        0x00000020u
#define TFS_TRACE_ALWAYS            0x80000000u

#ifndef TFS_CFG_TRACE_MASK
#  define TFS_CFG_TRACE_MASK        0u
#endif

/*-------------------------------------------------------------------
 *  Temporary buffers per device
 *-------------------------------------------------------------------*/
#define TFS_N_TEMP_BUFFERS          6

/*-------------------------------------------------------------------
 *  Checkpoint version stamp
 *-------------------------------------------------------------------*/
#define TFS_CHECKPOINT_VERSION      4

/*-------------------------------------------------------------------
 *  Summary version stamp
 *-------------------------------------------------------------------*/
#define TFS_SUMMARY_VERSION         1

#endif /* TFS_CONFIG_H */
