# PGFS Component AI Notes

This file captures practical guidance for AI-assisted work under `components/pgfs/`.

## Flash backend contract (read this before assuming FTL features)

- `components/pgfs/` mounts over little_flash (see `components/little_flash/inc/little_flash_ftl.h` for the public FTL header).
- The little_flash "FTL" layer is **static bad-block replacement only**, NOT a true FTL. It provides:
  - Per-page mapping (l2p/p2l) for static bad-block replacement
  - Double-slot checkpoint + remap journal
  - O(1) find_spare via bitmap (since F-10)
- It does NOT provide: dynamic block reclaim, erase-count wear-leveling, GC stalls, l2p/p2l compression.
- Treat as MTD + journal, not FTL. If you find yourself assuming WL/GC behavior at the pgfs layer, that's a pgfs-side bug — pgfs owns its own checkpointing and crash recovery, but the FTL beneath it does not give write-amplification guarantees.
- Full scope of the FTL layer's known gaps: `docs/audit/track_b_ftl_layer.md` §1 (F-01..F-10) and §10 (5-phase plan).

## Scope

- Component: `components/pgfs/`
- Mount integration: `components/little_flash/luat_lib_little_flash.c`
- PC enable path: `bsp/pc/include/luat_conf_bsp.h` (`LUAT_USE_PGFS_COMPONENT`)

## Key contracts

1. **Durability boundary**
   - Writes may stay in cache before close.
   - `fclose` success is the durability point.
   - Any injected failure before checkpoint commit must make `fclose` fail.

2. **Flash backend ABI (4 ops only)**
   - `read/write/erase/control`
   - Keep PC and device backends behind this interface.

3. **Generation recovery**
   - Superblock/checkpoint dual-generation selection uses seq + CRC validity.
   - Newer generation corruption must fall back to older valid generation.

4. **Feature gating**
   - Use `LUAT_USE_PGFS_COMPONENT` guards in mixed modules (`little_flash`, adapters).
   - Do not rely on `xmake add_defines` for this macro in PC; declare it in `luat_conf_bsp.h`.

## Recommended verification (PC)

From `bsp/pc`:

```powershell
cmd /c build_windows_32bit_msvc.bat
.\build\out\luatos-lua.exe ..\..\testcase\common\scripts\ ..\..\testcase\unit_testcase_tools\pgfs_basic\scripts\
.\build\out\luatos-lua.exe ..\..\testcase\common\scripts\ ..\..\testcase\pgfs_regression\pgfs_regression_basic\scripts\
```

## Current regression focus

- `pgfs_basic`: generation fallback, close durability, info rebuild, control invalid args, C selftests.
- `pgfs_regression_basic`: lock toggle, GC churn, bad-block-once hook, write+close performance trace.
- Performance trace log key:
  - `trace_total_stall_us=<value>`

## Common pitfalls

- Prefer `mcu.ticks()` for timing in PC tests; `rtos.tick()` may be unavailable.
- Mount-point reuse in the same process can hit VFS mount limits; reuse mounted flash context in suites.
- Keep test assertions deterministic; avoid depending on one specific failure spot when fault injection is probabilistic by design.
