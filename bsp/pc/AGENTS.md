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
| `build_linux_64bit.sh` | 64-bit |
| `build_linux_64bit_gui.sh` | 64-bit, GUI |

Recommended:
- Non-GUI verification: `./build_linux_64bit.sh`
- GUI / AirUI verification: `./build_linux_64bit_gui.sh`
- Full output: append `full`
- Clean rebuild: append `clean`

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

## FEATURES

- Lua 5.3 VM execution
- GUI simulation (SDL2)
- Network (via host OS, libuv adapter)
- TCP Client & Server (listen/accept)
- File system (host filesystem)
- Most libraries supported

## NETWORK ADAPTER (libuv)

**File**: `port/network/luat_network_adapter_libuv.c`

The PC simulator uses libuv for async network I/O. Key architecture:

### Threading Model
- **Main thread**: Lua VM, message bus, coroutine scheduling
- **libuv thread**: Runs `uv_run()` event loop, handles I/O callbacks
- **Bridge**: `cb_to_nw_task()` sends events via `uv_async_send` from main → libuv thread

### Socket States
```
SC_IDLE → SC_USED → SC_CONNECTING → SC_CONNECTED → SC_CLOSING → SC_CLOSED
                  → SC_LISTENING (TCP Server)
```

### TCP Server Flow (one-to-one mode, `no_accept=1`)
1. `libuv_socket_listen`: creates separate `listen_tcp` (heap), binds, listens
2. `on_new_connection`: accepts client into socket's embedded `tcp` handle
3. State: LISTEN(6) → ONLINE(5)
4. Close: closes both `listen_tcp` and embedded `tcp`

### ⚠️ Critical libuv Pitfalls

| Pitfall | Detail |
|---------|--------|
| **Never memcpy uv handles** | `uv_tcp_t` contains internal linked-list pointers (`handle_queue`). Memcpy corrupts the event loop. |
| **`uv_close` is async** | Close callback fires in future event loop iteration. Heap-allocate handles that need to outlive close. |
| **`uv_accept` target must be init'd** | The target handle must be initialized (`uv_tcp_init`) but not connected. |
| **Thread safety** | Callbacks from `uv_async_send` fire on the libuv thread. Be careful with Lua state access. |

### Debug Reference
- See `docs/debug_tcp_listen.md` for the full TCP listen/accept debugging record

## WHERE TO LOOK

| Task | Location |
|------|----------|
| Main entry | `src/main.c` |
| Build config | `xmake.lua` |
| Platform port | `port/` |
| Network adapter | `port/network/luat_network_adapter_libuv.c` |
| UI tests | `ui/` |
| Debug records | `docs/` |

## CONVENTIONS

**Adding PC Support:**
- Add files to `src/` or `port/`
- Update `xmake.lua` with platform detection
- Use `#ifdef LUAT_USE_WINDOWS` etc.

## PC 模拟器测试脚本规范

### ⚠️ 必须在任务内部调用 `os.exit(0)`

PC 模拟器的 `sys.run()` 最终调用 libuv 的 `uv_run(UV_RUN_DEFAULT)`，该事件循环**不会因为 Lua 任务结束而自动退出**——只要还有任何活跃的 libuv 句柄（如网络、文件、定时器），进程就会一直挂起等待。

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
| `MP4PLAYER_SRC_DIR` | 路径 | mp4player 源码根目录（与 `LUAT_USE_MP4PLAYER=y` 配合使用） |

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
