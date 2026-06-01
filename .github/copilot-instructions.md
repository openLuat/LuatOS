# Copilot Instructions for LuatOS

## Build, Test, and Lint

### Build (PC Simulator)
The project uses [xmake](https://xmake.io) for building.

**CRITICAL**: Never run `xmake -y` directly—it causes full rebuild (10+ minutes) with truncated shell output. **Always use helper batch scripts** from `bsp/pc/`:

```powershell
cd bsp\pc
# For non-GUI changes (increment build, ~10-30 sec)
cmd /c build_windows_32bit_msvc.bat
# For 64-bit
cmd /c build_windows_64bit_msvc.bat
# For GUI/AirUI/LVGL/SDL changes
cmd /c build_windows_32bit_msvc_gui.bat
# Force full rebuild: add "full" argument
cmd /c build_windows_32bit_msvc.bat full
```

Scripts call `build_with_summary.ps1` which shows only errors/warnings. Full log is in `bsp/pc/build/logs/`.

**When to use GUI variant**: If you modify `components/airui/`, LVGL, SDL display code, or anything behind `LUAT_USE_GUI`.

**Configuration**:
- **Directory**: `bsp/pc`
- **Configure**: `xmake f -a x86 -y` (or `-a x64`)
- **Manual build** (only if scripts fail): `xmake -y` from `bsp/pc/`
- **Clean**: `xmake clean -a`

### Test (Lua Scripts)
Tests are located in `testcase/` and are Lua scripts executed by the LuatOS firmware (or PC simulator).
- **Structure**: `testcase/<feature>/<feature>_basic/scripts/`
- **Run**: Execute the built binary and pass exactly two script directories: `testcase/common/scripts/` and one target testcase's `scripts/` directory.
  ```powershell
  # Example running a test on PC simulator
  build\out\luatos-lua.exe ..\..\testcase\common\scripts\ ..\..\testcase\unit_testcase_tools\mreport\scripts\
  ```
  Note: This mode does not support running multiple target testcase directories in a single command.
  Note: Check `bsp/pc/xmake.lua` for the exact output path (usually `$(builddir)/out`).

**PC Simulator Test Scripts Must Call `os.exit(0)`**: The PC simulator runs Lua in an event loop that never exits automatically, even after tasks complete. Test scripts MUST call `os.exit(0)` to terminate the process.
  ```lua
  -- ✅ CORRECT: Call os.exit(0) inside the task (before sys.run() returns)
  sys.taskInit(function()
      -- test logic
      os.exit(0)  -- Forces event loop to exit
  end)
  sys.run()

  -- ❌ WRONG: Calling os.exit(0) after sys.run() doesn't work (sys.run never returns)
  sys.taskInit(function()
      -- test logic
  end)
  sys.run()
  os.exit(0)  -- Never reached
  ```

- **New Test**:
  1. Create `testcase/<feature>/<feature>_basic/scripts/`
  2. Create `metas.json` with test metadata.
  3. Create `main.lua` (define `PROJECT`, `VERSION`, require `testrunner`, call `sys.taskInit`)
  4. Create `<feature>_test.lua` with functions starting with `test_` (testrunner handles exit automatically)

## High-Level Architecture

LuatOS is an embedded Lua operating system based on Lua 5.3.
- **`lua/`**: Modified Lua 5.3 VM source.
- **`luat/`**: Core framework (task management, VFS, HAL).
  - **`luat/modules/`**: C implementations of Lua libraries (e.g., `luat_lib_gpio.c`).
  - **`luat/vfs/`**: Virtual File System.
- **`components/`**: Extension libraries (Network, GUI, Drivers).
  - **`components/network/`**: Network stacks (LwIP, etc.). See `components/network/AGENTS.md` for 3-layer architecture.
  - **`components/airui/`**: GUI components (LVGL based).
- **`bsp/`**: Board Support Packages. `bsp/pc` is the simulator. See `bsp/pc/AGENTS.md` for network details.
- **`script/`**: Lua scripts, core libraries (`corelib`), and drivers (`libs`).

## Key Conventions

### C Code (Core & Modules)
- **Prefix**: Core APIs use `luat_` prefix (e.g., `luat_gpio_set`).
- **Headers**: Core headers in `luat/include`.
- **Macros**: Feature flags often prefixed with `LUAT_` (e.g., `LUAT_USE_GUI`).

### Lua Code (Scripts & Tests)
- **Task Management**: Use `sys.taskInit(function() ... end)` for concurrency.
- **Entry Point**: Scripts end with `sys.run()`.
- **Testing**:
  - Test functions must start with `test_` to be picked up by `testrunner`.
  - Use `log.info()` for output.
  - Assertions: `assert(condition, message)`.

### Build Configuration (xmake)
- **`xmake.lua`**: Located in BSP directories (e.g., `bsp/pc/xmake.lua`).
- **Dependencies**: Components are included/excluded via `add_files` and `remove_files` based on flags.

## Common Pitfalls & Debugging Lessons

### xmake `remove_files` + `add_files` Interaction Bug
**Problem**: Calling `remove_files("dir/*.c")` creates an internal xmake blacklist. Subsequent `add_files("dir/foo.c")` calls cannot override this blacklist—the file remains excluded.

**Root cause**: xmake maintains a permanent exclusion list, not dynamic path resolution.

**❌ Wrong approach**:
```lua
remove_files("port/mp4player/*.c")
if os.getenv("LUAT_USE_MP4PLAYER") == "y" then
    add_files("port/mp4player/dac_sound_pc.c")  -- ← Still excluded, never compiles
end
```

**✅ Solution**: Place conditionally-compiled files in a separate directory that's never blanket-removed:
```lua
-- Don't touch stubs/mp4player with any remove_files()
if os.getenv("LUAT_USE_MP4PLAYER") == "y" then
    add_files("stubs/mp4player/dac_sound_pc.c")  -- ← Normal compile
end
```

### Memory Initialization in C Code
- **`lua_newuserdata` does NOT zero memory** — always call `memset()` on the returned pointer
- **`malloc`/`luat_heap_malloc` also do NOT zero** — use `memset()` or `calloc()`
- **Uninitialized pointers** (e.g., `task_name`, `cb_ref` in callback handlers) cause delayed crashes in async event chains

### GCC Optimization Bugs on ARM
**GCC `-Os` stack slot aliasing bug**: On ARM, `-Os` optimization uses `push {r0, r1, r2, ...}` to simultaneously save registers and allocate stack frame space (saves a `sub sp, #N` instruction). This can cause GCC to incorrectly cache local pointer values, treating bitfields or loop-dependent variables as constants—leading to silent logic errors.

**Symptoms**: 
- Code works fine with `-O0` or `-O1` but fails with `-Os` (production default)
- Often appears in struct field access loops or pointer dereferencing chains
- No compiler warnings

**Workaround** (if code must remain unmodified):
```c
#pragma GCC optimize("O1")  // Force O1 for this function
static void pb_nextentry(...) { ... }
```

**Better fix**: Refactor code to avoid the pattern (see AGENTS.md for protobuf example).

### Git CRLF Line-Ending Pollution
**Symptom**: After editing files on Windows, `git diff master HEAD` shows entire files as "rewritten" (all lines deleted + re-added) despite minimal content changes.

**Root cause**: master branch uses LF (Unix), but Windows editing introduces CRLF. Git compares line-by-line; different line endings = different content.

**Diagnosis** (check original file's line endings):
```powershell
$hash = git rev-parse "master:path/to/file.c"
cmd /c "git cat-file blob $hash > $env:TEMP\check.bin"
$bytes = [System.IO.File]::ReadAllBytes("$env:TEMP\check.bin")
"CR count: $(($bytes | ?{$_-eq13}).Count)"   # 0 = LF, >0 = CRLF
```

**Fix** (selective, not global—avoid introducing new phantom diffs):
1. Identify which `master` files use LF (not CRLF)
2. Convert only those branch files from CRLF→LF
3. Commit the `.gitattributes` rules at the same time

**Note**: `.gitattributes` prevents future CRLF on checkin, but doesn't retroactively fix existing mismatches. Don't use `git add --renormalize .` blindly—it may reverse-pollute files that master intentionally uses CRLF.

### Async Event Safety
- When closing resources, consider what events are still in-flight
- Async callbacks may fire on a **different thread** — the originating context may already be freed
- Don't send state-machine events (e.g., `EV_NW_SOCKET_CLOSE_OK`) if the handler will access uninitialized state
- **Never memcpy** `uv_tcp_t` or other handles — they have internal linked-list pointers
- `uv_close` is async — the handle must remain valid until the close callback fires

### NDK RV32C / Host ABI Pitfalls
- **Host ABI guest fixture must use `zicsr` in `-march`** — `testcase\ndk\guest\build_hostabi_v1.ps1` should use `rv32ima_zicsr` / `rv32imac_zicsr` for both GNU and LLVM paths because the fixture emits `csrr/csrrw`. Plain `rv32ima` / `rv32imac` is not robust on post-split ISA toolchains.

- **`-march=rv32imac` alone is not proof that compressed instructions are present** — keep an explicit `rvc_smoke.S`, disassemble with `objdump -d -M no-aliases`, and assert the output contains `c.` mnemonics before accepting the generated RV32C binary.

- **Keep `.option norvc` local to CSR helper inline asm** — in `components/ndk/include/luat_ndk_builtin.h` and `testcase/ndk/guest/hostabi_v1/ndk_stubs.c`, `norvc` is an intentional fixed-width CSR boundary. Do not remove it just because the guest now supports RV32C, and do not expand it to file-global scope.

- **RV32C support in mini-rv32ima must use low-halfword-first fetch** — read the low 16 bits, decide 16/32-bit length from `ir16 & 0x3`, enforce 2-byte PC alignment, and trap on unsupported/all-zero compressed halfwords instead of treating them as no-ops.

- **Preferred regression chain for NDK RV32C changes** — run `testcase\ndk\guest\build_hostabi_v1.ps1`, then `testcase\ndk\ndk_basic\guest\build.ps1`, rebuild `bsp\pc` with `build_windows_32bit_msvc.bat`, then execute both `ndk_basic` and `ndk_hostabi_basic` script suites on the PC simulator.
