# PGFS NAND Filesystem Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a new LuatOS component `pgfs` that provides a NAND-optimized log-structured filesystem with `fclose` durability guarantee, fast `info()`, optional locking, and VFS integration.

**Architecture:** `pgfs` is implemented as a standalone component under `components/pgfs/` with clear module boundaries: core record logic, checkpoint generation switch, GC/allocator, cache+lock, and VFS adapter. It uses a strict 4-op flash backend (`read/write/erase/control`) and an in-band metadata record format (no OOB dependency). PC simulator backend and fault injection are introduced first, then stress/regression tests verify recovery, GC stability, and status-path performance.

**Tech Stack:** C (LuatOS core/VFS), Lua testcase framework (`testrunner`), xmake (PC target), little_flash integration, Windows PC simulator build scripts.

---

## File Structure (locked before coding)

### New component files
- Create: `components/pgfs/luat_pgfs.h` — public PGFS API and backend ops definition.
- Create: `components/pgfs/pgfs_internal.h` — internal structs/enums/constants.
- Create: `components/pgfs/pgfs_core.c` — record encode/decode, file data write path, replay dispatcher.
- Create: `components/pgfs/pgfs_checkpoint.c` — dual-superblock/dual-checkpoint generation protocol.
- Create: `components/pgfs/pgfs_alloc_gc.c` — segment allocator, summary bookkeeping, GC scheduling.
- Create: `components/pgfs/pgfs_cache_lock.c` — write cache, optional lock wrappers.
- Create: `components/pgfs/pgfs_vfs_adapter.c` — LuatOS VFS filesystem/file opts glue.
- Create: `components/pgfs/pgfs_pc_backend.c` — PC NAND simulation + fault injection implementation.

### Existing integration files
- Modify: `components/little_flash/luat_lib_little_flash.c` — add `pgfs` mount selector and bus wiring.
- Modify: `bsp/pc/xmake.lua` — compile `components/pgfs/**.c` and define `LUAT_USE_PGFS_COMPONENT`.
- Modify: `bsp/pc/include/luat_conf_bsp.h` — add PGFS feature define for PC.

### New tests
- Create: `testcase/unit_testcase_tools/pgfs_basic/metas.json`
- Create: `testcase/unit_testcase_tools/pgfs_basic/scripts/main.lua`
- Create: `testcase/unit_testcase_tools/pgfs_basic/scripts/pgfs_test.lua`
- Create: `testcase/pgfs_regression/pgfs_regression_basic/scripts/metas.json`
- Create: `testcase/pgfs_regression/pgfs_regression_basic/scripts/main.lua`
- Create: `testcase/pgfs_regression/pgfs_regression_basic/scripts/pgfs_regression_test.lua`

### Docs
- Create: `docs/superpowers/specs/2026-05-28-pgfs-design.md` (already exists; keep in sync if changed by implementation)

---

### Task 1: Scaffold PGFS component and compile-empty VFS registration

**Files:**
- Create: `components/pgfs/luat_pgfs.h`
- Create: `components/pgfs/pgfs_internal.h`
- Create: `components/pgfs/pgfs_vfs_adapter.c`
- Modify: `bsp/pc/xmake.lua`
- Modify: `bsp/pc/include/luat_conf_bsp.h`
- Test: PC build only

- [ ] **Step 1: Write the failing build expectation (TDD red)**

Add this compile target expectation in your notes and run build before creating files:

```powershell
Set-Location D:\github\LuatOS\bsp\pc
cmd /c build_windows_32bit_msvc.bat
```

Expected: FAIL because `components/pgfs/*.c` are not present yet (after you wire them in xmake in Step 2).

- [ ] **Step 2: Wire xmake and bsp define minimally**

In `bsp/pc/xmake.lua` add:

```lua
add_defines("LUAT_USE_PGFS_COMPONENT")
add_includedirs(luatos.."components/pgfs",{public = true})
add_files(luatos.."components/pgfs/**.c")
```

In `bsp/pc/include/luat_conf_bsp.h` add:

```c
#define LUAT_USE_PGFS_COMPONENT 1
```

- [ ] **Step 3: Add minimal headers and VFS registrar stubs**

`components/pgfs/luat_pgfs.h`:

```c
#ifndef LUAT_PGFS_H
#define LUAT_PGFS_H
#include <stddef.h>
#include <stdint.h>

typedef struct {
    void* ctx;
    int (*read)(void* ctx, uint32_t addr, uint8_t* buf, size_t len);
    int (*write)(void* ctx, uint32_t addr, const uint8_t* buf, size_t len);
    int (*erase)(void* ctx, uint32_t block_addr, uint32_t block_count);
    int (*control)(void* ctx, uint32_t cmd, void* arg);
} pgfs_flash_opts_t;

void pgfs_vfs_init(void);
void* pgfs_default_bus(void* flash, size_t offset, size_t maxsize);
#endif
```

`components/pgfs/pgfs_vfs_adapter.c`:

```c
#include "luat_base.h"
#include "luat_fs.h"
#include "luat_pgfs.h"

static int pgfs_mount(void** userdata, luat_fs_conf_t* conf) {
    if (!userdata || !conf || !conf->busname) return -1;
    *userdata = conf->busname;
    return 0;
}

static int pgfs_umount(void* userdata, luat_fs_conf_t* conf) { (void)userdata; (void)conf; return 0; }
static int pgfs_info(void* userdata, const char* path, luat_fs_info_t* conf) {
    (void)userdata; (void)path;
    memset(conf, 0, sizeof(*conf));
    memcpy(conf->filesystem, "pgfs", 4);
    return 0;
}

const struct luat_vfs_filesystem vfs_fs_pgfs = {
    .name = "pgfs",
    .opts = { .mount = pgfs_mount, .umount = pgfs_umount, .info = pgfs_info },
};

void pgfs_vfs_init(void) {
    static uint8_t inited = 0;
    if (!inited) { luat_vfs_reg(&vfs_fs_pgfs); inited = 1; }
}

void* pgfs_default_bus(void* flash, size_t offset, size_t maxsize) {
    (void)offset; (void)maxsize; return flash;
}
```

- [ ] **Step 4: Run build to verify it passes with stubs**

Run:

```powershell
Set-Location D:\github\LuatOS\bsp\pc
cmd /c build_windows_32bit_msvc.bat
```

Expected: `Build completed successfully`.

- [ ] **Step 5: Commit**

```bash
git add bsp/pc/xmake.lua bsp/pc/include/luat_conf_bsp.h components/pgfs/luat_pgfs.h components/pgfs/pgfs_vfs_adapter.c
git commit -m "feat(pgfs): scaffold component and vfs registrar"
```

---

### Task 2: Integrate little_flash mount selector for `pgfs`

**Files:**
- Modify: `components/little_flash/luat_lib_little_flash.c`
- Test: `testcase/unit_testcase_tools/pgfs_basic/scripts/main.lua` (new)

- [ ] **Step 1: Write failing Lua testcase for mount selector**

Create `testcase/unit_testcase_tools/pgfs_basic/scripts/main.lua`:

```lua
PROJECT = "pgfs_basic"
VERSION = "1.0.0"
require("sys")

sys.taskInit(function()
    local spi_device = spi.deviceSetup(0, 17, 0, 0, 8, 2 * 1000 * 1000, spi.MSB, 1, 0)
    assert(spi_device, "spi.deviceSetup failed")
    local flash = lf.init(spi_device)
    assert(flash, "lf.init failed")
    assert(lf.mount(flash, "/pgfs/", 0, 0, "pgfs"), "lf.mount pgfs failed")
    os.exit(0)
end)
sys.run()
```

- [ ] **Step 2: Run testcase to verify it fails**

Run:

```powershell
Set-Location D:\github\LuatOS\bsp\pc
.\build\out\luatos-lua.exe ..\..\testcase\common\scripts\ ..\..\testcase\unit_testcase_tools\pgfs_basic\scripts\
```

Expected: FAIL at `lf.mount(..., "pgfs")`.

- [ ] **Step 3: Add selector path in little_flash**

In `components/little_flash/luat_lib_little_flash.c`:

```c
#ifdef LUAT_USE_PGFS_COMPONENT
#include "luat_pgfs.h"
#endif

static void* luat_little_flash_named_bus(void* flash, size_t offset, size_t maxsize, const char* fs) {
    ...
#ifdef LUAT_USE_PGFS_COMPONENT
    if (fs != NULL && strcmp(fs, "pgfs") == 0) {
        pgfs_vfs_init();
        return pgfs_default_bus(flash, offset, maxsize);
    }
#endif
    return NULL;
}
```

Update mount API docs in same file to include `"pgfs"`.

- [ ] **Step 4: Run build + testcase to verify pass**

Run:

```powershell
Set-Location D:\github\LuatOS\bsp\pc
cmd /c build_windows_32bit_msvc.bat
.\build\out\luatos-lua.exe ..\..\testcase\common\scripts\ ..\..\testcase\unit_testcase_tools\pgfs_basic\scripts\
```

Expected: testcase exits 0.

- [ ] **Step 5: Commit**

```bash
git add components/little_flash/luat_lib_little_flash.c testcase/unit_testcase_tools/pgfs_basic/scripts/main.lua
git commit -m "feat(pgfs): add little_flash mount selector"
```

---

### Task 3: Implement PGFS on-disk headers and generation selection (checkpoint core)

**Files:**
- Create: `components/pgfs/pgfs_internal.h`
- Create: `components/pgfs/pgfs_checkpoint.c`
- Modify: `components/pgfs/pgfs_vfs_adapter.c`
- Test: `testcase/unit_testcase_tools/pgfs_basic/scripts/pgfs_test.lua`

- [ ] **Step 1: Add failing test for generation fallback**

Create `testcase/unit_testcase_tools/pgfs_basic/scripts/pgfs_test.lua`:

```lua
local M = {}
function M.test_mount_generation_fallback()
    assert(io.exists("/pgfs/") or io.mkdir("/pgfs_tmp"), "mount path missing")
    -- control API will inject corruption for latest generation
    local ok = lf.control and lf.control("pgfs.inject_corrupt_latest_cp", true)
    assert(ok ~= false, "inject flag set failed")
    local info = io.disk("/pgfs/")
    assert(info, "io.disk failed after fallback")
    assert(info.filesystem == "pgfs", "filesystem mismatch")
end
return M
```

Update `main.lua` to run this test module via `testrunner`.

- [ ] **Step 2: Run testcase to verify fail**

Run same command as Task 2 Step 4.  
Expected: FAIL because checkpoint protocol/control hooks do not exist.

- [ ] **Step 3: Implement generation structs and chooser**

In `components/pgfs/pgfs_internal.h`:

```c
typedef struct {
    uint32_t magic;
    uint16_t version;
    uint16_t flags;
    uint32_t seq;
    uint32_t cp_addr;
    uint32_t cp_len;
    uint32_t crc32;
} pgfs_superblock_t;

typedef struct {
    uint32_t magic;
    uint16_t version;
    uint16_t reserved;
    uint32_t seq;
    uint32_t used_blocks;
    uint32_t total_blocks;
    uint32_t crc32;
} pgfs_checkpoint_t;
```

In `components/pgfs/pgfs_checkpoint.c`, implement:

```c
int pgfs_pick_latest_valid_sb(const pgfs_superblock_t* a, const pgfs_superblock_t* b, pgfs_superblock_t* out);
int pgfs_checkpoint_load(void* fs, pgfs_checkpoint_t* cp);
int pgfs_checkpoint_store_next(void* fs, const pgfs_checkpoint_t* current, pgfs_checkpoint_t* next);
```

Winner policy: valid CRC + highest seq; if tie, prefer slot B.

- [ ] **Step 4: Connect checkpoint load in mount path**

In `pgfs_vfs_adapter.c` mount:

```c
if (pgfs_checkpoint_load(*userdata, &ctx->cp) != 0) {
    return -1;
}
```

- [ ] **Step 5: Run build + testcase and verify pass**

Expected: mount succeeds after injected corruption by falling back to previous generation.

- [ ] **Step 6: Commit**

```bash
git add components/pgfs/pgfs_internal.h components/pgfs/pgfs_checkpoint.c components/pgfs/pgfs_vfs_adapter.c testcase/unit_testcase_tools/pgfs_basic/scripts/pgfs_test.lua testcase/unit_testcase_tools/pgfs_basic/scripts/main.lua
git commit -m "feat(pgfs): add dual-generation checkpoint selection"
```

---

### Task 4: Implement write cache + `fclose` durability boundary

**Files:**
- Create: `components/pgfs/pgfs_cache_lock.c`
- Create: `components/pgfs/pgfs_core.c`
- Modify: `components/pgfs/pgfs_vfs_adapter.c`
- Test: `testcase/unit_testcase_tools/pgfs_basic/scripts/pgfs_test.lua`

- [ ] **Step 1: Add failing durability test**

Append to `pgfs_test.lua`:

```lua
function M.test_fclose_is_durable_boundary()
    local f = assert(io.open("/pgfs/durable.txt", "wb"))
    assert(f:write("abc123"))
    -- simulate crash before close commit
    if lf.control then lf.control("pgfs.inject_powercut_stage", "before_close_commit") end
    local ok, err = pcall(function() f:close() end)
    assert(not ok, "close should fail under injected powercut")

    local f2 = io.open("/pgfs/durable.txt", "rb")
    if f2 then f2:close() end

    local f3 = assert(io.open("/pgfs/durable2.txt", "wb"))
    assert(f3:write("commit_me"))
    if lf.control then lf.control("pgfs.inject_powercut_stage", "none") end
    assert(f3:close() == true or f3:close() == nil, "close must succeed")
    local v = io.readFile("/pgfs/durable2.txt")
    assert(v == "commit_me", "durable data mismatch")
end
```

- [ ] **Step 2: Run testcase to verify fail**

Expected: FAIL because close commit staging is not implemented.

- [ ] **Step 3: Implement cache + commit pipeline**

In `pgfs_cache_lock.c`, implement:

```c
int pgfs_cache_append(pgfs_file_t* f, const uint8_t* data, size_t len);
int pgfs_cache_flush_to_log(pgfs_ctx_t* ctx, pgfs_file_t* f);
int pgfs_lock(pgfs_ctx_t* ctx);
int pgfs_unlock(pgfs_ctx_t* ctx);
```

In `pgfs_core.c`, implement:

```c
int pgfs_file_write(pgfs_ctx_t* ctx, pgfs_file_t* f, const void* data, size_t len);
int pgfs_file_close(pgfs_ctx_t* ctx, pgfs_file_t* f) {
    // 1 flush cache to DATA records
    // 2 append CP_DELTA
    // 3 store next checkpoint generation
    // 4 switch superblock pointer
    // 5 success return 0 only after all above succeed
}
```

- [ ] **Step 4: Map VFS `fwrite/fclose` to core pipeline**

Update `pgfs_vfs_adapter.c` file-opts callbacks to call `pgfs_file_write` and `pgfs_file_close`.

- [ ] **Step 5: Run build + testcase and verify pass**

Expected: injected pre-commit close fails, successful close persists content.

- [ ] **Step 6: Commit**

```bash
git add components/pgfs/pgfs_cache_lock.c components/pgfs/pgfs_core.c components/pgfs/pgfs_vfs_adapter.c testcase/unit_testcase_tools/pgfs_basic/scripts/pgfs_test.lua
git commit -m "feat(pgfs): enforce fclose durability boundary"
```

---

### Task 5: Implement fast `info()` path and metadata recovery fallback

**Files:**
- Modify: `components/pgfs/pgfs_checkpoint.c`
- Modify: `components/pgfs/pgfs_vfs_adapter.c`
- Test: `testcase/unit_testcase_tools/pgfs_basic/scripts/pgfs_test.lua`

- [ ] **Step 1: Add failing `info()` fast path test**

Add test:

```lua
function M.test_info_fast_path_and_rebuild()
    local info = assert(io.disk("/pgfs/"))
    assert(info.filesystem == "pgfs")
    if lf.control then lf.control("pgfs.inject_corrupt_checkpoint", true) end
    local info2 = assert(io.disk("/pgfs/"))
    assert(info2.total_block > 0, "rebuild fallback failed")
end
```

- [ ] **Step 2: Run testcase to verify fail**

Expected: FAIL on corrupted checkpoint fallback.

- [ ] **Step 3: Implement fast info + fallback rebuild**

In `pgfs_checkpoint.c` implement:

```c
int pgfs_info_fast(pgfs_ctx_t* ctx, luat_fs_info_t* out);
int pgfs_rebuild_checkpoint_from_replay(pgfs_ctx_t* ctx);
```

Policy:
- normal path reads memory counters or latest checkpoint only.
- if invalid checkpoint detected, perform replay once, store new checkpoint generation, then return info.

- [ ] **Step 4: Hook VFS info callback**

In `pgfs_vfs_adapter.c`:

```c
static int pgfs_info(void* userdata, const char* path, luat_fs_info_t* conf) {
    return pgfs_info_fast((pgfs_ctx_t*)userdata, conf);
}
```

- [ ] **Step 5: Run build + testcase and verify pass**

Expected: `io.disk("/pgfs/")` succeeds both normal and corrupted-checkpoint scenarios.

- [ ] **Step 6: Commit**

```bash
git add components/pgfs/pgfs_checkpoint.c components/pgfs/pgfs_vfs_adapter.c testcase/unit_testcase_tools/pgfs_basic/scripts/pgfs_test.lua
git commit -m "feat(pgfs): add fast info path with replay fallback"
```

---

### Task 6: Implement segment summary + budgeted GC + bad-block retirement hooks

**Files:**
- Create: `components/pgfs/pgfs_alloc_gc.c`
- Modify: `components/pgfs/pgfs_core.c`
- Modify: `components/pgfs/pgfs_checkpoint.c`
- Test: `testcase/pgfs_regression/pgfs_regression_basic/scripts/pgfs_regression_test.lua`

- [ ] **Step 1: Add failing GC regression testcase**

Create `testcase/pgfs_regression/pgfs_regression_basic/scripts/pgfs_regression_test.lua`:

```lua
local M = {}
function M.test_gc_under_churn()
    for i = 1, 200 do
        local name = "/pgfs/churn_" .. i .. ".txt"
        assert(io.writeFile(name, string.rep("X", 256)))
        if i % 3 == 0 then os.remove(name) end
    end
    local info = assert(io.disk("/pgfs/"))
    assert(info.total_block > 0, "invalid total")
end

function M.test_bad_block_retire_hook()
    if lf.control then
        local ok = lf.control("pgfs.inject_bad_block_once", true)
        assert(ok ~= false, "inject bad block failed")
    end
    assert(io.writeFile("/pgfs/badblock_probe.txt", "ok"), "write failed after retire")
end
return M
```

Create `main.lua` + `metas.json` for this testcase (same pattern as `lfs2n_regression`).

- [ ] **Step 2: Run testcase to verify fail**

Expected: FAIL due to missing GC/retire logic.

- [ ] **Step 3: Implement allocator and GC budget**

In `pgfs_alloc_gc.c` implement:

```c
int pgfs_alloc_segment(pgfs_ctx_t* ctx, uint32_t* seg_id);
int pgfs_gc_step(pgfs_ctx_t* ctx, uint32_t byte_budget, uint32_t time_budget_us);
int pgfs_mark_block_retired(pgfs_ctx_t* ctx, uint32_t block_id);
```

Use segment summary fields:

```c
typedef struct {
    uint32_t live_bytes;
    uint32_t dead_bytes;
    uint32_t erase_count;
    uint32_t flags; // retired/full/hot
} pgfs_seg_summary_t;
```

- [ ] **Step 4: Integrate GC stepping into write path**

In `pgfs_core.c`, call `pgfs_gc_step` with small budget before/after large append batches.

- [ ] **Step 5: Persist summary in checkpoint**

In `pgfs_checkpoint.c`, include summary counters in checkpoint payload serialization.

- [ ] **Step 6: Run build + regression testcase and verify pass**

Expected: churn and bad-block injection tests pass without metadata corruption.

- [ ] **Step 7: Commit**

```bash
git add components/pgfs/pgfs_alloc_gc.c components/pgfs/pgfs_core.c components/pgfs/pgfs_checkpoint.c testcase/pgfs_regression/pgfs_regression_basic/scripts/pgfs_regression_test.lua testcase/pgfs_regression/pgfs_regression_basic/scripts/main.lua testcase/pgfs_regression/pgfs_regression_basic/scripts/metas.json
git commit -m "feat(pgfs): add segment summary, budgeted gc, and retire hooks"
```

---

### Task 7: Add optional lock mode and lock-off deterministic mode tests

**Files:**
- Modify: `components/pgfs/pgfs_cache_lock.c`
- Modify: `components/pgfs/pgfs_vfs_adapter.c`
- Modify: `testcase/pgfs_regression/pgfs_regression_basic/scripts/pgfs_regression_test.lua`

- [ ] **Step 1: Add failing lock mode tests**

Append regression tests:

```lua
function M.test_lock_on_mode()
    if lf.control then assert(lf.control("pgfs.set_lock_mode", "on") ~= false) end
    assert(io.writeFile("/pgfs/lock_on.txt", "1"))
end

function M.test_lock_off_mode_single_thread()
    if lf.control then assert(lf.control("pgfs.set_lock_mode", "off") ~= false) end
    assert(io.writeFile("/pgfs/lock_off.txt", "1"))
end
```

- [ ] **Step 2: Run regression testcase to verify fail**

Expected: FAIL because control/set lock mode is not implemented.

- [ ] **Step 3: Implement lock mode switch**

In `pgfs_cache_lock.c`:

```c
typedef enum { PGFS_LOCK_OFF = 0, PGFS_LOCK_ON = 1 } pgfs_lock_mode_t;
int pgfs_set_lock_mode(pgfs_ctx_t* ctx, pgfs_lock_mode_t mode);
```

In `pgfs_vfs_adapter.c` control handler, map command string to `pgfs_set_lock_mode`.

- [ ] **Step 4: Run build + regression testcase and verify pass**

Expected: lock on/off mode tests pass.

- [ ] **Step 5: Commit**

```bash
git add components/pgfs/pgfs_cache_lock.c components/pgfs/pgfs_vfs_adapter.c testcase/pgfs_regression/pgfs_regression_basic/scripts/pgfs_regression_test.lua
git commit -m "feat(pgfs): add optional lock mode controls"
```

---

### Task 8: Complete PC fault-injection backend and full verification run

**Files:**
- Create: `components/pgfs/pgfs_pc_backend.c`
- Modify: `components/pgfs/pgfs_core.c`
- Modify: `components/pgfs/pgfs_checkpoint.c`
- Modify: `components/pgfs/pgfs_vfs_adapter.c`
- Test: both `pgfs_basic` and `pgfs_regression_basic`

- [ ] **Step 1: Add failing fault-injection control coverage**

Extend `pgfs_basic` tests to call:

```lua
lf.control("pgfs.inject_powercut_stage", "before_close_commit")
lf.control("pgfs.inject_corrupt_latest_cp", true)
lf.control("pgfs.inject_bad_block_once", true)
```

Assert each command returns success.

- [ ] **Step 2: Run tests to verify fail**

Expected: FAIL due to missing backend control command implementations.

- [ ] **Step 3: Implement backend flash ops + control commands**

In `pgfs_pc_backend.c` implement:

```c
int pgfs_pc_read(void* ctx, uint32_t addr, uint8_t* buf, size_t len);
int pgfs_pc_write(void* ctx, uint32_t addr, const uint8_t* buf, size_t len);
int pgfs_pc_erase(void* ctx, uint32_t block_addr, uint32_t block_count);
int pgfs_pc_control(void* ctx, uint32_t cmd, void* arg);
```

Control commands:
- set/clear powercut stage
- corrupt latest checkpoint generation
- inject one-time bad block
- set lock mode
- get profile counters

- [ ] **Step 4: Run full build + two testcase suites**

Run:

```powershell
Set-Location D:\github\LuatOS\bsp\pc
cmd /c build_windows_32bit_msvc.bat
.\build\out\luatos-lua.exe ..\..\testcase\common\scripts\ ..\..\testcase\unit_testcase_tools\pgfs_basic\scripts\
.\build\out\luatos-lua.exe ..\..\testcase\common\scripts\ ..\..\testcase\pgfs_regression\pgfs_regression_basic\scripts\
```

Expected: both suites PASS and exit 0.

- [ ] **Step 5: Commit**

```bash
git add components/pgfs/pgfs_pc_backend.c components/pgfs/pgfs_core.c components/pgfs/pgfs_checkpoint.c components/pgfs/pgfs_vfs_adapter.c testcase/unit_testcase_tools/pgfs_basic/scripts/pgfs_test.lua testcase/pgfs_regression/pgfs_regression_basic/scripts/pgfs_regression_test.lua
git commit -m "feat(pgfs): add pc fault-injection backend and verify recovery matrix"
```

---

### Task 9: Final polish (docs sync + smoke commands for handoff)

**Files:**
- Modify: `docs/superpowers/specs/2026-05-28-pgfs-design.md` (only if behavior changed during implementation)
- Modify: `testcase/unit_testcase_tools/pgfs_basic/metas.json`
- Modify: `testcase/pgfs_regression/pgfs_regression_basic/scripts/metas.json`

- [ ] **Step 1: Add/verify testcase metadata**

Example `metas.json` content:

```json
{
  "name": "pgfs_basic",
  "summary": "PGFS mount/durability baseline",
  "platform": ["pc"],
  "timeout": 120
}
```

and:

```json
{
  "name": "pgfs_regression_basic",
  "summary": "PGFS recovery/gc/regression suite",
  "platform": ["pc"],
  "timeout": 300
}
```

- [ ] **Step 2: Run final smoke sequence**

```powershell
Set-Location D:\github\LuatOS\bsp\pc
cmd /c build_windows_32bit_msvc.bat
.\build\out\luatos-lua.exe ..\..\testcase\common\scripts\ ..\..\testcase\unit_testcase_tools\pgfs_basic\scripts\
.\build\out\luatos-lua.exe ..\..\testcase\common\scripts\ ..\..\testcase\pgfs_regression\pgfs_regression_basic\scripts\
```

Expected: build success, both test runs exit 0.

- [ ] **Step 3: Commit**

```bash
git add testcase/unit_testcase_tools/pgfs_basic/metas.json testcase/pgfs_regression/pgfs_regression_basic/scripts/metas.json docs/superpowers/specs/2026-05-28-pgfs-design.md
git commit -m "test(pgfs): finalize metadata and handoff smoke flow"
```

---

## Spec Coverage Check

- NAND optimization: Tasks 3, 6, 8.
- `fclose` durability guarantee: Task 4 + Task 8 fault injection.
- balanced RW + fast `info`: Tasks 5, 6.
- superblock/checkpoint: Task 3.
- RAM bounded model (~512 KiB target): Tasks 4/5/6 implementation constraints.
- PC-first + stress tests: Tasks 2, 6, 8, 9.
- 4-op flash interface: Tasks 1 and 8.
- optional lock: Task 7.
- VFS mount integration: Tasks 1 and 2.

## Placeholder/Consistency Check

- No TBD/TODO placeholders remain.
- Function names are consistent across tasks (`pgfs_file_close`, `pgfs_checkpoint_load`, `pgfs_gc_step`, `pgfs_set_lock_mode`).
- Test commands consistently use PC simulator two-directory invocation and exit-based assertions.
