#include "luat_base.h"
#include "pgfs_internal.h"
#include "pgfs_ecc.h"
#include "luat_mem.h"
#include "luat_mcu.h"
#include "luat_crypto.h"
#define LUAT_LOG_TAG "pgfs"
#include "luat_log.h"

#ifdef LUAT_USE_PGFS_COMPONENT

typedef struct pgfs_data_record_hdr {
    uint32_t magic;
    uint32_t path_len;
    uint32_t data_len;
    uint32_t crc32;
    uint8_t  ecc[8];   /* Phase 3b: Hamming(72,64) SECDED over the header */
} pgfs_data_record_hdr_t;

typedef struct pgfs_batch_data_record_hdr {
    uint32_t magic;
    uint32_t path_len;
    uint32_t data_len;
    uint32_t batch_id;
    uint32_t crc32;
    uint8_t  ecc[8];   /* Phase 3b: Hamming(72,64) SECDED over the header */
} pgfs_batch_data_record_hdr_t;

typedef struct pgfs_batch_commit_record_hdr {
    uint32_t magic;
    uint32_t batch_id;
    uint32_t record_count;
    uint32_t crc32;
    uint8_t  ecc[8];   /* Phase 3b: Hamming(72,64) SECDED over the header */
} pgfs_batch_commit_record_hdr_t;

static int pgfs_batch_apply_committed(pgfs_mount_ctx_t* ctx, uint32_t batch_id);
static void pgfs_batch_drop(pgfs_mount_ctx_t* ctx, uint32_t batch_id);
static pgfs_file_entry_t* pgfs_alloc_file(pgfs_mount_ctx_t* ctx, const char* path);
static int pgfs_append_batch_data_record(pgfs_mount_ctx_t* ctx, pgfs_batch_pending_entry_t* p);
static int pgfs_append_batch_commit_record(pgfs_mount_ctx_t* ctx, uint32_t batch_id, uint32_t record_count);
static int pgfs_batch_persist_committed(pgfs_mount_ctx_t* ctx, uint32_t batch_id);

static void pgfs_mark_checkpoint_pending(pgfs_mount_ctx_t* ctx) {
    if (ctx == NULL) {
        return;
    }
    if (ctx->pending_checkpoint_writes < PGFS_CHECKPOINT_PENDING_CAP) {
        ctx->pending_checkpoint_writes++;
    }
}

static void pgfs_heap_free_by_type(uint8_t heap_type, void* ptr) {
    if (ptr == NULL) {
        return;
    }
    if (heap_type == (uint8_t)LUAT_HEAP_PSRAM) {
        luat_heap_opt_free(LUAT_HEAP_PSRAM, ptr);
    }
    else {
        luat_heap_free(ptr);
    }
}

static void* pgfs_heap_alloc_prefer_psram(size_t len, uint8_t* heap_type) {
    void* ptr = luat_heap_opt_malloc(LUAT_HEAP_PSRAM, len);
    if (ptr != NULL) {
        if (heap_type != NULL) {
            *heap_type = (uint8_t)LUAT_HEAP_PSRAM;
        }
        return ptr;
    }
    ptr = luat_heap_malloc(len);
    if (ptr != NULL && heap_type != NULL) {
        *heap_type = (uint8_t)LUAT_HEAP_SRAM;
    }
    return ptr;
}

static uint32_t pgfs_crc32_calc(const void* data, size_t len) {
    return luat_crc32(data, (uint32_t)len, 0xFFFFFFFFu, 0);
}

/* pgfs_account_live_block — add `bytes` to live_bytes[block_of(addr)].
 * Called from the data record append path (DATA / BATCH_DATA) and from
 * the replay path. The block_id is derived from the absolute flash
 * address divided by the erase size. Uses the cached layout.erase_size
 * to avoid a control(GET_GEOMETRY) call on every record write. */
static void pgfs_account_live_block(pgfs_mount_ctx_t* ctx, uint32_t addr, uint32_t bytes) {
    if (ctx == NULL || bytes == 0) return;
    if (ctx->ftl.live_bytes_per_block == NULL) return;
    uint32_t erase_size = ctx->layout.erase_size;
    if (erase_size == 0) {
        /* Fallback: query geometry (only on first call before layout is set) */
        if (ctx->ftl.flash_opts == NULL || ctx->ftl.flash_opts->control == NULL) return;
        pgfs_flash_geometry_t geo = {0};
        if (ctx->ftl.flash_opts->control(ctx->ftl.flash_opts->ctx,
                                         PGFS_CTRL_GET_GEOMETRY, &geo) != 0 ||
            geo.erase_size == 0) {
            return;
        }
        erase_size = geo.erase_size;
    }
    uint32_t block_id = addr / erase_size;
    if (block_id >= ctx->ftl.total_blocks) return;
    ctx->ftl.live_bytes_per_block[block_id] += bytes;
    pgfs_ftl_mark_dirty(&ctx->ftl);
}

/* pgfs_account_dead_block — add `bytes` to dead_bytes[block_of(addr)].
 * Best-effort: called when we know the source block of shadowed or
 * deleted data. Uses cached layout.erase_size for performance. */
static void pgfs_account_dead_block(pgfs_mount_ctx_t* ctx, uint32_t addr, uint32_t bytes) {
    if (ctx == NULL || bytes == 0) return;
    if (ctx->ftl.dead_bytes_per_block == NULL) return;
    uint32_t erase_size = ctx->layout.erase_size;
    if (erase_size == 0) {
        if (ctx->ftl.flash_opts == NULL || ctx->ftl.flash_opts->control == NULL) return;
        pgfs_flash_geometry_t geo = {0};
        if (ctx->ftl.flash_opts->control(ctx->ftl.flash_opts->ctx,
                                         PGFS_CTRL_GET_GEOMETRY, &geo) != 0 ||
            geo.erase_size == 0) {
            return;
        }
        erase_size = geo.erase_size;
    }
    uint32_t block_id = addr / erase_size;
    if (block_id >= ctx->ftl.total_blocks) return;
    ctx->ftl.dead_bytes_per_block[block_id] += bytes;
    pgfs_ftl_mark_dirty(&ctx->ftl);
}

/* pgfs_data_log_base_addr — derive the data log base address from the
 * mount ctx's pre-computed layout. The layout is filled in by
 * pgfs_layout_compute() at mount time, so callers that reach this
 * helper without a populated layout are misusing the API. */
static uint32_t pgfs_data_log_base_addr(pgfs_mount_ctx_t* ctx) {
    if (ctx == NULL || ctx->layout.erase_size == 0) {
        return 0;
    }
    return ctx->layout.data_log_first_block * ctx->layout.erase_size;
}

static uint32_t pgfs_program_size(pgfs_mount_ctx_t* ctx) {
    pgfs_flash_geometry_t geo = {0};
    if (ctx != NULL && ctx->flash_opts != NULL && ctx->flash_opts->control != NULL &&
        ctx->flash_opts->control(ctx->flash_opts->ctx, PGFS_CTRL_GET_GEOMETRY, &geo) == 0 &&
        geo.prog_size != 0) {
        return geo.prog_size;
    }
    return 1u;
}

static size_t pgfs_record_storage_len(pgfs_mount_ctx_t* ctx, size_t logical_len) {
    uint32_t prog_size = pgfs_program_size(ctx);
    uint64_t span = logical_len;
    if (prog_size > 1u) {
        span = (span + (uint64_t)prog_size - 1u) / (uint64_t)prog_size * (uint64_t)prog_size;
    }
    if (span > SIZE_MAX) {
        return 0;
    }
    return (size_t)span;
}

static uint32_t pgfs_align_up_u32(uint32_t value, uint32_t align) {
    uint64_t out = 0;
    if (align <= 1u) {
        return value;
    }
    out = ((uint64_t)value + (uint64_t)align - 1u) / (uint64_t)align * (uint64_t)align;
    if (out > 0xFFFFFFFFu) {
        return 0xFFFFFFFFu;
    }
    return (uint32_t)out;
}

/* ── Per-mount tables + hash index (P0-1 / P1-2) ──────────────────────── */

/* FNV-1a 32-bit path hash. */
static uint32_t pgfs_path_hash(const char* path) {
    uint32_t h = 2166136261u;
    if (path == NULL) return h;
    while (*path) {
        h ^= (uint8_t)(*path++);
        h *= 16777619u;
    }
    return h;
}

static uint32_t pgfs_hash_next_pow2(uint32_t v) {
    uint32_t p = 1u;
    while (p < v) {
        p <<= 1u;
    }
    return p;
}

static int32_t* pgfs_hash_alloc(uint32_t table_cap, uint32_t* out_cap) {
    uint32_t cap = pgfs_hash_next_pow2(table_cap * 2u);
    int32_t* slots = NULL;
    if (cap < 16u) cap = 16u;
    slots = (int32_t*)luat_heap_malloc(cap * sizeof(int32_t));
    if (slots == NULL) {
        return NULL;
    }
    memset(slots, 0, cap * sizeof(int32_t));
    *out_cap = cap;
    return slots;
}

static int pgfs_hash_lookup_file(pgfs_mount_ctx_t* ctx, const char* path) {
    uint32_t i = 0;
    uint32_t cap = 0;
    if (ctx == NULL || ctx->file_hash_slots == NULL || path == NULL) {
        return -1;
    }
    cap = ctx->file_hash_cap;
    if (cap == 0) {
        return -1;
    }
    i = pgfs_path_hash(path) & (cap - 1u);
    while (ctx->file_hash_slots[i] != 0) {
        int32_t v = ctx->file_hash_slots[i];
        if (v > 0) {
            uint32_t idx = (uint32_t)(v - 1);
            if (idx < ctx->file_cap && ctx->files != NULL &&
                ctx->files[idx].used && strcmp(ctx->files[idx].path, path) == 0) {
                return (int)idx;
            }
        }
        i = (i + 1u) & (cap - 1u);
    }
    return -1;
}

static int pgfs_hash_lookup_dir(pgfs_mount_ctx_t* ctx, const char* path) {
    uint32_t i = 0;
    uint32_t cap = 0;
    if (ctx == NULL || ctx->dir_hash_slots == NULL || path == NULL) {
        return -1;
    }
    cap = ctx->dir_hash_cap;
    if (cap == 0) {
        return -1;
    }
    i = pgfs_path_hash(path) & (cap - 1u);
    while (ctx->dir_hash_slots[i] != 0) {
        int32_t v = ctx->dir_hash_slots[i];
        if (v > 0) {
            uint32_t idx = (uint32_t)(v - 1);
            if (idx < ctx->dir_cap && ctx->dirs != NULL &&
                ctx->dirs[idx].used && strcmp(ctx->dirs[idx].path, path) == 0) {
                return (int)idx;
            }
        }
        i = (i + 1u) & (cap - 1u);
    }
    return -1;
}

static void pgfs_hash_insert(int32_t* slots, uint32_t cap, const char* path,
                             uint32_t table_index) {
    uint32_t i = pgfs_path_hash(path) & (cap - 1u);
    if (slots == NULL || cap == 0) {
        return;
    }
    while (slots[i] != 0 && slots[i] != -1) {
        i = (i + 1u) & (cap - 1u);
    }
    slots[i] = (int32_t)table_index + 1;
}

static void pgfs_hash_remove(int32_t* slots, uint32_t cap, const char* path,
                             uint32_t table_index) {
    uint32_t i = 0;
    if (slots == NULL || cap == 0 || path == NULL) {
        return;
    }
    i = pgfs_path_hash(path) & (cap - 1u);
    while (slots[i] != 0) {
        if (slots[i] == (int32_t)table_index + 1) {
            slots[i] = -1; /* tombstone */
            return;
        }
        i = (i + 1u) & (cap - 1u);
    }
}

int pgfs_tables_init(pgfs_mount_ctx_t* ctx) {
    if (ctx == NULL) {
        return -1;
    }
    if (ctx->files != NULL) {
        return 0; /* already initialised */
    }
    ctx->file_cap = PGFS_MAX_FILES;
    ctx->dir_cap = PGFS_MAX_DIRS;
    ctx->batch_pending_cap = PGFS_MAX_BATCH_PENDING;
    ctx->files = (pgfs_file_entry_t*)luat_heap_malloc(ctx->file_cap * sizeof(pgfs_file_entry_t));
    ctx->dirs = (pgfs_dir_entry_t*)luat_heap_malloc(ctx->dir_cap * sizeof(pgfs_dir_entry_t));
    ctx->batch_pending = (pgfs_batch_pending_entry_t*)luat_heap_malloc(ctx->batch_pending_cap * sizeof(pgfs_batch_pending_entry_t));
    if (ctx->files == NULL || ctx->dirs == NULL || ctx->batch_pending == NULL) {
        pgfs_tables_deinit(ctx);
        return -1;
    }
    memset(ctx->files, 0, ctx->file_cap * sizeof(pgfs_file_entry_t));
    memset(ctx->dirs, 0, ctx->dir_cap * sizeof(pgfs_dir_entry_t));
    memset(ctx->batch_pending, 0, ctx->batch_pending_cap * sizeof(pgfs_batch_pending_entry_t));
    ctx->file_hash_slots = pgfs_hash_alloc(ctx->file_cap, &ctx->file_hash_cap);
    ctx->dir_hash_slots = pgfs_hash_alloc(ctx->dir_cap, &ctx->dir_hash_cap);
    if (ctx->file_hash_slots == NULL || ctx->dir_hash_slots == NULL) {
        pgfs_tables_deinit(ctx);
        return -1;
    }
    return 0;
}

int pgfs_tables_ensure(pgfs_mount_ctx_t* ctx) {
    if (ctx == NULL) {
        return -1;
    }
    if (ctx->files != NULL) {
        return 0;
    }
    return pgfs_tables_init(ctx);
}

void pgfs_tables_deinit(pgfs_mount_ctx_t* ctx) {
    uint32_t i = 0;
    if (ctx == NULL) {
        return;
    }
    if (ctx->files != NULL) {
        for (i = 0; i < ctx->file_cap; i++) {
            if (ctx->files[i].data != NULL) {
                pgfs_heap_free_by_type(ctx->files[i].heap_type, ctx->files[i].data);
            }
        }
        luat_heap_free(ctx->files);
    }
    if (ctx->dirs != NULL) {
        luat_heap_free(ctx->dirs);
    }
    if (ctx->batch_pending != NULL) {
        for (i = 0; i < ctx->batch_pending_cap; i++) {
            if (ctx->batch_pending[i].data != NULL) {
                pgfs_heap_free_by_type(ctx->batch_pending[i].heap_type, ctx->batch_pending[i].data);
            }
        }
        luat_heap_free(ctx->batch_pending);
    }
    if (ctx->file_hash_slots != NULL) {
        luat_heap_free(ctx->file_hash_slots);
    }
    if (ctx->dir_hash_slots != NULL) {
        luat_heap_free(ctx->dir_hash_slots);
    }
    ctx->files = NULL;
    ctx->dirs = NULL;
    ctx->batch_pending = NULL;
    ctx->file_hash_slots = NULL;
    ctx->dir_hash_slots = NULL;
    ctx->file_cap = 0;
    ctx->dir_cap = 0;
    ctx->batch_pending_cap = 0;
    ctx->file_hash_cap = 0;
    ctx->dir_hash_cap = 0;
}


static int pgfs_path_normalize(const char* in, char* out, size_t outlen) {
    size_t len = 0;
    if (in == NULL || out == NULL || outlen == 0) {
        return -1;
    }
    while (*in == '/' || *in == '\\') {
        in++;
    }
    while (*in != '\0') {
        char c = *in++;
        if (c == '\\') {
            c = '/';
        }
        if (c == '/') {
            while (*in == '/' || *in == '\\') {
                in++;
            }
            if (len == 0 || out[len - 1] == '/') {
                continue;
            }
            if (len + 1 >= outlen) {
                return -1;
            }
            out[len++] = '/';
            continue;
        }
        if (len + 1 >= outlen) {
            return -1;
        }
        out[len++] = c;
    }
    while (len > 0 && out[len - 1] == '/') {
        len--;
    }
    out[len] = '\0';
    return 0;
}

static int pgfs_path_parent(const char* path, char* parent, size_t parentlen) {
    const char* pos = NULL;
    size_t len = 0;
    if (path == NULL || parent == NULL || parentlen == 0) {
        return -1;
    }
    pos = strrchr(path, '/');
    if (pos == NULL) {
        parent[0] = '\0';
        return 0;
    }
    len = (size_t)(pos - path);
    if (len >= parentlen) {
        return -1;
    }
    memcpy(parent, path, len);
    parent[len] = '\0';
    return 0;
}

static int pgfs_path_child(const char* dir, const char* path, char* child, size_t childlen, int* is_dir) {
    const char* cursor = NULL;
    const char* slash = NULL;
    size_t seg_len = 0;
    size_t dir_len = 0;
    if (dir == NULL || path == NULL) {
        return -1;
    }
    dir_len = strlen(dir);
    if (dir_len == 0) {
        cursor = path;
    }
    else {
        if (strncmp(path, dir, dir_len) != 0 || path[dir_len] != '/') {
            return 0;
        }
        cursor = path + dir_len + 1;
    }
    if (*cursor == '\0') {
        return 0;
    }
    slash = strchr(cursor, '/');
    seg_len = slash ? (size_t)(slash - cursor) : strlen(cursor);
    if (seg_len == 0) {
        return 0;
    }
    if (child != NULL) {
        if (seg_len >= childlen) {
            return -1;
        }
        memcpy(child, cursor, seg_len);
        child[seg_len] = '\0';
    }
    if (is_dir != NULL) {
        *is_dir = slash != NULL ? 1 : 0;
    }
    return 1;
}

static pgfs_file_entry_t* pgfs_find_file_norm(pgfs_mount_ctx_t* ctx, const char* path) {
    int idx = -1;
    size_t i = 0;
    if (ctx == NULL || path == NULL || ctx->files == NULL) {
        return NULL;
    }
    /* P1-2: hash lookup first, linear scan as fallback (defensive). */
    idx = pgfs_hash_lookup_file(ctx, path);
    if (idx >= 0) {
        return &ctx->files[idx];
    }
    for (i = 0; i < ctx->file_cap; i++) {
        if (ctx->files[i].used && strcmp(ctx->files[i].path, path) == 0) {
            return &ctx->files[i];
        }
    }
    return NULL;
}

static pgfs_dir_entry_t* pgfs_find_dir_norm(pgfs_mount_ctx_t* ctx, const char* path) {
    int idx = -1;
    size_t i = 0;
    if (ctx == NULL || path == NULL || ctx->dirs == NULL) {
        return NULL;
    }
    idx = pgfs_hash_lookup_dir(ctx, path);
    if (idx >= 0) {
        return &ctx->dirs[idx];
    }
    for (i = 0; i < ctx->dir_cap; i++) {
        if (ctx->dirs[i].used && strcmp(ctx->dirs[i].path, path) == 0) {
            return &ctx->dirs[i];
        }
    }
    return NULL;
}

static int pgfs_ctx_handle_valid(pgfs_mount_ctx_t* ctx, uint32_t generation) {
    if (ctx == NULL) {
        return 0;
    }
    return ctx->runtime_generation == generation;
}

int pgfs_batch_begin(pgfs_mount_ctx_t* ctx, uint32_t* out_batch_id) {
    if (ctx == NULL || out_batch_id == NULL || ctx->batch_active) {
        return -1;
    }
    if (ctx->batch_next_id == 0) {
        ctx->batch_next_id = 1;
    }
    ctx->batch_id = ctx->batch_next_id++;
    ctx->batch_active = 1;
    *out_batch_id = ctx->batch_id;
    return 0;
}

int pgfs_batch_commit(pgfs_mount_ctx_t* ctx, uint32_t batch_id) {
    if (ctx == NULL || !ctx->batch_active || ctx->batch_id != batch_id || batch_id == 0) {
        return -1;
    }
    if (pgfs_lock(ctx) != 0) {
        return -1;
    }
    if (pgfs_batch_persist_committed(ctx, batch_id) != 0) {
        pgfs_unlock(ctx);
        return -1;
    }
    if (pgfs_batch_apply_committed(ctx, batch_id) != 0) {
        pgfs_unlock(ctx);
        return -1;
    }
    pgfs_unlock(ctx);
    ctx->batch_active = 0;
    ctx->batch_id = 0;
    return 0;
}

int pgfs_batch_abort(pgfs_mount_ctx_t* ctx, uint32_t batch_id) {
    if (ctx == NULL || !ctx->batch_active || ctx->batch_id != batch_id || batch_id == 0) {
        return -1;
    }
    pgfs_batch_drop(ctx, batch_id);
    ctx->batch_active = 0;
    ctx->batch_id = 0;
    return 0;
}

static int pgfs_dir_has_descendant_norm(pgfs_mount_ctx_t* ctx, const char* path) {
    size_t i = 0;
    if (ctx == NULL || ctx->files == NULL || ctx->dirs == NULL) {
        return 0;
    }
    for (i = 0; i < ctx->file_cap; i++) {
        if (!ctx->files[i].used) {
            continue;
        }
        if (path[0] == '\0' || (strncmp(ctx->files[i].path, path, strlen(path)) == 0 && ctx->files[i].path[strlen(path)] == '/')) {
            return 1;
        }
    }
    for (i = 0; i < ctx->dir_cap; i++) {
        if (!ctx->dirs[i].used) {
            continue;
        }
        if (path[0] == '\0') {
            if (ctx->dirs[i].path[0] != '\0') {
                return 1;
            }
            continue;
        }
        if (strncmp(ctx->dirs[i].path, path, strlen(path)) == 0 && ctx->dirs[i].path[strlen(path)] == '/') {
            return 1;
        }
    }
    return 0;
}

static int pgfs_dir_exists_norm(pgfs_mount_ctx_t* ctx, const char* path) {
    if (path == NULL) {
        return 0;
    }
    if (path[0] == '\0') {
        return 1;
    }
    return pgfs_find_dir_norm(ctx, path) != NULL || pgfs_dir_has_descendant_norm(ctx, path);
}

static int pgfs_dir_find_free_slot(pgfs_mount_ctx_t* ctx) {
    size_t i = 0;
    if (ctx == NULL || ctx->dirs == NULL) {
        return -1;
    }
    for (i = 0; i < ctx->dir_cap; i++) {
        if (!ctx->dirs[i].used) {
            return (int)i;
        }
    }
    return -1;
}

static int pgfs_dir_store_norm(pgfs_mount_ctx_t* ctx, const char* path) {
    pgfs_dir_entry_t* entry = NULL;
    int slot = 0;
    if (ctx == NULL || path == NULL || path[0] == '\0' || ctx->dirs == NULL) {
        return 0;
    }
    if (pgfs_find_file_norm(ctx, path) != NULL) {
        return -1;
    }
    entry = pgfs_find_dir_norm(ctx, path);
    if (entry != NULL) {
        return 0;
    }
    slot = pgfs_dir_find_free_slot(ctx);
    if (slot < 0) {
        return -1;
    }
    memset(&ctx->dirs[slot], 0, sizeof(ctx->dirs[slot]));
    ctx->dirs[slot].used = 1;
    memcpy(ctx->dirs[slot].path, path, strlen(path) + 1);
    pgfs_hash_insert(ctx->dir_hash_slots, ctx->dir_hash_cap, path, (uint32_t)slot);
    return 0;
}

static int pgfs_dir_ensure_norm(pgfs_mount_ctx_t* ctx, const char* path) {
    char current[PGFS_MAX_PATH] = {0};
    size_t len = 0;
    if (ctx == NULL || path == NULL) {
        return -1;
    }
    if (path[0] == '\0') {
        return 0;
    }
    len = strlen(path);
    if (len >= sizeof(current)) {
        return -1;
    }
    memcpy(current, path, len + 1);
    for (size_t i = 0; i < len; i++) {
        if (current[i] != '/') {
            continue;
        }
        current[i] = '\0';
        if (current[0] != '\0' && pgfs_dir_store_norm(ctx, current) != 0) {
            return -1;
        }
        current[i] = '/';
    }
    return pgfs_dir_store_norm(ctx, current);
}

static int pgfs_dir_remove_norm(pgfs_mount_ctx_t* ctx, const char* path) {
    pgfs_dir_entry_t* entry = NULL;
    if (ctx == NULL || path == NULL || path[0] == '\0' || ctx->dirs == NULL) {
        return -1;
    }
    if (pgfs_dir_has_descendant_norm(ctx, path)) {
        return -1;
    }
    entry = pgfs_find_dir_norm(ctx, path);
    if (entry == NULL) {
        return -1;
    }
    {
        size_t idx = (size_t)(entry - ctx->dirs);
        pgfs_hash_remove(ctx->dir_hash_slots, ctx->dir_hash_cap, path, (uint32_t)idx);
    }
    memset(entry, 0, sizeof(*entry));
    return 0;
}

/* P2-9: Zero-allocation lsdir — uses O(n²) dedup scan instead of a
 * heap-allocated seen-names buffer. For typical embedded directories
 * (PGFS_MAX_DIRS=256, PGFS_MAX_FILES=512), the ~300K comparison
 * worst-case is acceptable for an infrequent directory listing
 * operation and saves up to 12KB of heap. */

/* P2-9: scan the ENTIRE dir and file tables for a duplicate child name.
 * dir_limit and file_limit specify the maximum index to scan (use
 * PGFS_MAX_DIRS/PGFS_MAX_FILES to scan the whole table, or an index < N
 * to scan only entries before a given position for dedup). */
static int pgfs_lsdir_name_is_duplicate(pgfs_mount_ctx_t* ctx, const char* child, const char* parent,
                                         size_t dir_limit, size_t file_limit) {
    size_t k;
    char cmp[PGFS_MAX_PATH] = {0};
    int cmp_is_dir = 0;
    size_t max_k;
    if (ctx == NULL || ctx->dirs == NULL || ctx->files == NULL) {
        return 0;
    }
    /* Guard against (size_t)-1 sentinel — cap at table size */
    max_k = dir_limit < ctx->dir_cap ? dir_limit : ctx->dir_cap;
    for (k = 0; k < max_k; k++) {
        cmp[0] = '\0'; cmp_is_dir = 1;
        if (!ctx->dirs[k].used) continue;
        if (strcmp(ctx->dirs[k].path, parent) == 0) continue;
        if (pgfs_path_child(parent, ctx->dirs[k].path, cmp, sizeof(cmp), &cmp_is_dir) <= 0 || cmp[0] == '\0') continue;
        if (strcmp(cmp, child) == 0) return 1;
    }
    /* Check file entries */
    max_k = file_limit < ctx->file_cap ? file_limit : ctx->file_cap;
    for (k = 0; k < max_k; k++) {
        cmp[0] = '\0'; cmp_is_dir = 0;
        if (!ctx->files[k].used) continue;
        if (strcmp(ctx->files[k].path, parent) == 0) continue;
        if (pgfs_path_child(parent, ctx->files[k].path, cmp, sizeof(cmp), &cmp_is_dir) <= 0 || cmp[0] == '\0') continue;
        if (strcmp(cmp, child) == 0) return 1;
    }
    return 0;
}

static int pgfs_dir_lsdir_norm(pgfs_mount_ctx_t* ctx, const char* path, luat_fs_dirent_t* ents, size_t offset, size_t len) {
    size_t unique_count = 0;
    size_t out = 0;
    size_t i = 0;
    char norm[PGFS_MAX_PATH] = {0};
    if (ctx == NULL || ctx->dirs == NULL || ctx->files == NULL || ents == NULL || len == 0 || path == NULL) {
        return 0;
    }
    if (pgfs_path_normalize(path, norm, sizeof(norm)) != 0) {
        return 0;
    }
    if (!pgfs_dir_exists_norm(ctx, norm)) {
        return 0;
    }
    /* Pass 1: directories (child_is_dir = 1) */
    for (i = 0; i < ctx->dir_cap && out < len; i++) {
        char child[PGFS_MAX_PATH] = {0};
        int child_is_dir = 1;
        if (!ctx->dirs[i].used) continue;
        if (strcmp(ctx->dirs[i].path, norm) == 0) continue;
        if (pgfs_path_child(norm, ctx->dirs[i].path, child, sizeof(child), &child_is_dir) <= 0 || child[0] == '\0') continue;
        /* P2-9: dedup by scanning earlier entries instead of a heap buffer */
        if (pgfs_lsdir_name_is_duplicate(ctx, child, norm, i, (size_t)-1)) continue;
        unique_count++;
        if (unique_count <= offset) continue;
        memset(&ents[out], 0, sizeof(ents[out]));
        ents[out].d_type = 1;
        memcpy(ents[out].d_name, child, strlen(child) + 1);
        out++;
    }
    /* Pass 2: files (child_is_dir = 0) */
    for (i = 0; i < ctx->file_cap && out < len; i++) {
        char child[PGFS_MAX_PATH] = {0};
        int child_is_dir = 0;
        if (!ctx->files[i].used) continue;
        if (strcmp(ctx->files[i].path, norm) == 0) continue;
        if (pgfs_path_child(norm, ctx->files[i].path, child, sizeof(child), &child_is_dir) <= 0 || child[0] == '\0') continue;
        /* P2-9: dedup by scanning earlier entries instead of a heap buffer */
        if (pgfs_lsdir_name_is_duplicate(ctx, child, norm, (size_t)-1, i)) continue;
        unique_count++;
        if (unique_count <= offset) continue;
        memset(&ents[out], 0, sizeof(ents[out]));
        ents[out].d_type = 0;
        memcpy(ents[out].d_name, child, strlen(child) + 1);
        out++;
    }
    return (int)out;
}

typedef struct pgfs_dir_handle {
    uint32_t generation;
    char path[PGFS_MAX_PATH];
} pgfs_dir_handle_t;

static int pgfs_mode_is_write(const char* mode) {
    return mode && (strchr(mode, 'w') || strchr(mode, 'a') || strchr(mode, '+'));
}

static int pgfs_mode_is_read(const char* mode) {
    return mode && (strchr(mode, 'r') || strchr(mode, '+'));
}

static int pgfs_path_copy(char* out, size_t outlen, const char* in) {
    size_t len = 0;
    if (out == NULL || outlen == 0 || in == NULL) {
        return -1;
    }
    len = strlen(in);
    if (len >= outlen) {
        return -1;
    }
    memcpy(out, in, len + 1);
    return 0;
}

static void pgfs_batch_pending_reset_all(pgfs_mount_ctx_t* ctx) {
    size_t i = 0;
    if (ctx == NULL || ctx->batch_pending == NULL) {
        return;
    }
    for (i = 0; i < ctx->batch_pending_cap; i++) {
        if (ctx->batch_pending[i].data != NULL) {
            pgfs_heap_free_by_type(ctx->batch_pending[i].heap_type, ctx->batch_pending[i].data);
        }
        memset(&ctx->batch_pending[i], 0, sizeof(ctx->batch_pending[i]));
    }
}

static pgfs_batch_pending_entry_t* pgfs_batch_pending_find(pgfs_mount_ctx_t* ctx, uint32_t batch_id, const char* path) {
    size_t i = 0;
    if (ctx == NULL || ctx->batch_pending == NULL || path == NULL || path[0] == '\0') {
        return NULL;
    }
    for (i = 0; i < ctx->batch_pending_cap; i++) {
        if (ctx->batch_pending[i].used &&
            ctx->batch_pending[i].batch_id == batch_id &&
            strcmp(ctx->batch_pending[i].path, path) == 0) {
            return &ctx->batch_pending[i];
        }
    }
    return NULL;
}

static pgfs_batch_pending_entry_t* pgfs_batch_pending_alloc(pgfs_mount_ctx_t* ctx, uint32_t batch_id, const char* path) {
    size_t i = 0;
    pgfs_batch_pending_entry_t* p = NULL;
    if (ctx == NULL || ctx->batch_pending == NULL) {
        return NULL;
    }
    p = pgfs_batch_pending_find(ctx, batch_id, path);
    if (p != NULL) {
        return p;
    }
    for (i = 0; i < ctx->batch_pending_cap; i++) {
        if (!ctx->batch_pending[i].used) {
            memset(&ctx->batch_pending[i], 0, sizeof(ctx->batch_pending[i]));
            ctx->batch_pending[i].used = 1;
            ctx->batch_pending[i].batch_id = batch_id;
            if (pgfs_path_copy(ctx->batch_pending[i].path, sizeof(ctx->batch_pending[i].path), path) != 0) {
                memset(&ctx->batch_pending[i], 0, sizeof(ctx->batch_pending[i]));
                return NULL;
            }
            return &ctx->batch_pending[i];
        }
    }
    return NULL;
}

static int pgfs_batch_pending_stage(pgfs_mount_ctx_t* ctx, pgfs_file_t* f) {
    pgfs_batch_pending_entry_t* p = NULL;
    if (ctx == NULL || f == NULL || !f->opened_in_batch || !ctx->batch_active || f->batch_id != ctx->batch_id) {
        return -1;
    }
    p = pgfs_batch_pending_alloc(ctx, f->batch_id, f->path);
    if (p == NULL) {
        return -1;
    }
    if (p->data != NULL) {
        pgfs_heap_free_by_type(p->heap_type, p->data);
        p->data = NULL;
        p->len = 0;
        p->cap = 0;
        p->heap_type = (uint8_t)LUAT_HEAP_SRAM;
    }
    p->data = f->cache.data;
    p->len = f->cache.len;
    p->cap = f->cache.cap;
    p->heap_type = f->cache.heap_type;
    f->cache.data = NULL;
    f->cache.len = 0;
    f->cache.cap = 0;
    f->cache.heap_type = (uint8_t)LUAT_HEAP_SRAM;
    return 0;
}

static int pgfs_batch_persist_committed(pgfs_mount_ctx_t* ctx, uint32_t batch_id) {
    uint32_t record_count = 0;
    size_t i = 0;
    if (ctx == NULL || batch_id == 0) {
        return -1;
    }
    for (i = 0; i < ctx->batch_pending_cap; i++) {
        pgfs_batch_pending_entry_t* p = &ctx->batch_pending[i];
        if (!p->used || p->batch_id != batch_id) {
            continue;
        }
        if (pgfs_append_batch_data_record(ctx, p) != 0) {
            return -1;
        }
        record_count++;
    }
    if (pgfs_append_batch_commit_record(ctx, batch_id, record_count) != 0) {
        return -1;
    }
    ctx->checkpoint.written_blocks = (uint32_t)(ctx->checkpoint.written_blocks + record_count);
    if (record_count > 0) {
        pgfs_mark_checkpoint_pending(ctx);
    }
    return 0;
}

static int pgfs_batch_apply_committed(pgfs_mount_ctx_t* ctx, uint32_t batch_id) {
    size_t i = 0;
    if (ctx == NULL || ctx->batch_pending == NULL) {
        return -1;
    }
    for (i = 0; i < ctx->batch_pending_cap; i++) {
        pgfs_batch_pending_entry_t* p = &ctx->batch_pending[i];
        pgfs_file_entry_t* e = NULL;
        if (!p->used || p->batch_id != batch_id) {
            continue;
        }
        e = pgfs_alloc_file(ctx, p->path);
        if (e == NULL) {
            return -1;
        }
        /* P0-2: the old entry (if any) is shadowed — attribute dead bytes
         * to the block that held its previous record, and release its live
         * credit so GC can reclaim that block. */
        if (e->last_written_block != 0 && e->last_written_block != 0xFFFFu && e->len > 0 &&
            ctx->ftl.total_blocks > 0 && e->last_written_block < ctx->ftl.total_blocks) {
            if (ctx->ftl.dead_bytes_per_block != NULL) {
                ctx->ftl.dead_bytes_per_block[e->last_written_block] += (uint32_t)e->len;
            }
            if (ctx->ftl.live_bytes_per_block != NULL &&
                ctx->ftl.live_bytes_per_block[e->last_written_block] >= (uint32_t)e->len) {
                ctx->ftl.live_bytes_per_block[e->last_written_block] -= (uint32_t)e->len;
            }
            ctx->checkpoint.gc_dead_bytes += (uint32_t)e->len;
            pgfs_ftl_mark_dirty(&ctx->ftl);
        }
        if (e->data != NULL) {
            pgfs_heap_free_by_type(e->heap_type, e->data);
        }
        e->data = p->data;
        e->len = p->len;
        e->cap = p->cap;
        e->heap_type = p->heap_type;
        if (p->on_flash_addr != 0) {
            uint32_t esz = ctx->layout.erase_size != 0 ? ctx->layout.erase_size : ctx->ftl.erase_size;
            if (esz > 0) {
                uint32_t blk = p->on_flash_addr / esz;
                if (blk <= 0xFFFEu) {
                    e->last_written_block = (uint16_t)blk;
                }
            }
        }
        p->data = NULL;
        memset(p, 0, sizeof(*p));
    }
    return 0;
}

static void pgfs_batch_drop(pgfs_mount_ctx_t* ctx, uint32_t batch_id) {
    size_t i = 0;
    if (ctx == NULL || ctx->batch_pending == NULL) {
        return;
    }
    for (i = 0; i < ctx->batch_pending_cap; i++) {
        pgfs_batch_pending_entry_t* p = &ctx->batch_pending[i];
        if (!p->used || p->batch_id != batch_id) {
            continue;
        }
        if (p->data != NULL) {
            pgfs_heap_free_by_type(p->heap_type, p->data);
        }
        memset(p, 0, sizeof(*p));
    }
}

static int pgfs_batch_handle_match(pgfs_mount_ctx_t* ctx, pgfs_file_t* f) {
    if (ctx == NULL || f == NULL) {
        return 0;
    }
    if (f->opened_in_batch) {
        return ctx->batch_active && ctx->batch_id == f->batch_id;
    }
    return !ctx->batch_active;
}

static pgfs_file_entry_t* pgfs_alloc_file(pgfs_mount_ctx_t* ctx, const char* path) {
    size_t i = 0;
    pgfs_file_entry_t* e = NULL;
    if (ctx == NULL || ctx->files == NULL || path == NULL || path[0] == '\0') {
        return NULL;
    }
    if (pgfs_dir_exists_norm(ctx, path)) {
        return NULL;
    }
    e = pgfs_find_file_norm(ctx, path);
    if (e) {
        return e;
    }
    for (i = 0; i < ctx->file_cap; i++) {
        if (!ctx->files[i].used) {
            memset(&ctx->files[i], 0, sizeof(ctx->files[i]));
            ctx->files[i].used = 1;
            if (pgfs_path_copy(ctx->files[i].path, sizeof(ctx->files[i].path), path) != 0) {
                memset(&ctx->files[i], 0, sizeof(ctx->files[i]));
                return NULL;
            }
            pgfs_hash_insert(ctx->file_hash_slots, ctx->file_hash_cap, path, (uint32_t)i);
            return &ctx->files[i];
        }
    }
    return NULL;
}

void pgfs_file_reset(pgfs_mount_ctx_t* ctx) {
    /* P0-1: reset == full release. The tables are heap-allocated per
     * mount; any later use (replay, file ops) re-allocates them via
     * pgfs_tables_ensure. Keeping the arrays allocated here would leak
     * ~90KB per mount whenever a caller zeroes the ctx (as the test
     * suite does between cases). */
    pgfs_tables_deinit(ctx);
}

/* P4-16: fexist — check if a file or directory exists. Returns 1 if found. */
int pgfs_file_fexist(pgfs_mount_ctx_t* ctx, const char *filename) {
    char norm[PGFS_MAX_PATH] = {0};
    if (ctx == NULL || filename == NULL) return 0;
    if (pgfs_tables_ensure(ctx) != 0) return 0;
    if (pgfs_path_normalize(filename, norm, sizeof(norm)) != 0 || norm[0] == '\0') return 0;
    if (pgfs_find_file_norm(ctx, norm) != NULL) return 1;
    if (pgfs_dir_exists_norm(ctx, norm)) return 1;
    return 0;
}

/* P4-16: fsize — return file size from the in-memory file table. */
size_t pgfs_file_fsize(pgfs_mount_ctx_t* ctx, const char *filename) {
    pgfs_file_entry_t* e;
    char norm[PGFS_MAX_PATH] = {0};
    if (ctx == NULL || filename == NULL) return 0;
    if (pgfs_tables_ensure(ctx) != 0) return 0;
    if (pgfs_path_normalize(filename, norm, sizeof(norm)) != 0 || norm[0] == '\0') return 0;
    e = pgfs_find_file_norm(ctx, norm);
    return e ? e->len : 0;
}

int pgfs_file_remove(pgfs_mount_ctx_t* ctx, const char *filename) {
    pgfs_file_entry_t* e = NULL;
    char norm[PGFS_MAX_PATH] = {0};
    if (ctx == NULL || filename == NULL) {
        return -1;
    }
    if (pgfs_tables_ensure(ctx) != 0) {
        return -1;
    }
    if (pgfs_path_normalize(filename, norm, sizeof(norm)) != 0 || norm[0] == '\0') {
        return -1;
    }
    /* P1-6: acquire per-mount lock to protect the global file table
     * against concurrent open/close/remove operations. */
    if (ctx != NULL) {
        if (pgfs_lock(ctx) != 0) {
            return -1;
        }
    }
    e = pgfs_find_file_norm(ctx, norm);
    if (e == NULL) {
        if (ctx != NULL) { pgfs_unlock(ctx); }
        return -1;
    }
    /* Phase 2 GC: the file's live bytes are now dead. Attribute them
     * to the block the last DATA record landed in, and decrement the
     * live counter so the wrap-around / GC can identify truly free blocks. */
    if (ctx != NULL && e->last_written_block != 0 && e->last_written_block != 0xFFFFu &&
        e->len > 0 && e->last_written_block < ctx->ftl.total_blocks) {
        if (ctx->ftl.dead_bytes_per_block != NULL) {
            ctx->ftl.dead_bytes_per_block[e->last_written_block] += (uint32_t)e->len;
        }
        if (ctx->ftl.live_bytes_per_block != NULL &&
            ctx->ftl.live_bytes_per_block[e->last_written_block] >= (uint32_t)e->len) {
            ctx->ftl.live_bytes_per_block[e->last_written_block] -= (uint32_t)e->len;
        }
        ctx->checkpoint.gc_dead_bytes += (uint32_t)e->len;
        pgfs_ftl_mark_dirty(&ctx->ftl);
    }
    if (e->data) {
        pgfs_heap_free_by_type(e->heap_type, e->data);
    }
    {
        size_t idx = (size_t)(e - ctx->files);
        pgfs_hash_remove(ctx->file_hash_slots, ctx->file_hash_cap, norm, (uint32_t)idx);
    }
    memset(e, 0, sizeof(*e));
    if (ctx != NULL) { pgfs_unlock(ctx); }
    return 0;
}

uint16_t pgfs_file_table_lookup_last_written(pgfs_mount_ctx_t* ctx, const char* path) {
    pgfs_file_entry_t* e = NULL;
    char norm[PGFS_MAX_PATH] = {0};
    if (ctx == NULL || path == NULL) return 0xFFFFu;
    if (pgfs_tables_ensure(ctx) != 0) return 0xFFFFu;
    if (pgfs_path_normalize(path, norm, sizeof(norm)) != 0 || norm[0] == '\0') {
        return 0xFFFFu;
    }
    e = pgfs_find_file_norm(ctx, norm);
    if (e != NULL) {
        return e->last_written_block;
    }
    return 0xFFFFu;
}

int pgfs_file_table_visit(pgfs_mount_ctx_t* ctx, pgfs_file_visit_fn cb, void* user_data) {
    uint32_t i = 0;
    int stopped = 0;
    if (cb == NULL || ctx == NULL || ctx->files == NULL) return 0;
    for (i = 0; i < ctx->file_cap; i++) {
        if (!ctx->files[i].used) continue;
        if (cb(&ctx->files[i], user_data) != 0) {
            stopped = 1;
            break;
        }
    }
    return stopped;
}

static int pgfs_file_reserve(pgfs_file_entry_t* e, size_t need) {
    size_t target = 0;
    uint8_t* p = NULL;
    uint8_t heap_type = (uint8_t)LUAT_HEAP_SRAM;
    if (e == NULL) {
        return -1;
    }
    if (need <= e->cap) {
        return 0;
    }
    target = e->cap == 0 ? 256 : e->cap;
    while (target < need) {
        size_t next = target << 1;
        if (next <= target) {
            return -1;
        }
        target = next;
    }
    p = (uint8_t*)pgfs_heap_alloc_prefer_psram(target, &heap_type);
    if (!p) {
        LLOGE("file_reserve alloc failed path=%s need=%u target=%u old_cap=%u", e->path, (unsigned int)need, (unsigned int)target, (unsigned int)e->cap);
        return -1;
    }
    if (e->data != NULL && e->len > 0) {
        memcpy(p, e->data, e->len);
    }
    if (e->data != NULL) {
        pgfs_heap_free_by_type(e->heap_type, e->data);
    }
    e->data = p;
    e->heap_type = heap_type;
    e->cap = target;
    return 0;
}

static int pgfs_region_is_erased(pgfs_mount_ctx_t* ctx, uint32_t addr, size_t len, int* is_erased) {
    uint8_t tmp[64];
    size_t off = 0;
    if (ctx == NULL || is_erased == NULL || len == 0 || ctx->flash_opts == NULL || ctx->flash_opts->read == NULL) {
        return -1;
    }
    *is_erased = 1;
    while (off < len) {
        size_t n = (len - off) > sizeof(tmp) ? sizeof(tmp) : (len - off);
        size_t i = 0;
        if (ctx->flash_opts->read(ctx->flash_opts->ctx, addr + (uint32_t)off, tmp, n) != 0) {
            return -1;
        }
        for (i = 0; i < n; i++) {
            if (tmp[i] != 0xFFu) {
                *is_erased = 0;
                return 0;
            }
        }
        off += n;
    }
    return 0;
}

static int pgfs_prepare_data_log_region(pgfs_mount_ctx_t* ctx, uint32_t addr, size_t len) {
    pgfs_flash_geometry_t geo = {0};
    uint64_t end_addr = (uint64_t)addr + (uint64_t)len;
    uint32_t erase_end = 0;
    uint32_t erase_start = 0;
    uint32_t prepared_until = 0;
    int erased = 0;
    int probe_ret = 0;
    if (ctx == NULL || len == 0 || ctx->flash_opts == NULL || ctx->flash_opts->control == NULL || ctx->flash_opts->erase == NULL) {
        return -1;
    }
    if (ctx->flash_opts->control(ctx->flash_opts->ctx, PGFS_CTRL_GET_GEOMETRY, &geo) != 0 || geo.erase_size == 0) {
        LLOGE("prepare region geometry invalid erase_size=%u addr=%u", (unsigned int)geo.erase_size, (unsigned int)addr);
        return -1;
    }
    if (geo.capacity != 0 && end_addr > geo.capacity) {
        LLOGE("prepare region out-of-cap addr=%u len=%u end=%u cap=%u", (unsigned int)addr, (unsigned int)len, (unsigned int)end_addr, (unsigned int)geo.capacity);
        return -1;
    }
    if ((addr % geo.erase_size) != 0) {
        size_t probe_len = pgfs_program_size(ctx);
        if (probe_len > len) {
            probe_len = len;
        }
        probe_ret = pgfs_region_is_erased(ctx, addr, probe_len, &erased);
        if (probe_ret == 0 && !erased) {
            LLOGE("prepare region unaligned non-erased addr=%u len=%u", (unsigned int)addr, (unsigned int)probe_len);
            return -1;
        }
        if (probe_ret != 0) {
            LLOGW("prepare region unaligned probe read failed addr=%u len=%u, append without erase", (unsigned int)addr, (unsigned int)probe_len);
        }
        return 0;
    }

    erase_end = pgfs_align_up_u32((uint32_t)end_addr, geo.erase_size);
    if (erase_end == 0 || (geo.capacity != 0 && erase_end > geo.capacity)) {
        LLOGE("prepare region erase range invalid addr=%u len=%u erase_end=%u cap=%u", (unsigned int)addr, (unsigned int)len, (unsigned int)erase_end, (unsigned int)geo.capacity);
        return -1;
    }
    prepared_until = ctx->data_log_prepared_until;
    if (prepared_until < addr) {
        prepared_until = addr;
    }
    erase_start = pgfs_align_up_u32(prepared_until, geo.erase_size);
    if (erase_start < addr) {
        erase_start = addr;
    }
    if (erase_start >= erase_end) {
        ctx->data_log_prepared_until = erase_end;
        return 0;
    }
    /* Skip the FTL state erase-unit: erasing it would destroy the persisted
     * bad-block bitmap and erase counts. If the requested range crosses the
     * FTL state region, split the erase into two halves. */
    uint32_t ftl_state_addr = pgfs_ftl_state_addr(geo.erase_size);
    uint32_t ftl_state_end  = ftl_state_addr + geo.erase_size;
    if (ftl_state_addr != 0u && erase_start < ftl_state_end && erase_end > ftl_state_addr) {
        if (erase_start < ftl_state_addr) {
            uint32_t mid = (ftl_state_addr < erase_end) ? ftl_state_addr : erase_end;
            if (ctx->flash_opts->erase(ctx->flash_opts->ctx, erase_start, mid - erase_start) != 0) {
                LLOGE("prepare region erase (pre-FTL) failed addr=%u size=%u", (unsigned int)erase_start, (unsigned int)(mid - erase_start));
                return -1;
            }
        }
        if (ftl_state_end < erase_end) {
            if (ctx->flash_opts->erase(ctx->flash_opts->ctx, ftl_state_end, erase_end - ftl_state_end) != 0) {
                LLOGE("prepare region erase (post-FTL) failed addr=%u size=%u", (unsigned int)ftl_state_end, (unsigned int)(erase_end - ftl_state_end));
                return -1;
            }
        }
    } else {
        if (ctx->flash_opts->erase(ctx->flash_opts->ctx, erase_start, erase_end - erase_start) != 0) {
            LLOGE("prepare region erase failed addr=%u size=%u", (unsigned int)erase_start, (unsigned int)(erase_end - erase_start));
            return -1;
        }
    }
    ctx->data_log_prepared_until = erase_end;
    return 0;
}

static int pgfs_relocate_unaligned_write_head(pgfs_mount_ctx_t* ctx, uint32_t addr, size_t len, uint32_t* relocated_addr) {
    pgfs_flash_geometry_t geo = {0};
    uint32_t new_addr = 0;
    uint64_t end_addr = 0;
    uint64_t erase_end = 0;
    int erased = 0;
    if (ctx == NULL || relocated_addr == NULL || ctx->flash_opts == NULL ||
        ctx->flash_opts->control == NULL || ctx->flash_opts->erase == NULL) {
        LLOGE("relocate head invalid args");
        return -1;
    }
    if (ctx->flash_opts->control(ctx->flash_opts->ctx, PGFS_CTRL_GET_GEOMETRY, &geo) != 0 || geo.erase_size == 0) {
        LLOGE("relocate head get geometry failed");
        return -1;
    }
    if ((addr % geo.erase_size) == 0) {
        LLOGE("relocate head addr already aligned addr=%u", (unsigned int)addr);
        return -1;
    }
    new_addr = (uint32_t)(((uint64_t)addr + (uint64_t)geo.erase_size - 1u) / (uint64_t)geo.erase_size * (uint64_t)geo.erase_size);
    end_addr = (uint64_t)new_addr + (uint64_t)len;
    erase_end = (end_addr + (uint64_t)geo.erase_size - 1u) / (uint64_t)geo.erase_size * (uint64_t)geo.erase_size;
    if (erase_end > geo.capacity) {
        LLOGE("relocate head out-of-cap addr=%u new=%u len=%u erase_end=%u cap=%u", (unsigned int)addr, (unsigned int)new_addr, (unsigned int)len, (unsigned int)erase_end, (unsigned int)geo.capacity);
        return -1;
    }
    if (ctx->flash_opts->erase(ctx->flash_opts->ctx, new_addr, (uint32_t)(erase_end - new_addr)) != 0) {
        LLOGE("relocate head erase failed new=%u size=%u", (unsigned int)new_addr, (unsigned int)(erase_end - new_addr));
        return -1;
    }
    {
        int verify_ret = pgfs_region_is_erased(ctx, new_addr, len, &erased);
        if (verify_ret == 0 && !erased) {
            LLOGE("relocate head verify failed new=%u len=%u", (unsigned int)new_addr, (unsigned int)len);
            return -1;
        }
        if (verify_ret != 0) {
            LLOGW("relocate head verify read failed new=%u len=%u, continue", (unsigned int)new_addr, (unsigned int)len);
        }
    }
    *relocated_addr = new_addr;
    ctx->data_log_prepared_until = (uint32_t)erase_end;
    return 0;
}

static int pgfs_append_log_record(pgfs_mount_ctx_t* ctx, const uint8_t* hdr, size_t hdr_len,
                                  const uint8_t* path, uint32_t path_len,
                                  const uint8_t* data, uint32_t data_len) {
    size_t rec_len = 0;
    size_t write_len = 0;
    uint64_t end_addr = 0;
    pgfs_flash_geometry_t geo = {0};
    uint32_t addr = 0;
    int attempt = 0;
    if (ctx == NULL || hdr == NULL || hdr_len == 0 || ctx->flash_opts == NULL || ctx->flash_opts->write == NULL) {
        return -1;
    }
    if ((path_len != 0 && path == NULL) || (data_len != 0 && data == NULL)) {
        return -1;
    }
    rec_len = hdr_len + (size_t)path_len + (size_t)data_len;
    write_len = pgfs_record_storage_len(ctx, rec_len);
    if (write_len == 0 || write_len < rec_len) {
        return -1;
    }
    addr = ctx->data_log_write_addr;
retry_prepare:
    end_addr = (uint64_t)addr + (uint64_t)write_len;
    if (ctx->flash_opts->control != NULL &&
        ctx->flash_opts->control(ctx->flash_opts->ctx, PGFS_CTRL_GET_GEOMETRY, &geo) == 0 &&
        geo.capacity > pgfs_data_log_base_addr(ctx) &&
        end_addr > geo.capacity) {
        /* Wrap-around: the write head reached the end of flash. Find a
         * free block in the data log area (one with no live data) and
         * restart the append from there. This is the core mechanism that
         * keeps the filesystem usable indefinitely — without it, the FS
         * becomes permanently full after the first pass through flash. */
        uint32_t erase_size = ctx->layout.erase_size;
        if (erase_size == 0) erase_size = ctx->ftl.erase_size;
        uint32_t wrapped_addr = 0;
        int found = 0;
        if (erase_size > 0 && ctx->ftl.total_blocks > 0) {
            uint32_t first_block = ctx->layout.data_log_first_block;
            uint32_t last_block = ctx->layout.data_log_last_block;
            /* Fallback when layout is not populated (e.g. C unit tests
             * that bypass the VFS adapter mount path). */
            if (first_block == 0 && last_block == 0) {
                first_block = PGFS_LAYOUT_RESERVED_BLOCKS;
                last_block = ctx->ftl.total_blocks - 1u;
            }
            for (uint32_t blk = first_block; blk <= last_block; blk++) {
                if (pgfs_ftl_is_block_bad(&ctx->ftl, blk)) continue;
                if (pgfs_ftl_is_reserved(&ctx->ftl, blk)) continue;
                if (pgfs_ftl_is_retired(&ctx->ftl, blk)) continue;
                /* A block with zero live bytes has no current data —
                 * all its records have been shadowed or deleted.
                 * Also accept blocks where dead >= live (all data has
                 * been invalidated but accounting noise remains from
                 * header/path/padding overhead). */
                if (ctx->ftl.live_bytes_per_block != NULL &&
                    ctx->ftl.live_bytes_per_block[blk] > 0) {
                    uint32_t dead = (ctx->ftl.dead_bytes_per_block != NULL)
                        ? ctx->ftl.dead_bytes_per_block[blk] : 0u;
                    if (dead < ctx->ftl.live_bytes_per_block[blk]) continue;
                }
                wrapped_addr = blk * erase_size;
                if (wrapped_addr + write_len <= geo.capacity) {
                    found = 1;
                    break;
                }
            }
        }
        if (!found) {
            LLOGE("append_data out-of-cap and no free block for wrap addr=%u write_len=%u cap=%u",
                  (unsigned int)addr, (unsigned int)write_len, (unsigned int)geo.capacity);
            return -1;
        }
        LLOGI("append_data wrap-around: %u -> %u", (unsigned int)addr, (unsigned int)wrapped_addr);
        addr = wrapped_addr;
        ctx->data_log_write_addr = wrapped_addr;
        ctx->data_log_prepared_until = wrapped_addr;
        goto retry_prepare;
    }
    if (pgfs_prepare_data_log_region(ctx, addr, write_len) != 0) {
        if (attempt < 1 && pgfs_relocate_unaligned_write_head(ctx, addr, write_len, &addr) == 0) {
            attempt++;
            LLOGW("append_data relocate write head to %u", (unsigned int)addr);
            goto retry_prepare;
        }
        return -1;
    }
    /* Powercut injection: fail right after the region is prepared (erased)
     * but before any record is written. Recovery should see a clean erased
     * region and advance the write head without committing a record. */
    if (ctx->inject_powercut_stage == PGFS_INJECT_POWERCUT_AFTER_APPEND_ERASE) {
        ctx->inject_powercut_stage = PGFS_INJECT_POWERCUT_NONE;
        ctx->stats.powercut_inject_count++;
        LLOGW("append_data: powercut injected after prepare, before write");
        return -1;
    }
    if (ctx->flash_opts->write(ctx->flash_opts->ctx, addr, hdr, hdr_len) != 0 ||
        (path_len != 0 && ctx->flash_opts->write(ctx->flash_opts->ctx, addr + (uint32_t)hdr_len, path, path_len) != 0) ||
        (data_len != 0 && ctx->flash_opts->write(ctx->flash_opts->ctx, addr + (uint32_t)hdr_len + path_len, data, data_len) != 0)) {
        /* Notify FTL that the block at addr may be suspect — a write failure
         * often means the block has bad pages. This propagates a bad-block
         * mark so the next allocation skips it. */
        if (ctx->flash_opts->control != NULL &&
            ctx->flash_opts->control(ctx->flash_opts->ctx, PGFS_CTRL_GET_GEOMETRY, &geo) == 0 &&
            geo.erase_size != 0) {
            uint32_t bad_block = addr / geo.erase_size;
            if (bad_block < ctx->ftl.total_blocks) {
                pgfs_ftl_on_erase_failure(ctx, bad_block);
            }
            /* Single retry: relocate to next block. */
            if (attempt < 1) {
                uint32_t next_addr = pgfs_align_up_u32(addr + 1u, geo.erase_size);
                uint64_t next_end = (uint64_t)next_addr + (uint64_t)write_len;
                if (next_addr > addr && (geo.capacity == 0 || next_end <= geo.capacity)) {
                    LLOGW("append_data write failed at addr=%u, retry next block=%u (attempt=%d)",
                          (unsigned int)addr, (unsigned int)next_addr, attempt + 1);
                    addr = next_addr;
                    ctx->data_log_prepared_until = next_addr;
                    attempt++;
                    goto retry_prepare;
                }
            }
        }
        return -1;
    }
    ctx->data_log_write_addr = (uint32_t)end_addr;
    return 0;
}

/* pgfs_append_data_record — append a DATA record to the data log using
 * the cached entry from a `pgfs_file_t`. Phase 2 GC reuses this to
 * re-write live records out of a victim block. Exposed (non-static)
 * so the GC in pgfs_alloc_gc.c can call it through the visitor
 * pattern. */
int pgfs_append_data_record(pgfs_mount_ctx_t* ctx, pgfs_file_t* f) {
    pgfs_data_record_hdr_t hdr = {0};
    uint32_t start_addr = 0;
    if (ctx == NULL || f == NULL || f->entry == NULL || f->cache.len == 0) {
        return -1;
    }
    if (ctx->inject_bad_block_once) {
        ctx->inject_bad_block_once = 0;
        ctx->stats.badblock_inject_count++;
        return -1;
    }
    hdr.magic = PGFS_DATA_RECORD_MAGIC;
    hdr.path_len = (uint32_t)strlen(f->entry->path);
    hdr.data_len = (uint32_t)f->cache.len;
    /* CRC scope: header up to and including crc32 (excludes the ecc
     * field at bytes 16..23, otherwise the ECC write would invalidate
     * the stored CRC). */
    hdr.crc32 = luat_crc32(&hdr, offsetof(pgfs_data_record_hdr_t, crc32), 0xFFFFFFFFu, 0);
    hdr.crc32 = luat_crc32((const uint8_t*)f->entry->path, hdr.path_len, hdr.crc32, 0);
    if (hdr.data_len != 0) {
        hdr.crc32 = luat_crc32(f->cache.data, hdr.data_len, hdr.crc32, 0);
    }
    /* P2-4: Hamming(72,64) ECC over the first 16 header bytes — group 0
     * covers magic..data_len (bytes 0..7), group 1 covers data_len+crc32
     * (bytes 8..15). The ecc field is zeroed first so both encodes see a
     * clean input. Legacy single-group records (ecc[1]==0) remain
     * decodable on replay. */
    memset(hdr.ecc, 0, sizeof(hdr.ecc));
    hdr.ecc[0] = pgfs_ecc_hamming_encode((const uint8_t*)&hdr);
    hdr.ecc[1] = pgfs_ecc_hamming_encode((const uint8_t*)&hdr + 8);
    start_addr = ctx->data_log_write_addr;
    int ret = pgfs_append_log_record(ctx, (const uint8_t*)&hdr, sizeof(hdr),
                                     (const uint8_t*)f->entry->path, hdr.path_len,
                                     f->cache.data, hdr.data_len);
    if (ret == 0) {
        /* Phase 2 prep: account for the live bytes this record contributes
         * to its block. The block_id is derivable from the start address
         * (which may differ from start_addr if append_log_record relocated
         * the write head). */
        size_t rec_len = sizeof(hdr) + hdr.path_len + hdr.data_len;
        (void)rec_len;
        uint32_t written_block = ctx->data_log_write_addr;
        /* Approximate: the record spans at most two erase blocks. We
         * attribute the whole live contribution to the block containing
         * the START of the record — the trailing-page cost (when the
         * record crosses a block boundary) is negligible and the GC
         * victim selection tolerates small per-block noise. */
        if (start_addr < ctx->data_log_write_addr) {
            pgfs_account_live_block(ctx, start_addr, (uint32_t)(ctx->data_log_write_addr - start_addr));
        }
        /* Phase 2 GC: remember which block this file's most recent
         * record landed in. The file-close and file-delete paths use
         * this to attribute the OLD data's dead bytes to the right
         * block when the file is rewritten or removed. */
        if (ctx->flash_opts && ctx->flash_opts->control) {
            pgfs_flash_geometry_t geo = {0};
            if (ctx->flash_opts->control(ctx->flash_opts->ctx,
                                         PGFS_CTRL_GET_GEOMETRY, &geo) == 0 &&
                geo.erase_size > 0) {
                uint32_t block_id = start_addr / geo.erase_size;
                if (block_id <= 0xFFFEu) {
                    f->entry->last_written_block = (uint16_t)block_id;
                }
            }
        }
        (void)written_block;
    }
    return ret;
}

/* P2-11a: pgfs_compact_live_entries removed. The cost-benefit GC data-move
 * path (pgfs_gc_step + pgfs_gc_rewrite_victim) safely reclaims blocks
 * without erasing the entire data log. */

static int pgfs_append_batch_data_record(pgfs_mount_ctx_t* ctx, pgfs_batch_pending_entry_t* p) {
    pgfs_batch_data_record_hdr_t hdr = {0};
    uint32_t start_addr = 0;
    if (ctx == NULL || p == NULL || !p->used || p->batch_id == 0) {
        return -1;
    }
    hdr.magic = PGFS_BATCH_DATA_RECORD_MAGIC;
    hdr.path_len = (uint32_t)strlen(p->path);
    hdr.data_len = (uint32_t)p->len;
    hdr.batch_id = p->batch_id;
    /* Phase 3b: CRC scope is hdr[0..11] (magic..crc32, excluding ecc)
     * plus path plus data — same as pgfs_append_data_record. The replay
     * chains the CRC across this same prefix, so the two sides must
     * stay in sync. */
    hdr.crc32 = luat_crc32(&hdr, offsetof(pgfs_batch_data_record_hdr_t, crc32), 0xFFFFFFFFu, 0);
    if (hdr.path_len != 0) {
        hdr.crc32 = luat_crc32((const uint8_t*)p->path, hdr.path_len, hdr.crc32, 0);
    }
    if (hdr.data_len != 0) {
        hdr.crc32 = luat_crc32(p->data, hdr.data_len, hdr.crc32, 0);
    }
    memset(hdr.ecc, 0, sizeof(hdr.ecc));
    /* P2-4: three ECC groups — bytes 0..7, 8..15 and 16..23 (crc32 plus
     * the first four ecc bytes). ecc[2] is computed last so it covers the
     * already-set ecc[0]/ecc[1]; replay decodes groups in reverse order
     * so an ecc-byte correction propagates to lower groups. */
    hdr.ecc[0] = pgfs_ecc_hamming_encode((const uint8_t*)&hdr);
    hdr.ecc[1] = pgfs_ecc_hamming_encode((const uint8_t*)&hdr + 8);
    {
        /* P2-4 group 2: encode the crc32 (4 bytes) + 4 zero bytes — the
         * ecc bytes must not pollute their own syndrome. This matches the
         * decode window in pgfs_ecc_decode_header(). */
        uint8_t win[8] = {0};
        memcpy(win, &hdr.crc32, 4);
        hdr.ecc[2] = pgfs_ecc_hamming_encode(win);
    }
    start_addr = ctx->data_log_write_addr;
    int ret = pgfs_append_log_record(ctx, (const uint8_t*)&hdr, sizeof(hdr),
                                     (const uint8_t*)p->path, hdr.path_len,
                                     p->data, hdr.data_len);
    if (ret == 0) {
        p->on_flash_addr = start_addr;
        /* P0-2: credit live bytes to the block holding the record start. */
        if (ctx->data_log_write_addr > start_addr) {
            pgfs_account_live_block(ctx, start_addr,
                                    (uint32_t)(ctx->data_log_write_addr - start_addr));
        }
    }
    return ret;
}

static int pgfs_append_batch_commit_record(pgfs_mount_ctx_t* ctx, uint32_t batch_id, uint32_t record_count) {
    pgfs_batch_commit_record_hdr_t hdr = {0};
    if (ctx == NULL || batch_id == 0) {
        return -1;
    }
    hdr.magic = PGFS_BATCH_COMMIT_RECORD_MAGIC;
    hdr.batch_id = batch_id;
    hdr.record_count = record_count;
    /* P2-4: two ECC groups over bytes 0..7 and 8..15 (record_count +
     * crc32). The ecc field is zeroed so the encodes see clean input. */
    memset(hdr.ecc, 0, sizeof(hdr.ecc));
    hdr.ecc[0] = pgfs_ecc_hamming_encode((const uint8_t*)&hdr);
    hdr.ecc[1] = pgfs_ecc_hamming_encode((const uint8_t*)&hdr + 8);
    /* CRC must NOT include the ecc field (bytes 16..23) — otherwise setting
     * the ecc above would invalidate the stored CRC. Scope is bytes
     * 0..15 (i.e. up to and including crc32, excluding ecc). */
    hdr.crc32 = pgfs_crc32_calc(&hdr, offsetof(pgfs_batch_commit_record_hdr_t, crc32));
    return pgfs_append_log_record(ctx, (const uint8_t*)&hdr, sizeof(hdr), NULL, 0, NULL, 0);
}

static int pgfs_replay_flash_read(pgfs_mount_ctx_t* ctx, uint32_t addr, void* buf, size_t len) {
    if (ctx == NULL || ctx->flash_opts == NULL || ctx->flash_opts->read == NULL || buf == NULL || len == 0) {
        return -1;
    }
    return ctx->flash_opts->read(ctx->flash_opts->ctx, addr, (uint8_t*)buf, len);
}

typedef struct pgfs_replay_pending_entry {
    uint8_t used;
    uint8_t heap_type;
    uint16_t reserved;
    uint32_t batch_id;
    char path[PGFS_MAX_PATH];
    uint8_t* data;
    uint32_t len;
    /* P0-2: on-flash address of the BATCH_DATA record, used to attribute
     * live bytes to its block when the batch is applied during replay. */
    uint32_t on_flash_addr;
} pgfs_replay_pending_entry_t;

static void pgfs_replay_pending_drop_all(pgfs_replay_pending_entry_t* pending) {
    size_t i = 0;
    if (pending == NULL) {
        return;
    }
    for (i = 0; i < PGFS_MAX_BATCH_PENDING; i++) {
        pgfs_replay_pending_entry_t* p = &pending[i];
        if (p->data != NULL) {
            pgfs_heap_free_by_type(p->heap_type, p->data);
        }
        memset(p, 0, sizeof(*p));
    }
}

static int pgfs_replay_pending_stage(pgfs_replay_pending_entry_t* pending, uint32_t batch_id,
                                     const char* path, const uint8_t* data, uint32_t len,
                                     uint32_t on_flash_addr) {
    size_t i = 0;
    pgfs_replay_pending_entry_t* slot = NULL;
    uint8_t* data_copy = NULL;
    uint8_t heap_type = (uint8_t)LUAT_HEAP_SRAM;
    if (pending == NULL || batch_id == 0 || path == NULL || path[0] == '\0') {
        return -1;
    }
    for (i = 0; i < PGFS_MAX_BATCH_PENDING; i++) {
        if (pending[i].used && pending[i].batch_id == batch_id && strcmp(pending[i].path, path) == 0) {
            slot = &pending[i];
            break;
        }
    }
    if (slot == NULL) {
        for (i = 0; i < PGFS_MAX_BATCH_PENDING; i++) {
            if (!pending[i].used) {
                slot = &pending[i];
                break;
            }
        }
    }
    if (slot == NULL) {
        return -1;
    }
    if (len > 0) {
        data_copy = (uint8_t*)pgfs_heap_alloc_prefer_psram(len, &heap_type);
        if (data_copy == NULL) {
            return -1;
        }
        memcpy(data_copy, data, len);
    }
    if (slot->data != NULL) {
        pgfs_heap_free_by_type(slot->heap_type, slot->data);
    }
    memset(slot, 0, sizeof(*slot));
    slot->used = 1;
    slot->batch_id = batch_id;
    slot->heap_type = heap_type;
    slot->len = len;
    slot->data = data_copy;
    slot->on_flash_addr = on_flash_addr;
    if (pgfs_path_copy(slot->path, sizeof(slot->path), path) != 0) {
        if (slot->data != NULL) {
            pgfs_heap_free_by_type(slot->heap_type, slot->data);
        }
        memset(slot, 0, sizeof(*slot));
        return -1;
    }
    return 0;
}

static int pgfs_replay_pending_apply(pgfs_mount_ctx_t* ctx, pgfs_replay_pending_entry_t* pending, uint32_t batch_id) {
    size_t i = 0;
    if (ctx == NULL || pending == NULL || batch_id == 0) {
        return -1;
    }
    for (i = 0; i < PGFS_MAX_BATCH_PENDING; i++) {
        pgfs_replay_pending_entry_t* p = &pending[i];
        pgfs_file_entry_t* entry = NULL;
        size_t old_len = 0;
        char parent[PGFS_MAX_PATH] = {0};
        if (!p->used || p->batch_id != batch_id) {
            continue;
        }
        if (pgfs_path_parent(p->path, parent, sizeof(parent)) != 0 || pgfs_dir_ensure_norm(ctx, parent) != 0) {
            return -1;
        }
        entry = pgfs_alloc_file(ctx, p->path);
        if (entry == NULL) {
            return -1;
        }
        old_len = entry->len;
        /* P0-2: attribute the BATCH_DATA record's live bytes to the block
         * holding its on-flash start address (mirrors the DATA append
         * path so per-block accounting is complete for batches too). */
        if (p->on_flash_addr != 0) {
            pgfs_account_live_block(ctx, p->on_flash_addr,
                                    sizeof(pgfs_batch_data_record_hdr_t) +
                                    (uint32_t)strlen(p->path) + p->len);
        }
        if (entry->data != NULL) {
            pgfs_heap_free_by_type(entry->heap_type, entry->data);
        }
        entry->data = p->data;
        entry->len = p->len;
        entry->cap = p->len;
        entry->heap_type = p->heap_type;
        if (p->on_flash_addr != 0) {
            uint32_t esz = ctx->layout.erase_size != 0 ? ctx->layout.erase_size : ctx->ftl.erase_size;
            if (esz > 0) {
                uint32_t blk = p->on_flash_addr / esz;
                if (blk <= 0xFFFEu) {
                    entry->last_written_block = (uint16_t)blk;
                }
            }
        }
        p->data = NULL;
        ctx->checkpoint.gc_live_bytes += entry->len;
        if (old_len > 0) {
            ctx->checkpoint.gc_dead_bytes += (uint32_t)old_len;
            /* P0-2: shadow the old record — release its live credit and
             * attribute dead bytes to the old block. */
            uint16_t old_blk = entry->last_written_block;
            if (old_blk != 0 && old_blk != 0xFFFFu &&
                ctx->ftl.dead_bytes_per_block != NULL &&
                old_blk < ctx->ftl.total_blocks) {
                ctx->ftl.dead_bytes_per_block[old_blk] += (uint32_t)old_len;
                if (ctx->ftl.live_bytes_per_block != NULL &&
                    ctx->ftl.live_bytes_per_block[old_blk] >= (uint32_t)old_len) {
                    ctx->ftl.live_bytes_per_block[old_blk] -= (uint32_t)old_len;
                }
                pgfs_ftl_mark_dirty(&ctx->ftl);
            }
        }
        ctx->checkpoint.written_blocks += 1u;
        memset(p, 0, sizeof(*p));
    }
    return 0;
}

static int pgfs_replay_pending_has_entries(const pgfs_replay_pending_entry_t* pending) {
    size_t i = 0;
    if (pending == NULL) {
        return 0;
    }
    for (i = 0; i < PGFS_MAX_BATCH_PENDING; i++) {
        if (pending[i].used) {
            return 1;
        }
    }
    return 0;
}

static int pgfs_replay_try_resync_in_block(pgfs_mount_ctx_t* ctx,
                                           uint32_t addr,
                                           uint32_t limit,
                                           const pgfs_flash_geometry_t* geo,
                                           uint32_t* out_addr) {
    uint32_t prog = 1u;
    uint32_t block_end = 0u;
    uint32_t probe = 0u;
    if (ctx == NULL || geo == NULL || out_addr == NULL || geo->erase_size == 0u) {
        return -1;
    }
    if (geo->prog_size > 0u) {
        prog = geo->prog_size;
    }
    block_end = pgfs_align_up_u32(addr + 1u, geo->erase_size);
    if (block_end <= addr) {
        return -1;
    }
    if (limit != 0u && block_end > limit) {
        block_end = limit;
    }
    probe = addr + prog;
    while (probe + sizeof(uint32_t) <= block_end) {
        uint32_t probe_magic = 0u;
        if (pgfs_replay_flash_read(ctx, probe, &probe_magic, sizeof(probe_magic)) == 0) {
            if (probe_magic == PGFS_DATA_RECORD_MAGIC ||
                probe_magic == PGFS_BATCH_DATA_RECORD_MAGIC ||
                probe_magic == PGFS_BATCH_COMMIT_RECORD_MAGIC) {
                *out_addr = probe;
                return 0;
            }
        }
        if (probe > 0xFFFFFFFFu - prog) {
            break;
        }
        probe += prog;
    }
    return -1;
}

static int pgfs_replay_recover_after_corrupt_record(pgfs_mount_ctx_t* ctx,
                                                     uint32_t addr,
                                                     uint32_t limit,
                                                     const pgfs_flash_geometry_t* geo,
                                                     uint32_t* out_addr) {
    uint32_t next_block = 0u;
    if (ctx == NULL || geo == NULL || out_addr == NULL) {
        return 0;
    }
    if (pgfs_replay_try_resync_in_block(ctx, addr, limit, geo, out_addr) == 0) {
        LLOGW("replay resync after corrupt record at addr=%u -> %u",
              (unsigned int)addr, (unsigned int)*out_addr);
        return 1;
    }
    if (geo->erase_size > 0u) {
        next_block = pgfs_align_up_u32(addr + 1u, geo->erase_size);
        if (next_block > addr && (limit == 0u || next_block < limit)) {
            LLOGW("replay skip block after corrupt record at addr=%u next_block=%u",
                  (unsigned int)addr, (unsigned int)next_block);
            *out_addr = next_block;
            return 1;
        }
    }
    return 0;
}

/* P2-4: decode ECC groups (reverse order so a correction to the ecc bytes
 * themselves propagates into the parity source of lower groups). Each
 * group covers 8 bytes starting at 8*g; the parity byte lives at
 * hdr[ecc_offset + g]. A zero parity means the group was not written
 * (legacy single-group record) and is skipped. Group 2 (BATCH_DATA) uses
 * a masked 8-byte window: crc32 (4 bytes) + 4 zero bytes, because the
 * ecc field must not pollute its own syndrome. Returns 1 if any data was
 * corrected; sets *weak when any group is uncorrectable (double-bit). */
static int pgfs_ecc_decode_header(uint8_t* hdr, uint32_t ecc_offset,
                                  uint32_t group_count, int* weak) {
    int corrected_any = 0;
    int g = 0;
    for (g = (int)group_count - 1; g >= 0; g--) {
        uint8_t parity = 0;
        uint8_t win[8] = {0};
        uint8_t corrected[8] = {0};
        int res = 0;
        parity = hdr[ecc_offset + (uint32_t)g];
        if (parity == 0) {
            continue;
        }
        if (g == 2) {
            /* BATCH_DATA group 2: window is crc32 + 4 zero bytes. */
            memcpy(win, hdr + 16, 4);
        }
        else {
            memcpy(win, hdr + 8u * (uint32_t)g, 8);
        }
        res = pgfs_ecc_hamming_decode(win, parity, corrected);
        if (res == 1) {
            if (g == 2) {
                memcpy(hdr + 16, corrected, 4);
            }
            else {
                memcpy(hdr + 8u * (uint32_t)g, corrected, 8);
            }
            corrected_any = 1;
        }
        else if (res < 0) {
            if (weak != NULL) {
                *weak = 1;
            }
        }
    }
    return corrected_any;
}

int pgfs_replay_data_log(pgfs_mount_ctx_t* ctx) {
    pgfs_flash_geometry_t geo = {0};
    /* Use the explicit ctx->data_log_base_addr rather than
     * pgfs_data_log_base_addr(ctx): the helper derives the base from
     * ctx->layout, which the unit tests don't populate (they set the
     * field directly). Comparing against the helper's result would
     * treat write_addr > 0 as a durable-bound even when write_addr
     * itself is the data log base, prematurely breaking the scan
     * before the very first record is reached. */
    uint32_t base = ctx->data_log_base_addr;
    uint32_t addr = base;
    uint32_t limit = 0;
    /* v2 layout: if the mount ctx restored data_log_write_addr from the
     * CP's log_tail_*, cap the scan at that point so orphan records
     * written past the last committed CP (e.g. a close() that crashed
     * before checkpoint commit, leaving a record in the log but no CP
     * entry pointing at it) do not get re-applied to the file table on
     * remount / reset_runtime. When data_log_write_addr is still at the
     * base (no CP was loaded or its log_tail_* are zero), fall back to
     * the full capacity scan used by the legacy replay path. */
    uint32_t durable_limit = 0;
    pgfs_replay_pending_entry_t pending[PGFS_MAX_BATCH_PENDING];
    int ret = 0;
    /* P2-7: Pre-allocated replay buffers to eliminate per-record
     * malloc/free. path_buf holds the record path (max 96 bytes),
     * data_buf grows on demand to hold the largest record payload
     * seen during this replay. Both are freed once at cleanup. */
    #define PGFS_REPLAY_PATH_BUF_SIZE PGFS_MAX_PATH
    #define PGFS_REPLAY_DATA_INIT_CAP 4096u
    #define PGFS_REPLAY_DATA_MAX_CAP  (256u * 1024u)
    uint8_t* replay_path_buf = NULL;
    uint8_t* replay_data_buf = NULL;
    size_t replay_data_cap = 0;

    if (ctx == NULL || ctx->flash_opts == NULL || ctx->flash_opts->read == NULL) {
        return -1;
    }
    if (pgfs_tables_ensure(ctx) != 0) {
        return -1;
    }
    memset(pending, 0, sizeof(pending));

    replay_path_buf = (uint8_t*)luat_heap_malloc(PGFS_REPLAY_PATH_BUF_SIZE);
    if (replay_path_buf == NULL) {
        return -1;
    }

    ctx->checkpoint.written_blocks = 0;
    ctx->checkpoint.gc_live_bytes = 0;
    ctx->checkpoint.gc_dead_bytes = 0;

    if (ctx->flash_opts->control != NULL &&
        ctx->flash_opts->control(ctx->flash_opts->ctx, PGFS_CTRL_GET_GEOMETRY, &geo) == 0 &&
        geo.capacity > base) {
        limit = geo.capacity;
    }
    else {
        limit = 0;
    }
    if (ctx->data_log_write_addr > base) {
        durable_limit = ctx->data_log_write_addr;
    }
    while (1) {
        uint32_t magic = 0;
        uint32_t path_len = 0;
        uint32_t data_len = 0;
        uint32_t batch_id = 0;
        uint32_t crc32 = 0;
        size_t hdr_len = 0;
        /* Phase 3b: the on-disk CRC covers the bytes of the header that
         * precede the crc32 field (magic..data_len for DATA records,
         * magic..batch_id for BATCH_DATA records — 12 bytes in both
         * cases) plus the path plus the data. The ECC verify step
         * above has already zeroed the in-memory ecc[8] field, so
         * copying those prefix bytes into a stable buffer lets the
         * replay chain the CRC correctly. */
        uint8_t hdr_prefix[16] = {0};
        char norm[PGFS_MAX_PATH] = {0};
        char parent[PGFS_MAX_PATH] = {0};
        /* P2-7: use pre-allocated replay buffers instead of per-record malloc */
        uint8_t* path_buf = replay_path_buf;
        uint8_t* data_buf = NULL;
        uint64_t record_len = 0;
        size_t storage_len = 0;
        uint64_t next_addr = 0;
        uint32_t crc = 0;
        size_t crc_len = 0;
        pgfs_file_entry_t* entry = NULL;
        size_t old_len = 0;

        if (limit != 0 && addr + sizeof(magic) > limit) {
            break;
        }
        /* v2 durable-bound: stop once we cross the persisted log_tail
         * (see durable_limit setup above). Anything past it is orphan
         * data from a close() that did not reach a successful CP commit. */
        if (durable_limit != 0 && addr >= durable_limit) {
            break;
        }
        if (pgfs_replay_flash_read(ctx, addr, &magic, sizeof(magic)) != 0) {
            /* ECC failure or hardware read error: skip to next block boundary so records
             * written to later blocks are not lost (e.g., NAND bad-page at end of block). */
            if (pgfs_replay_pending_has_entries(pending) || (limit != 0u && geo.erase_size > 0u &&
                pgfs_align_up_u32(addr + 1u, geo.erase_size) >= limit)) {
                uint32_t resync_addr = 0u;
                if (pgfs_replay_try_resync_in_block(ctx, addr, limit, &geo, &resync_addr) == 0) {
                    LLOGW("replay resync after read failure at addr=%u -> %u",
                          (unsigned int)addr, (unsigned int)resync_addr);
                    addr = resync_addr;
                    continue;
                }
            }
            if (geo.erase_size > 0) {
                uint32_t next_block = pgfs_align_up_u32(addr + 1u, geo.erase_size);
                if (next_block > addr && (limit == 0u || next_block < limit)) {
                    LLOGW("replay skip bad block read failure at addr=%u next_block=%u",
                          (unsigned int)addr, (unsigned int)next_block);
                    addr = next_block;
                    continue;
                }
            }
            break;
        }
        if (magic == PGFS_DATA_RECORD_MAGIC) {
            pgfs_data_record_hdr_t hdr = {0};
            if (limit != 0 && addr + sizeof(hdr) > limit) {
                break;
            }
            if (pgfs_replay_flash_read(ctx, addr, &hdr, sizeof(hdr)) != 0) {
                if (pgfs_replay_recover_after_corrupt_record(ctx, addr, limit, &geo, &addr)) {
                    continue;
                }
                break;
            }
            /* P2-4: ECC verify over groups (bytes 0..7 and 8..15).
             * Single-bit errors are silently corrected; uncorrectable
             * groups mark the block weak but the record is still passed
             * to the authoritative CRC check below. A zero parity byte
             * means the group was not written (legacy record) and is
             * skipped. */
            {
                int ecc_weak = 0;
                if (pgfs_ecc_decode_header((uint8_t*)&hdr, 16u, 2u, &ecc_weak) == 1) {
                    LLOGW("replay: ECC corrected single-bit error at addr=%u", (unsigned int)addr);
                }
                if (ecc_weak) {
                    LLOGW("replay: ECC mismatch at addr=%u (block weak, continuing)", (unsigned int)addr);
                    uint32_t blk = addr / geo.erase_size;
                    if (blk < ctx->ftl.total_blocks) {
                        pgfs_ftl_mark_weak(&ctx->ftl, blk);
                    }
                }
            }
            path_len = hdr.path_len;
            data_len = hdr.data_len;
            crc32 = hdr.crc32;
            hdr_len = sizeof(hdr);
            /* P2-4: keep the (corrected) prefix bytes the producer
             * hashed for the CRC chain below. */
            memcpy(hdr_prefix, &hdr, offsetof(pgfs_data_record_hdr_t, crc32));
        }
        else if (magic == PGFS_BATCH_DATA_RECORD_MAGIC) {
            pgfs_batch_data_record_hdr_t hdr = {0};
            if (limit != 0 && addr + sizeof(hdr) > limit) {
                break;
            }
            if (pgfs_replay_flash_read(ctx, addr, &hdr, sizeof(hdr)) != 0) {
                if (pgfs_replay_recover_after_corrupt_record(ctx, addr, limit, &geo, &addr)) {
                    continue;
                }
                break;
            }
            /* P2-4: three ECC groups (bytes 0..7, 8..15, and crc32 via
             * the masked 16..19 window). Like DATA records, an ECC
             * mismatch marks the block weak and continues to the CRC
             * verdict instead of skipping the record outright. */
            {
                int ecc_weak = 0;
                if (pgfs_ecc_decode_header((uint8_t*)&hdr, 20u, 3u, &ecc_weak) == 1) {
                    LLOGW("replay: ECC corrected single-bit error at addr=%u", (unsigned int)addr);
                }
                if (ecc_weak) {
                    LLOGW("replay: ECC mismatch at addr=%u (block weak, continuing)", (unsigned int)addr);
                    uint32_t blk = addr / geo.erase_size;
                    if (blk < ctx->ftl.total_blocks) {
                        pgfs_ftl_mark_weak(&ctx->ftl, blk);
                    }
                }
            }
            path_len = hdr.path_len;
            data_len = hdr.data_len;
            batch_id = hdr.batch_id;
            crc32 = hdr.crc32;
            hdr_len = sizeof(hdr);
            /* P2-4: keep the (corrected) prefix bytes the producer
             * hashed (magic..batch_id = 16 bytes) for the CRC chain. */
            memcpy(hdr_prefix, &hdr, offsetof(pgfs_batch_data_record_hdr_t, crc32));
            if (batch_id == 0) {
                if (pgfs_replay_recover_after_corrupt_record(ctx, addr, limit, &geo, &addr)) {
                    continue;
                }
                break;
            }
        }
        else if (magic == PGFS_BATCH_COMMIT_RECORD_MAGIC) {
            pgfs_batch_commit_record_hdr_t hdr = {0};
            uint32_t hdr_crc = 0;
            if (limit != 0 && addr + sizeof(hdr) > limit) {
                break;
            }
            if (pgfs_replay_flash_read(ctx, addr, &hdr, sizeof(hdr)) != 0) {
                if (pgfs_replay_recover_after_corrupt_record(ctx, addr, limit, &geo, &addr)) {
                    continue;
                }
                break;
            }
            /* P2-4: two ECC groups over bytes 0..7 and 8..15 (record_count
             * + crc32). Mismatch marks the block weak and continues to the
             * CRC verdict (consistent with DATA / BATCH_DATA handling). */
            {
                int ecc_weak = 0;
                if (pgfs_ecc_decode_header((uint8_t*)&hdr, 16u, 2u, &ecc_weak) == 1) {
                    LLOGW("replay: ECC corrected single-bit error at addr=%u", (unsigned int)addr);
                }
                if (ecc_weak) {
                    LLOGW("replay: ECC mismatch at addr=%u (block weak, continuing)", (unsigned int)addr);
                    uint32_t blk = addr / geo.erase_size;
                    if (blk < ctx->ftl.total_blocks) {
                        pgfs_ftl_mark_weak(&ctx->ftl, blk);
                    }
                }
            }
            hdr_crc = pgfs_crc32_calc(&hdr, offsetof(pgfs_batch_commit_record_hdr_t, crc32));
            if (hdr.magic != PGFS_BATCH_COMMIT_RECORD_MAGIC || hdr.batch_id == 0 || hdr_crc != hdr.crc32) {
                if (pgfs_replay_recover_after_corrupt_record(ctx, addr, limit, &geo, &addr)) {
                    continue;
                }
                break;
            }
            record_len = sizeof(hdr);
            storage_len = pgfs_record_storage_len(ctx, (size_t)record_len);
            if (storage_len < (size_t)record_len) {
                break;
            }
            next_addr = (uint64_t)addr + (uint64_t)storage_len;
            if (limit != 0 && next_addr > limit) {
                break;
            }
            if (pgfs_replay_pending_apply(ctx, pending, hdr.batch_id) != 0) {
                ret = -1;
                goto cleanup;
            }
            ctx->data_log_write_addr = (uint32_t)next_addr;
            addr = (uint32_t)next_addr;
            continue;
        }
        else {
            if (pgfs_replay_pending_has_entries(pending) || (limit != 0u && geo.erase_size > 0u &&
                pgfs_align_up_u32(addr + 1u, geo.erase_size) >= limit)) {
                uint32_t resync_addr = 0u;
                if (pgfs_replay_try_resync_in_block(ctx, addr, limit, &geo, &resync_addr) == 0) {
                    LLOGW("replay resync after unknown region at addr=%u magic=%08x -> %u",
                          (unsigned int)addr, (unsigned int)magic, (unsigned int)resync_addr);
                    addr = resync_addr;
                    continue;
                }
            }
            if (geo.erase_size > 0) {
                uint32_t next_block = pgfs_align_up_u32(addr + 1u, geo.erase_size);
                if (next_block > addr && (limit == 0u || next_block < limit)) {
                    if (magic == 0xFFFFFFFFu || magic == 0x00000000u) {
                        LLOGW("replay skip blank block at addr=%u next_block=%u",
                              (unsigned int)addr, (unsigned int)next_block);
                    }
                    else {
                        LLOGW("replay skip unknown region at addr=%u magic=%08x next_block=%u",
                              (unsigned int)addr, (unsigned int)magic, (unsigned int)next_block);
                    }
                    addr = next_block;
                    continue;
                }
            }
            break;
        }
        if (path_len == 0 || path_len >= sizeof(norm)) {
            if (pgfs_replay_recover_after_corrupt_record(ctx, addr, limit, &geo, &addr)) {
                continue;
            }
            break;
        }
        record_len = (uint64_t)hdr_len + (uint64_t)path_len + (uint64_t)data_len;
        storage_len = pgfs_record_storage_len(ctx, (size_t)record_len);
        if (record_len < hdr_len || storage_len < (size_t)record_len) {
            if (pgfs_replay_recover_after_corrupt_record(ctx, addr, limit, &geo, &addr)) {
                continue;
            }
            break;
        }
        next_addr = (uint64_t)addr + (uint64_t)storage_len;
        if (limit != 0 && next_addr > limit) {
            break;
        }
        /* P2-7: path_buf is pre-allocated. Reject records whose path
         * exceeds the buffer — this can only happen with a corrupted
         * record header (path_len is bounded by sizeof(norm) == 96). */
        if (path_len >= PGFS_REPLAY_PATH_BUF_SIZE) {
            if (pgfs_replay_recover_after_corrupt_record(ctx, addr, limit, &geo, &addr)) {
                continue;
            }
            break;
        }
        /* P2-7: grow data_buf on demand if this record is larger than
         * the current capacity. Caps at PGFS_REPLAY_DATA_MAX_CAP to
         * prevent OOM from a corrupted data_len field. */
        if (data_len > 0) {
            size_t need = (size_t)data_len;
            if (need > PGFS_REPLAY_DATA_MAX_CAP) {
                if (pgfs_replay_recover_after_corrupt_record(ctx, addr, limit, &geo, &addr)) {
                    continue;
                }
                break;
            }
            if (replay_data_buf == NULL || replay_data_cap < need) {
                size_t new_cap = replay_data_cap == 0 ? PGFS_REPLAY_DATA_INIT_CAP : replay_data_cap;
                while (new_cap < need && new_cap < PGFS_REPLAY_DATA_MAX_CAP) {
                    if (new_cap < 4096) new_cap *= 2;
                    else new_cap += 4096;
                }
                if (new_cap > PGFS_REPLAY_DATA_MAX_CAP) new_cap = PGFS_REPLAY_DATA_MAX_CAP;
                if (new_cap < need) new_cap = need;
                uint8_t* grown = (uint8_t*)luat_heap_malloc(new_cap);
                if (grown == NULL) {
                    ret = -1;
                    goto cleanup;
                }
                if (replay_data_buf != NULL) {
                    luat_heap_free(replay_data_buf);
                }
                replay_data_buf = grown;
                replay_data_cap = new_cap;
            }
            data_buf = replay_data_buf;
        }
        if (pgfs_replay_flash_read(ctx, addr + (uint32_t)hdr_len, path_buf, path_len) != 0) {
            luat_heap_free(path_buf);
            luat_heap_free(data_buf);
            if (pgfs_replay_recover_after_corrupt_record(ctx, addr, limit, &geo, &addr)) {
                continue;
            }
            break;
        }
        path_buf[path_len] = '\0';
        if (data_len != 0 &&
            pgfs_replay_flash_read(ctx, addr + (uint32_t)hdr_len + path_len, data_buf, data_len) != 0) {
            luat_heap_free(path_buf);
            luat_heap_free(data_buf);
            if (pgfs_replay_recover_after_corrupt_record(ctx, addr, limit, &geo, &addr)) {
                continue;
            }
            break;
        }
        crc_len = (size_t)path_len + (size_t)data_len;
        if (crc_len > 0) {
            /* Phase 3b: chain the CRC across the header prefix first,
             * then path, then data — exactly mirroring what the
             * producer wrote. Compute directly from path_buf/data_buf
             * to avoid a redundant crc_buf allocation per record. */
            size_t prefix_len = (magic == PGFS_BATCH_DATA_RECORD_MAGIC)
                ? offsetof(pgfs_batch_data_record_hdr_t, crc32)
                : offsetof(pgfs_data_record_hdr_t, crc32);
            uint32_t prefix_crc = luat_crc32(hdr_prefix, (uint32_t)prefix_len, 0xFFFFFFFFu, 0);
            crc = luat_crc32(path_buf, (uint32_t)path_len, prefix_crc, 0);
            if (data_len != 0) {
                crc = luat_crc32(data_buf, (uint32_t)data_len, crc, 0);
            }
        }
        if (crc != crc32) {
            luat_heap_free(path_buf);
            luat_heap_free(data_buf);
            if (pgfs_replay_recover_after_corrupt_record(ctx, addr, limit, &geo, &addr)) {
                continue;
            }
            break;
        }
        if (pgfs_path_normalize((const char*)path_buf, norm, sizeof(norm)) != 0 || norm[0] == '\0') {
            luat_heap_free(path_buf);
            luat_heap_free(data_buf);
            if (pgfs_replay_recover_after_corrupt_record(ctx, addr, limit, &geo, &addr)) {
                continue;
            }
            break;
        }
        if (magic == PGFS_DATA_RECORD_MAGIC) {
            if (pgfs_path_parent(norm, parent, sizeof(parent)) != 0 || pgfs_dir_ensure_norm(ctx, parent) != 0) {
                luat_heap_free(path_buf);
                luat_heap_free(data_buf);
                ret = -1;
                goto cleanup;
            }
            entry = pgfs_alloc_file(ctx, norm);
            if (entry == NULL) {
                luat_heap_free(path_buf);
                luat_heap_free(data_buf);
                ret = -1;
                goto cleanup;
            }
            old_len = entry->len;
            if (data_len != 0) {
                if (pgfs_file_reserve(entry, data_len) != 0) {
                    luat_heap_free(path_buf);
                    luat_heap_free(data_buf);
                    ret = -1;
                    goto cleanup;
                }
                memcpy(entry->data, data_buf, data_len);
            }
            entry->len = data_len;
            ctx->checkpoint.gc_live_bytes += data_len;
            /* Phase 2 prep: per-block live accounting. The DATA record's
             * data + path landed in the block holding the record's start
             * address; attribute the live bytes to that block so the
             * future cost-benefit GC can find blocks with the least
             * live data. */
            pgfs_account_live_block(ctx, addr, (uint32_t)record_len);
            if (old_len > 0) {
                ctx->checkpoint.gc_dead_bytes += (uint32_t)old_len;
                /* Phase 2 prep + shadow detection: the OLD version of
                 * this file is now dead. Its last-known block is
                 * entry->last_written_block (set by the previous
                 * append or replay iteration). Attribute the dead
                 * bytes to that block so the cost-benefit GC can
                 * pick it. Note: if last_written_block is 0 /
                 * 0xFFFFu (never written), the dead bytes are
                 * unaccounted for at the block level — they still
                 * count in the global gc_dead_bytes, just not
                 * per-block. */
                uint16_t old_blk = entry->last_written_block;
                if (old_blk != 0 && old_blk != 0xFFFFu &&
                    ctx->ftl.dead_bytes_per_block != NULL &&
                    old_blk < ctx->ftl.total_blocks) {
                    ctx->ftl.dead_bytes_per_block[old_blk] += (uint32_t)old_len;
                    /* P0-2: release the old record's live credit so the
                     * block can be picked by the cost-benefit GC instead
                     * of looking perpetually full. */
                    if (ctx->ftl.live_bytes_per_block != NULL &&
                        ctx->ftl.live_bytes_per_block[old_blk] >= (uint32_t)old_len) {
                        ctx->ftl.live_bytes_per_block[old_blk] -= (uint32_t)old_len;
                    }
                    pgfs_ftl_mark_dirty(&ctx->ftl);
                }
            }
            /* Update the file's last-known block to the record we
             * just replayed. The next replay iteration (or the
             * close-path attribution) will use this to mark the
             * NEXT shadow event. */
            {
                pgfs_flash_geometry_t geo = {0};
                if (ctx->ftl.flash_opts != NULL && ctx->ftl.flash_opts->control != NULL &&
                    ctx->ftl.flash_opts->control(ctx->ftl.flash_opts->ctx,
                                                 PGFS_CTRL_GET_GEOMETRY, &geo) == 0 &&
                    geo.erase_size > 0) {
                    uint32_t new_blk = addr / geo.erase_size;
                    if (new_blk <= 0xFFFEu) {
                        entry->last_written_block = (uint16_t)new_blk;
                    }
                }
            }
            ctx->checkpoint.written_blocks += 1u;
        }
        else {
            if (pgfs_replay_pending_stage(pending, batch_id, norm, data_buf, data_len, addr) != 0) {
                luat_heap_free(path_buf);
                luat_heap_free(data_buf);
                ret = -1;
                goto cleanup;
            }
        }
        ctx->data_log_write_addr = (uint32_t)next_addr;
        /* P2-7: replay buffers are pre-allocated, no per-record free needed */
        addr = (uint32_t)next_addr;
    }

    pgfs_replay_pending_drop_all(pending);
    if (ctx->data_log_write_addr < base) {
        ctx->data_log_write_addr = base;
    }
    if (ctx->data_log_prepared_until < ctx->data_log_write_addr) {
        ctx->data_log_prepared_until = ctx->data_log_write_addr;
    }
    ctx->pending_checkpoint_writes = 0;
    return ret;

cleanup:
    /* P2-7: free pre-allocated replay buffers */
    if (replay_path_buf != NULL) {
        luat_heap_free(replay_path_buf);
    }
    if (replay_data_buf != NULL) {
        luat_heap_free(replay_data_buf);
    }
    pgfs_replay_pending_drop_all(pending);
    pgfs_file_reset(ctx);
    return ret;
}

static int pgfs_apply_cache_to_entry(pgfs_file_t* f) {
    pgfs_file_entry_t* e = NULL;
    if (f == NULL || f->entry == NULL || f->cache.len == 0) {
        return 0;
    }
    e = f->entry;
    if (e->data) {
        pgfs_heap_free_by_type(e->heap_type, e->data);
    }
    /* Transfer ownership from write-cache to entry to avoid large-file double allocation. */
    e->data = f->cache.data;
    e->cap = f->cache.cap;
    e->len = f->cache.len;
    e->heap_type = f->cache.heap_type;
    f->cache.data = NULL;
    f->cache.cap = 0;
    f->cache.len = 0;
    f->cache.heap_type = (uint8_t)LUAT_HEAP_SRAM;
    /* Note: gc_live_bytes / gc_dead_bytes attribution is handled by the
     * caller (pgfs_file_close) which has the full context of the previous
     * version's block location. Doing it here would double-count. */
    return 0;
}

/* P0-1/P0-3: refresh ctx->ftl.write_head / log_tail fields from the current
 * data-log write head and persist the FTL state so the next mount replay
 * can discover records written since the last CP commit. Returns -1 only
 * when the persist failed twice (transient SPI failures are retried
 * once); callers turn that into a strict fclose/fflush error. Skips
 * silently on unit-test layouts where the write head is inside the FTL
 * state block (persisting there would erase live data). */
static int pgfs_persist_write_head(pgfs_mount_ctx_t* ctx) {
    uint32_t ftl_state_end = 0;
    if (ctx == NULL || ctx->ftl.flash_opts == NULL || !ctx->checkpoint_loaded ||
        ctx->ftl.erase_size == 0) {
        return 0;
    }
    ftl_state_end = pgfs_ftl_state_addr(ctx->ftl.erase_size) + ctx->ftl.erase_size;
    if (ctx->data_log_write_addr < ftl_state_end) {
        return 0;
    }
    if (ctx->flash_opts == NULL || ctx->flash_opts->control == NULL) {
        return 0;
    }
    {
        pgfs_flash_geometry_t geo_ftl = {0};
        if (ctx->flash_opts->control(ctx->flash_opts->ctx,
                                     PGFS_CTRL_GET_GEOMETRY, &geo_ftl) != 0 ||
            geo_ftl.erase_size == 0 ||
            ctx->data_log_write_addr < ctx->data_log_base_addr) {
            return 0;
        }
        uint32_t base_block = ctx->data_log_base_addr / geo_ftl.erase_size;
        uint32_t write_block = ctx->data_log_write_addr / geo_ftl.erase_size;
        uint32_t write_off   = ctx->data_log_write_addr % geo_ftl.erase_size;
        if (write_block >= base_block) {
            ctx->ftl.write_head_block  = write_block - base_block;
            ctx->ftl.write_head_offset = (uint16_t)write_off;
        }
        ctx->ftl.log_tail_block  = ctx->log_tail_block;
        ctx->ftl.log_tail_offset = ctx->log_tail_offset;
        pgfs_ftl_mark_dirty(&ctx->ftl);
        if (pgfs_ftl_persist(&ctx->ftl, ctx->checkpoint.seq) != 0 &&
            pgfs_ftl_persist(&ctx->ftl, ctx->checkpoint.seq) != 0) {
            return -1;
        }
    }
    return 0;
}

FILE* pgfs_file_open(pgfs_mount_ctx_t* ctx, const char *filename, const char *mode) {
    pgfs_file_t* f = NULL;
    pgfs_file_entry_t* e = NULL;
    char norm[PGFS_MAX_PATH] = {0};
    char parent[PGFS_MAX_PATH] = {0};
    if (ctx == NULL || filename == NULL || mode == NULL) {
        return NULL;
    }
    if (pgfs_tables_ensure(ctx) != 0) {
        return NULL;
    }
    if (pgfs_lock(ctx) != 0) {
        return NULL;
    }
    if (pgfs_path_normalize(filename, norm, sizeof(norm)) != 0 || norm[0] == '\0') {
        pgfs_unlock(ctx);
        return NULL;
    }
    if (pgfs_mode_is_write(mode)) {
        if (pgfs_path_parent(norm, parent, sizeof(parent)) != 0 || pgfs_dir_ensure_norm(ctx, parent) != 0) {
            pgfs_unlock(ctx);
            return NULL;
        }
        if (!ctx->batch_active) {
            e = pgfs_alloc_file(ctx, norm);
        }
    }
    else {
        e = pgfs_find_file_norm(ctx, norm);
    }
    if (e == NULL && !(pgfs_mode_is_write(mode) && ctx->batch_active)) {
        pgfs_unlock(ctx);
        return NULL;
    }
    f = (pgfs_file_t*)luat_heap_malloc(sizeof(pgfs_file_t));
    if (f == NULL) {
        pgfs_unlock(ctx);
        return NULL;
    }
    memset(f, 0, sizeof(*f));
    f->ctx = ctx;
    f->entry = e;
    f->generation = ctx->runtime_generation;
    f->mode_write = (uint8_t)pgfs_mode_is_write(mode);
    f->mode_read = (uint8_t)pgfs_mode_is_read(mode);
    f->opened_in_batch = (uint8_t)(ctx->batch_active ? 1 : 0);
    f->batch_id = ctx->batch_id;
    memcpy(f->path, norm, strlen(norm) + 1);
    f->pos = 0;
    /* P0-2: Append mode must copy existing file content into the write
     * cache. Without this, pgfs_apply_cache_to_entry at close replaces
     * entry->data with the cache (only containing new writes), discarding
     * all original file content. */
    if (e != NULL && strchr(mode, 'a')) {
        f->pos = e->len;
        if (e->data != NULL && e->len > 0) {
            if (pgfs_cache_expand(&f->cache, e->len) == 0) {
                memcpy(f->cache.data, e->data, e->len);
                f->cache.len = e->len;
            }
        }
    }
    pgfs_unlock(ctx);
    return (FILE*)f;
}

int pgfs_file_close(pgfs_mount_ctx_t* ctx, FILE* stream) {
    pgfs_file_t* f = (pgfs_file_t*)stream;
    int ret = 0;
    uint32_t seg_id = 0;
    uint64_t t0 = 0;
    uint64_t t_gc = 0;
    uint64_t t_alloc = 0;
    uint64_t t_append = 0;
    uint64_t t_apply = 0;
    uint64_t t_cp = 0;
    uint8_t checkpoint_flushed = 0;
    if (ctx == NULL || f == NULL) {
        return -1;
    }
    if (!pgfs_ctx_handle_valid(ctx, f->generation)) {
        if (f->cache.data) {
            pgfs_heap_free_by_type(f->cache.heap_type, f->cache.data);
        }
        luat_heap_free(f);
        return -1;
    }
    if (!pgfs_batch_handle_match(ctx, f)) {
        if (f->cache.data) {
            pgfs_heap_free_by_type(f->cache.heap_type, f->cache.data);
        }
        luat_heap_free(f);
        return -1;
    }

    if (pgfs_lock(ctx) != 0) {
        return -1;
    }
    if (f->mode_write) {
        if (f->opened_in_batch) {
            if (pgfs_batch_pending_stage(ctx, f) != 0) {
                ret = -1;
            }
            goto finish;
        }
        if (f->cache.len == 0) {
            /* P2-1: nothing buffered — either fflush already flushed the
             * cache to the log, or the handle was opened for write but
             * never written. There is no new record to append or persist;
             * skipping also fixes the old "close an empty write handle
             * fails" behaviour (pgfs_append_data_record rejects len==0). */
            goto finish;
        }
        /* Phase 2 GC: capture the OLD block the previous version of
         * this file lived in so the close path can attribute the
         * dead bytes to that block (the new write will credit a
         * different block via pgfs_append_data_record below). */
        uint16_t prev_last_written = f->entry->last_written_block;
        size_t prev_len = f->entry->len;
        t0 = luat_mcu_tick64_ms();
        /* Only trigger GC when space pressure is detected: if the write
         * head is within 2 erase blocks of the end of flash, run GC to
         * reclaim space. Unconditional GC on every close was a major
         * performance bottleneck (two full block-table scans per close). */
        {
            uint32_t erase_sz = ctx->layout.erase_size;
            if (erase_sz == 0) erase_sz = ctx->ftl.erase_size;
            if (erase_sz > 0 && ctx->flash_opts != NULL &&
                ctx->flash_opts->control != NULL) {
                pgfs_flash_geometry_t geo_chk = {0};
                if (ctx->flash_opts->control(ctx->flash_opts->ctx,
                    PGFS_CTRL_GET_GEOMETRY, &geo_chk) == 0 &&
                    geo_chk.capacity > 0) {
                    uint64_t remaining = (uint64_t)geo_chk.capacity -
                                         (uint64_t)ctx->data_log_write_addr;
                    if (remaining < (uint64_t)erase_sz * 2u) {
                        (void)pgfs_gc_step(ctx, 4096, 2000);
                    }
                }
            }
        }
        t_gc = luat_mcu_tick64_ms();
        if (pgfs_alloc_segment(ctx, &seg_id) != 0) {
            /* Aggressive GC retry: the initial small-budget GC may not have
             * reclaimed enough space. Try up to 3 larger GC steps before
             * giving up, so transient space pressure doesn't cause silent
             * data loss. */
            int gc_retry = 0;
            int alloc_ok = 0;
            for (gc_retry = 0; gc_retry < 3; gc_retry++) {
                uint32_t gc_budget = 4096u * (uint32_t)(gc_retry + 2u);
                if (pgfs_gc_step(ctx, gc_budget, 5000) == 0) {
                    break; /* GC found nothing to reclaim */
                }
                if (pgfs_alloc_segment(ctx, &seg_id) == 0) {
                    alloc_ok = 1;
                    break;
                }
            }
            if (!alloc_ok && pgfs_alloc_segment(ctx, &seg_id) != 0) {
                LLOGE("close alloc_segment failed after GC retries (path=%s)",
                      f->entry ? f->entry->path : "?");
                f->err = 1;
                ret = -1;
                goto finish;
            }
        }
        t_alloc = luat_mcu_tick64_ms();
        if (ctx->inject_powercut_stage == PGFS_INJECT_POWERCUT_BEFORE_APPEND) {
            ctx->inject_powercut_stage = PGFS_INJECT_POWERCUT_NONE;
            ctx->stats.powercut_inject_count++;
            ret = -1;
            goto finish;
        }
        if (pgfs_append_data_record(ctx, f) != 0) {
            /* Append failed (out of space or write error). Try GC + retry
             * once before giving up. */
            (void)pgfs_gc_step(ctx, 8192, 5000);
            if (pgfs_append_data_record(ctx, f) != 0) {
                LLOGE("close append_data_record failed addr=%u path=%s",
                      (unsigned int)ctx->data_log_write_addr,
                      f->entry ? f->entry->path : "?");
                (void)pgfs_mark_block_retired(ctx, seg_id);
                f->err = 1;
                ret = -1;
                goto finish;
            }
        }
        /* Phase 2 GC: the new write succeeded, so the OLD version is
         * now dead. Attribute the old live bytes to the old block so
         * the cost-benefit GC can pick it. */
        if (prev_last_written != 0 && prev_last_written != 0xFFFFu && prev_len > 0) {
            if (ctx->ftl.dead_bytes_per_block != NULL &&
                prev_last_written < ctx->ftl.total_blocks) {
                ctx->ftl.dead_bytes_per_block[prev_last_written] += (uint32_t)prev_len;
            }
            /* P0-2: release the old record's live credit so the shadowed
             * block becomes a GC candidate instead of looking full. */
            if (ctx->ftl.live_bytes_per_block != NULL &&
                ctx->ftl.live_bytes_per_block[prev_last_written] >= (uint32_t)prev_len) {
                ctx->ftl.live_bytes_per_block[prev_last_written] -= (uint32_t)prev_len;
            }
            ctx->checkpoint.gc_dead_bytes += (uint32_t)prev_len;
            pgfs_ftl_mark_dirty(&ctx->ftl);
        }
        /* Attribute new live bytes (the record just written). */
        ctx->checkpoint.gc_live_bytes += (uint32_t)f->cache.len;
        t_append = luat_mcu_tick64_ms();
        if (ctx->inject_powercut_stage == PGFS_INJECT_POWERCUT_AFTER_APPEND) {
            ctx->inject_powercut_stage = PGFS_INJECT_POWERCUT_NONE;
            ctx->stats.powercut_inject_count++;
            ret = -1;
            goto finish;
        }
        /* P0-1: Persist FTL write_head after each successful data record
         * append so the next mount replay can discover records written
         * since the last CP commit. Without this, up to 7 fclose() calls
         * that return success can be lost after a power cycle because the
         * CP's log_tail (and the replay durable_limit derived from it)
         * were not updated.
         * P0-3: the persist is now STRICT — after one retry, a failure
         * makes fclose return an error (durability is only guaranteed
         * once the write head is persisted), unless the close's own CP
         * commit succeeds, whose log_tail covers the record anyway.
         * Only fire on properly-mounted filesystems (checkpoint_loaded)
         * where the data log write head is safely past the FTL state
         * block. Persisting when data_log_write_addr is still within
         * the FTL state region would erase live data (as can happen
         * in legacy tests using PGFS_DATA_LOG_BASE_ADDR=0x4000 which
         * overlaps the v3 layout's block-4 FTL state). */
        int ftl_persist_failed = 0;
        if (pgfs_persist_write_head(ctx) != 0) {
            LLOGE("close FTL write_head persist failed twice path=%s",
                  f->entry ? f->entry->path : "?");
            ftl_persist_failed = 1;
        }
        if (pgfs_apply_cache_to_entry(f) != 0) {
            LLOGE("close apply_cache failed");
            ret = -1;
            goto finish;
        }
        t_apply = luat_mcu_tick64_ms();
        ctx->checkpoint.written_blocks = (uint32_t)(ctx->checkpoint.written_blocks + 1u);
        pgfs_mark_checkpoint_pending(ctx);
        if (ctx->inject_powercut_stage == PGFS_INJECT_POWERCUT_BEFORE_CP) {
            ctx->inject_powercut_stage = PGFS_INJECT_POWERCUT_NONE;
            ctx->stats.powercut_inject_count++;
            ret = -1;
            goto finish;
        }
        if (ctx->pending_checkpoint_writes >= PGFS_CHECKPOINT_BATCH_CLOSES) {
            if (pgfs_checkpoint_commit_pending(ctx) != 0) {
                LLOGE("close checkpoint_store failed");
                ret = -1;
                goto finish;
            }
            checkpoint_flushed = 1;
            /* P0-3: the CP's log_tail now covers this record — durability
             * is guaranteed by the CP even though the per-close FTL
             * persist failed. */
            ftl_persist_failed = 0;
        }
        if (ftl_persist_failed) {
            LLOGE("close: FTL write_head not persisted and no CP commit — "
                  "returning error (durability not guaranteed)");
            f->err = 1;
            ret = -1;
        }
        t_cp = luat_mcu_tick64_ms();
        LLOGD("perf close path=%s size=%u gc=%u alloc=%u append=%u apply=%u cp=%u total=%u cp_flush=%u pending_cp=%u",
              f->entry ? f->entry->path : "?", (unsigned int)(f->entry ? f->entry->len : 0),
              (unsigned int)(t_gc - t0), (unsigned int)(t_alloc - t_gc), (unsigned int)(t_append - t_alloc),
              (unsigned int)(t_apply - t_append), (unsigned int)(t_cp - t_apply), (unsigned int)(t_cp - t0),
              (unsigned int)checkpoint_flushed, (unsigned int)ctx->pending_checkpoint_writes);
    }
finish:
    if (f->cache.data) {
        pgfs_heap_free_by_type(f->cache.heap_type, f->cache.data);
    }
    pgfs_unlock(ctx);
    luat_heap_free(f);
    return ret;
}

int pgfs_dir_mkdir(pgfs_mount_ctx_t* ctx, const char *path) {
    char norm[PGFS_MAX_PATH] = {0};
    int ret = 0;
    if (path == NULL) {
        return -1;
    }
    if (pgfs_tables_ensure(ctx) != 0) {
        return -1;
    }
    if (pgfs_path_normalize(path, norm, sizeof(norm)) != 0) {
        return -1;
    }
    if (ctx != NULL && pgfs_lock(ctx) != 0) {
        return -1;
    }
    ret = pgfs_dir_ensure_norm(ctx, norm);
    if (ctx != NULL) {
        pgfs_unlock(ctx);
    }
    return ret;
}

int pgfs_dir_rmdir(pgfs_mount_ctx_t* ctx, const char *path) {
    char norm[PGFS_MAX_PATH] = {0};
    int ret = -1;
    if (path == NULL) {
        return -1;
    }
    if (pgfs_tables_ensure(ctx) != 0) {
        return -1;
    }
    if (pgfs_path_normalize(path, norm, sizeof(norm)) != 0) {
        return -1;
    }
    if (ctx != NULL && pgfs_lock(ctx) != 0) {
        return -1;
    }
    ret = pgfs_dir_remove_norm(ctx, norm);
    if (ctx != NULL) {
        pgfs_unlock(ctx);
    }
    return ret;
}

int pgfs_dir_lsdir(pgfs_mount_ctx_t* ctx, const char *path, luat_fs_dirent_t* ents, size_t offset, size_t len) {
    int ret = 0;
    if (pgfs_tables_ensure(ctx) != 0) {
        return 0;
    }
    if (ctx != NULL && pgfs_lock(ctx) != 0) {
        return 0;
    }
    ret = pgfs_dir_lsdir_norm(ctx, path, ents, offset, len);
    if (ctx != NULL) {
        pgfs_unlock(ctx);
    }
    return ret;
}

void* pgfs_dir_opendir(pgfs_mount_ctx_t* ctx, const char *path) {
    pgfs_dir_handle_t* dir = NULL;
    char norm[PGFS_MAX_PATH] = {0};
    if (ctx == NULL || path == NULL) {
        return NULL;
    }
    if (pgfs_tables_ensure(ctx) != 0) {
        return NULL;
    }
    if (pgfs_path_normalize(path, norm, sizeof(norm)) != 0) {
        return NULL;
    }
    if (ctx != NULL && pgfs_lock(ctx) != 0) {
        return NULL;
    }
    if (!pgfs_dir_exists_norm(ctx, norm)) {
        if (ctx != NULL) {
            pgfs_unlock(ctx);
        }
        return NULL;
    }
    dir = (pgfs_dir_handle_t*)luat_heap_malloc(sizeof(pgfs_dir_handle_t));
    if (dir == NULL) {
        if (ctx != NULL) {
            pgfs_unlock(ctx);
        }
        return NULL;
    }
    memset(dir, 0, sizeof(*dir));
    dir->generation = ctx != NULL ? ctx->runtime_generation : 0;
    memcpy(dir->path, norm, strlen(norm) + 1);
    if (ctx != NULL) {
        pgfs_unlock(ctx);
    }
    return dir;
}

int pgfs_dir_closedir(pgfs_mount_ctx_t* ctx, void* dir) {
    pgfs_dir_handle_t* handle = (pgfs_dir_handle_t*)dir;
    if (dir != NULL) {
        if (ctx != NULL && handle != NULL && handle->generation != ctx->runtime_generation) {
            luat_heap_free(dir);
            return -1;
        }
        luat_heap_free(dir);
    }
    return 0;
}

size_t pgfs_file_read(pgfs_mount_ctx_t* ctx, void *ptr, size_t size, size_t nmemb, FILE *stream) {
    pgfs_file_t* f = (pgfs_file_t*)stream;
    size_t want;
    size_t left = 0;
    size_t take = 0;
    if (ptr == NULL || f == NULL || f->entry == NULL || !f->mode_read || size == 0 || nmemb == 0) {
        return 0;
    }
    /* P1-5: guard against size_t overflow in size * nmemb */
    if (size > (size_t)-1 / nmemb) {
        return 0;
    }
    want = size * nmemb;
    if (!pgfs_ctx_handle_valid(ctx, f->generation)) {
        return 0;
    }
    /* P1-6: acquire per-mount lock to protect against concurrent close/remove
     * which may free or modify the entry's data pointer. */
    if (ctx != NULL) {
        if (pgfs_lock(ctx) != 0) {
            return 0;
        }
    }
    if (f->pos >= f->entry->len) {
        f->eof = 1;
        if (ctx != NULL) { pgfs_unlock(ctx); }
        return 0;
    }
    left = f->entry->len - f->pos;
    take = want < left ? want : left;
    memcpy(ptr, f->entry->data + f->pos, take);
    f->pos += take;
    f->eof = (f->pos >= f->entry->len) ? 1 : 0;
    if (ctx != NULL) { pgfs_unlock(ctx); }
    return size == 0 ? 0 : (take / size);
}

int pgfs_file_getc(pgfs_mount_ctx_t* ctx, FILE* stream) {
    pgfs_file_t* f = (pgfs_file_t*)stream;
    int ch = -1;
    if (f == NULL || f->entry == NULL || !f->mode_read) {
        return -1;
    }
    if (!pgfs_ctx_handle_valid(ctx, f->generation)) {
        return -1;
    }
    /* P3-2: protect against concurrent close/remove freeing the entry. */
    if (ctx != NULL) {
        if (pgfs_lock(ctx) != 0) {
            return -1;
        }
    }
    if (f->pos >= f->entry->len) {
        f->eof = 1;
        if (ctx != NULL) { pgfs_unlock(ctx); }
        return -1;
    }
    ch = (int)((uint8_t)f->entry->data[f->pos]);
    f->pos++;
    f->eof = (f->pos >= f->entry->len) ? 1 : 0;
    if (ctx != NULL) { pgfs_unlock(ctx); }
    return ch;
}

size_t pgfs_file_write(pgfs_mount_ctx_t* ctx, const void *ptr, size_t size, size_t nmemb, FILE *stream) {
    pgfs_file_t* f = (pgfs_file_t*)stream;
    size_t total;
    int ret;
    if (f == NULL || ptr == NULL || !f->mode_write || size == 0 || nmemb == 0) {
        return 0;
    }
    /* P1-5: guard against size_t overflow in size * nmemb */
    if (size > (size_t)-1 / nmemb) {
        f->err = 1;
        return 0;
    }
    total = size * nmemb;
    if (!pgfs_ctx_handle_valid(ctx, f->generation)) {
        f->err = 1;
        return 0;
    }
    if (!pgfs_batch_handle_match(ctx, f)) {
        f->err = 1;
        return 0;
    }
    /* P1-6: acquire per-mount lock to protect against concurrent operations
     * on the global file table and the file entry. */
    if (ctx != NULL) {
        if (pgfs_lock(ctx) != 0) {
            f->err = 1;
            return 0;
        }
    }
    /* P2-1: after a successful fflush the entry holds the flushed content
     * and the cache is empty. Re-seed the cache from the entry so the
     * next write (and the eventual close) continues from the flushed
     * data instead of replacing it. */
    if (f->flushed && f->cache.len == 0 && f->entry != NULL &&
        f->entry->len > 0 && f->entry->data != NULL) {
        if (pgfs_cache_expand(&f->cache, f->entry->len) != 0) {
            f->err = 1;
            if (ctx != NULL) { pgfs_unlock(ctx); }
            return 0;
        }
        memcpy(f->cache.data, f->entry->data, f->entry->len);
        f->cache.len = f->entry->len;
    }
    ret = pgfs_cache_append(f, (const uint8_t*)ptr, total);
    if (ctx != NULL) { pgfs_unlock(ctx); }
    if (ret != 0) {
        f->err = 1;
        return 0;
    }
    f->pos += total;
    return nmemb;
}

int pgfs_file_seek(pgfs_mount_ctx_t* ctx, FILE* stream, long int offset, int origin) {
    pgfs_file_t* f = (pgfs_file_t*)stream;
    size_t base = 0;
    size_t npos = 0;
    (void)ctx;
    if (f == NULL || f->entry == NULL) {
        return -1;
    }
    if (!pgfs_ctx_handle_valid(ctx, f->generation)) {
        return -1;
    }
    if (origin == SEEK_SET) {
        base = 0;
    }
    else if (origin == SEEK_CUR) {
        base = f->pos;
    }
    else if (origin == SEEK_END) {
        base = f->entry->len;
    }
    else {
        return -1;
    }
    if (offset < 0 && (size_t)(-offset) > base) {
        return -1;
    }
    npos = offset < 0 ? (base - (size_t)(-offset)) : (base + (size_t)offset);
    if (npos > f->entry->len) {
        return -1;
    }
    f->pos = npos;
    f->eof = 0;
    return 0;
}

int pgfs_file_tell(pgfs_mount_ctx_t* ctx, FILE* stream) {
    pgfs_file_t* f = (pgfs_file_t*)stream;
    (void)ctx;
    if (f == NULL) {
        return -1;
    }
    if (!pgfs_ctx_handle_valid(ctx, f->generation)) {
        return -1;
    }
    return (int)f->pos;
}

int pgfs_file_eof(pgfs_mount_ctx_t* ctx, FILE* stream) {
    pgfs_file_t* f = (pgfs_file_t*)stream;
    (void)ctx;
    if (!pgfs_ctx_handle_valid(ctx, f ? f->generation : 0)) {
        return 1;
    }
    return f ? f->eof : 1;
}

int pgfs_file_error(pgfs_mount_ctx_t* ctx, FILE* stream) {
    pgfs_file_t* f = (pgfs_file_t*)stream;
    (void)ctx;
    if (!pgfs_ctx_handle_valid(ctx, f ? f->generation : 0)) {
        return 1;
    }
    return f ? f->err : 1;
}

int pgfs_file_flush(pgfs_mount_ctx_t* ctx, FILE* stream) {
    pgfs_file_t* f = (pgfs_file_t*)stream;
    uint32_t seg_id = 0;
    uint16_t prev_last_written = 0;
    size_t prev_len = 0;
    if (ctx == NULL || f == NULL) {
        return -1;
    }
    if (!pgfs_ctx_handle_valid(ctx, f->generation)) {
        return -1;
    }
    if (!pgfs_batch_handle_match(ctx, f)) {
        return -1;
    }
    if (!f->mode_write) {
        return 0;
    }
    if (f->opened_in_batch) {
        return 0;
    }
    if (pgfs_lock(ctx) != 0) {
        return -1;
    }
    /* P2-1: fflush is now a real durability point — append the buffered
     * cache to the data log and persist the FTL write head, then apply
     * the cache to the entry so a later fclose with an empty cache is a
     * no-op. */
    if (f->cache.len == 0) {
        pgfs_unlock(ctx);
        return 0;
    }
    prev_last_written = f->entry->last_written_block;
    prev_len = f->entry->len;
    /* GC pressure check (mirrors pgfs_file_close). */
    {
        uint32_t erase_sz = ctx->layout.erase_size;
        if (erase_sz == 0) erase_sz = ctx->ftl.erase_size;
        if (erase_sz > 0 && ctx->flash_opts != NULL &&
            ctx->flash_opts->control != NULL) {
            pgfs_flash_geometry_t geo_chk = {0};
            if (ctx->flash_opts->control(ctx->flash_opts->ctx,
                PGFS_CTRL_GET_GEOMETRY, &geo_chk) == 0 &&
                geo_chk.capacity > 0) {
                uint64_t remaining = (uint64_t)geo_chk.capacity -
                                     (uint64_t)ctx->data_log_write_addr;
                if (remaining < (uint64_t)erase_sz * 2u) {
                    (void)pgfs_gc_step(ctx, 4096, 2000);
                }
            }
        }
    }
    if (pgfs_alloc_segment(ctx, &seg_id) != 0) {
        int gc_retry = 0;
        int alloc_ok = 0;
        for (gc_retry = 0; gc_retry < 3; gc_retry++) {
            uint32_t gc_budget = 4096u * (uint32_t)(gc_retry + 2u);
            if (pgfs_gc_step(ctx, gc_budget, 5000) == 0) {
                break;
            }
            if (pgfs_alloc_segment(ctx, &seg_id) == 0) {
                alloc_ok = 1;
                break;
            }
        }
        if (!alloc_ok && pgfs_alloc_segment(ctx, &seg_id) != 0) {
            f->err = 1;
            pgfs_unlock(ctx);
            return -1;
        }
    }
    if (pgfs_append_data_record(ctx, f) != 0) {
        (void)pgfs_gc_step(ctx, 8192, 5000);
        if (pgfs_append_data_record(ctx, f) != 0) {
            LLOGE("fflush append_data_record failed path=%s",
                  f->entry ? f->entry->path : "?");
            (void)pgfs_mark_block_retired(ctx, seg_id);
            f->err = 1;
            pgfs_unlock(ctx);
            return -1;
        }
    }
    /* P0-2: the old version is now dead — symmetric live/dead attribution. */
    if (prev_last_written != 0 && prev_last_written != 0xFFFFu && prev_len > 0) {
        if (ctx->ftl.dead_bytes_per_block != NULL &&
            prev_last_written < ctx->ftl.total_blocks) {
            ctx->ftl.dead_bytes_per_block[prev_last_written] += (uint32_t)prev_len;
        }
        if (ctx->ftl.live_bytes_per_block != NULL &&
            ctx->ftl.live_bytes_per_block[prev_last_written] >= (uint32_t)prev_len) {
            ctx->ftl.live_bytes_per_block[prev_last_written] -= (uint32_t)prev_len;
        }
        ctx->checkpoint.gc_dead_bytes += (uint32_t)prev_len;
        pgfs_ftl_mark_dirty(&ctx->ftl);
    }
    ctx->checkpoint.gc_live_bytes += (uint32_t)f->cache.len;
    if (pgfs_persist_write_head(ctx) != 0) {
        f->err = 1;
        pgfs_unlock(ctx);
        return -1;
    }
    if (pgfs_apply_cache_to_entry(f) != 0) {
        f->err = 1;
        pgfs_unlock(ctx);
        return -1;
    }
    f->flushed = 1;
    ctx->checkpoint.written_blocks = (uint32_t)(ctx->checkpoint.written_blocks + 1u);
    pgfs_mark_checkpoint_pending(ctx);
    pgfs_unlock(ctx);
    return 0;
}

/* ── C-layer test stubs ────────────────────────────────────────────────
 *
 * Production builds (LUAT_USE_UTEST not set) need pgfs_run_c_layer_tests
 * and pgfs_run_c_layer_case symbols to exist so callers in
 * components/little_flash/luat_lib_little_flash.c (lf.pgfsctl "run_c_tests")
 * can link. Real test bodies live in
 * components/utest/pgfs/luat_pgfs_utest.c, which is only compiled when
 * LUAT_USE_UTEST=y. The stubs here always return -1 ("no tests") so the
 * Lua command simply fails fast in production builds.
 */
#ifndef LUAT_USE_UTEST
int pgfs_run_c_layer_tests(void) {
    return -1;
}

int pgfs_run_c_layer_case(const char* case_name) {
    (void)case_name;
    return -1;
}
#endif

#endif
