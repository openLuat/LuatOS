# LuatOS AirUI - GUI Framework

**Scope**: `components/airui/` - AirUI framework built on LVGL 9, including core runtime, platform adapters, widgets, fonts, and Lua bindings.

## OVERVIEW

AirUI is LuatOS's GUI layer. It wraps LVGL 9, provides LuatOS/SDL platform glue, exposes Lua-facing widgets, and includes helper code for XML, display, input, events, fonts, and component metadata.

## STRUCTURE

```
airui/
├── binding/                  # AirUI Lua binding entry points (airui.xxx)
├── inc/                      # Public headers and shared declarations
├── lvgl9/                    # Bundled LVGL 9 source tree and headers
└── src/
    ├── core/                 # Context, display, input, buffer, fs, xml, error helpers
    ├── components/
    │   ├── base/             # Marshal, metadata, event, common component helpers
    │   └── widgets/          # Widget implementations (button, win, label, chart, ...)
    ├── platform/
    │   ├── luatos/           # Runtime adapters for LuatOS devices
    │   └── sdl/              # PC simulator / SDL adapters
    └── font/                 # Built-in AirUI fonts
```

## WHERE TO LOOK

| Task | Location |
|------|----------|
| LVGL core / widget internals | `lvgl9/src/` |
| AirUI top-level Lua module | `binding/luat_lib_airui.c` |
| Component Lua bindings | `binding/luat_lib_airui_*.c` |
| Widget implementations | `src/components/widgets/` |
| Shared component helpers | `src/components/base/` |
| Runtime / context / XML / display flow | `src/core/` |
| SDL simulator integration | `src/platform/sdl/` |
| LuatOS platform integration | `src/platform/luatos/` |
| Public headers | `inc/` |
| AirUI built-in fonts | `src/font/` |

## CONVENTIONS

**Widget layering:**
- Lua-facing API lives in `binding/luat_lib_airui_*.c`
- Widget creation and behavior live in `src/components/widgets/luat_airui_*.c`
- Shared Lua table parsing, event binding, and metadata logic belong in `src/components/base/`
- Cross-platform display/input/time logic belongs in `src/platform/`, not in widget files

**Naming:**
- Widget implementation functions use `airui_<widget>_*`
- Lua binding files use `luat_lib_airui_<widget>.c`
- Shared parsing helpers use `airui_marshal_*`

**Lua API style:**
- Constructors follow `airui.<widget>({ ... })`
- Instance methods follow `obj:set_xxx(...)`, `obj:get_xxx(...)`, `obj:add_xxx(...)` when applicable
- Config tables should preserve backward compatibility where possible; deprecations should warn before removal

**Style/config handling:**
- Use shared marshal helpers for reading Lua config tables
- For optional style overrides, prefer helpers that preserve the distinction between "not provided" and explicit zero/false values
- If multiple widgets need the same parsing or normalization logic, move it to shared helpers instead of duplicating static functions

## BUILD / VERIFICATION

- AirUI changes are GUI changes; do not verify them with plain `xmake -y` alone
- When modifying `components/airui/`, LVGL, SDL display flow, or `LUAT_USE_GUI` code, use the GUI-enabled PC build path
- On Windows, prefer `bsp/pc/build_windows_64bit_msvc_gui.bat` or `bsp/pc/build_windows_32bit_msvc_gui.bat`
- On Linux/macOS, ensure `LUAT_USE_GUI=y` is enabled before running `xmake f ...` and `xmake -y`, or use the provided GUI helper scripts
- Do not report AirUI verification complete unless the GUI build path has been exercised

## ANTI-PATTERNS

- ❌ Do NOT modify the LVGL core without explicit permission
- ❌ Do NOT put shared parsing helpers into a single widget file when they belong in `src/components/base/`
- ❌ Do NOT mix platform-specific SDL/LuatOS logic directly into generic widget implementations
- ❌ Do NOT break existing Lua API compatibility silently; keep compatibility paths or add explicit deprecation warnings
- ❌ Do NOT claim AirUI changes were verified if only a non-GUI build was run
