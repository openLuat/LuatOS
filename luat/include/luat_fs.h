/******************************************************************************
 *  ADC设备操作抽象层
 *  @author wendal
 *  @since 0.1.5
 *****************************************************************************/
#ifndef Luat_FS
#define Luat_FS
#include "luat_base.h"

typedef struct luat_fs_conf {
    char name[8];
    char filesystem[8];
    char mount_point[32];
} luat_fs_conf_t;

int luat_fs_init();

int luat_fs_mount(luat_fs_conf_t *conf);
int luat_fs_umount(luat_fs_conf_t *conf);

int luat_fs_fopen(char const* _FileName, char const* _Mode);
char luat_fs_getc(int fd);
int luat_fs_fseek(int fd, long offset, int origin);
int luat_fs_ftell(int fd);
int luat_fs_fclose(int fd);


// TODO 文件夹相关的API
//int luat_fs_diropen(char const* _FileName);

#endif
