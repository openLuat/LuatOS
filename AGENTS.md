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
├── components/       # Extension libraries
│   ├── network/      # Network stacks (LwIP, MQTT, HTTP)
│   ├── airui/        # GUI framework (LVGL 9 based)
│   ├── mbedtls/      # Cryptography library
│   ├── fatfs/        # File system
│   └── ...           # Bluetooth, audio, sensors, etc.
├── bsp/              # Board Support Packages
│   ├── pc/           # PC simulator (xmake build)
│   └── [model]/      # Hardware-specific firmware/demos
├── module/           # Module firmware and solutions
├── script/           # Lua script libraries
│   ├── corelib/      # Core libraries (sys.lua, etc.)
│   ├── libs/         # External driver libraries
│   └── turnkey/      # Ready-to-use project templates
├── testcase/         # Test suites
├── tools/            # Auxiliary tools
└── build/            # Build output directory
```

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
build/out/luatos-lua.exe ../../testcase/common/scripts/ ../../testcase/unit_testcase_tools/mreport/scripts/
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
- [ ] If required, build passes in `bsp/pc` using the correct mode: plain `xmake -y` for non-GUI changes, GUI-enabled build for AirUI/LVGL/SDL changes
- [ ] Tests pass (if applicable)
- [ ] Code follows existing patterns
- [ ] No hardcoded credentials or security issues
- [ ] User's original request fully addressed

---

## Key Files Reference

| File | Description |
|------|-------------|
| `bsp/pc/xmake.lua` | PC simulator build configuration |
| `bsp/pc/port/network/luat_network_adapter_libuv.c` | PC network adapter (libuv) |
| `luat/include/luat.h` | Core header file |
| `components/network/adapter/luat_network_adapter.c` | Network framework state machine |
| `components/network/adapter/luat_network_adapter.h` | Network adapter API definitions |
| `components/network/adapter/luat_lib_socket.c` | Socket Lua bindings |
| `script/corelib/sys.lua` | Lua task system core |
| `module/<model>/core` | Module firmware description |
| `.github/workflows/` | CI/CD configuration |
| `.github/copilot-instructions.md` | GitHub Copilot specific instructions |
| `QWEN.md` | Project context and documentation |

---

## Debugging Lessons & Common Pitfalls

### Memory Initialization
- `lua_newuserdata` does **NOT** zero memory — always `memset` the returned pointer
- `malloc` / `luat_heap_malloc` also do not zero — use `memset` or `calloc`
- Uninitialized pointers (e.g. `task_name`, `cb_ref`) cause delayed crashes in callback chains

### Async Event Safety
- When closing resources, consider what events are still in-flight
- `uv_async_send` callbacks fire on a **different thread** — the originating context may already be freed
- Don't send state-machine events (e.g. `EV_NW_SOCKET_CLOSE_OK`) if the handler will access uninitialized state

### libuv Handle Rules
- **Never memcpy** `uv_tcp_t` or other handles — they have internal linked-list pointers
- `uv_close` is async — the handle must remain valid until the close callback fires
- Heap-allocate handles that need to outlive their creating scope

### Debugging Methodology
1. Add `DBG_ERR` prints to narrow down the layer (Lua API → framework → adapter)
2. In async systems, trace the **full event chain** from send to callback
3. Check if the crash is in a synchronous return path or an async callback
4. Always clean up debug prints after fixing

### AirLink / nanopb RPC Pitfalls

- **`#ifdef LUAT_USE_AIRLINK_RPC` must NOT appear before `#include "luat_base.h"`** — the feature macros (`LUAT_USE_*`) are provided by `luat_conf_bsp.h` which is pulled in through `luat_base.h`. If you guard the entire file contents with `#ifdef LUAT_USE_AIRLINK_RPC` but only include `luat_base.h` inside the guard, the preprocessor sees the macro as undefined and skips the whole file → silent linker errors (`LNK2001` unresolved external).  
  **Fix**: always put `#include "luat_base.h"` as the very first include, before any `#ifdef LUAT_USE_*` guard.

- **nanopb struct name prefix depends on `package` in the `.proto` file** — without a `package` directive, the generated type is `SdataNotify` (bare name). With `package drv_sdata;` it would be `drv_sdata_SdataNotify`. Check the actual generated `.pb.h` before writing C code that uses the types.

- **Static table file needs `luat_base.h` too** — `luat_airlink_rpc_nb_table.c` only includes `luat_airlink_rpc.h`, which does not transitively include `luat_conf_bsp.h`. Add `#include "luat_base.h"` before the `#ifdef LUAT_USE_AIRLINK_RPC` guard.

- **`drv_sdata.pb.c` is generated into `include/` by the nanopb generator** — after running `nanopb_generator.exe --output-dir=../include`, manually copy/move the `.pb.c` file to `src/` so the build system compiles it. The `.pb.h` stays in `include/`.

### Debug Records
- `bsp/pc/docs/debug_tcp_listen.md` — TCP listen/accept implementation and crash debugging

---

- **Official Documentation**: https://docs.openluat.com/
- **API Reference**: https://docs.openluat.com/osapi/
- **Third-party Tools**: LuatOS IDE Helper (https://gitee.com/tianyiw/LuatOS-ide-helper)

---

## Quick Start Flow

1. **Hardware**: Use supported dev board or PC simulator
2. **Flashing**: Use LuaTools to download firmware
3. **Learning**: Browse API docs → Run demos → Develop business logic
4. **Debugging**: Test on PC simulator → Deploy to hardware

---

```lua
-- 感谢您使用 LuatOS ^_^
-- Thank you for using LuatOS ^_^
print("Hello LuatOS!")
```
