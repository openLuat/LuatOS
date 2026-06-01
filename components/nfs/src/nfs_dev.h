/*
 * nfs_dev.h — Internal device structure for NFS (not part of public API)
 *
 * nfs_dev_t aggregates everything needed to manage one NAND device:
 *   - geometry, driver callbacks
 *   - block info array and chunk bitmap
 *   - object hash table (in-RAM inode cache)
 *   - GC state, checkpoint state, cache state
 *   - statistics
 */

#ifndef NFS_DEV_H
#define NFS_DEV_H

#include "../inc/nfs_types.h"
#include "../inc/nfs_config.h"
#include "../inc/nfs_port.h"
#include "nfs_list.h"

/*===================================================================
 *  Forward declarations
 *===================================================================*/

struct nfs_obj;
struct nfs_tnode;
struct nfs_cache_entry;
struct nfs_checkpt_dev;
typedef struct nfs_summary_tags nfs_summary_tags_t;

/*===================================================================
 *  Block info (per erase block, stored in RAM)
 *===================================================================*/

typedef union {
    struct {
        nfs_s32 pages_in_use    : 10;
        nfs_s32 soft_del_pages  : 10;
        nfs_u32 block_state     :  4;  /* nfs_block_state_t */
        nfs_u32 needs_retiring  :  1;
        nfs_u32 gc_prioritise   :  1;
        nfs_u32 has_summary     :  1;
        nfs_u32 has_shrink_hdr  :  1;
        nfs_u32 skip_erased_chk :  1;
        nfs_u32 ecc_strikes     :  3;
        nfs_u32 seq_number;            /* Block sequence number */
    } bi;
    nfs_u32 as_u32[2];
} nfs_block_info_t;

/*===================================================================
 *  Extended chunk tags (used in RAM; packed for NAND storage)
 *===================================================================*/

typedef struct {
    nfs_u32        chunk_used     : 1;
    nfs_u32        block_bad      : 1;
    nfs_u32        is_deleted     : 1;

    nfs_u32        obj_id;
    nfs_u32        chunk_id;
    nfs_u32        n_bytes;
    nfs_u32        seq_number;

    nfs_ecc_result_t ecc_result;

    /* Extra info packed into object-header tags */
    nfs_u32        extra_available  : 1;
    nfs_u32        extra_is_shrink  : 1;
    nfs_u32        extra_shadows    : 1;
    nfs_u32        extra_parent_id;
    nfs_obj_type_t extra_obj_type;
    nfs_off_t      extra_file_size;
    nfs_u32        extra_equiv_id;
} nfs_ext_tags_t;

/*===================================================================
 *  Object header (on-NAND layout)
 *===================================================================*/

typedef struct {
    nfs_u32 type;                          /* nfs_obj_type_t */
    nfs_u32 parent_obj_id;
    nfs_u16 sum_no_longer_used;
    char    name[NFS_MAX_NAME_LEN + 1];

    nfs_u32 mode;
    nfs_u32 uid;
    nfs_u32 gid;
    nfs_u32 atime;
    nfs_u32 mtime;
    nfs_u32 ctime;

    nfs_u32 file_size_low;
    nfs_s32 equiv_id;
    char    alias[NFS_MAX_ALIAS_LEN + 1];
    nfs_u32 rdev;

    nfs_u32 file_size_high;
    nfs_u32 reserved[1];
    nfs_s32 shadows_obj;
    nfs_u32 is_shrink;
} nfs_obj_hdr_t;

/*===================================================================
 *  Tnode — chunk-index tree node
 *===================================================================*/

#define NFS_TNODES_LEVEL0        16
#define NFS_TNODES_LEVEL0_BITS    4
#define NFS_TNODES_INTERNAL      (NFS_TNODES_LEVEL0 / 2)
#define NFS_TNODES_INTERNAL_BITS (NFS_TNODES_LEVEL0_BITS - 1)
#define NFS_TNODES_MAX_LEVEL      8

typedef struct nfs_tnode {
    struct nfs_tnode *internal[NFS_TNODES_INTERNAL];
} nfs_tnode_t;

/*===================================================================
 *  In-RAM object (inode)
 *===================================================================*/

typedef struct nfs_obj {
    /* Status flags */
    nfs_u8 deleted       : 1;
    nfs_u8 soft_del      : 1;
    nfs_u8 unlinked      : 1;
    nfs_u8 fake          : 1;
    nfs_u8 rename_allowed: 1;
    nfs_u8 unlink_allowed: 1;
    nfs_u8 dirty         : 1;
    nfs_u8 valid         : 1;
    nfs_u8 lazy_loaded   : 1;
    nfs_u8 defered_free  : 1;
    nfs_u8 being_created : 1;
    nfs_u8 is_shadowed   : 1;

    nfs_u8  serial;
    nfs_u16 sum;               /* Name hash for fast search */

    struct nfs_dev *my_dev;
    nfs_list_t      hash_link;
    nfs_list_t      hard_links;

    struct nfs_obj *parent;
    nfs_list_t      siblings;

    int      hdr_chunk;        /* Where is the header on NAND? */
    int      n_data_chunks;
    nfs_u32  obj_id;
    nfs_u32  mode;
    nfs_u32  uid, gid;
    nfs_u32  atime, mtime, ctime;
    nfs_u32  rdev;

    char short_name[NFS_SHORT_NAME_LEN + 1];

    nfs_u32 obj_type;          /* nfs_obj_type_t */

    union {
        struct {
            nfs_off_t    file_size;
            nfs_off_t    stored_size;
            nfs_off_t    shrink_size;
            int          top_level;
            nfs_tnode_t *top;
        } file;

        struct {
            nfs_list_t children;
            nfs_list_t dirty;
        } dir;

        struct {
            char *alias;
        } symlink;

        struct {
            struct nfs_obj *equiv_obj;
            nfs_u32         equiv_id;
        } hardlink;
    } var;
} nfs_obj_t;

/*===================================================================
 *  Object bucket (hash table slot)
 *===================================================================*/

typedef struct {
    nfs_list_t list;
    int        count;
} nfs_obj_bucket_t;

/*===================================================================
 *  Temporary chunk-sized buffer
 *===================================================================*/

typedef struct {
    nfs_u8 *buffer;
    int     in_use;
} nfs_buffer_t;

/*===================================================================
 *  Write cache entry
 *===================================================================*/

typedef struct nfs_cache_entry {
    nfs_obj_t *object;
    int        chunk_id;
    int        last_use;
    int        dirty;
    int        n_bytes;
    int        locked;
    nfs_u8    *data;
} nfs_cache_entry_t;

typedef struct {
    nfs_cache_entry_t *cache;
    int                n_caches;
    int                cache_last_use;
} nfs_cache_mgr_t;

/*===================================================================
 *  Device parameters (set by caller before nfs_add_device)
 *===================================================================*/

typedef struct {
    const char *name;
    nfs_geo_t   geo;

    int     inband_tags;
    int     use_nand_ecc;
    int     no_tags_ecc;
    int     is_yaffs2;               /* always 1 for NFS */
    int     empty_lost_n_found;
    int     refresh_period;
    int     enable_xattr;
    int     max_objects;
    int     hide_lost_n_found;
    int     stored_endian;

    nfs_u8  skip_checkpt_rd;
    nfs_u8  skip_checkpt_wr;

    /* Callbacks */
    void (*remove_obj_fn)(nfs_obj_t *obj);
    void (*sb_dirty_fn)  (struct nfs_dev *dev);
    unsigned (*gc_control_fn)(struct nfs_dev *dev);

    /* Debug flags */
    int use_header_file_size;
    int disable_lazy_load;
    int wide_tnodes_disabled;
    int defered_dir_update;
    int always_check_erased;
    int disable_summary;
    int disable_bad_block_marking;
} nfs_param_t;

/*===================================================================
 *  Main device structure
 *===================================================================*/

typedef struct nfs_dev {
    nfs_param_t  param;
    nfs_drv_t    drv;

    nfs_list_t   dev_list;

    int is_mounted;
    int read_only;
    int is_checkpointed;
    int swap_endian;

    /* Runtime geometry (derived from param.geo) */
    nfs_u32 data_bytes_per_chunk;
    nfs_u32 chunk_shift;     /* for power-of-2 chunk sizes */
    nfs_u32 chunk_div;
    nfs_u32 chunk_mask;
    nfs_u16 chunk_grp_bits;
    nfs_u16 chunk_grp_size;

    /* Tnode width */
    nfs_u32 tnode_width;
    nfs_u32 tnode_mask;
    nfs_u32 tnode_size;

    /* Block / chunk offset (to allow start_block != 0) */
    nfs_u32 internal_start_block;
    nfs_u32 internal_end_block;
    int     block_offset;
    int     chunk_offset;

    /* Block info array (one entry per block) */
    nfs_block_info_t *block_info;
    nfs_u8           *chunk_bits;       /* bitmap: chunk in use */
    int               chunk_bit_stride; /* bytes per block in chunk_bits */

    int     n_erased_blocks;
    int     alloc_block;
    nfs_u32 alloc_page;
    int     alloc_block_finder;

    /* Object / tnode allocator context */
    void *allocator;
    int   n_obj;
    int   n_tnodes;
    int   n_hardlinks;

    nfs_obj_bucket_t obj_bucket[NFS_OBJ_BUCKETS];
    nfs_u32          bucket_finder;

    int n_free_chunks;

    /* GC state */
    nfs_u32 *gc_cleanup_list;
    nfs_u32  n_clean_ups;

    unsigned has_pending_prioritised_gc;
    unsigned gc_disable;
    unsigned gc_block_finder;
    unsigned gc_dirtiest;
    unsigned gc_pages_in_use;
    unsigned gc_not_done;
    unsigned gc_block;
    unsigned gc_chunk;
    unsigned gc_skip;
    nfs_summary_tags_t *gc_sum_tags;

    /* Special pseudo-objects */
    nfs_obj_t *root_dir;
    nfs_obj_t *lost_n_found;
    nfs_obj_t *unlinked_dir;
    nfs_obj_t *del_dir;
    nfs_obj_t *unlinked_deletion;

    int n_deleted_files;
    int n_unlinked_files;
    int n_bg_deletions;

    /* Cache */
    nfs_cache_mgr_t cache_mgr;

    /* Temp buffers (chunk-sized) */
    nfs_buffer_t temp_buffer[NFS_N_TEMP_BUFFERS];
    int max_temp;
    int temp_in_use;

    /* YAFFS2 sequence number */
    nfs_u32  seq_number;
    nfs_u32  oldest_dirty_seq;
    nfs_u32  oldest_dirty_block;

    /* Block refresh */
    int refresh_skip;

    /* Dirty directories list */
    nfs_list_t dirty_dirs;

    /* Summary */
    int chunks_per_summary;
    nfs_summary_tags_t *sum_tags;

    /* Checkpoint state */
    int     checkpt_page_seq;
    int     checkpt_byte_count;
    int     checkpt_byte_offs;
    nfs_u8 *checkpt_buffer;
    int     checkpt_open_write;
    nfs_u32 blocks_in_checkpt;
    int     checkpt_cur_chunk;
    int     checkpt_cur_block;
    int     checkpt_next_block;
    int    *checkpt_block_list;
    nfs_u32 checkpt_max_blocks;
    nfs_u32 checkpt_sum;
    nfs_u32 checkpt_xor;
    int     checkpoint_blocks_required;

    nfs_tnode_t *tn_swap_buffer;

    /* Staging buffer for inband-tags read/write (physical page size) */
    nfs_u8 *inband_buf;

    /* Statistics */
    nfs_u32 n_page_writes;
    nfs_u32 n_page_reads;
    nfs_u32 n_erasures;
    nfs_u32 n_erase_failures;
    nfs_u32 n_ecc_fixed;
    nfs_u32 n_ecc_unfixed;
    nfs_u32 n_tags_ecc_fixed;
    nfs_u32 n_tags_ecc_unfixed;
    nfs_u32 n_gc_copies;
    nfs_u32 n_gc_blocks;
    nfs_u32 n_retried_writes;
    nfs_u32 n_retired_blocks;
    nfs_u32 n_obj_created;
    nfs_u32 n_obj_deleted;
} nfs_dev_t;

/*===================================================================
 *  Convenience accessor macros
 *===================================================================*/

#define nfs_get_block_info(dev, blk) \
    (&(dev)->block_info[(blk) - (dev)->block_offset])

#define nfs_chunks_per_block(dev) \
    ((dev)->param.geo.chunks_per_block)

#define nfs_total_blocks(dev) \
    ((dev)->internal_end_block - (dev)->internal_start_block + 1)

#endif /* NFS_DEV_H */
