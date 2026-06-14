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

(empty)

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

(empty)

## tfs

(empty)

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
