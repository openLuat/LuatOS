# pgfs Design Spec (NAND Log-Structured Filesystem)

Date: 2026-06-03
Status: Implemented (Phases 0–5b complete; v3 on-flash format)
Scope: LuatOS component `components/pgfs/`

This document supersedes the original 2026-05-28 design spec. It reflects
the **as-built** state of the component, including the v2 → v3 on-disk
format migration done in Phases 3b / 4b / 5b and the per-block live/dead
accounting added in Phase 2 prep. For developer ergonomics while
touching the code, see `AGENTS.md` next to this file.

## 1. Goals (unchanged from original)

`pgfs` is a NAND-optimized log-structured filesystem for LuatOS:

1. Append-friendly, erase-block aware, bad-block aware.
2. **Power-loss semantics**: data before `fclose` may be lost; if
   `fclose` returns success, durability is guaranteed.
3. Balanced read/write performance; `info()` must be fast (≤ 1 ms
   in steady state).
4. Dual-superblock generation management.
5. RAM scales with FS size; target typical total ≤ 512 KiB.
6. PC simulator is the primary validation backend.
7. Flash backend API is exactly four ops: `read`, `write`, `erase`,
   `control`.
8. Optional locking.
9. Must mount through LuatOS VFS.

## 2. Architecture

### 2.1 Module layout

| File | Role |
| --- | --- |
| `pgfs_core.c` | Object model, record encode/decode, replay coordinator, write cache, file/dir operations, per-block live-bytes accounting. |
| `pgfs_checkpoint.c` | Dual-superblock / dual-checkpoint generation protocol, `pgfs_layout_compute`, `pgfs_checkpoint_is_consistent_with_ftl` (Phase 4b). |
| `pgfs_alloc_gc.c` | Segment allocator (wear-levelling), bad/retired block retirement, **cost-benefit GC** (Phase 2 — picks victim by score, retires empty blocks today; data-move path added in 5b). |
| `pgfs_cache_lock.c` | Write cache and optional lock wrappers. |
| `pgfs_vfs_adapter.c` | LuatOS VFS hooks (`mount`, `umount`, `info`, `fopen`, `fread`, `fwrite`, `fclose`, `remove`, dir ops). |
| `pgfs_nand_ftl.c` | NAND FTL state: bad/reserved/retired/weak bitmaps, per-block erase counts, per-block live/dead byte accounting, persist+load v3 record. |
| `pgfs_nand_ftl.h` | FTL public API + meta on-flash layout. |
| `pgfs_ecc.c` / `.h` | Per-record header ECC (Phase 3b). XOR-parity placeholder sized for a future Hamming(72,64) SECDED drop-in. |
| `pgfs_internal.h` | Internal API: `pgfs_checkpoint_t`, `pgfs_mount_ctx_t`, `pgfs_layout_t`, `pgfs_flash_geometry_t`, all the struct definitions and the public-ish declarations used across modules. |
| `pgfs_*.h` | Public LuatOS API consumed by `pgfs_vfs_adapter.c`. |

### 2.2 Boundary rules

- Persistent media access occurs only through `pgfs_flash_opts_t`.
- `fclose` is the sole durability boundary for normal file writes.
- `info()` reads the in-memory `pgfs_checkpoint_t`, not a scan.
- The FTL state (`pgfs_nand_ftl.c`) is the only place that talks
  about erase sizes, bad blocks, and per-block stats. The mount
  path and GC consult it via accessor functions.

## 3. YAFFS2 principles adopted

| Principle | Implementation |
| --- | --- |
| Copy-on-write only | All writes go through `pgfs_append_log_record`. No in-place overwrite. |
| Atomic commit boundary | `fclose` triggers `pgfs_checkpoint_commit_pending` which writes a fresh CP + SB, then persists the FTL state. |
| Dual generations | SB-A / SB-B + CP-A / CP-B. New writes alternate. |
| Fast-mount first | **Phase 4b**: mount reads CP, then loads FTL state, then runs `pgfs_checkpoint_is_consistent_with_ftl`. If CP and FTL agree on the data log write head, the O(1) skip path bypasses the data log replay entirely. |
| In-band tags | Every record carries magic/path_len/data_len/crc32/ecc in-band. No OOB. |
| Segment summaries (per-block live/dead) | **Phase 2 prep**: `pgfs_nand_ftl_ctx_t` carries `live_bytes_per_block[]` and `dead_bytes_per_block[]`, persisted in the v3 FTL record. |
| Incremental GC | **Phase 2**: `pgfs_gc_step` is a real cost-benefit victim picker with safe-subset retirement (empty blocks today; data-move path added for non-empty blocks). |
| Bad-block aware allocation | **Phase 5b**: `pgfs_ftl_is_retired` is independent of `pgfs_ftl_is_block_bad`. Allocation skips both. |
| Deterministic recovery | Replay and SB/CP selection are seq + CRC driven. |
| Integrity layering | Per-record CRC32 (over header prefix + path + data) AND per-record header ECC. |
| Bounded RAM | `pgfs_file_entry_t[PGFS_MAX_FILES]` and `pgfs_dir_entry_t[PGFS_MAX_DIRS]` are compile-time caps. |
| Observability | `pgfs_diag_stats_t` in `pgfs_mount_ctx_t` tracks lock_acquire, checkpoint_fallback, powercut_inject, badblock_inject counts. |

## 4. On-Disk Format (v3)

### 4.1 Flash regions

Five regions occupy one erase unit each, plus an arbitrary data log:

| Block | Region | Address (4 KiB erase) | Notes |
| --- | --- | --- | --- |
| 0 | SB-A | `0x0000` | alternates with SB-B |
| 1 | SB-B | `0x1000` | |
| 2 | CP-A | `0x2000` | alternates with CP-B |
| 3 | CP-B | `0x3000` | |
| 4 | FTL state | `0x4000` | v3 record (see §4.3) |
| 5..N-1 | Data log | `0x5000..` | append-only, aligned records |

For 64 MiB / 128 KiB erase: 512 blocks, 507 data log blocks (~64.7 MiB).
For 4 MiB / 4 KiB erase (PC SPI NOR sim): 16 blocks, 11 data log blocks.

All addresses are derived from `pgfs_layout_t` computed at mount by
`pgfs_layout_compute(geo, &out)`. The v1 / v2 fallback paths have been
removed; only v3 records are accepted.

### 4.2 CP / SB record (v3)

`pgfs_checkpoint_t` is packed:

| Field | Size | Notes |
| --- | --- | --- |
| `magic` | 4 | `0x50474350` |
| `version` | 2 | `PGFS_ONDISK_VERSION = 3` |
| `reserved` | 2 | padding |
| `seq` | 4 | monotonic generation |
| `total_blocks` | 4 | from `pgfs_flash_geometry_t` |
| `written_blocks` | 4 | data log record counter |
| `flags` | 4 | bit 0 set if any block was retired this generation |
| `gc_live_bytes` / `gc_dead_bytes` | 4 + 4 | roll-up of the per-block arrays |
| `log_tail_block` | 4 | **Phase 4b**: data log block at CP commit time |
| `log_tail_offset` | 2 | **Phase 4b**: offset within that block |
| `log_tail_reserved` | 2 | padding |
| `crc32` | 4 | over the entire struct (with this field = 0) |

`pgfs_superblock_t` mirrors the relevant subset: magic, version, seq,
`checkpoint_addr`, `checkpoint_len`, `checkpoint_crc`, crc32.

### 4.3 FTL state record (v3)

| Section | Size | Notes |
| --- | --- | --- |
| `pgfs_ftl_meta_t` | ~56 B | magic (`'PFTL'`), version = 3, total_blocks, bitmap_bytes, reserved_bitmap_bytes, erase_count_bytes, retired_bitmap_bytes, write_head_block/offset, log_tail_block/offset, crc32. |
| bad_blocks_bitmap | `total_blocks / 8` | 1 bit per block |
| reserved_blocks_bitmap | same | blocks 0..4 by default |
| retired_blocks_bitmap | same | **Phase 5b** |
| erase_counts[] | `total_blocks × 2` | uint16 per block |
| live_bytes_per_block[] | `total_blocks × 4` | **Phase 2 prep** |
| dead_bytes_per_block[] | same | **Phase 2 prep** |

Layout buffer is sized `sizeof(meta) + 3 * bitmap_bytes + ec_bytes + 2 * 4 * total_blocks`.
For 16 blocks / 4 KiB erase: 56 + 3 + 6 + 32 + 32 + 32 = 161 B (well within the 4 KiB FTL state).
For 512 blocks / 128 KiB erase: 56 + 24 + 16 + 1024 + 1024 + 1024 = 3168 B (within 128 KiB).

Only v3 records are accepted on load. v1 / v2 records are
rejected → factory scan. The on-flash format version `PGFS_ONDISK_VERSION`
(for CP/SB) and `PGFS_FTL_VERSION` (for FTL) are independently versioned.

### 4.4 Data log records

Three record types are emitted to the data log:

| Magic | Type | Layout |
| --- | --- | --- |
| `0x50474644` | `DATA` | 24 B header + path + data |
| `0x50474642` | `BATCH_DATA` | 24 B header + path + data (pending until commit) |
| `0x50474643` | `BATCH_COMMIT` | 24 B header (batch_id, record_count) |

Header layout (all three):

| Field | Size | Notes |
| --- | --- | --- |
| `magic` | 4 | record type |
| path_len / batch_id / record_count | 4 | depends on type |
| data_len | 4 | data length (0 for BATCH_COMMIT) |
| crc32 | 4 | over `header[0..crc32)` (excludes `ecc`) + path + data |
| `ecc[8]` | 8 | **Phase 3b**: XOR parity placeholder sized for Hamming(72,64) drop-in |

The CRC scope is `offsetof(..., crc32)` so it does not include the
parity field (setting parity would otherwise invalidate the stored CRC).

Storage alignment is `prog_size` (256 B default) so a record can span
two erase blocks; the live-bytes accounting attributes the whole
contribution to the block containing the record's start address.

## 5. Commit and Recovery

### 5.1 `fclose` (the durability boundary)

`pgfs_file_close`:

1. Run `pgfs_gc_step(4096, 2000)` — one victim per close, budgeted.
2. `pgfs_alloc_segment` — find a non-bad, non-reserved, lowest-erase-count
   data log block.
3. `pgfs_append_data_record` — append the DATA record. Credits
   `live_bytes_per_block[start_block]`. Updates `entry->last_written_block`.
4. **Phase 2 GC dead attribution**: the OLD `last_written_block` +
   `len` are attributed to `dead_bytes_per_block[old_block]`. This is
   the runtime source of dead bytes.
5. `pgfs_apply_cache_to_entry` — moves the cache into the entry.
6. `pgfs_checkpoint_commit_pending` — if `pending_checkpoint_writes`
   has reached `PGFS_CHECKPOINT_BATCH_CLOSES`, write CP + SB.

`pgfs_checkpoint_store_next` (called by commit):

1. Read geometry, set `log_tail_block` / `log_tail_offset` from
   `ctx->data_log_write_addr`.
2. Erase CP + SB blocks, write new CP, verify readback, write new SB,
   verify readback.

### 5.2 Power-loss injection

`ctx->inject_powercut_stage` selects a hook point:

| Constant | Effect |
| --- | --- |
| `PGFS_INJECT_POWERCUT_BEFORE_APPEND` | `fclose` returns -1, no DATA written |
| `PGFS_INJECT_POWERCUT_AFTER_APPEND_ERASE` | region prepared but not written |
| `PGFS_INJECT_POWERCUT_AFTER_APPEND` | DATA written, not committed |
| `PGFS_INJECT_POWERCUT_AFTER_CP_ERASE` | CP/SB erased, not rewritten |
| `PGFS_INJECT_POWERCUT_AFTER_CP_WRITE` | CP written, SB not |

Stages 3 / 4 (legacy) are forwarded to the FTL erase / write injects.

### 5.3 Mount

1. `pgfs_checkpoint_load` — pick the latest valid CP by seq + CRC.
2. If no valid CP, `pgfs_rebuild_checkpoint_from_replay` (also re-creates
   the FTL state if needed).
3. **Phase 4b O(1) skip**: if a CP was loaded, do an early
   `pgfs_ftl_on_mount` to load the FTL state, then run
   `pgfs_checkpoint_is_consistent_with_ftl(cp, ftl)`. If true, skip
   `pgfs_replay_data_log`. Otherwise, do the full replay.
4. `pgfs_ftl_on_mount` (idempotent for init) does the reserved-bit
   marking, optional factory scan on fresh flash, and (now that init
   is idempotent) just runs through to completion if called twice.

### 5.4 `pgfs_checkpoint_is_consistent_with_ftl` (Phase 4b)

Returns `true` iff `cp->log_tail_block == ftl->write_head_block &&
cp->log_tail_offset == ftl->write_head_offset` AND neither pair is
zero. A zero pair means the CP was written before Phase 4b plumbing
existed (legacy v2 / v3 record with no log_tail populated) and forces
the safe replay path. The CP-side `log_tail_*` is set by
`pgfs_checkpoint_store_next`; the FTL-side `write_head_*` is set by
`pgfs_ftl_on_checkpoint_commit` immediately before `pgfs_ftl_persist`.

## 6. Per-Block Live/Dead Accounting (Phase 2 prep)

The cost-benefit GC needs to know "how much live data and how much
dead data is in each block". The bookkeeping is split between two
counters per block in `pgfs_nand_ftl_ctx_t`:

- `live_bytes_per_block[id]`: bytes contributed by a current (not
  shadowed) record whose start address falls in this block. Updated
  by `pgfs_account_live_block` in three places:
  - `pgfs_append_data_record` after a successful DATA append
    (also writes `entry->last_written_block`)
  - `pgfs_replay_data_log` for each replayed DATA record
- `dead_bytes_per_block[id]`: bytes contributed by shadowed or
  deleted records whose source block is `id`. Updated by:
  - `pgfs_file_close` (overwrite case): attributes the previous
    `len` to the OLD `last_written_block`
  - `pgfs_file_remove`: attributes the file's `len` to its
    `last_written_block`
  - **TODO**: replay shadow detection (would attribute earlier
    records of the same path when a later record shadows them)

Both arrays are persisted in the v3 FTL state and round-trip via
`pgfs_ftl_persist` / `pgfs_ftl_load`.

## 7. Cost-Benefit Garbage Collection (Phase 2)

### 7.1 Victim selection

`pgfs_gc_pick_victim` iterates the data log blocks (skipping bad /
reserved / retired) and scores each by:

```
score = (dead_bytes[id] + free_bytes[id]) / (erase_count[id] + 1)
```

where `free_bytes[id] = erase_size - live_bytes[id]`. The block with
the highest score is picked.

### 7.2 Data move

`pgfs_gc_rewrite_victim` walks the in-memory file table via
`pgfs_file_table_visit`. For every entry whose
`last_written_block == victim`, it re-appends the entry's data to
the data log. The visitor forces the data log write head past the
victim before appending so the new record lands in a different block.

### 7.3 Step

`pgfs_gc_step`:

1. Pick victim via `pgfs_gc_pick_victim`.
2. If `live_bytes[victim] > 0`, call `pgfs_gc_rewrite_victim`. If
   the move returns 0, the step returns 0 (no retirement) to avoid
   losing data.
3. Zero the victim's `live_bytes` and `dead_bytes` (the moved
   records are now credited to their new blocks).
4. Call `pgfs_mark_block_retired` (sets the retired bit + CP flag
   `0x01u`).

The current implementation retires any non-empty block whose
file_entries can be moved. The "score still works for empty blocks"
case is the trivial safety net — any block with `live_bytes == 0` is
safe to retire.

## 8. Bad / Reserved / Retired / Weak Blocks

`pgfs_nand_ftl_ctx_t` carries four bitmaps, each `(total_blocks+7)/8`
bytes, persisted in the v3 FTL record:

| Bitmap | Phase | Set by | Allocation skips? |
| --- | --- | --- | --- |
| `bad_blocks_bitmap` | initial | `pgfs_ftl_mark_block_bad` on erase failure | yes |
| `reserved_blocks_bitmap` | 1 | `pgfs_ftl_on_mount` (blocks 0..4 by default) | yes |
| `retired_blocks_bitmap` | 5b | `pgfs_mark_block_retired` | yes (Phase 5b) |
| `weak_blocks_bitmap` | 3 | `pgfs_replay_data_log` on ECC-correctable read | no (still used) |

The three "skip" bitmaps are independent so a block can be:
- bad-only (hardware failure)
- retired-only (GC moved data out, erase pending)
- bad-and-retired (retired first, then erase failed)

A separate "weak" state tracks "degraded but still usable" so the
allocator doesn't skip it but the GC prefers to reclaim it.

## 9. Flash Backend Interface

`pgfs_flash_opts_t` — exactly four function pointers:

```c
int  (*read) (void* ctx, uint32_t addr, uint8_t* buf, size_t len);
int  (*write)(void* ctx, uint32_t addr, const uint8_t* buf, size_t len);
int  (*erase)(void* ctx, uint32_t block_addr, uint32_t block_count);
int  (*control)(void* ctx, uint32_t cmd, void* arg);
```

`control` minimum capabilities:
- `PGFS_CTRL_GET_GEOMETRY` → `pgfs_flash_geometry_t`
- `PGFS_CTRL_MARK_BLOCK_BAD` (test injection)
- `PGFS_CTRL_INJECT_BAD_BLOCK_ONCE` (test injection)

## 10. VFS Integration

`pgfs_vfs_adapter.c` exposes the LuatOS VFS operations:

| Op | Implementation |
| --- | --- |
| `mount` | `luat_vfs_pgfs_mount` (see §5.3) |
| `umount` | `luat_vfs_pgfs_umount` |
| `info` | `pgfs_info_fast` — reads in-memory CP, no scan |
| `fopen` | `pgfs_file_open` |
| `fread` | `pgfs_file_read` — reads from in-memory file entry |
| `fwrite` | `pgfs_file_write` — appends to per-file cache |
| `fflush` | no-op (cache flush is folded into `fclose`) |
| `fclose` | `pgfs_file_close` (see §5.1) |
| `fseek` / `ftell` | `pgfs_file_seek` / `pgfs_file_tell` |
| `remove` | `pgfs_file_remove` (attributes dead bytes) |
| `mkdir` / `rmdir` | `pgfs_dir_mkdir` / `pgfs_dir_rmdir` |
| `lsdir` / `opendir` / `closedir` | `pgfs_dir_lsdir` / `pgfs_dir_opendir` / `pgfs_dir_closedir` |

## 11. Concurrency

`pgfs_lock` / `pgfs_unlock` are optional. When the lock is taken
(`pgfs_mount_ctx_t.lock_mode != 0`), it serialises:
- `fopen` / `fclose` / `fread` / `fwrite` / `fseek`
- `remove` / `mkdir` / `rmdir` / `lsdir`
- the GC step
- the FTL on_checkpoint_commit hook

`info()` and the read-only data log path are lock-free.

## 12. Test Matrix

`pgfs_basic` covers:
- Phase 0: `pgfs_test_layout_compute_64mb`
- Phase 1: `pgfs_test_reserved_blocks_never_allocated`,
  `pgfs_test_reserved_bitmap_persists_roundtrip`
- Phase 2 prep: `pgfs_test_live_dead_per_block_roundtrip`,
  `pgfs_test_per_block_live_updates_on_write`
- Phase 2 GC: `pgfs_test_gc_step_returns_zero_when_nothing_to_reclaim`,
  `pgfs_test_gc_step_retires_empty_block`,
  `pgfs_test_gc_picks_lowest_erase_count_among_empties`,
  `pgfs_test_gc_excludes_bad_reserved_retired`,
  `pgfs_test_gc_data_move_preserves_file`
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
- Pre-existing: wear-levelling alloc, CP-erase powercut recovery,
  FTL state skip, single-block retirement, FTL persist snapshot,
  FTL persist readback failure.

PC backend validation:
- minimal mount/read/write loop
- close durability (with powercut injection at every stage)
- recovery matrix
- stress / fragmentation / reclaim

## 13. Phase Changelog

| Phase | Description | On-disk impact |
| --- | --- | --- |
| 0 | Layout struct, version bump, 64 MiB slab | bumps `PGFS_ONDISK_VERSION` 1→2 |
| 1 | Reserved block bitmap, layout-driven FTL init | adds `reserved_blocks_bitmap` to FTL v2 |
| 2 | Placeholder (disable anti-wear-levelling GC) | none |
| 3 | Weak-block tracking, ECC placeholder | adds `weak_blocks_bitmap` to FTL |
| 3b | Per-record header ECC, CRC scope fix | adds `ecc[8]` to record headers, widens CRC scope |
| 4 | O(1) mount consistency check scaffolding | none (returns false unconditionally) |
| 4b | O(1) mount skip activated | adds `log_tail_*` to CP, `write_head_*` + `log_tail_*` to FTL v2; bumps `PGFS_ONDISK_VERSION` 2→3 |
| 5 | Retired vs bad separation | semantically separate `pgfs_mark_block_retired` from `pgfs_ftl_mark_block_bad` |
| 5b | Retired bitmap persisted | adds `retired_blocks_bitmap` to FTL; bumps `PGFS_FTL_VERSION` 2→3 |
| 2 prep | Per-block live/dead byte accounting | adds `live_bytes_per_block[]` + `dead_bytes_per_block[]` to FTL v3 |
| 2 | Cost-benefit GC: victim picker + retirement + data move | none (runtime + future replay shadow detection) |

## 14. Non-Goals

- No OOB tag dependency.
- No compression.
- No extreme-minimum-RAM mode at the expense of correctness.

## 15. Acceptance Criteria

Design is accepted when:
1. `fclose` durability boundary holds under fault injection at
   every stage of the close-commit path.
2. Mount recovers deterministically across interrupted commits.
3. `info()` returns in < 1 ms in steady state (no scan).
4. NAND bad-block handling does not violate data consistency.
5. The Phase 4b O(1) skip path activates on a clean remount when
   the CP and FTL write heads agree.
6. The Phase 2 GC reclaims empty data log blocks without
   ever losing data (verified by `pgfs_test_gc_data_move_preserves_file`).
