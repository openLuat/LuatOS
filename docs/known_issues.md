# VFS 统一测试 — 已知问题 / Bug 列表

本文件由 `testcase/utest/fs/vfs_uniform/` 框架自动/手动追加, 汇总 vfs 统一接口在
6 个文件系统 (ram/posix/lfs2/fatfs/tfs/pgfs) 上的行为差异与已发现 bug.

## 格式

```markdown
### <FS>::<test_name>  [severity]
- **Expected**: 一句话预期行为
- **Actual**: 一句话实际行为
- **Source**: 源文件:行号 (定位)
- **Repro**:
  1. 步骤 1
  2. 步骤 2
- **Tags**: fs=<fs>, mode=<mode>, feature=<area>
```

## 索引

- [ram](#ram)
- [posix](#posix)
- [lfs2](#lfs2)
- [fatfs](#fatfs)
- [tfs](#tfs)
- [pgfs](#pgfs)

---

## ram

(empty)

## posix

### posix::test_dir_nested_mkdir_auto_parent  [med]
- **Expected**: `io.mkdir("a/b/c")` 在父目录 b 不存在时应自动创建 (与 ram 行为一致)
- **Actual**: `io.mkdir` 失败, 不创建父目录
- **Source**: `luat/vfs/luat_fs_posix.c:200-208` (直接调原生 `mkdir`, 不会递归创建父目录)
- **Repro**:
  1. `io.mkdir("vfs_dir_a/b/c")` (b 不存在)
- **Tags**: fs=posix, mode=mkdir, feature=dir

### posix::test_edge_deep_nesting  [low]
- **Expected**: `io.mkdir` 应能创建 7 级嵌套目录 (a/b/c/d/e/f/g)
- **Actual**: `io.mkdir` 失败, 因为中间父目录 (a, a/b, …) 不存在
- **Source**: `luat/vfs/luat_fs_posix.c:200-208` (同上, 单一 `mkdir` 调用)
- **Repro**:
  1. `io.mkdir("vfs_edge_deep/a/b/c/d/e/f/g")`
- **Tags**: fs=posix, mode=mkdir, feature=dir

### posix::test_meta_rename_overwrite  [low]
- **Expected**: `os.rename` 覆盖已存在目标文件应成功
- **Actual**: `os.rename` 失败, 源文件保持不变
- **Source**: `luat/vfs/luat_fs_posix.c:105-112` (直接调原生 `rename`; Windows 不允许 overwrite existing target)
- **Repro**:
  1. `mkdir d; io.open("d/from.txt","wb"); io.open("d/to.txt","wb")`
  2. `os.rename("d/from.txt", "d/to.txt")`
- **Tags**: fs=posix, mode=rename, feature=meta, platform=windows

## lfs2

> lfs2 跑通 26/30 (跳过 1 个 C13 嵌套 mkdir). 真实 bug 4 个 (含 2 个 refcount 缺失).

### lfs2::test_edge_long_filename  [low]
- **Expected**: 60 字符文件名应可创建 (与 ram 一致)
- **Actual**: 60 字符文件名 open 失败
- **Source**: `luat/vfs/luat_fs_lfs2.c` (lfs2 默认 name_max=63, 但 PC 配置/驱动对长名更敏感)
- **Repro**:
  1. `io.open("/lfs2/vfs_edge_<60 chars>.txt", "wb")`
- **Tags**: fs=lfs2, mode=create, feature=long-name

### lfs2::test_edge_deep_nesting  [low]
- **Expected**: mkdir a/b/c/d/e/f/g 7 级嵌套应成功
- **Actual**: 失败
- **Source**: `luat/vfs/luat_fs_lfs2.c:206-223` (mkdir 不自动创建父目录)
- **Repro**:
  1. `io.mkdir("/lfs2/vfs_edge_deep/a/b/c/d/e/f/g")`
- **Tags**: fs=lfs2, mode=mkdir, feature=deep-nesting

### lfs2::test_refcount_remove_open_fails  [med]
- **Expected**: 打开中的文件不应被 os.remove 删除
- **Actual**: os.remove 成功了
- **Source**: `luat/vfs/luat_fs_lfs2.c:134` (直接调 `lfs_remove`, 不检查引用计数)
- **Repro**:
  1. 创文件 p
  2. `f = io.open(p, "r")`
  3. `os.remove(p)` -- 期望失败
  4. `f:close()`
- **Tags**: fs=lfs2, mode=read+remove, feature=refcount

### lfs2::test_refcount_rename_open_fails  [med]
- **Expected**: 打开中的源文件不应被 os.rename 重命名
- **Actual**: os.rename 成功了
- **Source**: `luat/vfs/luat_fs_lfs2.c:134` (rename 路径同样不检查引用)
- **Repro**:
  1. 创文件 src
  2. `f = io.open(src, "r")`
  3. `os.rename(src, dst)` -- 期望失败
  4. `f:close()`
- **Tags**: fs=lfs2, mode=read+rename, feature=refcount

## fatfs

### fatfs::setup_module_not_found  [high]
- **Expected**: 当 `fatfs` 模块在 PC BSP 中不可用时, `mount_fatfs.setup()` 应返回 false 让 `main.lua` 自跳过整个测试套
- **Actual**: `mount_fatfs.lua:9` 的 `require("fatfs")` 在 PC BSP 上直接抛出 "module 'fatfs' not found", VM 在 `main.lua` 检测 `fs_ok` 之前就崩溃退出, 测试套根本没有 self-skip 机会
- **Source**: `testcase/utest/fs/vfs_uniform/scripts/mount_fatfs.lua:9`
- **Repro**:
  1. 在 PC 模拟器上跑 `vfs_uniform_fatfs`
  2. `mount_fatfs.setup()` 里 `require("fatfs")` 失败, 抛错
  3. 错误沿着 `require` 链 `vfs_uniform_mount.lua -> mount_fatfs.lua` 一路冒泡, VM 退出
  4. `main.lua` 的 `if not fs_ok then ... os.exit(0) end` 永远不会执行
- **Tags**: fs=fatfs, mode=pc, feature=framework-bootstrap

### fatfs::pc_build_fatfs_module_unavailable  [high]
- **Expected**: PC BSP 应当能 `require("fatfs")` 加载内置 fatfs 模块 (因为 `LUAT_USE_FATFS` 已在 `bsp/pc/include/luat_conf_bsp.h:145` 定义, 且 `luaopen_fatfs` 在 `bsp/pc/port/luat_base_mini.c:160` 注册)
- **Actual**: 当前 PC 二进制 `bsp/pc/build/out/luatos-lua.exe` 对 `require("fatfs")` 返回 "module not found", 同样 `require("uart")`/`require("json")` 等内置模块也都失败; 只有 `io`/`os`/`string`/`log`/`rtos` 这类 globals 仍可用. 整个 fatfs 测试套无法在 PC 上执行
- **Source**: `bsp/pc/port/luat_base_mini.c:159-161` (注册) vs PC BSP 实际加载行为
- **Repro**:
  1. 写 `print(type(require("fatfs")))` 的最小 main.lua
  2. 用 `bsp/pc/build/out/luatos-lua.exe ... /tmp/test/` 跑
  3. 输出 `module 'fatfs' not found` 然后 `Lua VM exit!! reboot in 1000ms`
- **Tags**: fs=fatfs, mode=pc, feature=module-registration

## tfs

### tfs::tfs_mount_format_name_marker  [high]
- **Expected**: `lf.mount(flash, "/tfs0", 0, 256*1024, {fs="tfs"})` 在 PC 模拟器空白 flash 上应返回 true, mount 后 VFS 即可在 /tfs0 上读写文件
- **Actual**: 第一次 `lf.mount` 返回 false, 日志显示 `tfs: format ret=0 read_errors=0` (format 成功) 紧接着 `tfs: open name marker failed` 和 `tfs: format mount failed`, 之后才出现 `tfs: anchor written chunk=0 seq=4096`; 二次 mount 找到 anchor 但仍 `tfs: open name marker failed` 触发 `tfs: probe failed, reformatting`, 再次 `tfs: open name marker failed` 后 `tfs: format or mount failed`
- **Source**: `components/little_flash/luat_little_flash_tfs.c:478` (`lf_tfs_write_name_marker` 中 `tfs_open` 失败) 与 `:1226` (`tfs: format mount failed`)
- **Repro**:
  1. 在 PC 上跑 `D:/github/LuatOS/bsp/pc/build/out/luatos-lua.exe` 并加载 vfs_uniform_tfs/scripts
  2. `mount_tfs.lua` 调 `spi.deviceSetup(1,255,...)` + `lf.init(spidev)` + `lf.mount(flash,"/tfs0",0,256*1024,{fs="tfs"})`
  3. 观察: format ret=0 → open name marker failed → format mount failed, 紧接着 anchor 写入但 mount 仍失败
- **Tags**: fs=tfs, mode=mount, feature=format-name-marker

### tfs::all_tests_skipped_mount_unavailable  [high]
- **Expected**: 30 个共享用例应在 /tfs0 上运行, 大部分通过
- **Actual**: 30 个用例全部 0/0 跳过, 因为 tfs mount 失败直接 `os.exit(0)`, 没有任何用例被执行
- **Source**: 测试 `main.lua` 在 `mount.setup()` 返回 false 时退出; 根因是 tfs mount bug
- **Repro**:
  1. 跑 vfs_uniform_tfs (与上面 tfs_mount_format_name_marker 同一触发条件)
  2. 日志最后两行: `tfs mount 失败` + `tfs FS 不可用, 退出`
- **Tags**: fs=tfs, mode=run, feature=suite-execution


## pgfs

> pgfs mounted successfully on PC simulator (`/pgfs0`, 256KB partition, virtual NAND
> W25N01GVZEIG). However the FTL has very few free blocks at mount time (`next=1, total=2,
> bad=0`), and the GC allocator reports `alloc_segment: no free blocks` whenever a write
> triggers a new segment allocation. This causes most write/read roundtrip assertions to
> fail with 0-byte content. Each test below is a separate symptom of the same root cause
> (or, in two cases, an independent semantic bug).

### pgfs::test_refcount_remove_open_fails  [med]
- **Expected**: 打开中的文件不应被 os.remove 删除 (refcount 应阻止 remove)
- **Actual**: os.remove 成功了 (pgfs 直接删除了正在被读取的文件)
- **Source**: `components/pgfs/luat_pgfs_posix.c` (remove 路径未检查 refcount, 沿用 lfs2 的旧语义)
- **Repro**:
  1. `io.open("/pgfs0/vfs_refcount_rm.txt", "wb")` 然后 close
  2. `f = io.open("/pgfs0/vfs_refcount_rm.txt", "r")`
  3. `os.remove("/pgfs0/vfs_refcount_rm.txt")`  -- 期望失败, 实际成功
  4. `f:close()`
- **Tags**: fs=pgfs, mode=read+remove, feature=refcount

### pgfs::test_meta_rename_overwrite  [low]
- **Expected**: rename 覆盖已存在的目标文件应成功 (POSIX 行为)
- **Actual**: rename 失败, 目标文件保持旧内容
- **Source**: `components/pgfs/luat_pgfs_posix.c` rename 实现 (未先 unlink 目标)
- **Repro**:
  1. `io.mkdir("/pgfs0/d")`
  2. 创 `/pgfs0/d/from.txt` (内容 "new") 和 `/pgfs0/d/to.txt` (内容 "old")
  3. `os.rename("/pgfs0/d/from.txt", "/pgfs0/d/to.txt")`  -- 期望成功, 实际失败
- **Tags**: fs=pgfs, mode=rename, feature=metadata

### pgfs::test_basic_write_read_roundtrip  [high]
- **Expected**: 写入 "hello" 后读取应得到 "hello"
- **Actual**: 读出为空字符串 (write 静默失败, 文件大小为 0)
- **Source**: `components/pgfs/pgfs_alloc_gc.c:78` `alloc_segment: no free blocks`
  + `components/pgfs/luat_pgfs_posix.c` (write 路径未检测 segment 分配失败)
- **Repro**:
  1. mount pgfs (256KB)
  2. `f = io.open("/pgfs0/x.txt", "wb"); f:write("hello"); f:close()`
  3. `f = io.open("/pgfs0/x.txt", "rb"); f:read("*a")`  -- 期望 "hello", 实际 ""
- **Tags**: fs=pgfs, mode=wb/rb, feature=write-data-loss

### pgfs::test_basic_write_read_large  [high]
- **Expected**: 写入 64KB 数据后读回应得到 65536 字节
- **Actual**: 读出 0 字节 (write 静默失败, 因 segment 分配失败)
- **Source**: 同 test_basic_write_read_roundtrip (FTL 没有空闲块)
- **Repro**:
  1. `f = io.open("/pgfs0/big.bin", "wb"); f:write(<64KB>); f:close()`
  2. `io.open("/pgfs0/big.bin", "rb"):read("*a")`  -- 期望 65536 字节, 实际 0
- **Tags**: fs=pgfs, mode=wb/rb, feature=large-write-data-loss

### pgfs::test_edge_block_size_boundary  [high]
- **Expected**: 4096 字节精确写入读回后, 大小和内容完全一致
- **Actual**: 读出 0 字节 (page-aligned 4KB 写入也静默失败)
- **Source**: 同 test_basic_write_read_roundtrip (FTL 没有空闲块)
- **Repro**:
  1. `f = io.open("/pgfs0/block.bin", "wb"); f:write(<4096 bytes>); f:close()`
  2. `f = io.open("/pgfs0/block.bin", "rb"); f:read("*a")`  -- 期望 4096, 实际 0
- **Tags**: fs=pgfs, mode=wb/rb, feature=block-boundary

### pgfs::test_basic_seek_tell  [high]
- **Expected**: 写入 100 字节, seek('set', 50) 后 tell() 返回 50, 读出第 51 字节 = 50
- **Actual**: seek() 返回 0, read 返回空 (文件为 0 字节, write 静默失败)
- **Source**: 同 test_basic_write_read_roundtrip (根因 = FTL 段分配失败)
- **Repro**:
  1. `f = io.open("/pgfs0/x.bin", "wb"); f:write(<100 bytes>); f:close()`
  2. `f = io.open("/pgfs0/x.bin", "rb"); f:seek("set", 50); print(f:seek())`  -- 期望 50, 实际 0
- **Tags**: fs=pgfs, mode=rb, feature=seek-data-loss

### pgfs::test_basic_seek_end  [high]
- **Expected**: 写入 100 字节后 seek('end') 给出位置 100
- **Actual**: seek() 返回 0 (文件为空, write 失败)
- **Source**: 同 test_basic_write_read_roundtrip (根因 = FTL 段分配失败)
- **Repro**:
  1. `f = io.open("/pgfs0/x.bin", "wb"); f:write("x"*100); f:close()`
  2. `f = io.open("/pgfs0/x.bin", "rb"); f:seek("end"); print(f:seek())`  -- 期望 100, 实际 0
- **Tags**: fs=pgfs, mode=rb, feature=seek-end

### pgfs::test_basic_seek_cur  [high]
- **Expected**: seek('end') 后 seek('cur', -10) 给出位置 90
- **Actual**: seek() 返回 0 (文件为空, write 失败)
- **Source**: 同 test_basic_write_read_roundtrip (根因 = FTL 段分配失败)
- **Repro**:
  1. `f = io.open("/pgfs0/x.bin", "wb"); f:write("x"*100); f:close()`
  2. `f = io.open("/pgfs0/x.bin", "rb"); f:seek("end"); f:seek("cur", -10); print(f:seek())`
     -- 期望 90, 实际 0
- **Tags**: fs=pgfs, mode=rb, feature=seek-cur

### pgfs::test_meta_fsize  [high]
- **Expected**: 写入 1234 字节, fs.fsize 应返回 1234
- **Actual**: fs.fsize 返回 0 (write 静默失败)
- **Source**: 同 test_basic_write_read_roundtrip (根因 = FTL 段分配失败)
- **Repro**:
  1. `f = io.open("/pgfs0/x.bin", "wb"); f:write("Z"*1234); f:close()`
  2. `fs.fsize("/pgfs0/x.bin")`  -- 期望 1234, 实际 0
- **Tags**: fs=pgfs, mode=wb, feature=fsize

### pgfs::test_meta_rename_file  [high]
- **Expected**: rename a->b 应成功, 之后 b 存在且内容是 "data-a"
- **Actual**: rename 返回 err=2 (源文件不存在 / 写入失败, 链式失败)
- **Source**: 同 test_basic_write_read_roundtrip (写入失败导致源文件未创建, rename 报 ENOENT)
- **Repro**:
  1. `f = io.open("/pgfs0/a.txt", "wb"); f:write("data-a"); f:close()`
  2. `os.rename("/pgfs0/a.txt", "/pgfs0/b.txt")`  -- 期望 true, 实际 err=2
- **Tags**: fs=pgfs, mode=rename, feature=metadata-chain-failure

### pgfs::test_basic_append_mode  [high]
- **Expected**: "foo" + append "bar" 后读出 "foobar"
- **Actual**: 读出空字符串 (write 静默失败)
- **Source**: 同 test_basic_write_read_roundtrip (根因 = FTL 段分配失败)
- **Repro**:
  1. `f = io.open("/pgfs0/x.txt", "wb"); f:write("foo"); f:close()`
  2. `f = io.open("/pgfs0/x.txt", "ab"); f:write("bar"); f:close()`
  3. `io.open("/pgfs0/x.txt", "rb"):read("*a")`  -- 期望 "foobar", 实际 ""
- **Tags**: fs=pgfs, mode=ab, feature=append-data-loss

### pgfs::test_posix_mode_w_plus  [high]
- **Expected**: "w+" 打开后 write("xyz") 再 seek(0) read 应得到 "xyz"
- **Actual**: read 返回空字符串 (write 静默失败)
- **Source**: 同 test_basic_write_read_roundtrip (根因 = FTL 段分配失败)
- **Repro**:
  1. `f = io.open("/pgfs0/x.txt", "w+"); f:write("xyz"); f:seek("set", 0); print(f:read("*a"))`
     -- 期望 "xyz", 实际 ""
- **Tags**: fs=pgfs, mode=w+, feature=mode-flags

### pgfs::test_posix_mode_r_plus  [high]
- **Expected**: "r+" 打开已有文件后 write + seek + read 应得到原长度 (首字节被覆盖)
- **Actual**: read 返回 0 字节字符串 (写时静默失败, 文件被截断/清空)
- **Source**: 同 test_basic_write_read_roundtrip (根因 = FTL 段分配失败) +
  `components/pgfs/luat_pgfs_posix.c` (r+ 模式 open 后的截断/清空行为)
- **Repro**:
  1. `f = io.open("/pgfs0/x.txt", "wb"); f:write("initial"); f:close()`
  2. `f = io.open("/pgfs0/x.txt", "r+"); f:write("X"); f:seek("set", 0); print(f:read("*a"))`
     -- 期望 "Xniti..."(7 字节), 实际 ""
- **Tags**: fs=pgfs, mode=r+, feature=mode-flags

### pgfs::test_posix_binary_text_same  [high]
- **Expected**: 写入 0x0A 0x0D 0x00 0xFF 后 read(4) 读出 4 字节
- **Actual**: read(4) 返回 nil (文件为空, write 静默失败)
- **Source**: 同 test_basic_write_read_roundtrip (根因 = FTL 段分配失败)
- **Repro**:
  1. `f = io.open("/pgfs0/x.bin", "wb"); f:write("\x0A\x0D\x00\xFF"); f:close()`
  2. `f = io.open("/pgfs0/x.bin", "rb"); f:read(4)`  -- 期望 4 字节, 实际 nil
- **Tags**: fs=pgfs, mode=rb, feature=binary-mode
