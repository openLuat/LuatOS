#include "luat_base.h"
#include "luat_fskv.h"
#include "luat_malloc.h"

#define LUAT_LOG_TAG "fskv"
#include "luat_log.h"

#include "lfs.h"

#define LFS_BLOCK_DEVICE_READ_SIZE (256)
#define LFS_BLOCK_DEVICE_PROG_SIZE (256)
#define LFS_BLOCK_DEVICE_CACHE_SIZE (256)
#define LFS_BLOCK_DEVICE_ERASE_SIZE (4096) // one sector 4KB
#define LFS_BLOCK_DEVICE_TOTOAL_SIZE (64 * 1024)
#define LFS_BLOCK_DEVICE_LOOK_AHEAD (16)


static lfs_t fskv_lfs;
static struct lfs_config fskv_lfs_conf;

static char fskv_buff[LFS_BLOCK_DEVICE_TOTOAL_SIZE];
// Read a block
static int block_device_read(const struct lfs_config *cfg, lfs_block_t block,
                             lfs_off_t off, void *buffer, lfs_size_t size)
{
    (void)cfg;
    memcpy(buffer, fskv_buff + (block * 4096 + off), size);
    return LFS_ERR_OK;
}

// Program a block
//
// The block must have previously been erased.
static int block_device_prog(const struct lfs_config *cfg, lfs_block_t block,
                             lfs_off_t off, const void *buffer, lfs_size_t size)
{
    (void)cfg;
    memcpy(fskv_buff + (block * 4096 + off), buffer, size);
    return LFS_ERR_OK;
}

// Erase a block
//
// A block must be erased before being programmed. The
// state of an erased block is undefined.
static int block_device_erase(const struct lfs_config *cfg, lfs_block_t block)
{
    (void)cfg;
    memset(fskv_buff + (block * 4096), 0, 4096);
    return 0;
}

// Sync the block device
static int block_device_sync(const struct lfs_config *cfg)
{
    (void)cfg;
    return 0;
}

int luat_fskv_init(void)
{
    int ret = 0;
    fskv_lfs_conf.read = block_device_read;
    fskv_lfs_conf.prog = block_device_prog;
    fskv_lfs_conf.erase = block_device_erase;
    fskv_lfs_conf.sync = block_device_sync;
    fskv_lfs_conf.attr_max = 0;
    fskv_lfs_conf.file_max = 4096;
    fskv_lfs_conf.block_count = (LFS_BLOCK_DEVICE_TOTOAL_SIZE) / LFS_BLOCK_DEVICE_ERASE_SIZE;
    fskv_lfs_conf.block_size = LFS_BLOCK_DEVICE_ERASE_SIZE;
    fskv_lfs_conf.block_cycles = 200;
    fskv_lfs_conf.name_max = 63;
    fskv_lfs_conf.read_size = LFS_BLOCK_DEVICE_CACHE_SIZE;
    fskv_lfs_conf.cache_size = LFS_BLOCK_DEVICE_CACHE_SIZE;
    fskv_lfs_conf.prog_size = LFS_BLOCK_DEVICE_PROG_SIZE;
    fskv_lfs_conf.lookahead_size = LFS_BLOCK_DEVICE_LOOK_AHEAD;
    fskv_lfs_conf.lookahead_buffer = luat_heap_malloc(4096);
    fskv_lfs_conf.prog_buffer = luat_heap_malloc(4096);
    fskv_lfs_conf.read_buffer = luat_heap_malloc(4096);
    fskv_lfs_conf.context = NULL;

    ret = lfs_mount(&fskv_lfs, &fskv_lfs_conf);
    if (ret != LFS_ERR_OK)
    {
        LLOGI("fskv_lfs mount ret %d, exec auto-format", ret);
        ret = lfs_format(&fskv_lfs, &fskv_lfs_conf);
        if (ret != LFS_ERR_OK)
        {
            LLOGE("fskv_lfs auto-format ret %d", ret);
            return ret;
        }
        ret = lfs_mount(&fskv_lfs, &fskv_lfs_conf);
        if (ret != LFS_ERR_OK)
        {
            LLOGE("fskv_lfs remount ret %d", ret);
            return ret;
        }
    }
    LLOGD("init ok");
    return 0;
}


int luat_fskv_del(const char *key)
{
    lfs_remove(&fskv_lfs, key);
    return 0;
}

int luat_fskv_set(const char *key, void *data, size_t len)
{
    lfs_file_t fd = {0};
    int ret = 0;
    ret = lfs_file_open(&fskv_lfs, &fd, key, LFS_O_WRONLY | LFS_O_CREAT | LFS_O_TRUNC);
    if (ret != LFS_ERR_OK)
    {
        return -1;
    }
    ret = lfs_file_write(&fskv_lfs, &fd, data, len);
    ret |= lfs_file_close(&fskv_lfs, &fd);
    return ret;
}

int luat_fskv_get(const char *key, void *data, size_t len)
{
    lfs_file_t fd = {0};
    int ret = 0;
    ret = lfs_file_open(&fskv_lfs, &fd, key, LFS_O_RDONLY);
    if (ret != LFS_ERR_OK)
    {
        return 0;
    }
    ret = lfs_file_read(&fskv_lfs, &fd, data, len);
    lfs_file_close(&fskv_lfs, &fd);
    return ret > 0 ? ret : 0;
}

int luat_fskv_clear(void)
{
    int ret = 0;
    ret = lfs_format(&fskv_lfs, &fskv_lfs_conf);
    if (ret != LFS_ERR_OK)
    {
        LLOGE("fskv clear ret %d", ret);
        return ret;
    }
    ret = lfs_mount(&fskv_lfs, &fskv_lfs_conf);
    if (ret != LFS_ERR_OK)
    {
        LLOGE("fskv reinit ret %d", ret);
        return ret;
    }
    return 0;
}

int luat_fskv_stat(size_t *using_sz, size_t *total, size_t *kv_count)
{
    *using_sz = lfs_fs_size(&fskv_lfs) * LFS_BLOCK_DEVICE_ERASE_SIZE;
    *total = LFS_BLOCK_DEVICE_TOTOAL_SIZE;
    lfs_dir_t dir = {0};
    int ret = lfs_dir_open(&fskv_lfs, &dir, "");
    if (ret != LFS_ERR_OK)
    {
        LLOGW("lfs_dir_open ret %d", ret);
        return -1;
    }
    size_t count = 0;
    struct lfs_info info = {0};
    while (1)
    {
        ret = lfs_dir_read(&fskv_lfs, &dir, &info);
        if (ret > 0)
        {
            if (info.type == LFS_TYPE_REG)
                count++;
        }
        else
            break;
    }
    lfs_dir_close(&fskv_lfs, &dir);
    *kv_count = count;
    return 0;
}

int luat_fskv_size(const char *key, char buff[4])
{
    lfs_file_t fd = {0};
    int ret = 0;
    ret = lfs_file_open(&fskv_lfs, &fd, key, LFS_O_RDONLY);
    if (ret != LFS_ERR_OK)
    {
        return 0;
    }
    ret = lfs_file_size(&fskv_lfs, &fd);
    if (ret > 1 && ret < 256)
    {
        int ret2 = lfs_file_read(&fskv_lfs, &fd, buff, ret);
        if (ret2 != ret)
        {
            ret = -2; // 读取失败,肯定有问题
        }
    }
    lfs_file_close(&fskv_lfs, &fd);
    return ret;
}

int luat_fskv_next(char *buff, size_t offset)
{
    lfs_dir_t dir = {0};
    struct lfs_info info = {0};
    // offset要+2, 因为前2个值是"."和".."两个dir
    offset += 2;
    int ret = lfs_dir_open(&fskv_lfs, &dir, "");
    if (ret < 0)
    {
        LLOGW("lfs_dir_open ret %d", ret);
        return -1;
    }
    ret = lfs_dir_seek(&fskv_lfs, &dir, offset);
    if (ret < 0)
    {
        lfs_dir_close(&fskv_lfs, &dir);
        return -2;
    }
    ret = lfs_dir_read(&fskv_lfs, &dir, &info);
    if (ret <= 0)
    {
        lfs_dir_close(&fskv_lfs, &dir);
        return -3;
    }
    memcpy(buff, info.name, strlen(info.name) + 1);
    lfs_dir_close(&fskv_lfs, &dir);
    return 0;
}
