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

### Git 换行符污染（CRLF vs LF）

**症状**：`git diff master HEAD` 显示某些文件"像整个被重写了一样"——`driver/` 和 `drv/` 目录尤其明显，实际上内容几乎没变。

**根因**：master 分支文件使用 LF（Unix 换行），但在 Windows 上编辑并提交后变成 CRLF。git 逐行比对时每行结尾字节不同，所有行都显示为"删除+新增"。

**快速诊断**：
```powershell
# 检查 git 对象的原始换行符（用 cmd 重定向避免 PowerShell 自动转换）
$hash = git rev-parse "master:path/to/file.c"
cmd /c "git cat-file blob $hash > $env:TEMP\check.bin"
$bytes = [System.IO.File]::ReadAllBytes("$env:TEMP\check.bin")
"CR count: $(($bytes | ?{$_-eq13}).Count)"   # 0=LF, >0=CRLF
```

**根治方案**：

1. 在仓库根目录创建 `.gitattributes`（已创建），对源文件强制 `eol=lf`
2. 精准转换「master=LF、branch=CRLF」的文件，跳过「master=CRLF」的文件（避免引入新 phantom diff）：
   ```powershell
   # 只转换 master=LF 的文件
   git diff --name-only master HEAD | ForEach-Object {
       $mHash = git rev-parse "master:$_" 2>$null
       if ($mHash) {
           cmd /c "git cat-file blob $mHash > $env:TEMP\m.bin"
           $cr = ([IO.File]::ReadAllBytes("$env:TEMP\m.bin") | ?{$_-eq13}).Count
           if ($cr -eq 0) { $_ }  # master=LF，需要修正
       }
   }
   ```
3. 对筛选出的文件做 CRLF→LF 转换后 `git add`，和 `.gitattributes` 一起提交。

**注意**：`git add --renormalize .` 会全量规范化，若 master 本身有 CRLF 文件则会反向引入新的 phantom diff，**不要无脑用**。务必精准筛选后再操作。

**预防**：`.gitattributes` 已提交到仓库，后续 `git add` 会自动强制 LF，无需手动处理。

### xmake `remove_files` + `add_files` 交互陷阱

**症状**：在 xmake.lua 中先无条件调用 `remove_files("dir/*.c")`，然后在 `if` 块内调用 `add_files("dir/foo.c")` 尝试将其中某些文件"加回来"，但链接阶段报符号未定义。

**根因**：xmake 的 `remove_files` 在内部维护一个排除名单（blacklist），即使后续的 `add_files` 指向同一文件，该文件也不会被编译——无论是通配符匹配还是精确路径匹配。

**复现场景**：PC 模拟器通过 `port/**.c` 通配符无条件编译所有平台 stub，而某些 stub 只应在可选功能（如 `LUAT_USE_MP4PLAYER`）启用时才参与编译。最初的"先排除再加回"写法是无效的。

**解决方案**：将只在条件下编译的 stub 文件放到一个**不被任何全局通配符覆盖**的目录，例如 `stubs/<feature>/`。在条件块内用精确路径 `add_files("stubs/<feature>/foo.c")` 添加。这样完全绕开了排除名单问题：

```lua
-- ❌ 错误写法：remove_files 后 add_files 无法将文件加回
remove_files("port/mp4player/*.c")
if os.getenv("LUAT_USE_MP4PLAYER") == "y" then
    add_files("port/mp4player/dac_sound_pc.c")  -- 永远不会编译
end

-- ✅ 正确写法：stub 放在不被通配符覆盖的目录
-- stubs/mp4player/*.c 不属于 port/**.c 的范围
if os.getenv("LUAT_USE_MP4PLAYER") == "y" then
    add_files("stubs/mp4player/dac_sound_pc.c")  -- 正常编译
end
```

### mp4player PC 模拟器适配经验

**场景**：将平台专有的 mp4player（依赖 CCM42xx DAC/DMA 外设）适配到 PC 模拟器，关键处理：

| 问题 | 解决方案 |
|------|----------|
| CCM42xx DAC/DMA 硬件驱动（`dac_sound.c`, `sys_dac.c`）| 排除原文件，在 `stubs/mp4player/` 提供 no-op stub |
| ARM GCC 专属头（`<sys.h>` RTOS, `atomic_gcc.h`）| 在 `bsp/pc/include/` 添加 `sys.h` 空 stub；在 `atomic_gcc.h` 加 `#ifdef _MSC_VER` 兼容块 |
| `config.h` 无法被 `-D` 命令行覆盖 | 必须直接修改 `.h` 文件，`#ifdef _MSC_VER` 选择平台实现 |
| `malloc_align`（CCM42xx 自定义对齐 malloc）| 在 `mem.c` 用 `#ifdef _MSC_VER` 映射到 `_aligned_malloc`/`_aligned_free`/`_aligned_realloc` |
| 符号冲突：player 内部 `h264_decode_stream` vs LuatOS `components/h264/src/h264_decoder.c` | 排除 player 的 `avcodec/h264_decode.c`，`mp4_decode.c` 直接调用 FFmpeg AVCodec API |
| 符号冲突：player `h264/yuv.c` vs SDL2 `yuv_rgb_std.c` | 排除 player 的 `h264/yuv.c` |
| `*_template.c` 被通配符纳入直接编译 | `remove_files` 排除所有 `*_template.c` |
| ARM NEON 文件（`yuv2rgb_neon.c`）| `remove_files` 排除 |
| libavutil 的 `file_open.c` 依赖 `<fcntl.h>` 而 config.h 未启用 | 排除 + 在 `stubs/mp4player/avcodec_fileopen_pc.c` 提供 stub |

**涉及文件**（PC 模拟器侧）：
- `bsp/pc/stubs/mp4player/dac_sound_pc.c` — DAC 音频接口 stub
- `bsp/pc/stubs/mp4player/sys_dac_pc.c` — DAC DMA stub（立即回调）
- `bsp/pc/stubs/mp4player/avcodec_fileopen_pc.c` — `avpriv_open`/`av_fopen_utf8` stub
- `bsp/pc/include/sys.h` — RTOS `<sys.h>` 空 stub
- `bsp/pc/include/win32_ver.h` — libfaad Windows 版本资源空 stub
- `bsp/pc/include/wchar_filename.h` — `utf8towchar` stub（返回 NULL 触发 ASCII 回退）

**涉及文件**（外部 player 源码侧，需直接修改）：
- `player/video_decode/avcodec/h264/libavutil/atomic_gcc.h` — 加 `#ifdef _MSC_VER` 用 volatile 实现原子操作
- `player/video_decode/avcodec/h264/libavutil/mem.c` — 加 `#ifdef _MSC_VER` 映射对齐内存分配

### Debug Records
- `bsp/pc/docs/debug_tcp_listen.md` — TCP listen/accept implementation and crash debugging

### PC 模拟器测试脚本必须调用 `os.exit(0)`

**症状**：Lua 任务执行完毕（日志正常打印），但进程永远不退出，挂在 `sys.run()` 处。

**根因**：`sys.run()` 调用 libuv 的 `uv_run(UV_RUN_DEFAULT)`，只要有任意活跃句柄（网络、文件、MP4 播放器等内部资源），事件循环就不会自行退出。

**修复**：在 Lua 任务协程内部（`sys.run()` 调用前执行的协程中）调用 `os.exit(0)`：

```lua
sys.taskInit(function()
    -- ... 执行任务 ...
    os.exit(0)   -- ✅ 强制退出 libuv 事件循环
end)
sys.run()        -- 启动事件循环
```

**注意**：`os.exit(0)` 写在 `sys.run()` 之后无效——`sys.run()` 永远不返回，后面的代码不会执行。使用 `testrunner` 框架的标准测试用例由框架自身处理退出，无需手动添加。

### `ad_fopen` 在 `__LUATOS__` 下使用 `luat_fs` VFS

player SDK 的 `plat_support.c` 通过 `#ifdef __LUATOS__` 将 `ad_fopen/fread/fseek/fclose/fsize` 路由到 `luat_fs_*` 系列函数，而非 FatFS 或 stdio。PC 模拟器构建时 `__LUATOS__` 已定义，因此：

- 文件路径通过 LuatOS VFS 解析（支持 PC 模拟器脚本目录自动挂载）
- 无需将 `ad_fopen` 替换为 `fopen` 或 `luat_fs_fopen`
- 资源文件放在测试脚本目录下，VFS 会自动找到

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
