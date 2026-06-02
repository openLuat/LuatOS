# PGFS Component AI Notes

This file captures practical guidance for AI-assisted work under `components/pgfs/`.

## Scope

- Component: `components/pgfs/`
- Mount integration: `components/little_flash/luat_lib_little_flash.c`
- PC enable path: `bsp/pc/include/luat_conf_bsp.h` (`LUAT_USE_PGFS_COMPONENT`)

## Key contracts

1. **Durability boundary**
   - Writes may stay in cache before close.
   - `fclose` success is the durability point.
   - Any injected failure before checkpoint commit must make `fclose` fail.
   - `pgfs_cache_flush_to_log` is intentionally a no-op; callers that need explicit
     durability should use `fclose()` rather than `fflush()`.

2. **Flash backend ABI (4 ops only)**
   - `read/write/erase/control`
   - Keep PC and device backends behind this interface.
   - Real NAND chips (W25N01GVZEIG, MX35LF512) use **128KB erase blocks** with
     4KB sub-page program granularity; the architecture now tolerates this.

3. **NAND FTL state layout**
   - CP slots: `PGFS_CHECKPOINT_A_ADDR` / `PGFS_CHECKPOINT_B_ADDR`.
   - FTL state erase-unit: computed as `align_up(PGFS_CHECKPOINT_B_ADDR + erase_size, erase_size)`.
   - Data log base: `pgfs_data_log_base_addr()` snaps past the FTL state when the
     FTL is initialized (i.e. a real NAND layout is in use). Without FTL, the
     legacy `PGFS_DATA_LOG_BASE_ADDR` is used.
   - The data log prepare path (`pgfs_prepare_data_log_region`) splits the erase
     range around the FTL state region so a write head crossing the FTL block
     does not destroy the persisted FTL state.

4. **Generation recovery**
   - Superblock/checkpoint dual-generation selection uses seq + CRC validity.
   - Newer generation corruption must fall back to older valid generation.
   - On checkpoint commit, the FTL state (bad-block bitmap + erase counts) is
     re-persisted alongside the CP so runtime-discovered bad blocks and
     wear-levelling counters survive an unexpected power loss.

5. **CP/SB write safety**
   - `pgfs_checkpoint_store_next` performs a readback + CRC verify after every
     CP and SB write. A bad readback aborts the store so the old SB/CP pair on
     the alternate slot remains authoritative.
   - `pgfs_ftl_persist` similarly readback-verifies the FTL state. On failure
     the previous `last_persist_buf` snapshot is preserved so recovery is still
     possible.

6. **Wear-levelling**
   - `pgfs_alloc_segment` picks the non-bad block with the lowest `erase_counts`
     entry, scanning from `gc_next_seg_id` to `total_blocks` (with a wrap to the
     start when no good block is found in the first pass).

7. **Feature gating**
   - Use `LUAT_USE_PGFS_COMPONENT` guards in mixed modules (`little_flash`, adapters).
   - Do not rely on `xmake add_defines` for this macro in PC; declare it in `luat_conf_bsp.h`.

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

## Current regression focus

- `pgfs_basic`: generation fallback, close durability, info rebuild, control invalid args, C selftests.
  - Includes new C-level tests for: wear-levelling alloc, CP-erase powercut recovery,
    FTL state skip, single-block retirement, FTL persist snapshot, FTL persist
    readback failure.
  - `pgfs_test_fill_delete_rewrite_recovers_capacity` is intentionally not in the
    default `c_layer_selftests` dispatch — it depends on data-log compaction
    after file deletion, which is not yet implemented. Run it explicitly via
    `pgfs.utest("fill_delete_rewrite_recovers_capacity")` if needed.
- `pgfs_regression_basic`: lock toggle, GC churn, bad-block-once hook, write+close performance trace.
- Performance trace log key:
  - `trace_total_stall_us=<value>`

## Test infrastructure notes

- `pgfs_test_flash_t` is heap-allocated from a shared 16MB static slab. The
  default test flash size is 32KB with 4KB erase (matches the original layout).
  Tests that exercise NAND geometry (W25N01GVZEIG / MX35LF512) set
  `flash->capacity_override = 0x1000000` and `flash->erase_size_override = 128*1024`.
- `pgfs_data_log_base_addr(ctx)` snaps the data log base past the FTL state
  region **only when `ctx.ftl.total_blocks != 0`** (i.e. FTL has been
  initialised). Tests that don't init the FTL keep the legacy layout.

## Common pitfalls

- Prefer `mcu.ticks()` for timing in PC tests; `rtos.tick()` may be unavailable.
- Mount-point reuse in the same process can hit VFS mount limits; reuse mounted flash context in suites.
- Keep test assertions deterministic; avoid depending on one specific failure spot when fault injection is probabilistic by design.
- The lazy FTL init in `pgfs_alloc_segment` triggers on first allocation — tests
  that intend to verify the "no FTL" path must call `pgfs_alloc_segment` with
  a context that already has the FTL initialised, or exercise the code paths
  that don't go through the allocator.
- The CP commit calls `pgfs_ftl_on_checkpoint_commit` which always invokes
  `pgfs_ftl_persist`. With the FTL initialised this writes to the FTL state
  region on flash, consuming space in the data log area on the small 32KB test
  flash. Tests should account for this when sizing data log writes.
