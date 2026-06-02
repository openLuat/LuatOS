# S-06: fexist/fsize 快速路径 (`luat_lfs2_stat` 替代 `open/close`)

**Task ID**: S-06  
**Date**: 2026-06-02  
**Worktree**: `D:\github\LuatOS\.worktrees\fix-storage-quickwins\`  
**Audit ref**: `docs/audit/track_d_lfs2_nand.md` D-05

---

## 改动文件

| File | Change |
|------|--------|
| `components/luat_lfs2_nand/luat_fs_lfs2_nand.c` | `luat_vfs_lfs2_nand_base_fexist` / `luat_vfs_lfs2_nand_base_fsize` 加 `luat_lfs2_stat` 快路径,原 `open/close` 路径保留为兜底 |
| `components/luat_lfs2_nand/luat_fs_lfs2_nand_profile.c` | 不改 (wrapper 自动继承,无 static cache 状态) |

---

## 关键 diff (`luat_fs_lfs2_nand.c` 192-243)

### before

```c
int luat_vfs_lfs2_nand_base_fexist(void* userdata, const char *filename) {
    FILE* fd = luat_vfs_lfs2_nand_base_fopen(userdata, filename, "rb");
    if (fd) {
        luat_vfs_lfs2_nand_base_fclose(userdata, fd);
        return 1;
    }
    return 0;
}

size_t luat_vfs_lfs2_nand_base_fsize(void* userdata, const char *filename) {
    FILE *fd;
    size_t size = 0;
    fd = luat_vfs_lfs2_nand_base_fopen(userdata, filename, "rb");
    if (fd) {
        size = luat_lfs2_file_size((luat_lfs2_t*)userdata, (luat_lfs2_file_t*)fd);
        luat_vfs_lfs2_nand_base_fclose(userdata, fd);
    }
    return size;
}
```

### after

```c
int luat_vfs_lfs2_nand_base_fexist(void* userdata, const char *filename) {
    // Fast path: luat_lfs2_stat reads dirent metadata only, no file handle and
    // no write-cache slot allocation. This is what littlefs's stat() is for.
    luat_lfs2_t* fs = (luat_lfs2_t*)userdata;
    struct luat_lfs2_info info;
    uint64_t start_us = luat_vfs_lfs2_nand_base_now_us();
    int stat_ret = luat_lfs2_stat(fs, filename, &info);
    uint64_t cost_us = luat_vfs_lfs2_nand_base_now_us() - start_us;
    if (cost_us >= LFS2_TRACE_SLOW_US || stat_ret < 0) {
        LFS2N_CORE_TRACE("LFS2_TRACE_FEXIST stat ret=%d cost_us=%llu",
                         stat_ret, (unsigned long long)cost_us);
    }
    if (stat_ret == 0 && info.type == LFS_TYPE_REG) {
        return 1;
    }
    // Fallback: original open/close path. Preserves the historical
    // "regular file only" semantics — directories still return 0,
    // matching the previous fopen("rb") + LFS_ERR_ISDIR behaviour.
    FILE* fd = luat_vfs_lfs2_nand_base_fopen(userdata, filename, "rb");
    if (fd) {
        luat_vfs_lfs2_nand_base_fclose(userdata, fd);
        return 1;
    }
    return 0;
}

size_t luat_vfs_lfs2_nand_base_fsize(void* userdata, const char *filename) {
    // Fast path: see fexist above. dir_find + dir_getinfo only, no file handle.
    luat_lfs2_t* fs = (luat_lfs2_t*)userdata;
    struct luat_lfs2_info info;
    uint64_t start_us = luat_vfs_lfs2_nand_base_now_us();
    int stat_ret = luat_lfs2_stat(fs, filename, &info);
    uint64_t cost_us = luat_vfs_lfs2_nand_base_now_us() - start_us;
    if (cost_us >= LFS2_TRACE_SLOW_US || stat_ret < 0) {
        LFS2N_CORE_TRACE("LFS2_TRACE_FSIZE stat ret=%d cost_us=%llu",
                         stat_ret, (unsigned long long)cost_us);
    }
    if (stat_ret == 0 && info.type == LFS_TYPE_REG) {
        return info.size;
    }
    // Fallback: original open/close + luat_lfs2_file_size path.
    FILE *fd;
    size_t size = 0;
    fd = luat_vfs_lfs2_nand_base_fopen(userdata, filename, "rb");
    if (fd) {
        size = luat_lfs2_file_size((luat_lfs2_t*)userdata, (luat_lfs2_file_t*)fd);
        luat_vfs_lfs2_nand_base_fclose(userdata, fd);
    }
    return size;
}
```

函数签名未变 (`int fexist` / `size_t fsize`)。`luat_lfs2.h` 已在文件顶部包含 (line 15),`struct luat_lfs2_info` 和 `LFS_TYPE_REG` 来自该头,无需新 `#include`。

`profile.c` 的 wrapper (line 485-491) 是简单透传,不持有 static cache 状态,自动继承新行为。

---

## Build tail

```
[pc-build] mode=summary clean=False arch=x86 vm64=0 gui=n mgba=n
[pc-build] configure: xmake f -a x86 -y -p windows --toolchain=msvc
[pc-build] configure completed without visible warnings
[pc-build] build: xmake -y
[pc-build] build emitted 131 visible warning line(s)
[pc-build] build warning codes: C4133 x59, C4828 x23, C4090 x14, C4113 x10, C4047 x9, C4005 x5, C4024 x5, C4022 x3
[pc-build] build warning areas: components x124, bsp/pc x5, luat x1, other x1
[pc-build] Build completed successfully
```

警告全在其它文件 (`lwipopts.h` / `mqttcore.c` / `ymodem.c` / `mobile.c` / `sms.c` / `uart_drv_win32.c` 等),pre-existing。  
本文件编译无 warning:日志中 `luat_fs_lfs2_nand.c` 仅出现一次,对应 `compiling.release` 行,无 warning 行。

回归对照:master build 与本 worktree build 跑 `lfs2n_regression_basic` 结果完全一致 (2 passed, 5 failed,后者均为 `lf.init` 环境问题,非本次改动相关)。

---

## 设计说明

**为什么用 `luat_lfs2_stat` 而不是 `lfs2_open+file_size`?**

`luat_lfs2_stat` 内部只走 `luat_lfs2_dir_find` + `luat_lfs2_dir_getinfo` (`luat_lfs2.c:6123` 调 `luat_lfs2_stat_` @ line 3927),只读 dirent 元数据块:
- 不分配 `luat_lfs2_file_t` handle (避免 `luat_heap_malloc` + 后续 `luat_heap_free`)
- 不进入 write cache pool (`g_lfs2_nand_write_cache[]` 8 slots 不会被占用/释放)
- 不动 `lfs->mlist` 链表
- 不触发 CTZ skiplist 中的 prog buffer

相反 `fopen("rb")` → `luat_lfs2_file_open` 必须 alloc file struct、走 cache 分配、`luat_lfs2_file_close` 又要走 `file_sync`(即使是 RDONLY)+ 释放 cache slot。对纯查询 (`io.exists` / `io.fs`) 而言完全是浪费。`io.exists` 在 Lua 脚本里被广泛使用,大量场景下会累计显著开销 (D-05 审计结论)。

**为什么保留 `open/close` 兜底?**

三个原因:
1. **行为兼容性**:原实现对 `directory` 路径返回 0 (因为 `fopen("rb")` 在 littlefs 上会 `LFS_ERR_ISDIR`)。`stat` 对 dir 路径会成功且 `info.type == LFS_TYPE_DIR`,如果直接当"存在"返回会破坏历史语义。`type == LFS_TYPE_REG` 守护 + 兜底保留了原行为。
2. **未知边界条件**:littlefs `stat` 在 mount 异常恢复、metadata 损坏等场景下的行为我没完全审计;保留 open 路径作为最后兜底,避免引入新回归。
3. **零风险**:两条路径互斥 (stat 成功用 stat;stat 失败走 open),`stat` 成功但 type 不匹配的场景会原样掉进兜底,行为退化路径已与 master 完全一致。
