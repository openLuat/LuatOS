# TFS — Tiny File System

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Language: C99](https://img.shields.io/badge/Language-C99-green.svg)]()
[![Tests: 110/110](https://img.shields.io/badge/Tests-110%2F110%20PASS-brightgreen.svg)]()

A portable, bare-metal/RTOS-targeted NAND filesystem written in C99. TFS is a full rewrite of the YAFFS2 algorithm focused on performance, portability, and production reliability — with zero Linux kernel dependencies.

---

## Features

- **POSIX-style API** — `open`, `read`, `write`, `lseek`, `mkdir`, `readdir`, `symlink`, `link`, `stat`, `fstat`, `rename`, `unlink`, `truncate`, `dup`
- **Inband tags support** — for SPI NAND devices without OOB exposure
- **Checkpoint/fast-mount** — serialises filesystem state to NAND on unmount; restores in milliseconds
- **Per-block summary pages** — dramatically reduces mount scan time on large devices
- **Software Hamming ECC** — 1-bit correction, 2-bit detection per 256-byte sector
- **Greedy garbage collector** — background GC, call from idle task
- **Hard links, symlinks, sparse files, large files** (multi-level tnode trees)
- **C99 only** — `uint8_t`/`uint32_t` etc., no custom type aliases
- **No OS dependencies** — uses only `malloc`, `free`, `memcpy`, `memset`, `strlen`
- **Tiny footprint** — suitable for MCUs with ≥64 KB RAM

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Application                                                │
├─────────────────────────────────────────────────────────────┤
│  inc/tfs.h           Public POSIX-style API                 │
├──────────────┬──────────────┬───────────────────────────────┤
│  tfs_fs.c    │  tfs_dir.c   │  tfs_verify.c                 │
│  (POSIX API) │  (directory) │  (integrity checks)           │
├──────────────┴──────────────┴───────────────────────────────┤
│  tfs_core.c    Format / mount / unmount / GC orchestration  │
├────────────┬─────────────┬──────────────┬───────────────────┤
│ tfs_inode.c│ tfs_block.c │ tfs_cache.c  │ tfs_checkpoint.c  │
│ (objects)  │ (alloc/erase│ (write cache)│ (fast mount)      │
├────────────┴─────────────┴──────────────┴───────────────────┤
│  tfs_tnode.c  tfs_tags.c  tfs_ecc.c  tfs_summary.c         │
├─────────────────────────────────────────────────────────────┤
│  inc/tfs_port.h       Driver/OS porting interface           │
│  port/tfs_port.c      Example: FreeRTOS / bare-metal        │
└─────────────────────────────────────────────────────────────┘
```

### Key files

| File | Purpose |
|------|---------|
| `inc/tfs.h` | Only header user code should include |
| `inc/tfs_types.h` | Enums, structs, error codes |
| `inc/tfs_config.h` | Compile-time configuration macros |
| `inc/tfs_port.h` | Driver/OS porting interface (`tfs_drv_t`, `tfs_geo_t`) |
| `src/tfs_core.c` | Format, mount, unmount, GC, checkpoint orchestration |
| `src/tfs_fs.c` | POSIX API implementation |
| `src/tfs_inode.c` | Object lifecycle, hash table, header I/O |
| `src/tfs_block.c` | Block/chunk allocation, erase, read/write |
| `src/tfs_tnode.c` | Tnode trees (chunk-to-object mapping) |
| `src/tfs_cache.c` | Write cache |
| `src/tfs_checkpoint.c` | Fast-mount checkpoint (serialize objects to NAND) |
| `src/tfs_summary.c` | Per-block summary pages |
| `src/tfs_tags.c` | Tag pack/unpack (OOB + inband) |
| `src/tfs_ecc.c` | Software Hamming ECC |
| `src/tfs_dir.c` | Directory operations |
| `src/tfs_verify.c` | Filesystem integrity checks |
| `port/tfs_port.c` | Example port (FreeRTOS / bare-metal) |
| `test/tfs_test.c` | 110-test suite (T01–T28) |
| `test/tfs_ram_nand.c` | RAM NAND emulator for host testing |

---

## Quick Start — Porting Guide

### 1. Implement the driver callbacks

Copy `port/tfs_port.c` and fill in the five NAND callbacks:

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

### 2. Configure geometry

```c
tfs_geo_t geo = {
    .total_blocks        = 1024,
    .pages_per_block     = 64,
    .data_bytes_per_page = 2048,
    .spare_bytes_per_page = 64,
    .inband_tags         = 0,   /* 1 for SPI NAND without OOB */
};
```

### 3. Register and mount

```c
tfs_drv_t drv = { /* fill callbacks + geo */ };
tfs_add_device("nand0", &drv, &geo);

tfs_init();
tfs_mount("nand0");           /* or tfs_format("nand0") first time */
```

### 4. Use the filesystem

```c
int fd = tfs_open("/data/log.txt", TFS_O_WRONLY | TFS_O_CREAT, 0644);
tfs_write(fd, buf, len);
tfs_close(fd);
tfs_unmount("nand0");
```

---

## API Reference

### Lifecycle

| Function | Description |
|----------|-------------|
| `tfs_init()` | Must be called once before any other API |
| `tfs_add_device(name, drv, geo)` | Register a NAND device |
| `tfs_remove_device(name)` | Deregister (must be unmounted first) |
| `tfs_format(name)` | Erase and initialise filesystem |
| `tfs_mount(name)` | Mount (restores from checkpoint if present) |
| `tfs_unmount(name)` | Flush, write checkpoint, unmount |
| `tfs_sync(name)` | Flush write cache to NAND |
| `tfs_bg_gc(name)` | Run one GC pass (call from idle task) |

### File I/O

| Function | Description |
|----------|-------------|
| `tfs_open(path, flags, mode)` | Open/create file; returns fd ≥ 0 |
| `tfs_close(fd)` | Flush and close |
| `tfs_read(fd, buf, n)` | Read up to n bytes; returns bytes read |
| `tfs_write(fd, buf, n)` | Write n bytes; returns bytes written |
| `tfs_lseek(fd, offset, whence)` | Reposition file offset |
| `tfs_fsync(fd)` | Flush to NAND |
| `tfs_dup(fd)` | Duplicate file descriptor |
| `tfs_ftruncate(fd, size)` | Resize open file |
| `tfs_truncate(path, size)` | Resize by path |
| `tfs_unlink(path)` | Delete file |
| `tfs_rename(old, new)` | Rename / move |

### Stat

| Function | Description |
|----------|-------------|
| `tfs_stat(path, st)` | Stat by path (follows symlinks) |
| `tfs_lstat(path, st)` | Stat by path (does not follow symlinks) |
| `tfs_fstat(fd, st)` | Stat open file descriptor |

### Directories

| Function | Description |
|----------|-------------|
| `tfs_mkdir(path, mode)` | Create directory |
| `tfs_rmdir(path)` | Remove empty directory |
| `tfs_opendir(path)` | Open directory; returns dfd ≥ 0 |
| `tfs_readdir(dfd, de)` | Fill entry; returns 1=entry, 0=end, -1=error |
| `tfs_closedir(dfd)` | Close directory handle |

### Links & Space

| Function | Description |
|----------|-------------|
| `tfs_symlink(target, linkpath)` | Create symbolic link |
| `tfs_readlink(path, buf, size)` | Read symlink target |
| `tfs_link(oldpath, newpath)` | Create hard link |
| `tfs_freespace(name)` | Free bytes on device |
| `tfs_totalspace(name)` | Total bytes on device |
| `tfs_get_error()` | Last error code (`TFS_E*`) |

### Open flags

| Flag | Value | Meaning |
|------|-------|---------|
| `TFS_O_RDONLY` | 0x0000 | Read-only |
| `TFS_O_WRONLY` | 0x0001 | Write-only |
| `TFS_O_RDWR` | 0x0002 | Read/write |
| `TFS_O_CREAT` | 0x0040 | Create if not exists |
| `TFS_O_EXCL` | 0x0080 | Fail if exists (with O_CREAT) |
| `TFS_O_TRUNC` | 0x0200 | Truncate to zero on open |
| `TFS_O_APPEND` | 0x0400 | Always write at end |

---

## Configuration Reference (`inc/tfs_config.h`)

| Macro | Default | Description |
|-------|---------|-------------|
| `TFS_MAX_OPEN_FILES` | 16 | Maximum simultaneously open file descriptors |
| `TFS_MAX_OPEN_DIRS` | 8 | Maximum simultaneously open directory handles |
| `TFS_MAX_NAME_LEN` | 255 | Maximum filename length in bytes |
| `TFS_MAX_DEVICES` | 4 | Maximum registered NAND devices |
| `TFS_OBJ_BUCKETS` | 256 | Hash table buckets for object lookup |
| `TFS_OBJ_ID_FIRST_USER` | 0x100 | First object ID assigned to user files |
| `TFS_CACHE_CHUNKS` | 10 | Write-cache slots per device |
| `TFS_SUMMARY_ENABLED` | 1 | Enable per-block summary pages |
| `TFS_CHECKPOINT_ENABLED` | 1 | Enable fast-mount checkpoint |
| `TFS_ECC_ENABLED` | 1 | Enable software Hamming ECC |
| `TFS_INBAND_TAGS` | 0 | Default inband-tags mode (override per device) |

---

## Test Results

Test suite: 28 groups, 110 individual checks, all using a RAM-backed NAND emulator.

```
┌────────────────────────────────────────────────────────┐
│ TEST GROUP                                   │ RESULT  │
├────────────────────────────────────────────────────────┤
│ T01: Format                                  │  3/3    │
│ T02: File read/write                         │  5/5    │
│ T03: Directories                             │  4/4    │
│ T04: Unlink                                  │  2/2    │
│ T05: Rename                                  │  3/3    │
│ T06: Persistence (remount)                   │  2/2    │
│ T07: Garbage collection                      │  1/1    │
│ T08: Verify integrity                        │  1/1    │
│ T09: Inband tags persistence                 │  3/3    │
│ T10: Mount without format                    │  5/5    │
│ T11: Performance benchmarks                  │  0/0    │
│ T12: POSIX file API                          │  9/9    │
│ T13: lseek                                   │  5/5    │
│ T14: stat/fstat/lstat                        │  7/7    │
│ T15: opendir/readdir/closedir                │  4/4    │
│ T16: ftruncate/truncate                      │  6/6    │
│ T17: O_TRUNC and O_APPEND                    │  2/2    │
│ T18: Symlinks                                │  4/4    │
│ T19: Hard links                              │  5/5    │
│ T20: Large file (multi-level tnode)          │  4/4    │
│ T21: Sparse file                             │  5/5    │
│ T22: Rename edge cases                       │  7/7    │
│ T23: Error codes                             │  5/5    │
│ T24: Disk space                              │  4/4    │
│ T25: Pattern file + remount integrity        │  3/3    │
│ T26: Deep directory tree                     │  4/4    │
│ T27: GC pressure                             │  3/3    │
│ T28: Stress test                             │  4/4    │
├────────────────────────────────────────────────────────┤
│ TOTAL                                        │ 110/110 │
└────────────────────────────────────────────────────────┘
```

### Performance (T11 — RAM NAND emulator, 64 blocks × 64 pages × 2048 bytes)

| Operation | Time |
|-----------|------|
| Format (64 blocks × 64 pages) | 2.0 ms |
| Write 128 KB | < 1 ms |
| Checkpoint write (sync/unmount) | < 1 ms |
| Checkpoint restore (remount) | < 1 ms |
| Read 128 KB | < 1 ms |
| GC one pass | < 1 ms |

> Note: times reflect the RAM emulator; real NAND will be bounded by flash write latency.

---

## License

MIT — see [LICENSE](LICENSE).