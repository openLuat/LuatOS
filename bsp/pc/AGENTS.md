# LuatOS PC Simulator

**Scope**: `bsp/pc/` - PC simulator for Windows/Linux/macOS development.

## OVERVIEW

PC simulator allowing LuatOS development and testing on desktop without hardware. Uses SDL2 for GUI simulation.

## STRUCTURE

```
pc/
├── src/              # Simulator-specific code
├── port/             # Platform porting layer
├── include/          # Headers
├── win32/            # Windows-specific
├── ui/               # UI test code
└── xmake.lua         # Build configuration
```

## BUILD

```bash
cd bsp/pc
```

### Build Selection Rules

- Use plain `xmake -y` only for fast verification of non-GUI changes
- If the change touches `components/airui/`, LVGL, SDL display flow, or any code gated by `LUAT_USE_GUI`, you MUST use a GUI-enabled build
- Do not report AirUI-related verification as complete if you only ran plain `xmake -y`
- Prefer the existing platform helper scripts when available, because they already set the expected GUI environment flags
- Helper scripts now default to incremental `summary` mode to reduce low-value warning noise during routine development
- Helper scripts also normalize xmake to `--theme=plain` so build logs and terminal output do not include ANSI color noise
- Use `full` to see raw compiler output, and use `clean` only when you explicitly need a clean rebuild
- Summary/full logs are written to `bsp/pc/build/logs/`

### gmssl 构建（本地源码，不使用 xmake 包）

PC 模拟器直接编译 `components/gmssl`（与 ARM 固件同源的 LuatOS 分支），不再依赖 xmake 的 `gmssl` 包。该目录是**裁剪过的** GmSSL：只保留 SM2/SM3/SM4 及其直接依赖，没有 `x509` / `pem` / `pkcs8` / `ec` / `digest` / `base64` / `aes` 等实现。保留的源码里仍有一些**未被调用**的辅助函数（`*_print`、PEM/X509 导入导出）引用这些上游符号：

- ARM 固件构建用 `-ffunction-sections` + `--gc-sections` 把未引用函数整段丢弃，所以那些符号不进链接；
- **MSVC 没有等价能力**——`/Gy` + `/OPT:REF`（甚至 `/LTCG`）只做减体积，未引用函数里的未定义符号照样报 `LNK2019`。已实测确认，不要指望在 Windows 上靠 GC 通过。

因此 `bsp/pc/xmake.lua` 里维护一份**显式源码清单**（`gmssl_sources`，只含 Lua 绑定真正用到的 TU），其余缺符号由 `bsp/pc/port/gmssl/luat_gmssl_pc_stubs.c` 兜底：打印/校验类给出真实或最小实现，`aes_*` / `ec_*` / `pem_*` / `pkcs8_*` / `x509_*` / `DIGEST_sm3` / `pbkdf2_genkey` 等按“PC 未编译该功能”处理（告警 + 返回失败，均不在 Lua 绑定调用链上）。

新增 Lua 侧 gmssl 接口时，若用到清单外的 TU（例如 `sm2_key_share.c`、`sm4_rng.c`），把它加进 `gmssl_sources` 并按链接报错补 stub。

另外：`gmssl/mem.h` 在 `__LUATOS__` 下把 `malloc/free` 宏替换成 `luat_heap_*`，所以 gmssl 的 TU 必须**先包含 `stdlib.h`**（`xmake.lua` 用 `/FIstdlib.h` / `-include stdlib.h` 实现），否则 MSVC 会在 `corecrt_malloc.h` 报 C2375。

**不要**为了让链接通过而往 `components/gmssl/` 里加文件或改其源码——固件构建会 glob 编译该目录下所有 `.c`（`luatos-soc-2022`、`luatos-sdk-rda8910`、`luatos-sdk-ccm42xx-gcc` 都是全量）。PC 侧需要补齐的符号一律放 `bsp/pc/port/gmssl/`。

### Windows

| Script | Description |
|--------|-------------|
| `build_windows_32bit_msvc.bat` | 32-bit, no GUI |
| `build_windows_32bit_msvc_gui.bat` | 32-bit, GUI (with clean) |
| `build_windows_64bit_msvc.bat` | 64-bit, no GUI |
| `build_windows_64bit_msvc_gui.bat` | 64-bit, GUI |

Recommended:
- Non-GUI verification: `build_windows_64bit_msvc.bat`
- GUI / AirUI verification: `build_windows_64bit_msvc_gui.bat` (or `build_windows_32bit_msvc_gui.bat` when targeting 32-bit)
- Full output: append `full`
- Clean rebuild: append `clean`

Examples:
- `build_windows_64bit_msvc.bat`
- `build_windows_64bit_msvc.bat full`
- `build_windows_64bit_msvc_gui.bat clean`

### Linux

| Script | Description |
|--------|-------------|
| `build_linux_32bit.sh` | 32-bit i386 |
| `build_linux_32bit_armv6.sh` | 32-bit ARMv6 |
| `build_linux_64bit.sh` | 64-bit x86_64 (requires gcc multilib) |
| `build_linux_64bit_gui.sh` | 64-bit x86_64 GUI (requires gcc multilib) |
| `build_linux_aarch64.sh` | 64-bit ARM/AArch64 native |
| `build_linux_aarch64_gui.sh` | 64-bit ARM/AArch64 native GUI |

Recommended:
- Non-GUI verification: `./build_linux_64bit.sh` (x86_64) or `./build_linux_aarch64.sh` (ARM64)
- GUI / AirUI verification: `./build_linux_64bit_gui.sh` (x86_64) or `./build_linux_aarch64_gui.sh` (ARM64)
- Full output: append `full`
- Clean rebuild: append `clean`

#### AArch64 / ARM64 native build

On AArch64 hosts (e.g. Raspberry Pi 4/5, ARM cloud instances, Apple Silicon Linux VMs), the x86_64 helper scripts will fail because the toolchain does not support `-m32`/`-m64`. Use the `build_linux_aarch64*.sh` scripts instead.

Required system packages (Ubuntu/Debian example):

```bash
sudo apt-get install -y libsdl2-dev libx11-dev libxau-dev libxdmcp-dev \
    xorg-dev libssl-dev libasound2-dev libpulse-dev libwayland-dev \
    libxkbcommon-dev libudev-dev libdbus-1-dev libibus-1.0-dev libdecor-0-dev
```

Then build:

```bash
cd bsp/pc
./build_linux_aarch64.sh
```

Notes:
- The AArch64 build defines `LUAT_CONF_USE_LIBSYS_SOURCE` so that the inline `sys.lua` / `sysplus.lua` are loaded as source rather than precompiled 32-bit luac, avoiding `size_t size mismatch` errors on 64-bit platforms.
- `xmake` refuses to run as root by default; set `XMAKE_ROOT=y` or pass `--root` if you are building as root.

### macOS

| Script | Description |
|--------|-------------|
| `build_macos.sh` | no GUI |
| `build_macos_gui.sh` | GUI |

Recommended:
- Non-GUI verification: `./build_macos.sh`
- GUI / AirUI verification: `./build_macos_gui.sh`
- Full output: append `full`
- Clean rebuild: append `clean`

Output: `build/out/luatos-lua.exe` (Windows) or `build/out/luatos-lua` (Linux/macOS)

### C-Layer UTest Coverage

- Canonical helper: `bsp\pc\pc_utest_coverage.ps1`
- Typical usage:
  - `cd bsp\pc && .\pc_utest_coverage.ps1 -Suite dtls_basic`
  - `cd bsp\pc && .\pc_utest_coverage.ps1 -Suite tcp_basic`
  - `cd bsp\pc && .\pc_utest_coverage.ps1 -Suite http_basic -SkipBuild`
  - `cd bsp\pc && .\pc_utest_coverage.ps1 -Suite https_basic -SkipBuild`
- After the first suite build, reuse the same binary for more suites with `-SkipBuild`
- `-Suite` and `-TestcaseScripts` are mutually exclusive; pass only one of them
- `-Suite <name>` is resolved by scanning `testcase/utest/{net,lib,sys,fs}/<name>/` first, then `testcase/unit/<domain>/<name>/` and `testcase/func/<domain>/<name>/` as fallbacks
- Coverage HTML is written to `build\coverage\<suite>\html\index.html`
- C-layer utest suites (under `testcase\utest\`):
  - `net/dtls_basic`: PC-only DTLS-PSK loopback against `127.0.0.1`
  - `net/tcp_basic`: TCP reachability against `www.qq.com:80`
  - `net/http_basic`: HTTP reachability against `http://www.qq.com`
  - `net/https_basic`: HTTPS reachability against `https://www.qq.com`
  - `lib/core_basic`, `lib/crypto_basic`, `lib/miniz_basic`, `sys/ndk_basic`
  - `fs/pgfs_basic`: PGFS filesystem replay/FTL/gc selftests (all 17 tests are fully passing)
- Additional PC socket regression:
  - `socket_udp_limit_basic`: verifies `socket.rx(..., limit)` truncates UDP data and discards the unread datagram tail
- DTLS loopback depends on the PC mbedTLS3 config in `include\mbedtls_config_pc_mbedtls3.h` enabling DTLS server/PSK support

### UTest 快速运行（无覆盖率）

直接跑单个 utest 用例（跳过 OpenCppCoverage，只看 pass/fail）：

```powershell
# ⚠️ 必须先带 LUAT_USE_UTEST=y 编译，否则 socket.utest / http.utest 等函数不存在
cd bsp\pc
$env:LUAT_USE_UTEST = "y"
cmd /c build_windows_32bit_msvc.bat   # 或 build_windows_64bit_msvc.bat

# 运行（需要传两个脚本目录：common + 目标 testcase）
cd build\out
.\luatos-lua.exe ..\..\..\..\testcase\common\scripts\ ..\..\..\..\testcase\utest\net\dtls_basic\scripts\
```

输出中搜索 `OVERALL_PASS` / `OVERALL_FAIL` 判断结果。
`pc_utest_coverage.ps1` 已内置 `LUAT_USE_UTEST=y`，使用它时无需手动设置。

## FEATURES

- Lua 5.3 VM execution
- GUI simulation (SDL2)
- Network (via host OS adapter)
- TCP Client & Server (listen/accept)
- File system (host filesystem)
- Most libraries supported

## NETWORK ADAPTER

**File**: `port/network/luat_network_adapter_posix.c`

The PC simulator uses the host OS adapter for async network I/O. Key architecture:

### Threading Model
- **Main thread**: Lua VM, message bus, coroutine scheduling
- **Network worker**: Handles async I/O callbacks
- **Bridge**: `cb_to_nw_task()` forwards network events to framework callbacks

### Socket States
```
SC_IDLE → SC_USED → SC_CONNECTING → SC_CONNECTED → SC_CLOSING → SC_CLOSED
                  → SC_LISTENING (TCP Server)
```

### TCP Server Flow (one-to-one mode, `no_accept=1`)
1. `socket_listen`: creates listener handle, binds, listens
2. `on_new_connection`: accepts client into socket's embedded `tcp` handle
3. State: LISTEN(6) → ONLINE(5)
4. Close: closes both `listen_tcp` and embedded `tcp`

### ⚠️ Critical Async Pitfalls

| Pitfall | Detail |
|---------|--------|
| **Do not memcpy runtime handles** | Runtime-managed handles may carry internal state; copying them can corrupt async flow. |
| **Async close lifecycle** | Close callbacks fire later; keep handles valid until close callback runs. |
| **Accept target readiness** | The target handle must be initialized but not connected. |
| **Thread safety** | Async callbacks may run on a different thread; be careful with Lua state access. |

## PC 模拟器测试脚本

独立 PC 脚本存放在 `bsp/pc/test/<编号>.<名称>/main.lua`，不依赖 `testcase/common` 的 `testrunner`/`testsuite` 框架。新增脚本时从当前最大编号续编。

这些脚本用于验证 PC 模拟器特有功能或需要真实 PC 外设（摄像头、CH347、网卡模拟等）的场景，与 `testcase/` 中正式测试框架分离。

示例运行方式：

```powershell
cd bsp/pc/build/out
./luatos-lua.exe ../../../test/131.camera_pc/
```

## WHERE TO LOOK

| Task | Location |
|------|----------|
| Main entry | `src/main.c` |
| Build config | `xmake.lua` |
| Platform port | `port/` |
| Network adapter | `port/network/luat_network_adapter_posix.c` |
| UI tests | `ui/` |
| Debug records | `docs/` |

## CONVENTIONS

**Adding PC Support:**
- Add files to `src/` or `port/`
- Update `xmake.lua` with platform detection
- Use `#ifdef LUAT_USE_WINDOWS` etc.

## PC 模拟器测试脚本规范

### ⚠️ 必须在任务内部调用 `os.exit(0)`

PC 模拟器的 `sys.run()` 进入事件循环，该循环**不会因为 Lua 任务结束而自动退出**——只要还有任何活跃句柄（如网络、文件、定时器），进程就会一直挂起等待。

**正确写法**（`os.exit(0)` 在任务协程内、`sys.run()` 之前执行）：

```lua
sys.taskInit(function()
    -- ... 执行任务逻辑 ...
    videoplayer.close(player)
    log.info("main", "完成")
    os.exit(0)   -- ✅ 在任务内部强制退出
end)

sys.run()        -- 启动事件循环（os.exit 会在任务中断开它）
```

**错误写法**（`os.exit(0)` 在 `sys.run()` 之后，永远不会执行）：

```lua
sys.taskInit(function()
    -- ...
end)

sys.run()        -- ❌ 挂在这里，os.exit 永远不会执行
os.exit(0)
```

**适用场景**：所有在 PC 模拟器上运行的独立测试脚本（非 `testrunner` 框架管理的）都应遵循此规范。使用 `testrunner` 框架的标准测试用例由框架自身负责调用 `os.exit`，无需手动添加。

### `ad_fopen` 文件 API 与 luat_fs VFS

player SDK 中的 `plat_support.c` 通过 `#ifdef __LUATOS__` 条件编译，在 LuatOS 构建（包括 PC 模拟器）上将 `ad_fopen/fread/fseek/fclose/fsize` 路由到 `luat_fs_*` VFS 函数，而非直接使用 FatFS 或 stdio。

- **优点**：文件路径通过 LuatOS VFS 解析，PC 模拟器启动时传入的脚本目录自动映射为根路径，`ad_fopen("foo.mp4", ...)` 等价于 `luat_fs_fopen("/lua/foo.mp4", ...)`（取决于 VFS 挂载配置）
- **无需替换**：不必将 `ad_fopen` 换成 `fopen` 或 `luat_fs_fopen`，在 `__LUATOS__` 构建中它们本质上是同一个
- **文件路径**：测试时将资源文件放在脚本目录下，VFS 会正确解析

## CAMERA SCAN (Windows)

PC 模拟器支持扫码，链路与 `luatos-sdk-ccm42xx-gcc` 对齐：MF 摄像头取 MJPG 帧 → WIC 解出 8bit 灰度 → ZXing-C++ 软解码 → `camera.on(id, "scanned", cb)`。

- 解码库 ZXing-C++ v3.1.1 源码位于 `luatos-ext-components/zxing`（由 `luatos_ext_root` 解析）。**版本需与 SDK 一致**，否则码制/识别率行为会有差异。
- **依赖是可选的**：环境变量 `LUAT_USE_CAMERA_SCAN=y` 强制启用 / `=n` 强制禁用，未设置时按 `luatos_ext-components/zxing` 是否存在自动检测；未启用时 `camera.stream(..., scan_enable=true)` 无扫码行为、`camera.utest_qr_decode` 不存在，其余 camera 功能不受影响。启用时会定义宏 `LUAT_USE_CAMERA_SCAN`。
- `core/Version.h` 是 cmake 生成物，PC 侧用 `bsp/pc/stubs/zxing/Version.h` 代替（READERS 开 / WRITERS 关），不改上游文件。
- ZXing 3.x 需要 C++20：该目录的 TU 用 `{cxflags = {"/std:c++20", "/W0", "/DZXING_INTERNAL"}}` 单独指定（全局仍是 `cxx17`）。`ZXING_INTERNAL` 对应上游 cmake 的 `ZXING_PRIVATE_FLAGS`，缺了会在 `GridSampler.cpp` 报 `Size`/`Rectangle` 找不到；xmake 的 glob 不递归，故用 `core/src/**.cpp` 并排除 writer 组；`libzueci` 是 TextDecoder 的 ECI 依赖，需一并编译。
- Lua 用法（`camera.init` 后可不开预览）：
  ```lua
  camera.on(0, "scanned", function(id, str) log.info("scan", str) end)
  camera.stream(0, nil, nil, nil, false, true)   -- 最后一个参数 scan_enable
  ```
  非 USB 的 `camera.stream()` 分支在启用扫码的构建（宏 `LUAT_USE_CAMERA_SCAN`）下会调用 `luat_camera_scan()`，其他 BSP 不受影响。
- 扫码结果通过静态环形缓冲经 msgbus 投递给 `l_camera_handler` 的 `scanned` 分支（该分支不释放内存，故不能传堆指针）。
- 手动验证脚本：`bsp/pc/test/155.camera_scan/main.lua`（需本机摄像头）。

### camera.utest_qr_decode（仅 utest 构建）

无摄像头环境下验证解码链路，编译期由 `LUAT_USE_UTEST` + `LUAT_USE_CAMERA_SCAN` 两个宏同时控制（`$env:LUAT_USE_UTEST = "y"` 且启用扫码的构建才存在，否则用例自动跳过）：

```lua
local frame = videoplayer.read_frame(player)   -- frame.data 为 RGB565 小端像素
local str = camera.utest_qr_decode(frame.data, frame.width, frame.height)  -- 可选 fmt(0=RGB565,1=灰度) 与码制组合
```

配套用例：`testcase/utest/lib/camera_qr_basic`（QR 图片 fixture 走 `/luadb/qr_test.jpg`）。

## ANTI-PATTERNS

- ❌ Do NOT assume PC == hardware behavior (timing differences)
- ❌ Do NOT hardcode paths - use relative paths
- ❌ Do NOT skip hardware validation phase

## OPTIONAL FEATURES (环境变量开关)

PC 模拟器支持通过环境变量按需启用可选功能，遵循与 `LUAT_USE_GUI`、`LUAT_USE_MGBA` 相同的模式：

| 环境变量 | 值 | 说明 |
|----------|----|------|
| `LUAT_USE_GUI` | `y` | 启用 SDL2 GUI / AirUI |
| `LUAT_USE_MGBA` | `y` | 启用 mGBA GameBoy 模拟器 |
| `LUAT_USE_MP4PLAYER` | `y` | 启用 MP4/H.264/AAC 解码器 |
| `LUAT_USE_UTEST` | `y` | 启用 C 层 utest（`socket.utest`、`http.utest` 等）。覆盖率和直接运行都需要 |
| `MP4PLAYER_SRC_DIR` | 路径 | mp4player 源码根目录（与 `LUAT_USE_MP4PLAYER=y` 配合使用） |
| `LUAT_USE_CODEC_G729` | `y`/`n` | G.729 编解码（Annex A+B，`codec.G729` / audio_v2 G729）。源码位于 `luatos-ext-components/g729`；`y` 强制启用（缺失时报错），`n` 强制禁用，未设置时按目录存在性自动检测。禁用时 `LUAT_SUPPORT_G729` 不定义，g729 胶水层编译为空 |
| `LUATOS_EXT_ROOT` | 路径 | `luatos-ext-components` 仓库根目录。未设置时自动从脚本目录向上三级查找；**在 git worktree 中必须设置此变量**（或依赖自动 worktree 检测）。 |

### mp4player 启用示例（PowerShell）

```powershell
$env:LUAT_USE_MP4PLAYER = "y"
$env:MP4PLAYER_SRC_DIR  = "D:/github/luatos-sdk-ccm42xx-gcc/csdk/project/luatos/player"
cmd /c build_windows_32bit_msvc.bat
```

### ⚠️ xmake `remove_files` + `add_files` 陷阱

**问题**：在 `if` 块外无条件调用 `remove_files("port/mp4player/*.c")`，然后在 `if` 块内调用 `add_files("port/mp4player/foo.c")` 尝试加回某些文件——该文件**永远不会被编译**。`remove_files` 维护内部排除名单，后续 `add_files` 无法绕过。

**正确做法**：将只在条件下编译的 stub 文件放到**不被任何全局通配符覆盖**的目录，如 `stubs/<feature>/`：

```lua
-- ❌ 错误：remove_files 黑名单无法被 add_files 解除
remove_files("port/mp4player/*.c")
if os.getenv("LUAT_USE_MP4PLAYER") == "y" then
    add_files("port/mp4player/dac_sound_pc.c")  -- 无效
end

-- ✅ 正确：stubs/ 目录不在 port/**.c 通配符范围内
if os.getenv("LUAT_USE_MP4PLAYER") == "y" then
    add_files("stubs/mp4player/dac_sound_pc.c")  -- 正常编译
end
```

**目录约定**：`bsp/pc/stubs/<feature>/` — 存放只在特定可选功能开启时才参与编译的 PC stub 文件。

### ⚠️ `stubs/mp4player/` 里的**头文件**桩不能全局加入 include 路径

mp4player 的 `mp4_decode.c` 是按 MCU 写的，会 `#include "FreeRTOS.h" / "task.h" / "semphr.h"`。PC 没有 FreeRTOS，所以 `stubs/mp4player/` 下放了这三个兼容头，把 `xSemaphoreGive` / `vTaskSuspend` / `soc_task_sleep_ms` 映射到 LuatOS 的 `luat_rtos_*`。

这四个文件名（`FreeRTOS.h`、`task.h`、`semphr.h`、`msvc_attr_stub.h`）**太通用**，一旦被全局 `add_includedirs` 加进去就会遮蔽别的同名头。规则：

- `add_includedirs("stubs/mp4player")` **只能写在 mp4player 的 `if use_mp4player then` 块内**。
- 往里加头文件前先确认该名字在整个 PC include 路径上没有别的来源。

### 用 `forceincludes` 给上游源码打补丁

上游代码有两类问题**改 include 路径解决不了**，必须用 xmake 的 per-file 强制包含：

```lua
add_files(mp4player_src .. "/video_decode/mp4_decode.c",
    {forceincludes = {"msvc_attr_stub.h", "yuv_rgb_565.h"}})  -- 裸文件名，靠 -Istubs/mp4player 解析
```

- `msvc_attr_stub.h`：`__attribute__((aligned(4)))` 这类 GCC 扩展 MSVC 不认（错误点在所有 `#include` 之后）。
- `yuv_rgb_565.h`：上游只在 `#if defined(LUAT_USE_DISPLAY)` 里 include 它，但 `mplayer_h264_disp_cb()` 无条件使用 `YUV_RGB_Param` → 非 GUI 构建 `C2065`。

坑 1：**`forceincludes` 必须写裸文件名**。写相对路径（如 `stubs/mp4player/x.h`）时 MSVC 会相对**源文件所在目录**（这里是外部仓库 `luatos-ext-components/mp4player/video_decode/`）去找，必然 `C1083`。

坑 2：可以传 table 一次包含多个，`add_files` 的第三参数（`{forceincludes=...}`）只对**这一条** `add_files` 生效，后续的 `add_files` 不受影响。

### 上游 mp4player 会漂移，集成代码要按需核对

`luatos-ext-components/mp4player` 由别的仓库维护，改动后 PC 集成代码里的假设会过期。历史上踩过的几处：

- 上游给 `mp4player/audio_decode/mp3/mp3player.c` 加了 `_MINIMP3_IMPLEMENTATION_GUARD`，改为复用 LuatOS 的 `components/multimedia/minimp3.c`。PC 侧原先的 `remove_files(.../multimedia/minimp3.c)` 因此变成错误的——`mp3dec_init` / `mp3dec_decode_frame` 只有 LuatOS 那份实现。
- 上游新增 `video_decode/yuv_rb.c`（YUV 帧队列），`mp4_decode.c` 直接调用其 `yuv_queue_*`，漏加就是 6 个 `LNK2019`。
- 上游 `plat_support.h` 在 `__LUATOS__` 下无条件 `#include "luat_display.h"`，而 `components/display/inc` 只在 GUI 构建里加过 → 非 GUI 构建 `C1083`。
- `YUV_RGB_565()` 真机由 SoC C 库提供，LuatOS 内没有实现，PC 侧用 `stubs/mp4player/yuv_rgb_565_pc.c` 转接到库内已有的 `yuv420p_to_rgb565_thumb()`。

**核对方法**：`xmake -y` 跑完后只看链接错误里的 `LNK2019`/`LNK2005`，逐个回上游/本仓库找实现方，比反复全量编译快得多。想快速迭代单文件时可以用 `xmake project -k compile_commands .` 生成 `compile_commands.json`，复用其中该文件的完整编译参数单独跑 `cl`（~10 秒一轮）。
