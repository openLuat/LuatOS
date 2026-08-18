# WS2812 多模块 Demo

> **适用产品范围**：本 demo 仅适用于合宙 **Air1780P / Air1780H**。

> 面向 **AI 代理 / 开发者** 的自包含文档。本文档描述模块化 WS2812 demo 的目的、结构、API、扩展方式与故障排除。
> 维护约定：新增/修改 `_task.lua` 后请同步更新「效果模块」与「项目结构」两节。

---

## 目录

1. [项目概述](#1-项目概述)
2. [技术栈](#2-技术栈)
3. [硬件信息](#3-硬件信息)
4. [环境配置](#4-环境配置)
5. [项目结构解析](#5-项目结构解析)
6. [快速开始](#6-快速开始)
7. [效果模块详解](#7-效果模块详解)
8. [公共 API（ws2812_config.lua）](#8-公共-apiws2812_configlua)
9. [字模与文本条带（ws2812_fonts.lua）](#9-字模与文本条带ws2812_fontslua)
10. [运行时配置与串口命令](#10-运行时配置与串口命令)
11. [编写自定义效果](#11-编写自定义效果)
12. [故障排除](#12-故障排除)
13. [FAQ](#13-faq)
14. [官方支持渠道](#14-官方支持渠道)

---

## 1. 项目概述

在合宙 **Air1780P / Air1780H** 上驱动一块 **22×22 = 484 颗 WS2812 RGB 灯珠**的全彩灯板，实现稳定、清晰的滚动文字显示和多种灯光动效。

灯光效果拆成**独立、可插拔的任务模块**，每个文件对应一个可独立运行的小 demo，`main.lua` 只负责 `require` 调度，方便学习、复用与扩展。

### 1.1 主要功能

- 六个开箱即用的灯光效果（默认启用色块覆盖/灯珠检测，其他按需取消注释）：

| 模块 | 效果 | 速度系数 |
|------|------|---------:|
| `ws2812_blocks_task` | 色块覆盖 + 红/绿/蓝/白纯色停留，用于 LED 灯珠坏点检测 | 1× |
| `ws2812_rainbow_task` | HSV 彩虹渐变，颜色在矩阵上流动 | 1× |
| `ws2812_snake_task` | 带 6 像素拖尾的光点按蛇形走线 S 形跑动 | 2× |
| `ws2812_sparkle_task` | 每帧随机 30 颗彩灯，星空闪烁 | 2× |
| `ws2812_rect_task` | 从中心向外扩散、再向内收缩的彩色方框 | 3× |
| `ws2812_scroll_task` | 横向滚动 **"欢迎使用LuatOS"**（中文 22×22 + 英文 22×11 半宽） | 1× |

- 公共硬件初始化、蛇形坐标映射、HSV 颜色工具集中在 `ws2812_config.lua`；
- 字模和 UTF-8 条带构建集中在 `ws2812_fonts.lua`；
- 支持 UART 串口命令实时调节亮度和速度（`b=NNN` / `s=NNN`），无需重新烧录；
- 内置开机复位清零，消除第一颗 LED 上电鬼影。

### 1.2 与根目录 main.lua 的关系

| 对比项 | 根目录 `main.lua` | `ws2812_demo/` |
|--------|-------------------|----------------|
| 定位 | 正式产品程序（色块 2 圈 + 滚动文字） | 学习/扩展用的模块化 demo 集合 |
| 组织 | 单文件全部逻辑 | 多文件按职责拆分 |
| 效果 | 固定两阶段 | 6 种效果可任意组合（色块覆盖 + 5 种循环效果） |
| 字模 | 内置 | 抽到 `ws2812_fonts.lua` |
| 风格 | 应用代码 | 模块化（`@module` 注释、`sys.taskInit`、`require` 调度） |

> Luatools 同一时刻只能把一个 `main.lua` 设为 MAIN。两者不互相依赖，可独立烧录。

---

## 2. 技术栈

| 层级 | 技术 |
|------|------|
| 脚本语言 | Lua 5.3（支持位运算符 `<< >> & \|`） |
| 框架 | LuatOS（Air1780P / Air1780H） |
| LED 协议 | WS2812 单总线归零码（通过 LuatOS `ws2812` 固件组件驱动） |
| 依赖（固件内置） | `sys`、`log`、`ws2812`、`uart`、`math`、`string`、`table`、`os` |
| 外部依赖 | 无 |
| 编码 | UTF-8（中文 3 字节解析） |
| 烧录工具 | Luatools 3.x |

---

## 3. 硬件信息

> **适用产品范围**：本 demo 仅适用于合宙 **Air1780P / Air1780H**。

| 项 | 值 |
|---|---|
| 主控 | 合宙 Air1780P / Air1780H |
| 灯板 | 22 × 22 = **484 颗** WS2812 |
| 数据引脚 | **GPIO16（PIN97）**，`ws2812.GPIO` 模式 |
| 通信 | USB 虚拟串口，命令 115200bps |

**蛇形走线**（本项目物理实际）：

```
y=0  偶行:  LED 0  →  1  → ... → 21   左→右
y=1  奇行:  LED 43 → 42  → ... → 22   右→左
y=2  偶行:  LED 44 → 45  → ... → 65   左→右
...
```

模块通过 [ws2812_xy()](#8-公共-apiws2812_configlua) 把逻辑坐标 `(x,y)` 自动映射成正确的物理 LED 编号，业务代码不用关心蛇形。

**供电**：WS2812 单颗全白约 60mA，484 颗峰值约 25–30A。彩色实际 2–6A，建议外接 **5V/10A 以上** 电源并共地；USB 只用于低亮度调试（`brightness ≤ 50`）。

---

## 4. 环境配置

### 4.1 开发环境

1. 安装 [Luatools 3.x](https://docs.openluat.com/)；
2. 下载 Air1780P 对应 LuatOS SoC 固件（`.soc`，**必须含 `ws2812` 组件**，固件定义可在 [docs.openluat.com](https://docs.openluat.com/) 查询）；
3. Type-C USB 连接开发板；
4. Luatools 新建项目，选择固件。

### 4.2 生产环境

脚本随固件烧录到片上 Flash（脚本分区约 384KB），上电自动执行 `main.lua`，独立运行无需额外运行时。灯板需外接 5V 电源并与模组共地（详见第 3 节供电）。

### 4.3 串口与调试

- USB 虚拟串口同时承载日志输出与命令输入；
- 命令通道波特率 **115200**，在 `main.lua` 通过 `uart.setup(1, 115200)` 初始化；
- 支持 `b=NNN`（亮度）、`s=NNN`（速度）等实时命令，详见第 10 节；
- 若只看日志不发命令，无需额外接线。

### 4.4 导入 demo 文件

把 `ws2812_demo/` 目录下所有 `.lua` 文件加入 Luatools 项目的脚本资源：

```
ws2812_demo/
├── main.lua                 ← 勾选为 MAIN 主脚本
├── ws2812_config.lua
├── ws2812_fonts.lua
└── ws2812_*_task.lua        ← 全部加入脚本资源（是否启用由 main.lua 控制）
```

> 即使 `main.lua` 里某行 `require` 被注释，建议也把对应 `_task.lua` 一起烧录，方便随时取消注释切换效果，只需下次下载脚本即可（1–2 秒）。

---

## 5. 项目结构解析

```
ws2812_demo/
├── main.lua                     # 入口：require 调度 + 串口命令
├── ws2812_config.lua            # 硬件、坐标、HSV 工具、WS2812 句柄、全局 API
├── ws2812_fonts.lua             # 字模表 + UTF-8 条带构建（滚动任务依赖）
├── ws2812_blocks_task.lua       # 色块覆盖 + LED 灯珠检测（红绿蓝白纯色循环）
├── ws2812_rainbow_task.lua      # 彩虹渐变
├── ws2812_snake_task.lua        # 蛇形扫描
├── ws2812_sparkle_task.lua      # 星点闪烁
├── ws2812_rect_task.lua         # 矩形收缩扩散
├── ws2812_scroll_task.lua       # 滚动"欢迎使用LuatOS"
└── readme.md                    # 本文档
```

**加载顺序**：

```
main.lua
  ├─ require "ws2812_config"     ① 最先：初始化 WS2812_LEDS、全局工具
  ├─ require "ws2812_*_task"     ② 各效果任务内部再 require config / fonts
  └─ sys.run()                   ③ 启动 LuatOS 调度器
```

每个 `_task.lua` 自己调用 `sys.taskInit(fn)`，LuatOS 调度器会让它们**并发协作**（协作式多任务，`sys.wait()` 让出 CPU）。

---

## 6. 快速开始

### 6.1 启用/切换效果

编辑 [main.lua](file:///c:/Users/Administrator/Desktop/1780P跑马灯/ws2812_demo/main.lua)：

```lua
require "ws2812_config"          -- 必须最先加载

-- 取消/添加注释来启停各效果（默认只启用 LED 检测，避免多个任务抢帧缓冲）：
require "ws2812_blocks_task"     -- LED 灯珠检测（逐颗覆盖 + 红绿蓝白纯色循环）
-- require "ws2812_rainbow_task"
-- require "ws2812_snake_task"
-- require "ws2812_sparkle_task"
-- require "ws2812_rect_task"
-- require "ws2812_scroll_task"  -- 若要滚动文字，需把 ws2812_blocks_task.lua 里 DETECT_LOOP 改为 false
```

保存后在 Luatools 里只下载脚本即可，无需重烧固件。

### 6.2 多效果并行

多个 `require` 同时打开时，每个任务都是独立协程，会交替刷新同一帧缓冲。

> ⚠️ 两个任务同时调用 `ws2812_clear()` + `ws2812.send()` 会互相覆盖，出现闪烁。并行仅适合**分工明确**的任务（如一个负责背景、一个负责前景），或接受快速闪烁的测试场景。日常使用建议**一次只启用一个效果**。

### 6.3 调亮度/速度

- 改默认：编辑 [ws2812_config.lua](file:///c:/Users/Administrator/Desktop/1780P跑马灯/ws2812_demo/ws2812_config.lua#L25-L28)：
  ```lua
  WS2812_CFG = {
      brightness = 50,
      speed_ms   = 50,
  }
  ```
- 运行时：用串口助手发送 `b=80` 调亮度、`s=30` 调速度（详见 [第 10 节](#10-运行时配置与串口命令)）。

---

## 7. 效果模块详解

### 7.1 `ws2812_blocks_task`（色块覆盖 / LED 灯珠检测）

用于客户验灯，方便逐色检查每颗 WS2812 是否存在坏点、虚焊、颜色通道缺失。默认 `DETECT_LOOP = true` 无限循环：

1. **逐颗覆盖**：按物理蛇形顺序从 0 → 483 逐颗点亮随机颜色，验证走线顺序和焊接；
2. **全红停留 2 秒**：检查红色通道；
3. **全绿停留 2 秒**：检查绿色通道；
4. **全蓝停留 2 秒**：检查蓝色通道；
5. **全白停留 2 秒**：检查三通道同时点亮（最耗电，注意供电）；
6. 清屏 1 秒后回到步骤 1。

**关键参数**（文件顶部可改）：

| 参数 | 默认 | 含义 |
|------|----:|------|
| `DETECT_LOOP` | `true` | `true`=无限循环检测模式；`false`=开机过渡模式（跑 `BLOCK_ROUNDS` 圈后退出） |
| `BLOCK_ROUNDS` | `2` | 非循环模式下的覆盖圈数 |
| `FILL_STEP_MS` | `10` | 逐颗覆盖时每颗的间隔 ms |
| `HOLD_MS` | `300` | 每轮覆盖填满后的停顿 ms |
| `DETECT_HOLD_MS` | `2000` | 红/绿/蓝/白每色停留时间 ms |
| `GAP_MS` | `1000` | 一轮结束后清屏停留 ms |

**坏点判断方法**：
- 某位置在所有纯色下都不亮 → LED 损坏或虚焊；
- 只在某一通道不亮（例如全红时缺一颗）→ 该通道 LED 芯片损坏；
- 颜色顺序错乱或前一颗影响后一颗 → DIN 走线/焊接问题；
- 白色时整板变暗/闪烁 → 电源电流不足，降低 `brightness`。

> ⚠️ 全白模式 484 颗同时点亮电流最大（亮度 255 时约 25–30A），默认亮度 50 时约 5–6A，USB 供电无法支撑，必须外接 5V 电源并共地。

### 7.2 `ws2812_rainbow_task`（彩虹渐变）

- 每帧遍历 22×22 所有 LED；
- 色相 `h = ((x+y)*360/44 + frame*3) % 360`，斜向彩虹随帧向右上流动；
- 一轮 120 帧后循环。

**关键参数**（文件顶部可改）：`steps = 120`、色相步进 `frame*3`。

### 7.3 `ws2812_snake_task`（蛇形扫描）

- 光点按 **物理 LED 编号** 0→483 跑动，拖尾 6 颗线性渐暗；
- 因为灯板蛇形走线，视觉上光点"S 形"逐行扫描，是验证蛇形映射最直观的效果；
- 颜色随位置色相变化。

**关键参数**：`trail = 6`（拖尾长度），间隔 `speed_ms * 2`。

### 7.4 `ws2812_sparkle_task`（星点闪烁）

- 每帧随机点亮 30 颗 LED，每颗随机色相；
- 每 100 帧后重新一轮。

**关键参数**：每轮帧数 `100`、每帧点数 `30`。

### 7.5 `ws2812_rect_task`（矩形收缩扩散）

- 从中心点 `(11,11)` 开始画矩形框，半径从 0 扩到 11 再收回；
- 颜色 `h = rr*20 % 360` 随半径变化；
- 越界由 `ws2812_set()` 自动忽略。

**关键参数**：间隔 `speed_ms * 3`（呼吸感更明显）。

### 7.6 `ws2812_scroll_task`（滚动文字）

- 文本默认 `"欢迎使用LuatOS"`（UTF-8）；
- 中文字模 22×22（`FONT_CN`），英文半宽 22×11（`FONT_EN22`），未收录的 ASCII 回退到 5×7 放大字模；
- 英文字模渲染时 `voffset=2` 下移 2 排与中文视觉对齐；
- 文字从右侧（offset = -22）滑入、向左滑出（offset = strip_w-1），无空白帧循环；
- 每轮通过 6 色区 LCG 选一个新颜色。

**改文本**：修改 [ws2812_scroll_task.lua#L26](file:///c:/Users/Administrator/Desktop/1780P跑马灯/ws2812_demo/ws2812_scroll_task.lua#L26) `local SCROLL_TEXT = "欢迎使用LuatOS"`。若含未收录汉字，需要在 `ws2812_fonts.lua` 的 `FONT_CN` 里补字模。

---

## 8. 公共 API（ws2812_config.lua）

`require "ws2812_config"` 后以下符号全局可用。

### 8.1 常量

| 名称 | 类型 | 值 | 说明 |
|------|------|----|------|
| `LED_W` | number | 22 | 灯板列数 |
| `LED_H` | number | 22 | 灯板行数 |
| `LED_COUNT` | number | 484 | LED 总数 |
| `LED_GPIO` | number | 16 | DIN 引脚编号（PIN97） |
| `WS2812_LEDS` | userdata | — | ws2812 句柄，失败为 `nil` |
| `WS2812_CFG` | table | `{brightness=50, speed_ms=50}` | 运行时配置，各任务读取 |

### 8.2 函数

#### `ws2812_xy(x, y) -> index`

蛇形逻辑坐标 → 物理 LED 索引（0-based）。
- `x, y` 范围：`0..LED_W-1`、`0..LED_H-1`；
- 奇数行自动水平翻转以匹配蛇形走线。

```lua
local idx = ws2812_xy(0, 1)   -- 第 1 行第 0 列 → 物理 43（右→左）
```

#### `ws2812_hsv2rgb(h, s, v) -> color`

HSV 转 24-bit RGB 整数。
- `h` 色相 0–359；`s` 饱和度 0–255；`v` 明度 0–255；
- 返回值可直接传给 `ws2812.set` / `ws2812_set`。

```lua
local red = ws2812_hsv2rgb(0, 255, 100)
```

#### `ws2812_rgb(r, g, b) -> color`

RGB 打包为 24-bit 整数。

```lua
local white = ws2812_rgb(80, 80, 80)
```

#### `ws2812_set(x, y, color)`

按**逻辑坐标**点亮一颗 LED。越界自动忽略，句柄未就绪时静默丢弃，不会抛错。内部先 `ws2812_xy` 映射再写缓冲。

```lua
ws2812_set(11, 11, ws2812_rgb(255, 0, 0))  -- 中心点红灯
ws2812_send()                                -- 记得发送
```

#### `ws2812_fill(color)`

整片填充同一颜色并立即 `send`。句柄未就绪时静默返回。

```lua
ws2812_fill(ws2812_rgb(0, 0, 60))  -- 整片暗蓝
```

#### `ws2812_clear()`

把整片缓冲写 0。**不发送**，调用后需要 `ws2812_send()` 才会真正熄灭。

```lua
ws2812_clear()
ws2812_send()
```

#### `ws2812_send()`

发送当前缓冲到灯板。所有 `ws2812_set/clear` 都是写缓冲，必须调用此函数才会刷新 LED。句柄未就绪（`ws2812.create` 失败）时静默返回，不会对 nil 调用 C 函数导致崩溃。

```lua
ws2812_send()
```

### 8.3 底层 ws2812 固件 API

公共函数未覆盖的高级用法可直接调用固件 API：

```lua
ws2812.create(ws2812.GPIO, LED_COUNT, LED_GPIO)
ws2812.args(WS2812_LEDS, 20, 30, 35, 20, 0)   -- 本项目实测时序，勿改
ws2812.set(WS2812_LEDS, physical_index, color)
ws2812.send(WS2812_LEDS)
```

> 时序 `(20,30,35,20,0)` 单位 ns，经实测稳定，乱改可能导致颜色错乱或不亮。

---

## 9. 字模与文本条带（ws2812_fonts.lua）

`ws2812_scroll_task` 依赖此模块，其他效果不需要。

### 9.1 字模表

| 表 | 尺寸 | 内容 |
|----|------|------|
| `FONT_CN` | 22 行 × 22 列 | 中文 欢/迎/使/用 |
| `FONT_EN22` | 22 行 × 11 列 | 英文 L/u/a/t/O/S（Consolas 半宽） |
| `FONT5x7` | 5 字节/字 | A–Z 大写、部分小写，作为 ASCII 回退 |

字符串点阵格式：等长字符串，`#` = 亮，`.` = 灭。

### 9.2 列掩码函数

```lua
ws2812_col_mask(glyph, col, voffset) -> integer
```

把某字形的某一列打包成 22-bit 整数（bit n 表示第 n 行是否亮）。`voffset` 用于垂直偏移（英文字模传 2 下移 2 排）。

### 9.3 条带构建

```lua
local columns = ws2812_build_strip("欢迎使用LuatOS")
-- columns 是数组，每项是一列的 22-bit 掩码
-- 字间距自动加 2 列空白
```

内部 UTF-8 解析使用 `while` 循环（中文 3 字节、ASCII 1 字节）。⚠️ 切勿改成数值 `for` + 体内 `i=i+3`，Lua for 循环变量不接受体内修改，会导致中文乱码。

### 9.4 渲染一帧示例

```lua
for y = 0, 21 do
    local bit = 1 << y
    for x = 0, 21 do
        local col_idx = x + offset + 1
        if col_idx >= 1 and col_idx <= #columns then
            if (columns[col_idx] & bit) ~= 0 then
                ws2812_set(x, y, color)
            end
        end
    end
end
ws2812_send()
```

---

## 10. 运行时配置与串口命令

### 10.1 配置表

所有任务每帧直接读 `WS2812_CFG`，运行时修改立即生效（下一帧）。

```lua
WS2812_CFG.brightness = 80   -- 0–255
WS2812_CFG.speed_ms   = 60   -- 20–2000 ms
```

### 10.2 串口命令

`main.lua` 在 UART1（USB 虚拟串口，115200）注册了命令解析。用任意串口助手（Luatools 自带、SSCOM、minicom 等）发送：

| 命令 | 作用 | 范围 |
|------|------|------|
| `b=80\r\n` | 设置亮度 | 0–255 |
| `s=60\r\n` | 设置帧间隔 | 20–2000 ms（越小越快） |
| `b?\r\n` | 查询当前亮度 | — |
| `s?\r\n` | 查询当前速度 | — |

**交互示例**：

```
> b=100
< [cmd] brightness = 100
> s=30
< [cmd] speed_ms = 30
> b?
< [cmd] brightness = 100
```

**实现要点**：
- 命令以 `\r` 或 `\n` 结尾，支持 `\r\n`；
- 非法参数自动钳制范围，不会崩溃；
- 命令在独立 `sys.task` 里处理，不阻塞 UART 接收回调。

### 10.3 速度系数

各任务内部对 `speed_ms` 的使用并不统一，以实现不同的"节奏感"：

| 任务 | 实际帧间隔 |
|------|-----------|
| rainbow / scroll | `speed_ms` × 1 |
| snake / sparkle | `speed_ms` × 2 |
| rect | `speed_ms` × 3 |

---

## 11. 编写自定义效果

### 11.1 模板

在 `ws2812_demo/` 新建 `ws2812_myeffect_task.lua`：

```lua
--[[
@module  ws2812_myeffect_task
@summary 我的自定义 WS2812 效果
@version 1.0
@date    2026.08.17
@usage
核心业务逻辑：每帧画一个对角线上移动的红点
]]

require "ws2812_config"

local function myeffect_task()
    if not WS2812_LEDS then return end
    sys.wait(100)  -- 必须等开机复位清零完成

    local pos = 0
    while 1 do
        ws2812_clear()
        local color = ws2812_hsv2rgb(0, 255, WS2812_CFG.brightness)
        ws2812_set(pos, pos, color)         -- 对角线上移动
        ws2812_set(LED_W - 1 - pos, pos, color)
        ws2812_send()
        pos = (pos + 1) % LED_W
        sys.wait(WS2812_CFG.speed_ms)
    end
end

sys.taskInit(myeffect_task)
```

### 11.2 在 main.lua 注册

```lua
require "ws2812_myeffect_task"
```

### 11.3 注意事项

1. **开头 `sys.wait(100)`**：等 config 里 50ms 开机复位发送完成，避免第一帧竞争。
2. **每帧 clear → set → send**：WS2812 没有自动清屏，遗漏 `clear()` 会让上一帧残留。
3. **用逻辑坐标 `ws2812_set(x,y,color)`**，不要直接 `ws2812.set(LEDS, idx, color)` 除非你明确要操作物理索引（如 snake 任务）。
4. **不要在回调里跑循环**：长逻辑放在 `sys.taskInit` 协程里，UART/GPIO 回调只做标志设置。
5. **避免忙等**：用 `sys.wait(ms)` 让出 CPU，禁止 `while true do end` 无等待。

---

## 12. 故障排除

| 现象 | 可能原因 | 解决 |
|------|---------|------|
| 启动报 `bad argument #2 to 'timer_start' (number expected, got nil)` | 任务里 `sys.wait(WS2812_CFG.speed_ms)` 取到 nil | 确认 `require "ws2812_config"` 在任务文件顶部；config 中字段名是 `speed_ms` 不是 `scroll_ms` |
| 开机只有左上角 1 颗微亮 | DIN 上电杂波被锁存（鬼影） | config 已内置 50ms 复位；若仍存在，检查 330Ω 串联电阻、电源稳定性 |
| 完全不亮 | GPIO/电源/接线错误 | DIN 接 GPIO16/PIN97；VCC 5V；GND 共地；勿改 `ws2812.args` |
| 竖线呈之字形 | 蛇形映射未生效 | 不要直接使用物理索引；用 `ws2812_set(x,y,...)`；若走线方向相反，在 config 中翻转奇数行判定 |
| 颜色错乱、绿色闪烁 | 电源电流不足 | 外接 5V/10A+；降低 `brightness`；检查共地 |
| 滚动中文乱码 / 字后多空白列 | UTF-8 用了数值 for | 必须用 `while` 循环（见 9.3） |
| 串口命令无反应 | 串口号/波特率/换行 | 用 Luatools 日志所在虚拟串口；115200；命令末尾回车 `\r\n` |
| 两个效果同时启用时严重闪烁 | 两任务都 clear+send 抢缓冲 | 同一时刻只启用一个效果，或合并到一个任务 |
| 日志报 "ws2812.create 失败" | 固件不含 ws2812 组件 | 换用含 ws2812 的 Air1780P LuatOS SoC 固件（固件定义可在 [docs.openluat.com](https://docs.openluat.com/) 查询） |
| 改了脚本但灯效没变 | Luatools MAIN 指向了另一个 main.lua | 确认 `ws2812_demo/main.lua` 被勾选为 MAIN 主脚本 |

---

## 13. FAQ

**Q0：本 demo 支持哪些合宙模组？**
A：本 demo **仅适用于合宙 Air1780P / Air1780H**。

**Q1：为什么拆成这么多文件？**
A：每个 `xxx_task.lua` 是一个独立可参考的最小示例，方便学习和复制；公共部分抽到 config/fonts，避免重复。

**Q2：能同时跑彩虹 + 滚动文字吗？**
A：技术上可以（都 `require` 即可），但两个任务都在 `clear + send`，会互相覆盖导致闪烁。推荐一次只开一个；如果确实要叠加，需要修改其中一个任务不要 clear、只写自己负责的像素。

**Q3：怎么改灯板尺寸（比如改成 16×16）？**
A：改 `ws2812_config.lua` 里 `LED_W/LED_H/LED_COUNT/LED_GPIO`，蛇形映射 `ws2812_xy` 自动适配；字模是 22 宽，换尺寸后滚动文字可能需要换字模或调整坐标裁剪。

**Q4：怎么加新的中文字模？**
A：在 `ws2812_fonts.lua` 的 `FONT_CN` 里加 `["新字"] = { "....", ... }`，必须 22 行、每行 22 字符。字模可由点阵字模工具生成后解码为 `#`/`.`。

**Q5：亮度设多少合适？**
A：USB 供电建议 ≤ 50；外接 5V/10A 电源可设 80–150；长时间运行不建议长期 255（电流大、发热明显）。

**Q6：为什么英文下移 2 排？**
A：中文字模基本占满 22 行，英文 22×11 字模上下留白较多，整体视觉偏上；下移 2 排后中英文视觉重心对齐。

**Q7：`speed_ms` 设多小会死机？**
A：代码里串口命令钳制最小 20ms。低于 20ms 可能 WS2812 发送（484 颗约 15ms）占满 CPU 影响系统响应；建议 ≥ 30ms。

---

## 14. 官方支持渠道

- 文档中心：https://docs.openluat.com/
- 开源代码：https://gitee.com/openLuat/LuatOS/tree/master/module
- 官方企业微信群：https://docs.openluat.com/ 网站底部二维码，扫码加入
- 官方淘宝店：https://luat.taobao.com/ （选购核心板、开发板，对比验证）
