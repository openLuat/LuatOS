
#include "luat_base.h"

#include "luat_sfd.h"
#include "luat_malloc.h"

#define LUAT_LOG_TAG "lfs"
#include "luat_log.h"

luat_sfd_lfs_t* sfd_lfs;

// Read a block
static int block_device_read(const struct lfs_config *cfg, lfs_block_t block,
        lfs_off_t off, void *buffer, lfs_size_t size) {
    sfd_drv_t* drv = cfg->context;
    int ret = luat_sfd_read(drv, buffer, block * LFS_BLOCK_DEVICE_ERASE_SIZE + off, size);
    // LLOGD("sfd read %d %d %d %d", block, off, size, ret);
    if (ret >= 0) {
        // LLOGD("block_device_read return LFS_ERR_OK");
        return LFS_ERR_OK;
    }
    // LLOGD("block_device_read return LFS_ERR_IO");
    return LFS_ERR_IO;
}

// Program a block
//
// The block must have previously been erased.
static int block_device_prog(const struct lfs_config *cfg, lfs_block_t block,
        lfs_off_t off, const void *buffer, lfs_size_t size) {
    sfd_drv_t* drv = cfg->context;
    int ret = luat_sfd_write(drv, buffer, block * LFS_BLOCK_DEVICE_ERASE_SIZE + off, size);
    // LLOGD("sfd write %d %d %d %d", block, off, size, ret);
    if (ret >= 0) {
        // LLOGD("block_device_prog return LFS_ERR_OK");
        return LFS_ERR_OK;
    }
    // LLOGD("block_device_prog return LFS_ERR_IO");
    return LFS_ERR_IO;
}

// Erase a block
//
// A block must be erased before being programmed. The
// state of an erased block is undefined.
static int block_device_erase(const struct lfs_config *cfg, lfs_block_t block) {
    sfd_drv_t* drv = cfg->context;
    int ret = luat_sfd_erase(drv, block * LFS_BLOCK_DEVICE_ERASE_SIZE, LFS_BLOCK_DEVICE_ERASE_SIZE);
    // LLOGD("sfd erase %d %d", block, ret);
    (void)ret;
    return 0;
}

// Sync the block device
static int block_device_sync(const struct lfs_config *cfg) {
    return 0;
}

int luat_sfd_lfs_init(sfd_drv_t *drv) {
    int ret = 0;
    if (sfd_lfs == NULL) {
        sfd_lfs = luat_heap_malloc(sizeof(luat_sfd_lfs_t));
        if (sfd_lfs == NULL) {
            LLOGE("out of memory when malloc sfd_lfs");
            return -1;
        }
        memset(sfd_lfs, 0, sizeof(luat_sfd_lfs_t));
        sfd_lfs->conf.read = block_device_read;
        sfd_lfs->conf.prog = block_device_prog;
        sfd_lfs->conf.erase = block_device_erase;
        sfd_lfs->conf.sync = block_device_sync;
        sfd_lfs->conf.attr_max = 0;
        sfd_lfs->conf.file_max = 4096;
        sfd_lfs->conf.block_count = (LFS_BLOCK_DEVICE_TOTOAL_SIZE) / LFS_BLOCK_DEVICE_ERASE_SIZE;
        sfd_lfs->conf.block_size = LFS_BLOCK_DEVICE_ERASE_SIZE;
        sfd_lfs->conf.block_cycles = 200;
        sfd_lfs->conf.name_max = 63;
        sfd_lfs->conf.read_size = LFS_BLOCK_DEVICE_CACHE_SIZE;
        sfd_lfs->conf.cache_size = LFS_BLOCK_DEVICE_CACHE_SIZE;
        sfd_lfs->conf.prog_size = LFS_BLOCK_DEVICE_PROG_SIZE;
        sfd_lfs->conf.cache_size = LFS_BLOCK_DEVICE_CACHE_SIZE;
        sfd_lfs->conf.lookahead_size = LFS_BLOCK_DEVICE_LOOK_AHEAD;
        sfd_lfs->conf.lookahead_buffer = sfd_lfs->lookahead_buffer;
        sfd_lfs->conf.prog_buffer = sfd_lfs->prog_buffer;
        sfd_lfs->conf.read_buffer = sfd_lfs->read_buffer;
        sfd_lfs->conf.context = drv;

        ret = lfs_mount(&sfd_lfs->lfs, &sfd_lfs->conf);
        if (ret != LFS_ERR_OK) {
            LLOGI("sfd_lfs mount ret %d, exec auto-format", ret);
            ret = lfs_format(&sfd_lfs->lfs, &sfd_lfs->conf);
            if (ret != LFS_ERR_OK) {
                luat_heap_free(sfd_lfs);
                sfd_lfs = NULL;
                LLOGE("sfd_lfs auto-format ret %d", ret);
                return ret;
            }
            ret = lfs_mount(&sfd_lfs->lfs, &sfd_lfs->conf);
            if (ret != LFS_ERR_OK) {
                luat_heap_free(sfd_lfs);
                sfd_lfs = NULL;
                LLOGE("sfd_lfs remount ret %d", ret);
                return ret;
            }
        }
        LLOGD("init ok");
    }
    return 0;
}
