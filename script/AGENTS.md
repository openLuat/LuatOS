# LuatOS Script Libraries

**Scope**: `script/` - Lua libraries, drivers, and application templates.

## OVERVIEW

Lua script libraries providing high-level APIs for peripherals, protocols, and complete application templates.

## STRUCTURE

```
script/
├── corelib/          # Built-in core libraries
│   └── sys.lua       # Task scheduling system
├── libs/             # External libraries (drivers)
│   ├── ex*.lua       # Extension libraries
│   └── peripheral/   # Peripheral drivers
└── turnkey/          # Complete project templates
```

## WHERE TO LOOK

| Task | Location | Examples |
|------|----------|----------|
| Core system | `corelib/` | `sys.lua`, `log.lua` |
| Peripheral driver | `libs/` | `exmodbus_tcp.lua` |
| Complete project | `turnkey/` | `scanner_air105/` |
| UI components | `libs/` | `exeasyui.lua` |

## CONVENTIONS

**Library Structure:**
```lua
local mod = {}

function mod.init(params)
    -- Initialize
end

function mod.do_something(arg)
    -- Implementation
end

return mod
```

**Loading:**
```lua
local mylib = require("mylib")
mylib.do_something()
```

**Task-based:**
```lua
sys.taskInit(function()
    -- Async operations
end)
```

## ANTI-PATTERNS

- ❌ Do NOT poll in tight loops - use `sys.wait()`
- ❌ Do NOT block the main thread
- ❌ Do NOT use global variables for module state
