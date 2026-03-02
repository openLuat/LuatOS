# LuatOS AirUI - GUI Framework

**Scope**: `components/airui/` - LVGL 9-based GUI framework with Lua bindings.

## OVERVIEW

AirUI provides a comprehensive GUI framework built on LVGL 9, with Lua bindings for rapid UI development on embedded devices.

## STRUCTURE

```
airui/
├── lvgl9/            # LVGL 9.x source (modified)
│   ├── src/          # Core LVGL source
│   ├── binding/      # Lua-C bindings
│   └── font/         # Font files
├── src/              # AirUI extensions
│   ├── font/         # Additional fonts
│   └── ...           # UI components
├── binding/          # Lua binding layer
└── inc/              # Headers
```

## WHERE TO LOOK

| Task | Location |
|------|----------|
| LVGL core | `lvgl9/src/` |
| Lua bindings | `binding/`, `lvgl9/binding/` |
| Fonts | `lvgl9/font/`, `src/font/` |
| UI components | `src/` |

## CONVENTIONS

**LVGL Lua API:**
- Objects: `lv.<widget>.create(parent)`
- Setters: `obj:set_<property>(value)`
- Getters: `obj:get_<property>()`
- Events: `obj:add_event(callback, event)`

**Example:**
```lua
local scr = lv.obj()
local btn = lv.btn(scr)
btn:set_size(100, 50)
btn:add_event(function() print("clicked") end, lv.EVENT.CLICKED)
```

## BUILD FLAGS

```c
#define LUAT_USE_GUI        // Enable GUI support
#define LUAT_USE_AIRUI      // Enable AirUI
#define U8G2_USE_LARGE_FONTS // Large font support
```

## ANTI-PATTERNS

- ❌ Do NOT modify LVGL core without compatibility testing
- ❌ Do NOT create UI objects outside main thread
- ❌ Do NOT forget `lv.task_handler()` in main loop
