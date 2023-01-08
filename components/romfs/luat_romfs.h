#ifndef LUAT_ROMFS_H
#define LUAT_ROMFS_H

#include "luat_base.h"

typedef int (*luat_romfs_read)(void* userdata, char* buff, size_t offset, size_t len);

typedef struct luat_romfs_ctx
{
    void* userdata;
    luat_romfs_read read;
}luat_romfs_ctx;


typedef struct romfs_file
{
    uint8_t next_offset[4];
    uint32_t spec;
    uint8_t size[4];
    uint32_t checksum;
    char name[16];
} romfs_file_t;

typedef struct romfs_fd
{
    romfs_file_t file;
    size_t offset;
    size_t addr;
} romfs_fd_t;


#endif
