#include "luat_base.h"
#include <string.h>
#include "luat_pgfs.h"

#define LUAT_LOG_TAG "pgfs"
#include "luat_log.h"

#ifdef LUAT_USE_PGFS_COMPONENT

#include "luat_fs.h"
#include "luat_rtos_legacy.h"
#include "pgfs_internal.h"  /* includes pgfs_nand_ftl.h internally */
#ifdef LUAT_USE_LITTLE_FLASH
#include "little_flash.h"
#endif

static pgfs_mount_ctx_t s_pgfs_ctxs[PGFS_MAX_MOUNTS];

/* --- Multi-mount helpers --- */

pgfs_mount_ctx_t* pgfs_find_mount_by_point(const char* mount_point) {
    uint32_t i;
    if (mount_point == NULL) return NULL;
    for (i = 0; i < PGFS_MAX_MOUNTS; i++) {
        if (s_pgfs_ctxs[i].mounted &&
            strcmp(s_pgfs_ctxs[i].mount_point, mount_point) == 0) {
            return &s_pgfs_ctxs[i];
        }
    }
    return NULL;
}

pgfs_mount_ctx_t* pgfs_find_mount_by_opts(const pgfs_flash_opts_t* opts) {
    uint32_t i;
    if (opts == NULL) return NULL;
    for (i = 0; i < PGFS_MAX_MOUNTS; i++) {
        if (s_pgfs_ctxs[i].mounted && s_pgfs_ctxs[i].flash_opts == opts) {
            return &s_pgfs_ctxs[i];
        }
    }
    return NULL;
}

pgfs_mount_ctx_t* pgfs_find_first_mounted(void) {
    uint32_t i;
    for (i = 0; i < PGFS_MAX_MOUNTS; i++) {
        if (s_pgfs_ctxs[i].mounted) {
            return &s_pgfs_ctxs[i];
        }
    }
    return NULL;
}

pgfs_mount_ctx_t* pgfs_find_free_mount_slot(void) {
    uint32_t i;
    for (i = 0; i < PGFS_MAX_MOUNTS; i++) {
        if (!s_pgfs_ctxs[i].mounted) {
            return &s_pgfs_ctxs[i];
        }
    }
    return NULL;
}

pgfs_mount_ctx_t* pgfs_get_mount_ctx(void) {
    return pgfs_find_first_mounted();
}

#ifdef LUAT_USE_LITTLE_FLASH
typedef struct {
    pgfs_flash_opts_t opts;
    little_flash_t* flash;
    uint32_t offset;
    uint32_t maxsize;
} pgfs_lf_bus_t;

static pgfs_lf_bus_t s_pgfs_lf_buses[PGFS_MAX_MOUNTS];

static int pgfs_lf_check_range(pgfs_lf_bus_t* bus, uint32_t addr, size_t len) {
    uint64_t end = 0;
    if (bus == NULL) {
        return -1;
    }
    end = (uint64_t)addr + (uint64_t)len;
    if (bus->maxsize != 0 && end > bus->maxsize) {
        return -1;
    }
    return 0;
}

static int pgfs_lf_read(void *ctx, uint32_t addr, uint8_t *buf, size_t len) {
    pgfs_lf_bus_t* bus = (pgfs_lf_bus_t*)ctx;
    if (bus == NULL || bus->flash == NULL || buf == NULL || pgfs_lf_check_range(bus, addr, len) != 0) {
        return -1;
    }
    return little_flash_read(bus->flash, bus->offset + addr, buf, (uint32_t)len) == LF_ERR_OK ? 0 : -1;
}

static int pgfs_lf_write(void *ctx, uint32_t addr, const uint8_t *buf, size_t len) {
    pgfs_lf_bus_t* bus = (pgfs_lf_bus_t*)ctx;
    if (bus == NULL || bus->flash == NULL || buf == NULL || pgfs_lf_check_range(bus, addr, len) != 0) {
        return -1;
    }
    return little_flash_write(bus->flash, bus->offset + addr, buf, (uint32_t)len) == LF_ERR_OK ? 0 : -1;
}

static int pgfs_lf_erase(void *ctx, uint32_t block_addr, uint32_t block_count) {
    pgfs_lf_bus_t* bus = (pgfs_lf_bus_t*)ctx;
    if (bus == NULL || bus->flash == NULL || block_count == 0) {
        return -1;
    }
    int ret = little_flash_erase(bus->flash, bus->offset + block_addr, block_count);

    /* Update FTL erase counts and bad-block state */
    pgfs_mount_ctx_t *mount_ctx = pgfs_find_mount_by_opts(&bus->opts);
    if (mount_ctx == NULL) mount_ctx = pgfs_find_first_mounted();
    if (mount_ctx && mount_ctx->mounted) {
        uint32_t block_id = block_addr / bus->flash->chip_info.erase_size;
        if (ret == LF_ERR_OK) {
            pgfs_ftl_on_erase_success(mount_ctx, block_id);
        } else {
            pgfs_ftl_on_erase_failure(mount_ctx, block_id);
        }
    }

    return ret == LF_ERR_OK ? 0 : -1;
}

static int pgfs_lf_control(void *ctx, uint32_t cmd, void *arg) {
    pgfs_lf_bus_t* bus = (pgfs_lf_bus_t*)ctx;
    pgfs_flash_geometry_t* geo = (pgfs_flash_geometry_t*)arg;
    if (bus == NULL || bus->flash == NULL) {
        return -1;
    }
    if (cmd == PGFS_CTRL_GET_GEOMETRY && geo != NULL) {
        uint32_t cap = bus->flash->chip_info.capacity;
        if (cap > bus->offset) {
            cap -= bus->offset;
        }
        else {
            cap = 0;
        }
        if (bus->maxsize != 0 && cap > bus->maxsize) {
            cap = bus->maxsize;
        }
        geo->capacity = cap;
        geo->erase_size = bus->flash->chip_info.erase_size;
        geo->prog_size = bus->flash->chip_info.prog_size;
        return 0;
    }
    return -1;
}
#endif

/* pgfs_compute_data_log_base — mount helper. Calls pgfs_layout_compute()
 * to derive the layout from the geometry, and returns the byte address
 * of the first data-log block. The layout always starts the data log
 * at block PGFS_LAYOUT_RESERVED_BLOCKS, which is past the FTL state
 * region by construction. */
static uint32_t pgfs_compute_data_log_base(const pgfs_flash_opts_t* opts) {
    pgfs_flash_geometry_t geo = {0};
    pgfs_layout_t layout = {0};
    if (opts == NULL || opts->control == NULL) {
        return PGFS_DATA_LOG_BASE_ADDR;
    }
    if (opts->control(opts->ctx, PGFS_CTRL_GET_GEOMETRY, &geo) != 0 || geo.erase_size == 0) {
        return PGFS_DATA_LOG_BASE_ADDR;
    }
    if (pgfs_layout_compute(&geo, &layout) != 0) {
        return PGFS_DATA_LOG_BASE_ADDR;
    }
    return layout.data_log_first_block * layout.erase_size;
}

static int luat_vfs_pgfs_mount(void** fsdata, luat_fs_conf_t *conf) {
    int ret = 0;
    size_t mlen = 0;
    pgfs_mount_ctx_t* ctx = NULL;
    if (fsdata == NULL || conf == NULL || conf->mount_point == NULL || conf->busname == NULL) {
        return -1;
    }
    /* Reject duplicate mount point */
    if (pgfs_find_mount_by_point(conf->mount_point) != NULL) {
        LLOGE("pgfs: mount point %s already mounted", conf->mount_point);
        return -1;
    }
    ctx = pgfs_find_free_mount_slot();
    if (ctx == NULL) {
        LLOGE("pgfs: no free mount slot (max %u)", (unsigned)PGFS_MAX_MOUNTS);
        return -1;
    }
    memset(ctx, 0, sizeof(*ctx));
    pgfs_file_reset_all();
    mlen = strlen(conf->mount_point);
    if (mlen >= sizeof(ctx->mount_point)) {
        mlen = sizeof(ctx->mount_point) - 1;
    }
    memcpy(ctx->mount_point, conf->mount_point, mlen);
    ctx->mount_point[mlen] = 0;
    ctx->flash_opts = (const pgfs_flash_opts_t *)conf->busname;
    ctx->runtime_generation = 1;
    /* Initialize platform mutex for thread-safe operations */
    if (ctx->mutex == NULL) {
        ctx->mutex = luat_mutex_create();
    }
    /* TDD gate: reject partitions smaller than 8MB.
     * 256KB-class utest partitions cannot host the FTL metadata
     * (~256KB) + 2x superblock + 2x CP + 64 segments of 128KB
     * blocks. They cause "no free blocks" failures in the FTL. */
    {
        pgfs_flash_geometry_t geo = {0};
        if (ctx->flash_opts->control &&
            ctx->flash_opts->control(ctx->flash_opts->ctx,
                                           PGFS_CTRL_GET_GEOMETRY, &geo) == 0) {
            if (geo.capacity < PGFS_MIN_PARTITION_BYTES) {
                LLOGE("pgfs: partition too small (%u bytes), need >= %u",
                      (unsigned)geo.capacity, (unsigned)PGFS_MIN_PARTITION_BYTES);
                memset(ctx, 0, sizeof(*ctx));
                return -1;
            }
        }
    }
    ctx->data_log_base_addr = pgfs_compute_data_log_base(ctx->flash_opts);
    ctx->data_log_write_addr = ctx->data_log_base_addr;
    ctx->data_log_prepared_until = ctx->data_log_base_addr;

    ret = pgfs_checkpoint_load(ctx, &ctx->checkpoint);
    if (ret != 0) {
        ret = pgfs_rebuild_checkpoint_from_replay(ctx);
        if (ret != 0) {
            memset(ctx, 0, sizeof(*ctx));
            return -1;
        }
        /* The rebuild path also runs a replay internally. */
        ctx->stats.replay_count += 1;
    }
    else {
        /* Phase 4b: early FTL init so the persisted write_head /
         * log_tail is available for the replay-bound calculation
         * below. Idempotent on the second pgfs_ftl_on_mount call
         * later in this function (it skips pgfs_ftl_init if
         * flash_opts is set). */
        if (pgfs_ftl_on_mount(ctx) != 0) {
            LLOGE("pgfs: early FTL init failed");
            memset(ctx, 0, sizeof(*ctx));
            return -1;
        }
        /* Phase 4b: bound the data log write head from the CP's
         * log_tail_* so pgfs_replay_data_log walks only the durable
         * region. Same logic as the fbeda6236 fix in
         * pgfs_control_reset_runtime. Without this, replay would
         * scan to end-of-flash and resurrect orphan records. */
        if (ctx->checkpoint.log_tail_block != 0 ||
            ctx->checkpoint.log_tail_offset != 0) {
            pgfs_flash_geometry_t geo = {0};
            uint32_t erase_size = 0;
            if (ctx->flash_opts->control &&
                ctx->flash_opts->control(ctx->flash_opts->ctx,
                                               PGFS_CTRL_GET_GEOMETRY, &geo) == 0 &&
                geo.erase_size > 0) {
                erase_size = geo.erase_size;
                ctx->data_log_write_addr =
                    ctx->data_log_base_addr +
                    (uint32_t)ctx->checkpoint.log_tail_block * erase_size +
                    ctx->checkpoint.log_tail_offset;
                ctx->data_log_prepared_until = ctx->data_log_write_addr;
                LLOGI("pgfs mount: replay bound by CP log_tail=%u/%u (write_addr=%u)",
                      (unsigned int)ctx->checkpoint.log_tail_block,
                      (unsigned int)ctx->checkpoint.log_tail_offset,
                      (unsigned int)ctx->data_log_write_addr);
            }
        }
        /* Always replay on mount. The file table is in-RAM only and
         * must be rebuilt from the data log; the O(1) skip in the
         * previous design was wrong because it left the file table
         * empty after a fresh mount (test_reopen_recover bug 10.3).
         * The replay is bounded by data_log_write_addr above, so the
         * performance intent of the O(1) optimization is preserved. */
        ret = pgfs_replay_data_log(ctx);
        if (ret != 0) {
            memset(ctx, 0, sizeof(*ctx));
            return -1;
        }
        ctx->stats.replay_count += 1;
    }
    ctx->checkpoint_loaded = 1;

    /* NAND FTL init: try loading persisted state, fall back to factory scan */
    if (pgfs_ftl_on_mount(ctx) != 0) {
        LLOGE("pgfs: NAND FTL init failed");
        memset(ctx, 0, sizeof(*ctx));
        return -1;
    }

    ctx->mounted = 1;
    ctx->stats.mount_count += 1;
    *fsdata = ctx;
    return 0;
}

static int luat_vfs_pgfs_umount(void* fsdata, luat_fs_conf_t *conf) {
    pgfs_mount_ctx_t* ctx = (pgfs_mount_ctx_t*)fsdata;
    (void)conf;
    if (ctx == NULL) {
        return -1;
    }
    if (ctx->mounted) {
        /* Persist FTL state before committing checkpoint */
        pgfs_ftl_on_checkpoint_commit(ctx);
        if (pgfs_checkpoint_commit_pending(ctx) != 0) {
            return -1;
        }
        pgfs_ftl_deinit(&ctx->ftl);
    }
    pgfs_file_reset_all();
    if (ctx->mutex != NULL) {
        luat_mutex_release(ctx->mutex);
        ctx->mutex = NULL;
    }
    memset(ctx, 0, sizeof(*ctx));
    return 0;
}

static int luat_vfs_pgfs_info(void* fsdata, const char* path, luat_fs_info_t *conf) {
    pgfs_mount_ctx_t* ctx = (pgfs_mount_ctx_t*)fsdata;
    (void)path;
    if (ctx == NULL || conf == NULL) {
        return -1;
    }
    return pgfs_info_fast(ctx, conf);
}

static int luat_vfs_pgfs_remove(void* fsdata, const char *filename) {
    return pgfs_file_remove((pgfs_mount_ctx_t*)fsdata, filename);
}

static int luat_vfs_pgfs_mkdir(void* fsdata, char const* _DirName) {
    return pgfs_dir_mkdir((pgfs_mount_ctx_t*)fsdata, _DirName);
}

static int luat_vfs_pgfs_rmdir(void* fsdata, char const* _DirName) {
    return pgfs_dir_rmdir((pgfs_mount_ctx_t*)fsdata, _DirName);
}

static int luat_vfs_pgfs_lsdir(void* fsdata, char const* _DirName, luat_fs_dirent_t* ents, size_t offset, size_t len) {
    return pgfs_dir_lsdir((pgfs_mount_ctx_t*)fsdata, _DirName, ents, offset, len);
}

static void* luat_vfs_pgfs_opendir(void* fsdata, char const* _DirName) {
    return pgfs_dir_opendir((pgfs_mount_ctx_t*)fsdata, _DirName);
}

static int luat_vfs_pgfs_closedir(void* fsdata, void* dir) {
    return pgfs_dir_closedir((pgfs_mount_ctx_t*)fsdata, dir);
}

static FILE* luat_vfs_pgfs_fopen(void* fsdata, const char *filename, const char *mode) {
    return pgfs_file_open((pgfs_mount_ctx_t*)fsdata, filename, mode);
}

static int luat_vfs_pgfs_fclose(void* fsdata, FILE* stream) {
    return pgfs_file_close((pgfs_mount_ctx_t*)fsdata, stream);
}

static size_t luat_vfs_pgfs_fread(void* fsdata, void *ptr, size_t size, size_t nmemb, FILE *stream) {
    return pgfs_file_read((pgfs_mount_ctx_t*)fsdata, ptr, size, nmemb, stream);
}

static size_t luat_vfs_pgfs_fwrite(void* fsdata, const void *ptr, size_t size, size_t nmemb, FILE *stream) {
    return pgfs_file_write((pgfs_mount_ctx_t*)fsdata, ptr, size, nmemb, stream);
}

static int luat_vfs_pgfs_fseek(void* fsdata, FILE* stream, long int offset, int origin) {
    return pgfs_file_seek((pgfs_mount_ctx_t*)fsdata, stream, offset, origin);
}

static int luat_vfs_pgfs_ftell(void* fsdata, FILE* stream) {
    return pgfs_file_tell((pgfs_mount_ctx_t*)fsdata, stream);
}

static int luat_vfs_pgfs_feof(void* fsdata, FILE* stream) {
    return pgfs_file_eof((pgfs_mount_ctx_t*)fsdata, stream);
}

static int luat_vfs_pgfs_ferror(void* fsdata, FILE *stream) {
    return pgfs_file_error((pgfs_mount_ctx_t*)fsdata, stream);
}

static int luat_vfs_pgfs_fflush(void* fsdata, FILE *stream) {
    return pgfs_file_flush((pgfs_mount_ctx_t*)fsdata, stream);
}

static int luat_vfs_pgfs_getc(void* fsdata, FILE* stream) {
    return pgfs_file_getc((pgfs_mount_ctx_t*)fsdata, stream);
}

const struct luat_vfs_filesystem vfs_fs_pgfs = {
    .name = "pgfs",
    .opts = {
        .mount = luat_vfs_pgfs_mount,
        .umount = luat_vfs_pgfs_umount,
        .info = luat_vfs_pgfs_info,
        .remove = luat_vfs_pgfs_remove,
        .mkdir = luat_vfs_pgfs_mkdir,
        .rmdir = luat_vfs_pgfs_rmdir,
        .lsdir = luat_vfs_pgfs_lsdir,
        .opendir = luat_vfs_pgfs_opendir,
        .closedir = luat_vfs_pgfs_closedir,
    },
    .fopts = {
        .fopen = luat_vfs_pgfs_fopen,
        .fseek = luat_vfs_pgfs_fseek,
        .ftell = luat_vfs_pgfs_ftell,
        .fclose = luat_vfs_pgfs_fclose,
        .feof = luat_vfs_pgfs_feof,
        .ferror = luat_vfs_pgfs_ferror,
        .fread = luat_vfs_pgfs_fread,
        .fwrite = luat_vfs_pgfs_fwrite,
        .fflush = luat_vfs_pgfs_fflush,
        .getc = luat_vfs_pgfs_getc,
    },
};

void* pgfs_default_bus(void* flash, size_t offset, size_t maxsize) {
#ifdef LUAT_USE_LITTLE_FLASH
    uint32_t i;
    pgfs_lf_bus_t* bus = NULL;
    LLOGD("pgfs_default_bus offset=%u maxsize=%u", (unsigned int)offset, (unsigned int)maxsize);
    /* Find a free bus slot (one not referenced by any mounted ctx) */
    for (i = 0; i < PGFS_MAX_MOUNTS; i++) {
        int in_use = 0;
        uint32_t j;
        for (j = 0; j < PGFS_MAX_MOUNTS; j++) {
            if (s_pgfs_ctxs[j].mounted &&
                s_pgfs_ctxs[j].flash_opts == &s_pgfs_lf_buses[i].opts) {
                in_use = 1;
                break;
            }
        }
        if (!in_use) {
            bus = &s_pgfs_lf_buses[i];
            break;
        }
    }
    if (bus == NULL) {
        LLOGE("pgfs_default_bus: no free bus slot");
        return NULL;
    }
    memset(bus, 0, sizeof(*bus));
    bus->flash = (little_flash_t*)flash;
    bus->offset = (uint32_t)offset;
    bus->maxsize = (uint32_t)maxsize;
    bus->opts.ctx = bus;
    bus->opts.read = pgfs_lf_read;
    bus->opts.write = pgfs_lf_write;
    bus->opts.erase = pgfs_lf_erase;
    bus->opts.control = pgfs_lf_control;
    return &bus->opts;
#else
    (void)offset;
    (void)maxsize;
    return flash;
#endif
}

void pgfs_vfs_init(void) {
    static uint8_t inited = 0;
    if (!inited) {
        luat_pgfs_vfs_register();
        inited = 1;
    }
}

int luat_pgfs_vfs_register(void) {
    return luat_vfs_reg(&vfs_fs_pgfs);
}

int luat_pgfs_mount(const char *mount_point, const pgfs_flash_opts_t *opts) {
    luat_fs_conf_t conf = {
        .busname = (char*)opts,
        .type = "pgfs",
        .filesystem = "pgfs",
        .mount_point = mount_point,
    };
    return luat_fs_mount(&conf);
}

int luat_pgfs_umount(const char *mount_point) {
    luat_fs_conf_t conf = {
        .busname = NULL,
        .type = "pgfs",
        .filesystem = "pgfs",
        .mount_point = mount_point,
    };
    return luat_fs_umount(&conf);
}

int luat_pgfs_info(const char *path, luat_fs_info_t *info) {
    return luat_fs_info(path, info);
}

int luat_pgfs_begin_batch(uint32_t* out_batch_id) {
    pgfs_mount_ctx_t* ctx = pgfs_find_first_mounted();
    if (ctx == NULL) {
        return -1;
    }
    return pgfs_batch_begin(ctx, out_batch_id);
}

int luat_pgfs_commit_batch(uint32_t batch_id) {
    pgfs_mount_ctx_t* ctx = pgfs_find_first_mounted();
    if (ctx == NULL) {
        return -1;
    }
    return pgfs_batch_commit(ctx, batch_id);
}

int luat_pgfs_abort_batch(uint32_t batch_id) {
    pgfs_mount_ctx_t* ctx = pgfs_find_first_mounted();
    if (ctx == NULL) {
        return -1;
    }
    return pgfs_batch_abort(ctx, batch_id);
}

int luat_pgfs_begin_batch_on(const char *mount_point, uint32_t* out_batch_id) {
    pgfs_mount_ctx_t* ctx = pgfs_find_mount_by_point(mount_point);
    if (ctx == NULL) {
        return -1;
    }
    return pgfs_batch_begin(ctx, out_batch_id);
}

int luat_pgfs_commit_batch_on(const char *mount_point, uint32_t batch_id) {
    pgfs_mount_ctx_t* ctx = pgfs_find_mount_by_point(mount_point);
    if (ctx == NULL) {
        return -1;
    }
    return pgfs_batch_commit(ctx, batch_id);
}

int luat_pgfs_abort_batch_on(const char *mount_point, uint32_t batch_id) {
    pgfs_mount_ctx_t* ctx = pgfs_find_mount_by_point(mount_point);
    if (ctx == NULL) {
        return -1;
    }
    return pgfs_batch_abort(ctx, batch_id);
}

static int pgfs_parse_on_off(const char* mode, int* out) {
    if (mode == NULL || out == NULL) {
        return -1;
    }
    if (strcmp(mode, "on") == 0) {
        *out = 1;
        return 0;
    }
    if (strcmp(mode, "off") == 0) {
        *out = 0;
        return 0;
    }
    return -1;
}

int pgfs_control_set_lock_mode(const char* mode) {
    pgfs_mount_ctx_t* ctx = pgfs_find_first_mounted();
    int enabled = 0;
    if (ctx == NULL) return -1;
    if (pgfs_parse_on_off(mode, &enabled) != 0) {
        return -1;
    }
    ctx->lock_mode = enabled ? PGFS_LOCK_MODE_ON : PGFS_LOCK_MODE_OFF;
    return 0;
}

int pgfs_control_set_lock_mode_on(const char *mount_point, const char* mode) {
    pgfs_mount_ctx_t* ctx = pgfs_find_mount_by_point(mount_point);
    int enabled = 0;
    if (ctx == NULL) return -1;
    if (pgfs_parse_on_off(mode, &enabled) != 0) {
        return -1;
    }
    ctx->lock_mode = enabled ? PGFS_LOCK_MODE_ON : PGFS_LOCK_MODE_OFF;
    return 0;
}

static int pgfs_control_inject_powercut_stage_ctx(pgfs_mount_ctx_t* ctx, const char* stage) {
    if (ctx == NULL || stage == NULL) {
        return -1;
    }
    if (strcmp(stage, "none") == 0) {
        ctx->inject_powercut_stage = PGFS_INJECT_POWERCUT_NONE;
        return 0;
    }
    if (strcmp(stage, "before_checkpoint") == 0 ||
        strcmp(stage, "before_cp") == 0) {
        ctx->inject_powercut_stage = PGFS_INJECT_POWERCUT_BEFORE_CP;
        return 0;
    }
    if (strcmp(stage, "before_append") == 0) {
        ctx->inject_powercut_stage = PGFS_INJECT_POWERCUT_BEFORE_APPEND;
        return 0;
    }
    if (strcmp(stage, "after_append") == 0) {
        ctx->inject_powercut_stage = PGFS_INJECT_POWERCUT_AFTER_APPEND;
        return 0;
    }
    if (strcmp(stage, "after_cp_erase") == 0) {
        ctx->inject_powercut_stage = PGFS_INJECT_POWERCUT_AFTER_CP_ERASE;
        return 0;
    }
    if (strcmp(stage, "after_cp_write") == 0) {
        ctx->inject_powercut_stage = PGFS_INJECT_POWERCUT_AFTER_CP_WRITE;
        return 0;
    }
    if (strcmp(stage, "after_append_erase") == 0) {
        ctx->inject_powercut_stage = PGFS_INJECT_POWERCUT_AFTER_APPEND_ERASE;
        return 0;
    }
    return -1;
}

int pgfs_control_inject_powercut_stage(const char* stage) {
    return pgfs_control_inject_powercut_stage_ctx(pgfs_find_first_mounted(), stage);
}

int pgfs_control_inject_powercut_stage_on(const char *mount_point, const char* stage) {
    return pgfs_control_inject_powercut_stage_ctx(pgfs_find_mount_by_point(mount_point), stage);
}

int pgfs_control_inject_corrupt_latest_cp(int enable) {
    pgfs_mount_ctx_t* ctx = pgfs_find_first_mounted();
    if (ctx == NULL) return -1;
    ctx->inject_corrupt_latest_cp = enable ? 1 : 0;
    return 0;
}

int pgfs_control_inject_corrupt_latest_cp_on(const char *mount_point, int enable) {
    pgfs_mount_ctx_t* ctx = pgfs_find_mount_by_point(mount_point);
    if (ctx == NULL) return -1;
    ctx->inject_corrupt_latest_cp = enable ? 1 : 0;
    return 0;
}

int pgfs_control_inject_bad_block_once(int enable) {
    pgfs_mount_ctx_t* ctx = pgfs_find_first_mounted();
    if (ctx == NULL) return -1;
    if (enable) {
        if (ctx->mounted) {
            pgfs_ftl_inject_bad_block_once(&ctx->ftl, 0);
        } else {
            ctx->inject_bad_block_once = 1;
        }
    } else {
        ctx->inject_bad_block_once = 0;
        if (ctx->mounted) {
            ctx->ftl.inject_bad_block_once = 0;
        }
    }
    return 0;
}

int pgfs_control_inject_bad_block_once_on(const char *mount_point, int enable) {
    pgfs_mount_ctx_t* ctx = pgfs_find_mount_by_point(mount_point);
    if (ctx == NULL) return -1;
    if (enable) {
        if (ctx->mounted) {
            pgfs_ftl_inject_bad_block_once(&ctx->ftl, 0);
        } else {
            ctx->inject_bad_block_once = 1;
        }
    } else {
        ctx->inject_bad_block_once = 0;
        if (ctx->mounted) {
            ctx->ftl.inject_bad_block_once = 0;
        }
    }
    return 0;
}

static int pgfs_control_reset_runtime_ctx(pgfs_mount_ctx_t* ctx) {
    const pgfs_flash_opts_t* flash_opts = NULL;
    char mount_point[sizeof(ctx->mount_point)] = {0};
    uint8_t mounted = 0;
    uint32_t next_generation = 0;
    pgfs_checkpoint_t checkpoint = {0};
    int loaded = -1;

    if (ctx == NULL) {
        return -1;
    }
    flash_opts = ctx->flash_opts;
    memcpy(mount_point, ctx->mount_point, sizeof(mount_point));
    mounted = (uint8_t)ctx->mounted;
    next_generation = ctx->runtime_generation;

    if (ctx->mounted) {
        if (pgfs_checkpoint_commit_pending(ctx) != 0) {
            LLOGW("pgfs: CP commit failed on reset, falling back to on-flash state "
                  "(orphan log records beyond the persisted log_tail will be ignored)");
        }
        pgfs_ftl_deinit(&ctx->ftl);
    }
    if (ctx->mutex != NULL) {
        luat_mutex_release(ctx->mutex);
        ctx->mutex = NULL;
    }
    pgfs_file_reset_all();
    memset(ctx, 0, sizeof(*ctx));
    ctx->runtime_generation = next_generation == 0 ? 1 : next_generation + 1;
    ctx->flash_opts = flash_opts;
    memcpy(ctx->mount_point, mount_point, sizeof(ctx->mount_point));
    ctx->mounted = mounted;
    ctx->data_log_base_addr = pgfs_compute_data_log_base(ctx->flash_opts);
    ctx->data_log_write_addr = ctx->data_log_base_addr;
    ctx->data_log_prepared_until = ctx->data_log_base_addr;
    /* Re-create platform mutex after reset */
    if (ctx->mutex == NULL) {
        ctx->mutex = luat_mutex_create();
    }
    if (ctx->flash_opts != NULL) {
        loaded = pgfs_checkpoint_load(ctx, &checkpoint);
        if (loaded == 0) {
            ctx->checkpoint = checkpoint;
            ctx->checkpoint_loaded = 1;
            if (ctx->checkpoint.log_tail_block != 0 ||
                ctx->checkpoint.log_tail_offset != 0) {
                pgfs_flash_geometry_t geo = {0};
                uint32_t erase_size = 0;
                if (ctx->flash_opts->control &&
                    ctx->flash_opts->control(ctx->flash_opts->ctx,
                                                   PGFS_CTRL_GET_GEOMETRY, &geo) == 0 &&
                    geo.erase_size > 0) {
                    erase_size = geo.erase_size;
                    ctx->data_log_write_addr =
                        ctx->data_log_base_addr +
                        (uint32_t)ctx->checkpoint.log_tail_block * erase_size +
                        ctx->checkpoint.log_tail_offset;
                    ctx->data_log_prepared_until = ctx->data_log_write_addr;
                    LLOGI("pgfs reset: replay bound by CP log_tail=%u/%u (write_addr=%u)",
                          (unsigned int)ctx->checkpoint.log_tail_block,
                          (unsigned int)ctx->checkpoint.log_tail_offset,
                          (unsigned int)ctx->data_log_write_addr);
                }
            }
            loaded = pgfs_replay_data_log(ctx);
            if (loaded != 0) {
                return -1;
            }
            ctx->stats.replay_count += 1;
        }
        else {
            loaded = pgfs_rebuild_checkpoint_from_replay(ctx);
            if (loaded != 0) {
                return -1;
            }
            ctx->checkpoint_loaded = 1;
        }
    }
    if (ctx->flash_opts != NULL) {
        if (pgfs_ftl_on_mount(ctx) != 0) {
            LLOGE("pgfs: FTL re-init failed on runtime reset");
            return -1;
        }
    }
    return 0;
}

int pgfs_control_reset_runtime(void) {
    return pgfs_control_reset_runtime_ctx(pgfs_find_first_mounted());
}

int pgfs_control_reset_runtime_on(const char *mount_point) {
    return pgfs_control_reset_runtime_ctx(pgfs_find_mount_by_point(mount_point));
}

#else

const struct luat_vfs_filesystem vfs_fs_pgfs = {
    .name = "pgfs",
    .opts = {0},
    .fopts = {0},
};

void* pgfs_default_bus(void* flash, size_t offset, size_t maxsize) {
    (void)flash;
    (void)offset;
    (void)maxsize;
    return NULL;
}

void pgfs_vfs_init(void) {
}

int luat_pgfs_vfs_register(void) {
    return -1;
}

int luat_pgfs_mount(const char *mount_point, const pgfs_flash_opts_t *opts) {
    (void)mount_point;
    (void)opts;
    return -1;
}

int luat_pgfs_umount(const char *mount_point) {
    (void)mount_point;
    return -1;
}

int luat_pgfs_info(const char *path, luat_fs_info_t *info) {
    (void)path;
    if (info != NULL) {
        memset(info, 0, sizeof(*info));
    }
    return -1;
}

int luat_pgfs_begin_batch(uint32_t* out_batch_id) {
    (void)out_batch_id;
    return -1;
}

int luat_pgfs_commit_batch(uint32_t batch_id) {
    (void)batch_id;
    return -1;
}

int luat_pgfs_abort_batch(uint32_t batch_id) {
    (void)batch_id;
    return -1;
}

int luat_pgfs_begin_batch_on(const char *mount_point, uint32_t* out_batch_id) {
    (void)mount_point;
    (void)out_batch_id;
    return -1;
}

int luat_pgfs_commit_batch_on(const char *mount_point, uint32_t batch_id) {
    (void)mount_point;
    (void)batch_id;
    return -1;
}

int luat_pgfs_abort_batch_on(const char *mount_point, uint32_t batch_id) {
    (void)mount_point;
    (void)batch_id;
    return -1;
}

int pgfs_control_set_lock_mode(const char* mode) {
    (void)mode;
    return -1;
}

int pgfs_control_inject_powercut_stage(const char* stage) {
    (void)stage;
    return -1;
}

int pgfs_control_inject_corrupt_latest_cp(int enable) {
    (void)enable;
    return -1;
}

int pgfs_control_inject_bad_block_once(int enable) {
    (void)enable;
    return -1;
}

int pgfs_control_reset_runtime(void) {
    return -1;
}

int pgfs_control_set_lock_mode_on(const char *mount_point, const char* mode) {
    (void)mount_point;
    (void)mode;
    return -1;
}

int pgfs_control_inject_powercut_stage_on(const char *mount_point, const char* stage) {
    (void)mount_point;
    (void)stage;
    return -1;
}

int pgfs_control_inject_corrupt_latest_cp_on(const char *mount_point, int enable) {
    (void)mount_point;
    (void)enable;
    return -1;
}

int pgfs_control_inject_bad_block_once_on(const char *mount_point, int enable) {
    (void)mount_point;
    (void)enable;
    return -1;
}

int pgfs_control_reset_runtime_on(const char *mount_point) {
    (void)mount_point;
    return -1;
}

#endif
