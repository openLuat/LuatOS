#include "luat_base.h"
#include "luat_fskv.h"
#include "luat_malloc.h"
#include "luat_msgbus.h"
#include "luat_sfd.h"

#define LUAT_LOG_TAG "fskv"
#include "luat_log.h"

#include "lfs.h"

luat_fskv_t* fskv;

int sfd_onchip_init (void* userdata);
int sfd_onchip_status (void* userdata);
int sfd_onchip_read (void* userdata, char* buff, size_t offset, size_t len);
int sfd_onchip_write (void* userdata, const char* buff, size_t offset, size_t len);
int sfd_onchip_erase (void* userdata, size_t offset, size_t len);
int sfd_onchip_ioctl (void* userdata, size_t cmd, void* buff);

// Read a block
static int block_device_read(const struct lfs_config *cfg, lfs_block_t block,
        lfs_off_t off, void *buffer, lfs_size_t size) {
    int ret = sfd_onchip_read(NULL, buffer, block * LFS_BLOCK_DEVICE_ERASE_SIZE + off, size);
    // LLOGD("sfd read %d %d %d %d", block, off, size, ret);
    if (ret == size) {
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
    int ret = sfd_onchip_write(NULL, buffer, block * LFS_BLOCK_DEVICE_ERASE_SIZE + off, size);
    // LLOGD("sfd write %d %d %d %d", block, off, size, ret);
    if (ret == size) {
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
    int ret = sfd_onchip_erase(NULL, block * LFS_BLOCK_DEVICE_ERASE_SIZE, LFS_BLOCK_DEVICE_ERASE_SIZE);
    // LLOGD("sfd erase %d %d", block, ret);
    (void)ret;
    return 0;
}

// Sync the block device
static int block_device_sync(const struct lfs_config *cfg) {
    return 0;
}

int luat_fskv_init(void) {
    int ret = 0;
    if (fskv == NULL) {
        fskv = luat_heap_malloc(sizeof(luat_fskv_t));
        if (fskv == NULL) {
            LLOGE("out of memory when malloc fskv");
            return -1;
        }
        memset(fskv, 0, sizeof(luat_fskv_t));
        fskv->conf.read = block_device_read;
        fskv->conf.prog = block_device_prog;
        fskv->conf.erase = block_device_erase;
        fskv->conf.sync = block_device_sync;
        fskv->conf.attr_max = 0;
        fskv->conf.file_max = 4096;
        fskv->conf.block_count = (LFS_BLOCK_DEVICE_TOTOAL_SIZE) / LFS_BLOCK_DEVICE_ERASE_SIZE;
        fskv->conf.block_size = LFS_BLOCK_DEVICE_ERASE_SIZE;
        fskv->conf.block_cycles = 200;
        fskv->conf.name_max = 63;
        fskv->conf.read_size = LFS_BLOCK_DEVICE_CACHE_SIZE;
        fskv->conf.cache_size = LFS_BLOCK_DEVICE_CACHE_SIZE;
        fskv->conf.prog_size = LFS_BLOCK_DEVICE_PROG_SIZE;
        fskv->conf.cache_size = LFS_BLOCK_DEVICE_CACHE_SIZE;
        fskv->conf.lookahead_size = LFS_BLOCK_DEVICE_LOOK_AHEAD;
        fskv->conf.lookahead_buffer = fskv->lookahead_buffer;
        fskv->conf.prog_buffer = fskv->prog_buffer;
        fskv->conf.read_buffer = fskv->read_buffer;

        // LLOGD("fskv->conf.block_count %d", fskv->conf.block_count);
        // LLOGD("fskv->conf.block_size %d", fskv->conf.block_size);
        // LLOGD("fskv->conf.read_size %d", fskv->conf.read_size);
        // LLOGD("fskv->conf.prog_size %d", fskv->conf.prog_size);
        // LLOGD("fskv->conf.cache_size %d", fskv->conf.cache_size);

        sfd_onchip_init(NULL);

        // block_device_read(NULL, 0, 0, fskv->prog_buffer, 256);
        // LLOGD("Flash starts %02X %02X %02X %02X", fskv->prog_buffer[0], fskv->prog_buffer[1], 
        //                                        fskv->prog_buffer[2], fskv->prog_buffer[3]);
        // if (fskv->prog_buffer[0] == 0x00 && fskv->prog_buffer[1] == 0x00 && 
        //     fskv->prog_buffer[2] == 245 && fskv->prog_buffer[3] == 256) {

        //     }
        // sfd_onchip_erase(NULL, 0, LFS_BLOCK_DEVICE_TOTOAL_SIZE);

        ret = lfs_mount(&fskv->lfs, &fskv->conf);
        if (ret != LFS_ERR_OK) {
            LLOGI("fskv mount ret %d, exe auto-format", ret);
            ret = lfs_format(&fskv->lfs, &fskv->conf);
            if (ret != LFS_ERR_OK) {
                luat_heap_free(fskv);
                fskv = NULL;
                LLOGE("fskv auto-format ret %d", ret);
                return ret;
            }
            ret = lfs_mount(&fskv->lfs, &fskv->conf);
            if (ret != LFS_ERR_OK) {
                luat_heap_free(fskv);
                fskv = NULL;
                LLOGE("fskv remount ret %d", ret);
                return ret;
            }
        }
        LLOGD("init ok");
    }
    return 0;
}


int luat_fskv_del(const char* key) {
    lfs_remove(&fskv->lfs, key);
    return 0;
}

int luat_fskv_set(const char* key, void* data, size_t len) {
    lfs_file_t fd = {0};
    int ret = 0;
    ret = lfs_file_open(&fskv->lfs, &fd, key, LFS_O_WRONLY | LFS_O_CREAT | LFS_O_TRUNC);
    if (ret != LFS_ERR_OK) {
        return -1;
    }
    ret = lfs_file_write(&fskv->lfs, &fd, data, len);
    lfs_file_close(&fskv->lfs, &fd);
    return ret;
}

int luat_fskv_get(const char* key, void* data, size_t len) {
    lfs_file_t fd = {0};
    int ret = 0;
    ret = lfs_file_open(&fskv->lfs, &fd, key, LFS_O_RDONLY);
    if (ret != LFS_ERR_OK) {
        return 0;
    }
    ret = lfs_file_read(&fskv->lfs, &fd, data, len);
    lfs_file_close(&fskv->lfs, &fd);
    return ret > 0 ? ret : 0;
}

int luat_fskv_clear(void) {
    int ret = 0;
    ret = lfs_format(&fskv->lfs, &fskv->conf);
    if (ret != LFS_ERR_OK) {
        luat_heap_free(fskv);
        LLOGE("fskv clear ret %d", ret);
        return ret;
    }
    ret = lfs_mount(&fskv->lfs, &fskv->conf);
    if (ret != LFS_ERR_OK) {
        luat_heap_free(fskv);
        LLOGE("fskv reinit ret %d", ret);
        return ret;
    }
    return 0;
}

int luat_fskv_stat(size_t *using_sz, size_t *total, size_t *kv_count) {
    *using_sz = lfs_fs_size(&fskv->lfs) * LFS_BLOCK_DEVICE_ERASE_SIZE;
    *total = LFS_BLOCK_DEVICE_TOTOAL_SIZE;
    lfs_dir_t dir = {0};
    int ret = lfs_dir_open(&fskv->lfs, &dir, "");
    if (ret != LFS_ERR_OK) {
        LLOGW("lfs_dir_open ret %d", ret);
        return -1;
    }
    size_t count = 0;
    struct lfs_info info = {0};
    while (1) {
        ret = lfs_dir_read(&fskv->lfs, &dir, &info);
        if (ret > 0) {
            if (info.type == LFS_TYPE_REG)
                count ++;
        }
        else
            break;
    }
    lfs_dir_close(&fskv->lfs, &dir);
    *kv_count = count;
    return 0;
}
