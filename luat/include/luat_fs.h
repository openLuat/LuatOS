/******************************************************************************
 *  ADC设备操作抽象层
 *  @author wendal
 *  @since 0.1.5
 *****************************************************************************/
#ifndef LUAT_FS_H
#define LUAT_FS_H
//#include "luat_base.h"
#include "stdio.h"

#ifndef LUAT_WEAK
#define LUAT_WEAK __attribute__((weak))
#endif

typedef struct luat_fs_conf {
    char* busname;
    char* type;
    char* filesystem;
    const char* mount_point;
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
int luat_fs_getc(FILE* stream);
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


#ifdef LUAT_USE_FS_VFS

#ifndef LUAT_VFS_FILESYSTEM_MAX
#define LUAT_VFS_FILESYSTEM_MAX 4
#endif

#ifndef LUAT_VFS_FILESYSTEM_MOUNT_MAX
#define LUAT_VFS_FILESYSTEM_MOUNT_MAX 4
#endif

#ifndef LUAT_VFS_FILESYSTEM_FD_MAX
#define LUAT_VFS_FILESYSTEM_FD_MAX 16
#endif

struct luat_vfs_file_opts {
    FILE* (*fopen)(void* fsdata, const char *filename, const char *mode);
    int (*getc)(void* fsdata, FILE* stream);
    int (*fseek)(void* fsdata, FILE* stream, long int offset, int origin);
    int (*ftell)(void* fsdata, FILE* stream);
    int (*fclose)(void* fsdata, FILE* stream);
    int (*feof)(void* fsdata, FILE* stream);
    int (*ferror)(void* fsdata, FILE *stream);
    size_t (*fread)(void* fsdata, void *ptr, size_t size, size_t nmemb, FILE *stream);
    size_t (*fwrite)(void* fsdata, const void *ptr, size_t size, size_t nmemb, FILE *stream);
};

struct luat_vfs_filesystem_opts {
    int (*remove)(void* fsdata, const char *filename);
    int (*rename)(void* fsdata, const char *old_filename, const char *new_filename);
    size_t (*fsize)(void* fsdata, const char *filename);
    int (*fexist)(void* fsdata, const char *filename);
    int (*mkfs)(void* fsdata, luat_fs_conf_t *conf);

    int (*mount)(void** fsdata, luat_fs_conf_t *conf);
    int (*umount)(void* fsdata, luat_fs_conf_t *conf);
    int (*info)(void* fsdata, const char* path, luat_fs_info_t *conf);

    int (*mkdir)(void* fsdata, char const* _DirName);
    int (*rmdir)(void* fsdata, char const* _DirName);
};

typedef struct luat_vfs_filesystem {
    char name[16];
    struct luat_vfs_filesystem_opts opts;
    struct luat_vfs_file_opts fopts;
}luat_vfs_filesystem_t;

typedef struct luat_vfs_mount {
    struct luat_vfs_filesystem *fs;
    void *userdata;
    char prefix[16];
    int ok;
} luat_vfs_mount_t;

typedef struct luat_vfs_fd{
    FILE* fd;
    luat_vfs_mount_t *fsMount;
}luat_vfs_fd_t;


typedef struct luat_vfs
{
    struct luat_vfs_filesystem* fsList[LUAT_VFS_FILESYSTEM_MAX];
    luat_vfs_mount_t mounted[LUAT_VFS_FILESYSTEM_MOUNT_MAX];
    luat_vfs_fd_t fds[LUAT_VFS_FILESYSTEM_FD_MAX+1];
}luat_vfs_t;

int luat_vfs_init(void* params);
int luat_vfs_reg(const struct luat_vfs_filesystem* fs);
FILE* luat_vfs_add_fd(FILE* fd, luat_vfs_mount_t * mount);
int luat_vfs_rm_fd(FILE* fd);
const char* luat_vfs_mmap(FILE* fd);
#endif

#endif
