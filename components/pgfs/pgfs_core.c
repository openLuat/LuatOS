#include "luat_base.h"
#include "pgfs_internal.h"
#include "luat_mem.h"
#include "luat_crypto.h"

#ifdef LUAT_USE_PGFS_COMPONENT

#define PGFS_MAX_FILES 512
#define PGFS_DATA_RECORD_MAGIC 0x50474644u

typedef struct pgfs_data_record_hdr {
    uint32_t magic;
    uint32_t path_len;
    uint32_t data_len;
    uint32_t crc32;
} pgfs_data_record_hdr_t;

static pgfs_file_entry_t s_pgfs_files[PGFS_MAX_FILES];
static pgfs_dir_entry_t s_pgfs_dirs[PGFS_MAX_DIRS];

static uint32_t pgfs_crc32_calc(const void* data, size_t len) {
    return luat_crc32(data, (uint32_t)len, 0xFFFFFFFFu, 0);
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

static pgfs_file_entry_t* pgfs_alloc_file(const char* path) {
    size_t i = 0;
    if (path == NULL || path[0] == '\0') {
        return NULL;
    }
    if (pgfs_dir_exists_norm(path)) {
        return NULL;
    }
    pgfs_file_entry_t* e = pgfs_find_file_norm(path);
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
            luat_heap_free(s_pgfs_files[i].data);
        }
        memset(&s_pgfs_files[i], 0, sizeof(s_pgfs_files[i]));
    }
    for (i = 0; i < PGFS_MAX_DIRS; i++) {
        memset(&s_pgfs_dirs[i], 0, sizeof(s_pgfs_dirs[i]));
    }
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
        luat_heap_free(e->data);
    }
    memset(e, 0, sizeof(*e));
    return 0;
}

static int pgfs_file_reserve(pgfs_file_entry_t* e, size_t need) {
    size_t target = 0;
    uint8_t* p = NULL;
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
    p = (uint8_t*)luat_heap_realloc(e->data, target);
    if (!p) {
        return -1;
    }
    e->data = p;
    e->cap = target;
    return 0;
}

static int pgfs_append_data_record(pgfs_mount_ctx_t* ctx, pgfs_file_t* f) {
    pgfs_data_record_hdr_t hdr = {0};
    uint8_t* rec_buf = NULL;
    size_t rec_len = 0;
    uint64_t end_addr = 0;
    pgfs_flash_geometry_t geo = {0};
    uint32_t addr = 0;
    if (ctx == NULL || f == NULL || f->entry == NULL || f->cache.len == 0 ||
        ctx->flash_opts == NULL || ctx->flash_opts->write == NULL) {
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
    rec_len = sizeof(hdr) + (size_t)hdr.path_len + (size_t)hdr.data_len;
    rec_buf = (uint8_t*)luat_heap_malloc(rec_len);
    if (rec_buf == NULL) {
        return -1;
    }
    memcpy(rec_buf + sizeof(hdr), f->entry->path, hdr.path_len);
    memcpy(rec_buf + sizeof(hdr) + hdr.path_len, f->cache.data, f->cache.len);
    hdr.crc32 = pgfs_crc32_calc(rec_buf + sizeof(hdr), (size_t)hdr.path_len + (size_t)hdr.data_len);
    memcpy(rec_buf, &hdr, sizeof(hdr));

    addr = ctx->data_log_write_addr;
    end_addr = (uint64_t)addr + (uint64_t)rec_len;
    if (ctx->flash_opts->control != NULL &&
        ctx->flash_opts->control(ctx->flash_opts->ctx, PGFS_CTRL_GET_GEOMETRY, &geo) == 0 &&
        geo.capacity > PGFS_DATA_LOG_BASE_ADDR &&
        end_addr > geo.capacity) {
        luat_heap_free(rec_buf);
        return -1;
    }
    if (ctx->flash_opts->write(ctx->flash_opts->ctx, addr, rec_buf, rec_len) != 0) {
        luat_heap_free(rec_buf);
        return -1;
    }
    luat_heap_free(rec_buf);
    ctx->data_log_write_addr = (uint32_t)end_addr;
    return 0;
}

static int pgfs_replay_flash_read(pgfs_mount_ctx_t* ctx, uint32_t addr, void* buf, size_t len) {
    if (ctx == NULL || ctx->flash_opts == NULL || ctx->flash_opts->read == NULL || buf == NULL || len == 0) {
        return -1;
    }
    return ctx->flash_opts->read(ctx->flash_opts->ctx, addr, (uint8_t*)buf, len);
}

int pgfs_replay_data_log(pgfs_mount_ctx_t* ctx) {
    pgfs_flash_geometry_t geo = {0};
    uint32_t addr = PGFS_DATA_LOG_BASE_ADDR;
    uint32_t limit = 0;

    if (ctx == NULL || ctx->flash_opts == NULL || ctx->flash_opts->read == NULL) {
        return -1;
    }

    ctx->checkpoint.used_blocks = 0;
    ctx->checkpoint.gc_live_bytes = 0;
    ctx->checkpoint.gc_dead_bytes = 0;

    if (ctx->flash_opts->control != NULL &&
        ctx->flash_opts->control(ctx->flash_opts->ctx, PGFS_CTRL_GET_GEOMETRY, &geo) == 0 &&
        geo.capacity > PGFS_DATA_LOG_BASE_ADDR) {
        limit = geo.capacity;
    }
    else {
        limit = 0;
    }

    while (1) {
        pgfs_data_record_hdr_t hdr = {0};
        uint8_t* path_buf = NULL;
        uint8_t* data_buf = NULL;
        char norm[sizeof(s_pgfs_files[0].path)] = {0};
        char parent[sizeof(s_pgfs_dirs[0].path)] = {0};
        pgfs_file_entry_t* entry = NULL;
        size_t old_len = 0;
        uint64_t record_len = 0;
        uint64_t next_addr = 0;
        uint32_t crc = 0;
        size_t crc_len = 0;

        if (limit != 0 && addr + sizeof(hdr) > limit) {
            break;
        }
        if (pgfs_replay_flash_read(ctx, addr, &hdr, sizeof(hdr)) != 0) {
            break;
        }
        if (hdr.magic != PGFS_DATA_RECORD_MAGIC || hdr.path_len == 0) {
            break;
        }
        if (hdr.path_len >= sizeof(norm)) {
            break;
        }
        record_len = (uint64_t)sizeof(hdr) + (uint64_t)hdr.path_len + (uint64_t)hdr.data_len;
        next_addr = (uint64_t)addr + record_len;
        if (record_len < sizeof(hdr) || (limit != 0 && next_addr > limit)) {
            break;
        }
        path_buf = (uint8_t*)luat_heap_malloc((size_t)hdr.path_len + 1u);
        if (path_buf == NULL) {
            return -1;
        }
        data_buf = hdr.data_len == 0 ? NULL : (uint8_t*)luat_heap_malloc((size_t)hdr.data_len);
        if (hdr.data_len != 0 && data_buf == NULL) {
            luat_heap_free(path_buf);
            return -1;
        }
        if (pgfs_replay_flash_read(ctx, addr + (uint32_t)sizeof(hdr), path_buf, hdr.path_len) != 0) {
            luat_heap_free(path_buf);
            luat_heap_free(data_buf);
            break;
        }
        path_buf[hdr.path_len] = '\0';
        if (hdr.data_len != 0 &&
            pgfs_replay_flash_read(ctx, addr + (uint32_t)sizeof(hdr) + hdr.path_len, data_buf, hdr.data_len) != 0) {
            luat_heap_free(path_buf);
            luat_heap_free(data_buf);
            break;
        }
        crc_len = (size_t)hdr.path_len + (size_t)hdr.data_len;
        if (crc_len > 0) {
            uint8_t* crc_buf = (uint8_t*)luat_heap_malloc(crc_len);
            if (crc_buf == NULL) {
                luat_heap_free(path_buf);
                luat_heap_free(data_buf);
                return -1;
            }
            memcpy(crc_buf, path_buf, hdr.path_len);
            if (hdr.data_len != 0) {
                memcpy(crc_buf + hdr.path_len, data_buf, hdr.data_len);
            }
            crc = pgfs_crc32_calc(crc_buf, crc_len);
            luat_heap_free(crc_buf);
        }
        if (crc != hdr.crc32) {
            luat_heap_free(path_buf);
            luat_heap_free(data_buf);
            break;
        }
        if (pgfs_path_normalize((const char*)path_buf, norm, sizeof(norm)) != 0 || norm[0] == '\0') {
            luat_heap_free(path_buf);
            luat_heap_free(data_buf);
            break;
        }
        if (pgfs_path_parent(norm, parent, sizeof(parent)) != 0 || pgfs_dir_ensure_norm(parent) != 0) {
            luat_heap_free(path_buf);
            luat_heap_free(data_buf);
            return -1;
        }
        entry = pgfs_alloc_file(norm);
        if (entry == NULL) {
            luat_heap_free(path_buf);
            luat_heap_free(data_buf);
            return -1;
        }
        old_len = entry->len;
        if (hdr.data_len != 0) {
            if (pgfs_file_reserve(entry, hdr.data_len) != 0) {
                luat_heap_free(path_buf);
                luat_heap_free(data_buf);
                return -1;
            }
            memcpy(entry->data, data_buf, hdr.data_len);
        }
        entry->len = hdr.data_len;
        ctx->checkpoint.gc_live_bytes += hdr.data_len;
        if (old_len > 0) {
            ctx->checkpoint.gc_dead_bytes += (uint32_t)old_len;
        }
        ctx->checkpoint.used_blocks += 1u;
        ctx->data_log_write_addr = (uint32_t)next_addr;
        luat_heap_free(path_buf);
        luat_heap_free(data_buf);
        addr = (uint32_t)next_addr;
    }

    if (ctx->data_log_write_addr < PGFS_DATA_LOG_BASE_ADDR) {
        ctx->data_log_write_addr = PGFS_DATA_LOG_BASE_ADDR;
    }
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
    if (pgfs_file_reserve(e, f->cache.len) != 0) {
        return -1;
    }
    memcpy(e->data, f->cache.data, f->cache.len);
    e->len = f->cache.len;
    if (f->ctx) {
        f->ctx->checkpoint.gc_live_bytes += (uint32_t)f->cache.len;
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
        e = pgfs_alloc_file(norm);
    }
    else {
        e = pgfs_find_file_norm(norm);
    }
    if (e == NULL) {
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
    f->pos = 0;
    if (strchr(mode, 'a')) {
        f->pos = e->len;
    }
    pgfs_unlock(ctx);
    return (FILE*)f;
}

int pgfs_file_close(pgfs_mount_ctx_t* ctx, FILE* stream) {
    pgfs_file_t* f = (pgfs_file_t*)stream;
    int ret = 0;
    uint32_t seg_id = 0;
    if (ctx == NULL || f == NULL) {
        return -1;
    }
    if (!pgfs_ctx_handle_valid(ctx, f->generation)) {
        if (f->cache.data) {
            luat_heap_free(f->cache.data);
        }
        luat_heap_free(f);
        return -1;
    }

    if (pgfs_lock(ctx) != 0) {
        return -1;
    }
    if (f->mode_write) {
        (void)pgfs_gc_step(ctx, 4096, 2000);
        (void)pgfs_alloc_segment(ctx, &seg_id);
        if (pgfs_cache_flush_to_log(ctx, f) != 0) {
            ret = -1;
            goto finish;
        }
        if (pgfs_append_data_record(ctx, f) != 0) {
            (void)pgfs_mark_block_retired(ctx, seg_id);
            ret = -1;
            goto finish;
        }
        if (pgfs_apply_cache_to_entry(f) != 0) {
            ret = -1;
            goto finish;
        }
        if (ctx->inject_powercut_stage == PGFS_INJECT_POWERCUT_BEFORE_CP) {
            ctx->inject_powercut_stage = PGFS_INJECT_POWERCUT_NONE;
            ctx->stats.powercut_inject_count++;
            ret = -1;
            goto finish;
        }
        if (pgfs_checkpoint_store_next(ctx, &ctx->checkpoint, &ctx->checkpoint) != 0) {
            ret = -1;
            goto finish;
        }
        ctx->checkpoint_loaded = 1;
        ctx->checkpoint.used_blocks = (uint32_t)(ctx->checkpoint.used_blocks + 1u);
    }
finish:
    if (f->cache.data) {
        luat_heap_free(f->cache.data);
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
    if (!f->mode_write) {
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
