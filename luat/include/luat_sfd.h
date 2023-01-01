
#ifndef LUAT_SFD_H
#define LUAT_SFD_H

#include "luat_base.h"

#include "luat_spi.h"
#include "luat_zbuff.h"

typedef struct sdf_opts {
    int (*initialize) (void* userdata);
	int (*status) (void* userdata);
	int (*read) (void* userdata, char* buff, size_t offset, size_t len);
	int (*write) (void* userdata, const char* buff, size_t offset, size_t len);
	int (*erase) (void* userdata, size_t offset, size_t len);
	int (*ioctl) (void* userdata, size_t cmd, void* buff);
}sdf_opts_t;

typedef struct sfd_drv {
    const sdf_opts_t* opts;
    uint8_t type;
    union
    {
        struct sfd_spi {
            int id;
            int cs;
        } spi;
        luat_zbuff_t* zbuff;
    } cfg;
    size_t sector_size;
    size_t sector_count;
    size_t erase_size;
    char chip_id[8];
    void* userdata;
} sfd_drv_t;

typedef struct sfd_onchip {
    char name[8];
    size_t addr;
    size_t block_count;
    size_t block_size;
    //const sdf_opts_t* opts;
}sfd_onchip_t;


// int luat_sfd_init (sfd_drv_t* drv);
int luat_sfd_status (sfd_drv_t* drv);
int luat_sfd_read (sfd_drv_t* drv, char* buff, size_t offset, size_t len);
int luat_sfd_write (sfd_drv_t* drv, const char* buff, size_t offset, size_t len);
int luat_sfd_erase (sfd_drv_t* drv, size_t offset, size_t len);
int luat_sfd_ioctl (sfd_drv_t* drv, size_t cmd, void* buff);

int sfd_onchip_init (void* userdata);
int sfd_onchip_status (void* userdata);
int sfd_onchip_read (void* userdata, char* buff, size_t offset, size_t len);
int sfd_onchip_write (void* userdata, const char* buff, size_t offset, size_t len);
int sfd_onchip_erase (void* userdata, size_t offset, size_t len);
int sfd_onchip_ioctl (void* userdata, size_t cmd, void* buff);

int luat_sfd_onchip_init(void);

// 临时声明
#include "lfs.h"

#define LFS_BLOCK_DEVICE_READ_SIZE (256)
#define LFS_BLOCK_DEVICE_PROG_SIZE (256)
#define LFS_BLOCK_DEVICE_CACHE_SIZE (256)
#define LFS_BLOCK_DEVICE_ERASE_SIZE (4096) // one sector 4KB
#define LFS_BLOCK_DEVICE_TOTOAL_SIZE (64 * 1024)
#define LFS_BLOCK_DEVICE_LOOK_AHEAD (16)

#define LUAT_sfd_lfs_MAX_SIZE (4096)

typedef struct luat_sfd_lfs
{
    char read_buffer[LFS_BLOCK_DEVICE_READ_SIZE];
    char prog_buffer[LFS_BLOCK_DEVICE_PROG_SIZE];
    // char cache_buffer[LFS_BLOCK_DEVICE_CACHE_SIZE];
    char lookahead_buffer[LFS_BLOCK_DEVICE_LOOK_AHEAD];
    lfs_t lfs;
    struct lfs_config conf;
}luat_sfd_lfs_t;


int luat_sfd_lfs_init(sfd_drv_t *drv);

#endif
