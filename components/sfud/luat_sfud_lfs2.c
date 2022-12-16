
#include "luat_base.h"
#include "luat_fs.h"
#include "luat_malloc.h"

#define LUAT_LOG_TAG "sfud"
#include "luat_log.h"

#ifdef LUAT_USE_SFUD
#ifdef LUAT_USE_FS_VFS
#include "lfs.h"
#include "sfud.h"
#define LFS_BLOCK_SIZE (4096)
#define LFS_BLOCK_DEVICE_READ_SIZE (256)
#define LFS_BLOCK_DEVICE_PROG_SIZE (256)
#define LFS_BLOCK_DEVICE_CACHE_SIZE (256)
#define LFS_BLOCK_DEVICE_ERASE_SIZE (4096) // one sector 4KB
//#define LFS_BLOCK_DEVICE_TOTOAL_SIZE (FLASH_FS_REGION_SIZE)
#define LFS_BLOCK_DEVICE_LOOK_AHEAD (16)

static size_t sfud_offset = 0;

// Read a block
static int sfud_block_device_read(const struct lfs_config *cfg, lfs_block_t block, lfs_off_t off, void *buffer, lfs_size_t size) {
    sfud_flash* flash = (sfud_flash*)cfg->context;
    int ret = sfud_read(flash, sfud_offset + block * LFS_BLOCK_SIZE + off, size, buffer);
    //LLOGD("sfud_block_device_read ret %d", ret);
    return LFS_ERR_OK;
}

static int sfud_block_device_prog(const struct lfs_config *cfg, lfs_block_t block, lfs_off_t off, const void *buffer, lfs_size_t size) {
    sfud_flash* flash = (sfud_flash*)cfg->context;
    int ret = sfud_write(flash, sfud_offset + block * LFS_BLOCK_SIZE + off, size, buffer);
    //LLOGD("sfud_block_device_prog ret %d", ret);
    return LFS_ERR_OK;
}

static int sfud_block_device_erase(const struct lfs_config *cfg, lfs_block_t block) {
    sfud_flash* flash = (sfud_flash*)cfg->context;
    int ret = sfud_erase(flash, sfud_offset + block * LFS_BLOCK_SIZE, LFS_BLOCK_SIZE);
    //LLOGD("sfud_block_device_erase ret %d", ret);
    return LFS_ERR_OK;
}

static int sfud_block_device_sync(const struct lfs_config *cfg) {
    return LFS_ERR_OK;
}

typedef struct LFS2 {
    lfs_t lfs;
    struct lfs_config cfg;
    uint8_t read_buffer[LFS_BLOCK_DEVICE_READ_SIZE];
    uint8_t prog_buffer[LFS_BLOCK_DEVICE_PROG_SIZE];
    uint8_t lookahead_buffer[LFS_BLOCK_DEVICE_LOOK_AHEAD];
}LFS2_t;


lfs_t* flash_lfs_sfud(sfud_flash* flash, size_t offset, size_t maxsize) {
    LFS2_t *_lfs = luat_heap_malloc(sizeof(LFS2_t));
    if (_lfs == NULL)
        return NULL;
    memset(_lfs, 0, sizeof(LFS2_t));
    sfud_offset = offset;
    lfs_t *lfs = &_lfs->lfs;
    struct lfs_config *lfs_cfg = &_lfs->cfg;

    lfs_cfg->context = flash,
    // block device operations
    lfs_cfg->read = sfud_block_device_read;
    lfs_cfg->prog = sfud_block_device_prog;
    lfs_cfg->erase = sfud_block_device_erase;
    lfs_cfg->sync = sfud_block_device_sync;

    // block device configuration
    lfs_cfg->read_size = LFS_BLOCK_DEVICE_READ_SIZE;
    lfs_cfg->prog_size = LFS_BLOCK_DEVICE_PROG_SIZE;
    lfs_cfg->block_size = flash->chip.erase_gran;
    lfs_cfg->block_count = (maxsize > 0 ? maxsize : flash->chip.capacity) / flash->chip.erase_gran;
    lfs_cfg->block_cycles = 200;
    lfs_cfg->cache_size = LFS_BLOCK_DEVICE_CACHE_SIZE;
    lfs_cfg->lookahead_size = LFS_BLOCK_DEVICE_LOOK_AHEAD;

    lfs_cfg->read_buffer = _lfs->read_buffer;
    lfs_cfg->prog_buffer = _lfs->prog_buffer;
    lfs_cfg->lookahead_buffer = _lfs->lookahead_buffer;
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

#endif

