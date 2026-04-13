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

## ANTI-PATTERNS

- ❌ Do NOT assume PC == hardware behavior (timing differences)
- ❌ Do NOT hardcode paths - use relative paths
- ❌ Do NOT skip hardware validation phase
