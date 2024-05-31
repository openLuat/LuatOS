/******************************************************************************
 *  文件系统操作抽象层
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
/**
 * @defgroup luat_fs 文件系统接口
 * @{
 */
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

/**
 * @brief 文件系统初始化
 * @return int =0成功，其他失败
 */
int luat_fs_init(void);
/**
 * @brief 文件系统格式化
 * @return int =0成功，其他失败
 */
int luat_fs_mkfs(luat_fs_conf_t *conf);
/**
 * @brief 文件系统挂载
 * @return int =0成功，其他失败
 */
int luat_fs_mount(luat_fs_conf_t *conf);
/**
 * @brief 文件系统取消挂载
 * @return int =0成功，其他失败
 */
int luat_fs_umount(luat_fs_conf_t *conf);

/**
 * @brief 获取文件系统状态
 * @param path[IN] 挂载路径, 通常为 /
 * @param info[OUT] 文件系统信息
 * @return int =0成功，其他失败
 */
int luat_fs_info(const char* path, luat_fs_info_t *conf);

/**
 * @brief 打开文件,类似于fopen
 * @param filename[IN] 文件路径
 * @param mode[IN] 打开模式,与posix类型, 例如 "r" "rw" "w" "w+" "a"
 * @return FILE* 文件句柄,失败返回NULL
 */

FILE* luat_fs_fopen(const char *filename, const char *mode);


/**
 * @brief 读到单个字节,类似于getc
 * @param stream[IN] 文件句柄
 * @return int >=0读取成功返回, -1失败, 例如读取到文件尾部
 */

int luat_fs_getc(FILE* stream);

/**
 * @brief 设置句柄位置,类似于fseek
 * @param stream[IN] 文件句柄
 * @param offset[IN] 偏移量
 * @param origin[IN] 参考点, 例如 SEEK_SET 绝对坐标, SEEK_END 结尾, SEEK_CUR 当前
 * @return int >=0成功,否则失败
 */
int luat_fs_fseek(FILE* stream, long int offset, int origin);
/**
 * @brief 获取句柄位置,类似于ftell
 * @param stream[IN] 文件句柄
 * @return int >=0当前位置, 否则失败
 */
int luat_fs_ftell(FILE* stream);

/**
 * @brief 关闭句柄位置,类似于fclose
 * @param stream[IN] 文件句柄
 * @return int =0成功,否则失败
 */
int luat_fs_fclose(FILE* stream);
/**
 * @brief 是否已经到文件结尾,类似于feof
 * @param stream[IN] 文件句柄
 * @return int =0未到文件尾部,其余为到达文件尾部
 */
int luat_fs_feof(FILE* stream);
/**
 * @brief 是否有文件系统错误,类似于ferror
 * @param stream[IN] 文件句柄
 * @return int =0无错误, 其余为错误值
 */
int luat_fs_ferror(FILE *stream);
/**
 * @brief 读取文件,类似于fread
 * @param ptr[OUT] 存放读取数据的缓冲区
 * @param size[IN] 单次读取大小
 * @param nmemb[IN] 读取次数
 * @param stream[IN] 文件句柄
 * @return int >=0实际读取的数量,<0出错
 */
size_t luat_fs_fread(void *ptr, size_t size, size_t nmemb, FILE *stream);
/**
 * @brief 写入文件,类似于fwrite
 * @param ptr[OUT] 存放写入数据的缓冲区
 * @param size[IN] 单次读取大小
 * @param nmemb[IN] 读取次数
 * @param stream[IN] 文件句柄
 * @return int >=0实际写入的数量,<0出错
 */

size_t luat_fs_fwrite(const void *ptr, size_t size, size_t nmemb, FILE *stream);

int luat_fs_fflush(FILE *stream);

/**
 * @brief 删除文件,类似于remove
 * @param filename[IN] 文件路径
 * @return int =0成功,否则失败
 */
int luat_fs_remove(const char *filename);
/**
 * @brief 文件改名,类似于rename
 * @param old_filename[IN] 原文件路径
 * @param new_filename[IN] 新文件路径
 * @return int =0成功,否则失败
 */

int luat_fs_rename(const char *old_filename, const char *new_filename);
/**
 * @brief 文件大小,类似于fsize
 * @param filename[IN] 文件路径
 * @return int >=0文件大小, 如果文件不存在也是返回0
 */

size_t luat_fs_fsize(const char *filename);

/**
 * @brief 文件是否存在,类似于fexist
 * @param filename[IN] 文件路径
 * @return int =0不存在,否则存在
 */
int luat_fs_fexist(const char *filename);
/**
 * @brief 行读取
 * @param buf[OUT] 读取缓冲区
 * @param bufsize[IN] 缓冲区大小
 * @param stream[IN] 文件句柄
 * @return int >=0实际写入的数量,<0出错
 */
int luat_fs_readline(char * buf, int bufsize, FILE * stream);

/**
 * @brief 获取文件映射地址
 * @param stream[IN] 文件句柄
 * @return void* 文件地址
 */
void* luat_fs_mmap(FILE * stream);

// TODO 文件夹相关的API
//int luat_fs_diropen(char const* _FileName);

typedef struct luat_fs_dirent
{
    unsigned char d_type; //0:文件；1：文件夹
    char d_name[255];
    size_t d_size;
}luat_fs_dirent_t;


/**
 * @brief 创建文件夹
 * @param _DirName[IN] 文件夹路径
 * @return int =0成功,否则失败
 */
int luat_fs_mkdir(char const* _DirName);
/**
 * @brief 删除文件夹,必须为空文件夹
 * @param _DirName[IN] 文件夹路径
 * @return int =0成功,否则失败
 */
int luat_fs_rmdir(char const* _DirName);

/**
 * @brief 遍历文件夹
 * @param _DirName[IN] 文件夹路径
 * @param ents[OUT] 文件列表,必须已分配内存,且不小于len个元素
 * @param offset[IN] 跳过多少个文件
 * @param len[IN] 最多读取多少个文件
 * @return int =>0读取到文件个数,否则失败
 */

int luat_fs_lsdir(char const* _DirName, luat_fs_dirent_t* ents, size_t offset, size_t len);


/**
 * @brief 文件截断
 * @param filename[IN] 文件名
 * @param len[IN] 长度
 * @return int =>0读取到文件个数,否则失败
 */
int luat_fs_truncate(const char* filename, size_t len);
/**
 * @brief 文件夹是否存在
 * @param dir[IN] 文件夹名称
 * @return int =0不存在,否则存在
 */
int luat_fs_dexist(const char *dir);
/** @}*/
#ifdef LUAT_USE_FS_VFS

#ifndef LUAT_VFS_FILESYSTEM_MAX
#define LUAT_VFS_FILESYSTEM_MAX 8
#endif

#ifndef LUAT_VFS_FILESYSTEM_MOUNT_MAX
#define LUAT_VFS_FILESYSTEM_MOUNT_MAX 8
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
    void* (*mmap)(void* fsdata, FILE *stream);
    int (*fflush)(void* fsdata, FILE *stream);
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
    int (*lsdir)(void* fsdata, char const* _DirName, luat_fs_dirent_t* ents, size_t offset, size_t len);

    int (*truncate)(void* fsdata, char const* _DirName, size_t nsize);
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
