# AGENTS.md — AI Agent Instructions for TFS

## Project Overview
TFS (Tiny File System) is a portable, bare-metal/RTOS-targeted NAND filesystem written in C99.
It is a full rewrite of YAFFS2 focused on performance, portability, and production reliability.

## Architecture Summary
- `inc/tfs.h` — Public POSIX-style API (the only header user code should include)
- `inc/tfs_types.h` — Enums, structs, error codes
- `inc/tfs_config.h` — Compile-time configuration macros
- `inc/tfs_port.h` — Driver/OS porting interface (`tfs_drv_t`, `tfs_geo_t`)
- `src/tfs_core.c` — Format, mount, unmount, GC, checkpoint orchestration
- `src/tfs_fs.c` — POSIX API layer (open, read, write, mkdir, symlink, ...)
- `src/tfs_inode.c` — Object lifecycle, hash table, header I/O
- `src/tfs_block.c` — Block/chunk allocation, erase, read/write
- `src/tfs_tnode.c` — Tnode trees (chunk-to-object mapping)
- `src/tfs_cache.c` — Write cache
- `src/tfs_checkpoint.c` — Fast mount checkpoint (serialize objects to NAND)
- `src/tfs_summary.c` — Per-block summary pages
- `src/tfs_tags.c` — Tag pack/unpack (OOB + inband)
- `src/tfs_ecc.c` — Software Hamming ECC
- `src/tfs_dir.c` — Directory operations
- `src/tfs_verify.c` — Filesystem integrity checks
- `port/tfs_port.c` — Example port (FreeRTOS / bare-metal)
- `test/tfs_test.c` — 110-test suite (T01–T28 with sub-tests)
- `test/tfs_ram_nand.c` — RAM NAND emulator for testing

## Coding Conventions
- **Prefix**: All public symbols use `tfs_` (functions, types, structs, enums)
- **Macros**: All macros use `TFS_` prefix
- **Types**: Use C99 standard types directly (`uint8_t`, `uint32_t`, `int32_t`, etc.)
- **No OS dependencies**: stdlib only (`malloc`, `free`, `memcpy`, `memset`, `strlen`)
- **Error codes**: Return `TFS_OK (0)` on success, negative `TFS_E*` codes on failure
- **NULL**: Use standard `NULL`, not any custom alias
- **File offset**: `tfs_off_t` (typedef for `int64_t`) for file positions

## Build Command
```bash
# From test/ directory using MSYS2/MinGW64 on Windows:
C:\msys64\usr\bin\bash.exe -c "export PATH='/mingw64/bin:/usr/bin:$PATH' && cd /f/code/codeup/nfs/test && gcc -I../inc -I../src -Wall -Wextra -Wno-unused-parameter -o tfs_test.exe tfs_test.c tfs_ram_nand.c ../src/tfs_fs.c ../src/tfs_core.c ../src/tfs_block.c ../src/tfs_tnode.c ../src/tfs_inode.c ../src/tfs_cache.c ../src/tfs_summary.c ../src/tfs_checkpoint.c ../src/tfs_tags.c ../src/tfs_ecc.c ../src/tfs_dir.c ../src/tfs_verify.c && ./tfs_test.exe"
```

## Key Technical Notes

### Object Hash Table
- 256 buckets (`TFS_OBJ_BUCKETS`), intrusive doubly-linked list per bucket
- `tfs_list_add(new_node, head)` — args are `(new_node, head)` — getting this wrong causes ejection bugs
- User objects start at `TFS_OBJ_ID_FIRST_USER = 0x100`

### Inband Tags
- When `dev->param.inband_tags=1`, tag data is stored in the last `sizeof(tfs_packed_tags2_t)` bytes of the data page, not in OOB
- `data_bytes_per_chunk` is reduced by `sizeof(tfs_packed_tags2_t)` in this mode
- Required for SPI NAND devices that don't expose OOB

### Checkpoint System
- On unmount: serializes all non-fake objects as byte stream to NAND
- On remount: restores objects, then `wire_parents()` re-links parent→child relationships
- Special objects (ROOT=1, LOSTNFOUND=2, UNLINKED=3, DEL=4) are fake and re-created every mount

### GC
- Greedy GC: find block with most deleted pages, copy valid pages out, erase
- `tfs_gc(dev, aggressive)` — call when free blocks are low

## Common Pitfalls for AI Agents
1. Do NOT swap `tfs_list_add(new_node, head)` argument order — causes hash table corruption
2. When modifying `tfs_chunk_write`, ensure `tfs_tags_pack` is called exactly ONCE
3. After any checkpoint/remount path change, run remount tests (T09–T15)
4. `tfs_close` must call `tfs_file_flush` (not just cache flush) to persist `file_size`
5. The test binary must be rebuilt after any source change before running tests
