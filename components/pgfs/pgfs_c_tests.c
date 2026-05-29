#include "luat_base.h"
#include "luat_crypto.h"
#include "pgfs_internal.h"
#include "luat_mem.h"

#ifdef LUAT_USE_PGFS_COMPONENT

#define PGFS_TEST_FLASH_SIZE 0x8000u
#define PGFS_TEST_DATA_RECORD_MAGIC 0x50474644u

typedef struct pgfs_test_data_record_hdr {
    uint32_t magic;
    uint32_t path_len;
    uint32_t data_len;
    uint32_t crc32;
} pgfs_test_data_record_hdr_t;

typedef struct {
    uint8_t mem[PGFS_TEST_FLASH_SIZE];
} pgfs_test_flash_t;

static uint32_t pgfs_test_crc32(const void* data, size_t len) {
    return luat_crc32(data, (uint32_t)len, 0xFFFFFFFFu, 0);
}

static void pgfs_test_build_cp(pgfs_checkpoint_t* cp, uint32_t seq, uint32_t total, uint32_t used) {
    memset(cp, 0, sizeof(*cp));
    cp->magic = PGFS_CHECKPOINT_MAGIC;
    cp->version = PGFS_ONDISK_VERSION;
    cp->seq = seq;
    cp->total_blocks = total;
    cp->used_blocks = used;
    cp->crc32 = 0;
    cp->crc32 = pgfs_test_crc32(cp, sizeof(*cp));
}

static void pgfs_test_build_sb(pgfs_superblock_t* sb, uint32_t seq, uint32_t cp_addr, uint32_t cp_crc) {
    memset(sb, 0, sizeof(*sb));
    sb->magic = PGFS_SUPERBLOCK_MAGIC;
    sb->version = PGFS_ONDISK_VERSION;
    sb->seq = seq;
    sb->checkpoint_addr = cp_addr;
    sb->checkpoint_len = sizeof(pgfs_checkpoint_t);
    sb->checkpoint_crc = cp_crc;
    sb->crc32 = 0;
    sb->crc32 = pgfs_test_crc32(sb, sizeof(*sb));
}

static size_t pgfs_test_build_record(uint8_t* out, size_t outlen, const char* path, const char* data) {
    pgfs_test_data_record_hdr_t hdr = {0};
    size_t path_len = strlen(path);
    size_t data_len = strlen(data);
    size_t need = sizeof(hdr) + path_len + data_len;
    if (out == NULL || outlen < need) {
        return 0;
    }
    hdr.magic = PGFS_TEST_DATA_RECORD_MAGIC;
    hdr.path_len = (uint32_t)path_len;
    hdr.data_len = (uint32_t)data_len;
    hdr.crc32 = pgfs_test_crc32(path, path_len);
    if (data_len > 0) {
        uint8_t* crc_buf = (uint8_t*)luat_heap_malloc(path_len + data_len);
        if (crc_buf == NULL) {
            return 0;
        }
        memcpy(crc_buf, path, path_len);
        memcpy(crc_buf + path_len, data, data_len);
        hdr.crc32 = pgfs_test_crc32(crc_buf, path_len + data_len);
        luat_heap_free(crc_buf);
    }
    memcpy(out, &hdr, sizeof(hdr));
    memcpy(out + sizeof(hdr), path, path_len);
    memcpy(out + sizeof(hdr) + path_len, data, data_len);
    return need;
}

static int pgfs_test_read(void* ctx, uint32_t addr, uint8_t* buf, size_t len) {
    pgfs_test_flash_t* tf = (pgfs_test_flash_t*)ctx;
    if (tf == NULL || buf == NULL || len == 0 || ((uint64_t)addr + (uint64_t)len) > PGFS_TEST_FLASH_SIZE) {
        return -1;
    }
    memcpy(buf, tf->mem + addr, len);
    return 0;
}

static int pgfs_test_write(void* ctx, uint32_t addr, const uint8_t* buf, size_t len) {
    pgfs_test_flash_t* tf = (pgfs_test_flash_t*)ctx;
    if (tf == NULL || buf == NULL || len == 0 || ((uint64_t)addr + (uint64_t)len) > PGFS_TEST_FLASH_SIZE) {
        return -1;
    }
    memcpy(tf->mem + addr, buf, len);
    return 0;
}

static int pgfs_test_erase(void* ctx, uint32_t block_addr, uint32_t block_count) {
    pgfs_test_flash_t* tf = (pgfs_test_flash_t*)ctx;
    uint32_t len = block_count;
    if (tf == NULL || len == 0 || ((uint64_t)block_addr + (uint64_t)len) > PGFS_TEST_FLASH_SIZE) {
        return -1;
    }
    memset(tf->mem + block_addr, 0xFF, len);
    return 0;
}

static int pgfs_test_control(void* ctx, uint32_t cmd, void* arg) {
    pgfs_flash_geometry_t* geo = (pgfs_flash_geometry_t*)arg;
    (void)ctx;
    if (cmd != PGFS_CTRL_GET_GEOMETRY || geo == NULL) {
        return -1;
    }
    geo->capacity = PGFS_TEST_FLASH_SIZE;
    geo->erase_size = 4096;
    geo->prog_size = 256;
    return 0;
}

static int pgfs_test_pick_latest_valid_sb(void) {
    int fail = 0;
    pgfs_superblock_t a = {0};
    pgfs_superblock_t b = {0};
    pgfs_superblock_t out = {0};
    pgfs_checkpoint_t cp_a = {0};
    pgfs_checkpoint_t cp_b = {0};

    pgfs_test_build_cp(&cp_a, 1, 128, 11);
    pgfs_test_build_cp(&cp_b, 2, 128, 22);
    pgfs_test_build_sb(&a, 1, PGFS_CHECKPOINT_A_ADDR, cp_a.crc32);
    pgfs_test_build_sb(&b, 2, PGFS_CHECKPOINT_B_ADDR, cp_b.crc32);

    if (pgfs_pick_latest_valid_sb(&a, &b, &out) != 0 || out.seq != 2) {
        fail++;
    }
    b.crc32 ^= 0xFFu;
    if (pgfs_pick_latest_valid_sb(&a, &b, &out) != 0 || out.seq != 1) {
        fail++;
    }
    a.crc32 ^= 0xAAu;
    if (pgfs_pick_latest_valid_sb(&a, &b, &out) == 0) {
        fail++;
    }
    return fail;
}

static int pgfs_test_checkpoint_roundtrip_and_fallback(void) {
    int fail = 0;
    pgfs_test_flash_t flash = {0};
    pgfs_flash_opts_t opts = {0};
    pgfs_mount_ctx_t ctx = {0};
    pgfs_checkpoint_t next = {0};
    pgfs_checkpoint_t loaded = {0};

    memset(flash.mem, 0xFF, sizeof(flash.mem));
    opts.ctx = &flash;
    opts.read = pgfs_test_read;
    opts.write = pgfs_test_write;
    opts.erase = pgfs_test_erase;
    opts.control = pgfs_test_control;
    ctx.flash_opts = &opts;

    if (pgfs_checkpoint_store_next(&ctx, NULL, &next) != 0 || next.seq != 1 || next.total_blocks == 0) {
        fail++;
    }
    ctx.checkpoint = next;
    if (pgfs_checkpoint_store_next(&ctx, &ctx.checkpoint, &next) != 0 || next.seq != 2) {
        fail++;
    }
    if (pgfs_checkpoint_load(&ctx, &loaded) != 0 || loaded.seq != 2) {
        fail++;
    }
    ctx.inject_corrupt_latest_cp = 1;
    if (pgfs_checkpoint_load(&ctx, &loaded) != 0 || loaded.seq != 1) {
        fail++;
    }
    return fail;
}

static int pgfs_test_lock_mode_counters(void) {
    int fail = 0;
    pgfs_mount_ctx_t ctx = {0};
    ctx.lock_mode = PGFS_LOCK_MODE_ON;
    if (pgfs_lock(&ctx) != 0 || pgfs_unlock(&ctx) != 0) {
        fail++;
    }
    if (ctx.stats.lock_acquire_count != 1 || ctx.stats.lock_passthrough_count != 0) {
        fail++;
    }
    ctx.lock_mode = PGFS_LOCK_MODE_OFF;
    if (pgfs_lock(&ctx) != 0 || pgfs_unlock(&ctx) != 0) {
        fail++;
    }
    if (ctx.stats.lock_passthrough_count != 1) {
        fail++;
    }
    return fail;
}

static int pgfs_test_directory_helpers(void) {
    int fail = 0;
    pgfs_mount_ctx_t ctx = {0};
    luat_fs_dirent_t ents[4] = {0};
    void* dir = NULL;

    if (pgfs_dir_mkdir(&ctx, "selftest_docs") != 0) {
        fail++;
    }
    if (pgfs_dir_mkdir(&ctx, "selftest_docs/manual") != 0) {
        fail++;
    }
    dir = pgfs_dir_opendir(&ctx, "selftest_docs");
    if (dir == NULL) {
        fail++;
    }
    else {
        pgfs_dir_closedir(&ctx, dir);
    }
    if (pgfs_dir_closedir(&ctx, NULL) != 0) {
        fail++;
    }
    if (pgfs_dir_lsdir(&ctx, "selftest_docs", ents, 0, 4) != 1) {
        fail++;
    }
    else if (strcmp(ents[0].d_name, "manual") != 0 || ents[0].d_type != 1) {
        fail++;
    }
    if (pgfs_dir_rmdir(&ctx, "selftest_docs/manual") != 0) {
        fail++;
    }
    if (pgfs_dir_rmdir(&ctx, "selftest_docs") != 0) {
        fail++;
    }
    return fail;
}

static int pgfs_test_replay_restores_file_contents(void) {
    int fail = 0;
    pgfs_test_flash_t flash = {0};
    pgfs_flash_opts_t opts = {0};
    pgfs_mount_ctx_t ctx = {0};
    uint8_t record[256] = {0};
    size_t record_len = 0;
    FILE* f = NULL;
    char buf[32] = {0};

    memset(flash.mem, 0xFF, sizeof(flash.mem));
    opts.ctx = &flash;
    opts.read = pgfs_test_read;
    opts.write = pgfs_test_write;
    opts.erase = pgfs_test_erase;
    opts.control = pgfs_test_control;
    ctx.flash_opts = &opts;
    ctx.runtime_generation = 1;
    ctx.mounted = 1;

    record_len = pgfs_test_build_record(record, sizeof(record), "docs/hello.txt", "persist_me");
    if (record_len == 0) {
        return 1;
    }
    if (pgfs_test_write(&flash, PGFS_DATA_LOG_BASE_ADDR, record, record_len) != 0) {
        return 1;
    }

    if (pgfs_replay_data_log(&ctx) != 0) {
        return 1;
    }
    f = pgfs_file_open(&ctx, "/docs/hello.txt", "rb");
    if (f == NULL) {
        return 1;
    }
    if (pgfs_file_read(&ctx, buf, 1, sizeof("persist_me") - 1, f) != sizeof("persist_me") - 1) {
        fail++;
    }
    if (memcmp(buf, "persist_me", sizeof("persist_me") - 1) != 0) {
        fail++;
    }
    if (pgfs_file_close(&ctx, f) != 0) {
        fail++;
    }
    if (ctx.data_log_write_addr <= PGFS_DATA_LOG_BASE_ADDR) {
        fail++;
    }
    return fail;
}

int pgfs_run_c_layer_tests(void) {
    int fail = 0;
    fail += pgfs_test_pick_latest_valid_sb();
    fail += pgfs_test_checkpoint_roundtrip_and_fallback();
    fail += pgfs_test_lock_mode_counters();
    fail += pgfs_test_directory_helpers();
    fail += pgfs_test_replay_restores_file_contents();
    return fail == 0 ? 0 : -1;
}

#else

int pgfs_run_c_layer_tests(void) {
    return -1;
}

#endif
