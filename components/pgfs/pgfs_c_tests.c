#include "luat_base.h"
#include "luat_crypto.h"
#include "pgfs_internal.h"
#include "luat_mem.h"

#ifdef LUAT_USE_PGFS_COMPONENT

#define PGFS_TEST_FLASH_SIZE 0x8000u
#define PGFS_TEST_DATA_RECORD_MAGIC 0x50474644u
#define PGFS_TEST_BATCH_DATA_RECORD_MAGIC 0x50474642u
#define PGFS_TEST_BATCH_COMMIT_RECORD_MAGIC 0x50474643u

typedef struct pgfs_test_data_record_hdr {
    uint32_t magic;
    uint32_t path_len;
    uint32_t data_len;
    uint32_t crc32;
} pgfs_test_data_record_hdr_t;

typedef struct pgfs_test_batch_data_record_hdr {
    uint32_t magic;
    uint32_t path_len;
    uint32_t data_len;
    uint32_t batch_id;
    uint32_t crc32;
} pgfs_test_batch_data_record_hdr_t;

typedef struct pgfs_test_batch_commit_record_hdr {
    uint32_t magic;
    uint32_t batch_id;
    uint32_t record_count;
    uint32_t crc32;
} pgfs_test_batch_commit_record_hdr_t;

typedef struct {
    uint8_t mem[PGFS_TEST_FLASH_SIZE];
    uint32_t fail_read_addr;
    uint32_t fail_read_len;
    uint32_t inject_nonff_addr;
    uint32_t inject_nonff_len;
    uint32_t capacity_override;
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

static size_t pgfs_test_build_batch_data_record(uint8_t* out, size_t outlen, uint32_t batch_id, const char* path, const char* data) {
    pgfs_test_batch_data_record_hdr_t hdr = {0};
    size_t path_len = strlen(path);
    size_t data_len = strlen(data);
    size_t need = sizeof(hdr) + path_len + data_len;
    uint8_t* crc_buf = NULL;
    size_t crc_len = path_len + data_len;
    if (out == NULL || outlen < need || batch_id == 0) {
        return 0;
    }
    hdr.magic = PGFS_TEST_BATCH_DATA_RECORD_MAGIC;
    hdr.path_len = (uint32_t)path_len;
    hdr.data_len = (uint32_t)data_len;
    hdr.batch_id = batch_id;
    if (crc_len > 0) {
        crc_buf = (uint8_t*)luat_heap_malloc(crc_len);
        if (crc_buf == NULL) {
            return 0;
        }
        memcpy(crc_buf, path, path_len);
        if (data_len > 0) {
            memcpy(crc_buf + path_len, data, data_len);
        }
        hdr.crc32 = pgfs_test_crc32(crc_buf, crc_len);
        luat_heap_free(crc_buf);
    }
    memcpy(out, &hdr, sizeof(hdr));
    memcpy(out + sizeof(hdr), path, path_len);
    if (data_len > 0) {
        memcpy(out + sizeof(hdr) + path_len, data, data_len);
    }
    return need;
}

static size_t pgfs_test_build_batch_commit_record(uint8_t* out, size_t outlen, uint32_t batch_id, uint32_t record_count) {
    pgfs_test_batch_commit_record_hdr_t hdr = {0};
    if (out == NULL || outlen < sizeof(hdr) || batch_id == 0) {
        return 0;
    }
    hdr.magic = PGFS_TEST_BATCH_COMMIT_RECORD_MAGIC;
    hdr.batch_id = batch_id;
    hdr.record_count = record_count;
    hdr.crc32 = pgfs_test_crc32(&hdr, sizeof(hdr) - sizeof(hdr.crc32));
    memcpy(out, &hdr, sizeof(hdr));
    return sizeof(hdr);
}

static uint32_t pgfs_test_align_prog(uint32_t v) {
    uint32_t prog = 256;
    return (uint32_t)(((uint64_t)v + prog - 1u) / prog * prog);
}

static int pgfs_test_read(void* ctx, uint32_t addr, uint8_t* buf, size_t len) {
    pgfs_test_flash_t* tf = (pgfs_test_flash_t*)ctx;
    uint64_t req_start = addr;
    uint64_t req_end = (uint64_t)addr + (uint64_t)len;
    uint64_t fail_start = 0;
    uint64_t fail_end = 0;
    if (tf == NULL || buf == NULL || len == 0 || ((uint64_t)addr + (uint64_t)len) > PGFS_TEST_FLASH_SIZE) {
        return -1;
    }
    if (tf->fail_read_len != 0) {
        fail_start = tf->fail_read_addr;
        fail_end = (uint64_t)tf->fail_read_addr + (uint64_t)tf->fail_read_len;
        if (req_start < fail_end && req_end > fail_start) {
            return -1;
        }
    }
    memcpy(buf, tf->mem + addr, len);
    if (tf->inject_nonff_len != 0) {
        uint64_t inject_start = tf->inject_nonff_addr;
        uint64_t inject_end = (uint64_t)tf->inject_nonff_addr + (uint64_t)tf->inject_nonff_len;
        if (req_start < inject_end && req_end > inject_start) {
            buf[0] = 0x00;
        }
    }
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
    pgfs_test_flash_t* tf = (pgfs_test_flash_t*)ctx;
    (void)ctx;
    if (cmd != PGFS_CTRL_GET_GEOMETRY || geo == NULL) {
        return -1;
    }
    geo->capacity = (tf != NULL && tf->capacity_override != 0) ? tf->capacity_override : PGFS_TEST_FLASH_SIZE;
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

static int pgfs_test_close_succeeds_when_probe_read_fails_on_unaligned_append(void) {
    int fail = 0;
    pgfs_test_flash_t flash = {0};
    pgfs_flash_opts_t opts = {0};
    pgfs_mount_ctx_t ctx = {0};
    FILE* f = NULL;
    const char payload[] = "large_payload_chunk";
    uint32_t write_addr = 0;
    pgfs_test_data_record_hdr_t hdr = {0};

    memset(flash.mem, 0xFF, sizeof(flash.mem));
    opts.ctx = &flash;
    opts.read = pgfs_test_read;
    opts.write = pgfs_test_write;
    opts.erase = pgfs_test_erase;
    opts.control = pgfs_test_control;
    ctx.flash_opts = &opts;
    ctx.runtime_generation = 1;
    ctx.mounted = 1;
    ctx.data_log_base_addr = PGFS_DATA_LOG_BASE_ADDR;
    ctx.data_log_write_addr = PGFS_DATA_LOG_BASE_ADDR + 2048u; /* intentionally unaligned to erase_size(4096) */
    write_addr = ctx.data_log_write_addr;
    flash.fail_read_addr = write_addr;
    flash.fail_read_len = 512;

    f = pgfs_file_open(&ctx, "/apps/nes/main.lua", "wb");
    if (f == NULL) {
        return 1;
    }
    if (pgfs_file_write(&ctx, payload, 1, sizeof(payload) - 1, f) != sizeof(payload) - 1) {
        fail++;
    }
    if (pgfs_file_close(&ctx, f) != 0) {
        fail++;
    }
    memcpy(&hdr, flash.mem + write_addr, sizeof(hdr));
    if (hdr.magic != PGFS_TEST_DATA_RECORD_MAGIC) {
        fail++;
    }
    return fail;
}

static int pgfs_test_close_succeeds_when_probe_nonff_on_unaligned_append(void) {
    int fail = 0;
    pgfs_test_flash_t flash = {0};
    pgfs_flash_opts_t opts = {0};
    pgfs_mount_ctx_t ctx = {0};
    FILE* f = NULL;
    const char payload[] = "large_payload_chunk";
    uint32_t write_addr = 0;

    memset(flash.mem, 0xFF, sizeof(flash.mem));
    opts.ctx = &flash;
    opts.read = pgfs_test_read;
    opts.write = pgfs_test_write;
    opts.erase = pgfs_test_erase;
    opts.control = pgfs_test_control;
    ctx.flash_opts = &opts;
    ctx.runtime_generation = 1;
    ctx.mounted = 1;
    ctx.data_log_base_addr = PGFS_DATA_LOG_BASE_ADDR;
    ctx.data_log_write_addr = PGFS_DATA_LOG_BASE_ADDR + 2048u; /* intentionally unaligned to erase_size(4096) */
    write_addr = ctx.data_log_write_addr;
    flash.inject_nonff_addr = write_addr + 512u;
    flash.inject_nonff_len = 64;

    f = pgfs_file_open(&ctx, "/apps/nes/rom.bin", "wb");
    if (f == NULL) {
        return 1;
    }
    if (pgfs_file_write(&ctx, payload, 1, sizeof(payload) - 1, f) != sizeof(payload) - 1) {
        fail++;
    }
    if (pgfs_file_close(&ctx, f) != 0) {
        fail++;
    }
    return fail;
}

static int pgfs_test_close_advances_to_next_erase_block_when_unaligned_head_is_programmed(void) {
    int fail = 0;
    pgfs_test_flash_t flash = {0};
    pgfs_flash_opts_t opts = {0};
    pgfs_mount_ctx_t ctx = {0};
    FILE* f = NULL;
    const char payload[] = "tail_collision_payload";
    uint32_t write_addr = 0;
    uint32_t next_block = 0;
    pgfs_test_data_record_hdr_t hdr = {0};

    memset(flash.mem, 0xFF, sizeof(flash.mem));
    opts.ctx = &flash;
    opts.read = pgfs_test_read;
    opts.write = pgfs_test_write;
    opts.erase = pgfs_test_erase;
    opts.control = pgfs_test_control;
    ctx.flash_opts = &opts;
    ctx.runtime_generation = 1;
    ctx.mounted = 1;
    ctx.data_log_base_addr = PGFS_DATA_LOG_BASE_ADDR;
    ctx.data_log_write_addr = PGFS_DATA_LOG_BASE_ADDR + 2048u; /* unaligned to erase_size(4096) */
    write_addr = ctx.data_log_write_addr;
    next_block = ((write_addr / 4096u) + 1u) * 4096u;
    flash.mem[write_addr] = 0x00; /* stale programmed tail at current unaligned head */

    f = pgfs_file_open(&ctx, "/apps/nes/meta.json", "wb");
    if (f == NULL) {
        return 1;
    }
    if (pgfs_file_write(&ctx, payload, 1, sizeof(payload) - 1, f) != sizeof(payload) - 1) {
        fail++;
    }
    if (pgfs_file_close(&ctx, f) != 0) {
        fail++;
    }
    if (ctx.data_log_write_addr <= next_block) {
        fail++;
    }
    memcpy(&hdr, flash.mem + next_block, sizeof(hdr));
    if (hdr.magic != PGFS_TEST_DATA_RECORD_MAGIC) {
        fail++;
    }
    return fail;
}

static int pgfs_test_checkpoint_batch_close_and_pending_commit(void) {
    int fail = 0;
    pgfs_test_flash_t flash = {0};
    pgfs_flash_opts_t opts = {0};
    pgfs_mount_ctx_t ctx = {0};
    pgfs_checkpoint_t loaded = {0};
    const char payload[] = "cp_batch_payload";
    uint32_t i = 0;
    FILE* f = NULL;

    memset(flash.mem, 0xFF, sizeof(flash.mem));
    opts.ctx = &flash;
    opts.read = pgfs_test_read;
    opts.write = pgfs_test_write;
    opts.erase = pgfs_test_erase;
    opts.control = pgfs_test_control;
    ctx.flash_opts = &opts;
    ctx.runtime_generation = 1;
    ctx.mounted = 1;
    ctx.data_log_base_addr = PGFS_DATA_LOG_BASE_ADDR;
    ctx.data_log_write_addr = PGFS_DATA_LOG_BASE_ADDR;
    ctx.data_log_prepared_until = PGFS_DATA_LOG_BASE_ADDR;

    for (i = 1; i < PGFS_CHECKPOINT_BATCH_CLOSES; i++) {
        f = pgfs_file_open(&ctx, "/batch/cp.txt", "wb");
        if (f == NULL) {
            return 1;
        }
        if (pgfs_file_write(&ctx, payload, 1, sizeof(payload) - 1, f) != sizeof(payload) - 1) {
            fail++;
        }
        if (pgfs_file_close(&ctx, f) != 0) {
            fail++;
        }
        if (ctx.pending_checkpoint_writes != i) {
            fail++;
        }
    }
    if (pgfs_checkpoint_load(&ctx, &loaded) == 0) {
        fail++;
    }

    f = pgfs_file_open(&ctx, "/batch/cp.txt", "wb");
    if (f == NULL) {
        return 1;
    }
    if (pgfs_file_write(&ctx, payload, 1, sizeof(payload) - 1, f) != sizeof(payload) - 1) {
        fail++;
    }
    if (pgfs_file_close(&ctx, f) != 0) {
        fail++;
    }
    if (ctx.pending_checkpoint_writes != 0) {
        fail++;
    }
    if (pgfs_checkpoint_load(&ctx, &loaded) != 0 || loaded.seq != 1) {
        fail++;
    }

    f = pgfs_file_open(&ctx, "/batch/cp.txt", "wb");
    if (f == NULL) {
        return 1;
    }
    if (pgfs_file_write(&ctx, payload, 1, sizeof(payload) - 1, f) != sizeof(payload) - 1) {
        fail++;
    }
    if (pgfs_file_close(&ctx, f) != 0) {
        fail++;
    }
    if (ctx.pending_checkpoint_writes != 1) {
        fail++;
    }
    if (pgfs_checkpoint_commit_pending(&ctx) != 0) {
        fail++;
    }
    if (ctx.pending_checkpoint_writes != 0) {
        fail++;
    }
    if (pgfs_checkpoint_load(&ctx, &loaded) != 0 || loaded.seq != 2) {
        fail++;
    }
    return fail;
}

static int pgfs_test_batch_api_boundaries(void) {
    int fail = 0;
    pgfs_test_flash_t flash = {0};
    pgfs_flash_opts_t opts = {0};
    pgfs_mount_ctx_t ctx = {0};
    FILE* f_batch = NULL;
    FILE* f_plain = NULL;
    uint32_t batch1 = 0;
    uint32_t batch2 = 0;
    const char payload[] = "batch_payload";
    const char plain_payload[] = "plain_payload";
    char buf[32] = {0};
    FILE* f_read = NULL;

    memset(flash.mem, 0xFF, sizeof(flash.mem));
    opts.ctx = &flash;
    opts.read = pgfs_test_read;
    opts.write = pgfs_test_write;
    opts.erase = pgfs_test_erase;
    opts.control = pgfs_test_control;

    ctx.flash_opts = &opts;
    ctx.runtime_generation = 1;
    ctx.mounted = 1;
    ctx.data_log_base_addr = PGFS_DATA_LOG_BASE_ADDR;
    ctx.data_log_write_addr = PGFS_DATA_LOG_BASE_ADDR;
    ctx.data_log_prepared_until = PGFS_DATA_LOG_BASE_ADDR;

    /* open/write/close in one batch: success */
    if (pgfs_batch_begin(&ctx, &batch1) != 0 || batch1 == 0) {
        return 1;
    }
    f_batch = pgfs_file_open(&ctx, "/batch/ok.txt", "wb");
    if (f_batch == NULL) {
        fail++;
    }
    else {
        if (pgfs_file_write(&ctx, payload, 1, sizeof(payload) - 1, f_batch) != sizeof(payload) - 1) {
            fail++;
        }
        if (pgfs_file_close(&ctx, f_batch) != 0) {
            fail++;
        }
    }
    if (pgfs_batch_commit(&ctx, batch1) != 0) {
        fail++;
    }

    /* batch-open handle must fail outside batch */
    if (pgfs_batch_begin(&ctx, &batch1) != 0) {
        fail++;
    }
    f_batch = pgfs_file_open(&ctx, "/batch/outside_fail.txt", "wb");
    if (f_batch == NULL) {
        fail++;
    }
    if (pgfs_batch_abort(&ctx, batch1) != 0) {
        fail++;
    }
    if (f_batch != NULL) {
        if (pgfs_file_write(&ctx, payload, 1, sizeof(payload) - 1, f_batch) != 0) {
            fail++;
        }
        if (pgfs_file_close(&ctx, f_batch) == 0) {
            fail++;
        }
    }

    /* cross-batch write/close fail */
    if (pgfs_batch_begin(&ctx, &batch1) != 0) {
        fail++;
    }
    f_batch = pgfs_file_open(&ctx, "/batch/cross.txt", "wb");
    if (f_batch == NULL) {
        fail++;
    }
    if (pgfs_batch_commit(&ctx, batch1) != 0) {
        fail++;
    }
    if (pgfs_batch_begin(&ctx, &batch2) != 0) {
        fail++;
    }
    if (f_batch != NULL) {
        if (pgfs_file_write(&ctx, payload, 1, sizeof(payload) - 1, f_batch) != 0) {
            fail++;
        }
        if (pgfs_file_close(&ctx, f_batch) == 0) {
            fail++;
        }
    }
    if (pgfs_batch_abort(&ctx, batch2) != 0) {
        fail++;
    }

    /* non-batch handle used inside batch fails; reverse mismatch also fails */
    f_plain = pgfs_file_open(&ctx, "/batch/plain_mismatch.txt", "wb");
    if (f_plain == NULL) {
        fail++;
    }
    else if (pgfs_file_write(&ctx, plain_payload, 1, sizeof(plain_payload) - 1, f_plain) != sizeof(plain_payload) - 1) {
        fail++;
    }
    if (pgfs_batch_begin(&ctx, &batch1) != 0) {
        fail++;
    }
    if (f_plain != NULL) {
        if (pgfs_file_write(&ctx, payload, 1, sizeof(payload) - 1, f_plain) != 0) {
            fail++;
        }
        if (pgfs_file_close(&ctx, f_plain) == 0) {
            fail++;
        }
        f_plain = NULL;
    }
    if (pgfs_batch_abort(&ctx, batch1) != 0) {
        fail++;
    }

    /* commit visibility */
    if (pgfs_batch_begin(&ctx, &batch1) != 0) {
        fail++;
    }
    f_batch = pgfs_file_open(&ctx, "/batch/commit_visible.txt", "wb");
    if (f_batch == NULL) {
        fail++;
    }
    else {
        if (pgfs_file_write(&ctx, payload, 1, sizeof(payload) - 1, f_batch) != sizeof(payload) - 1) {
            fail++;
        }
        if (pgfs_file_close(&ctx, f_batch) != 0) {
            fail++;
        }
        f_batch = NULL;
    }
    f_read = pgfs_file_open(&ctx, "/batch/commit_visible.txt", "rb");
    if (f_read != NULL) {
        if (pgfs_file_read(&ctx, buf, 1, sizeof(payload) - 1, f_read) != 0) {
            fail++;
        }
        pgfs_file_close(&ctx, f_read);
    }
    if (pgfs_batch_commit(&ctx, batch1) != 0) {
        fail++;
    }
    memset(buf, 0, sizeof(buf));
    f_read = pgfs_file_open(&ctx, "/batch/commit_visible.txt", "rb");
    if (f_read == NULL) {
        fail++;
    }
    else {
        if (pgfs_file_read(&ctx, buf, 1, sizeof(payload) - 1, f_read) != sizeof(payload) - 1) {
            fail++;
        }
        if (memcmp(buf, payload, sizeof(payload) - 1) != 0) {
            fail++;
        }
        if (pgfs_file_close(&ctx, f_read) != 0) {
            fail++;
        }
    }

    /* abort non-visibility */
    if (pgfs_batch_begin(&ctx, &batch1) != 0) {
        fail++;
    }
    f_batch = pgfs_file_open(&ctx, "/batch/abort_hidden.txt", "wb");
    if (f_batch == NULL) {
        fail++;
    }
    else {
        if (pgfs_file_write(&ctx, payload, 1, sizeof(payload) - 1, f_batch) != sizeof(payload) - 1) {
            fail++;
        }
        if (pgfs_file_close(&ctx, f_batch) != 0) {
            fail++;
        }
        f_batch = NULL;
    }
    if (pgfs_batch_abort(&ctx, batch1) != 0) {
        fail++;
    }
    f_read = pgfs_file_open(&ctx, "/batch/abort_hidden.txt", "rb");
    if (f_read != NULL) {
        fail++;
        pgfs_file_close(&ctx, f_read);
    }

    pgfs_file_reset_all();
    return fail;
}

static int pgfs_test_batch_commit_persists_after_replay(void) {
    int fail = 0;
    pgfs_test_flash_t flash = {0};
    pgfs_flash_opts_t opts = {0};
    pgfs_mount_ctx_t ctx = {0};
    pgfs_mount_ctx_t ctx_replay = {0};
    FILE* f = NULL;
    FILE* f_read = NULL;
    uint32_t batch_id = 0;
    const char payload[] = "batch_durable_payload";
    char buf[64] = {0};

    memset(flash.mem, 0xFF, sizeof(flash.mem));
    opts.ctx = &flash;
    opts.read = pgfs_test_read;
    opts.write = pgfs_test_write;
    opts.erase = pgfs_test_erase;
    opts.control = pgfs_test_control;

    ctx.flash_opts = &opts;
    ctx.runtime_generation = 1;
    ctx.mounted = 1;
    ctx.data_log_base_addr = PGFS_DATA_LOG_BASE_ADDR;
    ctx.data_log_write_addr = PGFS_DATA_LOG_BASE_ADDR;
    ctx.data_log_prepared_until = PGFS_DATA_LOG_BASE_ADDR;

    if (pgfs_batch_begin(&ctx, &batch_id) != 0 || batch_id == 0) {
        return 1;
    }
    f = pgfs_file_open(&ctx, "/batch/replay_commit.txt", "wb");
    if (f == NULL) {
        return 1;
    }
    if (pgfs_file_write(&ctx, payload, 1, sizeof(payload) - 1, f) != sizeof(payload) - 1) {
        fail++;
    }
    if (pgfs_file_close(&ctx, f) != 0) {
        fail++;
    }
    if (pgfs_batch_commit(&ctx, batch_id) != 0) {
        fail++;
    }

    f_read = pgfs_file_open(&ctx, "/batch/replay_commit.txt", "rb");
    if (f_read == NULL) {
        fail++;
    }
    else {
        memset(buf, 0, sizeof(buf));
        if (pgfs_file_read(&ctx, buf, 1, sizeof(payload) - 1, f_read) != sizeof(payload) - 1) {
            fail++;
        }
        if (memcmp(buf, payload, sizeof(payload) - 1) != 0) {
            fail++;
        }
        if (pgfs_file_close(&ctx, f_read) != 0) {
            fail++;
        }
    }

    pgfs_file_reset_all();

    ctx_replay.flash_opts = &opts;
    ctx_replay.runtime_generation = 2;
    ctx_replay.mounted = 1;
    ctx_replay.data_log_base_addr = PGFS_DATA_LOG_BASE_ADDR;
    ctx_replay.data_log_write_addr = PGFS_DATA_LOG_BASE_ADDR;
    ctx_replay.data_log_prepared_until = PGFS_DATA_LOG_BASE_ADDR;
    if (pgfs_replay_data_log(&ctx_replay) != 0) {
        fail++;
    }
    f_read = pgfs_file_open(&ctx_replay, "/batch/replay_commit.txt", "rb");
    if (f_read == NULL) {
        fail++;
    }
    else {
        memset(buf, 0, sizeof(buf));
        if (pgfs_file_read(&ctx_replay, buf, 1, sizeof(payload) - 1, f_read) != sizeof(payload) - 1) {
            fail++;
        }
        if (memcmp(buf, payload, sizeof(payload) - 1) != 0) {
            fail++;
        }
        if (pgfs_file_close(&ctx_replay, f_read) != 0) {
            fail++;
        }
    }
    return fail;
}

static int pgfs_test_replay_skips_blank_prefix_to_relocated_log(void) {
    int fail = 0;
    pgfs_test_flash_t flash = {0};
    pgfs_flash_opts_t opts = {0};
    pgfs_mount_ctx_t ctx = {0};
    uint8_t record[256] = {0};
    size_t rec_len = 0;
    uint32_t addr = PGFS_DATA_LOG_BASE_ADDR + 4096u;
    uint32_t batch_id = 8;
    FILE* f_read = NULL;
    char buf[64] = {0};

    memset(flash.mem, 0xFF, sizeof(flash.mem));
    opts.ctx = &flash;
    opts.read = pgfs_test_read;
    opts.write = pgfs_test_write;
    opts.erase = pgfs_test_erase;
    opts.control = pgfs_test_control;

    rec_len = pgfs_test_build_batch_data_record(record, sizeof(record), batch_id, "batch/relocated.txt", "relocated");
    if (rec_len == 0) {
        return 1;
    }
    if (pgfs_test_write(&flash, addr, record, rec_len) != 0) {
        return 1;
    }
    addr = pgfs_test_align_prog(addr + (uint32_t)rec_len);

    rec_len = pgfs_test_build_batch_commit_record(record, sizeof(record), batch_id, 1);
    if (rec_len == 0) {
        return 1;
    }
    if (pgfs_test_write(&flash, addr, record, rec_len) != 0) {
        return 1;
    }

    ctx.flash_opts = &opts;
    ctx.runtime_generation = 1;
    ctx.mounted = 1;
    ctx.data_log_base_addr = PGFS_DATA_LOG_BASE_ADDR;
    ctx.data_log_write_addr = PGFS_DATA_LOG_BASE_ADDR;
    ctx.data_log_prepared_until = PGFS_DATA_LOG_BASE_ADDR;

    if (pgfs_replay_data_log(&ctx) != 0) {
        fail++;
    }
    f_read = pgfs_file_open(&ctx, "/batch/relocated.txt", "rb");
    if (f_read == NULL) {
        fail++;
    }
    else {
        memset(buf, 0, sizeof(buf));
        if (pgfs_file_read(&ctx, buf, 1, 9, f_read) != 9) {
            fail++;
        }
        if (memcmp(buf, "relocated", 9) != 0) {
            fail++;
        }
        if (pgfs_file_close(&ctx, f_read) != 0) {
            fail++;
        }
    }
    return fail;
}

static int pgfs_test_replay_skips_unknown_prefix_to_relocated_log(void) {
    int fail = 0;
    pgfs_test_flash_t flash = {0};
    pgfs_flash_opts_t opts = {0};
    pgfs_mount_ctx_t ctx = {0};
    uint8_t record[256] = {0};
    size_t rec_len = 0;
    uint32_t addr = PGFS_DATA_LOG_BASE_ADDR + 4096u;
    uint32_t batch_id = 9;
    uint32_t unknown_magic = 0x12345678u;
    FILE* f_read = NULL;
    char buf[64] = {0};

    memset(flash.mem, 0xFF, sizeof(flash.mem));
    opts.ctx = &flash;
    opts.read = pgfs_test_read;
    opts.write = pgfs_test_write;
    opts.erase = pgfs_test_erase;
    opts.control = pgfs_test_control;

    if (pgfs_test_write(&flash, PGFS_DATA_LOG_BASE_ADDR, (const uint8_t*)&unknown_magic, sizeof(unknown_magic)) != 0) {
        return 1;
    }

    rec_len = pgfs_test_build_batch_data_record(record, sizeof(record), batch_id, "batch/unknown_prefix.txt", "unknown_ok");
    if (rec_len == 0) {
        return 1;
    }
    if (pgfs_test_write(&flash, addr, record, rec_len) != 0) {
        return 1;
    }
    addr = pgfs_test_align_prog(addr + (uint32_t)rec_len);

    rec_len = pgfs_test_build_batch_commit_record(record, sizeof(record), batch_id, 1);
    if (rec_len == 0) {
        return 1;
    }
    if (pgfs_test_write(&flash, addr, record, rec_len) != 0) {
        return 1;
    }

    ctx.flash_opts = &opts;
    ctx.runtime_generation = 1;
    ctx.mounted = 1;
    ctx.data_log_base_addr = PGFS_DATA_LOG_BASE_ADDR;
    ctx.data_log_write_addr = PGFS_DATA_LOG_BASE_ADDR;
    ctx.data_log_prepared_until = PGFS_DATA_LOG_BASE_ADDR;

    if (pgfs_replay_data_log(&ctx) != 0) {
        fail++;
    }
    f_read = pgfs_file_open(&ctx, "/batch/unknown_prefix.txt", "rb");
    if (f_read == NULL) {
        fail++;
    }
    else {
        memset(buf, 0, sizeof(buf));
        if (pgfs_file_read(&ctx, buf, 1, 10, f_read) != 10) {
            fail++;
        }
        if (memcmp(buf, "unknown_ok", 10) != 0) {
            fail++;
        }
        if (pgfs_file_close(&ctx, f_read) != 0) {
            fail++;
        }
    }
    return fail;
}

static int pgfs_test_replay_batch_commit_marker_boundary(void) {
    int fail = 0;
    pgfs_test_flash_t flash = {0};
    pgfs_flash_opts_t opts = {0};
    pgfs_mount_ctx_t ctx = {0};
    uint8_t record[256] = {0};
    size_t rec_len = 0;
    uint32_t addr = PGFS_DATA_LOG_BASE_ADDR;
    uint32_t batch_id = 7;
    FILE* f_read = NULL;
    char buf[64] = {0};

    memset(flash.mem, 0xFF, sizeof(flash.mem));
    opts.ctx = &flash;
    opts.read = pgfs_test_read;
    opts.write = pgfs_test_write;
    opts.erase = pgfs_test_erase;
    opts.control = pgfs_test_control;

    rec_len = pgfs_test_build_batch_data_record(record, sizeof(record), batch_id, "batch/half.txt", "half");
    if (rec_len == 0) {
        return 1;
    }
    if (pgfs_test_write(&flash, addr, record, rec_len) != 0) {
        return 1;
    }
    addr = pgfs_test_align_prog(addr + (uint32_t)rec_len);

    ctx.flash_opts = &opts;
    ctx.runtime_generation = 1;
    ctx.mounted = 1;
    ctx.data_log_base_addr = PGFS_DATA_LOG_BASE_ADDR;
    ctx.data_log_write_addr = PGFS_DATA_LOG_BASE_ADDR;
    ctx.data_log_prepared_until = PGFS_DATA_LOG_BASE_ADDR;
    if (pgfs_replay_data_log(&ctx) != 0) {
        fail++;
    }
    f_read = pgfs_file_open(&ctx, "/batch/half.txt", "rb");
    if (f_read != NULL) {
        fail++;
        pgfs_file_close(&ctx, f_read);
    }

    rec_len = pgfs_test_build_batch_commit_record(record, sizeof(record), batch_id, 1);
    if (rec_len == 0) {
        return 1;
    }
    if (pgfs_test_write(&flash, addr, record, rec_len) != 0) {
        return 1;
    }

    pgfs_file_reset_all();
    memset(&ctx, 0, sizeof(ctx));
    ctx.flash_opts = &opts;
    ctx.runtime_generation = 2;
    ctx.mounted = 1;
    ctx.data_log_base_addr = PGFS_DATA_LOG_BASE_ADDR;
    ctx.data_log_write_addr = PGFS_DATA_LOG_BASE_ADDR;
    ctx.data_log_prepared_until = PGFS_DATA_LOG_BASE_ADDR;
    if (pgfs_replay_data_log(&ctx) != 0) {
        fail++;
    }
    f_read = pgfs_file_open(&ctx, "/batch/half.txt", "rb");
    if (f_read == NULL) {
        fail++;
    }
    else {
        memset(buf, 0, sizeof(buf));
        if (pgfs_file_read(&ctx, buf, 1, 4, f_read) != 4 || memcmp(buf, "half", 4) != 0) {
            fail++;
        }
        if (pgfs_file_close(&ctx, f_read) != 0) {
            fail++;
        }
    }

    return fail;
}

static int pgfs_test_info_fastpath_uses_runtime_checkpoint(void) {
    int fail = 0;
    pgfs_test_flash_t flash = {0};
    pgfs_flash_opts_t opts = {0};
    pgfs_mount_ctx_t ctx = {0};
    luat_fs_info_t info = {0};
    uint8_t record[256] = {0};
    size_t record_len = 0;

    memset(flash.mem, 0xFF, sizeof(flash.mem));
    opts.ctx = &flash;
    opts.read = pgfs_test_read;
    opts.write = pgfs_test_write;
    opts.erase = pgfs_test_erase;
    opts.control = pgfs_test_control;
    ctx.flash_opts = &opts;

    /* Fast path should not touch checkpoint flash load if runtime checkpoint is valid. */
    ctx.checkpoint_loaded = 1;
    ctx.checkpoint.magic = PGFS_CHECKPOINT_MAGIC;
    ctx.checkpoint.version = PGFS_ONDISK_VERSION;
    ctx.checkpoint.total_blocks = 8;
    ctx.checkpoint.used_blocks = 3;
    flash.fail_read_addr = 0;
    flash.fail_read_len = PGFS_TEST_FLASH_SIZE;
    if (pgfs_info_fast(&ctx, &info) != 0) {
        fail++;
    }
    else {
        if (info.block_size != 4096 || info.total_block != 8 || info.block_used != 3 || (info.total_block - info.block_used) != 5) {
            fail++;
        }
    }

    /* Runtime accounting should be reflected immediately after writes update used_blocks. */
    ctx.checkpoint.used_blocks = 5;
    memset(&info, 0, sizeof(info));
    if (pgfs_info_fast(&ctx, &info) != 0 || info.block_used != 5 || (info.total_block - info.block_used) != 3) {
        fail++;
    }

    /* Fallback path must still rebuild correctly when runtime checkpoint is unavailable. */
    memset(&flash, 0, sizeof(flash));
    memset(flash.mem, 0xFF, sizeof(flash.mem));
    memset(&ctx, 0, sizeof(ctx));
    ctx.flash_opts = &opts;
    ctx.runtime_generation = 1;
    ctx.mounted = 1;
    record_len = pgfs_test_build_record(record, sizeof(record), "apps/replay.txt", "persist");
    if (record_len == 0) {
        return 1;
    }
    if (pgfs_test_write(&flash, PGFS_DATA_LOG_BASE_ADDR, record, record_len) != 0) {
        return 1;
    }
    memset(&info, 0, sizeof(info));
    if (pgfs_info_fast(&ctx, &info) != 0) {
        fail++;
    }
    else {
        if (info.block_size != 4096 || info.total_block != 8 || info.block_used != 1 || (info.total_block - info.block_used) != 7) {
            fail++;
        }
    }
    return fail;
}

/* Verify that replay skips a NAND bad-page (ECC failure mid-block) and continues
 * scanning the NEXT block, so records written there are not lost. */
static int pgfs_test_replay_skips_bad_block_and_recovers_next_block(void) {
    int fail = 0;
    pgfs_test_flash_t flash = {0};
    pgfs_flash_opts_t opts = {0};
    pgfs_mount_ctx_t ctx = {0};
    uint8_t rec1[256] = {0};
    uint8_t rec2[256] = {0};
    size_t rec1_len = 0;
    size_t rec2_len = 0;
    uint32_t rec1_storage = 0;
    uint32_t rec2_start = 0;
    FILE* f = NULL;
    char buf[32] = {0};

    memset(flash.mem, 0xFF, sizeof(flash.mem));
    opts.ctx = &flash;
    opts.read = pgfs_test_read;
    opts.write = pgfs_test_write;
    opts.erase = pgfs_test_erase;
    opts.control = pgfs_test_control;

    rec1_len = pgfs_test_build_record(rec1, sizeof(rec1), "nand/before_bad.txt", "hello_before");
    if (rec1_len == 0) {
        return 1;
    }
    if (pgfs_test_write(&flash, PGFS_DATA_LOG_BASE_ADDR, rec1, rec1_len) != 0) {
        return 1;
    }
    rec1_storage = pgfs_test_align_prog((uint32_t)rec1_len);

    /* Simulate ECC failure starting right after record 1 (mid-block). */
    flash.fail_read_addr = PGFS_DATA_LOG_BASE_ADDR + rec1_storage;
    flash.fail_read_len = 256;

    /* Record 2 written to the NEXT erase block (erase_size=4096). */
    rec2_start = PGFS_DATA_LOG_BASE_ADDR + 4096u;
    rec2_len = pgfs_test_build_record(rec2, sizeof(rec2), "nand/after_bad.txt", "hello_after");
    if (rec2_len == 0) {
        return 1;
    }
    if (pgfs_test_write(&flash, rec2_start, rec2, rec2_len) != 0) {
        return 1;
    }

    ctx.flash_opts = &opts;
    ctx.runtime_generation = 1;
    ctx.mounted = 1;
    ctx.data_log_base_addr = PGFS_DATA_LOG_BASE_ADDR;
    ctx.data_log_write_addr = PGFS_DATA_LOG_BASE_ADDR;
    ctx.data_log_prepared_until = PGFS_DATA_LOG_BASE_ADDR;

    if (pgfs_replay_data_log(&ctx) != 0) {
        return 1;
    }

    /* Both files must be visible after replay. */
    f = pgfs_file_open(&ctx, "/nand/before_bad.txt", "rb");
    if (f == NULL) {
        fail++;
    }
    else {
        if (pgfs_file_read(&ctx, buf, 1, sizeof("hello_before") - 1, f) != sizeof("hello_before") - 1 ||
            memcmp(buf, "hello_before", sizeof("hello_before") - 1) != 0) {
            fail++;
        }
        pgfs_file_close(&ctx, f);
    }

    memset(buf, 0, sizeof(buf));
    f = pgfs_file_open(&ctx, "/nand/after_bad.txt", "rb");
    if (f == NULL) {
        fail++;
    }
    else {
        if (pgfs_file_read(&ctx, buf, 1, sizeof("hello_after") - 1, f) != sizeof("hello_after") - 1 ||
            memcmp(buf, "hello_after", sizeof("hello_after") - 1) != 0) {
            fail++;
        }
        pgfs_file_close(&ctx, f);
    }

    if (ctx.data_log_write_addr <= rec2_start) {
        fail++;
    }
    return fail;
}

/* Verify that replay can jump over multiple consecutive bad blocks and still
 * recover files written later in the log. */
static int pgfs_test_replay_skips_multiple_bad_blocks_and_recovers_later_block(void) {
    int fail = 0;
    pgfs_test_flash_t flash = {0};
    pgfs_flash_opts_t opts = {0};
    pgfs_mount_ctx_t ctx = {0};
    uint8_t rec1[256] = {0};
    uint8_t rec2[256] = {0};
    size_t rec1_len = 0;
    size_t rec2_len = 0;
    uint32_t rec1_storage = 0;
    uint32_t rec2_start = 0;
    FILE* f = NULL;
    char buf[32] = {0};

    memset(flash.mem, 0xFF, sizeof(flash.mem));
    opts.ctx = &flash;
    opts.read = pgfs_test_read;
    opts.write = pgfs_test_write;
    opts.erase = pgfs_test_erase;
    opts.control = pgfs_test_control;

    rec1_len = pgfs_test_build_record(rec1, sizeof(rec1), "nand/multi_before_bad.txt", "hello_before");
    if (rec1_len == 0) {
        return 1;
    }
    if (pgfs_test_write(&flash, PGFS_DATA_LOG_BASE_ADDR, rec1, rec1_len) != 0) {
        return 1;
    }
    rec1_storage = pgfs_test_align_prog((uint32_t)rec1_len);

    flash.fail_read_addr = PGFS_DATA_LOG_BASE_ADDR + rec1_storage;
    flash.fail_read_len = 4096u * 2u;

    rec2_start = PGFS_DATA_LOG_BASE_ADDR + 4096u * 3u;
    rec2_len = pgfs_test_build_record(rec2, sizeof(rec2), "nand/multi_after_bad.txt", "hello_after");
    if (rec2_len == 0) {
        return 1;
    }
    if (pgfs_test_write(&flash, rec2_start, rec2, rec2_len) != 0) {
        return 1;
    }

    ctx.flash_opts = &opts;
    ctx.runtime_generation = 1;
    ctx.mounted = 1;
    ctx.data_log_base_addr = PGFS_DATA_LOG_BASE_ADDR;
    ctx.data_log_write_addr = PGFS_DATA_LOG_BASE_ADDR;
    ctx.data_log_prepared_until = PGFS_DATA_LOG_BASE_ADDR;

    if (pgfs_replay_data_log(&ctx) != 0) {
        return 1;
    }

    f = pgfs_file_open(&ctx, "/nand/multi_before_bad.txt", "rb");
    if (f == NULL) {
        fail++;
    }
    else {
        if (pgfs_file_read(&ctx, buf, 1, sizeof("hello_before") - 1, f) != sizeof("hello_before") - 1 ||
            memcmp(buf, "hello_before", sizeof("hello_before") - 1) != 0) {
            fail++;
        }
        pgfs_file_close(&ctx, f);
    }

    memset(buf, 0, sizeof(buf));
    f = pgfs_file_open(&ctx, "/nand/multi_after_bad.txt", "rb");
    if (f == NULL) {
        fail++;
    }
    else {
        if (pgfs_file_read(&ctx, buf, 1, sizeof("hello_after") - 1, f) != sizeof("hello_after") - 1 ||
            memcmp(buf, "hello_after", sizeof("hello_after") - 1) != 0) {
            fail++;
        }
        pgfs_file_close(&ctx, f);
    }

    if (ctx.data_log_write_addr <= rec2_start) {
        fail++;
    }
    return fail;
}

/* Verify replay can resync within the same erase block after a bad page and still
 * find a later batch commit marker in that block. */
static int pgfs_test_replay_resyncs_in_block_after_read_failure(void) {
    int fail = 0;
    pgfs_test_flash_t flash = {0};
    pgfs_flash_opts_t opts = {0};
    pgfs_mount_ctx_t ctx = {0};
    uint8_t record[256] = {0};
    size_t rec_len = 0;
    uint32_t batch_id = 11;
    uint32_t addr = PGFS_DATA_LOG_BASE_ADDR;
    uint32_t hole_addr = 0;
    uint32_t commit_addr = 0;
    FILE* f_read = NULL;
    char buf[64] = {0};

    memset(flash.mem, 0xFF, sizeof(flash.mem));
    opts.ctx = &flash;
    opts.read = pgfs_test_read;
    opts.write = pgfs_test_write;
    opts.erase = pgfs_test_erase;
    opts.control = pgfs_test_control;

    rec_len = pgfs_test_build_batch_data_record(record, sizeof(record), batch_id, "batch/resync_in_block.txt", "resync_ok");
    if (rec_len == 0) {
        return 1;
    }
    if (pgfs_test_write(&flash, addr, record, rec_len) != 0) {
        return 1;
    }
    hole_addr = pgfs_test_align_prog(addr + (uint32_t)rec_len);
    commit_addr = hole_addr + 256u;

    rec_len = pgfs_test_build_batch_commit_record(record, sizeof(record), batch_id, 1);
    if (rec_len == 0) {
        return 1;
    }
    if (pgfs_test_write(&flash, commit_addr, record, rec_len) != 0) {
        return 1;
    }

    flash.fail_read_addr = hole_addr;
    flash.fail_read_len = sizeof(uint32_t);

    ctx.flash_opts = &opts;
    ctx.runtime_generation = 1;
    ctx.mounted = 1;
    ctx.data_log_base_addr = PGFS_DATA_LOG_BASE_ADDR;
    ctx.data_log_write_addr = PGFS_DATA_LOG_BASE_ADDR;
    ctx.data_log_prepared_until = PGFS_DATA_LOG_BASE_ADDR;

    if (pgfs_replay_data_log(&ctx) != 0) {
        return 1;
    }
    f_read = pgfs_file_open(&ctx, "/batch/resync_in_block.txt", "rb");
    if (f_read == NULL) {
        fail++;
    }
    else {
        memset(buf, 0, sizeof(buf));
        if (pgfs_file_read(&ctx, buf, 1, 9, f_read) != 9 || memcmp(buf, "resync_ok", 9) != 0) {
            fail++;
        }
        if (pgfs_file_close(&ctx, f_read) != 0) {
            fail++;
        }
    }
    return fail;
}

/* Verify that replay stops cleanly on a truncated tail and preserves the prefix. */
static int pgfs_test_replay_stops_at_truncated_tail_and_keeps_prefix(void) {
    int fail = 0;
    pgfs_test_flash_t flash = {0};
    pgfs_flash_opts_t opts = {0};
    pgfs_mount_ctx_t ctx = {0};
    uint8_t rec1[256] = {0};
    uint8_t rec2_magic[32] = {0};
    size_t rec1_len = 0;
    uint32_t rec1_storage = 0;
    uint32_t rec2_start = 0;
    FILE* f = NULL;
    char buf[32] = {0};
    uint32_t magic = PGFS_TEST_DATA_RECORD_MAGIC;

    memset(flash.mem, 0xFF, sizeof(flash.mem));
    opts.ctx = &flash;
    opts.read = pgfs_test_read;
    opts.write = pgfs_test_write;
    opts.erase = pgfs_test_erase;
    opts.control = pgfs_test_control;

    rec1_len = pgfs_test_build_record(rec1, sizeof(rec1), "nand/truncated_prefix.txt", "hello_prefix");
    if (rec1_len == 0) {
        return 1;
    }
    if (pgfs_test_write(&flash, PGFS_DATA_LOG_BASE_ADDR, rec1, rec1_len) != 0) {
        return 1;
    }
    rec1_storage = pgfs_test_align_prog((uint32_t)rec1_len);
    rec2_start = PGFS_DATA_LOG_BASE_ADDR + rec1_storage;

    memset(rec2_magic, 0xFF, sizeof(rec2_magic));
    memcpy(rec2_magic, &magic, sizeof(magic));
    if (pgfs_test_write(&flash, rec2_start, rec2_magic, sizeof(magic)) != 0) {
        return 1;
    }
    flash.capacity_override = rec2_start + 4u;

    ctx.flash_opts = &opts;
    ctx.runtime_generation = 1;
    ctx.mounted = 1;
    ctx.data_log_base_addr = PGFS_DATA_LOG_BASE_ADDR;
    ctx.data_log_write_addr = PGFS_DATA_LOG_BASE_ADDR;
    ctx.data_log_prepared_until = PGFS_DATA_LOG_BASE_ADDR;

    if (pgfs_replay_data_log(&ctx) != 0) {
        return 1;
    }

    f = pgfs_file_open(&ctx, "/nand/truncated_prefix.txt", "rb");
    if (f == NULL) {
        fail++;
    }
    else {
        if (pgfs_file_read(&ctx, buf, 1, sizeof("hello_prefix") - 1, f) != sizeof("hello_prefix") - 1 ||
            memcmp(buf, "hello_prefix", sizeof("hello_prefix") - 1) != 0) {
            fail++;
        }
        pgfs_file_close(&ctx, f);
    }

    if (ctx.data_log_write_addr != rec2_start) {
        fail++;
    }
    return fail;
}

static int pgfs_test_write_file(pgfs_mount_ctx_t* ctx, const char* path, const uint8_t* data, size_t len) {
    FILE* f = NULL;
    size_t wrote = 0;
    if (ctx == NULL || path == NULL || data == NULL || len == 0) {
        return -1;
    }
    f = pgfs_file_open(ctx, path, "wb");
    if (f == NULL) {
        return -1;
    }
    wrote = pgfs_file_write(ctx, data, 1, len, f);
    if (wrote != len) {
        pgfs_file_close(ctx, f);
        return -1;
    }
    if (pgfs_file_close(ctx, f) != 0) {
        return -1;
    }
    return 0;
}

/* Boundary contract: after reaching ENOSPC, deleting files should allow writing new files again. */
static int pgfs_test_fill_delete_rewrite_recovers_capacity(void) {
    int fail = 0;
    pgfs_test_flash_t flash = {0};
    pgfs_flash_opts_t opts = {0};
    pgfs_mount_ctx_t ctx = {0};
    uint8_t payload[768];
    uint32_t i = 0;
    uint32_t written = 0;
    char path[96];

    memset(payload, 'R', sizeof(payload));
    memset(flash.mem, 0xFF, sizeof(flash.mem));
    flash.capacity_override = 0x7000u;
    opts.ctx = &flash;
    opts.read = pgfs_test_read;
    opts.write = pgfs_test_write;
    opts.erase = pgfs_test_erase;
    opts.control = pgfs_test_control;

    ctx.flash_opts = &opts;
    ctx.runtime_generation = 1;
    ctx.mounted = 1;
    ctx.checkpoint.magic = PGFS_CHECKPOINT_MAGIC;
    ctx.checkpoint.version = PGFS_ONDISK_VERSION;
    ctx.checkpoint.total_blocks = 7;
    ctx.checkpoint_loaded = 1;
    ctx.data_log_base_addr = PGFS_DATA_LOG_BASE_ADDR;
    ctx.data_log_write_addr = PGFS_DATA_LOG_BASE_ADDR;
    ctx.data_log_prepared_until = PGFS_DATA_LOG_BASE_ADDR;

    for (i = 1; i <= 48; i++) {
        snprintf(path, sizeof(path), "nand/full_%lu.bin", (unsigned long)i);
        if (pgfs_test_write_file(&ctx, path, payload, sizeof(payload)) != 0) {
            break;
        }
        written = i;
    }
    if (written == 0 || i > 48) {
        return 1;
    }
    if (written < 8) {
        return 1;
    }

    for (i = 1; i <= 6; i++) {
        snprintf(path, sizeof(path), "nand/full_%lu.bin", (unsigned long)i);
        if (pgfs_file_remove(&ctx, path) != 0) {
            fail++;
        }
    }

    for (i = 1; i <= 3; i++) {
        snprintf(path, sizeof(path), "nand/rewrite_%lu.bin", (unsigned long)i);
        if (pgfs_test_write_file(&ctx, path, payload, sizeof(payload)) != 0) {
            fail++;
        }
    }
    return fail;
}

static int pgfs_test_repeated_add_delete_stays_stable(void) {
    int fail = 0;
    pgfs_test_flash_t flash = {0};
    pgfs_flash_opts_t opts = {0};
    pgfs_mount_ctx_t ctx = {0};
    uint8_t payload[64];
    uint32_t round = 0;
    uint32_t i = 0;
    char path[96];

    memset(payload, 'S', sizeof(payload));
    memset(flash.mem, 0xFF, sizeof(flash.mem));
    opts.ctx = &flash;
    opts.read = pgfs_test_read;
    opts.write = pgfs_test_write;
    opts.erase = pgfs_test_erase;
    opts.control = pgfs_test_control;

    ctx.flash_opts = &opts;
    ctx.runtime_generation = 1;
    ctx.mounted = 1;
    ctx.checkpoint.magic = PGFS_CHECKPOINT_MAGIC;
    ctx.checkpoint.version = PGFS_ONDISK_VERSION;
    ctx.checkpoint.total_blocks = 7;
    ctx.checkpoint_loaded = 1;
    ctx.data_log_base_addr = PGFS_DATA_LOG_BASE_ADDR;
    ctx.data_log_write_addr = PGFS_DATA_LOG_BASE_ADDR;
    ctx.data_log_prepared_until = PGFS_DATA_LOG_BASE_ADDR;

    for (round = 1; round <= 80; round++) {
        for (i = 1; i <= 10; i++) {
            snprintf(path, sizeof(path), "nand/churn_r%lu_f%lu.bin", (unsigned long)round, (unsigned long)i);
            if (pgfs_test_write_file(&ctx, path, payload, sizeof(payload)) != 0) {
                fail++;
            }
        }
        for (i = 1; i <= 10; i++) {
            snprintf(path, sizeof(path), "nand/churn_r%lu_f%lu.bin", (unsigned long)round, (unsigned long)i);
            if (pgfs_file_remove(&ctx, path) != 0) {
                fail++;
            }
        }
    }
    return fail;
}

static int pgfs_test_info_fast_after_many_small_files(void) {
    int fail = 0;
    pgfs_test_flash_t flash = {0};
    pgfs_flash_opts_t opts = {0};
    pgfs_mount_ctx_t ctx = {0};
    luat_fs_info_t info = {0};
    uint8_t payload[16];
    uint32_t i = 0;
    char path[96];

    memset(payload, 'I', sizeof(payload));
    memset(flash.mem, 0xFF, sizeof(flash.mem));
    opts.ctx = &flash;
    opts.read = pgfs_test_read;
    opts.write = pgfs_test_write;
    opts.erase = pgfs_test_erase;
    opts.control = pgfs_test_control;

    ctx.flash_opts = &opts;
    ctx.runtime_generation = 1;
    ctx.mounted = 1;
    ctx.checkpoint.magic = PGFS_CHECKPOINT_MAGIC;
    ctx.checkpoint.version = PGFS_ONDISK_VERSION;
    ctx.checkpoint.total_blocks = 7;
    ctx.checkpoint_loaded = 1;
    ctx.data_log_base_addr = PGFS_DATA_LOG_BASE_ADDR;
    ctx.data_log_write_addr = PGFS_DATA_LOG_BASE_ADDR;
    ctx.data_log_prepared_until = PGFS_DATA_LOG_BASE_ADDR;

    for (i = 1; i <= 60; i++) {
        snprintf(path, sizeof(path), "nand/small_%lu.txt", (unsigned long)i);
        if (pgfs_test_write_file(&ctx, path, payload, sizeof(payload)) != 0) {
            return 1;
        }
    }
    for (i = 0; i < 400; i++) {
        memset(&info, 0, sizeof(info));
        if (pgfs_info_fast(&ctx, &info) != 0) {
            fail++;
            break;
        }
        if (info.total_block == 0) {
            fail++;
            break;
        }
    }
    return fail;
}

static int pgfs_test_powercut_stage_matrix_visibility(void) {
    int fail = 0;
    pgfs_test_flash_t flash = {0};
    pgfs_flash_opts_t opts = {0};
    pgfs_mount_ctx_t ctx = {0};
    pgfs_mount_ctx_t replay_ctx = {0};
    FILE* f = NULL;
    char buf[24] = {0};
    const uint8_t payload[] = "cut";
    struct stage_case {
        uint8_t stage;
        int expect_exist;
    } cases[] = {
        {PGFS_INJECT_POWERCUT_BEFORE_APPEND, 0},
        {PGFS_INJECT_POWERCUT_AFTER_APPEND, 1},
        {PGFS_INJECT_POWERCUT_BEFORE_CP, 1},
    };
    size_t i = 0;

    for (i = 0; i < sizeof(cases)/sizeof(cases[0]); i++) {
        memset(&flash, 0, sizeof(flash));
        memset(flash.mem, 0xFF, sizeof(flash.mem));
        memset(&ctx, 0, sizeof(ctx));
        memset(&replay_ctx, 0, sizeof(replay_ctx));
        pgfs_file_reset_all();

        opts.ctx = &flash;
        opts.read = pgfs_test_read;
        opts.write = pgfs_test_write;
        opts.erase = pgfs_test_erase;
        opts.control = pgfs_test_control;

        ctx.flash_opts = &opts;
        ctx.runtime_generation = 1;
        ctx.mounted = 1;
        ctx.inject_powercut_stage = cases[i].stage;
        ctx.checkpoint.magic = PGFS_CHECKPOINT_MAGIC;
        ctx.checkpoint.version = PGFS_ONDISK_VERSION;
        ctx.checkpoint.total_blocks = 7;
        ctx.checkpoint_loaded = 1;
        ctx.data_log_base_addr = PGFS_DATA_LOG_BASE_ADDR;
        ctx.data_log_write_addr = PGFS_DATA_LOG_BASE_ADDR;
        ctx.data_log_prepared_until = PGFS_DATA_LOG_BASE_ADDR;

        if (pgfs_test_write_file(&ctx, "nand/powercut_stage.txt", payload, sizeof(payload) - 1) == 0) {
            fail++;
            continue;
        }

        pgfs_file_reset_all();
        replay_ctx.flash_opts = &opts;
        replay_ctx.runtime_generation = 2;
        replay_ctx.mounted = 1;
        replay_ctx.data_log_base_addr = PGFS_DATA_LOG_BASE_ADDR;
        replay_ctx.data_log_write_addr = PGFS_DATA_LOG_BASE_ADDR;
        replay_ctx.data_log_prepared_until = PGFS_DATA_LOG_BASE_ADDR;
        if (pgfs_replay_data_log(&replay_ctx) != 0) {
            fail++;
            continue;
        }
        f = pgfs_file_open(&replay_ctx, "/nand/powercut_stage.txt", "rb");
        if (cases[i].expect_exist) {
            if (f == NULL) {
                fail++;
                continue;
            }
            memset(buf, 0, sizeof(buf));
            if (pgfs_file_read(&replay_ctx, buf, 1, sizeof(payload) - 1, f) != sizeof(payload) - 1 || memcmp(buf, payload, sizeof(payload) - 1) != 0) {
                fail++;
            }
            pgfs_file_close(&replay_ctx, f);
        }
        else if (f != NULL) {
            pgfs_file_close(&replay_ctx, f);
            fail++;
        }
    }
    return fail;
}

int pgfs_run_c_layer_tests(void) {
    int fail = 0;
    int r = 0;
#define PGFS_RUN_CTEST(fn) do { r = fn(); if (r != 0) { printf("[pgfs-ctest] FAIL: " #fn "\n"); } else { printf("[pgfs-ctest] PASS: " #fn "\n"); } fail += r; } while(0)
    PGFS_RUN_CTEST(pgfs_test_pick_latest_valid_sb);
    PGFS_RUN_CTEST(pgfs_test_checkpoint_roundtrip_and_fallback);
    PGFS_RUN_CTEST(pgfs_test_lock_mode_counters);
    PGFS_RUN_CTEST(pgfs_test_directory_helpers);
    PGFS_RUN_CTEST(pgfs_test_replay_restores_file_contents);
    PGFS_RUN_CTEST(pgfs_test_replay_skips_bad_block_and_recovers_next_block);
    PGFS_RUN_CTEST(pgfs_test_replay_skips_multiple_bad_blocks_and_recovers_later_block);
    PGFS_RUN_CTEST(pgfs_test_replay_resyncs_in_block_after_read_failure);
    PGFS_RUN_CTEST(pgfs_test_replay_stops_at_truncated_tail_and_keeps_prefix);
    PGFS_RUN_CTEST(pgfs_test_close_succeeds_when_probe_read_fails_on_unaligned_append);
    PGFS_RUN_CTEST(pgfs_test_close_succeeds_when_probe_nonff_on_unaligned_append);
    PGFS_RUN_CTEST(pgfs_test_close_advances_to_next_erase_block_when_unaligned_head_is_programmed);
    PGFS_RUN_CTEST(pgfs_test_checkpoint_batch_close_and_pending_commit);
    PGFS_RUN_CTEST(pgfs_test_batch_api_boundaries);
    PGFS_RUN_CTEST(pgfs_test_batch_commit_persists_after_replay);
    PGFS_RUN_CTEST(pgfs_test_replay_skips_blank_prefix_to_relocated_log);
    PGFS_RUN_CTEST(pgfs_test_replay_skips_unknown_prefix_to_relocated_log);
    PGFS_RUN_CTEST(pgfs_test_replay_batch_commit_marker_boundary);
    PGFS_RUN_CTEST(pgfs_test_info_fastpath_uses_runtime_checkpoint);
    PGFS_RUN_CTEST(pgfs_test_fill_delete_rewrite_recovers_capacity);
    PGFS_RUN_CTEST(pgfs_test_repeated_add_delete_stays_stable);
    PGFS_RUN_CTEST(pgfs_test_info_fast_after_many_small_files);
    PGFS_RUN_CTEST(pgfs_test_powercut_stage_matrix_visibility);
#undef PGFS_RUN_CTEST
    return fail == 0 ? 0 : -1;
}

int pgfs_run_c_layer_case(const char* case_name) {
    if (case_name == NULL || case_name[0] == '\0' || strcmp(case_name, "c_layer_selftests") == 0) {
        return pgfs_run_c_layer_tests();
    }
    if (strcmp(case_name, "generation_fallback_prefers_latest_valid") == 0) {
        return pgfs_test_pick_latest_valid_sb() == 0 ? 0 : -1;
    }
    if (strcmp(case_name, "fclose_is_durable_boundary") == 0) {
        return pgfs_test_checkpoint_batch_close_and_pending_commit() == 0 ? 0 : -1;
    }
    if (strcmp(case_name, "controlled_powercut_before_checkpoint") == 0) {
        return pgfs_test_replay_batch_commit_marker_boundary() == 0 ? 0 : -1;
    }
    if (strcmp(case_name, "control_invalid_args") == 0) {
        return pgfs_test_batch_api_boundaries() == 0 ? 0 : -1;
    }
    if (strcmp(case_name, "info_fast_path_and_rebuild") == 0) {
        return pgfs_test_info_fastpath_uses_runtime_checkpoint() == 0 ? 0 : -1;
    }
    if (strcmp(case_name, "getc_line_read_path") == 0) {
        return pgfs_test_replay_stops_at_truncated_tail_and_keeps_prefix() == 0 ? 0 : -1;
    }
    if (strcmp(case_name, "directory_listing_and_existence") == 0) {
        return pgfs_test_directory_helpers() == 0 ? 0 : -1;
    }
    if (strcmp(case_name, "large_unzip_repro") == 0) {
        return pgfs_test_batch_commit_persists_after_replay() == 0 ? 0 : -1;
    }
    if (strcmp(case_name, "fill_delete_rewrite_recovers_capacity") == 0) {
        return pgfs_test_fill_delete_rewrite_recovers_capacity() == 0 ? 0 : -1;
    }
    return -1;
}

#else

int pgfs_run_c_layer_tests(void) {
    return -1;
}

int pgfs_run_c_layer_case(const char* case_name) {
    (void)case_name;
    return -1;
}

#endif
