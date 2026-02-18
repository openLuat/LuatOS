# Copilot Instructions for LuatOS

## Build, Test, and Lint

### Build (PC Simulator)
The project uses [xmake](https://xmake.io) for building.
- **Directory**: `bsp/pc`
- **Configure**: `xmake f -a x86 -y` (or `-a x64`)
- **Build**: `xmake -y`
- **Clean**: `xmake clean -a`

### Test (Lua Scripts)
Tests are located in `testcase/` and are Lua scripts executed by the LuatOS firmware (or PC simulator).
- **Structure**: `testcase/<feature>/<feature>_basic/scripts/`
- **Run**: Execute the built binary and pass exactly two script directories: `testcase/common/scripts/` and one target testcase's `scripts/` directory.
  ```powershell
  # Example running a test on PC simulator
  build\out\luatos-lua.exe ..\..\testcase\common\scripts\ ..\..\testcase\unit_testcase_tools\mreport\scripts\
  ```
  Note: This mode does not support running multiple target testcase directories in a single command.
  Note: Check `bsp/pc/xmake.lua` for the exact output path (usually `$(builddir)/out`).

- **New Test**:
  1. Create `testcase/<feature>/<feature>_basic/scripts/`
  2. Create `metas.json` with test metadata.
  3. Create `main.lua` (define `PROJECT`, `VERSION`, require `testrunner`, call `sys.taskInit`)
  4. Create `<feature>_test.lua` with functions starting with `test_`

## High-Level Architecture

LuatOS is an embedded Lua operating system based on Lua 5.3.
- **`lua/`**: Modified Lua 5.3 VM source.
- **`luat/`**: Core framework (task management, VFS, HAL).
  - **`luat/modules/`**: C implementations of Lua libraries (e.g., `luat_lib_gpio.c`).
  - **`luat/vfs/`**: Virtual File System.
- **`components/`**: Extension libraries (Network, GUI, Drivers).
  - **`components/network/`**: Network stacks (LwIP, etc.).
  - **`components/airui/`**: GUI components (LVGL based).
- **`bsp/`**: Board Support Packages. `bsp/pc` is the simulator.
- **`script/`**: Lua scripts, core libraries (`corelib`), and drivers (`libs`).

## Key Conventions

### C Code (Core & Modules)
- **Prefix**: Core APIs use `luat_` prefix (e.g., `luat_gpio_set`).
- **Headers**: Core headers in `luat/include`.
- **Macros**: Feature flags often prefixed with `LUAT_` (e.g., `LUAT_USE_GUI`).

### Lua Code (Scripts & Tests)
- **Task Management**: Use `sys.taskInit(function() ... end)` for concurrency.
- **Entry Point**: Scripts end with `sys.run()`.
- **Testing**:
  - Test functions must start with `test_` to be picked up by `testrunner`.
  - Use `log.info()` for output.
  - Assertions: `assert(condition, message)`.

### Build Configuration (xmake)
- **`xmake.lua`**: Located in BSP directories (e.g., `bsp/pc/xmake.lua`).
- **Dependencies**: Components are included/excluded via `add_files` and `remove_files` based on flags.
