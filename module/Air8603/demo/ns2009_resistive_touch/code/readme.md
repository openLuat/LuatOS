# NS2009 电阻触摸整机测试 Demo（ns2009_resistive_touch）

Air8603M1（模组 Air1603）+ 7 寸 800×480 RGB 屏（HX8264）+ NS2009 电阻触摸：
点屏、触摸实时测试、四点标定与标定系数 fskv 持久化，一套工程验证整机显示与触摸。

界面用 AirUI 控件（container / label / button / shape）+ hzfont 真字体；
触摸、四点标定走核心库 `tp`，AirUI 通过 `airui.device_bind_touch(dev)` 复用
`tp.init` 的设备，直接拿到标定后的屏幕坐标。

> 目录结构：本 readme 与全部脚本在 `code/` 子目录；上级目录是硬件环境说明
> （`测试硬件环境说明.md`）与屏/触摸规格书 PDF。烧录时脚本目录选 `code/`。

## 功能模块介绍

1、main.lua：主程序入口，底板上电时序 → 点屏（`display.init` 分配 FB）→
   `airui.init`/旋转/字体 → `tp.init` 触摸 + `airui.device_bind_touch` → 建界面 →
   起主循环 → 上电标定恢复/强制标定；

2、config.lua：唯一配置源，上电时序 / RGB 时序 / 背光 / 触摸参数 / AirUI 主题配色与字号
   全部在这里，其它模块只 require 本文件，不写死任何引脚号；

3、drv_screen.lua：真机 `display.init("rgb")` 分配帧缓冲（AirUI 随后使用）+ PWM3 背光调光；
   点屏/刷新/绘制全交给 AirUI（LVGL 每帧自刷），本模块不做绘制封装；

4、drv_touch.lua：核心库 tp（新版 API）直驱 NS2009：事件桥接、四点标定封装、
   标定系数读回 / 回灌 / fskv 存档；

5、ui_test.lua：AirUI 测试界面（触摸区 + 网格 + 准星 + 轨迹 + X/Y 数值面板 + 4 按钮 +
   标定页 + 保存/不保存页 + 超时页）。

## 演示功能概述

1、触摸实时测试：在网格区滑动，准星跟随（shape 移动）或画线（shape 累积折线，段数封顶），
   右侧面板实时显示 X/Y 坐标、按下状态、已标定状态；
   坐标/按下状态在全屏任意位置触摸都更新（准星/轨迹绘制仍限于网格区）；

2、模式切换：`准星` / `画线` 两个模式按钮（当前模式按钮带 ● 高亮）；`清空` 清掉轨迹；

3、四点标定：`标定` 按钮 → 干净标定页 + 十字，按 左上 → 右上 → 左下 → 右下 依次点击
   （调核心库 tp.calibration）；

4、标定系数持久化（新版 tp API）：标定完成后出"保存 / 不保存"选择页，选"保存"系数经 json
   存入 fskv（键 ns2009_cal），下次上电用 `tp.calibration(dev, data)` 回灌恢复，
   不再重复标定；首次上电标定与手动标定同一待遇，都出选择页，由用户决定是否存档；

5、存档自愈：存档损坏或与固件系数结构不兼容时自动删除并重新标定；

6、手动标定超时（60 秒）：停在"标定超时 + 返回"页，点返回回主界面可再标；

7、首次上电强制标定：无存档时必须完成一次标定才能进主界面——未标定时触摸坐标上下颠倒
   （NS2009 芯片原点在左下、屏幕逻辑原点在左上）。标定不限时、无法退出：
   不点就一直等，固件侧超时/失败自动重新开始，直到标成功；
   标定页顶部居中显示"正在校准屏幕触摸"。

## 演示硬件环境

1、Air8603 开发板（Air8603M1 底板，模组 Air1603）一块；

2、40PIN 电阻触摸显示屏一套：宏显伟业 0700A001-H1E0191，7 寸 800×480 RGB-24BIT
   （驱动 IC HX8264），触摸为深圳纳芯微 NS2009（4 线电阻，在屏排线上）；

3、12V DC 电源一个（40PIN 屏的背光升压需要 12V，USB 口带不动整机）；

4、USB 数据线一根（接 Type-C，用于烧录和看日志）。

接线方式（详见上级目录 `测试硬件环境说明.md`）：

- 屏排线接底板 40PIN 座（屏和 NS2009 同一路供电，底板上电时序会逐轨拉高）；
- 触摸走 I2C1：PIN42=SCL / PIN41=SDA，PENIRQ = PIN51（GPIO51），NS2009 地址 0x49（A0 拉高）；
- 12V 电源接 DC 座，Type-C 接电脑烧录。

> 注意：上电时序（GPIO12/56/44/52 → 5V/9V/12V/5VOUT）在 main.lua 的 power_on 里完成，
> 少了这步的表现是：LCDC 初始化"成功"但黑屏 + I2C 上触摸无应答。

## 演示软件环境

1、[Luatools 工具](https://docs.openluat.com/common/Luatools/)；

2、内核固件文件（本 demo 需要同时启用下列库的固件）：

   - `airui`（AirUI/LVGL GUI 层）——缺它直接跑不起来；
   - `display`（真机 RGB 帧缓冲，AirUI 依赖它分配的 FB）；
   - `tp`（NS2009 触摸 + 四点标定 + 系数读回/回灌，需新版支持读回/回灌）；
   - `fskv`（标定系数持久化；缺它则每次上电重标，日志会提示"固件没有 fskv 库"）；
   - `json`（系数序列化）；
   - `pwm`（背光调光）。

   Air8603 factory 固件本身就带 AirUI（设置/开机画面都用它），可直接用；
   若用裸 demo 固件，需确认已编译进 `LUAT_USE_AIRUI`。

## 演示核心步骤

### 1、按实际接线检查配置

打开 config.lua，确认触摸段（改硬件只动这个文件）：

```lua
CFG.touch = {
    i2c_id  = 1,             -- I2C1：PIN42=SCL / PIN41=SDA
    pin_int = 51,            -- PENIRQ 引脚（★ 按实际接线修改；nil 则启动时报错）
    w       = 800,           -- 触摸映射目标宽（与屏一致）
    h       = 480,           -- 触摸映射目标高
    save_cal = true,         -- 标定完成后自动存 fskv，上电自动恢复
    cal_kv  = "ns2009_cal",  -- fskv 键名
    auto_cal = true,         -- 无有效存档时上电强制四点标定（不限时）
    direction = nil,         -- 触摸坐标旋转；nil=跟随 LCD（默认不设，方向靠标定解决）
    swap_xy  = nil,          -- 坐标镜像翻转；nil=不翻转（保持固件默认基准）
}
```

### 2、烧录并运行

用 Luatools 把 `code/` 目录下的所有 .lua 文件下载到模块（脚本目录选 `code/`），
下载完成后自动运行。

### 3、首次上电：强制四点标定

无存档时强制进入标定页（顶部显示"正在校准屏幕触摸"）：保持松手，屏幕依次出现四个十字，
按 左上 → 右上 → 左下 → 右下 顺序点击。此页面不限时、无法退出——不点就一直等，
固件侧超时/失败会自动重新开始，直到标完为止；完成后出"保存 / 不保存"选择页，
选"保存"则存档并进主界面（之后上电免标定）。

> 点"标定"按钮手动重标不受此限：保留 60 秒超时，超时出"标定超时 + 返回"页。

### 4、观察日志

首次上电（标定并存档）：

```
I/main 供电轨 GPIO12 =1
I/screen display.init(rgb) true nil 800x480
I/main airui version 1.3.0
I/touch NS2009 就绪（新版 tp API） 800x480 int=PIN51
I/main airui.device_bind_touch true
I/ui AirUI 界面已构建 800x480
I/main 无有效标定存档（not_saved），上电强制四点标定（不限时）
I/ui 开始四点标定；按左上、右上、左下、右下顺序点击十字
I/touch POINT 120 120
I/touch POINT 680 120
I/touch POINT 120 360
I/touch POINT 680 360
I/touch DONE true
I/ui 标定完成 true
I/touch 标定系数已存档 ns2009_cal 长度 87
```

再次上电（存档恢复，免标定）：

```
I/screen display.init(rgb) true nil 800x480
I/main airui.device_bind_touch true
I/ui AirUI 界面已构建 800x480
I/touch fskv 已初始化
I/touch 标定存档读取成功 ns2009_cal 长度 87
I/touch 标定系数已回灌
I/main 标定已从 fskv 恢复，跳过四点标定
I/main 测试界面已启动 屏幕 800x480 后端 airui 触摸 NS2009（tp 核心库）
```

判读要点：

- 看到 `airui.device_bind_touch true` + `测试界面已启动 后端 airui` 说明 AirUI 链路打通；
- 看到 `标定已从 fskv 恢复，跳过四点标定` 说明持久化生效，上电即可直接点；
- `fskv 无标定存档 ns2009_cal nil` 说明该键没存上（换固件/清过 kv），会自动重标一次；
- `标定存档不合法...将作废重标` 是自愈行为（固件系数结构变了或存档损坏），重标一次即可。

### 5、手动重标与选择是否保存

点左下 标定 按钮重新四点标定，完成后出选择页：

- 保存（绿）= 写入 fskv（覆盖旧存档，下次上电生效，提示"标定已保存"）；
- 不保存（红）= 本次开机生效，重启后仍用上次存档（提示"未保存（本次生效）"）；
- 选完自动回主界面；超时则出"标定超时 + 返回"页。

## 常见问题

- `固件未启用 airui 库`：换含 `LUAT_USE_AIRUI` 的固件（factory 固件自带）；
- 黑屏但 `display.init` true：先看有没有供电轨日志——没上电就没画面；
  再看 I2C 地址无应答（NS2009 同一路供电）；
- 界面出来但触摸无反应：确认 `airui.device_bind_touch true`；
  再查 NS2009 接线/pin_int/地址；坐标整体偏移/镜像做四点标定即可（标定 按钮），不要改代码；
- 中文字显示成方块/空白：当前字号用的内置 hzfont，个别生僻字可能缺；常用字都覆盖；
- 屏上花屏/条纹/滚动：先确认 RGB 时序（config.lua 的 hbp/hspw/hfp/vbp/vspw/vfp、bus_speed）；
- 背光不亮：确认底板背光是 PWM3，否则改 config.lua 的 CFG.backlight。
