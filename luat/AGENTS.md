# LuatOS Core Framework

**Scope**: `luat/` - Core framework, hardware abstraction, and VM integration.

## OVERVIEW

The `luat/` directory contains LuatOS core framework code that bridges the Lua VM (`lua/`) with hardware abstractions and provides the foundation for all LuatOS functionality.

## STRUCTURE

```
luat/
├── include/          # Core C headers (luat_base.h, luat_gpio.h, etc.)
├── modules/          # C implementations of Lua libraries
├── vfs/              # Virtual File System (FATFS, LFS, luadb)
└── weak/             # Weak reference implementations
```

## WHERE TO LOOK

| Task | Location | File Pattern |
|------|----------|--------------|
| Add hardware driver | `modules/` | `luat_lib_<name>.c` |
| Core APIs | `include/` | `luat_*.h` |
| File system | `vfs/` | `luat_fs_*.c` |
| Module registration | `include/luat_libs.h` | Library exports |

## CONVENTIONS

**C Module Files:**
- Naming: `luat_lib_<module>.c` (e.g., `luat_lib_gpio.c`)
- Registration: `luaopen_<module>` function exports library
- Headers: Place in `include/luat_<module>.h`

**API Design:**
- All public APIs use `luat_` prefix
- Return `int`: 0=success, negative=error
- Validate parameters at function entry

**Example Module Structure:**
```c
#include "luat.h"
#include "luat_gpio.h"

static int l_gpio_set(lua_State *L) {
    int pin = luaL_checkinteger(L, 1);
    int mode = luaL_checkinteger(L, 2);
    return luat_gpio_set(pin, mode);
}

LUAMOD_API int luaopen_gpio(lua_State *L) {
    luaL_newlib(L, reg);
    return 1;
}
```

## KEY FILES

| File | Purpose |
|------|---------|
| `include/luat_base.h` | Core definitions, version, main entry |
| `include/luat_libs.h` | Library registration table |
| `modules/luat_main.c` | Main initialization |
| `modules/luat_base.c` | Base library implementation |

## ANTI-PATTERNS

- ❌ Do NOT use direct Lua VM calls bypassing `luat_` APIs
- ❌ Do NOT add platform-specific code in `modules/` - use `bsp/`
- ❌ Do NOT modify VFS internals without understanding mount points
