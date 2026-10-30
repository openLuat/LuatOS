# AirUI 图形库

`components/airui/` 是 LuatOS 的 GUI 层，当前版本 `1.3.0`（`inc/luat_airui_conf.h` 的 `AIRUI_VERSION`）。它包一层 LVGL 9，向 Lua 暴露控件，并把显示、输入、文件系统和时基接到 PC（SDL）或真机（LuatOS）。

面板 IC、物理接口和 FrameBuffer 归属 `components/display/`（以及旧的 `lcd`）。AirUI 只通过平台 ops 使用它们。

控件支持情况说明：

| 控件 | Air8000 / Air780EHM | Air1601 / Air1602 | Air8101 |
|------|---------------------|-------------------|---------|
| `button` `label` `image` `container` `bar` `table` `tabview` `win` `dropdown` `switch` `msgbox` `textarea` `keyboard` `animimg` `chart` `qrcode` `spinner` `shape` `checkbox` | 支持 | 支持 | 支持 |
| `slider` | 不支持 | 支持 | 支持 |
| `camera` | 不支持 | 支持 | 不支持 |
| `map` | 不支持 | 支持 | 不支持 |
| `video` | 支持 | 支持 | 支持 |
| `nes` | 不支持 | 不支持 | 不支持 |
| `gbc` | 不支持 | 不支持 | 不支持 |
| `lottie` | 不支持 | 不支持 | 不支持 |

---

## 范围

本文件覆盖：

- 各平台固件实际编入的控件
- 控件从 Lua 配置表到 LVGL 对象的分层
- SDL 与 LuatOS 两套平台适配
- 真机显示后端的探测顺序
- 键盘输入协调层
- 新增控件的接线顺序
- GUI 构建验证

不在本文件里展开：

- LVGL 9 控件内部实现（`lvgl9/`）
- 面板驱动与接口驱动，见 `components/display/AGENTS.md`
- 通用 PC 构建规则，见根目录 `AGENTS.md` 的 Build & Test Commands，以及 `bsp/pc/AGENTS.md`

---

## 先看哪里

| 要改的东西 | 位置 |
|------------|------|
| Lua 模块入口（`airui.init` / 控件注册表） | `binding/luat_lib_airui.c` |
| 单个控件的 Lua 方法 | `binding/luat_lib_airui_<控件>.c` |
| 控件创建与行为 | `src/components/widgets/luat_airui_<控件>.c` |
| 配置表解析、事件、元数据 | `src/components/base/` |
| 上下文、缓冲、旋转 | `src/core/luat_airui_ctx.c`、`src/core/luat_airui_display.c` |
| 键盘 show/hide 的唯一入口 | `src/core/luat_airui_input_coordinator.c` |
| 焦点与预编辑状态 | `src/core/luat_airui_input_session.c` |
| 真机显示调度（先 display，再 lcd） | `src/platform/luatos/luat_airui_display_luatos.c` |
| display 库后端 | `src/platform/luatos/luat_airui_display_luatos_disp.c` |
| lcd 库后端 | `src/platform/luatos/luat_airui_display_luatos_lcd.c` |
| 真机触摸 / HID / 按键 | `src/platform/luatos/luat_airui_input_*.c` |
| SDL 显示与输入 | `src/platform/sdl/` |
| 公共类型与平台 ops | `inc/luat_airui.h` |
| 控件类型、元表名、marshal | `inc/luat_airui_component.h` |
| Lua userdata 生命周期 | `inc/luat_airui_binding.h` |
| 平台宏、缓存、字体、可选控件 | `inc/luat_airui_conf.h` |
| 内置字体 | `src/font/` |
| PC 是否编进 AirUI | `bsp/pc/xmake.lua`（`LUAT_USE_GUI`）与 `bsp/pc/include/luat_conf_bsp.h` |

---

## 库结构

```
airui/
├── binding/                         # Lua：airui.xxx 与实例方法
├── inc/                             # 公共头文件
├── lvgl9/                           # 内置 LVGL 9，默认不要改
└── src/
    ├── core/                        # 上下文、显示缓冲、文件系统、输入协调、调试
    ├── components/
    │   ├── base/                    # marshal、元数据、事件、字体工具
    │   └── widgets/                 # 各控件实现
    ├── platform/
    │   ├── luatos/                  # 真机：显示后端、触摸、HID、JPG/PNG 解码、时基
    │   └── sdl/                     # PC 模拟器
    └── font/                        # MiSans、hzfont
```

调用链固定为四层：

```
Lua  airui.<控件>({...})          binding/luat_lib_airui_<控件>.c
        │
        ▼
控件  airui_<控件>_create_from_config   src/components/widgets/
        │  读配置走 base/marshal，事件走 base/event
        ▼
核心  airui_ctx_t + LVGL            src/core/
        │
        ▼
平台  display / fs / input / time   src/platform/{luatos,sdl}/
```

运行态集中在 `airui_ctx_t`，Lua 侧通过注册表键 `airui_ctx` 取回。平台私有数据放在 `ctx->platform_data`，真机类型是 `luatos_platform_data_t`。

已注册控件（`binding/luat_lib_airui.c`）：`button`、`label`、`image`、`map`、`container`、`bar`、`table`、`tabview`、`win`、`dropdown`、`switch`、`msgbox`、`textarea`、`keyboard`、`lottie`、`slider`、`animimg`、`video`、`chart`、`qrcode`、`spinner`、`shape`、`checkbox`、`nes`、`gbc`。`camera` 仅在 `LUAT_USE_AIRUI_CAMERA` 打开时注册。

---

## 约定

### 命名与文件

- 控件实现函数用 `airui_<控件>_*`，文件是 `src/components/widgets/luat_airui_<控件>.c`
- Lua 绑定文件是 `binding/luat_lib_airui_<控件>.c`
- 元表名是 `"airui.<控件>"`，常量写在 `inc/luat_airui_component.h`（如 `AIRUI_BUTTON_MT`）
- 配置表解析用 `airui_marshal_*`，放在 `src/components/base/luat_airui_marshal.c`
- 平台 ops 分成 `display_ops`、`fs_ops`、`input_ops`、`time_ops`，定义在 `inc/luat_airui.h`

### Lua API

- 构造：`airui.<控件>({ ... })`，返回的 userdata 走 `airui_push_component_userdata()`
- 方法：`obj:set_xxx(...)`、`obj:get_xxx(...)`、`obj:add_xxx(...)`
- 实例方法注册在 `airui_register_<控件>_meta()`，并调用 `airui_component_set_metatable_gc()`
- 配置表保持兼容。废弃字段留兼容路径并打警告，例如按钮的 `stype`，以及 `airui.indev_bind_touch`（改用 `airui.device_bind_touch`）
- 简单控件的短按/长按分界是 `AIRUI_RELEASE_SELECT_LONG_PRESS_MS`（400ms），需要这套判定时用 `airui_component_enable_release_select_dispatch()`

### 配置表

- 读整型、布尔、字符串、颜色、点、渐变方向，都走 `airui_marshal_*`
- 可选样式要区分「没传」和「显式传了 0 / false」。没传时用 `airui_marshal_integer_opt()` 一类返回 bool 的接口，不要用带默认值的读取把缺省当成 0
- 两个以上控件共用的解析或归一化，抽到 `src/components/base/`，不要在控件文件里再抄一份 static 函数

### 平台

- 编译开关二选一：PC 为 `LUAT_USE_AIRUI_SDL2`，真机为 `LUAT_USE_AIRUI_LUATOS`，参数集中在 `inc/luat_airui_conf.h`
- 真机显示只接受 `LV_COLOR_FORMAT_RGB565`。调度器先挂 `display` 后端（`LUAT_USE_DISPLAY`），失败再挂 `lcd` 后端（`LUAT_USE_LCD`）
- 平台提供的连续缓冲由 `display_ops->get_buffers` 交出，AirUI 不释放；只有 `ctx->draw_buf1` / `draw_buf2` 这类自分配缓冲才在 `deinit` 里释放
- 硬件图层（视频、相机等直推画面）走 `display_ops->direct_present` / `direct_hide`，按 `owner` 独占图层
- SDL 打开了 `AIRUI_SDL_UPRIGHT_PREVIEW`：`airui.set_rotation()` 的逻辑分辨率和输入语义与真机一致，PC 窗口按逻辑坐标直立预览
- 键盘的显示和隐藏只经过 `airui_input_coordinator_request_show` / `request_hide`。控件和绑定不要直接改键盘可见性

### 可选能力

这些宏由板级 `luat_conf_bsp.h` 打开，缺省行为以 `inc/luat_airui_conf.h` 为准：

| 宏 | 作用 |
|----|------|
| `LUAT_USE_AIRUI_SLIDER` | 打开 LVGL slider，否则没有 `airui.slider` 的底层控件 |
| `LUAT_USE_AIRUI_CAMERA` | 编译并注册 `airui.camera` |
| `LUAT_USE_AIRUI_IMAGE_CACHE_SIZE` | 覆盖真机图片缓存，默认 1MB；SDL 固定 4MB |
| `LUAT_USE_AIRUI_DISPLAY_BUFFER_SIZE_DIVISOR` | 显示缓冲相对整屏的分母，默认 2（单缓冲半屏） |
| `LUAT_USE_AIRUI_MISANS_FONT_16` | 真机启用 16 号 MiSans 为默认字体 |
| `LUAT_USE_PINYIN` | 拼音词库。`LV_IME_PINYIN_USE_DEFAULT_DICT` 为 0，不打开此宏就没有默认词库 |

`src/**/*.c` 与 `binding/*.c` 由 `bsp/pc/xmake.lua` 通配编入。新文件放进这两个目录即可，不必改构建脚本。`lvgl9/src/drivers/` 以及 DMA2D、SDL 等绘制后端已被构建排除。

---

## 开发步骤

### 新增一个控件

1. 在 `inc/luat_airui_component.h` 增加 `AIRUI_<NAME>_MT` 和 `AIRUI_COMPONENT_<NAME>`。
2. 在 `src/components/widgets/luat_airui_<name>.c` 实现 `airui_<name>_create_from_config()`：用 marshal 读表，创建 LVGL 对象，`airui_component_meta_alloc()` 挂元数据，回调用 `airui_component_capture_callback()` + `airui_component_bind_event()`。
3. 在 `binding/luat_lib_airui_<name>.c` 写构造函数和 `airui_register_<name>_meta()`，构造结果用 `airui_push_component_userdata()` 压栈。文件头保留 `@module` / `@api` 注释，供脚本文档提取。
4. 在 `binding/luat_lib_airui.c` 声明这两个符号，并往 `reg_airui[]` 加入 `{"<name>", ROREG_FUNC(...)}`。需要板级开关时，用与 `camera` 相同的 `#ifdef` 包住注册项。
5. 用下方 GUI 构建验证。PC 脚本可参考 `bsp/pc/test/` 里已有的 AirUI 用例。

### 改显示或输入

- 换缓冲、旋转、刷新周期：改 `src/core/`，不要改到某个控件文件里。
- 真机多一种面板或接口：改 `components/display/` 或 `lcd`，AirUI 侧只扩展 `airui_luatos_fb_backend_t`。探测顺序仍是 display 优先、lcd 兜底。
- 键盘焦点、预编辑、自动收起：改 coordinator / session，不在 textarea 和 keyboard 两边各写一套。

---

## 构建与验证

AirUI、LVGL、SDL 显示路径以及任何 `LUAT_USE_GUI` 代码，都走 GUI 构建。通用规则见根目录 `AGENTS.md` 的 Build & Test Commands：不要直接跑 `xmake -y`。

Windows 上在 `bsp/pc` 执行：

```powershell
cmd /c build_windows_32bit_msvc_gui.bat
```

64 位用 `build_windows_64bit_msvc_gui.bat`。脚本输出出现 `Build completed successfully` 才算验证完成。非 GUI 的 `build_windows_*_msvc.bat` 不包含本库。

---

## 反模式

- 不要改 `lvgl9/`，除非任务明确要求改 LVGL 本身
- 不要把 SDL 或 LuatOS 的分支写进 `src/components/widgets/`
- 不要在控件里直接调用 `lcd` / `display` 的刷屏接口，显示输出只走 `airui_display_ops_t`
- 不要绕过 `airui_input_coordinator_*` 去显示或隐藏键盘
- 不要在单个控件文件里复制 marshal / 事件绑定
- 不要静默删掉现有 Lua 字段或方法；要留兼容路径或先打废弃警告
- 不要用非 GUI 构建宣称 AirUI 改动已验证
- 不要假定真机图片缓存大于 1MB，大图界面优先用 `airui.shape` 或自行确认 `LUAT_USE_AIRUI_IMAGE_CACHE_SIZE`

---

## 相关文档

- 根目录构建与编码约定：`AGENTS.md`（Build & Test Commands、Coding Conventions）
- PC 模拟器构建：`bsp/pc/AGENTS.md`
- 显示抽象层（Panel / Interface / FrameBuffer）：`components/display/AGENTS.md`
- 类型与平台 ops：`inc/luat_airui.h`
- 平台参数与可选宏：`inc/luat_airui_conf.h`
