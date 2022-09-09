
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
} sfd_drv_t;

typedef struct sfd_onchip {
    char name[8];
    size_t addr;
    size_t block_count;
    size_t block_size;
    //const sdf_opts_t* opts;
}sfd_onchip_t;

#endif
