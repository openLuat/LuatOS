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
| `bsp/pc/port/network/luat_network_adapter_posix.c` | PC network adapter |
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
- Async callbacks may fire on a **different thread** — the originating context may already be freed
- Don't send state-machine events (e.g. `EV_NW_SOCKET_CLOSE_OK`) if the handler will access uninitialized state

### Async Handle Rules
- Do not copy runtime-managed async handles by `memcpy`; keep handle ownership clear
- Async close operations require the handle to remain valid until close callback fires
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

### PC 模拟器测试脚本必须调用 `os.exit(0)`

**症状**：Lua 任务执行完毕（日志正常打印），但进程永远不退出，挂在 `sys.run()` 处。

**根因**：`sys.run()` 进入 PC 事件循环，只要有任意活跃句柄（网络、文件、MP4 播放器等内部资源），事件循环就不会自行退出。

**修复**：在 Lua 任务协程内部（`sys.run()` 调用前执行的协程中）调用 `os.exit(0)`：

```lua
sys.taskInit(function()
    -- ... 执行任务 ...
    os.exit(0)   -- ✅ 强制退出事件循环
end)
sys.run()        -- 启动事件循环
```

**注意**：`os.exit(0)` 写在 `sys.run()` 之后无效——`sys.run()` 永远不返回，后面的代码不会执行。使用 `testrunner` 框架的标准测试用例由框架自身处理退出，无需手动添加。

### Lua 性能计时口径陷阱（`os.time()` 误用）

**症状**：性能日志里 `write_wall/mount_wall` 显示 15000ms、16000ms 级别的大值，但同批次 C 层指标（如 `LFS2N_WRITE_MS`、`io_op_summary`）只有十几毫秒，二者明显矛盾。

**根因**：Lua 侧使用 `os.time()*1000` 统计 wall-clock。`os.time()` 只有秒级分辨率，且非单调计时源，不适合子秒级性能评估，容易把真实 10~20ms 放大成秒级台阶值（常见为 15000/16000/30000ms）。

**修复**：统一改为单调高精度时钟口径（`now_us()`），wall 指标由 `us_to_ms(now_us() - t0)` 计算；保留 C 层 `total_us/calls` 作为交叉校验。

**防回归约束**：
- 不允许在性能测试脚本中使用 `os.time()` 计算耗时。
- 每次改动后至少核对一组“Lua wall vs C层 us”是否同量级。
- 若 wall 指标变化极大但 `read/prog/erase total_us` 近似不变，先判定为“计量口径异常”，禁止直接宣称性能提升/回退。

### LFS2N 调试日志默认关闭与真机验证边界

**症状**：已经在仓库里关闭了 LFS2N 调试/性能日志，但真机日志仍然出现 `D/vfs.lfs2_nand*` / `D/little_flash*` 输出，容易误判“代码没生效”。

**根因**：当前真机验证如果继续使用旧 `.soc` 固件，只刷脚本（`flash script` 或 `flash test --script`）不会更新 C 层实现；日志行为仍由旧固件决定。

**修复策略**：
- 在 C 层使用门控宏并默认关闭：`LUAT_LFS2N_DEBUG_LOG=0`、`LUAT_LFS2N_PERF_LOG=0`、`LUAT_LFS2_IO_TRACE_LOG=0`、`LUAT_LFS2_IO_PROFILE_LOG=0`、`LUAT_LFS2N_CORE_TRACE_LOG=0`。
- Lua 测试脚本也默认关闭：`LFS2N_DEBUG_LOG_ENABLED=false`、`LFS2N_PERF_LOG_ENABLED=false`。
- 若要验证 C 层日志开关效果，必须先重编 `.soc` 并刷入新固件，再看串口日志。

**防回归约束**：
- “脚本下载成功”不等价于“C 层日志策略已生效”。
- 真机结论要标注验证对象：`script-only`（仅 Lua）或 `soc+script`（固件+脚本）。

### `ad_fopen` 在 `__LUATOS__` 下使用 `luat_fs` VFS

player SDK 的 `plat_support.c` 通过 `#ifdef __LUATOS__` 将 `ad_fopen/fread/fseek/fclose/fsize` 路由到 `luat_fs_*` 系列函数，而非 FatFS 或 stdio。PC 模拟器构建时 `__LUATOS__` 已定义，因此：

- 文件路径通过 LuatOS VFS 解析（支持 PC 模拟器脚本目录自动挂载）
- 无需将 `ad_fopen` 替换为 `fopen` 或 `luat_fs_fopen`
- 资源文件放在测试脚本目录下，VFS 会自动找到

### NDK RV32C / Host ABI 经验

- **Host ABI guest fixture 既然用了 CSR 指令，就必须带 `zicsr` 编译** —— `testcase/ndk/guest/build_hostabi_v1.ps1` 要统一使用 `-march=rv32ima_zicsr` / `-march=rv32imac_zicsr`（GNU 和 LLVM 路径都一样）。只写 `rv32ima` / `rv32imac` 在新工具链上可能直接拒绝 `csrr/csrrw`。

- **验证 RV32C 不能只看 `-march=rv32imac`** —— 要保留显式 `rvc_smoke.S`，再用反汇编验证真的生成了压缩指令。实践上可用 `objdump -d -M no-aliases` 后检查输出里是否出现 `c.` mnemonic，再决定是否拷贝测试二进制。

- **`.option norvc` 要继续局部保留在 CSR helper 的 inline asm 里** —— `components/ndk/include/luat_ndk_builtin.h` 和 `testcase/ndk/guest/hostabi_v1/ndk_stubs.c` 中的 `norvc` 是刻意的“固定宽度 CSR 编码”边界，不要因为 guest 已支持 RV32C 就删掉，也不要提升成文件级全局指令。

- **mini-rv32ima 做 RV32C 支持时，核心点是“两段式取指 + 2 字节对齐”** —— 先读低 16 bit，再根据 `ir16 & 0x3` 决定是 16 bit 还是 32 bit 指令；PC 对齐从 4 字节降为 2 字节；不支持的压缩编码以及全零半字 `0x0000` 都应该报非法指令 trap，而不是静默当 NOP。

- **当前 NDK RV32C 的标准回归链路**：先跑 `testcase\ndk\guest\build_hostabi_v1.ps1`，再跑 `testcase\ndk\ndk_basic\guest\build.ps1`，然后用 `bsp\pc\build_windows_32bit_msvc.bat` 重建 PC 模拟器，最后分别执行 `testcase\ndk\ndk_basic\scripts\` 和 `testcase\ndk\ndk_hostabi_basic\scripts\`。

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
