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

### Windows

| Script | Description |
|--------|-------------|
| `build_windows_32bit_msvc.bat` | 32-bit, no GUI |
| `build_windows_32bit_msvc_gui.bat` | 32-bit, GUI (with clean) |
| `build_windows_64bit_msvc.bat` | 64-bit, no GUI |
| `build_windows_64bit_msvc_gui.bat` | 64-bit, GUI |

Recommended:
- Non-GUI verification: `xmake -y`
- GUI / AirUI verification: `build_windows_64bit_msvc_gui.bat` (or `build_windows_32bit_msvc_gui.bat` when targeting 32-bit)

### Linux

| Script | Description |
|--------|-------------|
| `build_linux_32bit.sh` | 32-bit i386 |
| `build_linux_32bit_armv6.sh` | 32-bit ARMv6 |
| `build_linux_64bit.sh` | 64-bit |
| `build_linux_64bit_gui.sh` | 64-bit, GUI |

Recommended:
- Non-GUI verification: `xmake -y`
- GUI / AirUI verification: set `LUAT_USE_GUI=y`, run `xmake f ...`, then `xmake -y`, or use `build_linux_64bit_gui.sh`

### macOS

| Script | Description |
|--------|-------------|
| `build_macos.sh` | no GUI |
| `build_macos_gui.sh` | GUI |

Recommended:
- Non-GUI verification: `xmake -y`
- GUI / AirUI verification: set `LUAT_USE_GUI=y`, run `xmake f ...`, then `xmake -y`, or use `build_macos_gui.sh`

Output: `build/out/luatos-lua.exe` (Windows) or `build/out/luatos-lua` (Linux/macOS)

## FEATURES

- Lua 5.3 VM execution
- GUI simulation (SDL2)
- Network (via host OS)
- File system (host filesystem)
- Most libraries supported

## WHERE TO LOOK

| Task | Location |
|------|----------|
| Main entry | `src/main.c` |
| Build config | `xmake.lua` |
| Platform port | `port/` |
| UI tests | `ui/` |

## CONVENTIONS

**Adding PC Support:**
- Add files to `src/` or `port/`
- Update `xmake.lua` with platform detection
- Use `#ifdef LUAT_USE_WINDOWS` etc.

## ANTI-PATTERNS

- ❌ Do NOT assume PC == hardware behavior (timing differences)
- ❌ Do NOT hardcode paths - use relative paths
- ❌ Do NOT skip hardware validation phase
