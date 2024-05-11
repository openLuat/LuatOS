
#include "luat_base.h"
#include "luat_fs.h"
#include "luat_mem.h"

#define LUAT_LOG_TAG "little_flash"
#include "luat_log.h"

#ifdef LUAT_USE_FS_VFS
#include "lfs.h"
#include "little_flash.h"

static size_t lf_offset = 0;

// Read a block
static int lf_block_device_read(const struct lfs_config *cfg, lfs_block_t block, lfs_off_t off, void *buffer, lfs_size_t size) {
    little_flash_t* flash = (little_flash_t*)cfg->context;
    // int ret = lf_read(flash, lf_offset + block * flash->chip.erase_gran + off, size, buffer);
    int ret = little_flash_read(flash, lf_offset + block * flash->chip_info.erase_size + off, buffer, size);
    // LUAT_DEBUG_PRINT("lf_block_device_read ret %d", ret);
    return ret;
}

static int lf_block_device_prog(const struct lfs_config *cfg, lfs_block_t block, lfs_off_t off, const void *buffer, lfs_size_t size) {
    little_flash_t* flash = (little_flash_t*)cfg->context;
    // int ret = lf_write(flash, lf_offset + block * flash->chip.erase_gran + off, size, buffer);
    int ret = little_flash_write(flash, lf_offset + block * flash->chip_info.erase_size + off, buffer, size);
    // LUAT_DEBUG_PRINT("lf_block_device_prog ret %d", ret);
    return ret;
}

static int lf_block_device_erase(const struct lfs_config *cfg, lfs_block_t block) {
    little_flash_t* flash = (little_flash_t*)cfg->context;
    // int ret = lf_erase(flash, lf_offset + block * flash->chip.erase_gran, flash->chip.erase_gran);
    int ret = little_flash_erase(flash, lf_offset + block * flash->chip_info.erase_size, flash->chip_info.erase_size);
    // LUAT_DEBUG_PRINT("lf_block_device_erase ret %d", ret);
    return ret;
}

static int lf_block_device_sync(const struct lfs_config *cfg) {
    return LFS_ERR_OK;
}

typedef struct LFS2 {
    lfs_t lfs;
    struct lfs_config cfg;
}LFS2_t;

lfs_t* flash_lfs_lf(little_flash_t* flash, size_t offset, size_t maxsize) {
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
    lfs_cfg->block_cycles = 400;
    lfs_cfg->cache_size = flash->chip_info.prog_size;
    lfs_cfg->lookahead_size = flash->chip_info.prog_size;

    lfs_cfg->name_max = 63;
    lfs_cfg->file_max = 0;
    lfs_cfg->attr_max = 0;

    // LLOGD("block_size %d", lfs_cfg->block_size);
    // LLOGD("block_count %d", lfs_cfg->block_count);
    // LLOGD("capacity %d", flash->chip.capacity);
    // LLOGD("erase_gran %d", flash->chip.erase_gran);

    // ------
    int err = lfs_mount(lfs, lfs_cfg);
    LLOGD("lfs_mount %d",err);
    if (err)
    {
        err = lfs_format(lfs, lfs_cfg);
        // LLOGD("lfs_format %d",err);
        if(err)
            goto fail;
        err = lfs_mount(lfs, lfs_cfg);
        LLOGD("lfs_mount %d",err);
        if(err)
            goto fail;
    }
    return lfs;
fail :
    luat_heap_free(_lfs);
    return NULL;
    //------
}

#endif


