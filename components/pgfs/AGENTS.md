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
