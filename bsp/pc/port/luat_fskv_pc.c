#include "luat_base.h"
#include "luat_fskv.h"
#include "luat_malloc.h"
#include <stdio.h>

#define LUAT_LOG_TAG "fskv"
#include "luat_log.h"

#include "lfs.h"

#define LFS_BLOCK_DEVICE_READ_SIZE (256)
#define LFS_BLOCK_DEVICE_PROG_SIZE (256)
#define LFS_BLOCK_DEVICE_CACHE_SIZE (256)
#define LFS_BLOCK_DEVICE_ERASE_SIZE (4096) // one sector 4KB
#define LFS_BLOCK_DEVICE_TOTOAL_SIZE (64 * 1024)
#define LFS_BLOCK_DEVICE_LOOK_AHEAD (16)
#define FSKV_FILE_NAME "fskv.bin"

typedef struct fskv_file_ctx
{
    FILE *fd;
} fskv_file_ctx_t;

typedef int (*fskv_lfs_fn_t)(lfs_t *lfs, void *userdata);
typedef int (*fskv_raw_fn_t)(fskv_file_ctx_t *ctx, void *userdata);

typedef struct fskv_mounted_args
{
    fskv_lfs_fn_t fn;
    void *userdata;
} fskv_mounted_args_t;

typedef struct fskv_rw_args
{
    const char *key;
    void *data;
    size_t len;
} fskv_rw_args_t;

typedef struct fskv_stat_args
{
    size_t *using_sz;
    size_t *total;
    size_t *kv_count;
} fskv_stat_args_t;

typedef struct fskv_next_args
{
    char *buff;
    size_t offset;
} fskv_next_args_t;

static struct lfs_config fskv_lfs_conf;
static uint8_t fskv_lfs_conf_ready;

static int block_device_read(const struct lfs_config *cfg, lfs_block_t block,
                             lfs_off_t off, void *buffer, lfs_size_t size);
static int block_device_prog(const struct lfs_config *cfg, lfs_block_t block,
                             lfs_off_t off, const void *buffer, lfs_size_t size);
static int block_device_erase(const struct lfs_config *cfg, lfs_block_t block);
static int block_device_sync(const struct lfs_config *cfg);

static int fskv_prepare_conf(void)
{
    if (fskv_lfs_conf_ready)
    {
        return 0;
    }

    memset(&fskv_lfs_conf, 0, sizeof(fskv_lfs_conf));
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
    if (fskv_lfs_conf.lookahead_buffer == NULL || fskv_lfs_conf.prog_buffer == NULL || fskv_lfs_conf.read_buffer == NULL)
    {
        LLOGE("alloc lfs buffers failed");
        return -1;
    }
    fskv_lfs_conf_ready = 1;
    return 0;
}

static int fskv_reset_image(FILE *fd)
{
    static const uint8_t zero_buff[LFS_BLOCK_DEVICE_CACHE_SIZE] = {0};
    if (fseek(fd, 0, SEEK_SET) != 0)
    {
        return -1;
    }
    for (size_t offset = 0; offset < LFS_BLOCK_DEVICE_TOTOAL_SIZE; offset += sizeof(zero_buff))
    {
        size_t chunk = LFS_BLOCK_DEVICE_TOTOAL_SIZE - offset;
        if (chunk > sizeof(zero_buff))
        {
            chunk = sizeof(zero_buff);
        }
        if (fwrite(zero_buff, 1, chunk, fd) != chunk)
        {
            return -1;
        }
    }
    if (fflush(fd) != 0)
    {
        return -1;
    }
    return fseek(fd, 0, SEEK_SET);
}

static int fskv_open_file(fskv_file_ctx_t *ctx)
{
    FILE *fd = fopen(FSKV_FILE_NAME, "r+b");
    if (fd == NULL)
    {
        fd = fopen(FSKV_FILE_NAME, "w+b");
    }
    if (fd == NULL)
    {
        LLOGE("open %s failed", FSKV_FILE_NAME);
        return -1;
    }
    ctx->fd = fd;

    if (fseek(ctx->fd, 0, SEEK_END) != 0)
    {
        return -1;
    }
    long file_size = ftell(ctx->fd);
    if (file_size != LFS_BLOCK_DEVICE_TOTOAL_SIZE)
    {
        fd = freopen(FSKV_FILE_NAME, "w+b", ctx->fd);
        if (fd == NULL)
        {
            ctx->fd = NULL;
            LLOGE("reset %s failed", FSKV_FILE_NAME);
            return -1;
        }
        ctx->fd = fd;
        if (fskv_reset_image(ctx->fd) != 0)
        {
            LLOGE("init %s failed", FSKV_FILE_NAME);
            return -1;
        }
    }
    else if (fseek(ctx->fd, 0, SEEK_SET) != 0)
    {
        return -1;
    }
    return 0;
}

static int fskv_close_file(fskv_file_ctx_t *ctx)
{
    int ret = 0;
    if (ctx->fd)
    {
        if (fflush(ctx->fd) != 0)
        {
            ret = -1;
        }
        if (fclose(ctx->fd) != 0)
        {
            ret = -1;
        }
        ctx->fd = NULL;
    }
    return ret;
}

static long fskv_block_offset(lfs_block_t block, lfs_off_t off, lfs_size_t size)
{
    long absolute_offset = (long)block * LFS_BLOCK_DEVICE_ERASE_SIZE + (long)off;
    if (absolute_offset < 0 || (size_t)absolute_offset + size > LFS_BLOCK_DEVICE_TOTOAL_SIZE)
    {
        return -1;
    }
    return absolute_offset;
}

// Read a block
static int block_device_read(const struct lfs_config *cfg, lfs_block_t block,
                             lfs_off_t off, void *buffer, lfs_size_t size)
{
    fskv_file_ctx_t *ctx = (fskv_file_ctx_t *)cfg->context;
    long absolute_offset = fskv_block_offset(block, off, size);
    if (ctx == NULL || ctx->fd == NULL || absolute_offset < 0)
    {
        return LFS_ERR_IO;
    }
    if (fseek(ctx->fd, absolute_offset, SEEK_SET) != 0)
    {
        return LFS_ERR_IO;
    }
    if (fread(buffer, 1, size, ctx->fd) != size)
    {
        return LFS_ERR_IO;
    }
    return LFS_ERR_OK;
}

// Program a block
//
// The block must have previously been erased.
static int block_device_prog(const struct lfs_config *cfg, lfs_block_t block,
                             lfs_off_t off, const void *buffer, lfs_size_t size)
{
    fskv_file_ctx_t *ctx = (fskv_file_ctx_t *)cfg->context;
    long absolute_offset = fskv_block_offset(block, off, size);
    if (ctx == NULL || ctx->fd == NULL || absolute_offset < 0)
    {
        return LFS_ERR_IO;
    }
    if (fseek(ctx->fd, absolute_offset, SEEK_SET) != 0)
    {
        return LFS_ERR_IO;
    }
    if (fwrite(buffer, 1, size, ctx->fd) != size)
    {
        return LFS_ERR_IO;
    }
    return LFS_ERR_OK;
}

// Erase a block
//
// A block must be erased before being programmed. The
// state of an erased block is undefined.
static int block_device_erase(const struct lfs_config *cfg, lfs_block_t block)
{
    static const uint8_t zero_buff[LFS_BLOCK_DEVICE_CACHE_SIZE] = {0};
    fskv_file_ctx_t *ctx = (fskv_file_ctx_t *)cfg->context;
    long absolute_offset = fskv_block_offset(block, 0, LFS_BLOCK_DEVICE_ERASE_SIZE);
    if (ctx == NULL || ctx->fd == NULL || absolute_offset < 0)
    {
        return LFS_ERR_IO;
    }
    if (fseek(ctx->fd, absolute_offset, SEEK_SET) != 0)
    {
        return LFS_ERR_IO;
    }
    for (size_t offset = 0; offset < LFS_BLOCK_DEVICE_ERASE_SIZE; offset += sizeof(zero_buff))
    {
        size_t chunk = LFS_BLOCK_DEVICE_ERASE_SIZE - offset;
        if (chunk > sizeof(zero_buff))
        {
            chunk = sizeof(zero_buff);
        }
        if (fwrite(zero_buff, 1, chunk, ctx->fd) != chunk)
        {
            return LFS_ERR_IO;
        }
    }
    return LFS_ERR_OK;
}

// Sync the block device
static int block_device_sync(const struct lfs_config *cfg)
{
    fskv_file_ctx_t *ctx = (fskv_file_ctx_t *)cfg->context;
    if (ctx == NULL || ctx->fd == NULL)
    {
        return LFS_ERR_IO;
    }
    return fflush(ctx->fd) == 0 ? LFS_ERR_OK : LFS_ERR_IO;
}

static int fskv_mount(lfs_t *lfs)
{
    int ret = lfs_mount(lfs, &fskv_lfs_conf);
    if (ret != LFS_ERR_OK)
    {
        LLOGI("fskv_lfs mount ret %d, exec auto-format", ret);
        ret = lfs_format(lfs, &fskv_lfs_conf);
        if (ret != LFS_ERR_OK)
        {
            LLOGE("fskv_lfs auto-format ret %d", ret);
            return ret;
        }
        ret = lfs_mount(lfs, &fskv_lfs_conf);
        if (ret != LFS_ERR_OK)
        {
            LLOGE("fskv_lfs remount ret %d", ret);
            return ret;
        }
    }
    return LFS_ERR_OK;
}

static int fskv_with_opened_image(fskv_raw_fn_t fn, void *userdata)
{
    fskv_file_ctx_t ctx = {0};
    int ret = fskv_prepare_conf();
    if (ret != 0)
    {
        return ret;
    }
    ret = fskv_open_file(&ctx);
    if (ret != 0)
    {
        fskv_close_file(&ctx);
        return ret;
    }
    fskv_lfs_conf.context = &ctx;
    ret = fn(&ctx, userdata);
    fskv_lfs_conf.context = NULL;

    int close_ret = fskv_close_file(&ctx);
    if (ret >= 0 && close_ret != 0)
    {
        ret = close_ret;
    }
    return ret;
}

static int fskv_mounted_raw(fskv_file_ctx_t *ctx, void *userdata)
{
    (void)ctx;
    fskv_mounted_args_t *args = (fskv_mounted_args_t *)userdata;
    lfs_t lfs = {0};
    int ret = fskv_mount(&lfs);
    if (ret != LFS_ERR_OK)
    {
        return ret;
    }

    ret = args->fn(&lfs, args->userdata);
    int unmount_ret = lfs_unmount(&lfs);
    if (ret >= 0 && unmount_ret != LFS_ERR_OK)
    {
        ret = unmount_ret;
    }
    return ret;
}

static int fskv_with_mounted_lfs(fskv_lfs_fn_t fn, void *userdata)
{
    fskv_mounted_args_t args = {0};
    args.fn = fn;
    args.userdata = userdata;
    return fskv_with_opened_image(fskv_mounted_raw, &args);
}

static int fskv_noop_cb(lfs_t *lfs, void *userdata)
{
    (void)lfs;
    (void)userdata;
    return 0;
}

static int fskv_del_cb(lfs_t *lfs, void *userdata)
{
    const char *key = (const char *)userdata;
    int ret = lfs_remove(lfs, key);
    if (ret < 0 && ret != LFS_ERR_NOENT)
    {
        LLOGW("lfs_remove ret %d", ret);
    }
    return ret == LFS_ERR_NOENT ? 0 : (ret < 0 ? ret : 0);
}

static int fskv_set_cb(lfs_t *lfs, void *userdata)
{
    fskv_rw_args_t *args = (fskv_rw_args_t *)userdata;
    lfs_file_t fd = {0};
    int ret = lfs_file_open(lfs, &fd, args->key, LFS_O_WRONLY | LFS_O_CREAT | LFS_O_TRUNC);
    if (ret != LFS_ERR_OK)
    {
        return -1;
    }
    ret = lfs_file_write(lfs, &fd, args->data, args->len);
    int close_ret = lfs_file_close(lfs, &fd);
    if (ret >= 0 && close_ret != LFS_ERR_OK)
    {
        ret = close_ret;
    }
    return ret;
}

static int fskv_get_cb(lfs_t *lfs, void *userdata)
{
    fskv_rw_args_t *args = (fskv_rw_args_t *)userdata;
    lfs_file_t fd = {0};
    int ret = lfs_file_open(lfs, &fd, args->key, LFS_O_RDONLY);
    if (ret != LFS_ERR_OK)
    {
        return 0;
    }
    ret = lfs_file_read(lfs, &fd, args->data, args->len);
    lfs_file_close(lfs, &fd);
    return ret > 0 ? ret : 0;
}

static int fskv_clear_raw(fskv_file_ctx_t *ctx, void *userdata)
{
    (void)ctx;
    (void)userdata;
    lfs_t lfs = {0};
    int ret = lfs_format(&lfs, &fskv_lfs_conf);
    if (ret != LFS_ERR_OK)
    {
        LLOGE("fskv clear ret %d", ret);
    }
    return ret;
}

static int fskv_stat_cb(lfs_t *lfs, void *userdata)
{
    fskv_stat_args_t *args = (fskv_stat_args_t *)userdata;
    *args->using_sz = lfs_fs_size(lfs) * LFS_BLOCK_DEVICE_ERASE_SIZE;
    *args->total = LFS_BLOCK_DEVICE_TOTOAL_SIZE;

    lfs_dir_t dir = {0};
    int ret = lfs_dir_open(lfs, &dir, "");
    if (ret != LFS_ERR_OK)
    {
        LLOGW("lfs_dir_open ret %d", ret);
        return -1;
    }
    size_t count = 0;
    struct lfs_info info = {0};
    while (1)
    {
        ret = lfs_dir_read(lfs, &dir, &info);
        if (ret > 0)
        {
            if (info.type == LFS_TYPE_REG)
            {
                count++;
            }
        }
        else
        {
            break;
        }
    }
    lfs_dir_close(lfs, &dir);
    *args->kv_count = count;
    return 0;
}

static int fskv_size_cb(lfs_t *lfs, void *userdata)
{
    fskv_rw_args_t *args = (fskv_rw_args_t *)userdata;
    lfs_file_t fd = {0};
    int ret = lfs_file_open(lfs, &fd, args->key, LFS_O_RDONLY);
    if (ret != LFS_ERR_OK)
    {
        return 0;
    }
    ret = lfs_file_size(lfs, &fd);
    if (ret > 1 && ret < 256)
    {
        int ret2 = lfs_file_read(lfs, &fd, args->data, ret);
        if (ret2 != ret)
        {
            ret = -2;
        }
    }
    lfs_file_close(lfs, &fd);
    return ret;
}

static int fskv_next_cb(lfs_t *lfs, void *userdata)
{
    fskv_next_args_t *args = (fskv_next_args_t *)userdata;
    lfs_dir_t dir = {0};
    struct lfs_info info = {0};
    size_t offset = args->offset + 2;
    int ret = lfs_dir_open(lfs, &dir, "");
    if (ret < 0)
    {
        LLOGW("lfs_dir_open ret %d", ret);
        return -1;
    }
    ret = lfs_dir_seek(lfs, &dir, offset);
    if (ret < 0)
    {
        lfs_dir_close(lfs, &dir);
        return -2;
    }
    ret = lfs_dir_read(lfs, &dir, &info);
    if (ret <= 0)
    {
        lfs_dir_close(lfs, &dir);
        return -3;
    }
    memcpy(args->buff, info.name, strlen(info.name) + 1);
    lfs_dir_close(lfs, &dir);
    return 0;
}

int luat_fskv_init(void)
{
    int ret = fskv_with_mounted_lfs(fskv_noop_cb, NULL);
    if (ret != 0)
    {
        return ret;
    }
    LLOGD("init ok");
    return 0;
}


int luat_fskv_del(const char *key)
{
    return fskv_with_mounted_lfs(fskv_del_cb, (void *)key);
}

int luat_fskv_set(const char *key, void *data, size_t len)
{
    fskv_rw_args_t args = {0};
    args.key = key;
    args.data = data;
    args.len = len;
    return fskv_with_mounted_lfs(fskv_set_cb, &args);
}

int luat_fskv_get(const char *key, void *data, size_t len)
{
    fskv_rw_args_t args = {0};
    args.key = key;
    args.data = data;
    args.len = len;
    return fskv_with_mounted_lfs(fskv_get_cb, &args);
}

int luat_fskv_clear(void)
{
    return fskv_with_opened_image(fskv_clear_raw, NULL);
}

int luat_fskv_stat(size_t *using_sz, size_t *total, size_t *kv_count)
{
    fskv_stat_args_t args = {0};
    args.using_sz = using_sz;
    args.total = total;
    args.kv_count = kv_count;
    return fskv_with_mounted_lfs(fskv_stat_cb, &args);
}

int luat_fskv_size(const char *key, char buff[4])
{
    fskv_rw_args_t args = {0};
    args.key = key;
    args.data = buff;
    return fskv_with_mounted_lfs(fskv_size_cb, &args);
}

int luat_fskv_next(char *buff, size_t offset)
{
    fskv_next_args_t args = {0};
    args.buff = buff;
    args.offset = offset;
    return fskv_with_mounted_lfs(fskv_next_cb, &args);
}
