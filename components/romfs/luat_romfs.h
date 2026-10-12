#ifndef LUAT_ROMFS_H
#define LUAT_ROMFS_H

// 标准 romfs(-rom1fs-, genromfs 兼容)只读文件系统
// 镜像生成: tools/romfs/mkromfs.py
// 挂载: luat_fs_conf_t.busname 传 luat_romfs_ctx_t*

#include "luat_base.h"

#ifndef LUAT_ROMFS_MAX_NAME
#define LUAT_ROMFS_MAX_NAME 64      // 单级文件名最大长度(不含NUL), 超长条目跳过
#endif
#ifndef LUAT_ROMFS_MAX_PATH
#define LUAT_ROMFS_MAX_PATH 128     // 路径解析缓冲(含符号链接展开)
#endif
#ifndef LUAT_ROMFS_MAX_DEPTH
#define LUAT_ROMFS_MAX_DEPTH 8      // 符号链接/硬链接链最大解析深度
#endif
#ifndef LUAT_ROMFS_VERIFY_HEAD_CKSUM
#define LUAT_ROMFS_VERIFY_HEAD_CKSUM 1  // mount 时校验镜像头 checksum
#endif
#ifndef LUAT_ROMFS_USE_DIR_CACHE
#define LUAT_ROMFS_USE_DIR_CACHE 1      // mount 时把目录树载入内存缓存(约96B/节点), 0=退回镜像内联表查找(零RAM)
#endif
#ifndef LUAT_ROMFS_MAX_DIR_DEPTH
#define LUAT_ROMFS_MAX_DIR_DEPTH 4      // 目录嵌套深度上限, 超出则 mount 失败
#endif

// 读取回调: 从镜像 offset 读 len 字节到 buff, 成功返回读取字节数, 失败返回负值
// 单次调用 len 保证 <= 16MB
typedef int (*luat_romfs_read)(void* userdata, char* buff, size_t offset, size_t len);

typedef struct luat_romfs_ctx {
    void* userdata;        // 指针模式: 镜像基址; 回调模式: 用户上下文
    luat_romfs_read read;  // NULL=指针模式(memcpy, 支持 mmap 零拷贝); 非NULL=read回调模式
} luat_romfs_ctx_t;

#ifdef LUAT_USE_FS_VFS
extern const struct luat_vfs_filesystem vfs_fs_romfs;
#endif

#endif
