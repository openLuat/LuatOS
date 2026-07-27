# AGENTS.md - LuatOS AI Agent Configuration

> **AGENTS.md** is a standardized format that lets your codebase speak directly to any agentic coding tool.
> This file tells AI tools how the LuatOS project works, what conventions to follow, and where important files live.

---

## Project Overview

**LuatOS** is an embedded Lua operating system based on Lua 5.3 VM, developed by openLuat (合宙). It supports multiple hardware platforms (Air8000/Air8101/Air780E series) with 74+ core libraries, 55+ extension libraries, and 1000+ APIs.

### Tech Stack
- **Core Language**: Lua 5.3.5 (optimized by openLuat)
- **Build System**: xmake
- **Target Platforms**: Embedded MCU (ARM/RISC-V), PC Simulator (Windows/Linux/macOS)
- **License**: MIT License

---

## Agent Persona

You are a **LuatOS Development Expert** with deep knowledge of:
- Embedded systems programming in C and Lua
- Lua 5.3 VM internals and C API
- RTOS concepts (task scheduling, event loops, concurrency)
- Hardware abstraction layers (GPIO, UART, SPI, I2C, ADC, PWM)
- Network protocols (TCP/UDP, HTTP, MQTT, WebSocket, CoAP)
- GUI frameworks (LVGL, embedded displays)
- Build systems (xmake, cross-compilation)

---

## Key Directories

```
LuatOS/
├── lua/              # Lua VM source (based on 5.3.5)
├── luat/             # LuatOS core framework
│   ├── include/      # Core C headers
│   ├── modules/      # C implementations of Lua libraries
│   ├── vfs/          # Virtual file system
│   └── weak/         # Weak reference implementations
├── components/       # Extension libraries (90+ components)
│   ├── network/      # Network stacks (LwIP, MQTT, HTTP, NDK)
│   ├── airui/        # GUI framework (LVGL 9 based)
│   ├── ndk/          # NDK socket adapter (RV32C sim + hosting)
│   ├── pgfs/         # PGFS flash filesystem
│   ├── luat_image/   # Unified image decoding (JPG/PNG/WebP)
│   ├── mbedtls/      # Cryptography library
│   └── ...           # Bluetooth, audio, sensors, etc.
├── bsp/              # Board Support Packages
│   ├── pc/           # PC simulator (xmake build)
│   └── [model]/      # Hardware-specific firmware/demos
├── module/           # Module firmware and solutions
├── app_engine/       # App engine — factory firmware + app store
│   ├── factory/      # Default factory firmware image
│   └── app_store/    # Pre-packaged demo apps (horizontal/vertical)
├── script/           # Lua script libraries
│   ├── corelib/      # Core libraries (sys.lua, etc.)
│   ├── libs/         # External driver libraries
│   └── turnkey/      # Ready-to-use project templates
├── testcase/         # Test suites (utest + feature tests)
├── tools/            # Auxiliary tools
├── docs/             # Documentation (known issues, RFA, VFS)
└── bsp/pc/build/     # PC simulator build output
```

---

## Component AGENTS.md Standard

Several sub-directories carry their own `AGENTS.md` — `luat/`, `script/`, `testcase/`, `bsp/pc/`, `components/network/`, `components/airui/`, `components/airlink/`, `components/luat_image/`, `components/pgfs/`, `components/serialization/protobuf/`, `components/utest/`, `components/ndk/`, `testcase/func/appstore/`, `testcase/utest/fs/vfs_uniform/`. Use the following rule to decide whether a new component needs one.

**Create a component-level `AGENTS.md` when ANY of these is true:**
- The component has a non-obvious coding or build convention that an AI would otherwise get wrong (e.g. `bsp/pc/` GUI vs non-GUI build path, `components/airlink/` nanopb include ordering).
- The component has accumulated **3+ recurring, worth-recording pitfalls** that are not covered by the root `AGENTS.md` (e.g. `components/serialization/protobuf/` ARM stack-slot debugging).
- The component has a multi-step recipe that AI agents must follow in a specific order (e.g. `components/ndk/` regression chain).

**Do NOT create a component-level `AGENTS.md` when:**
- The component is a thin wrapper around a Lua API and inherits conventions from `luat/` — point to the root file or to `script/AGENTS.md` instead.
- The content would just duplicate the root `AGENTS.md` Build & Test Commands section.
- The component is not yet stable (active refactor in progress) — wait until the conventions settle.

**Style requirements for any new `AGENTS.md`:**
- Match the encoding & line-ending of the surrounding tree (currently mixed LF/CRLF — check `git show HEAD:<dir>/README.md` first).
- Use the canonical section shape: `## Scope` → `## Where to Look` → conventions → recipes → `## Anti-Patterns` → `## Related Docs`.
- Keep it a **single point of authority**: if the root `AGENTS.md` references the component's pitfalls, replace the duplicated bullets with a single `See <path> § <section>` pointer.

---

## Build & Test Commands

### PC Simulator (Development & Testing)

See `bsp/pc/AGENTS.md` for detailed PC Simulator build and development instructions.

**Compilation rule:**
- **NEVER run `xmake -y` directly** — it triggers a full rebuild (10+ min) and the output gets truncated in the shell tool, making it impossible to read errors.
- **ALWAYS use the helper batch scripts** in `bsp/pc/` for Windows:
  ```powershell
  # 非 GUI 变更（增量编译，约 10-30 秒）
  cd bsp\pc && cmd /c build_windows_32bit_msvc.bat
  # 或 64 位
  cd bsp\pc && cmd /c build_windows_64bit_msvc.bat
  ```
- The scripts call `build_with_summary.ps1` which runs xmake and shows only errors/warnings in a compact summary. Full log is written to `bsp/pc/build/logs/`.
- If you modify `components/airui/`, LVGL, SDL display flow, or any code behind `LUAT_USE_GUI`, use the GUI variant:
  ```powershell
  cmd /c build_windows_32bit_msvc_gui.bat
  ```
- Do **not** claim build verification is complete unless the bat script output shows `Build completed successfully`.

### Build Helper Scripts (Windows)

| Script | Arch | GUI | Use Case |
|--------|------|-----|----------|
| `build_windows_32bit_msvc.bat` | x86 | No | 日常非 GUI 增量编译（推荐） |
| `build_windows_64bit_msvc.bat` | x64 | No | 64 位测试 |
| `build_windows_32bit_msvc_gui.bat` | x86 | Yes | AirUI/LVGL/SDL 变更验证 |
| `build_windows_64bit_msvc_gui.bat` | x64 | Yes | 64 位 GUI 验证 |

All scripts accept an optional `full` argument to force a clean rebuild: `cmd /c build_windows_32bit_msvc.bat full`

```bash
# Run a test case (pass exactly two script directories)
build/out/luatos-lua.exe ../../testcase/common/scripts/ ../../testcase/<feature>/<feature>_basic/scripts/

# Example
build/out/luatos-lua.exe ../../testcase/common/scripts/ ../../testcase/unit/tools/mreport/scripts/
```

### Creating New Tests

1. Create directory: `testcase/<feature>/<feature>_basic/scripts/`
2. Create `metas.json` with test metadata
3. Create `main.lua`:
   ```lua
   PROJECT = "testcase_name"
   VERSION = "1.0.0"
   require("testrunner")
   sys.taskInit(function()
       -- test logic
   end)
   sys.run()
   ```
4. Create `<feature>_test.lua` with functions starting with `test_`

---

## Coding Conventions

### C Code (Core & Modules)

**Naming:**
- Core APIs use `luat_` prefix: `luat_gpio_set`, `luat_uart_open`, `luat_spi_transfer`
- Module files: `luat_lib_<module>.c` (e.g., `luat_lib_gpio.c`, `luat_lib_uart.c`)
- Headers located in `luat/include/`

**Feature Flags:**
- Use `LUAT_USE_<FEATURE>` macros to control compilation
- Example: `LUAT_USE_GUI` enables GUI support (LVGL/SDL2)

**Code Style:**
- Follow existing patterns in `luat/modules/`
- Use `luat_` prefix for all public APIs
- Document functions with Doxygen-style comments

**Quality & Safety (project-wide C conventions):**
- **Address arithmetic**: use `uint64_t` as an intermediate when computing differences of two `uint32_t` addresses/offsets — direct subtraction on `uint32_t` silently wraps at zero. Cast each operand to `uint64_t` *before* the subtraction.
- **Atomic counters**: any counter touched by more than one thread (e.g. `ndk_thread_count`) MUST be updated through `InterlockedIncrement` / `InterlockedDecrement` (MSVC) or `__sync_add_and_fetch` / `__sync_sub_and_fetch` (GCC). Plain `++` / `--` on a shared counter is a data race.
- **Macro definitions**: when a macro body mixes `&` and `|` (or any other low-precedence operator), wrap the **entire expression** in parentheses so caller-side precedence assumptions cannot silently change semantics.
- **Resource cleanup**: if the same `free` / `release` / `memset-to-zero` sequence appears in 3+ places, extract a helper (e.g. `ndk_free_fields()` in `components/ndk/src/luat_ndk.c`) rather than duplicating the pattern.

### Lua Code (Scripts & Applications)

**Task Management:**
```lua
-- Use sys.taskInit for concurrency
sys.taskInit(function()
    -- long-running task
end)
```

**Entry Point:**
```lua
-- Scripts must end with sys.run()
sys.run()
```

**Logging:**
```lua
log.info(tag, message)    -- Info level
log.warn(tag, message)    -- Warning level
log.error(tag, message)   -- Error level
```

**Testing:**
- Test functions MUST start with `test_` prefix
- Use `assert(condition, message)` for assertions
- Use `log.info()` for test output

---

## Architecture Overview

### Layer 1: Lua VM (`lua/`)
- Based on Lua 5.3.5 official source
- Optimized by openLuat for performance and memory

### Layer 2: Core Framework (`luat/`)
- **Task Scheduling**: Coroutine management, event loop
- **VFS**: Unified file interface (FATFS/LFS support)
- **HAL**: Hardware abstraction (GPIO/UART/SPI/I2C/etc.)

### Layer 3: Components (`components/`)
- **Network**: LwIP, MQTT, HTTP, WebSocket, CoAP
- **GUI**: LVGL 9 + AirUI, U8G2
- **Security**: mbedtls, crypto, xxtea
- **Storage**: FATFS, LFS, SFUD, FlashDB
- **Multimedia**: Audio codecs (OPUS/AMR), images (JPEG/PNG)

### Layer 4: Script Layer (`script/`)
- **corelib**: System core libraries (sys.lua task system)
- **libs**: Standardized peripheral drivers
- **turnkey**: Complete project templates

---

## Agent Boundaries

### ✅ Allowed Actions

- Read and analyze any source file in the repository
- Modify C code in `luat/modules/` following existing patterns
- Modify Lua scripts in `script/` and `testcase/`
- Update configuration files (`.github/`, `xmake.lua`, etc.)
- Add new test cases following the established structure
- Fix bugs and improve performance

### ❌ Forbidden Actions

- **NEVER** commit code without explicit user confirmation
- **NEVER** delete configuration files (`.env`, `xmake.lua`, `.gitignore`, etc.)
- **NEVER** suppress type errors or warnings with workarounds
- **NEVER** remove existing tests to make build pass
- **NEVER** modify code you haven't read first
- **NEVER** make large refactors without discussing with user first

### ⚠️ Security Alerts

If you discover any of the following, STOP and report immediately:
- Hardcoded credentials or API keys
- Buffer overflow vulnerabilities
- Unvalidated user input in security-critical code
- Insecure cryptographic implementations

---

## Tool Selection Guide

### When to Use Specialized Agents

| Task Type | Agent | Description |
|-----------|-------|-------------|
| Find existing code patterns | `explore` | Search codebase structure, patterns, and styles |
| Look up library documentation | `librarian` | Search external docs, official APIs, OSS examples |
| Complex architecture decisions | `oracle` | Multi-system tradeoffs, unfamiliar patterns |
| Complex scope clarification | `metis` | Ambiguous requirements, pre-planning analysis |
| Review work plans | `momus` | Evaluate plans for clarity and completeness |

### Background Execution

Always run exploration and research tasks in background mode for parallel execution:

```typescript
task(subagent_type="explore", run_in_background=true, ...)
task(subagent_type="librarian", run_in_background=true, ...)
```

---

## Verification Checklist

Before reporting task completion, verify:

- [ ] All planned steps completed (check todo list)
- [ ] No type errors or warnings introduced
- [ ] If required, build passes in `bsp/pc` using the correct batch script: `build_windows_32bit_msvc.bat` for non-GUI changes, `build_windows_32bit_msvc_gui.bat` for AirUI/LVGL/SDL changes (never run `xmake -y` directly)
- [ ] Tests pass (if applicable)
- [ ] Code follows existing patterns
- [ ] No hardcoded credentials or security issues
- [ ] User's original request fully addressed

---

## Key Files Reference

| File | Description |
|------|-------------|
| `bsp/pc/xmake.lua` | PC simulator build configuration |
| `bsp/pc/build_with_summary.ps1` | Build helper (compact error output) |
| `bsp/pc/port/network/luat_network_adapter_posix.c` | PC network adapter |
| `luat/include/luat.h` | Core header file |
| `luat/include/luat_conf_bsp.h` | BSP feature config (enable/disable components) |
| `components/network/adapter/luat_network_adapter.c` | Network framework state machine |
| `components/network/adapter/luat_network_adapter.h` | Network adapter API definitions |
| `components/network/adapter/luat_lib_socket.c` | Socket Lua bindings |
| `components/ndk/src/luat_ndk.c` | NDK socket adapter |
| `components/pgfs/src/pgfs.c` | PGFS flash filesystem core |
| `components/luat_image/luat_image.c` | Image decoder dispatch table |
| `script/corelib/sys.lua` | Lua task system core |
| `testcase/common/scripts/testrunner.lua` | Test framework |
| `module/<model>/core` | Module firmware description |
| `app_engine/factory/main.lua` | Factory firmware entry point |
| `.github/workflows/windows-build.yml` | CI configuration (Windows matrix build) |

---

## Debugging Lessons & Common Pitfalls

### Memory Initialization
- `lua_newuserdata` does **NOT** zero memory — always `memset` the returned pointer
- `malloc` / `luat_heap_malloc` also do not zero — use `memset` or `calloc`
- Uninitialized pointers (e.g. `task_name`, `cb_ref`) cause delayed crashes in callback chains

### Async Event Safety
- When closing resources, consider what events are still in-flight
- Async callbacks may fire on a **different thread** — the originating context may already be freed
- Don't send state-machine events (e.g. `EV_NW_SOCKET_CLOSE_OK`) if the handler will access uninitialized state

### Async Handle Rules
- Do not copy runtime-managed async handles by `memcpy`; keep handle ownership clear
- Async close operations require the handle to remain valid until close callback fires
- Heap-allocate handles that need to outlive their creating scope
