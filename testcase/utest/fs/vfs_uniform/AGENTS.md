# VFS 统一接口 UTest 框架

## 目的

通过 VFS 抽象层（`luat/vfs/luat_vfs.c`）的 **统一 API**（`io.*` / `os.*` / `fs.*` / `io.open`），
对 6 个文件系统（ram / posix / lfs2 / fatfs / tfs / pgfs）跑同一套 30 个用例，
捕获"同一 VFS 接口在 A FS 上能用、在 B FS 上失效"的真实 bug。

**只测 VFS 统一接口，不测 FS 特有 API**（如 `lfs2.mount`, `pgfs.pgfsctl` 等——这些有各自的 C 层 utest）。

## 目录结构

```
testcase/utest/fs/vfs_uniform/scripts/
├── vfs_common.lua        共享助手 + bug 记录器
├── vfs_cases.lua         30 个 test_* 用例 (C01-C30)
├── mount_ram.lua         ram 的 setup() 接口
├── mount_posix.lua
├── mount_lfs2.lua
├── mount_fatfs.lua
├── mount_tfs.lua
├── mount_pgfs.lua
└── metas.json
```

每个 FS 子任务在自己的 worktree 内创建：
```
testcase/utest/fs/vfs_uniform_<fs>/scripts/
├── main.lua                       入口: testrunner.runBatch
├── vfs_uniform_mount.lua          shim: return require("mount_<fs>")
└── metas.json
```

## 运行

```bash
cd build/out
./luatos-lua.exe ../../../testcase/common/scripts/ \
                 ../../../testcase/utest/fs/vfs_uniform/scripts/ \
                 ../../../testcase/utest/fs/vfs_uniform_<fs>/scripts/
```

退出码 0 = 全过；非 0 = 至少一个失败（**预期会失败**，这就是要捕获的 bug）。

## Bug 记录

失败用例在 `docs/known_issues.md` 里追加：
- **Expected**: 一句话
- **Actual**: 一句话
- **Source**: 源文件:行号
- **Repro**: 步骤

## 30 个用例分组

| 组 | 范围 | 用例数 |
|---|---|---|
| A | 基础文件操作 (open/close/read/write/seek/truncate) | C01-C08 |
| B | 目录操作 (mkdir/rmdir/lsdir/dexist) | C09-C13 |
| C | 文件元数据 (exist/fsize/rename/remove) | C14-C18 |
| D | 引用计数 (open 时不允许 remove/rename) | C19-C20 |
| E | 边界 (empty/block-size/长名/嵌套/特殊字符) | C21-C26 |
| F | POSIX flags (w+/r+/binary/closed) | C27-C30 |

详细用例见 `scripts/vfs_cases.lua` 内的注释。
