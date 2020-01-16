
#ifndef Luat_FS
#define Luat_FS
#include "luat_base.h"

typedef struct luat_fs_conf {
    char name[8];
    char filesystem[8];
    char mount_point[32];
} luat_fs_conf_t;

typedef struct luat_fs {
    luat_fs_conf_t conf;
} luat_fs_t;

typedef struct luat_file {
    luat_fs *fs;
    void* ptr;
} luat_file_t;

int luat_fs_init();
luat_fs* luat_fs_mount(luat_fs_conf_t *conf);
luat_fs* luat_fs_umount(luat_fs_conf_t *conf);

luat_file_t luat_fs_fopen(luat_fs_t *fs, char const* _FileName, char const* _Mode);
uint8_t luat_fs_getc(luat_fs_t *fs, luat_file_t* f);
uint8_t luat_fs_fseek(luat_fs_t *fs, luat_file_t* f, long offset, int origin);
uint32_t luat_fs_ftell(luat_fs_t *fs,luat_file_t* f);
uint8_t luat_fs_fclose(luat_fs_t *fs,luat_file_t* f);

#endif