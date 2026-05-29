#ifndef PGFS_INTERNAL_H
#define PGFS_INTERNAL_H

#include "luat_pgfs.h"

#define PGFS_SUPERBLOCK_MAGIC        0x50474653u
#define PGFS_CHECKPOINT_MAGIC        0x50474350u
#define PGFS_ONDISK_VERSION          1u

#define PGFS_SUPERBLOCK_A_ADDR       0x0000u
#define PGFS_SUPERBLOCK_B_ADDR       0x1000u
#define PGFS_CHECKPOINT_A_ADDR       0x2000u
#define PGFS_CHECKPOINT_B_ADDR       0x3000u
#define PGFS_DATA_LOG_BASE_ADDR      0x4000u
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
#define PGFS_INJECT_POWERCUT_BEFORE_CP 1u

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
    uint32_t used_blocks;
    uint32_t flags;
    uint32_t gc_live_bytes;
    uint32_t gc_dead_bytes;
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

typedef struct pgfs_diag_stats {
    uint32_t lock_acquire_count;
    uint32_t lock_passthrough_count;
    uint32_t checkpoint_fallback_count;
    uint32_t powercut_inject_count;
    uint32_t badblock_inject_count;
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
    pgfs_checkpoint_t checkpoint;
    uint32_t data_log_base_addr;
    uint32_t data_log_write_addr;
    uint32_t data_log_prepared_until;
    uint32_t gc_next_seg_id;
    pgfs_diag_stats_t stats;
    uint8_t batch_active;
    uint8_t batch_reserved[3];
    uint32_t batch_id;
    uint32_t batch_next_id;
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
int pgfs_cache_flush_to_log(pgfs_mount_ctx_t* ctx, pgfs_file_t* f);
int pgfs_lock(pgfs_mount_ctx_t* ctx);
int pgfs_unlock(pgfs_mount_ctx_t* ctx);
int pgfs_batch_begin(pgfs_mount_ctx_t* ctx, uint32_t* out_batch_id);
int pgfs_batch_commit(pgfs_mount_ctx_t* ctx, uint32_t batch_id);
int pgfs_batch_abort(pgfs_mount_ctx_t* ctx, uint32_t batch_id);

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
int pgfs_file_remove(pgfs_mount_ctx_t* ctx, const char *filename);
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
