#include "luat_lfs2_nand.h"

#include "luat_lfs2.h"
#include "luat_fs.h"
#include "luat_mem.h"
#include "luat_mcu.h"
#include "luat_fs_lfs2_nand_metadata.h"
#include "luat_log.h"

#define LUAT_LOG_TAG "vfs.lfs2_nand"

#ifdef LUAT_USE_FS_VFS

#ifndef LUAT_LFS2N_DEBUG_LOG
#define LUAT_LFS2N_DEBUG_LOG 0
#endif

#ifndef LUAT_LFS2N_PERF_LOG
#define LUAT_LFS2N_PERF_LOG 0
#endif

#define LFS2N_DEBUG_LOG(...) do { if (LUAT_LFS2N_DEBUG_LOG) { LLOGD(__VA_ARGS__); } } while (0)
#define LFS2N_PERF_LOG(...)  do { if (LUAT_LFS2N_PERF_LOG)  { LLOGD(__VA_ARGS__); } } while (0)

#define NAND_FS_NAME "lfsn"
#define LFS2_NAND_META_SLOT0 ".lfsn_space.meta0"
#define LFS2_NAND_META_SLOT1 ".lfsn_space.meta1"

extern int luat_vfs_lfs2_nand_base_mkfs(void* userdata, luat_fs_conf_t *conf);
extern int luat_vfs_lfs2_nand_base_umount(void* userdata, luat_fs_conf_t *conf);
extern int luat_vfs_lfs2_nand_base_mkdir(void* userdata, char const* _DirName);
extern int luat_vfs_lfs2_nand_base_rmdir(void* userdata, char const* _DirName);
extern int luat_vfs_lfs2_nand_base_lsdir(void* userdata, char const* _DirName, luat_fs_dirent_t* ents, size_t offset, size_t len);
extern int luat_vfs_lfs2_nand_base_remove(void* userdata, const char *filename);
extern int luat_vfs_lfs2_nand_base_rename(void* userdata, const char *old_filename, const char *new_filename);
extern size_t luat_vfs_lfs2_nand_base_fsize(void* userdata, const char *filename);
extern int luat_vfs_lfs2_nand_base_fexist(void* userdata, const char *filename);
extern int luat_vfs_lfs2_nand_base_info(void* userdata, const char* path, luat_fs_info_t *conf);
extern int luat_vfs_lfs2_nand_base_truncate(void* userdata, const char *filename, size_t len);
extern void* luat_vfs_lfs2_nand_base_opendir(void* userdata, const char *_DirName);
extern int luat_vfs_lfs2_nand_base_closedir(void* userdata, void* dir);
extern FILE* luat_vfs_lfs2_nand_base_fopen(void* userdata, const char *filename, const char *mode);
extern int luat_vfs_lfs2_nand_base_getc(void* userdata, FILE* stream);
extern int luat_vfs_lfs2_nand_base_fseek(void* userdata, FILE* stream, long int offset, int origin);
extern int luat_vfs_lfs2_nand_base_ftell(void* userdata, FILE* stream);
extern int luat_vfs_lfs2_nand_base_fclose(void* userdata, FILE* stream);
extern int luat_vfs_lfs2_nand_base_feof(void* userdata, FILE* stream);
extern int luat_vfs_lfs2_nand_base_ferror(void* userdata, FILE *stream);
extern size_t luat_vfs_lfs2_nand_base_fread(void* userdata, void *ptr, size_t size, size_t nmemb, FILE *stream);
extern size_t luat_vfs_lfs2_nand_base_fwrite(void* userdata, const void *ptr, size_t size, size_t nmemb, FILE *stream);
extern int luat_vfs_lfs2_nand_base_fflush(void* userdata, FILE *stream);
#ifdef LUAT_USE_LITTLE_FLASH
extern void luat_lfs2n_block_profile_reset(void);
extern void luat_lfs2n_block_profile_log(const char* prefix);
#endif

extern luat_lfs2_t* luat_lfs2_nand_flash_lfs_lf(void* flash, size_t offset, size_t maxsize);

typedef struct {
    void* userdata;
} luat_vfs_lfs2_nand_meta_ctx_t;

#define LFS2_NAND_WRITE_CACHE_LIMIT (256 * 1024)
#define LFS2_NAND_WRITE_CACHE_SLOTS 8
#define LFS2_NAND_WRITE_CACHE_CHUNK 4096
#define LFS2_NAND_SLOW_OP_US (5000u)

typedef struct {
    FILE* stream;
    uint8_t* data;
    size_t len;
    size_t cap;
} luat_vfs_lfs2_nand_write_cache_t;

static luat_vfs_lfs2_nand_write_cache_t g_lfs2_nand_write_cache[LFS2_NAND_WRITE_CACHE_SLOTS];
static uint8_t g_lfs2_nand_space_meta_dirty = 0;
static uint32_t g_lfs2_nand_meta_refresh_count = 0;
static uint64_t g_lfs2_nand_meta_refresh_us = 0;
static uint32_t g_lfs2_nand_cache_flush_count = 0;
static uint64_t g_lfs2_nand_cache_flush_us = 0;
static uint64_t g_lfs2_nand_cache_flush_bytes = 0;
// Metadata refresh throttling: Only refresh if dirty AND enough time has passed since last refresh
// This prevents rapid-fire refresh calls that occur during high-frequency metadata queries
static uint64_t g_lfs2_nand_meta_last_refresh_us = 0;
#define LFS2_NAND_META_REFRESH_MIN_INTERVAL_US (100000u)  // 100ms minimum between refreshes

static uint64_t luat_vfs_lfs2_nand_now_us(void) {
    uint64_t tick = luat_mcu_tick64();
    uint32_t tick_per_us = luat_mcu_us_period();
    if (tick_per_us == 0) {
        tick_per_us = 1;
    }
    return tick / tick_per_us;
}

static void luat_vfs_lfs2_nand_log_slow(const char* op, const char* detail, uint64_t cost_us) {
    if (cost_us >= LFS2_NAND_SLOW_OP_US) {
        LFS2N_PERF_LOG("%s slow %s cost=%llu us", op, detail ? detail : "", (unsigned long long)cost_us);
    }
}

static const char* luat_vfs_lfs2_nand_meta_slot_path(uint32_t slot) {
    return (slot == 0) ? LFS2_NAND_META_SLOT0 : LFS2_NAND_META_SLOT1;
}

static void luat_vfs_lfs2_nand_meta_log(void* ctx, const char* message) {
    (void)ctx;
    LFS2N_PERF_LOG("%s", message);
}

static int luat_vfs_lfs2_nand_meta_scan(void* ctx, uint32_t* used, uint32_t* total) {
    luat_fs_info_t info = {0};
    luat_vfs_lfs2_nand_meta_ctx_t* meta_ctx = (luat_vfs_lfs2_nand_meta_ctx_t*)ctx;
    if (!meta_ctx || !used || !total) {
        return -1;
    }
    if (luat_vfs_lfs2_nand_base_info(meta_ctx->userdata, "", &info) != 0) {
        return -1;
    }
    *used = (uint32_t)info.block_used;
    *total = (uint32_t)info.total_block;
    return 0;
}

static int luat_vfs_lfs2_nand_meta_read_slot(void* ctx, uint32_t slot, luat_lfs2_nand_space_meta_t* out) {
    luat_vfs_lfs2_nand_meta_ctx_t* meta_ctx = (luat_vfs_lfs2_nand_meta_ctx_t*)ctx;
    FILE* fd = NULL;
    size_t read_len = 0;

    if (!meta_ctx || !out) {
        return -1;
    }
    fd = luat_vfs_lfs2_nand_base_fopen(meta_ctx->userdata, luat_vfs_lfs2_nand_meta_slot_path(slot), "rb");
    if (!fd) {
        return -1;
    }
    read_len = luat_vfs_lfs2_nand_base_fread(meta_ctx->userdata, out, 1, sizeof(*out), fd);
    luat_vfs_lfs2_nand_base_fclose(meta_ctx->userdata, fd);
    return (read_len == sizeof(*out)) ? 0 : -1;
}

static int luat_vfs_lfs2_nand_meta_write_slot(void* ctx, uint32_t slot, const luat_lfs2_nand_space_meta_t* meta) {
    luat_vfs_lfs2_nand_meta_ctx_t* meta_ctx = (luat_vfs_lfs2_nand_meta_ctx_t*)ctx;
    FILE* fd = NULL;
    size_t write_len = 0;
    int flush_rc = -1;
    int close_rc = -1;

    if (!meta_ctx || !meta) {
        return -1;
    }
    fd = luat_vfs_lfs2_nand_base_fopen(meta_ctx->userdata, luat_vfs_lfs2_nand_meta_slot_path(slot), "wb");
    if (!fd) {
        return -1;
    }
    write_len = luat_vfs_lfs2_nand_base_fwrite(meta_ctx->userdata, meta, 1, sizeof(*meta), fd);
    flush_rc = luat_vfs_lfs2_nand_base_fflush(meta_ctx->userdata, fd);
    close_rc = luat_vfs_lfs2_nand_base_fclose(meta_ctx->userdata, fd);
    return (write_len == sizeof(*meta) && flush_rc == 0 && close_rc == 0) ? 0 : -1;
}

static luat_lfs2_nand_space_meta_ops_t luat_vfs_lfs2_nand_meta_ops(void* userdata, luat_vfs_lfs2_nand_meta_ctx_t* ctx) {
    luat_lfs2_nand_space_meta_ops_t ops = {0};
    ctx->userdata = userdata;
    ops.ctx = ctx;
    ops.read_slot = luat_vfs_lfs2_nand_meta_read_slot;
    ops.write_slot = luat_vfs_lfs2_nand_meta_write_slot;
    ops.scan = luat_vfs_lfs2_nand_meta_scan;
    ops.log = luat_vfs_lfs2_nand_meta_log;
    return ops;
}

static int luat_vfs_lfs2_nand_refresh_space_meta(void* userdata, const char* reason) {
    uint64_t start_us = luat_vfs_lfs2_nand_now_us();
    uint64_t cost_us = 0;
    luat_vfs_lfs2_nand_meta_ctx_t ctx = {0};
    luat_lfs2_nand_space_meta_ops_t ops = luat_vfs_lfs2_nand_meta_ops(userdata, &ctx);
    luat_lfs2_nand_space_meta_t current = {0};
    uint32_t slot = 0;
    if (luat_lfs2_nand_space_meta_load_or_rebuild(&ops, &current, &slot, NULL) != 0) {
        LFS2N_DEBUG_LOG("lfs2_nand: metadata bootstrap failed");
        return -1;
    }
    if (luat_lfs2_nand_space_meta_refresh(&ops, &current, slot, &current, &slot) != 0) {
        LFS2N_DEBUG_LOG("lfs2_nand: metadata refresh failed; fs_info will rebuild");
        return -1;
    }
    cost_us = luat_vfs_lfs2_nand_now_us() - start_us;
    g_lfs2_nand_meta_refresh_count++;
    g_lfs2_nand_meta_refresh_us += cost_us;
    // Update last refresh timestamp for throttling
    g_lfs2_nand_meta_last_refresh_us = start_us;
    luat_vfs_lfs2_nand_log_slow("meta_refresh", reason, cost_us);
    return 0;
}

static void luat_vfs_lfs2_nand_mark_space_dirty(void) {
    g_lfs2_nand_space_meta_dirty = 1;
}

static void luat_vfs_lfs2_nand_try_refresh_space_meta(void* userdata) {
    uint64_t now_us = 0;
    if (!g_lfs2_nand_space_meta_dirty) {
        return;
    }
    // Throttle refresh: only refresh if enough time has passed since last refresh
    now_us = luat_vfs_lfs2_nand_now_us();
    if (now_us - g_lfs2_nand_meta_last_refresh_us < LFS2_NAND_META_REFRESH_MIN_INTERVAL_US) {
        return;  // Skip refresh, still within throttle window
    }
    if (luat_vfs_lfs2_nand_refresh_space_meta(userdata, "dirty") == 0) {
        g_lfs2_nand_space_meta_dirty = 0;
        g_lfs2_nand_meta_last_refresh_us = now_us;
    }
}

// Force refresh, bypassing throttle window
static int luat_vfs_lfs2_nand_force_refresh_space_meta(void* userdata) {
    if (luat_vfs_lfs2_nand_refresh_space_meta(userdata, "force") == 0) {
        g_lfs2_nand_space_meta_dirty = 0;
        return 0;
    }
    return -1;
}

static luat_vfs_lfs2_nand_write_cache_t* luat_vfs_lfs2_nand_cache_find(FILE* stream) {
    uint32_t i = 0;
    while (i < LFS2_NAND_WRITE_CACHE_SLOTS) {
        if (g_lfs2_nand_write_cache[i].stream == stream) {
            return &g_lfs2_nand_write_cache[i];
        }
        i++;
    }
    return NULL;
}

static luat_vfs_lfs2_nand_write_cache_t* luat_vfs_lfs2_nand_cache_alloc(FILE* stream) {
    uint32_t i = 0;
    while (i < LFS2_NAND_WRITE_CACHE_SLOTS) {
        if (g_lfs2_nand_write_cache[i].stream == NULL) {
            g_lfs2_nand_write_cache[i].stream = stream;
            return &g_lfs2_nand_write_cache[i];
        }
        i++;
    }
    return NULL;
}

static void luat_vfs_lfs2_nand_cache_release(FILE* stream) {
    luat_vfs_lfs2_nand_write_cache_t* slot = luat_vfs_lfs2_nand_cache_find(stream);
    if (!slot) {
        return;
    }
    if (slot->data) {
        luat_heap_free(slot->data);
    }
    memset(slot, 0, sizeof(*slot));
}

static int luat_vfs_lfs2_nand_cache_expand(luat_vfs_lfs2_nand_write_cache_t* slot, size_t need) {
    size_t target = slot->cap;
    uint8_t* ptr;
    if (need <= slot->cap) {
        return 0;
    }
    if (need > LFS2_NAND_WRITE_CACHE_LIMIT) {
        return -1;
    }
    if (target < LFS2_NAND_WRITE_CACHE_CHUNK) {
        target = LFS2_NAND_WRITE_CACHE_CHUNK;
    }
    while (target < need && target < LFS2_NAND_WRITE_CACHE_LIMIT) {
        size_t next = target << 1;
        if (next <= target || next > LFS2_NAND_WRITE_CACHE_LIMIT) {
            target = LFS2_NAND_WRITE_CACHE_LIMIT;
            break;
        }
        target = next;
    }
    ptr = (uint8_t*)luat_heap_realloc(slot->data, target);
    if (!ptr) {
        return -1;
    }
    slot->data = ptr;
    slot->cap = target;
    return 0;
}

static int luat_vfs_lfs2_nand_cache_flush(void* userdata, luat_vfs_lfs2_nand_write_cache_t* slot) {
    uint64_t start_us = luat_vfs_lfs2_nand_now_us();
    uint64_t cost_us = 0;
    size_t wrote = 0;
    if (!slot || slot->stream == NULL || slot->len == 0) {
        return 0;
    }
    wrote = luat_vfs_lfs2_nand_base_fwrite(userdata, slot->data, 1, slot->len, slot->stream);
    if (wrote != slot->len) {
        return -1;
    }
    cost_us = luat_vfs_lfs2_nand_now_us() - start_us;
    g_lfs2_nand_cache_flush_count++;
    g_lfs2_nand_cache_flush_us += cost_us;
    g_lfs2_nand_cache_flush_bytes += slot->len;
    LFS2N_PERF_LOG("LFS2_TRACE_CACHE_FLUSH flush_idx=%u bytes=%u cost_us=%llu",
                   (unsigned int)g_lfs2_nand_cache_flush_count,
                   (unsigned int)slot->len,
                   (unsigned long long)cost_us);
    luat_vfs_lfs2_nand_log_slow("cache_flush", "writeback", cost_us);
#ifdef LUAT_USE_LITTLE_FLASH
    if (LUAT_LFS2N_PERF_LOG) {
        luat_lfs2n_block_profile_log("LFS2N_IO_SUMMARY");
    }
#endif
    slot->len = 0;
    luat_vfs_lfs2_nand_mark_space_dirty();
    return 0;
}

static int luat_vfs_lfs2_nand_load_space_meta(void* userdata, luat_lfs2_nand_space_meta_t* meta) {
    luat_vfs_lfs2_nand_meta_ctx_t ctx = {0};
    luat_lfs2_nand_space_meta_ops_t ops = luat_vfs_lfs2_nand_meta_ops(userdata, &ctx);
    uint8_t rebuilt = 0;
    uint8_t persisted = 0;
    if (luat_lfs2_nand_space_meta_load_prefer_fast(&ops, meta, &rebuilt, &persisted) != 0) {
        LFS2N_DEBUG_LOG("lfs2_nand: metadata recovery failed");
        return -1;
    }
    if (rebuilt) {
        if (persisted) {
            LFS2N_DEBUG_LOG("lfs2_nand: metadata rebuilt after validation failure");
        }
        else {
            LFS2N_DEBUG_LOG("lfs2_nand: metadata rebuilt via scan fallback without persistence");
        }
    }
    return 0;
}

static int luat_vfs_lfs2_nand_recover_layout(void* userdata, luat_fs_conf_t *conf) {
    LFS2N_DEBUG_LOG("lfs2_nand: legacy/incompatible layout detected, formatting and remounting");
    if (luat_vfs_lfs2_nand_base_mkfs(userdata, conf) != 0) {
        LFS2N_DEBUG_LOG("lfs2_nand: recovery mkfs failed");
        return -1;
    }
    if (luat_vfs_lfs2_nand_refresh_space_meta(userdata, "recover") != 0) {
        LFS2N_DEBUG_LOG("lfs2_nand: recovery metadata bootstrap failed");
        return -1;
    }
    return 0;
}

static int luat_vfs_lfs2_nand_detect_legacy_layout(void* userdata) {
    luat_fs_info_t info = {0};
    if (luat_vfs_lfs2_nand_base_fexist(userdata, LFS2_NAND_META_SLOT0) ||
        luat_vfs_lfs2_nand_base_fexist(userdata, LFS2_NAND_META_SLOT1)) {
        return 0;
    }
    if (luat_vfs_lfs2_nand_base_info(userdata, "", &info) != 0) {
        LFS2N_DEBUG_LOG("lfs2_nand: layout probe failed");
        return -1;
    }
    return 1;
}

static int luat_vfs_lfs2_nand_stream_may_change_space(FILE* stream) {
    luat_lfs2_file_t* file = (luat_lfs2_file_t*)stream;
    if (!file) {
        return 0;
    }
    return ((file->flags & LFS_O_WRONLY) == LFS_O_WRONLY) ||
           ((file->flags & LFS_O_RDWR) == LFS_O_RDWR) ||
           ((file->flags & LFS_O_APPEND) == LFS_O_APPEND);
}

static int luat_vfs_lfs2_nand_mount(void** userdata, luat_fs_conf_t *conf) {
    LFS2N_DEBUG_LOG("lfs2_nand mount start");
    if (!conf || !conf->busname) {
        *userdata = NULL;
        LFS2N_DEBUG_LOG("lfs2_nand mount invalid conf");
        return -1;
    }
    *userdata = (void*)conf->busname;
#ifdef LUAT_USE_LITTLE_FLASH
    luat_lfs2n_block_profile_reset();
#endif
    if (!*userdata) {
        LFS2N_DEBUG_LOG("lfs2_nand mount missing bus");
        return -1;
    }

    LFS2N_DEBUG_LOG("lfs2_nand mount detect layout");
    int legacy_layout = luat_vfs_lfs2_nand_detect_legacy_layout(*userdata);
    if (legacy_layout < 0) {
        *userdata = NULL;
        LFS2N_DEBUG_LOG("lfs2_nand mount detect layout failed");
        return -1;
    }
    if (legacy_layout > 0) {
        LFS2N_DEBUG_LOG("lfs2_nand mount legacy layout recover");
        if (luat_vfs_lfs2_nand_recover_layout(*userdata, conf) != 0) {
            *userdata = NULL;
            LFS2N_DEBUG_LOG("lfs2_nand mount recover failed");
            return -1;
        }
        LFS2N_DEBUG_LOG("lfs2_nand mount recovered");
        return 0;
    }
    LFS2N_DEBUG_LOG("lfs2_nand mount load metadata");
    if (luat_vfs_lfs2_nand_load_space_meta(*userdata, &(luat_lfs2_nand_space_meta_t){0}) != 0) {
        LFS2N_DEBUG_LOG("lfs2_nand mount load metadata failed, defer rebuild");
        // Do not block mount on full metadata rebuild; mark dirty and refresh lazily.
        g_lfs2_nand_space_meta_dirty = 1;
        LFS2N_DEBUG_LOG("lfs2_nand mount done with dirty metadata");
        return 0;
    }
    g_lfs2_nand_space_meta_dirty = 0;
    LFS2N_DEBUG_LOG("lfs2_nand mount done");
    return 0;
}

static int luat_vfs_lfs2_nand_mkfs(void* userdata, luat_fs_conf_t *conf) {
    int ret = luat_vfs_lfs2_nand_base_mkfs(userdata, conf);
    if (ret == 0) {
        if (luat_vfs_lfs2_nand_refresh_space_meta(userdata, "mkfs") == 0) {
            g_lfs2_nand_space_meta_dirty = 0;
        }
    }
    return ret;
}

static int luat_vfs_lfs2_nand_umount(void* userdata, luat_fs_conf_t *conf) {
    // Force final metadata refresh before unmounting to ensure all changes are persisted
    if (g_lfs2_nand_space_meta_dirty) {
        luat_vfs_lfs2_nand_force_refresh_space_meta(userdata);
    }
    if (g_lfs2_nand_meta_refresh_count || g_lfs2_nand_cache_flush_count) {
        LFS2N_PERF_LOG("profile summary: meta_refresh=%u total=%llu us, cache_flush=%u bytes=%llu total=%llu us",
                       g_lfs2_nand_meta_refresh_count, (unsigned long long)g_lfs2_nand_meta_refresh_us,
                       g_lfs2_nand_cache_flush_count, (unsigned long long)g_lfs2_nand_cache_flush_bytes,
                       (unsigned long long)g_lfs2_nand_cache_flush_us);
    }
    return luat_vfs_lfs2_nand_base_umount(userdata, conf);
}

static int luat_vfs_lfs2_nand_mkdir(void* userdata, char const* _DirName) {
    int ret = luat_vfs_lfs2_nand_base_mkdir(userdata, _DirName);
    if (ret == 0) {
        luat_vfs_lfs2_nand_mark_space_dirty();
    }
    return ret;
}

static int luat_vfs_lfs2_nand_rmdir(void* userdata, char const* _DirName) {
    int ret = luat_vfs_lfs2_nand_base_rmdir(userdata, _DirName);
    if (ret == 0) {
        luat_vfs_lfs2_nand_mark_space_dirty();
    }
    return ret;
}

static int luat_vfs_lfs2_nand_lsdir(void* userdata, char const* _DirName, luat_fs_dirent_t* ents, size_t offset, size_t len) {
    return luat_vfs_lfs2_nand_base_lsdir(userdata, _DirName, ents, offset, len);
}

static int luat_vfs_lfs2_nand_remove(void* userdata, const char *filename) {
    int ret = luat_vfs_lfs2_nand_base_remove(userdata, filename);
    if (ret == 0) {
        luat_vfs_lfs2_nand_mark_space_dirty();
    }
    return ret;
}

static int luat_vfs_lfs2_nand_rename(void* userdata, const char *old_filename, const char *new_filename) {
    int ret = luat_vfs_lfs2_nand_base_rename(userdata, old_filename, new_filename);
    if (ret == 0) {
        luat_vfs_lfs2_nand_mark_space_dirty();
    }
    return ret;
}

static size_t luat_vfs_lfs2_nand_fsize(void* userdata, const char *filename) {
    return luat_vfs_lfs2_nand_base_fsize(userdata, filename);
}

static int luat_vfs_lfs2_nand_fexist(void* userdata, const char *filename) {
    return luat_vfs_lfs2_nand_base_fexist(userdata, filename);
}

static int luat_vfs_lfs2_nand_info(void* userdata, const char* path, luat_fs_info_t *conf) {
    luat_lfs2_t* fs = (luat_lfs2_t*)userdata;
    luat_lfs2_nand_space_meta_t meta = {0};
    size_t fs_len = 0;
    (void)path;
    if (!fs || !conf) {
        return -1;
    }
    // Force refresh before reading space info to ensure latest data
    if (g_lfs2_nand_space_meta_dirty) {
        luat_vfs_lfs2_nand_force_refresh_space_meta(userdata);
    }
    if (luat_vfs_lfs2_nand_load_space_meta(userdata, &meta) != 0) {
        return -1;
    }
    memset(conf->filesystem, 0, sizeof(conf->filesystem));
    fs_len = strlen(NAND_FS_NAME);
    if (fs_len >= sizeof(conf->filesystem)) {
        fs_len = sizeof(conf->filesystem) - 1;
    }
    memcpy(conf->filesystem, NAND_FS_NAME, fs_len);
    conf->filesystem[fs_len] = 0;
    conf->type = 0;
    conf->total_block = meta.total;
    conf->block_used = meta.used;
    conf->block_size = fs->cfg->block_size;
    return 0;
}

static int luat_vfs_lfs2_nand_truncate(void* userdata, const char *filename, size_t len) {
    int ret = luat_vfs_lfs2_nand_base_truncate(userdata, filename, len);
    if (ret == 0) {
        luat_vfs_lfs2_nand_mark_space_dirty();
    }
    return ret;
}

static void* luat_vfs_lfs2_nand_opendir(void* userdata, const char *_DirName) {
    return luat_vfs_lfs2_nand_base_opendir(userdata, _DirName);
}

static int luat_vfs_lfs2_nand_closedir(void* userdata, void* dir) {
    return luat_vfs_lfs2_nand_base_closedir(userdata, dir);
}

static FILE* luat_vfs_lfs2_nand_fopen(void* userdata, const char *filename, const char *mode) {
    return luat_vfs_lfs2_nand_base_fopen(userdata, filename, mode);
}

static int luat_vfs_lfs2_nand_getc(void* userdata, FILE* stream) {
    luat_vfs_lfs2_nand_write_cache_t* slot = luat_vfs_lfs2_nand_cache_find(stream);
    if (slot && luat_vfs_lfs2_nand_cache_flush(userdata, slot) != 0) {
        return -1;
    }
    return luat_vfs_lfs2_nand_base_getc(userdata, stream);
}

static int luat_vfs_lfs2_nand_fseek(void* userdata, FILE* stream, long int offset, int origin) {
    luat_vfs_lfs2_nand_write_cache_t* slot = luat_vfs_lfs2_nand_cache_find(stream);
    if (slot && luat_vfs_lfs2_nand_cache_flush(userdata, slot) != 0) {
        return -1;
    }
    return luat_vfs_lfs2_nand_base_fseek(userdata, stream, offset, origin);
}

static int luat_vfs_lfs2_nand_ftell(void* userdata, FILE* stream) {
    luat_vfs_lfs2_nand_write_cache_t* slot = luat_vfs_lfs2_nand_cache_find(stream);
    if (slot && luat_vfs_lfs2_nand_cache_flush(userdata, slot) != 0) {
        return -1;
    }
    return luat_vfs_lfs2_nand_base_ftell(userdata, stream);
}

static int luat_vfs_lfs2_nand_fclose(void* userdata, FILE* stream) {
    int should_mark_dirty = luat_vfs_lfs2_nand_stream_may_change_space(stream);
    luat_vfs_lfs2_nand_write_cache_t* slot = luat_vfs_lfs2_nand_cache_find(stream);
    int ret = 0;
    if (slot && luat_vfs_lfs2_nand_cache_flush(userdata, slot) != 0) {
        luat_vfs_lfs2_nand_cache_release(stream);
        return -1;
    }
    ret = luat_vfs_lfs2_nand_base_fclose(userdata, stream);
    if (ret == 0 && should_mark_dirty) {
        luat_vfs_lfs2_nand_mark_space_dirty();
    }
    luat_vfs_lfs2_nand_cache_release(stream);
    return ret;
}

static int luat_vfs_lfs2_nand_feof(void* userdata, FILE* stream) {
    return luat_vfs_lfs2_nand_base_feof(userdata, stream);
}

static int luat_vfs_lfs2_nand_ferror(void* userdata, FILE *stream) {
    return luat_vfs_lfs2_nand_base_ferror(userdata, stream);
}

static size_t luat_vfs_lfs2_nand_fread(void* userdata, void *ptr, size_t size, size_t nmemb, FILE *stream) {
    luat_vfs_lfs2_nand_write_cache_t* slot = luat_vfs_lfs2_nand_cache_find(stream);
    if (slot && luat_vfs_lfs2_nand_cache_flush(userdata, slot) != 0) {
        return 0;
    }
    return luat_vfs_lfs2_nand_base_fread(userdata, ptr, size, nmemb, stream);
}

static size_t luat_vfs_lfs2_nand_fwrite(void* userdata, const void *ptr, size_t size, size_t nmemb, FILE *stream) {
    luat_lfs2_file_t* file = (luat_lfs2_file_t*)stream;
    luat_vfs_lfs2_nand_write_cache_t* slot;
    size_t total = size * nmemb;
    if (!file || total == 0) {
        return 0;
    }
    if (!luat_vfs_lfs2_nand_stream_may_change_space(stream)) {
        return luat_vfs_lfs2_nand_base_fwrite(userdata, ptr, size, nmemb, stream);
    }
    slot = luat_vfs_lfs2_nand_cache_find(stream);
    if (!slot) {
        slot = luat_vfs_lfs2_nand_cache_alloc(stream);
    }
    if (!slot) {
        size_t wrote = luat_vfs_lfs2_nand_base_fwrite(userdata, ptr, size, nmemb, stream);
        if (wrote == total) {
            luat_vfs_lfs2_nand_mark_space_dirty();
        }
        return wrote;
    }
    if (total > LFS2_NAND_WRITE_CACHE_LIMIT || (slot->len + total) > LFS2_NAND_WRITE_CACHE_LIMIT) {
        if (luat_vfs_lfs2_nand_cache_flush(userdata, slot) != 0) {
            return 0;
        }
        {
            size_t wrote = luat_vfs_lfs2_nand_base_fwrite(userdata, ptr, size, nmemb, stream);
            if (wrote == total) {
                luat_vfs_lfs2_nand_mark_space_dirty();
            }
            return wrote;
        }
    }
    if (luat_vfs_lfs2_nand_cache_expand(slot, slot->len + total) != 0) {
        if (luat_vfs_lfs2_nand_cache_flush(userdata, slot) != 0) {
            return 0;
        }
        {
            size_t wrote = luat_vfs_lfs2_nand_base_fwrite(userdata, ptr, size, nmemb, stream);
            if (wrote == total) {
                luat_vfs_lfs2_nand_mark_space_dirty();
            }
            return wrote;
        }
    }
    memcpy(slot->data + slot->len, ptr, total);
    slot->len += total;
    return total;
}

static int luat_vfs_lfs2_nand_fflush(void* userdata, FILE *stream) {
    luat_vfs_lfs2_nand_write_cache_t* slot = luat_vfs_lfs2_nand_cache_find(stream);
    int ret = 0;
    if (slot && luat_vfs_lfs2_nand_cache_flush(userdata, slot) != 0) {
        return -1;
    }
    ret = luat_vfs_lfs2_nand_base_fflush(userdata, stream);
    if (ret == 0 && luat_vfs_lfs2_nand_stream_may_change_space(stream)) {
        luat_vfs_lfs2_nand_mark_space_dirty();
    }
    return ret;
}

#define T(name) .name = luat_vfs_lfs2_nand_##name

const struct luat_vfs_filesystem vfs_fs_lfs2_nand = {
    .name = NAND_FS_NAME,
    .opts = {
        T(mkfs),
        .mount = luat_vfs_lfs2_nand_mount,
        T(umount),
        T(mkdir),
        T(rmdir),
        T(lsdir),
        T(remove),
        T(rename),
        T(fsize),
        T(fexist),
        T(info),
        T(truncate),
        T(opendir),
        T(closedir)
    },
    .fopts = {
        T(fopen),
        T(getc),
        T(fseek),
        T(ftell),
        T(fclose),
        T(feof),
        T(ferror),
        T(fread),
        T(fwrite),
        T(fflush)
    }
};

void* luat_fs_lfs2_nand_default_bus(void* flash, size_t offset, size_t maxsize) {
    return luat_lfs2_nand_flash_lfs_lf(flash, offset, maxsize);
}

void luat_lfs2_nand_vfs_init(void) {
    static uint8_t inited = 0;
    if (!inited) {
        luat_vfs_reg(&vfs_fs_lfs2_nand);
        inited = 1;
    }
}

#else

void* luat_fs_lfs2_nand_default_bus(void* flash, size_t offset, size_t maxsize) {
    (void)flash;
    (void)offset;
    (void)maxsize;
    return NULL;
}

void luat_lfs2_nand_vfs_init(void) {
}

#endif
