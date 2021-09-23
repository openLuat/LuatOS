
#include "luat_base.h"

#include "luat_sfd.h"
#include "luat_malloc.h"

#include "lfs.h"

#ifdef LUAT_SFD_ONCHIP
#if LUAT_SFD_ONCHIP

int sfd_onchip_init (void* userdata);
int sfd_onchip_status (void* userdata);
int sfd_onchip_read (void* userdata, char* buff, size_t offset, size_t len);
int sfd_onchip_write (void* userdata, const char* buff, size_t offset, size_t len);
int sfd_onchip_erase (void* userdata, size_t offset, size_t len);
int sfd_onchip_ioctl (void* userdata, size_t cmd, void* buff);

const sdf_opts_t sfd_onchip_opts = {
    .initialize = sfd_onchip_init,
    .status = sfd_onchip_status,
    .read = sfd_onchip_read,
    .write = sfd_onchip_write,
    .erase = sfd_onchip_erase,
    .ioctl = sfd_onchip_ioctl,
};



#include "lfs.h"
#define LFS_BLOCK_SIZE (4096)
#define LFS_BLOCK_DEVICE_READ_SIZE (256)
#define LFS_BLOCK_DEVICE_PROG_SIZE (256)
#define LFS_BLOCK_DEVICE_CACHE_SIZE (256)
#define LFS_BLOCK_DEVICE_ERASE_SIZE (4096) // one sector 4KB
//#define LFS_BLOCK_DEVICE_TOTOAL_SIZE (FLASH_FS_REGION_SIZE)
#define LFS_BLOCK_DEVICE_LOOK_AHEAD (16)

// Read a block
static int block_device_read(const struct lfs_config *cfg, lfs_block_t block, lfs_off_t off, void *buffer, lfs_size_t size) {
    sfd_onchip_t* onchip = (sfd_onchip_t*)cfg->context;
    sfd_onchip_read(onchip, buffer, block * LFS_BLOCK_SIZE + off, size);
    return LFS_ERR_OK;
}

static int block_device_prog(const struct lfs_config *cfg, lfs_block_t block, lfs_off_t off, const void *buffer, lfs_size_t size) {
    sfd_onchip_t* onchip = (sfd_onchip_t*)cfg->context;
    sfd_onchip_write(onchip, buffer, block * LFS_BLOCK_SIZE + off, size);
    return LFS_ERR_OK;
}

static int block_device_erase(const struct lfs_config *cfg, lfs_block_t block) {
    sfd_onchip_t* onchip = (sfd_onchip_t*)cfg->context;
    sfd_onchip_erase(onchip, block * LFS_BLOCK_SIZE, LFS_BLOCK_SIZE);
    return LFS_ERR_OK;
}

static int block_device_sync(const struct lfs_config *cfg) {
    sfd_onchip_t* onchip = (sfd_onchip_t*)cfg->context;
    sfd_onchip_ioctl(onchip, 0x05, NULL);
    return LFS_ERR_OK;
}

typedef struct LFS2 {
    lfs_t lfs;
    struct lfs_config cfg;
    uint8_t read_buffer[LFS_BLOCK_DEVICE_READ_SIZE];
    uint8_t prog_buffer[LFS_BLOCK_DEVICE_PROG_SIZE];
    uint8_t lookahead_buffer[LFS_BLOCK_DEVICE_LOOK_AHEAD];
}LFS2_t;


lfs_t* onchip_lfs_sfd(sfd_onchip_t* onchip) {
    LFS2_t *_lfs = luat_heap_malloc(sizeof(LFS2_t));
    if (_lfs == NULL)
        return NULL;
    lfs_t *lfs = &_lfs->lfs;
    struct lfs_config *lfs_cfg = &_lfs->cfg;

    lfs_cfg->context = onchip,
    // block device operations
    lfs_cfg->read = block_device_read;
    lfs_cfg->prog = block_device_prog;
    lfs_cfg->erase = block_device_erase;
    lfs_cfg->sync = block_device_sync;

    // block device configuration
    lfs_cfg->read_size = LFS_BLOCK_DEVICE_READ_SIZE;
    lfs_cfg->prog_size = LFS_BLOCK_DEVICE_PROG_SIZE;
    lfs_cfg->block_size = LFS_BLOCK_SIZE;
    lfs_cfg->block_count = onchip->block_count;
    lfs_cfg->block_cycles = 200;
    lfs_cfg->cache_size = LFS_BLOCK_DEVICE_CACHE_SIZE;
    lfs_cfg->lookahead_size = LFS_BLOCK_DEVICE_LOOK_AHEAD;

    lfs_cfg->read_buffer = _lfs->read_buffer;
    lfs_cfg->prog_buffer = _lfs->prog_buffer;
    lfs_cfg->lookahead_buffer = _lfs->lookahead_buffer;
    lfs_cfg->name_max = 63;
    lfs_cfg->file_max = 0;
    lfs_cfg->attr_max = 0;

    // ------
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
    luat_heap_free(_lfs);
    return NULL;
    //------
}

#endif
#endif
