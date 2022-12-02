
#ifndef LUAT_LUADB_H
#define LUAT_LUADB_H

// LuaDB只读文件系统

// 当前最新版本v2, Luatools 2.1.3及以上默认生成
#define LUAT_LUADB_MIN_VERSION 2

// 可同时打开的文件数量
#ifndef LUAT_LUADB_MAX_OPENFILE
#define LUAT_LUADB_MAX_OPENFILE 8
#endif

// 单个文件的数据结构
typedef struct luadb_file {
    char name[32]; // 最大路径长度为31字节
    size_t size;   // 最大体积为64kb
    const char* ptr; // 指向文件数据的起始位
} luadb_file_t;

// 文件句柄
typedef struct luadb_fd
{
    int fd;             // 句柄编号
    luadb_file_t *file; // 文件指针
    size_t fd_pos;      // 句柄的当前偏移量
}luadb_fd_t;

typedef struct luadb_fs
{
    uint16_t version;  // 文件系统版本号,当前支持v1/v2
    uint16_t filecount; // 文件总数,实际少于100
    luadb_fd_t fds[LUAT_LUADB_MAX_OPENFILE]; // 句柄数组
    // luadb_file_t *inlines;
    luadb_file_t files[1]; // 文件数组
} luadb_fs_t;

// 从指定位置查询并构建文件系统
luadb_fs_t* luat_luadb_mount(const char* ptr);
//  卸载文件系统,之后fs不可用
int luat_luadb_umount(luadb_fs_t *fs);
// 重新挂载文件系统,只是强制清空全部句柄
int luat_luadb_remount(luadb_fs_t *fs, unsigned flags);
// 打开文件
int luat_luadb_open(luadb_fs_t *fs, const char *path, int flags, int /*mode_t*/ mode);
// 关闭文件
int luat_luadb_close(luadb_fs_t *fs, int fd);
// 读数据
size_t luat_luadb_read(luadb_fs_t *fs, int fd, void *dst, size_t size);
//size_t luat_luadb_write(void *fs, int fd, const void *data, size_t size);
// 移动句柄
long luat_luadb_lseek(luadb_fs_t *fs, int fd, long /*off_t*/ offset, int mode);
// 获取文件信息
luadb_file_t* luat_luadb_stat(luadb_fs_t *fs, const char *path);
// 获取文件起始指针,通常只读
char* luat_luadb_direct_io(luadb_fs_t *fs, int fd, size_t *len);

#endif
