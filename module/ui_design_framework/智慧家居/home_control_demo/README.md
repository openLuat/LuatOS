# home_control_demo · 全屋智能中控 Demo

基于 LuatOS + AirUI（LVGL 9）的全屋智能中控演示工程，内置 5 个可轮询切换的界面方案，
覆盖玻璃拟态、环形中枢、Bento 磁贴、底部 Dock 与息屏时钟五种风格。

---

## 一、硬件环境

| 项目 | 说明 |
| --- | --- |
| 主控模组 | **Air8607**（核心 SoC：Air1603） |
| 固件 | **LuatOS-SoC_V1030_Air1603_102.soc** |
| 屏幕 | 官方 AirLCD_1100，10.1 寸 RGB，1024×600 |
| 屏幕驱动 IC | JD9165BA |
| 触摸 | GT911 电容触摸（I2C1，RST=14，INT=51） |
| 背光 | PWM3 |
| UI 框架 | AirUI（LVGL 9）+ hzfont 中文矢量字库 |

说明：

- 固件名中 `V1030` 为 LuatOS 版本，`Air1603` 为 SoC 系列，`102` 为变体编号
  （脚本区 4096KB / 文件系统 1536KB，适合本项目这种多文件结构）。
- 屏幕 / 触摸 / 背光初始化集中在 `hardware.lua`；更换板型改顶部 `M.profile`：
  - `"air8607_10i"`（默认，Air8607 + 10.1 寸 JD9165BA）
  - `"air8601_7i"`（Air8601 + 7 寸 HX8282，需 `lcd_hx8282_10in.lua`）

---

## 二、功能特性

### 5 个界面方案（`ui_page` 统一管理，默认 5 秒轮询）

| 页面 | 模块 | 说明 |
| --- | --- | --- |
| 息屏·待机 | `page_clock.lua` | AOD 时钟：霓虹光晕环 + 轨道光点 + 大时间，每秒刷新 |
| 方案D·玻璃拟态 | `page_glass.lua` | 暗色玻璃：顶栏 + 气候 / 设备 / 安防三栏 + 场景 Dock |
| 方案A·环形中枢 | `page_ring.lua` | 灯光 / 空调大环 + 安防 + 场景，支持深/浅主题切换 |
| 方案B·Bento 磁贴 | `page_bento.lua` | 12×6 磁贴网格，支持深/浅主题切换 |
| 方案C·底部 Dock | `page_dock.lua` | 房间 Tab + 三栏 + 场景 Dock，支持深/浅主题切换 |

### 交互与联动

- **场景联动**：点底部场景（回家 / 离家 / 睡眠 / 观影 / 起床 / 会客）→ 同步安防开关 + 当前房间设备磁贴。
- **亮暗主题**：方案 A / B / C 顶栏可切换深色 / 浅色（顶层容器销毁重建，避免逐控件重涂）。
- **即时反馈**：默认 `motion.instant = true`，交互状态一帧到位，无动画排队拖尾。
- **温湿度模拟**：每 5 秒 ±0.2℃ / ±1% 小幅漂移，模拟真实传感器。

### 视觉能力

- 玻璃拟态：半透明卡片 + 柔光背景 + 高光描边 + 双层假投影
  （LVGL 9 无 backdrop blur 时的降级方案）。
- 原生图形：`airui.shape` 画湿度点阵 / 分隔虚线，`airui.chart` 画 24h 温度趋势。

---

## 三、目录结构

```
home_control_demo/
├── main.lua               入口：缩放 → 硬件 → 注册五页 → ui_page.build → 5 秒轮询
├── hardware.lua           Air8607 上电 / JD9165BA / AirUI+hzfont / GT911 / PWM3 背光
├── exd_jd9165ba_rgb.lua   官方 JD9165BA RGB 显示扩展库
├── tp_gt911.lua           GT911 触摸绑定（I2C1 / RST=14 / INT=51）
├── lcd_hx8282_10in.lua    Air8601 7 寸备用板级（8607 不加载，保留硬件层完整性）
├── app_state.lua          四房数据（客厅/主卧/书房/厨房）+ 温湿度 5 秒漂移模拟
├── ui_theme.lua           玻璃色板、透明度、圆角、字号、微动参数
├── ui_widget.lua          玻璃组件 + 软补间引擎 + 按下反馈层（含旧固件回退）
├── ui_page.lua            多页面管理器：register / build / show / next / start_rotation
├── page_clock.lua         息屏·待机时钟（AOD）
├── page_glass.lua         方案D·玻璃拟态（含场景联动、安防文字居中）
├── page_ring.lua          方案A·环形中枢（深/浅主题）
├── page_bento.lua         方案B·Bento 磁贴（深/浅主题）
├── page_dock.lua          方案C·底部 Dock（深/浅主题）
├── design/                方案 A/B/C/D HTML 原型副本 + 息屏时钟 AI 参考图
├── index.html             页面方案索引（浏览器预览）
├── 整机演示.html           与真机一致的暗色玻璃浏览器预览
├── AGENTS.md              AirUI 应用层开发硬约束（13 条 + 禁用清单 + 烧录自检）
└── README.md
```

LuatOS 平铺加载：`require` 只写文件名，工程内文件名唯一（已核对）。

---

## 四、快速开始

1. 用 **Luatools** 打开本目录（`E:\Luatools\LuatOS-master\home_control_demo`）。
2. 设备选择 `Air8607`，固件选择 `LuatOS-SoC_V1030_Air1603_102.soc`。
3. 点击「下载脚本」烧录到板子，复位运行。
4. 首次上电显示「息屏·待机时钟」，5 秒后自动轮询到方案D、A、B、C。

> 也可在运行期手动切页：`ui_page.show("glass")`、`ui_page.next()`、
> `ui_page.start_rotation(ms)`、`ui_page.set_interval(ms)`。

---

## 五、启动流程

1. `hardware.init_density_scale()` — 以 1024×600 为基准（必须在界面模块加载前）。
2. `hardware.init()` — 上电 → JD9165BA RGB 时序 → `airui.init` + hzfont → GT911 → 背光。
3. `sys.wait(150)` — 等首帧。
4. `P.register(...)` × 5 — 注册 clock / glass / ring / bento / dock 五页（只 require 不构建）。
5. `P.build()` — 五页各建一个整页根容器并 `mod.create(root)`，除首页外全部推入屏外。
6. `P.show("clock")` + `P.start_rotation(5000)` — 先显示息屏时钟，之后每 5 秒自动切下一页。

看门狗 60s / 3s 喂狗。

---

## 六、页面与交互

| 页面 | 主要交互 |
| --- | --- |
| 息屏时钟 | 时间 / 日期每秒刷新；AOD 光晕环 |
| 方案D·玻璃 | 房间 Tab 切换、设备磁贴开关、`调` 打开调档条（− / +）、空调 ±、安防开关、场景联动 |
| 方案A·环形 | 灯光 / 空调大环、安防、场景、环境条 |
| 方案B·Bento | 12×6 磁贴网格、场景 |
| 方案C·Dock | 房间 Tab、三栏信息、场景 Dock |

### 方案D 场景联动规则

| 场景 | 安防（布防 / 门锁） | 当前房间设备 |
| --- | --- | --- |
| 回家 | 撤防 · 开锁 | 灯全开 · 窗帘全开 |
| 离家 | 布防 · 上锁 | 设备全关 |
| 睡眠 | 布防 · 上锁 | 灯全关 · 窗帘全关 |
| 观影 | 撤防 · 上锁 | 灯全关（只留灯带）· 窗帘关 |
| 起床 | 撤防 · 开锁 | 灯开 · 窗帘开 |
| 会客 | 撤防 · 开锁 | 设备全开 |

联动会刷新：安防开关滑块 / 圆点、顶栏状态芯片、设备磁贴状态与「设备 x/6 开」计数。

---

## 七、定制指南

| 想改什么 | 改哪里 |
| --- | --- |
| 配色 / 玻璃透明度 / 字号 | `ui_theme.lua`（`M.c` 颜色、`M.glass` 透明度、`M.f` 字号） |
| 关闭微动 | `ui_theme.lua` 里 `M.motion.enabled = false` |
| 关闭交互动画 | `ui_theme.lua` 里 `M.motion.instant = false`（退回逐帧补间） |
| 设备 / 房间 / 场景数据 | `app_state.lua`（`M.rooms`、`M.scenes`、`M.security`） |
| 接入真实设备 | 把 `app_state.lua` 的赋值处换成 MQTT / HTTP 下发，UI 层不动 |
| 场景联动规则 | `page_glass.lua` 的 `SCENE_RULES` |
| 换屏幕板型 | `hardware.lua` 顶部 `M.profile` |
| 新增页面 | 新建 `page_xxx.lua`，`main.lua` 里 `P.register(...)` |

---

## 八、开发规范

**基于本项目二次开发，先读 `AGENTS.md`**（应用层 13 条硬约束 + API 禁用清单 + 烧录自检清单）。

核心几条：

- 热区一律用 `W.press_layer`（透明 container + 闭包开关），**不要用 `airui.button` 做热区**。
- 显隐一律用透明度（`set_color(color, 0)` + 清文字 + 关命中），**不要用 `hide()/open()`**。
- 子控件不得探出父容器内容区（1px 就出滚动条），动画也要做边界预算。
- 文字一律走 `W.text` / `W.text_mid`，行高统一兜底。
- 定时器延迟 ≥ 5ms（`timerStart(fn, 0)` 会静默失败）。

---

## 九、常见问题

### 点了没反应

- 「调」点不开：曾因 `airui.button` 有 `hide()` 没 `open()`，改透明 container 热区解决。
- 整片区域点不动：上层有 alpha=0 的容器仍吃触摸，显隐时要同时关命中。

### 屏幕多出一条线

| 线在哪 | 根因 | 修法 |
| --- | --- | --- |
| 控件四周一圈 | 容器描边 `border_color` | 不传 `border_color`，只传 `border_width = 0` |
| 容器底边极细线 | 横向滚动条（内容溢出 1px） | 按内容区缩 2px / label 高度兜底 |
| 图表下方横线 | X 轴线未关 | 图表高度内缩 2~3px 或改 `shape` 自绘 |
| 卡片顶部 2px 亮线 | 反光条 `hl`（设计元素） | `ui_theme.M.glass.hl_opa = 0` |
| 磁贴点完顶部一横 | 磁贴高光条 sweep 补间停在 60 | 已移除磁贴 `hl`（`page_glass.build_tile`） |

### 中文显示 / 字体

- 中文最小字号 16（hzfont）。
- `airui.label` **没有 `font_weight`**，`weight = 700` 是空转，加粗需换 hzfont 粗体字库或加大字号。

### 时间与动画

- `sys.timerStart(fn, 0)` 会静默创建失败（rtos 最小超时 1ms），错开延迟一律 ≥ 5ms。
- 逐帧 Lua 定时器会被其他任务抢占（20~60ms 抖动），默认已改即时反馈。

---

## 十、已知限制

- **真·背景模糊做不到**：LVGL 9 无 backdrop blur，用「柔光底 + 半透明白卡」近似。
- `airui.container` 不支持 `set_size / scale / rotate / 通用 anim`，缩放类动效只能用 1~2px 位移 + 颜色变化近似。
- `airui.chart:set_values` **只吃整数**，小数不显示（用「基准 + 整数偏移」构造曲线）。
- `airui.shape` 没有弧线图元，环形进度需多段 line 拼，成本较高。
- `airui.image` 只支持 jpg/png 本地资源，不支持远程 URL。
- `label` 无 `set_hidden`，需要显隐的内容必须包 container。
- 容器滚动条固定 AUTO 且无关闭接口，只能靠尺寸预算避免。
