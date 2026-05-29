
#include "luat_base.h"
#include "luat_fs.h"
#include "luat_mem.h"
#include "luat_mcu.h"

#define LUAT_LOG_TAG "vfs.lfs2_nand"
#include "luat_log.h"

#ifdef LUAT_USE_LITTLE_FLASH

#ifdef LUAT_USE_FS_VFS
#include "luat_lfs2.h"
#include "little_flash.h"

#ifndef LUAT_LFS2_IO_TRACE_LOG
#define LUAT_LFS2_IO_TRACE_LOG 0
#endif

#ifndef LUAT_LFS2_IO_PROFILE_LOG
#define LUAT_LFS2_IO_PROFILE_LOG 0
#endif

#define LFS2_IO_TRACE_LOG(...)   do { if (LUAT_LFS2_IO_TRACE_LOG) { LLOGD(__VA_ARGS__); } } while (0)
#define LFS2_IO_PROFILE_LOG(...) do { if (LUAT_LFS2_IO_PROFILE_LOG) { LLOGD(__VA_ARGS__); } } while (0)

static size_t lf_offset = 0;
#define LFS2_IO_SLOW_US (5000u)

typedef struct {
    uint64_t calls;
    uint64_t bytes;
    uint64_t total_us;
    uint64_t max_us;
    uint64_t slow_calls;
} luat_lfs2_io_stat_t;

enum {
    LUAT_LFS2_IO_READ = 0,
    LUAT_LFS2_IO_PROG,
    LUAT_LFS2_IO_ERASE,
    LUAT_LFS2_IO_SYNC,
    LUAT_LFS2_IO_MAX
};

static luat_lfs2_io_stat_t g_lfs2_io_stats[LUAT_LFS2_IO_MAX];

static uint64_t luat_lfs2_now_us(void) {
    uint64_t tick = luat_mcu_tick64();
    uint32_t tick_per_us = luat_mcu_us_period();
    if (tick_per_us == 0) {
        tick_per_us = 1;
    }
    return tick / tick_per_us;
}

static void luat_lfs2_io_stat_record(uint32_t op, size_t bytes, uint64_t cost_us) {
    luat_lfs2_io_stat_t* stat = NULL;
    if (op >= LUAT_LFS2_IO_MAX) {
        return;
    }
    stat = &g_lfs2_io_stats[op];
    stat->calls++;
    stat->bytes += bytes;
    stat->total_us += cost_us;
    if (cost_us > stat->max_us) {
        stat->max_us = cost_us;
    }
    if (cost_us >= LFS2_IO_SLOW_US) {
        stat->slow_calls++;
    }
}

static void luat_lfs2_trace_io(uint32_t op, luat_lfs2_block_t block, luat_lfs2_off_t off, size_t bytes, int ret, uint64_t cost_us) {
    static const char* op_name[LUAT_LFS2_IO_MAX] = {"read", "prog", "erase", "sync"};
    if (op >= LUAT_LFS2_IO_MAX) {
        return;
    }
    if (op == LUAT_LFS2_IO_ERASE || cost_us >= LFS2_IO_SLOW_US) {
        LFS2_IO_TRACE_LOG("LFS2_TRACE_IO op=%s block=%u off=%u bytes=%u ret=%d cost_us=%llu",
                          op_name[op],
                          (unsigned int)block,
                          (unsigned int)off,
                          (unsigned int)bytes,
                          ret,
                          (unsigned long long)cost_us);
    }
}

void luat_lfs2n_block_profile_reset(void) {
    memset(g_lfs2_io_stats, 0, sizeof(g_lfs2_io_stats));
}

void luat_lfs2n_block_profile_log(const char* prefix) {
    const char* p = prefix ? prefix : "LFS2_IO_SUMMARY";
    static const char* op_name[LUAT_LFS2_IO_MAX] = {"read", "prog", "erase", "sync"};
    uint32_t i = 0;
    for (; i < LUAT_LFS2_IO_MAX; i++) {
        const luat_lfs2_io_stat_t* st = &g_lfs2_io_stats[i];
        if (st->calls == 0) {
            continue;
        }
        LFS2_IO_PROFILE_LOG("%s op=%s calls=%llu bytes=%llu total_us=%llu max_us=%llu slow_calls=%llu",
                            p, op_name[i],
                            (unsigned long long)st->calls,
                            (unsigned long long)st->bytes,
                            (unsigned long long)st->total_us,
                            (unsigned long long)st->max_us,
                            (unsigned long long)st->slow_calls);
    }
}

int luat_lfs2n_block_profile_read_snapshot(uint64_t* calls, uint64_t* bytes, uint64_t* total_us) {
    const luat_lfs2_io_stat_t* st = &g_lfs2_io_stats[LUAT_LFS2_IO_READ];
    if (calls) {
        *calls = st->calls;
    }
    if (bytes) {
        *bytes = st->bytes;
    }
    if (total_us) {
        *total_us = st->total_us;
    }
    return 0;
}

int luat_lfs2n_block_profile_read_snapshot_ex(uint64_t* read_calls, uint64_t* read_bytes, uint64_t* read_us,
                                              uint64_t* prog_calls, uint64_t* prog_bytes, uint64_t* prog_us,
                                              uint64_t* erase_calls, uint64_t* erase_bytes, uint64_t* erase_us,
                                              uint64_t* sync_calls, uint64_t* sync_bytes, uint64_t* sync_us) {
    if (read_calls) *read_calls = g_lfs2_io_stats[LUAT_LFS2_IO_READ].calls;
    if (read_bytes) *read_bytes = g_lfs2_io_stats[LUAT_LFS2_IO_READ].bytes;
    if (read_us) *read_us = g_lfs2_io_stats[LUAT_LFS2_IO_READ].total_us;
    if (prog_calls) *prog_calls = g_lfs2_io_stats[LUAT_LFS2_IO_PROG].calls;
    if (prog_bytes) *prog_bytes = g_lfs2_io_stats[LUAT_LFS2_IO_PROG].bytes;
    if (prog_us) *prog_us = g_lfs2_io_stats[LUAT_LFS2_IO_PROG].total_us;
    if (erase_calls) *erase_calls = g_lfs2_io_stats[LUAT_LFS2_IO_ERASE].calls;
    if (erase_bytes) *erase_bytes = g_lfs2_io_stats[LUAT_LFS2_IO_ERASE].bytes;
    if (erase_us) *erase_us = g_lfs2_io_stats[LUAT_LFS2_IO_ERASE].total_us;
    if (sync_calls) *sync_calls = g_lfs2_io_stats[LUAT_LFS2_IO_SYNC].calls;
    if (sync_bytes) *sync_bytes = g_lfs2_io_stats[LUAT_LFS2_IO_SYNC].bytes;
    if (sync_us) *sync_us = g_lfs2_io_stats[LUAT_LFS2_IO_SYNC].total_us;
    return 0;
}

// Read a block
static int lf_block_device_read(const struct luat_lfs2_config *cfg, luat_lfs2_block_t block, luat_lfs2_off_t off, void *buffer, luat_lfs2_size_t size) {
    little_flash_t* flash = (little_flash_t*)cfg->context;
    int ret = 0;
    uint64_t start_us = luat_lfs2_now_us();
    uint64_t cost_us = 0;
    // LLOGD("lf_block_device_read block:%d off:%d size:%d", block, off, size);
    ret = little_flash_read(flash, lf_offset + block * flash->chip_info.erase_size + off, buffer, size);
    cost_us = luat_lfs2_now_us() - start_us;
    luat_lfs2_io_stat_record(LUAT_LFS2_IO_READ, (size_t)size, cost_us);
    luat_lfs2_trace_io(LUAT_LFS2_IO_READ, block, off, (size_t)size, ret, cost_us);
    return ret;
    // LLOGD("lf_block_device_read ret:%d", ret);
    // return LFS_ERR_OK;
}

static int lf_block_device_prog(const struct luat_lfs2_config *cfg, luat_lfs2_block_t block, luat_lfs2_off_t off, const void *buffer, luat_lfs2_size_t size) {
    little_flash_t* flash = (little_flash_t*)cfg->context;
    int ret = 0;
    uint64_t start_us = luat_lfs2_now_us();
    uint64_t cost_us = 0;
    // LLOGD("lf_block_device_prog block:%d off:%d size:%d", block, off, size);
    ret = little_flash_write(flash, lf_offset + block * flash->chip_info.erase_size + off, buffer, size);
    cost_us = luat_lfs2_now_us() - start_us;
    luat_lfs2_io_stat_record(LUAT_LFS2_IO_PROG, (size_t)size, cost_us);
    luat_lfs2_trace_io(LUAT_LFS2_IO_PROG, block, off, (size_t)size, ret, cost_us);
    return ret;
    // LLOGD("lf_block_device_prog ret:%d", ret);
    // return LFS_ERR_OK;
}

static int lf_block_device_erase(const struct luat_lfs2_config *cfg, luat_lfs2_block_t block) {
    little_flash_t* flash = (little_flash_t*)cfg->context;
    int ret = 0;
    uint64_t start_us = luat_lfs2_now_us();
    uint64_t cost_us = 0;
    ret = little_flash_erase(flash, lf_offset + block * flash->chip_info.erase_size, flash->chip_info.erase_size);
    cost_us = luat_lfs2_now_us() - start_us;
    luat_lfs2_io_stat_record(LUAT_LFS2_IO_ERASE, (size_t)flash->chip_info.erase_size, cost_us);
    luat_lfs2_trace_io(LUAT_LFS2_IO_ERASE, block, 0, (size_t)flash->chip_info.erase_size, ret, cost_us);
    return ret;
    // LLOGD("lf_block_device_erase ret:%d block:%d", ret, block);
    // return LFS_ERR_OK;
}

static int lf_block_device_sync(const struct luat_lfs2_config *cfg) {
    uint64_t start_us = luat_lfs2_now_us();
    uint64_t cost_us = 0;
    (void)cfg;
    cost_us = luat_lfs2_now_us() - start_us;
    luat_lfs2_io_stat_record(LUAT_LFS2_IO_SYNC, 0, cost_us);
    luat_lfs2_trace_io(LUAT_LFS2_IO_SYNC, 0, 0, 0, 0, cost_us);
    return LFS_ERR_OK;
}

#define LFS_LOOKAHEAD_MIN_BYTES (32u)
#define LFS_LOOKAHEAD_MAX_BYTES (128u)
#define LFS_CACHE_MIN_MULTIPLIER (2u)
#define LFS_CACHE_MAX_BYTES (8u * 1024u)
typedef struct LFS2 {
    luat_lfs2_t lfs;
    struct luat_lfs2_config cfg;
    uint8_t lookahead_buffer[LFS_LOOKAHEAD_MAX_BYTES];
    uint8_t* read_buffer;
    uint8_t* prog_buffer;
}LFS2_t;

static luat_lfs2_size_t luat_lfs2_align_up(luat_lfs2_size_t value, luat_lfs2_size_t unit) {
    if (unit == 0) {
        return value;
    }
    return ((value + unit - 1) / unit) * unit;
}

static luat_lfs2_size_t luat_lfs2_pick_cache_size(const little_flash_t* flash) {
    luat_lfs2_size_t prog = flash->chip_info.prog_size;
    luat_lfs2_size_t block = flash->chip_info.erase_size;
    luat_lfs2_size_t target;
    if (prog == 0) {
        return 0;
    }
    target = prog * LFS_CACHE_MIN_MULTIPLIER;
    if (target < prog) {
        target = prog;
    }
    if (target > LFS_CACHE_MAX_BYTES) {
        target = LFS_CACHE_MAX_BYTES;
    }
    if (block > 0 && target > block) {
        target = block;
    }
    target = luat_lfs2_align_up(target, prog);
    if (block > 0 && target > block) {
        target = block - (block % prog);
        if (target == 0) {
            target = prog;
        }
    }
    return target;
}

static luat_lfs2_size_t luat_lfs2_pick_lookahead_size(luat_lfs2_size_t block_count) {
    luat_lfs2_size_t target = block_count / 8;
    if ((block_count % 8) != 0) {
        target++;
    }
    if (target < LFS_LOOKAHEAD_MIN_BYTES) {
        target = LFS_LOOKAHEAD_MIN_BYTES;
    }
    if (target > LFS_LOOKAHEAD_MAX_BYTES) {
        target = LFS_LOOKAHEAD_MAX_BYTES;
    }
    target &= ~((luat_lfs2_size_t)7);
    if (target == 0) {
        target = 8;
    }
    return target;
}

luat_lfs2_t* luat_lfs2_nand_flash_lfs_lf(little_flash_t* flash, size_t offset, size_t maxsize) {
    if (flash==NULL){
        LLOGE("flash is null");
        return NULL;
    }
    LFS2_t *_lfs = luat_heap_malloc(sizeof(LFS2_t));
    if (_lfs == NULL)
        return NULL;
    memset(_lfs, 0, sizeof(LFS2_t));

    lf_offset = offset;
    luat_lfs2_t *lfs = &_lfs->lfs;
    struct luat_lfs2_config *luat_lfs2_cfg = &_lfs->cfg;

    luat_lfs2_cfg->context = flash,
    // block device operations
    luat_lfs2_cfg->read = lf_block_device_read;
    luat_lfs2_cfg->prog = lf_block_device_prog;
    luat_lfs2_cfg->erase = lf_block_device_erase;
    luat_lfs2_cfg->sync = lf_block_device_sync;

    // block device configuration
    luat_lfs2_cfg->read_size = flash->chip_info.read_size;
    luat_lfs2_cfg->prog_size = flash->chip_info.prog_size;
    luat_lfs2_cfg->block_size = flash->chip_info.erase_size;
    luat_lfs2_cfg->block_count = (maxsize > 0 ? maxsize : (flash->chip_info.capacity - offset)) / flash->chip_info.erase_size;
    luat_lfs2_cfg->block_cycles = 500;
    luat_lfs2_cfg->cache_size = luat_lfs2_pick_cache_size(flash);
    luat_lfs2_cfg->lookahead_size = luat_lfs2_pick_lookahead_size(luat_lfs2_cfg->block_count);

    _lfs->read_buffer = luat_heap_malloc(luat_lfs2_cfg->cache_size);
    _lfs->prog_buffer = luat_heap_malloc(luat_lfs2_cfg->cache_size);
    if (_lfs->read_buffer == NULL || _lfs->prog_buffer == NULL) {
        goto fail;
    }

    luat_lfs2_cfg->read_buffer = _lfs->read_buffer;
    luat_lfs2_cfg->prog_buffer = _lfs->prog_buffer;
    luat_lfs2_cfg->lookahead_buffer = _lfs->lookahead_buffer;
    luat_lfs2_cfg->name_max = 63;
    luat_lfs2_cfg->file_max = 0;
    luat_lfs2_cfg->attr_max = 0;

    // LLOGD("block_size %d", luat_lfs2_cfg->block_size);
    // LLOGD("block_count %d", luat_lfs2_cfg->block_count);
    // LLOGD("capacity %d", flash->chip_info.capacity);
    // LLOGD("erase_size %d", flash->chip_info.erase_size);

    // ------
    LFS2_IO_TRACE_LOG("flash_lfs_lf mount begin offset=%u maxsize=%u block_size=%u block_count=%u cache=%u lookahead=%u",
                      (unsigned int)offset, (unsigned int)maxsize,
                      (unsigned int)luat_lfs2_cfg->block_size, (unsigned int)luat_lfs2_cfg->block_count,
                      (unsigned int)luat_lfs2_cfg->cache_size, (unsigned int)luat_lfs2_cfg->lookahead_size);
    int err = luat_lfs2_mount(lfs, luat_lfs2_cfg);
    LFS2_IO_TRACE_LOG("luat_lfs2_mount %d",err);
    if (err)
    {
        err = luat_lfs2_format(lfs, luat_lfs2_cfg);
        LFS2_IO_TRACE_LOG("luat_lfs2_format %d",err);
        if(err) {
            LLOGE("lfsn format failed err=%d offset=%u maxsize=%u block_count=%u",
                  err, (unsigned int)offset, (unsigned int)maxsize, (unsigned int)luat_lfs2_cfg->block_count);
            goto fail;
        }
        err = luat_lfs2_mount(lfs, luat_lfs2_cfg);
        LFS2_IO_TRACE_LOG("luat_lfs2_mount %d",err);
        if(err) {
            LLOGE("lfsn remount failed err=%d offset=%u maxsize=%u block_count=%u",
                  err, (unsigned int)offset, (unsigned int)maxsize, (unsigned int)luat_lfs2_cfg->block_count);
            goto fail;
        }
    }
    return lfs;
fail :
    if (_lfs->read_buffer) {
        luat_heap_free(_lfs->read_buffer);
    }
    if (_lfs->prog_buffer) {
        luat_heap_free(_lfs->prog_buffer);
    }
    luat_heap_free(_lfs);
    return NULL;
    //------
}

#endif

#endif
