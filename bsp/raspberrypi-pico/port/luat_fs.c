#include <stdio.h>

#include "luat_fs.h"
#define LUAT_LOG_TAG "luat.fs"
#include "luat_log.h"
#include "lfs.h"
#include "pico/stdlib.h"
#include "hardware/flash.h"
#include "string.h"

#define LFS_START_ADDR 0x101E0000
#define FLASH_FS_REGION_SIZE (1024 * 256)
/***************************************************
 ***************       MACRO      ******************
 ***************************************************/

#define LFS_BLOCK_DEVICE_READ_SIZE (256)
#define LFS_BLOCK_DEVICE_PROG_SIZE (256)
#define LFS_BLOCK_DEVICE_CACHE_SIZE (256)
#define LFS_BLOCK_DEVICE_ERASE_SIZE (4096) // one sector 4KB
#define LFS_BLOCK_DEVICE_TOTOAL_SIZE (FLASH_FS_REGION_SIZE)
#define LFS_BLOCK_DEVICE_LOOK_AHEAD (16)

/***************************************************
 *******    FUNCTION FORWARD DECLARTION     ********
 ***************************************************/

// Read a block
static int block_device_read(const struct lfs_config *cfg, lfs_block_t block,
                             lfs_off_t off, void *buffer, lfs_size_t size);

// Program a block
//
// The block must have previously been erased.
static int block_device_prog(const struct lfs_config *cfg, lfs_block_t block,
                             lfs_off_t off, const void *buffer, lfs_size_t size);

// Erase a block
//
// A block must be erased before being programmed. The
// state of an erased block is undefined.
static int block_device_erase(const struct lfs_config *cfg, lfs_block_t block);

// Sync the block device
static int block_device_sync(const struct lfs_config *cfg);

// utility functions for traversals
//static int lfs_statfs_count(void *p, lfs_block_t b);

/************************************************************/

static int block_device_read(const struct lfs_config *cfg, lfs_block_t block,
                             lfs_off_t off, void *buffer, lfs_size_t size)
{
    int ret;
    // buffer = (uint8_t *)(block * 4096 + off + LFS_START_ADDR+XIP_BASE);
    memcpy(buffer, LFS_START_ADDR+block*4096+off, size);
    // flash_read(&spi, LFS_START_ADDR+block*4096+off, buffer, size);
    //LLOGD("block_device_read ,block = %d, off = %d,  size = %d",block, off, size);
    // ret = tls_fls_read(block * 4096 + off + LFS_START_ADDR, (u8 *)buffer, size);
    // //LLOGD("block_device_read return val : %d",ret);
    // if (ret != TLS_FLS_STATUS_OK)
    // {
    //     return -1;
    // }
    return LFS_ERR_OK;
}
static int block_device_prog(const struct lfs_config *cfg, lfs_block_t block,
                             lfs_off_t off, const void *buffer, lfs_size_t size)
{
    int ret;
    //LLOGD("block_device_prog ,block = %d, off = %d,  size = %d",block, off, size);
    flash_range_program(block * 4096 + off + LFS_START_ADDR, (uint8_t *)buffer, size);
    // flash_page_program(&spi, block * 4096 + off + LFS_START_ADDR, (uint8_t *)buffer);
    //LLOGD("block_device_prog return val : %d",ret);
    // if (ret != TLS_FLS_STATUS_OK)
    // {
    //     return -1;
    // }

    return LFS_ERR_OK;
}

static int block_device_erase(const struct lfs_config *cfg, lfs_block_t block)
{
    int ret;
    flash_range_erase(LFS_START_ADDR + block * 4096, 4096);
    // flash_sector_erase(&spi, LFS_START_ADDR + block * 4096);
    return LFS_ERR_OK;
}

static int block_device_sync(const struct lfs_config *cfg)
{
    return LFS_ERR_OK;
}

/***************************************************
 ***************  GLOBAL VARIABLE  *****************
 ***************************************************/

// variables used by the filesystem
static lfs_t lfs;

#ifdef LFS_THREAD_SAFE_MUTEX
static osMutexId_t lfs_mutex;
#endif

static char lfs_read_buf[256];
static char lfs_prog_buf[256];
//static __ALIGNED(4) char lfs_lookahead_buf[LFS_BLOCK_DEVICE_LOOK_AHEAD];
//__align(4)  static  char lfs_lookahead_buf[LFS_BLOCK_DEVICE_LOOK_AHEAD];
static  char  __attribute__((aligned(4))) lfs_lookahead_buf[LFS_BLOCK_DEVICE_LOOK_AHEAD];
// configuration of the filesystem is provided by this struct
static struct lfs_config lfs_cfg =
    {
        .context = NULL,
        // block device operations
        .read = block_device_read,
        .prog = block_device_prog,
        .erase = block_device_erase,
        .sync = block_device_sync,

        // block device configuration
        .read_size = LFS_BLOCK_DEVICE_READ_SIZE,
        .prog_size = LFS_BLOCK_DEVICE_PROG_SIZE,
        .block_size = LFS_BLOCK_DEVICE_ERASE_SIZE,
        .block_count = LFS_BLOCK_DEVICE_TOTOAL_SIZE / LFS_BLOCK_DEVICE_ERASE_SIZE,
        .block_cycles = 200,
        .cache_size = LFS_BLOCK_DEVICE_CACHE_SIZE,
        .lookahead_size = LFS_BLOCK_DEVICE_LOOK_AHEAD,

        .read_buffer = lfs_read_buf,
        .prog_buffer = lfs_prog_buf,
        .lookahead_buffer = lfs_lookahead_buf,
        .name_max = 63,
        .file_max = 0,
        .attr_max = 0};

FILE *luat_fs_fopen(const char *filename, const char *mode)
{
    ////LLOGD("fopen %s %s", filename, mode);
    int ret;
    char *t = (char *)mode;
    int flags = 0;
    lfs_file_t *lfsfile = NULL;
    for (int i = 0; i < strlen(mode); i++)
    {

        switch (*(t++))
        {
        case 'w':
            flags |= LFS_O_RDWR;
            break;
        case 'r':
            flags |= LFS_O_RDONLY;
            break;
        case 'a':
            flags |= LFS_O_APPEND;
            break;
        case 'b':
            break;
        case '+':
            break;
        default:

            break;
        }
    }

    lfsfile = malloc(sizeof(lfs_file_t));
    if (!lfsfile)
    {
        return lfsfile;
    }

    ret = lfs_file_open(&lfs, lfsfile, filename, flags);
    if (ret != 0)
    {
        return NULL;
    }

    return lfsfile;

}

int luat_fs_getc(FILE *stream)
{
    return getc(stream);
}

int luat_fs_fseek(FILE *stream, long int offset, int origin)
{
    int ret;
    ret = lfs_file_seek(&lfs, stream, offset, origin);
    if (ret < 0)
    {
        return -1;
    }

    return ret;
}

int luat_fs_ftell(FILE *stream)
{
    return ftell(stream);
}

int luat_fs_fclose(FILE *stream)
{
    int ret;
    ret = lfs_file_close(&lfs, (lfs_dir_t *)stream);
    if (ret != 0)
    {
        return 1;
    }
    free(stream);
    return 0;
}
int luat_fs_feof(FILE *stream)
{
    return feof(stream);
}
int luat_fs_ferror(FILE *stream)
{
    return ferror(stream);
}
size_t luat_fs_fread(void *ptr, size_t size, size_t nmemb, FILE *stream)
{
    int ret;
    ret = lfs_file_read(&lfs, stream,ptr, size * nmemb);
    if (ret < 0)
    {
        return 0;
    }
    return  ret;
}
size_t luat_fs_fwrite(const void *ptr, size_t size, size_t nmemb, FILE *stream)
{
    int ret;
    ret = lfs_file_write(&lfs,stream, ptr, size * nmemb);
    if (ret < 0)
    {
        return 0;
    }

    return ret;
}
int luat_fs_remove(const char *filename)
{
    int ret;
    ret = lfs_remove(&lfs,filename);
    if(ret != 0)
    {
        return 1;
    }
    return 0;
}
int luat_fs_rename(const char *old_filename, const char *new_filename)
{
    int ret;
    ret = lfs_rename(&lfs, old_filename,new_filename);
    if (ret != 0)
    {
       return 1;
    }
    return 0;
}
int luat_fs_fexist(const char *filename)
{
    FILE *fd = luat_fs_fopen(filename, "rb");
    if (fd)
    {
        luat_fs_fclose(fd);
        return 1;
    }
    return 0;
}

size_t luat_fs_fsize(const char *filename)
{
    FILE *fd;
    size_t size = 0;
    fd = luat_fs_fopen(filename, "rb");
    if (fd)
    {
        luat_fs_fseek(fd, 0, SEEK_END);
        size = luat_fs_ftell(fd);
        luat_fs_fclose(fd);
    }
    return size;
}

int luat_fs_init(void)
{
    // mount the filesystem
    int err = lfs_mount(&lfs, &lfs_cfg);
    //LLOGD("lfs_mount return val : %d",err);
    // reformat if we can't mount the filesystem
    // this should only happen on the first boot
    if (err)
    {
        err = lfs_format(&lfs, &lfs_cfg);
        //LLOGD("lfs_format return val : %d",err);
        if (err)
            return err;

        err = lfs_mount(&lfs, &lfs_cfg);
        //LLOGD("lfs_mount return val : %d",err);
        if (err)
            return err;
    }
}
