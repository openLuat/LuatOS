/******************************************************************************
 *  ADC设备操作抽象层
 *  @author wendal
 *  @since 0.1.5
 *****************************************************************************/
#ifndef Luat_FS
#define Luat_FS
//#include "luat_base.h"
#include "stdio.h"

#ifndef LUAT_WEAK
#define LUAT_WEAK __attribute__((weak))
#endif

typedef struct luat_fs_conf {
    char* busname;
    char* type;
    char* filesystem;
    char* mount_point;
} luat_fs_conf_t;

typedef struct luat_fs_info
{
    char filesystem[8]; // 文件系统类型
    unsigned char type;   // 连接方式, 片上,spi flash, tf卡等
    size_t total_block;
    size_t block_used;
    size_t block_size;
}luat_fs_info_t;


int luat_fs_init(void);

int luat_fs_mkfs(luat_fs_conf_t *conf);
int luat_fs_mount(luat_fs_conf_t *conf);
int luat_fs_umount(luat_fs_conf_t *conf);
int luat_fs_info(const char* path, luat_fs_info_t *conf);

FILE* luat_fs_fopen(const char *filename, const char *mode);
char luat_fs_getc(FILE* stream);
int luat_fs_fseek(FILE* stream, long int offset, int origin);
int luat_fs_ftell(FILE* stream);
int luat_fs_fclose(FILE* stream);
int luat_fs_feof(FILE* stream);
int luat_fs_ferror(FILE *stream);
size_t luat_fs_fread(void *ptr, size_t size, size_t nmemb, FILE *stream);
size_t luat_fs_fwrite(const void *ptr, size_t size, size_t nmemb, FILE *stream);
int luat_fs_remove(const char *filename);
int luat_fs_rename(const char *old_filename, const char *new_filename);
size_t luat_fs_fsize(const char *filename);
int luat_fs_fexist(const char *filename);

// TODO 文件夹相关的API
//int luat_fs_diropen(char const* _FileName);

int luat_fs_mkdir(char const* _DirName);
int luat_fs_rmdir(char const* _DirName);

#endif
