
#include "luat_base.h"
#include "luat_fs.h"
#include "luat_mem.h"

#define LUAT_LOG_TAG "little_flash"
#include "luat_log.h"

#ifdef LUAT_USE_LITTLE_FLASH

#ifdef LUAT_USE_FS_VFS
#include "lfs.h"
#include "little_flash.h"

static size_t lf_offset = 0;

// Read a block
static int lf_block_device_read(const struct lfs_config *cfg, lfs_block_t block, lfs_off_t off, void *buffer, lfs_size_t size) {
    little_flash_t* flash = (little_flash_t*)cfg->context;
    // LLOGD("lf_block_device_read block:%d off:%d size:%d", block, off, size);
    return little_flash_read(flash, lf_offset + block * flash->chip_info.erase_size + off, buffer, size);
    // LLOGD("lf_block_device_read ret:%d", ret);
    // return LFS_ERR_OK;
}

static int lf_block_device_prog(const struct lfs_config *cfg, lfs_block_t block, lfs_off_t off, const void *buffer, lfs_size_t size) {
    little_flash_t* flash = (little_flash_t*)cfg->context;
    // LLOGD("lf_block_device_prog block:%d off:%d size:%d", block, off, size);
    return little_flash_write(flash, lf_offset + block * flash->chip_info.erase_size + off, buffer, size);
    // LLOGD("lf_block_device_prog ret:%d", ret);
    // return LFS_ERR_OK;
}

static int lf_block_device_erase(const struct lfs_config *cfg, lfs_block_t block) {
    little_flash_t* flash = (little_flash_t*)cfg->context;
    return little_flash_erase(flash, lf_offset + block * flash->chip_info.erase_size, flash->chip_info.erase_size);
    // LLOGD("lf_block_device_erase ret:%d block:%d", ret, block);
    // return LFS_ERR_OK;
}

static int lf_block_device_sync(const struct lfs_config *cfg) {
    return LFS_ERR_OK;
}

#define LFS_LOOKAHEAD_MIN_BYTES (32u)
#define LFS_LOOKAHEAD_MAX_BYTES (128u)
#define LFS_CACHE_MIN_MULTIPLIER (2u)
#define LFS_CACHE_MAX_BYTES (8u * 1024u)
typedef struct LFS2 {
    lfs_t lfs;
    struct lfs_config cfg;
    uint8_t lookahead_buffer[LFS_LOOKAHEAD_MAX_BYTES];
    uint8_t* read_buffer;
    uint8_t* prog_buffer;
}LFS2_t;

static lfs_size_t luat_lfs2_align_up(lfs_size_t value, lfs_size_t unit) {
    if (unit == 0) {
        return value;
    }
    return ((value + unit - 1) / unit) * unit;
}

static lfs_size_t luat_lfs2_pick_cache_size(const little_flash_t* flash) {
    lfs_size_t prog = flash->chip_info.prog_size;
    lfs_size_t block = flash->chip_info.erase_size;
    lfs_size_t target;
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

static lfs_size_t luat_lfs2_pick_lookahead_size(lfs_size_t block_count) {
    lfs_size_t target = block_count / 8;
    if ((block_count % 8) != 0) {
        target++;
    }
    if (target < LFS_LOOKAHEAD_MIN_BYTES) {
        target = LFS_LOOKAHEAD_MIN_BYTES;
    }
    if (target > LFS_LOOKAHEAD_MAX_BYTES) {
        target = LFS_LOOKAHEAD_MAX_BYTES;
    }
    target &= ~((lfs_size_t)7);
    if (target == 0) {
        target = 8;
    }
    return target;
}

lfs_t* flash_lfs_lf(little_flash_t* flash, size_t offset, size_t maxsize) {
    if (flash==NULL){
        LLOGE("flash is null");
        return NULL;
    }
    LFS2_t *_lfs = luat_heap_malloc(sizeof(LFS2_t));
    if (_lfs == NULL)
        return NULL;
    memset(_lfs, 0, sizeof(LFS2_t));

    lf_offset = offset;
    lfs_t *lfs = &_lfs->lfs;
    struct lfs_config *lfs_cfg = &_lfs->cfg;

    lfs_cfg->context = flash,
    // block device operations
    lfs_cfg->read = lf_block_device_read;
    lfs_cfg->prog = lf_block_device_prog;
    lfs_cfg->erase = lf_block_device_erase;
    lfs_cfg->sync = lf_block_device_sync;

    // block device configuration
    lfs_cfg->read_size = flash->chip_info.read_size;
    lfs_cfg->prog_size = flash->chip_info.prog_size;
    lfs_cfg->block_size = flash->chip_info.erase_size;
    lfs_cfg->block_count = (maxsize > 0 ? maxsize : (flash->chip_info.capacity - offset)) / flash->chip_info.erase_size;
    lfs_cfg->block_cycles = 500;
    lfs_cfg->cache_size = luat_lfs2_pick_cache_size(flash);
    lfs_cfg->lookahead_size = luat_lfs2_pick_lookahead_size(lfs_cfg->block_count);

    _lfs->read_buffer = luat_heap_malloc(lfs_cfg->cache_size);
    _lfs->prog_buffer = luat_heap_malloc(lfs_cfg->cache_size);
    if (_lfs->read_buffer == NULL || _lfs->prog_buffer == NULL) {
        goto fail;
    }

    lfs_cfg->read_buffer = _lfs->read_buffer;
    lfs_cfg->prog_buffer = _lfs->prog_buffer;
    lfs_cfg->lookahead_buffer = _lfs->lookahead_buffer;
    lfs_cfg->name_max = 63;
    lfs_cfg->file_max = 0;
    lfs_cfg->attr_max = 0;

    // LLOGD("block_size %d", lfs_cfg->block_size);
    // LLOGD("block_count %d", lfs_cfg->block_count);
    // LLOGD("capacity %d", flash->chip_info.capacity);
    // LLOGD("erase_size %d", flash->chip_info.erase_size);

    // ------
    LLOGD("flash_lfs_lf mount begin offset=%u maxsize=%u block_size=%u block_count=%u cache=%u lookahead=%u",
          (unsigned int)offset, (unsigned int)maxsize,
          (unsigned int)lfs_cfg->block_size, (unsigned int)lfs_cfg->block_count,
          (unsigned int)lfs_cfg->cache_size, (unsigned int)lfs_cfg->lookahead_size);
    int err = lfs_mount(lfs, lfs_cfg);
    LLOGD("lfs_mount %d",err);
    if (err)
    {
        err = lfs_format(lfs, lfs_cfg);
        LLOGD("lfs_format %d",err);
        if(err)
            goto fail;
        err = lfs_mount(lfs, lfs_cfg);
        LLOGD("lfs_mount %d",err);
        if(err)
            goto fail;
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
