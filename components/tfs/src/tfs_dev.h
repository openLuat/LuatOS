/*
 * tfs_dev.h — Internal device structure for TFS (not part of public API)
 *
 * tfs_dev_t aggregates everything needed to manage one NAND device:
 *   - geometry, driver callbacks
 *   - block info array and chunk bitmap
 *   - object hash table (in-RAM inode cache)
 *   - GC state, checkpoint state, cache state
 *   - statistics
 */

#ifndef TFS_DEV_H
#define TFS_DEV_H

#include "../inc/tfs_types.h"
#include "../inc/tfs_config.h"
#include "../inc/tfs_port.h"
#include "tfs_list.h"

/*===================================================================
 *  Forward declarations
 *===================================================================*/

struct tfs_obj;
struct tfs_tnode;
struct tfs_cache_entry;
struct tfs_checkpt_dev;
typedef struct tfs_summary_tags tfs_summary_tags_t;

/*===================================================================
 *  Block info (per erase block, stored in RAM)
 *===================================================================*/

typedef union {
    struct {
        int32_t pages_in_use    : 10;
        int32_t soft_del_pages  : 10;
        uint32_t block_state     :  4;  /* tfs_block_state_t */
        uint32_t needs_retiring  :  1;
        uint32_t gc_prioritise   :  1;
        uint32_t has_summary     :  1;
        uint32_t has_shrink_hdr  :  1;
        uint32_t skip_erased_chk :  1;
        uint32_t ecc_strikes     :  3;
        uint32_t seq_number;            /* Block sequence number */
    } bi;
    uint32_t as_u32[2];
} tfs_block_info_t;

/*===================================================================
 *  Extended chunk tags (used in RAM; packed for NAND storage)
 *===================================================================*/

typedef struct {
    uint32_t        chunk_used     : 1;
    uint32_t        block_bad      : 1;
    uint32_t        is_deleted     : 1;

    uint32_t        obj_id;
    uint32_t        chunk_id;
    uint32_t        n_bytes;
    uint32_t        seq_number;

    tfs_ecc_result_t ecc_result;

    /* Extra info packed into object-header tags */
    uint32_t        extra_available  : 1;
    uint32_t        extra_is_shrink  : 1;
    uint32_t        extra_shadows    : 1;
    uint32_t        extra_parent_id;
    tfs_obj_type_t extra_obj_type;
    tfs_off_t      extra_file_size;
    uint32_t        extra_equiv_id;
} tfs_ext_tags_t;

/*===================================================================
 *  Object header (on-NAND layout)
 *===================================================================*/

typedef struct {
    uint32_t type;                          /* tfs_obj_type_t */
    uint32_t parent_obj_id;
    uint16_t sum_no_longer_used;
    char    name[TFS_MAX_NAME_LEN + 1];

    uint32_t mode;
    uint32_t uid;
    uint32_t gid;
    uint32_t atime;
    uint32_t mtime;
    uint32_t ctime;

    uint32_t file_size_low;
    int32_t equiv_id;
    char    alias[TFS_MAX_ALIAS_LEN + 1];
    uint32_t rdev;

    uint32_t file_size_high;
    uint32_t reserved[1];
    int32_t shadows_obj;
    uint32_t is_shrink;
} tfs_obj_hdr_t;

/*===================================================================
 *  Tnode — chunk-index tree node
 *===================================================================*/

#define TFS_TNODES_LEVEL0        16
#define TFS_TNODES_LEVEL0_BITS    4
#define TFS_TNODES_INTERNAL      (TFS_TNODES_LEVEL0 / 2)
#define TFS_TNODES_INTERNAL_BITS (TFS_TNODES_LEVEL0_BITS - 1)
#define TFS_TNODES_MAX_LEVEL      8

typedef struct tfs_tnode {
    struct tfs_tnode *internal[TFS_TNODES_INTERNAL];
} tfs_tnode_t;

/*===================================================================
 *  In-RAM object (inode)
 *===================================================================*/

typedef struct tfs_obj {
    /* Status flags */
    uint8_t deleted       : 1;
    uint8_t soft_del      : 1;
    uint8_t unlinked      : 1;
    uint8_t fake          : 1;
    uint8_t rename_allowed: 1;
    uint8_t unlink_allowed: 1;
    uint8_t dirty         : 1;
    uint8_t valid         : 1;
    uint8_t lazy_loaded   : 1;
    uint8_t defered_free  : 1;
    uint8_t being_created : 1;
    uint8_t is_shadowed   : 1;

    uint8_t  serial;
    uint16_t sum;               /* Name hash for fast search */

    struct tfs_dev *my_dev;
    tfs_list_t      hash_link;
    tfs_list_t      hard_links;
    uint16_t         n_hard_links;  /* ref count: hardlinks pointing to this file */

    struct tfs_obj *parent;
    tfs_list_t      siblings;

    int      hdr_chunk;        /* Where is the header on NAND? */
    int      n_data_chunks;
    uint32_t  obj_id;
    uint32_t  mode;
    uint32_t  uid, gid;
    uint32_t  atime, mtime, ctime;
    uint32_t  rdev;

    char short_name[TFS_SHORT_NAME_LEN + 1];
    char *full_name;

    uint32_t obj_type;          /* tfs_obj_type_t */

    union {
        struct {
            tfs_off_t    file_size;
            tfs_off_t    stored_size;
            tfs_off_t    shrink_size;
            int          top_level;
            tfs_tnode_t *top;
        } file;

        struct {
            tfs_list_t children;
            tfs_list_t dirty;
        } dir;

        struct {
            char *alias;
        } symlink;

        struct {
            struct tfs_obj *equiv_obj;
            uint32_t         equiv_id;
        } hardlink;
    } var;
} tfs_obj_t;

/*===================================================================
 *  Object bucket (hash table slot)
 *===================================================================*/

typedef struct {
    tfs_list_t list;
    int        count;
} tfs_obj_bucket_t;

/*===================================================================
 *  Temporary chunk-sized buffer
 *===================================================================*/

typedef struct {
    uint8_t *buffer;
    int     in_use;
} tfs_buffer_t;

/*===================================================================
 *  Write cache entry
 *===================================================================*/

typedef struct tfs_cache_entry {
    tfs_obj_t *object;
    int        chunk_id;
    int        last_use;
    int        dirty;
    int        n_bytes;
    int        locked;
    uint8_t    *data;
} tfs_cache_entry_t;

typedef struct {
    tfs_cache_entry_t *cache;
    int                n_caches;
    int                cache_last_use;
} tfs_cache_mgr_t;

/*===================================================================
 *  Device parameters (set by caller before tfs_add_device)
 *===================================================================*/

typedef struct {
    const char *name;
    tfs_geo_t   geo;

    int     inband_tags;
    int     use_nand_ecc;
    int     no_tags_ecc;
    int     is_yaffs2;               /* always 1 for TFS */
    int     empty_lost_n_found;
    int     refresh_period;
    int     enable_xattr;
    int     max_objects;
    int     hide_lost_n_found;
    int     stored_endian;

    uint8_t  skip_checkpt_rd;
    uint8_t  skip_checkpt_wr;

    /* Callbacks */
    void (*remove_obj_fn)(tfs_obj_t *obj);
    void (*sb_dirty_fn)  (struct tfs_dev *dev);
    unsigned (*gc_control_fn)(struct tfs_dev *dev);

    /* Debug flags */
    int use_header_file_size;
    int disable_lazy_load;
    int wide_tnodes_disabled;
    int defered_dir_update;
    int always_check_erased;
    int disable_summary;
    int disable_bad_block_marking;
} tfs_param_t;

/*===================================================================
 *  Main device structure
 *===================================================================*/

typedef struct tfs_dev {
    tfs_param_t  param;
    tfs_drv_t    drv;

    tfs_list_t   dev_list;

    int is_mounted;
    int read_only;
    int is_checkpointed;
    int checkpt_has_tnodes;
    int swap_endian;

    /* Runtime geometry (derived from param.geo) */
    uint32_t data_bytes_per_chunk;
    uint32_t chunk_shift;     /* for power-of-2 chunk sizes */
    uint32_t chunk_div;
    uint32_t chunk_mask;
    uint16_t chunk_grp_bits;
    uint16_t chunk_grp_size;

    /* Tnode width */
    uint32_t tnode_width;
    uint32_t tnode_mask;
    uint32_t tnode_size;

    /* Block / chunk offset (to allow start_block != 0) */
    uint32_t internal_start_block;
    uint32_t internal_end_block;
    int     block_offset;
    int     chunk_offset;

    /* Block info array (one entry per block) */
    tfs_block_info_t *block_info;
    uint8_t           *chunk_bits;       /* bitmap: chunk in use */
    int               chunk_bit_stride; /* bytes per block in chunk_bits */

    int     n_erased_blocks;
    int     alloc_block;
    uint32_t alloc_page;
    int     alloc_block_finder;

    /* Object / tnode allocator context */
    void *allocator;
    int   n_obj;
    int   n_tnodes;
    int   n_hardlinks;

    tfs_obj_bucket_t obj_bucket[TFS_OBJ_BUCKETS];
    uint32_t          bucket_finder;

    int n_free_chunks;

    /* GC state */
    uint32_t *gc_cleanup_list;
    uint32_t  n_clean_ups;

    unsigned has_pending_prioritised_gc;
    unsigned gc_disable;
    unsigned gc_block_finder;
    unsigned gc_dirtiest;
    unsigned gc_pages_in_use;
    unsigned gc_not_done;
    unsigned gc_block;
    unsigned gc_chunk;
    unsigned gc_skip;
    tfs_summary_tags_t *gc_sum_tags;

    /* Special pseudo-objects */
    tfs_obj_t *root_dir;
    tfs_obj_t *lost_n_found;
    tfs_obj_t *unlinked_dir;
    tfs_obj_t *del_dir;
    tfs_obj_t *unlinked_deletion;

    int n_deleted_files;
    int n_unlinked_files;
    int n_bg_deletions;

    /* Cache */
    tfs_cache_mgr_t cache_mgr;

    /* Temp buffers (chunk-sized) */
    tfs_buffer_t temp_buffer[TFS_N_TEMP_BUFFERS];
    int max_temp;
    int temp_in_use;

    /* YAFFS2 sequence number */
    uint32_t  seq_number;
    uint32_t  oldest_dirty_seq;
    uint32_t  oldest_dirty_block;

    /* Block refresh */
    int refresh_skip;

    /* Dirty directories list */
    tfs_list_t dirty_dirs;

    /* Summary */
    int chunks_per_summary;
    tfs_summary_tags_t *sum_tags;

    /* Checkpoint state */
    int     checkpt_page_seq;
    int     checkpt_byte_count;
    int     checkpt_byte_offs;
    uint8_t *checkpt_buffer;
    int     checkpt_open_write;
    uint32_t blocks_in_checkpt;
    int     checkpt_cur_chunk;
    int     checkpt_cur_block;
    int     checkpt_next_block;
    int    *checkpt_block_list;
    uint32_t checkpt_max_blocks;
    uint32_t checkpt_sum;
    uint32_t checkpt_xor;
    int     checkpoint_blocks_required;

    tfs_tnode_t *tn_swap_buffer;

    /* Staging buffer for inband-tags read/write (physical page size) */
    uint8_t *inband_buf;

    /* Statistics */
    uint32_t n_page_writes;
    uint32_t n_page_reads;
    uint32_t n_erasures;
    uint32_t n_erase_failures;
    uint32_t n_ecc_fixed;
    uint32_t n_ecc_unfixed;
    uint32_t n_tags_ecc_fixed;
    uint32_t n_tags_ecc_unfixed;
    uint32_t n_gc_copies;
    uint32_t n_gc_blocks;
    uint32_t n_retried_writes;
    uint32_t n_retired_blocks;
    uint32_t n_obj_created;
    uint32_t n_obj_deleted;
} tfs_dev_t;

/*===================================================================
 *  Convenience accessor macros
 *===================================================================*/

#define tfs_get_block_info(dev, blk) \
    (&(dev)->block_info[(blk) - (dev)->block_offset])

#define tfs_chunks_per_block(dev) \
    ((dev)->param.geo.chunks_per_block)

#define tfs_total_blocks(dev) \
    ((dev)->internal_end_block - (dev)->internal_start_block + 1)

#endif /* TFS_DEV_H */
