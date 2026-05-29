#include "luat_base.h"
#include "pgfs_internal.h"
#include "luat_mem.h"
#include "luat_mcu.h"
#include "luat_crypto.h"
#define LUAT_LOG_TAG "pgfs"
#include "luat_log.h"

#ifdef LUAT_USE_PGFS_COMPONENT

#define PGFS_MAX_FILES 512
#define PGFS_MAX_BATCH_PENDING 32

typedef struct pgfs_data_record_hdr {
    uint32_t magic;
    uint32_t path_len;
    uint32_t data_len;
    uint32_t crc32;
} pgfs_data_record_hdr_t;

typedef struct pgfs_batch_data_record_hdr {
    uint32_t magic;
    uint32_t path_len;
    uint32_t data_len;
    uint32_t batch_id;
    uint32_t crc32;
} pgfs_batch_data_record_hdr_t;

typedef struct pgfs_batch_commit_record_hdr {
    uint32_t magic;
    uint32_t batch_id;
    uint32_t record_count;
    uint32_t crc32;
} pgfs_batch_commit_record_hdr_t;

static pgfs_file_entry_t s_pgfs_files[PGFS_MAX_FILES];
static pgfs_dir_entry_t s_pgfs_dirs[PGFS_MAX_DIRS];

typedef struct pgfs_batch_pending_entry {
    uint8_t used;
    uint8_t heap_type;
    uint16_t reserved;
    uint32_t batch_id;
    char path[sizeof(s_pgfs_files[0].path)];
    uint8_t* data;
    size_t len;
    size_t cap;
} pgfs_batch_pending_entry_t;

static pgfs_batch_pending_entry_t s_pgfs_batch_pending[PGFS_MAX_BATCH_PENDING];

static int pgfs_batch_apply_committed(uint32_t batch_id);
static void pgfs_batch_drop(uint32_t batch_id);
static pgfs_file_entry_t* pgfs_alloc_file(const char* path);
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

static uint32_t pgfs_data_log_base_addr(pgfs_mount_ctx_t* ctx) {
    if (ctx != NULL && ctx->data_log_base_addr >= PGFS_DATA_LOG_BASE_ADDR) {
        return ctx->data_log_base_addr;
    }
    return PGFS_DATA_LOG_BASE_ADDR;
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

static pgfs_file_entry_t* pgfs_find_file_norm(const char* path) {
    size_t i = 0;
    for (i = 0; i < PGFS_MAX_FILES; i++) {
        if (s_pgfs_files[i].used && strcmp(s_pgfs_files[i].path, path) == 0) {
            return &s_pgfs_files[i];
        }
    }
    return NULL;
}

static pgfs_dir_entry_t* pgfs_find_dir_norm(const char* path) {
    size_t i = 0;
    for (i = 0; i < PGFS_MAX_DIRS; i++) {
        if (s_pgfs_dirs[i].used && strcmp(s_pgfs_dirs[i].path, path) == 0) {
            return &s_pgfs_dirs[i];
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
    if (pgfs_batch_apply_committed(batch_id) != 0) {
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
    pgfs_batch_drop(batch_id);
    ctx->batch_active = 0;
    ctx->batch_id = 0;
    return 0;
}

static int pgfs_dir_has_descendant_norm(const char* path) {
    size_t i = 0;
    for (i = 0; i < PGFS_MAX_FILES; i++) {
        if (!s_pgfs_files[i].used) {
            continue;
        }
        if (path[0] == '\0' || (strncmp(s_pgfs_files[i].path, path, strlen(path)) == 0 && s_pgfs_files[i].path[strlen(path)] == '/')) {
            return 1;
        }
    }
    for (i = 0; i < PGFS_MAX_DIRS; i++) {
        if (!s_pgfs_dirs[i].used) {
            continue;
        }
        if (path[0] == '\0') {
            if (s_pgfs_dirs[i].path[0] != '\0') {
                return 1;
            }
            continue;
        }
        if (strncmp(s_pgfs_dirs[i].path, path, strlen(path)) == 0 && s_pgfs_dirs[i].path[strlen(path)] == '/') {
            return 1;
        }
    }
    return 0;
}

static int pgfs_dir_exists_norm(const char* path) {
    if (path == NULL) {
        return 0;
    }
    if (path[0] == '\0') {
        return 1;
    }
    return pgfs_find_dir_norm(path) != NULL || pgfs_dir_has_descendant_norm(path);
}

static int pgfs_dir_find_free_slot(void) {
    size_t i = 0;
    for (i = 0; i < PGFS_MAX_DIRS; i++) {
        if (!s_pgfs_dirs[i].used) {
            return (int)i;
        }
    }
    return -1;
}

static int pgfs_dir_store_norm(const char* path) {
    pgfs_dir_entry_t* entry = NULL;
    int slot = 0;
    if (path == NULL || path[0] == '\0') {
        return 0;
    }
    if (pgfs_find_file_norm(path) != NULL) {
        return -1;
    }
    entry = pgfs_find_dir_norm(path);
    if (entry != NULL) {
        return 0;
    }
    slot = pgfs_dir_find_free_slot();
    if (slot < 0) {
        return -1;
    }
    memset(&s_pgfs_dirs[slot], 0, sizeof(s_pgfs_dirs[slot]));
    s_pgfs_dirs[slot].used = 1;
    memcpy(s_pgfs_dirs[slot].path, path, strlen(path) + 1);
    return 0;
}

static int pgfs_dir_ensure_norm(const char* path) {
    char current[sizeof(s_pgfs_dirs[0].path)] = {0};
    size_t len = 0;
    if (path == NULL) {
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
        if (current[0] != '\0' && pgfs_dir_store_norm(current) != 0) {
            return -1;
        }
        current[i] = '/';
    }
    return pgfs_dir_store_norm(current);
}

static int pgfs_dir_remove_norm(const char* path) {
    pgfs_dir_entry_t* entry = NULL;
    if (path == NULL || path[0] == '\0') {
        return -1;
    }
    if (pgfs_dir_has_descendant_norm(path)) {
        return -1;
    }
    entry = pgfs_find_dir_norm(path);
    if (entry == NULL) {
        return -1;
    }
    memset(entry, 0, sizeof(*entry));
    return 0;
}

static int pgfs_dir_lsdir_norm(pgfs_mount_ctx_t* ctx, const char* path, luat_fs_dirent_t* ents, size_t offset, size_t len) {
    size_t unique_count = 0;
    size_t out = 0;
    size_t i = 0;
    size_t max_seen = PGFS_MAX_FILES + PGFS_MAX_DIRS;
    char (*seen_names)[sizeof(((pgfs_dir_entry_t*)0)->path)] = NULL;
    char norm[sizeof(s_pgfs_dirs[0].path)] = {0};
    if (ctx == NULL || ents == NULL || len == 0 || path == NULL) {
        return 0;
    }
    if (pgfs_path_normalize(path, norm, sizeof(norm)) != 0) {
        return 0;
    }
    if (!pgfs_dir_exists_norm(norm)) {
        return 0;
    }
    seen_names = (char (*)[sizeof(((pgfs_dir_entry_t*)0)->path)])luat_heap_malloc(max_seen * sizeof(*seen_names));
    if (seen_names == NULL) {
        return 0;
    }
    memset(seen_names, 0, max_seen * sizeof(*seen_names));
    for (i = 0; i < PGFS_MAX_DIRS; i++) {
        char child[sizeof(s_pgfs_dirs[0].path)] = {0};
        int child_is_dir = 1;
        if (!s_pgfs_dirs[i].used) {
            continue;
        }
        if (strcmp(s_pgfs_dirs[i].path, norm) == 0) {
            continue;
        }
        if (pgfs_path_child(norm, s_pgfs_dirs[i].path, child, sizeof(child), &child_is_dir) <= 0 || child[0] == '\0') {
            continue;
        }
        if (child_is_dir != 1) {
            child_is_dir = 1;
        }
        if (unique_count > 0) {
            size_t j = 0;
            int duplicate = 0;
            for (j = 0; j < unique_count; j++) {
                if (strcmp(seen_names[j], child) == 0) {
                    duplicate = 1;
                    break;
                }
            }
            if (duplicate) {
                continue;
            }
        }
        if (unique_count >= max_seen) {
            break;
        }
        memcpy(seen_names[unique_count], child, strlen(child) + 1);
        unique_count++;
        if (unique_count <= offset) {
            continue;
        }
        if (out < len) {
            memset(&ents[out], 0, sizeof(ents[out]));
            ents[out].d_type = 1;
            memcpy(ents[out].d_name, child, strlen(child) + 1);
            out++;
        }
    }
    for (i = 0; i < PGFS_MAX_FILES; i++) {
        char child[sizeof(s_pgfs_dirs[0].path)] = {0};
        int child_is_dir = 0;
        if (!s_pgfs_files[i].used) {
            continue;
        }
        if (strcmp(s_pgfs_files[i].path, norm) == 0) {
            continue;
        }
        if (pgfs_path_child(norm, s_pgfs_files[i].path, child, sizeof(child), &child_is_dir) <= 0 || child[0] == '\0') {
            continue;
        }
        if (unique_count > 0) {
            size_t j = 0;
            int duplicate = 0;
            for (j = 0; j < unique_count; j++) {
                if (strcmp(seen_names[j], child) == 0) {
                    duplicate = 1;
                    break;
                }
            }
            if (duplicate) {
                continue;
            }
        }
        if (unique_count >= max_seen) {
            break;
        }
        memcpy(seen_names[unique_count], child, strlen(child) + 1);
        unique_count++;
        if (unique_count <= offset) {
            continue;
        }
        if (out < len) {
            memset(&ents[out], 0, sizeof(ents[out]));
            ents[out].d_type = child_is_dir ? 1 : 0;
            memcpy(ents[out].d_name, child, strlen(child) + 1);
            out++;
        }
    }
    luat_heap_free(seen_names);
    return (int)out;
}

typedef struct pgfs_dir_handle {
    uint32_t generation;
    char path[sizeof(s_pgfs_dirs[0].path)];
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

static void pgfs_batch_pending_reset_all(void) {
    size_t i = 0;
    for (i = 0; i < PGFS_MAX_BATCH_PENDING; i++) {
        if (s_pgfs_batch_pending[i].data != NULL) {
            pgfs_heap_free_by_type(s_pgfs_batch_pending[i].heap_type, s_pgfs_batch_pending[i].data);
        }
        memset(&s_pgfs_batch_pending[i], 0, sizeof(s_pgfs_batch_pending[i]));
    }
}

static pgfs_batch_pending_entry_t* pgfs_batch_pending_find(uint32_t batch_id, const char* path) {
    size_t i = 0;
    if (path == NULL || path[0] == '\0') {
        return NULL;
    }
    for (i = 0; i < PGFS_MAX_BATCH_PENDING; i++) {
        if (s_pgfs_batch_pending[i].used &&
            s_pgfs_batch_pending[i].batch_id == batch_id &&
            strcmp(s_pgfs_batch_pending[i].path, path) == 0) {
            return &s_pgfs_batch_pending[i];
        }
    }
    return NULL;
}

static pgfs_batch_pending_entry_t* pgfs_batch_pending_alloc(uint32_t batch_id, const char* path) {
    size_t i = 0;
    pgfs_batch_pending_entry_t* p = pgfs_batch_pending_find(batch_id, path);
    if (p != NULL) {
        return p;
    }
    for (i = 0; i < PGFS_MAX_BATCH_PENDING; i++) {
        if (!s_pgfs_batch_pending[i].used) {
            memset(&s_pgfs_batch_pending[i], 0, sizeof(s_pgfs_batch_pending[i]));
            s_pgfs_batch_pending[i].used = 1;
            s_pgfs_batch_pending[i].batch_id = batch_id;
            if (pgfs_path_copy(s_pgfs_batch_pending[i].path, sizeof(s_pgfs_batch_pending[i].path), path) != 0) {
                memset(&s_pgfs_batch_pending[i], 0, sizeof(s_pgfs_batch_pending[i]));
                return NULL;
            }
            return &s_pgfs_batch_pending[i];
        }
    }
    return NULL;
}

static int pgfs_batch_pending_stage(pgfs_mount_ctx_t* ctx, pgfs_file_t* f) {
    pgfs_batch_pending_entry_t* p = NULL;
    if (ctx == NULL || f == NULL || !f->opened_in_batch || !ctx->batch_active || f->batch_id != ctx->batch_id) {
        return -1;
    }
    p = pgfs_batch_pending_alloc(f->batch_id, f->path);
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
    for (i = 0; i < PGFS_MAX_BATCH_PENDING; i++) {
        pgfs_batch_pending_entry_t* p = &s_pgfs_batch_pending[i];
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
    ctx->checkpoint.used_blocks = (uint32_t)(ctx->checkpoint.used_blocks + record_count);
    if (record_count > 0) {
        pgfs_mark_checkpoint_pending(ctx);
    }
    return 0;
}

static int pgfs_batch_apply_committed(uint32_t batch_id) {
    size_t i = 0;
    for (i = 0; i < PGFS_MAX_BATCH_PENDING; i++) {
        pgfs_batch_pending_entry_t* p = &s_pgfs_batch_pending[i];
        pgfs_file_entry_t* e = NULL;
        if (!p->used || p->batch_id != batch_id) {
            continue;
        }
        e = pgfs_alloc_file(p->path);
        if (e == NULL) {
            return -1;
        }
        if (e->data != NULL) {
            pgfs_heap_free_by_type(e->heap_type, e->data);
        }
        e->data = p->data;
        e->len = p->len;
        e->cap = p->cap;
        e->heap_type = p->heap_type;
        p->data = NULL;
        memset(p, 0, sizeof(*p));
    }
    return 0;
}

static void pgfs_batch_drop(uint32_t batch_id) {
    size_t i = 0;
    for (i = 0; i < PGFS_MAX_BATCH_PENDING; i++) {
        pgfs_batch_pending_entry_t* p = &s_pgfs_batch_pending[i];
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

static pgfs_file_entry_t* pgfs_alloc_file(const char* path) {
    size_t i = 0;
    pgfs_file_entry_t* e = NULL;
    if (path == NULL || path[0] == '\0') {
        return NULL;
    }
    if (pgfs_dir_exists_norm(path)) {
        return NULL;
    }
    e = pgfs_find_file_norm(path);
    if (e) {
        return e;
    }
    for (i = 0; i < PGFS_MAX_FILES; i++) {
        if (!s_pgfs_files[i].used) {
            memset(&s_pgfs_files[i], 0, sizeof(s_pgfs_files[i]));
            s_pgfs_files[i].used = 1;
            if (pgfs_path_copy(s_pgfs_files[i].path, sizeof(s_pgfs_files[i].path), path) != 0) {
                memset(&s_pgfs_files[i], 0, sizeof(s_pgfs_files[i]));
                return NULL;
            }
            return &s_pgfs_files[i];
        }
    }
    return NULL;
}

void pgfs_file_reset_all(void) {
    size_t i = 0;
    for (i = 0; i < PGFS_MAX_FILES; i++) {
        if (s_pgfs_files[i].data) {
            pgfs_heap_free_by_type(s_pgfs_files[i].heap_type, s_pgfs_files[i].data);
        }
        memset(&s_pgfs_files[i], 0, sizeof(s_pgfs_files[i]));
    }
    for (i = 0; i < PGFS_MAX_DIRS; i++) {
        memset(&s_pgfs_dirs[i], 0, sizeof(s_pgfs_dirs[i]));
    }
    pgfs_batch_pending_reset_all();
}

int pgfs_file_remove(pgfs_mount_ctx_t* ctx, const char *filename) {
    pgfs_file_entry_t* e = NULL;
    char norm[sizeof(s_pgfs_files[0].path)] = {0};
    (void)ctx;
    if (filename == NULL) {
        return -1;
    }
    if (pgfs_path_normalize(filename, norm, sizeof(norm)) != 0 || norm[0] == '\0') {
        return -1;
    }
    e = pgfs_find_file_norm(norm);
    if (e == NULL) {
        return -1;
    }
    if (e->data) {
        pgfs_heap_free_by_type(e->heap_type, e->data);
    }
    memset(e, 0, sizeof(*e));
    return 0;
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
    if (ctx->flash_opts->erase(ctx->flash_opts->ctx, erase_start, erase_end - erase_start) != 0) {
        LLOGE("prepare region erase failed addr=%u size=%u", (unsigned int)erase_start, (unsigned int)(erase_end - erase_start));
        return -1;
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
    int retried = 0;
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
        LLOGE("append_data out-of-cap addr=%u write_len=%u end=%u cap=%u base=%u",
              (unsigned int)addr, (unsigned int)write_len, (unsigned int)end_addr,
              (unsigned int)geo.capacity, (unsigned int)pgfs_data_log_base_addr(ctx));
        return -1;
    }
    if (pgfs_prepare_data_log_region(ctx, addr, write_len) != 0) {
        if (!retried && pgfs_relocate_unaligned_write_head(ctx, addr, write_len, &addr) == 0) {
            retried = 1;
            LLOGW("append_data relocate write head to %u", (unsigned int)addr);
            goto retry_prepare;
        }
        return -1;
    }
    if (ctx->flash_opts->write(ctx->flash_opts->ctx, addr, hdr, hdr_len) != 0 ||
        (path_len != 0 && ctx->flash_opts->write(ctx->flash_opts->ctx, addr + (uint32_t)hdr_len, path, path_len) != 0) ||
        (data_len != 0 && ctx->flash_opts->write(ctx->flash_opts->ctx, addr + (uint32_t)hdr_len + path_len, data, data_len) != 0)) {
        if (!retried && ctx->flash_opts->control != NULL &&
            ctx->flash_opts->control(ctx->flash_opts->ctx, PGFS_CTRL_GET_GEOMETRY, &geo) == 0 &&
            geo.erase_size != 0) {
            uint32_t next_addr = pgfs_align_up_u32(addr + 1u, geo.erase_size);
            uint64_t next_end = (uint64_t)next_addr + (uint64_t)write_len;
            if (next_addr > addr && (geo.capacity == 0 || next_end <= geo.capacity)) {
                LLOGW("append_data write failed at addr=%u, retry next block=%u", (unsigned int)addr, (unsigned int)next_addr);
                addr = next_addr;
                ctx->data_log_prepared_until = next_addr;
                retried = 1;
                goto retry_prepare;
            }
        }
        return -1;
    }
    ctx->data_log_write_addr = (uint32_t)end_addr;
    return 0;
}

static int pgfs_append_data_record(pgfs_mount_ctx_t* ctx, pgfs_file_t* f) {
    pgfs_data_record_hdr_t hdr = {0};
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
    hdr.crc32 = luat_crc32((const uint8_t*)f->entry->path, hdr.path_len, 0xFFFFFFFFu, 0);
    if (hdr.data_len != 0) {
        hdr.crc32 = luat_crc32(f->cache.data, hdr.data_len, hdr.crc32, 0);
    }
    return pgfs_append_log_record(ctx, (const uint8_t*)&hdr, sizeof(hdr),
                                  (const uint8_t*)f->entry->path, hdr.path_len,
                                  f->cache.data, hdr.data_len);
}

static int pgfs_append_batch_data_record(pgfs_mount_ctx_t* ctx, pgfs_batch_pending_entry_t* p) {
    pgfs_batch_data_record_hdr_t hdr = {0};
    if (ctx == NULL || p == NULL || !p->used || p->batch_id == 0) {
        return -1;
    }
    hdr.magic = PGFS_BATCH_DATA_RECORD_MAGIC;
    hdr.path_len = (uint32_t)strlen(p->path);
    hdr.data_len = (uint32_t)p->len;
    hdr.batch_id = p->batch_id;
    hdr.crc32 = luat_crc32((const uint8_t*)p->path, hdr.path_len, 0xFFFFFFFFu, 0);
    if (hdr.data_len != 0) {
        hdr.crc32 = luat_crc32(p->data, hdr.data_len, hdr.crc32, 0);
    }
    return pgfs_append_log_record(ctx, (const uint8_t*)&hdr, sizeof(hdr),
                                  (const uint8_t*)p->path, hdr.path_len,
                                  p->data, hdr.data_len);
}

static int pgfs_append_batch_commit_record(pgfs_mount_ctx_t* ctx, uint32_t batch_id, uint32_t record_count) {
    pgfs_batch_commit_record_hdr_t hdr = {0};
    if (ctx == NULL || batch_id == 0) {
        return -1;
    }
    hdr.magic = PGFS_BATCH_COMMIT_RECORD_MAGIC;
    hdr.batch_id = batch_id;
    hdr.record_count = record_count;
    hdr.crc32 = pgfs_crc32_calc(&hdr, sizeof(hdr) - sizeof(hdr.crc32));
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
    char path[sizeof(s_pgfs_files[0].path)];
    uint8_t* data;
    uint32_t len;
} pgfs_replay_pending_entry_t;

static void pgfs_replay_pending_drop_all(pgfs_replay_pending_entry_t* pending) {
    size_t i = 0;
    if (pending == NULL) {
        return;
    }
    for (i = 0; i < PGFS_MAX_BATCH_PENDING; i++) {
        if (pending[i].data != NULL) {
            pgfs_heap_free_by_type(pending[i].heap_type, pending[i].data);
        }
        memset(&pending[i], 0, sizeof(pending[i]));
    }
}

static int pgfs_replay_pending_stage(pgfs_replay_pending_entry_t* pending, uint32_t batch_id,
                                     const char* path, const uint8_t* data, uint32_t len) {
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
        char parent[sizeof(s_pgfs_dirs[0].path)] = {0};
        if (!p->used || p->batch_id != batch_id) {
            continue;
        }
        if (pgfs_path_parent(p->path, parent, sizeof(parent)) != 0 || pgfs_dir_ensure_norm(parent) != 0) {
            return -1;
        }
        entry = pgfs_alloc_file(p->path);
        if (entry == NULL) {
            return -1;
        }
        old_len = entry->len;
        if (entry->data != NULL) {
            pgfs_heap_free_by_type(entry->heap_type, entry->data);
        }
        entry->data = p->data;
        entry->len = p->len;
        entry->cap = p->len;
        entry->heap_type = p->heap_type;
        p->data = NULL;
        ctx->checkpoint.gc_live_bytes += entry->len;
        if (old_len > 0) {
            ctx->checkpoint.gc_dead_bytes += (uint32_t)old_len;
        }
        ctx->checkpoint.used_blocks += 1u;
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

int pgfs_replay_data_log(pgfs_mount_ctx_t* ctx) {
    pgfs_flash_geometry_t geo = {0};
    uint32_t base = pgfs_data_log_base_addr(ctx);
    uint32_t addr = base;
    uint32_t limit = 0;
    pgfs_replay_pending_entry_t pending[PGFS_MAX_BATCH_PENDING];

    if (ctx == NULL || ctx->flash_opts == NULL || ctx->flash_opts->read == NULL) {
        return -1;
    }
    memset(pending, 0, sizeof(pending));

    ctx->checkpoint.used_blocks = 0;
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
    while (1) {
        uint32_t magic = 0;
        uint32_t path_len = 0;
        uint32_t data_len = 0;
        uint32_t batch_id = 0;
        uint32_t crc32 = 0;
        size_t hdr_len = 0;
        char norm[sizeof(s_pgfs_files[0].path)] = {0};
        char parent[sizeof(s_pgfs_dirs[0].path)] = {0};
        uint8_t* path_buf = NULL;
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
            path_len = hdr.path_len;
            data_len = hdr.data_len;
            crc32 = hdr.crc32;
            hdr_len = sizeof(hdr);
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
            path_len = hdr.path_len;
            data_len = hdr.data_len;
            batch_id = hdr.batch_id;
            crc32 = hdr.crc32;
            hdr_len = sizeof(hdr);
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
            hdr_crc = pgfs_crc32_calc(&hdr, sizeof(hdr) - sizeof(hdr.crc32));
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
                pgfs_replay_pending_drop_all(pending);
                return -1;
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
        path_buf = (uint8_t*)luat_heap_malloc((size_t)path_len + 1u);
        if (path_buf == NULL) {
            pgfs_replay_pending_drop_all(pending);
            return -1;
        }
        data_buf = data_len == 0 ? NULL : (uint8_t*)luat_heap_malloc((size_t)data_len);
        if (data_len != 0 && data_buf == NULL) {
            luat_heap_free(path_buf);
            pgfs_replay_pending_drop_all(pending);
            return -1;
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
            uint8_t* crc_buf = (uint8_t*)luat_heap_malloc(crc_len);
            if (crc_buf == NULL) {
                luat_heap_free(path_buf);
                luat_heap_free(data_buf);
                pgfs_replay_pending_drop_all(pending);
                return -1;
            }
            memcpy(crc_buf, path_buf, path_len);
            if (data_len != 0) {
                memcpy(crc_buf + path_len, data_buf, data_len);
            }
            crc = pgfs_crc32_calc(crc_buf, crc_len);
            luat_heap_free(crc_buf);
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
            if (pgfs_path_parent(norm, parent, sizeof(parent)) != 0 || pgfs_dir_ensure_norm(parent) != 0) {
                luat_heap_free(path_buf);
                luat_heap_free(data_buf);
                pgfs_replay_pending_drop_all(pending);
                return -1;
            }
            entry = pgfs_alloc_file(norm);
            if (entry == NULL) {
                luat_heap_free(path_buf);
                luat_heap_free(data_buf);
                pgfs_replay_pending_drop_all(pending);
                return -1;
            }
            old_len = entry->len;
            if (data_len != 0) {
                if (pgfs_file_reserve(entry, data_len) != 0) {
                    luat_heap_free(path_buf);
                    luat_heap_free(data_buf);
                    pgfs_replay_pending_drop_all(pending);
                    return -1;
                }
                memcpy(entry->data, data_buf, data_len);
            }
            entry->len = data_len;
            ctx->checkpoint.gc_live_bytes += data_len;
            if (old_len > 0) {
                ctx->checkpoint.gc_dead_bytes += (uint32_t)old_len;
            }
            ctx->checkpoint.used_blocks += 1u;
        }
        else {
            if (pgfs_replay_pending_stage(pending, batch_id, norm, data_buf, data_len) != 0) {
                luat_heap_free(path_buf);
                luat_heap_free(data_buf);
                pgfs_replay_pending_drop_all(pending);
                return -1;
            }
        }
        ctx->data_log_write_addr = (uint32_t)next_addr;
        luat_heap_free(path_buf);
        luat_heap_free(data_buf);
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
    return 0;
}

static int pgfs_apply_cache_to_entry(pgfs_file_t* f) {
    pgfs_file_entry_t* e = NULL;
    size_t old_len = 0;
    if (f == NULL || f->entry == NULL || f->cache.len == 0) {
        return 0;
    }
    e = f->entry;
    old_len = e->len;
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
    if (f->ctx) {
        f->ctx->checkpoint.gc_live_bytes += (uint32_t)e->len;
        if (old_len > 0) {
            f->ctx->checkpoint.gc_dead_bytes += (uint32_t)old_len;
        }
    }
    return 0;
}

FILE* pgfs_file_open(pgfs_mount_ctx_t* ctx, const char *filename, const char *mode) {
    pgfs_file_t* f = NULL;
    pgfs_file_entry_t* e = NULL;
    char norm[sizeof(s_pgfs_files[0].path)] = {0};
    char parent[sizeof(s_pgfs_dirs[0].path)] = {0};
    if (ctx == NULL || filename == NULL || mode == NULL) {
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
        if (pgfs_path_parent(norm, parent, sizeof(parent)) != 0 || pgfs_dir_ensure_norm(parent) != 0) {
            pgfs_unlock(ctx);
            return NULL;
        }
        if (!ctx->batch_active) {
            e = pgfs_alloc_file(norm);
        }
    }
    else {
        e = pgfs_find_file_norm(norm);
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
    if (e != NULL && strchr(mode, 'a')) {
        f->pos = e->len;
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
        t0 = luat_mcu_tick64_ms();
        (void)pgfs_gc_step(ctx, 4096, 2000);
        t_gc = luat_mcu_tick64_ms();
        if (pgfs_alloc_segment(ctx, &seg_id) != 0) {
            LLOGE("close alloc_segment failed");
            ret = -1;
            goto finish;
        }
        t_alloc = luat_mcu_tick64_ms();
        if (pgfs_cache_flush_to_log(ctx, f) != 0) {
            LLOGE("close cache_flush failed");
            ret = -1;
            goto finish;
        }
        if (pgfs_append_data_record(ctx, f) != 0) {
            LLOGE("close append_data_record failed addr=%u", (unsigned int)ctx->data_log_write_addr);
            (void)pgfs_mark_block_retired(ctx, seg_id);
            ret = -1;
            goto finish;
        }
        t_append = luat_mcu_tick64_ms();
        if (pgfs_apply_cache_to_entry(f) != 0) {
            LLOGE("close apply_cache failed");
            ret = -1;
            goto finish;
        }
        t_apply = luat_mcu_tick64_ms();
        ctx->checkpoint.used_blocks = (uint32_t)(ctx->checkpoint.used_blocks + 1u);
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
    char norm[sizeof(s_pgfs_dirs[0].path)] = {0};
    int ret = 0;
    if (path == NULL) {
        return -1;
    }
    if (pgfs_path_normalize(path, norm, sizeof(norm)) != 0) {
        return -1;
    }
    if (ctx != NULL && pgfs_lock(ctx) != 0) {
        return -1;
    }
    ret = pgfs_dir_ensure_norm(norm);
    if (ctx != NULL) {
        pgfs_unlock(ctx);
    }
    return ret;
}

int pgfs_dir_rmdir(pgfs_mount_ctx_t* ctx, const char *path) {
    char norm[sizeof(s_pgfs_dirs[0].path)] = {0};
    int ret = -1;
    if (path == NULL) {
        return -1;
    }
    if (pgfs_path_normalize(path, norm, sizeof(norm)) != 0) {
        return -1;
    }
    if (ctx != NULL && pgfs_lock(ctx) != 0) {
        return -1;
    }
    ret = pgfs_dir_remove_norm(norm);
    if (ctx != NULL) {
        pgfs_unlock(ctx);
    }
    return ret;
}

int pgfs_dir_lsdir(pgfs_mount_ctx_t* ctx, const char *path, luat_fs_dirent_t* ents, size_t offset, size_t len) {
    int ret = 0;
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
    char norm[sizeof(s_pgfs_dirs[0].path)] = {0};
    if (path == NULL) {
        return NULL;
    }
    if (pgfs_path_normalize(path, norm, sizeof(norm)) != 0) {
        return NULL;
    }
    if (ctx != NULL && pgfs_lock(ctx) != 0) {
        return NULL;
    }
    if (!pgfs_dir_exists_norm(norm)) {
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
    size_t want = size * nmemb;
    size_t left = 0;
    size_t take = 0;
    (void)ctx;
    if (ptr == NULL || f == NULL || f->entry == NULL || !f->mode_read || size == 0 || nmemb == 0) {
        return 0;
    }
    if (!pgfs_ctx_handle_valid(ctx, f->generation)) {
        return 0;
    }
    if (f->pos >= f->entry->len) {
        f->eof = 1;
        return 0;
    }
    left = f->entry->len - f->pos;
    take = want < left ? want : left;
    memcpy(ptr, f->entry->data + f->pos, take);
    f->pos += take;
    f->eof = (f->pos >= f->entry->len) ? 1 : 0;
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
    if (f->pos >= f->entry->len) {
        f->eof = 1;
        return -1;
    }
    ch = (int)((uint8_t)f->entry->data[f->pos]);
    f->pos++;
    f->eof = (f->pos >= f->entry->len) ? 1 : 0;
    return ch;
}

size_t pgfs_file_write(pgfs_mount_ctx_t* ctx, const void *ptr, size_t size, size_t nmemb, FILE *stream) {
    pgfs_file_t* f = (pgfs_file_t*)stream;
    size_t total = size * nmemb;
    (void)ctx;
    if (f == NULL || ptr == NULL || !f->mode_write || size == 0 || nmemb == 0) {
        return 0;
    }
    if (!pgfs_ctx_handle_valid(ctx, f->generation)) {
        return 0;
    }
    if (!pgfs_batch_handle_match(ctx, f)) {
        return 0;
    }
    if (pgfs_cache_append(f, (const uint8_t*)ptr, total) != 0) {
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
    if (pgfs_cache_flush_to_log(ctx, f) != 0) {
        f->err = 1;
        pgfs_unlock(ctx);
        return -1;
    }
    pgfs_unlock(ctx);
    return 0;
}

#endif
