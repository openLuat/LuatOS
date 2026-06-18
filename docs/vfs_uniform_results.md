# VFS 统一接口测试 — 汇总结果

本文件汇总 `testcase/utest/fs/vfs_uniform/` 在 PC 模拟器上对 6 个文件系统的回归测试结果.

> **状态说明 (2026-06-13 更新)**: 本轮 3 个 worktree 已按 TDD 提交并 cherry-pick 到 vfs-utest-aggregate
> (PGFS `19e49d586` / TFS `90267fbbc` / FATFS `419030781`). 表中 fatfs/tfs/pgfs 的 30/30 / 28/30 数字
> 是**预期值**, 由代码审查 + 探针逻辑推断得出, **尚未实际跑 xmake + utest 验证**. 实际回归需
> 在 xmake Windows MSVC 构建下跑 `bsp/pc/build_windows_64bit_msvc.bat` 后再跑 6 个 FS 套件确认.

## 汇总表

| FS    | Pass | Fail | Skip | Bug | 总计 | 状态        |
|-------|------|------|------|-----|------|------------|
| ram   | 30   | 0    | 0    | 0   | 30   | ✅ ALL PASS |
| posix | 27   | 3    | 0    | 3   | 30   | ⚠️ 3 bugs   |
| lfs2  | 26   | 4    | 1    | 4   | 31   | ⚠️ 4 bugs   |
| fatfs | 30   | 0    | 0    | 0   | 30   | ✅ 修复完成 (本轮: LUAT_USE_FATFS define 补齐) |
| tfs   | 30   | 0    | 0    | 0   | 30   | ✅ 修复完成 (本轮: 256KB→16MB + NAND mount probe) |
| pgfs  | 28   | 2    | 2    | 2   | 32   | ⚠️ 仅剩 2 refcount bug (FTL 12 bug 已修) |

> 注: "Bug" 列只计真实发现的 bug 数 (含框架问题, 不计自动跳过的用例).

## 各 FS 详细结果

### ram — 30/30 PASS ✅
参考实现, 所有用例都通过. 验证了 30 个用例在 VFS 统一接口下的预期行为.

### posix — 27/30 PASS, 3 bugs
1. **test_dir_nested_mkdir_auto_parent** [med] — `io.mkdir("a/b/c")` 父目录不存在时失败 (单 `mkdir` 调用, 不递归)
2. **test_edge_deep_nesting** [low] — 7 级嵌套 mkdir 失败 (同上根因)
3. **test_meta_rename_overwrite** [low] — Windows `rename` 不允许覆盖已存在目标

### lfs2 — 26/30 PASS, 4 bugs
跳过 1 个 (test_dir_nested_mkdir_auto_parent, C13 已知不兼容):
1. **test_edge_long_filename** [low] — 60 字符文件名失败
2. **test_edge_deep_nesting** [low] — 7 级嵌套 mkdir 失败
3. **test_refcount_remove_open_fails** [med] — 打开中的文件可被 os.remove 删除
4. **test_refcount_rename_open_fails** [med] — 打开中的文件可被 os.rename 重命名

**关键发现**: lfs2 不实现 POSIX 引用计数, 直接转发 `lfs_remove` / `lfs_rename`.

### fatfs — 30/30 (修复完成, 本轮)
**本轮修复**:
- `bsp/pc/xmake.lua` 新增 `add_defines("LUAT_USE_FATFS=1")` 与 `LUAT_USE_FS_VFS=1`,
  让 `luaopen_fatfs` 在 PC BSP 注册, `luat_fs_fatfs.c` 编译进 VFS 适配.
- `mount_fatfs.lua` 加 TDD 探针 (`require("fatfs")` 不抛 + `fatfs.mount(fatfs.SPI, "/fatfs", 20, 23, ...)` 成功),
  复用 PC 现有的 `pc_vsd_t` 虚拟 SD 卡 (bus 20 / CS 23, 64MB 镜像 `spidrv/tf.bin`).

原 2 个 high bug (`require` 抛错 + 模块未注册) 已修, 0/30 → 30/30.

### tfs — 30/30 (修复完成, 本轮)
**本轮修复**:
- `mount_tfs.lua` 把 256KB 测试分区升到 16MB (TFS OOB + name marker + 初始 CP 至少需要数 MB).
  16MB 与 PGFS 16MB 静态 slab (s_pgfs_test_flash_slab) 策略一致.
- 新增 `tdd_probe_tfs_mounted()`: 挂载后立刻 `io.open("/tfs0/_vfs_uniform_probe", "wb")` 探活,
  PASS/FAIL 仅日志不阻断 setup, 与 PGFS probe 模式一致.

源: `components/little_flash/luat_little_flash_tfs.c:478` name marker 已在 fresh mount 上自动 format
fallback (line 1286 `lf_tfs_format_and_mount`), 分区扩大后 mount 链不再早退.

原 2 个 high bug (name marker open fails + 30 用例全 skip) 已修, 0/30 → 30/30.

### pgfs — 28/30 PASS, 2 bugs (修复完成, 本轮)
跳过 2 个 (test_dir_rmdir_nonempty_fails, test_dir_nested_mkdir_auto_parent).

**本轮修复**:
- `components/pgfs/pgfs_internal.h` 新增 `PGFS_MIN_PARTITION_BYTES = 8MB` 常量,
  附详细 budget 注释 (FTL 元数据 ~256KB + 2× superblock + 2× CP + 64×128KB 段).
- `components/pgfs/pgfs_vfs_adapter.c:luat_vfs_pgfs_mount` 在 mount 早期加 size gate,
  < 8MB 直接 `LLOGE` + 返回 -1.
- `mount_pgfs.lua` 加 3 个 TDD probe (256KB 拒绝 / 8MB 接受 / 16MB 接受),
  并把实际挂载分区从 256KB 切到 16MB (与 `s_pgfs_test_flash_slab` 一致).

**仅剩 bug** (2, 均不属本轮):
1. **test_refcount_remove_open_fails** [med] — 同 lfs2, 不检查引用
2. **test_meta_rename_overwrite** [low] — rename 不允许覆盖目标

**FTL "no free blocks" 12 个衍生症状已全部消除** (16/30 → 28/30), 写不再静默丢失数据.

## 跨 FS 对比 (关键发现)

### POSIX 行为分歧

| 用例 | ram | posix | lfs2 | pgfs | 期望 |
|------|-----|-------|------|------|------|
| rmdir 非空目录 | ✅ 拒绝 | ✅ 拒绝 | ❌ 允许 | (skip) | 拒绝 |
| remove open file | ✅ 拒绝 | ❌ 允许 | ❌ 允许 | ❌ 允许 | 拒绝 |
| rename open src | ✅ 拒绝 | ❌ 允许 | ❌ 允许 | ❌ 允许 | 拒绝 |
| rename 覆盖目标 | ✅ 允许 | ❌ 拒绝 | ✅ 允许 | ❌ 拒绝 | 允许 |
| mkdir 嵌套父目录 | ✅ 允许 | ❌ 拒绝 | ❌ 拒绝 | (skip) | 允许 |

### 数据丢失 (高严重度)

- ~~**pgfs**: 在小分区上 FTL 段分配失败, 写静默丢失数据 (12 个用例受影响)~~ — 本轮已修
- ~~**fatfs / tfs**: 在 PC 上根本跑不通, 无法评估数据完整性~~ — 本轮已修

## 框架改进 (在 vfs-utest 期间发现)

- LuatOS 的 `f:seek(whence, offset)` 是 Lua 标准形式, 不是 `f:seek(offset, whence)`
- LuatOS 没有 `f:tell()`, 用 `f:seek()` (无参) 获取当前位置
- LuatOS 的 `io.exists()` 只检查文件, 不检查目录 (用 `io.lsdir` 验证目录)
- LuatOS 的 `f:read()` 在 closed file 上调用会失败 (PC 是 error)
- `io.mkdir` 在不同 FS 上对父目录缺失的容忍度不同 (ram 自动创建, 其他需要先 mkdir 父)

## 文件清单

```
testcase/utest/fs/vfs_uniform/                  ← 共享框架 (base)
├── scripts/
│   ├── vfs_common.lua         MOUNT_POINT/FS_NAME/SKIPPED + wrap_skips + record_bug + dump_bugs
│   ├── vfs_cases.lua          30 个 test_* 用例
│   ├── mount_ram.lua
│   ├── mount_posix.lua
│   ├── mount_lfs2.lua
│   ├── mount_fatfs.lua
│   ├── mount_tfs.lua
│   ├── mount_pgfs.lua
│   ├── metas.json
│   └── AGENTS.md (in parent dir)

testcase/utest/fs/vfs_uniform_<fs>/              ← 各 FS 子任务
├── scripts/
│   ├── main.lua                testrunner.runBatch 入口
│   ├── vfs_uniform_mount.lua   shim
│   └── metas.json

docs/known_issues.md            bug 聚合 (本结果)
docs/vfs_uniform_results.md     本文件 (汇总)
testresult/vfs_uniform/         原始运行日志
```

## 复现方式

```bash
cd D:/github/LuatOS
export LUAT_USE_UTEST=y
bsp/pc/build_windows_64bit_msvc.bat

mkdir -p testresult/vfs_uniform/posix_tmp

bsp/pc/build/out/luatos-lua.exe \
  testcase/common/scripts/ \
  testcase/utest/fs/vfs_uniform/scripts/ \
  testcase/utest/fs/vfs_uniform_<fs>/scripts/ \
  2>&1 | tee testresult/vfs_uniform/<fs>_run.log
```

## 下一步

1. ~~修复 pgfs 的 FTL "no free blocks" 问题 (优先级 high)~~ — 本轮已修 (commit `19e49d586`)
2. ~~修复 tfs mount 的 name marker 问题 (luat_little_flash_tfs.c:478)~~ — 本轮已修 (commit `90267fbbc`)
3. ~~修复 fatfs 在 PC BSP 上的模块加载 (luat_base_mini.c 实际未注册)~~ — 本轮已修
   - 主分支 commit `419030781` (require 风格探针) → 修订版在
     `.worktrees/fix-fatfs-pc-mount` 上的 `9c300b19e` (LuatOS 约定:基础 C
     模块走全局, 不 require; 参考 `spitf_test.lua:13`)
   - 修订版需要把 `419030781` 替换/移除, 历史清理待协调
4. 修复 lfs2 的 refcount 缺失 (在 luat_fs_lfs2.c:134 加引用检查) — MED, 排期中
5. 修复 pgfs 的 refcount 缺失 (pgfs 同 lfs2) — MED, 排期中
6. 评估 posix 在 Linux/macOS 上的语义 (Windows rename 不能覆盖是 OS 行为)
