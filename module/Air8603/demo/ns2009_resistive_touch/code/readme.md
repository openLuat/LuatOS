# NS2009 电阻触摸整机测试 Demo（ns2009_resistive_touch · 多分辨率兼容）

Air8603M1（模组 Air1603）+ RGB 电阻屏 + NS2009 电阻触摸：点屏、触摸实时测试、四点标定
与标定系数 fskv 持久化，一套工程验证整机显示与触摸。

本工程采用 **配置驱动架构**（参考 `module/Air8603/factory`）：一套代码兼容三种屏幕分辨率，
**换屏/换分辨率只改 `main.lua` 的 `PROJECT` 一行**，其余全部由配置驱动，不删代码、不改布局。

## 支持的分辨率（改 PROJECT 切换）

| PROJECT（`main.lua` 第 1 行） | 配置文件 | 分辨率 | 像素时钟 | 字号 | fskv 键名 |
|---|---|---|---|---|---|
| `NS2009_RESISTIVE_TOUCH_1024_600` | `config/ns2009_1024_600.lua` | 1024×600 | 51 MHz | 16/20 | `ns2009_cal_1024x600` |
| `NS2009_RESISTIVE_TOUCH_800_480`  | `config/ns2009_800_480.lua`  | 800×480  | 33 MHz | 16/20 | `ns2009_cal_800x480` |
| `NS2009_RESISTIVE_TOUCH_480_272`  | `config/ns2009_480_272.lua`  | 480×272  | 15 MHz | 12/16 | `ns2009_cal_480x272` |

> 每个分辨率用独立 `cal_kv` 键名：换屏后其它分辨率的旧标定存档自动失效，
> 上电强制重新四点标定，不会把旧系数错用到新屏上。

## 架构（分层，参考 factory 的配置驱动）

```
main.lua                   唯一入口：改 PROJECT 一行切换屏幕，其余只做装配
core/platform_loader.lua   PROJECT → 配置文件名 → 加载 _G.project_config + 上电/引脚复用
config/ns2009_*.lua        纯数据配置（每分辨率一份）：上电时序 / RGB 时序 / 背光 / 触摸 / 字号
drv_screen.lua             真机 display.init 分配 RGB 帧缓冲 + PWM 背光
drv_touch.lua              核心库 tp 直驱 NS2009（事件桥接 / 四点标定 / fskv 存档）
ui_test.lua                AirUI 界面（按 W/H 自适应布局，字号/十字从 CFG.ui 读）
```

- `platform_loader` 里 `PROJECT_MAP` 把长 PROJECT 名映射到短配置文件名（LuatOS 文件名 ≤24 字节）；
- 动态 `require(cfg_name)` 扫不到 `config/*.lua`，所以在 `platform_loader` 头部的
  `_compile_manifest()` 静态列出三份配置，让编译系统打包；**新增分辨率时在此加一行**；
- 未命中映射会回退到 `800x480` 配置并在日志打 warn，便于定位 PROJECT 填错。

## 功能模块介绍

1、`main.lua`：主程序入口，底板上电 → 点屏（`display.init` 分配 FB）→ `airui.init`/旋转/字体
   → `tp.init` 触摸 + `airui.device_bind_touch` → 建界面 → 起主循环 → 上电标定恢复/强制标定；

2、`core/platform_loader.lua`：PROJECT 映射 + 配置加载 + 上电时序 + 触摸引脚复用；

3、`config/ns2009_*.lua`：纯数据配置源，上电时序 / RGB 时序 / 背光 / 触摸参数 / 主题配色与字号
   全部在这里；**改硬件只改配置文件，其它模块只读 `_G.project_config`，不写死任何引脚号或分辨率**；

4、`drv_screen.lua`：真机 `display.init("rgb")` 分配帧缓冲（AirUI 随后使用）+ PWM3 背光调光；

5、`drv_touch.lua`：核心库 tp（新版 API）直驱 NS2009：事件桥接、四点标定封装、
   标定系数读回 / 回灌 / fskv 存档；

6、`ui_test.lua`：AirUI 测试界面（触摸区 + 网格 + 准星 + 轨迹 + X/Y 数值面板 + 4 按钮 +
   标定页 + 保存/不保存页 + 超时页）。布局按 `W/H` 自适应，字号/十字从 `CFG.ui` 读。

## 演示功能概述

1、触摸实时测试：在网格区滑动，准星跟随（shape 移动）或画线（shape 累积折线，段数封顶），
   右侧面板实时显示 X/Y 坐标、按下状态、已标定状态；

2、模式切换：`准星` / `画线` 两个模式按钮（当前模式带 ● 高亮）；`清空` 清掉轨迹；

3、四点标定：`标定` 按钮 → 干净标定页 + 十字，按 左上 → 右上 → 左下 → 右下 依次点击
   （调核心库 tp.calibration）；

4、标定系数持久化（新版 tp API）：标定完成出"保存 / 不保存"选择页，选"保存"系数经 json
   存入 fskv（键名见上表），下次上电用 `tp.calibration(dev, data)` 回灌恢复，不再重复标定；

5、存档自愈：存档损坏或与固件系数结构不兼容时自动删除并重新标定；

6、手动标定超时（60 秒）：停在"标定超时 + 返回"页，点返回回主界面可再标；

7、首次上电强制标定：无存档时必须完成一次标定才能进主界面——未标定时触摸坐标上下颠倒
   （NS2009 芯片原点在左下、屏幕逻辑原点在左上）。标定不限时、无法退出，直到标成功。

## 演示硬件环境

1、Air8603 开发板（Air8603M1 底板，模组 Air1603）一块；

2、40PIN 电阻触摸显示屏一套（800×480 原屏为 宏显伟业 0700A001 / HX8264；换 1024×600 或
   480×272 屏时其 RGB 时序须按新屏规格书重填），触摸为深圳纳芯微 NS2009（4 线电阻，在屏排线上）；

3、12V DC 电源一个（40PIN 屏的背光升压需要 12V，USB 口带不动整机）；

4、USB 数据线一根（接 Type-C，用于烧录和看日志）。

接线方式（详见上级目录 `测试硬件环境说明.md`）：

- 屏排线接底板 40PIN 座（屏和 NS2009 同一路供电，底板上电时序会逐轨拉高）；
- 触摸走 I2C1：PIN42=SCL / PIN41=SDA，PENIRQ = PIN51（GPIO51），NS2009 地址 0x49（A0 拉高）；
- 12V 电源接 DC 座，Type-C 接电脑烧录。

## 演示软件环境

1、[Luatools 工具](https://docs.openluat.com/common/Luatools/)；

2、内核固件文件（本 demo 需要同时启用下列库的固件）：

   - `airui`（AirUI/LVGL GUI 层）——缺它直接跑不起来；
   - `display`（真机 RGB 帧缓冲，AirUI 依赖它分配的 FB）；
   - `tp`（NS2009 触摸 + 四点标定 + 系数读回/回灌，需新版支持读回/回灌）；
   - `fskv`（标定系数持久化）；
   - `json`（系数序列化）；
   - `pwm`（背光调光）。

   Air8603 factory 固件本身就带 AirUI，可直接用；若用裸 demo 固件，需确认已编译进 `LUAT_USE_AIRUI`。

## 演示核心步骤

### 1、选分辨率

打开 `main.lua`，把 `PROJECT` 改成目标分辨率（见上表）。默认是 `NS2009_RESISTIVE_TOUCH_1024_600`。

### 2、按实际接线检查配置

打开 `config/` 下对应的配置文件，确认触摸段（改硬件只动这个文件）：

```lua
touch = {
    i2c_id  = 1,             -- I2C1：PIN42=SCL / PIN41=SDA
    pin_int = 51,            -- PENIRQ 引脚（★ 按实际接线修改；nil 则启动时报错）
    w       = 1024,          -- 触摸映射目标宽（与屏一致）
    h       = 600,           -- 触摸映射目标高
    save_cal = true,         -- 标定完成后自动存 fskv，上电自动恢复
    cal_kv  = "ns2009_cal_1024x600",  -- fskv 键名（每个分辨率独立存档）
    auto_cal = true,         -- 无有效存档时上电强制四点标定（不限时）
}
```

换 1024×600 / 480×272 屏时，`lcd.hbp/hspw/hfp/vbp/vspw/vfp` 和 `bus_speed` 必须按新屏规格书重填
（当前是通用参考值）。

### 3、烧录并运行

用 Luatools 把 `code/` 目录下的所有 .lua 文件下载到模块（脚本目录选 `code/`），下载完成后自动运行。

### 4、首次上电：强制四点标定

无存档时强制进入标定页（顶部显示"正在校准屏幕触摸"）：保持松手，屏幕依次出现四个十字，
按 左上 → 右上 → 左下 → 右下 顺序点击。此页面不限时、无法退出，直到标完；完成后出
"保存 / 不保存"选择页，选"保存"则存档并进主界面（之后上电免标定）。

### 5、观察日志

首次上电（1024×600，标定并存档）：

```
I/main 供电轨 GPIO12 =1
I/screen display.init(rgb) true nil 1024x600
I/main airui version 1.3.0
I/touch NS2009 就绪（新版 tp API） 1024x600 int=PIN51
I/main airui.device_bind_touch true
I/ui AirUI 界面已构建 1024x600
I/main 无有效标定存档（not_saved），上电强制四点标定（不限时）
I/ui 开始四点标定；按左上、右上、左下、右下顺序点击十字
I/touch POINT 150 150
I/touch POINT 874 150
I/touch POINT 150 450
I/touch POINT 874 450
I/touch DONE true
I/ui 标定完成 true
I/touch 标定系数已存档 ns2009_cal_1024x600 长度 87
```

再次上电（存档恢复，免标定）：

```
I/screen display.init(rgb) true nil 1024x600
I/main airui.device_bind_touch true
I/ui AirUI 界面已构建 1024x600
I/touch fskv 已初始化
I/touch 标定存档读取成功 ns2009_cal_1024x600 长度 87
I/touch 标定系数已回灌
I/main 标定已从 fskv 恢复，跳过四点标定
I/main 测试界面已启动 屏幕 1024x600 后端 airui 触摸 NS2009（tp 核心库）
```

判读要点：

- 看到 `airui.device_bind_touch true` + `测试界面已启动 后端 airui` 说明 AirUI 链路打通；
- 看到 `标定已从 fskv 恢复，跳过四点标定` 说明持久化生效；
- `fskv 无标定存档 ns2009_cal_1024x600 nil` 说明该键没存上，会自动重标一次；
- `标定存档不合法...将作废重标` 是自愈行为，重标一次即可。

### 6、手动重标与选择是否保存

点左下 `标定` 按钮重新四点标定，完成后出选择页：

- 保存（绿）= 写入 fskv（覆盖旧存档，下次上电生效，提示"标定已保存"）；
- 不保存（红）= 本次开机生效，重启后仍用上次存档；
- 选完自动回主界面；超时则出"标定超时 + 返回"页。

## 常见问题

- `固件未启用 airui 库`：换含 `LUAT_USE_AIRUI` 的固件（factory 固件自带）；
- 黑屏但 `display.init` true：先看有没有供电轨日志——没上电就没画面；
  再看 I2C 地址无应答（NS2009 同一路供电）；
- 界面出来但触摸无反应：确认 `airui.device_bind_touch true`；
  再查 NS2009 接线/pin_int/地址；坐标整体偏移/镜像做四点标定即可（标定 按钮），不要改代码；
- 换分辨率后触摸整体偏移：旧标定系数按其它分辨率映射，本工程用独立 `cal_kv` 键名让旧存档
  失效，上电强制重标一次即可；
- 屏幕底部出现可拖动的滚动条：有控件越界了。本工程所有容器都传了 `scrollable = false`，
  且 `relayout()` 保证右/下边界留余量；改布局时务必保持 `x + w <= W`、`y + h <= H`；
- 中文字显示成方块/空白：当前字号用的内置 hzfont，个别生僻字可能缺；常用字都覆盖；
- 屏上花屏/条纹/滚动：先确认 RGB 时序（`lcd.hbp/hspw/hfp/vbp/vspw/vfp`、`bus_speed`）——
  1024×600 / 480×272 屏须按新屏规格书重填，当前是通用参考值；像素时钟按
  `(w+水平消隐) × (h+垂直消隐) × 刷新率` 估算；
- 背光不亮：确认底板背光是 PWM3，否则改配置文件的 `backlight.pwm_ch`；
- 切分辨率没生效：确认改了 `main.lua` 的 `PROJECT` 且对应配置文件在 `config/` 下；
  若新增了配置文件，记得在 `core/platform_loader.lua` 的 `_compile_manifest()` 里加一行 `require`。
