# TFS — 微型文件系统

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Language: C99](https://img.shields.io/badge/Language-C99-green.svg)]()
[![Tests: 110/110](https://img.shields.io/badge/Tests-110%2F110%20PASS-brightgreen.svg)]()

一个可移植的、面向裸机/RTOS 的 NAND 闪存文件系统，采用 C99 编写。TFS 是对 YAFFS2 算法的全面重写，专注于性能、可移植性和生产可靠性，不依赖任何 Linux 内核头文件。

---

## 特性

- **POSIX 风格 API** — `open`、`read`、`write`、`lseek`、`mkdir`、`readdir`、`symlink`、`link`、`stat`、`fstat`、`rename`、`unlink`、`truncate`、`dup`
- **内联标签支持（Inband Tags）** — 适用于无 OOB 暴露的 SPI NAND 设备
- **检查点/快速挂载** — 卸载时将文件系统状态序列化到 NAND；重新挂载仅需毫秒级时间
- **块内摘要页** — 大容量设备挂载扫描时间大幅缩短
- **软件 Hamming ECC** — 每 256 字节扇区 1 位纠错、2 位检测
- **贪心垃圾回收器** — 后台 GC，可从空闲任务调用
- **硬链接、软链接、稀疏文件、大文件**（多级 tnode 树）
- **纯 C99** — 直接使用 `uint8_t`/`uint32_t` 等标准类型，无自定义类型别名
- **无操作系统依赖** — 仅使用 `malloc`、`free`、`memcpy`、`memset`、`strlen`
- **极小占用** — 适合 RAM ≥ 64 KB 的 MCU

---

## 架构

```
┌─────────────────────────────────────────────────────────────┐
│  应用层                                                      │
├─────────────────────────────────────────────────────────────┤
│  inc/tfs.h           公共 POSIX 风格 API                    │
├──────────────┬──────────────┬───────────────────────────────┤
│  tfs_fs.c    │  tfs_dir.c   │  tfs_verify.c                 │
│  (POSIX API) │  (目录操作)  │  (完整性检查)                 │
├──────────────┴──────────────┴───────────────────────────────┤
│  tfs_core.c    格式化 / 挂载 / 卸载 / GC 编排               │
├────────────┬─────────────┬──────────────┬───────────────────┤
│ tfs_inode.c│ tfs_block.c │ tfs_cache.c  │ tfs_checkpoint.c  │
│ (对象管理) │ (分配/擦除) │ (写缓存)     │ (快速挂载)        │
├────────────┴─────────────┴──────────────┴───────────────────┤
│  tfs_tnode.c  tfs_tags.c  tfs_ecc.c  tfs_summary.c         │
├─────────────────────────────────────────────────────────────┤
│  inc/tfs_port.h       驱动/OS 移植接口                      │
│  port/tfs_port.c      示例：FreeRTOS / 裸机                 │
└─────────────────────────────────────────────────────────────┘
```

### 关键文件

| 文件 | 用途 |
|------|------|
| `inc/tfs.h` | 用户代码唯一需要包含的头文件 |
| `inc/tfs_types.h` | 枚举、结构体、错误码 |
| `inc/tfs_config.h` | 编译期配置宏 |
| `inc/tfs_port.h` | 驱动/OS 移植接口（`tfs_drv_t`、`tfs_geo_t`） |
| `src/tfs_core.c` | 格式化、挂载、卸载、GC、检查点编排 |
| `src/tfs_fs.c` | POSIX API 实现 |
| `src/tfs_inode.c` | 对象生命周期、哈希表、头部 I/O |
| `src/tfs_block.c` | 块/chunk 分配、擦除、读写 |
| `src/tfs_tnode.c` | Tnode 树（chunk 到对象的映射） |
| `src/tfs_cache.c` | 写缓存 |
| `src/tfs_checkpoint.c` | 快速挂载检查点（对象序列化到 NAND） |
| `src/tfs_summary.c` | 块内摘要页 |
| `src/tfs_tags.c` | 标签打包/解包（OOB + 内联） |
| `src/tfs_ecc.c` | 软件 Hamming ECC |
| `src/tfs_dir.c` | 目录操作 |
| `src/tfs_verify.c` | 文件系统完整性检查 |
| `port/tfs_port.c` | 示例移植（FreeRTOS / 裸机） |
| `test/tfs_test.c` | 110 项测试套件（T01–T28） |
| `test/tfs_ram_nand.c` | 主机测试用 RAM NAND 模拟器 |

---

## 快速入门 — 移植指南

### 1. 实现驱动回调

复制 `port/tfs_port.c` 并填写五个 NAND 回调函数：

```c
#include "tfs_port.h"

static int my_write_page(void *ctx, uint32_t page,
                         const uint8_t *data, uint32_t data_len,
                         const uint8_t *oob,  uint32_t oob_len) { ... }

static int my_read_page(void *ctx, uint32_t page,
                        uint8_t *data, uint32_t data_len,
                        uint8_t *oob,  uint32_t oob_len) { ... }

static int my_erase_block(void *ctx, uint32_t block) { ... }
static int my_mark_bad   (void *ctx, uint32_t block) { ... }
static int my_check_bad  (void *ctx, uint32_t block) { ... }
```

### 2. 配置几何参数

```c
tfs_geo_t geo = {
    .total_blocks         = 1024,
    .pages_per_block      = 64,
    .data_bytes_per_page  = 2048,
    .spare_bytes_per_page = 64,
    .inband_tags          = 0,   /* SPI NAND 无 OOB 时置 1 */
};
```

### 3. 注册并挂载

```c
tfs_drv_t drv = { /* 填写回调 + geo */ };
tfs_add_device("nand0", &drv, &geo);

tfs_init();
tfs_mount("nand0");           /* 首次使用先调用 tfs_format("nand0") */
```

### 4. 使用文件系统

```c
int fd = tfs_open("/data/log.txt", TFS_O_WRONLY | TFS_O_CREAT, 0644);
tfs_write(fd, buf, len);
tfs_close(fd);
tfs_unmount("nand0");
```

---

## API 参考

### 生命周期

| 函数 | 说明 |
|------|------|
| `tfs_init()` | 所有其他 API 调用前必须先调用一次 |
| `tfs_add_device(name, drv, geo)` | 注册 NAND 设备 |
| `tfs_remove_device(name)` | 注销设备（需先卸载） |
| `tfs_format(name)` | 擦除并初始化文件系统 |
| `tfs_mount(name)` | 挂载（若有检查点则从检查点恢复） |
| `tfs_unmount(name)` | 刷新、写入检查点、卸载 |
| `tfs_sync(name)` | 将写缓存刷新到 NAND |
| `tfs_bg_gc(name)` | 执行一次 GC（从空闲任务调用） |

### 文件 I/O

| 函数 | 说明 |
|------|------|
| `tfs_open(path, flags, mode)` | 打开/创建文件；返回 fd ≥ 0 |
| `tfs_close(fd)` | 刷新并关闭 |
| `tfs_read(fd, buf, n)` | 读取最多 n 字节；返回实际读取字节数 |
| `tfs_write(fd, buf, n)` | 写入 n 字节；返回实际写入字节数 |
| `tfs_lseek(fd, offset, whence)` | 调整文件偏移 |
| `tfs_fsync(fd)` | 将数据刷新到 NAND |
| `tfs_dup(fd)` | 复制文件描述符 |
| `tfs_ftruncate(fd, size)` | 调整已打开文件大小 |
| `tfs_truncate(path, size)` | 按路径调整文件大小 |
| `tfs_unlink(path)` | 删除文件 |
| `tfs_rename(old, new)` | 重命名/移动 |

### 状态查询

| 函数 | 说明 |
|------|------|
| `tfs_stat(path, st)` | 按路径查询（跟随符号链接） |
| `tfs_lstat(path, st)` | 按路径查询（不跟随符号链接） |
| `tfs_fstat(fd, st)` | 查询已打开文件描述符 |

### 目录

| 函数 | 说明 |
|------|------|
| `tfs_mkdir(path, mode)` | 创建目录 |
| `tfs_rmdir(path)` | 删除空目录 |
| `tfs_opendir(path)` | 打开目录；返回 dfd ≥ 0 |
| `tfs_readdir(dfd, de)` | 填充目录项；1=有项目，0=结束，-1=错误 |
| `tfs_closedir(dfd)` | 关闭目录句柄 |

### 链接与空间

| 函数 | 说明 |
|------|------|
| `tfs_symlink(target, linkpath)` | 创建符号链接 |
| `tfs_readlink(path, buf, size)` | 读取符号链接目标 |
| `tfs_link(oldpath, newpath)` | 创建硬链接 |
| `tfs_freespace(name)` | 设备可用字节数 |
| `tfs_totalspace(name)` | 设备总字节数 |
| `tfs_get_error()` | 最近一次错误码（`TFS_E*`） |

### 打开标志

| 标志 | 值 | 含义 |
|------|----|------|
| `TFS_O_RDONLY` | 0x0000 | 只读 |
| `TFS_O_WRONLY` | 0x0001 | 只写 |
| `TFS_O_RDWR` | 0x0002 | 读写 |
| `TFS_O_CREAT` | 0x0040 | 不存在则创建 |
| `TFS_O_EXCL` | 0x0080 | 已存在则失败（与 O_CREAT 配合） |
| `TFS_O_TRUNC` | 0x0200 | 打开时截断为零 |
| `TFS_O_APPEND` | 0x0400 | 始终在末尾写入 |

---

## 配置参考（`inc/tfs_config.h`）

| 宏 | 默认值 | 说明 |
|----|--------|------|
| `TFS_MAX_OPEN_FILES` | 16 | 最大同时打开文件描述符数 |
| `TFS_MAX_OPEN_DIRS` | 8 | 最大同时打开目录句柄数 |
| `TFS_MAX_NAME_LEN` | 255 | 文件名最大字节长度 |
| `TFS_MAX_DEVICES` | 4 | 最大注册 NAND 设备数 |
| `TFS_OBJ_BUCKETS` | 256 | 对象查找哈希表桶数 |
| `TFS_OBJ_ID_FIRST_USER` | 0x100 | 用户文件起始对象 ID |
| `TFS_CACHE_CHUNKS` | 10 | 每设备写缓存槽数 |
| `TFS_SUMMARY_ENABLED` | 1 | 启用块内摘要页 |
| `TFS_CHECKPOINT_ENABLED` | 1 | 启用快速挂载检查点 |
| `TFS_ECC_ENABLED` | 1 | 启用软件 Hamming ECC |
| `TFS_INBAND_TAGS` | 0 | 默认内联标签模式（可按设备覆盖） |

---

## 测试结果

测试套件共 28 组、110 项检查，均使用 RAM 支持的 NAND 模拟器运行。

```
┌────────────────────────────────────────────────────────┐
│ 测试组                                        │ 结果    │
├────────────────────────────────────────────────────────┤
│ T01: 格式化                                   │  3/3    │
│ T02: 文件读写                                 │  5/5    │
│ T03: 目录操作                                 │  4/4    │
│ T04: 文件删除                                 │  2/2    │
│ T05: 重命名                                   │  3/3    │
│ T06: 持久化（重新挂载）                       │  2/2    │
│ T07: 垃圾回收                                 │  1/1    │
│ T08: 完整性验证                               │  1/1    │
│ T09: 内联标签持久化                           │  3/3    │
│ T10: 无格式挂载                               │  5/5    │
│ T11: 性能基准                                 │  0/0    │
│ T12: POSIX 文件 API                           │  9/9    │
│ T13: lseek                                    │  5/5    │
│ T14: stat/fstat/lstat                         │  7/7    │
│ T15: opendir/readdir/closedir                 │  4/4    │
│ T16: ftruncate/truncate                       │  6/6    │
│ T17: O_TRUNC 和 O_APPEND                      │  2/2    │
│ T18: 符号链接                                 │  4/4    │
│ T19: 硬链接                                   │  5/5    │
│ T20: 大文件（多级 tnode）                     │  4/4    │
│ T21: 稀疏文件                                 │  5/5    │
│ T22: 重命名边界情况                           │  7/7    │
│ T23: 错误码                                   │  5/5    │
│ T24: 磁盘空间                                 │  4/4    │
│ T25: 模式文件 + 重挂载完整性                  │  3/3    │
│ T26: 深层目录树                               │  4/4    │
│ T27: GC 压力测试                              │  3/3    │
│ T28: 压力测试                                 │  4/4    │
├────────────────────────────────────────────────────────┤
│ 合计                                          │ 110/110 │
└────────────────────────────────────────────────────────┘
```

### 性能（T11 — RAM NAND 模拟器，64 块 × 64 页 × 2048 字节）

| 操作 | 耗时 |
|------|------|
| 格式化（64 块 × 64 页） | 2.0 ms |
| 写入 128 KB | < 1 ms |
| 检查点写入（sync/unmount） | < 1 ms |
| 检查点恢复（remount） | < 1 ms |
| 读取 128 KB | < 1 ms |
| 单次 GC | < 1 ms |

> 注：以上时间反映 RAM 模拟器性能；实际 NAND 速度受限于闪存写入延迟。

---

## 许可证

MIT — 详见 [LICENSE](LICENSE)。
