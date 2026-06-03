#ifndef PGFS_INTERNAL_H
#define PGFS_INTERNAL_H

#include "luat_pgfs.h"
#include "pgfs_nand_ftl.h"  /* defines pgfs_nand_ftl_ctx_t before pgfs_mount_ctx_t uses it */

#define PGFS_SUPERBLOCK_MAGIC        0x50474653u
#define PGFS_CHECKPOINT_MAGIC        0x50474350u
/* On-disk format version 3: erase-aligned layout with 5 reserved blocks
 * (SB-A, SB-B, CP-A, CP-B, FTL state) and a per-segment data log. The
 * FTL state record (PGFS_FTL_VERSION) is independently versioned; see
 * pgfs_nand_ftl.h. New code MUST use pgfs_layout_t for all address
 * arithmetic — there are no legacy v1/v2 fallback paths. */
#define PGFS_ONDISK_VERSION          3u

/* Address constants for the on-flash regions. All address arithmetic in
 * pgfs must go through pgfs_layout_t, but these defines stay as named
 * anchors for code that needs a specific region (e.g. tests that hand-
 * construct a flash image, the FTL state probe, the VFS adapter's
 * initial base address). */
#define PGFS_SUPERBLOCK_A_ADDR        0x0000u
#define PGFS_SUPERBLOCK_B_ADDR        0x1000u
#define PGFS_CHECKPOINT_A_ADDR        0x2000u
#define PGFS_CHECKPOINT_B_ADDR        0x3000u
#define PGFS_DATA_LOG_BASE_ADDR       0x4000u
/* 5 reserved blocks, data log starts at block 5. */
#define PGFS_LAYOUT_RESERVED_BLOCKS  5u
#define PGFS_DATA_RECORD_MAGIC       0x50474644u
#define PGFS_BATCH_DATA_RECORD_MAGIC 0x50474642u
#define PGFS_BATCH_COMMIT_RECORD_MAGIC 0x50474643u
#define PGFS_MAX_DIRS                256u
#define PGFS_CHECKPOINT_BATCH_CLOSES 8u
#define PGFS_CHECKPOINT_PENDING_CAP  PGFS_CHECKPOINT_BATCH_CLOSES

#define PGFS_CTRL_GET_GEOMETRY       1u
#define PGFS_LOCK_MODE_OFF           0u
#define PGFS_LOCK_MODE_ON            1u
#define PGFS_INJECT_POWERCUT_NONE    0u
#define PGFS_INJECT_POWERCUT_BEFORE_APPEND 1u
#define PGFS_INJECT_POWERCUT_AFTER_APPEND 2u
#define PGFS_INJECT_POWERCUT_BEFORE_CP 3u
#define PGFS_INJECT_POWERCUT_AFTER_CP_ERASE 4u
#define PGFS_INJECT_POWERCUT_AFTER_CP_WRITE 5u
#define PGFS_INJECT_POWERCUT_AFTER_APPEND_ERASE 6u
/* Stages 3 and 4 are FTL powercut (forwarded to FTL ctx):
 *   3 → before FTL erase
 *   4 → after FTL erase, before FTL write
 * See pgfs_ftl_integration.c::pgfs_ftl_on_checkpoint_commit. */

#if defined(_MSC_VER)
#pragma pack(push, 1)
#endif

typedef struct pgfs_superblock {
    uint32_t magic;
    uint16_t version;
    uint16_t reserved;
    uint32_t seq;
    uint32_t checkpoint_addr;
    uint32_t checkpoint_len;
    uint32_t checkpoint_crc;
    uint32_t crc32;
}
#if !defined(_MSC_VER)
__attribute__((packed))
#endif
pgfs_superblock_t;

typedef struct pgfs_checkpoint {
    uint32_t magic;
    uint16_t version;
    uint16_t reserved;
    uint32_t seq;
    uint32_t total_blocks;
    /**
     * Count of data records appended to the data log since the last checkpoint.
     *
     * Note: this is NOT the number of erase blocks consumed on flash. It tracks
     * how many file write/batch-commit events have been recorded as log records
     * (and therefore may need to be replayed to rebuild state on mount).
     * The on-disk luat_fs_info_t.block_used is derived from this counter.
     */
    uint32_t written_blocks;
    uint32_t flags;
    uint32_t gc_live_bytes;
    uint32_t gc_dead_bytes;
    /* Phase 4b: per-segment write head at the moment this CP was committed.
     * Persisted into the FTL state alongside this CP via
     * pgfs_ftl_on_checkpoint_commit. On mount, if the FTL's persisted
     * log_tail_block/offset match these fields, the data log has not
     * been touched since the CP and pgfs_replay_data_log can be skipped. */
    uint32_t log_tail_block;
    uint16_t log_tail_offset;
    uint16_t log_tail_reserved;
    uint32_t crc32;
}
#if !defined(_MSC_VER)
__attribute__((packed))
#endif
pgfs_checkpoint_t;

typedef struct pgfs_flash_geometry {
    uint32_t capacity;
    uint32_t erase_size;
    uint32_t prog_size;
} pgfs_flash_geometry_t;

/* pgfs_layout_t — runtime-computed on-flash layout.
 *
 * Each region occupies exactly one erase unit. Block indices are stable
 * (0..4 are reserved; data log starts at 5). The data log wraps across
 * data_log_first_block..data_log_last_block inclusive, with per-segment
 * write heads persisted in the FTL state (Phase 2 onward).
 *
 * For a 64 MB / 128 KB-erase flash: total_blocks = 512, data log
 * occupies 507 erase units (~64.7 MB).
 *
 * This struct is computed by pgfs_layout_compute() at mount time and
 * every address arithmetic must go through it. Do not introduce new
 * hard-coded address constants. */
typedef struct pgfs_layout {
    uint32_t erase_size;
    uint32_t prog_size;
    uint32_t total_blocks;
    uint32_t sb_a_block;            /* 0 */
    uint32_t sb_b_block;            /* 1 */
    uint32_t cp_a_block;            /* 2 */
    uint32_t cp_b_block;            /* 3 */
    uint32_t ftl_state_block;       /* 4 */
    uint32_t data_log_first_block;  /* 5 */
    uint32_t data_log_last_block;   /* total_blocks - 1 */
    uint32_t reserved_block_count;  /* 5 */
} pgfs_layout_t;

/* pgfs_layout_compute — fill layout from a flash geometry.
 * Returns 0 on success, -1 if the geometry is too small to host
 * the required reserved blocks. */
int pgfs_layout_compute(const pgfs_flash_geometry_t* geo, pgfs_layout_t* out);

/* Phase 4: consistency check between the latest checkpoint and the FTL
 * state. If the CP's log_tail_block/offset matches the FTL's persisted
 * write_head_block/offset, the data log is consistent and the mount
 * path can skip pgfs_replay_data_log. Returns true if consistent. */
bool pgfs_checkpoint_is_consistent_with_ftl(const pgfs_checkpoint_t* cp,
                                          const pgfs_nand_ftl_ctx_t* ftl);

typedef struct pgfs_diag_stats {
    uint32_t lock_acquire_count;
    uint32_t lock_passthrough_count;
    uint32_t checkpoint_fallback_count;
    uint32_t powercut_inject_count;
    uint32_t badblock_inject_count;
    /* Phase 6: lifecycle + GC observability counters. These are
     * bumped on the relevant code paths and exposed (via
     * pgfs_diag_stats_dump below) for the stress / multi-mount tests
     * to assert against. */
    uint32_t mount_count;             /* successful luat_vfs_pgfs_mount calls */
    uint32_t replay_count;            /* full data log replays (not O(1) skip) */
    uint32_t replay_skip_count;       /* O(1) skip path activations (Phase 4b) */
    uint32_t replay_bytes_processed;  /* bytes scanned in the data log during replay */
    uint32_t cp_commit_count;         /* pgfs_checkpoint_store_next successes */
    uint32_t ftl_persist_count;       /* pgfs_ftl_persist successes */
    uint32_t ftl_load_count;          /* pgfs_ftl_load successes */
    uint32_t gc_step_count;           /* pgfs_gc_step invocations (any return) */
    uint32_t gc_bytes_reclaimed;      /* sum of erase_size returned by gc_step */
    uint32_t gc_records_moved;        /* sum of records rewritten by gc_step */
} pgfs_diag_stats_t;

typedef struct pgfs_mount_ctx {
    int mounted;
    char mount_point[16];
    const pgfs_flash_opts_t *flash_opts;
    uint32_t runtime_generation;
    uint8_t checkpoint_loaded;
    uint8_t lock_mode;
    uint8_t inject_powercut_stage;
    uint8_t inject_bad_block_once;
    uint8_t inject_corrupt_latest_cp;
    uint16_t pending_checkpoint_writes;
    uint16_t reserved0;
    pgfs_layout_t layout;                /* computed at mount from geometry */
    pgfs_checkpoint_t checkpoint;
    uint32_t data_log_base_addr;         /* legacy field; derived from layout */
    uint32_t data_log_write_addr;        /* legacy field; per-segment head in layout */
    uint32_t data_log_prepared_until;
    uint32_t gc_next_seg_id;            /* legacy; per-segment head replaces this */
    uint32_t log_tail_block;            /* Phase 4: per-segment write head at last CP */
    uint16_t log_tail_offset;            /* Phase 4: offset within tail block at last CP */
    uint16_t layout_reserved0;           /* padding to keep alignment */
    pgfs_diag_stats_t stats;
    uint8_t batch_active;
    uint8_t batch_reserved[3];
    uint32_t batch_id;
    uint32_t batch_next_id;
    /* NAND FTL context (bad-block map, erase counts, inject bookkeeping) */
    pgfs_nand_ftl_ctx_t ftl;
} pgfs_mount_ctx_t;

typedef struct pgfs_file_cache {
    uint8_t *data;
    size_t len;
    size_t cap;
    uint8_t heap_type;
} pgfs_file_cache_t;

typedef struct pgfs_file_entry {
    uint8_t used;
    uint8_t heap_type;
    uint8_t reserved[2];
    char path[96];
    uint8_t *data;
    size_t len;
    size_t cap;
    /* Phase 2 GC: block where the most recent DATA record for this
     * file was written. Used by the file-close / file-delete paths
     * to attribute dead bytes to the block that held the previous
     * version of the file. 0xFFFFu means "unknown / never written". */
    uint16_t last_written_block;
    uint16_t last_written_reserved;
} pgfs_file_entry_t;

typedef struct pgfs_dir_entry {
    uint8_t used;
    uint8_t reserved[3];
    char path[96];
} pgfs_dir_entry_t;

typedef struct pgfs_file {
    pgfs_mount_ctx_t *ctx;
    pgfs_file_entry_t *entry;
    char path[96];
    size_t pos;
    uint32_t generation;
    uint8_t mode_write;
    uint8_t mode_read;
    uint8_t eof;
    uint8_t err;
    uint8_t opened_in_batch;
    uint8_t batch_reserved[3];
    uint32_t batch_id;
    pgfs_file_cache_t cache;
} pgfs_file_t;

#if defined(_MSC_VER)
#pragma pack(pop)
#endif

pgfs_mount_ctx_t* pgfs_get_mount_ctx(void);

int pgfs_pick_latest_valid_sb(const pgfs_superblock_t* a, const pgfs_superblock_t* b, pgfs_superblock_t* out);
int pgfs_checkpoint_load(void* fs, pgfs_checkpoint_t* cp);
int pgfs_checkpoint_store_next(void* fs, const pgfs_checkpoint_t* current, pgfs_checkpoint_t* next);
int pgfs_checkpoint_commit_pending(pgfs_mount_ctx_t* ctx);
int pgfs_replay_data_log(pgfs_mount_ctx_t* ctx);
int pgfs_info_fast(pgfs_mount_ctx_t* ctx, luat_fs_info_t* out);
int pgfs_rebuild_checkpoint_from_replay(pgfs_mount_ctx_t* ctx);

int pgfs_cache_append(pgfs_file_t* f, const uint8_t* data, size_t len);
int pgfs_lock(pgfs_mount_ctx_t* ctx);
int pgfs_unlock(pgfs_mount_ctx_t* ctx);
int pgfs_batch_begin(pgfs_mount_ctx_t* ctx, uint32_t* out_batch_id);
int pgfs_batch_commit(pgfs_mount_ctx_t* ctx, uint32_t batch_id);
int pgfs_batch_abort(pgfs_mount_ctx_t* ctx, uint32_t batch_id);

/* Phase 2 GC: visit every in-use file_entry in the mount's file
 * table. The callback receives (entry, user_data). Returning non-zero
 * from the callback stops the iteration. Used by the cost-benefit GC
 * to find entries whose last_written_block matches a victim. */
typedef int (*pgfs_file_visit_fn)(pgfs_file_entry_t* entry, void* user_data);
int pgfs_file_table_visit(pgfs_file_visit_fn cb, void* user_data);

/* Phase 2 GC: re-append a DATA record from a file_t's cache. Used by
 * the GC data-move path to copy live records out of a victim block. */
int pgfs_append_data_record(pgfs_mount_ctx_t* ctx, struct pgfs_file* f);

FILE* pgfs_file_open(pgfs_mount_ctx_t* ctx, const char *filename, const char *mode);
int pgfs_file_close(pgfs_mount_ctx_t* ctx, FILE* stream);
size_t pgfs_file_read(pgfs_mount_ctx_t* ctx, void *ptr, size_t size, size_t nmemb, FILE *stream);
int pgfs_file_getc(pgfs_mount_ctx_t* ctx, FILE* stream);
size_t pgfs_file_write(pgfs_mount_ctx_t* ctx, const void *ptr, size_t size, size_t nmemb, FILE *stream);
int pgfs_file_seek(pgfs_mount_ctx_t* ctx, FILE* stream, long int offset, int origin);
int pgfs_file_tell(pgfs_mount_ctx_t* ctx, FILE* stream);
int pgfs_file_eof(pgfs_mount_ctx_t* ctx, FILE* stream);
int pgfs_file_error(pgfs_mount_ctx_t* ctx, FILE* stream);
int pgfs_file_flush(pgfs_mount_ctx_t* ctx, FILE* stream);
void pgfs_file_reset_all(void);
/* Phase 2 GC shadow detection: read the last_written_block of the
 * first matching file_entry. Used by tests to inspect which block a
 * given file's most recent record landed in. Returns 0xFFFFu when no
 * matching entry is found. */
uint16_t pgfs_file_table_lookup_last_written(const char* path);
int pgfs_dir_mkdir(pgfs_mount_ctx_t* ctx, const char *path);
int pgfs_dir_rmdir(pgfs_mount_ctx_t* ctx, const char *path);
int pgfs_dir_lsdir(pgfs_mount_ctx_t* ctx, const char *path, luat_fs_dirent_t* ents, size_t offset, size_t len);
void* pgfs_dir_opendir(pgfs_mount_ctx_t* ctx, const char *path);
int pgfs_dir_closedir(pgfs_mount_ctx_t* ctx, void* dir);

typedef struct pgfs_seg_summary {
    uint32_t live_bytes;
    uint32_t dead_bytes;
    uint32_t erase_count;
    uint32_t flags;
} pgfs_seg_summary_t;

int pgfs_alloc_segment(pgfs_mount_ctx_t* ctx, uint32_t* seg_id);
int pgfs_gc_step(pgfs_mount_ctx_t* ctx, uint32_t byte_budget, uint32_t time_budget_us);
int pgfs_mark_block_retired(pgfs_mount_ctx_t* ctx, uint32_t block_id);

#endif
