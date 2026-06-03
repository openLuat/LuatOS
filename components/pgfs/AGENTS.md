# PGFS Component AI Notes

This file captures practical guidance for AI-assisted work under `components/pgfs/`.

## Scope

- Component: `components/pgfs/`
- Mount integration: `components/little_flash/luat_lib_little_flash.c`
- PC enable path: `bsp/pc/include/luat_conf_bsp.h` (`LUAT_USE_PGFS_COMPONENT`)

## On-disk format version 2 (worktree-pgfs-64mb)

The 64MB+ refactor bumps `PGFS_ONDISK_VERSION` from 1 to 2. V1 records on
flash are treated as "fresh flash" and trigger a full factory scan. The new
layout (each region = one erase unit) is:

| Block | Region | Addr (128KB erase) | Notes |
|-------|--------|--------------------|-------|
| 0 | Superblock A | `0x00000` | separate erase unit from SB-B |
| 1 | Superblock B | `0x20000` | independent of SB-A |
| 2 | Checkpoint A | `0x40000` | new CP every batch close |
| 3 | Checkpoint B | `0x60000` | alternate CP slot |
| 4 | FTL state | `0x80000` | bitmap + erase counts + reserved + weak |
| 5..N-1 | Data log segments | `0xA0000..` | per-segment write head (Phase 2/4) |

For 64MB / 128KB erase = 512 blocks. Data log occupies 507 blocks (~64.7MB).

The layout is computed at mount by `pgfs_layout_compute(geo, &out)` and
stored in `pgfs_mount_ctx_t.layout`. Every address arithmetic in pgfs code
goes through this struct. Do not introduce new hardcoded address constants
beyond the named-region anchors in `pgfs_internal.h` (which exist for
the VFS adapter and the FTL state probe only).

## Key contracts

1. **Durability boundary**
   - Writes may stay in cache before close.
   - `fclose` success is the durability point.
   - Any injected failure before checkpoint commit must make `fclose` fail.
   - `pgfs_cache_flush_to_log` is intentionally a no-op; callers that need
     explicit durability should use `fclose()` rather than `fflush()`.

2. **Flash backend ABI (4 ops only)**
   - `read/write/erase/control`
   - Keep PC and device backends behind this interface.
   - Real NAND chips (W25N01GVZEIG, MX35LF512) use **128KB erase blocks**
     with 4KB sub-page program granularity; the v3 layout is designed for
     this.

3. **Reserved block bitmap (Phase 1)**
   - Blocks 0..4 (SB-A/B, CP-A/B, FTL state) are reserved and MUST never
     be allocated for data log segments.
   - `pgfs_alloc_segment` skips reserved blocks in both the forward scan
     and the wrap-around pass.
   - The reserved bitmap is persisted as part of the FTL state v3 record.

4. **Generation recovery**
   - Superblock/checkpoint dual-generation selection uses seq + CRC validity.
   - Newer generation corruption must fall back to older valid generation.
   - On checkpoint commit, the FTL state (bad-block bitmap + reserved bitmap
     + erase counts + weak bitmap) is re-persisted alongside the CP so
     runtime-discovered bad blocks, reservations, and wear-levelling
     counters survive an unexpected power loss.

5. **CP/SB write safety**
   - `pgfs_checkpoint_store_next` performs a readback + CRC verify after every
     CP and SB write. A bad readback aborts the store so the old SB/CP pair
     on the alternate slot remains authoritative.
   - `pgfs_ftl_persist` similarly readback-verifies the FTL state. On
     failure the previous `last_persist_buf` snapshot is preserved so
     recovery is still possible.

6. **Wear-levelling (Phase 2 placeholder → Phase 2 GC)**
   - `pgfs_alloc_segment` picks the non-bad, non-reserved block with the
     lowest `erase_counts` entry, scanning from `gc_next_seg_id` to
     `total_blocks` (with a wrap to the start when no good block is found).
   - `pgfs_gc_step` is now a real cost-benefit victim picker. Score is
     `(dead_bytes + reclaimable_free_bytes) / (erase_count + 1)`, with
     the best-scoring candidate (skipping bad / reserved / retired
     blocks) marked retired. The data-move step (re-write live records
     out of the victim before retiring) is a follow-up — currently the
     safe subset runs, which only retires blocks with zero live bytes.
     Per-block live / dead accounting (Phase 2 prep) is what would
     let a non-empty block be picked and safely reclaimed.

7. **Weak blocks (Phase 3)**
   - A weak block has shown signs of degradation (e.g. an ECC-corrected
     read). It is still usable for data writes but is a first-priority
     candidate for refresh on the next GC.
   - The weak bitmap is persisted as part of the FTL state v3 record.

7a. **Header ECC (Phase 3b)**
   - Each data record header carries an 8-byte `ecc[8]` field placed
     AFTER the CRC32 (DATA records: at offset 16; BATCH_DATA records:
     at offset 20; BATCH_COMMIT records: at offset 16). The field is
     sized to accommodate a full Hamming(72,64) SECDED code.
   - The current implementation (`pgfs_ecc_hamming_encode/decode` in
     `pgfs_ecc.c`) is a **single-byte XOR parity placeholder** — it
     detects any single-bit or multi-bit flip in the first 8 header
     bytes (magic..path_len, or magic..batch_id) but does NOT correct
     it. The on-disk 8-byte field is intentionally over-sized so a
     future change can drop in a real SECDED implementation without
     altering the record layout.
   - The CRC32 scope was widened to include the header prefix bytes
     that precede the `crc32` field (12 bytes for DATA and
     BATCH_COMMIT, 16 bytes for BATCH_DATA) so the CRC protects both
     the header AND the path/data. The replay chains the CRC across
     the same prefix.
   - On ECC mismatch in the replay, the block is marked weak and the
     record is still attempted — the CRC32 is the authoritative
     validation. ECC failure is a hint to refresh the block, not a
     reason to drop a still-recoverable record.

8. **O(1) mount (Phase 4 + Phase 4b)**
   - `pgfs_checkpoint_t` carries `log_tail_block` / `log_tail_offset`
     recording the data log write head at CP commit time. These are
     populated by `pgfs_checkpoint_store_next` from
     `ctx->data_log_write_addr` (and the geometry's erase_size) right
     before the CRC is computed.
   - `pgfs_nand_ftl_ctx_t` carries matching `write_head_block` /
     `write_head_offset` and `log_tail_block` / `log_tail_offset`.
     `pgfs_ftl_on_checkpoint_commit` refreshes `write_head_*` from
     `ctx->data_log_write_addr` and `log_tail_*` from the mirrored
     `ctx->log_tail_*` right before each `pgfs_ftl_persist`. The
     FTL meta v3 record round-trips both pairs so a future mount can
     detect consistency.
   - `pgfs_checkpoint_is_consistent_with_ftl` returns true when
     `cp->log_tail_block == ftl->write_head_block &&
      cp->log_tail_offset == ftl->write_head_offset` AND neither
     field is zero (a zero pair is treated as "CP record with no
     log_tail populated yet" and forces the safe replay path). The
     mount path can then skip `pgfs_replay_data_log`.

9. **Retired vs bad (Phase 5 + Phase 5b)**
   - `pgfs_mark_block_retired` no longer conflates with `pgfs_ftl_mark_block_bad`.
     Retired = GC has moved all live data out (safe to erase). Bad = at
     least one hardware erase attempt failed.
   - **Phase 5b**: the retired bit is now persisted in the FTL state
     v3 record (`retired_blocks_bitmap` between the reserved bitmap
     and the erase-count array). `pgfs_mark_block_retired` sets the
     bit on `ctx->ftl.retired_blocks_bitmap` and the CP flag 0x01u
     so test code that reads the CP directly can also observe the
     retirement.
   - The FTL allocator (`pgfs_ftl_find_free_block`) skips retired
     blocks just like bad ones; the two states are independent
     (retired-without-bad means GC moved data out; bad-on-top-of-
     retired would mean an erase later failed).
   - `pgfs_ftl_load` accepts only v3 records; a stale v2 record on
     flash is treated as a load failure and triggers a fresh factory
     scan (which is acceptable: there is no production data on v2 yet).

11. **Per-block live/dead accounting (Phase 2 prep / FTL v4)**
   - `pgfs_nand_ftl_ctx_t` carries `live_bytes_per_block[]` and
     `dead_bytes_per_block[]` arrays, both heap-allocated with
     `total_blocks` entries. They are persisted in the FTL v4 record
     immediately after the erase-count array.
   - The DATA record write path (`pgfs_append_data_record`) and the
     per-record replay path (`pgfs_replay_data_log`) attribute the
     record's bytes to the block holding the record's start address
     via `pgfs_account_live_block()`. Other blocks stay at zero.
   - The global `gc_live_bytes` / `gc_dead_bytes` in the CP are kept
     as a roll-up for `info()` and tests; per-block stats are the
     cost-benefit GC's input.
   - BATCH_DATA / file-delete dead attribution is a follow-up —
     requires carrying the BATCH_DATA record's on-flash address
     through `pgfs_replay_pending_entry_t`.

10. **Feature gating**
   - Use `LUAT_USE_PGFS_COMPONENT` guards in mixed modules (`little_flash`,
     adapters).
   - Do not rely on `xmake add_defines` for this macro in PC; declare it in
     `luat_conf_bsp.h`.

## Powercut injection stages (testing)

`pgfs_inject_powercut_stage` supports the following values (defined in
`pgfs_internal.h`):

| Constant | Value | Failure point |
|----------|-------|---------------|
| `PGFS_INJECT_POWERCUT_NONE` | 0 | (no injection) |
| `PGFS_INJECT_POWERCUT_BEFORE_APPEND` | 1 | before data log append (close fails) |
| `PGFS_INJECT_POWERCUT_AFTER_APPEND` | 2 | after append (data in log, entry not committed) |
| `PGFS_INJECT_POWERCUT_BEFORE_CP` | 3 | before checkpoint store (forwarded to FTL erase) |
| `PGFS_INJECT_POWERCUT_AFTER_CP_ERASE` | 4 | after CP/SB erase, before write |
| `PGFS_INJECT_POWERCUT_AFTER_CP_WRITE` | 5 | after CP write, before SB write |
| `PGFS_INJECT_POWERCUT_AFTER_APPEND_ERASE` | 6 | after data log prepare, before write |

Stages 3/4 (legacy) are forwarded to the FTL persist powercut injection
(`ctx.ftl.powercut_inject = 1` for FTL erase, `2` for FTL write). These are
retained for backward compatibility; the newer explicit stages (4/5/6) are
preferred for new tests.

## Recommended verification (PC)

From `bsp/pc`:

```powershell
$env:LUAT_USE_UTEST = "y"
powershell -File build_with_summary.ps1 -Arch x86 -Vm64 0 -Mode summary
powershell -File pc_utest_coverage.ps1 -Suite pgfs_basic -SkipBuild
```

## PC vs Hardware Verification Matrix

| 维度 | PC 验证(主战场) | 真机验证 |
|---|---|---|
| 套件 | `pgfs_basic`(17+ C-utest 用例) + `pgfs_regression_basic`(11 Lua 用例) | `air1601_pgfs_regression_basic`(8 Lua 用例) |
| 覆盖范围 | FTL/GC/recovery/contract/powercut 矩阵的**全部** | NOR/NAND mount + IO 不崩 + `lf.pgfsctl` 控制 API 不崩 |
| 跑法 | `LUAT_USE_UTEST=y` env + `pc_utest_coverage.ps1 -Suite pgfs_basic` | `luatos-cli flash test`,见 `/luatos-hw-test` skill |
| 入口 | `pgfs.utest("case")` | production API + `lf.pgfsctl(...)` 注入 |

**真机回归不重复 PC 已覆盖的 FTL/GC/契约验证**——那些用 PC 跑快、有覆盖率、可重复。真机只验证 PC 模拟不了的:真 SPI 信号完整性、真 NAND 时序、reset/上电恢复在真硬件上的行为。

`lf.pgfsctl(cmd, value)`(`components/little_flash/luat_lib_little_flash.c:329-360`)真机暴露的控制 API:

| cmd | value | 用途 |
|---|---|---|
| `lock_mode` | `"on"`/`"off"` | 切互斥锁包装(默认 off) |
| `powercut_stage` | 阶段名字符串 | 注入下次写入失败 |
| `corrupt_latest_cp` | bool | 强制最新 CP 校验失败,验证退到上一代 |
| `bad_block_once` | bool | 下次 erase 标 bad-block |
| `reset_runtime` | (无) | 强制 umount 重新 mount(测 CP 持久化) |
| `run_c_tests` | (无) | 真机上跑 C 层 selftest(`LUAT_USE_UTEST` 开了才有) |

### 真机已知限制(2026-06-03,见 `/luatos-hw-test` skill §10)
- ~~`reset_runtime` 在 W25N01KVZEIR NAND 上仍返回 false~~ — ✅ FIXED (`pgfs_vfs_adapter.c:553-562` 加 `if (flash_opts != NULL)` guard)。Path A(无 mount)和 Path B(mount 后 reset)都修好
- ~~`powercut_stage("before_cp")` 短形字符串没认~~ — ✅ FIXED (`pgfs_vfs_adapter.c:426-430` 加 `|| "before_cp"` alias,映射到 `PGFS_INJECT_POWERCUT_BEFORE_CP`)
- ~~`test_reopen_recover` 真机 fail(写+reset+remount 后文件丢失)~~ — ✅ FIXED in code path (`pgfs_vfs_adapter.c:158-200` mount 路径 O(1) skip 改 bounded replay,file table 总是从数据日志重建;同 `fbeda6236` 的 log_tail 限定逻辑统一到 mount/reset 两条路径)。**真机残留**:W25N01KVZEIR SPI 信号完整性(见下)导致 data record 被静默 skip,需后续 SPI retry 或降速
- W25N01KVZEIR 在 2 MHz SPI 偶有 `Read failed at addr=N`,是信号完整性,不是 pgfs bug;频繁触发则降 SPI clock(1 MHz 仍偶发,降到 500 KHz 可稳定)

## Current regression focus

- `pgfs_basic`: generation fallback, close durability, info rebuild, control
  invalid args, C selftests. Includes:
  - Phase 0: `pgfs_test_layout_compute_64mb`
  - Phase 1: `pgfs_test_reserved_blocks_never_allocated`,
    `pgfs_test_reserved_bitmap_persists_roundtrip`
  - Phase 3: `pgfs_test_weak_block_separate_from_bad`
  - Phase 3b: `pgfs_test_ecc_encode_decode_roundtrip`,
    `pgfs_test_ecc_decode_detects_corruption`,
    `pgfs_test_replay_marks_block_weak_on_ecc_mismatch`
  - Phase 4b: `pgfs_test_checkpoint_consistency_matches_when_synced`,
    `pgfs_test_checkpoint_consistency_fails_on_drift`,
    `pgfs_test_ftl_persist_round_trips_write_head_and_log_tail`
  - Phase 5: `pgfs_test_retired_does_not_mark_bad`
  - Phase 5b: `pgfs_test_retired_bitmap_persists_roundtrip`,
    `pgfs_test_alloc_skips_retired_blocks`
  - Phase 2 prep: `pgfs_test_live_dead_per_block_roundtrip`,
    `pgfs_test_per_block_live_updates_on_write`
  - Phase 2 GC: `pgfs_test_gc_step_returns_zero_when_nothing_to_reclaim`,
    `pgfs_test_gc_step_retires_empty_block`,
    `pgfs_test_gc_picks_lowest_erase_count_among_empties`,
    `pgfs_test_gc_excludes_bad_reserved_retired`,
    `pgfs_test_gc_data_move_preserves_file`
  - Phase 6 stress: `pgfs_test_stress_many_files_writes_counters`,
    `pgfs_test_stress_write_delete_cycles`
  - Phase 6 multi-mount: `pgfs_test_multi_mount_cycle_reads_via_replay`,
    `pgfs_test_multi_mount_counters_advance`
  - Phase 6 replay shadow: `pgfs_test_replay_shadow_detection_marks_dead_bytes`
  - Pre-existing: wear-levelling alloc, CP-erase powercut recovery, FTL
    state skip, single-block retirement, FTL persist snapshot, FTL
    persist readback failure.
  - `pgfs_test_fill_delete_rewrite_recovers_capacity` is intentionally not in
    the default `c_layer_selftests` dispatch — it depends on data-log
    compaction after file deletion, which is not yet implemented. Run it
    explicitly via `pgfs.utest("fill_delete_rewrite_recovers_capacity")` if
    needed.
- `pgfs_regression_basic`: lock toggle, GC churn, bad-block-once hook,
  write+close performance trace.
- Performance trace log key:
  - `trace_total_stall_us=<value>`

## Test infrastructure notes

- `pgfs_test_flash_t` is heap-allocated from a shared 16MB static slab. The
  default test flash size is 32KB with 4KB erase (matches the original
  layout). Tests that exercise NAND geometry set
  `flash->capacity_override = 0x1000000` (16MB) or `0x4000000` (64MB,
  `PGFS_TEST_FLASH_64MB_SIZE`) and `flash->erase_size_override = 128*1024`.
- `pgfs_test_flash_new_64mb()` tries `luat_heap_malloc(64MB)` and falls
  back to the 16MB BSS slab. Tests that assume 64MB physical flash must
  check `flash->mem_size == PGFS_TEST_FLASH_64MB_SIZE` before relying on
  it.
- `pgfs_data_log_base_addr(ctx)` reads `ctx->layout` directly; callers
  must ensure the layout is populated (via `pgfs_layout_compute` or
  by setting `ctx->layout` before the call) — there is no fallback
  for uninitialised ctx.

## Common pitfalls

- Prefer `mcu.ticks()` for timing in PC tests; `rtos.tick()` may be unavailable.
- Mount-point reuse in the same process can hit VFS mount limits; reuse
  mounted flash context in suites.
- Keep test assertions deterministic; avoid depending on one specific
  failure spot when fault injection is probabilistic by design.
- The lazy FTL init in `pgfs_alloc_segment` triggers on first allocation —
  tests that intend to verify the "no FTL" path must call
  `pgfs_alloc_segment` with a context that already has the FTL
  initialised, or exercise the code paths that don't go through the
  allocator.
- The CP commit calls `pgfs_ftl_on_checkpoint_commit` which always invokes
  `pgfs_ftl_persist`. With the FTL initialised this writes to the FTL
  state region on flash, consuming space in the data log area on the
  small 32KB test flash. Tests should account for this when sizing data
  log writes.
- The reserved bitmap default-marks blocks 0..4 reserved on
  `pgfs_ftl_init`. Tests that depend on the pre-Phase-1 contract (e.g.
  `pgfs_test_alloc_prefers_low_erase_count`) must call
  `pgfs_ftl_clear_reserved(&ctx.ftl, <block>)` to restore the old
  assumption.
