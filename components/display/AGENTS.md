# LuatOS Display - 显示核心库

**Scope**: `components/display/` - 新一代显示抽象层，Panel/Interface 分离架构，支持 RGB/MIPI-DSI/MIPI-DBI/SPI/QSPI/SDL 等多种接口。

## OVERVIEW

Display 是 LuatOS 的新显示核心库，替代 `components/lcd` 的 Panel+Interface 耦合设计。它将面板 IC 驱动与物理接口分离，提供统一的 FrameBuffer 管理和 VSync 机制，为 AirUI/LVGL 提供 DIRECT 渲染模式的底层支撑。

## STRUCTURE

```
display/
├── binding/                       # Lua binding entry points (display.xxx)
│   └── luat_lib_display.c         # display.init/on/off/sleep/flush/...
├── inc/                           # 公共头文件
│   └── luat_display.h             # 所有类型定义、枚举、API 声明
└── src/
    ├── luat_display.c             # 核心框架：注册表、分发、init/flush 默认实现
    ├── luat_display_fb.c          # 默认 FrameBuffer 管理器
    ├── interface/                 # 物理接口驱动
    │   ├── luat_display_if_rgb.c  # RGB 接口 stub (真机 BSP 覆盖)
    │   └── luat_display_if_sdl.c  # SDL2 接口 (PC 模拟器)
    └── panel/                     # 面板 IC 驱动
        └── luat_display_panel_*.c # 各面板 IC 的 panel_ops 实例
```

## 核心架构

### Panel / Interface 分离

```
luat_display_t
├── panel_ops → luat_display_panel_ops_t   (面板 IC 驱动：init_cmds, madctl, 电源控制)
├── if_ops    → luat_display_if_ops_t      (物理接口驱动：write_cmd, fb_flush, pan_display)
├── fb_info   → luat_display_fb_info_t     (FrameBuffer 描述信息)
└── rgb_timing → luat_display_rgb_timing_t (RGB 接口时序参数)
```

### 生命周期流程

```
display.init() → panel_ops->init() → if_ops->init() → fb_probe → fb_allocate
    → display.wakeup() → display.on()
display.flush() → if_ops->fb_flush() → if_ops->pan_display()
display.sleep() → panel_ops->sleep() → if_ops->deinit()
```

## WHERE TO LOOK

| Task | Location |
|------|----------|
| 核心类型定义 | `inc/luat_display.h` |
| 初始化流程 / 电源控制 | `src/luat_display.c` |
| FrameBuffer 分配策略 | `src/luat_display_fb.c` |
| 面板 IC 添加 | `src/panel/luat_display_panel_*.c` |
| 新增接口驱动 | `src/interface/luat_display_if_*.c` |
| Lua API | `binding/luat_lib_display.c` |
| BSP 配置宏 | `bsp/<platform>/include/luat_conf_bsp.h` (`LUAT_USE_DISPLAY`) |
| 构建配置 | `bsp/pc/xmake.lua` (GUI 构建路径) |

## CONVENTIONS

### 命名规范

- 公开 API 使用 `luat_display_` 前缀: `luat_display_init`, `luat_display_flush`
- 默认实现使用 `_default` 后缀: `luat_display_init_default`, `luat_display_flush_default`
- BSP 可覆盖的函数使用 `LUAT_WEAK` 声明: `LUAT_WEAK int luat_display_init(...)`
- Panel 驱动 ops 变量: `panel_ops_<model>` → `panel_ops_st7789`
- Interface 驱动 ops 变量: `if_ops_<type>` → `if_ops_rgb`, `if_ops_sdl`

### Panel 驱动添加步骤

1. 创建 `src/panel/luat_display_panel_<model>.c`
2. 定义 `const luat_display_panel_ops_t panel_ops_<model>` (填充 init_cmds / madctl 等)
3. 在 `binding/luat_lib_display.c` 的 `panel_regs[]` 注册表中添加条目
4. 在 `inc/luat_display.h` 中 `extern` 声明 ops 变量 (可选)

### Interface 驱动添加步骤

1. 创建 `src/interface/luat_display_if_<type>.c`
2. 实现 `const luat_display_if_ops_t if_ops_<type>`
3. 在 `binding/luat_lib_display.c` 的 `if_regs[]` 注册表中添加条目
4. 在 `inc/luat_display.h` 中 `extern` 声明 ops 变量

### 默认实现与 BSP 覆盖

- 核心流程函数使用 `LUAT_WEAK` + `_default` 双函数模式:
  ```c
  int luat_display_init_default(luat_display_t *disp) { /* 默认实现 */ }
  LUAT_WEAK int luat_display_init(luat_display_t *disp) { return luat_display_init_default(disp); }
  ```
- BSP 可直接覆盖 `luat_display_init` 提供强定义
- Interface 驱动由 BSP 提供强实现替换 stub (真机时)

### Init 命令表编码 (兼容 lcd 格式)

| 高字节 | 低字节 | 含义 |
|--------|--------|------|
| `0x00` / `0x02` | `cmd` | 发送命令字节 |
| `0x03` | `data` | 追加数据字节 |
| `0x01` | `delay_ms` | 延时毫秒 |

## BUILD / VERIFICATION

- Display 库在 GUI 构建路径中编译 (`add_files(luatos.."components/display/src/**.c")`)
- 必须使用 GUI-enabled 构建验证: `build_windows_64bit_msvc_gui.bat`
- 新文件放入 `src/` 目录自动被 `src/**.c` 递归通配符包含，无需修改 xmake.lua
- BSP 配置宏 `LUAT_USE_DISPLAY` 在 `luat_conf_bsp.h` 中定义

## Lua API

```lua
-- PC 模拟器
display.init("st7789", {w = 240, h = 320, interface = "sdl"})

-- 真机 RGB
display.init("st7789", {w = 480, h = 800, interface = "rgb",
    hbp = 20, hfp = 20, hspw = 5, vbp = 20, vfp = 20, vspw = 5,
    pclk_hz = 25000000, pin_rst = 18, pin_bl = 19})

display.on() / display.off() / display.sleep() / display.wakeup()
display.flush()
display.setRotation(display.ROTATE_90)
local w, h = display.getSize()
local addr, size, count = display.getFbInfo()
```

## ANTI-PATTERNS

- ❌ 不要把 Panel 逻辑和 Interface 逻辑混在一个文件里
- ❌ 不要在 Panel 驱动中硬编码 SPI/RGB 等接口细节，应通过 `if_ops` 分发
- ❌ 不要在 Interface 驱动中依赖特定的面板 IC
- ❌ 不要用 `#ifndef LUAT_COMPILER_NOWEAK` 包裹 Interface stub 函数 (用 static 函数 + ops 表引用)
- ❌ 不要在非 GUI 构建中验证 Display 变更
