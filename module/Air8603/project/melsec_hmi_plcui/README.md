# melsec_hmi_plcui — 三菱 FX 温度监控大屏（plcui 版）

> **看门狗提醒**
>
> 860X上有合宙Air153D 看门狗芯片 其他项目参考本项目时，须确定你的项目硬件上有无看门狗芯片 如果有 但是未添加喂狗逻辑 约12分钟左右 860X会重启

Air8603W1（10 寸 1024×600）通过 RS485 走**三菱 FX 计算机链接协议（格式 1）**，
读取 2 路温度（D0/D1，原始码 0~4000 对应 0~100.0℃），界面显示实时温度、趋势曲线与报警。
**纯只读**：不向 PLC 写任何数据。

本工程与 `melsec_hmi`（airui 版）**业务逻辑完全一致**，只把 UI 层从 airui 手写控件换成
`plcui`（XML 布局 + 数据绑定）：

| | airui 版 | 本工程（plcui 版） |
|---|---|---|
| UI 描述 | `ui_*.lua` 6 个文件用 Lua 建控件 | `main.xml` 一个文件描述 5 个页面 |
| 数据绑定 | 直接持有控件对象 | `xml:find(page, id):set_text()` |
| 事件 | 回调函数 | XML `on-click` → Lua `handlers` 表 |
| 图片 | 运行时生成/绘制 | `ui/img/*.png` 预生成 |

## 文件结构

Lua 源文件全部放在 `code/` 下，下载时把 `code/` 目录整体作为脚本区
（`main.xml` 与 `ui/img/` 必须一起打包，它们是运行时资源）。

```
melsec_hmi_plcui/
├── README.md
├── code/
│   ├── main.lua          入口：fskv → 参数 → 板级 → plcui → 触摸 → 采集 → 背光
│   ├── conf.lua          全部配置：板级时序、串口、站号、温度量程、点表、阈值
│   ├── board.lua         上电时序 + RGB 屏 + 触摸（界面初始化交给 ui_hmi）
│   ├── drv_lcd_rgb.lua   RGB 并口屏驱动（含 framebuffer 数量检查）
│   ├── drv_tp_gt911.lua  GT911 触摸驱动（绑定 plcui）
│   ├── drv_fxlinks.lua   三菱协议（拼接/解析/收发/读写软元件）
│   ├── app_data.lua      采集任务：一帧读 D0~D1 → 原始码换算成温度 → 历史缓存
│   ├── app_alarm.lua     报警状态机（含回差）+ 最近 8 条记录
│   ├── app_store.lua     fskv 掉电存储（阈值、报警记录）
│   ├── app_sound.lua     报警语音播报
│   ├── ui_hmi.lua        plcui 绑定层：切页、写控件、把点击转给业务模块
│   ├── main.xml          5 个页面 + 图片资源声明（1024×600）
│   └── ui/img/*.png      按钮/状态胶囊/图标等素材
└── tools/
    ├── gen_ui_assets.ps1 用 GDI+ 重新生成全部 PNG（改配色/文字后重跑）
    ├── scene.html        设备连接图的作图源文件（HTML/CSS/SVG，896×496）
    ├── gen_scene.ps1     用 Edge 无头模式把 scene.html 截成 ui/img/dev_scene.png
    ├── cut_bg.ps1        白底产品图抠图（flood fill 去背景 + 边缘羽化 + 裁到内容框）
    ├── anim.html         链路流光帧的作图页（一屏渲染 n 帧）
    ├── gen_anim.ps1      把 anim.html 截成 n 张透明帧，命名 flow_xxx_1..n.png
    ├── preview_motion.html 双击即可看动效（真机同款帧 + 同款 200ms 节奏，可切 4/5/8 fps）
    ├── img/              作图用的实物照片（抠好的透明图，只给 scene.html 引用，不进设备）
    ├── check_xml.ps1     XML 格式与重复 id 检查
    └── check_refs.ps1    图片资源引用完整性检查
```

## 固件要求（自己编固件时必须打开）

| 宏 / 组件 | 用途 |
|---|---|
| `LUAT_USE_GUI` | LVGL 9 |
| `LUAT_USE_PLCUI` | plcui（依赖 expat 解析 XML） |
| `LUAT_USE_HZFONT` | 内置中文点阵字库，XML 里 `font="hzfont"` 靠它 |
| `LUAT_USE_DISPLAY` + RGB 接口 | 1024×600 并口屏，**需要双 framebuffer** |
| `LUAT_USE_TP` + GT911 | 触摸，绑定后 plcui 才有输入设备 |
| `LUAT_USE_FSKV` | 阈值/报警记录掉电保存 |
| `LUAT_USE_AUDIO` + TTS | 报警语音（可关，`conf.alarm.speech=false`） |

`display` 必须先初始化，plcui 才能接管：

```
board.power_on()          -- 上电时序（含 485 供电）
lcd.init(conf.board.lcd)  -- display.init(1024x600, RGB, fb>=2, rotation=0)
ui_hmi.init({...})        -- plcui.init 接管 display 0 → load main.xml
board.touch_on()          -- plcui.device_bind_touch(tp)
```

plcui 的 `init` 会校验：屏幕尺寸与 XML 一致、`rotation == 0`、`fb_count >= 2`、
draw buffer 高度等于整屏。任何一条不满足会直接报错返回，不会半死状态。

## 界面（5 页，左侧固定导航）

- **监控**：两张实时温度卡（58px 大字 + 状态胶囊）、阈值行、最近报警行，底部 5 分钟迷你趋势；
- **趋势**：10 分钟窗口双通道曲线（300 点，2s/点），CH1/CH2 显示开关、清空历史；
- **报警**：最近 8 条表格（时间/通道/类型/触发值/阈值/状态），消音、复位、清空；
- **设备**：整幅设备连接图（屏 ↔ RS485 ↔ PLC ↔ AD0/AD1 ↔ 两台三线制 T100 变送器：红 24V / 黑 0V·GND / 黄信号，含 24 VDC 与屏蔽接地）。底图由 `tools/scene.html` 渲染成一张 PNG，实物照片已抠掉白底；页面上再叠 4 个 8 帧流光图层（RS485 请求/应答、两路变送器信号），由 `ui_hmi.lua` 的 `anim_tick` 每 200 ms 换一帧，只在设备页运行；两处「实测」框显示实时温度；
- **设置**：每路预警/报警阈值，步进 1.0℃，预警必须小于报警，保存写 fskv 并立即生效。

顶栏（每页都有）：PLC 在线点、在线文字、时钟、喇叭（静音/解除静音）。

### main.xml 几个硬规则

1. **`xml:find(page, id)` 只认当前页**。别的页面的控件拿不到，切页后旧句柄全部失效。
2. **事件回调里 `xml:show()` 是延迟生效的**，页面控件要等事件分发结束才建好，
   所以切页后要用 `sys.timerStart(..., 60)` 再刷新（`ui_hmi.lua` 里用 `plcui.status().page`
   对齐真实页码，避免拿错页的句柄）。
3. **XML 里出现的每个 `on-click` 必须在 handlers 表里有同名函数**，否则 `plcui.load`
   直接返回 `E_HANDLER`，整屏起不来。
4. **只有 `image` 可点击**（`clickable="true"`），所以按钮都是「图片 + 正常/按下/选中」三态小图，
   静态文字直接烘进 PNG；`label` 只用于运行时变化的文本。
5. `font_size` 只能配 `font="hzfont"`；`page` 只支持 `id` 和 `background`，
   圆角/描边要放在 `container` 上。
6. 页面尺寸必须等于 `plcui.init({width,height})`，也就是 1024×600。

### 素材

按钮/胶囊都是小图，不放大背景（1024×600 位图解码慢、吃内存）。
改配色或按钮文字后重新生成：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\gen_ui_assets.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\gen_scene.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\gen_anim.ps1 -W 104 -H 28 -N 8 -Dir ltr -Color 22D3EE -Prefix flow_485a
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\check_refs.ps1 -Path .\code\main.xml
```

设备页的 4 组流光帧（前缀 `flow_485a` / `flow_485b` / `flow_ma1` / `flow_ma2`，各 8 帧）
由 `gen_anim.ps1` 生成；实物照片抠图用 `cut_bg.ps1 -Src 原图 -Dst tools\img\xxx_cut.png`。

流光帧是「底光 + 会移动的亮核」画法：每帧整条线都亮着（`opacity 0.07` 的底光），
亮核从一端走到另一端，`ui_hmi.lua` 里每 200 ms 换一帧。`preview_motion.html`
用同一批 PNG 按同样节奏播放，**双击用浏览器打开就能看到真机上的效果**——
`?f=3` 可以定格在第 3 帧，页面上也能切 4/5/8 fps 对比哪种更顺。

`check_refs.ps1` 会核对 XML 里引用的每个 `src` / `src-pressed` / `src-checked`
是否都能在 `ui/img/` 找到文件，改完素材跑一下能挡掉大部分"白块"问题。

## PLC 侧准备（缺一不可）

```
; 上电初始化（M8002）
MOV H6087 D8120     ; 9600 / 8 位 / 偶校验 / 1 停止位 / 格式1 / 自动和校验
MOV K0    D8121     ; 站号 0

; 常驻扫描
RD3A K0 K0 D0       ; AD0 → D0（温度 1），用 2AD 模块时 K0/K1 两路
RD3A K0 K1 D1       ; AD1 → D1（温度 2）
```

要点：

- **改 `D8120` 后必须给 PLC 断电重启**，通信格式只在上电时读取一次；
- PLC 必须在 **RUN**，STOP 状态下不响应任何报文；
- 在线监视 `D8120`，值应为十进制 **24711**（`H6087`），不是这个数说明没写进去；
- `D8121` 必须与 `conf.plc.station` 一致（默认都是 0）。

## 点表与换算

| 用途 | 软元件 | 换算 |
|---|---|---|
| 温度 1 | D0 | 原始码 0~4000 → 0.0~100.0℃（`raw / 40`） |
| 温度 2 | D1 | 同上 |

两路地址连续，所以每 1s 只用**一帧** `WR` 就读完，总线占用最小。

量程换别的变送器（例如 0~10V 对应 0~150℃）只改 `conf.scale.val_max` 一处：
主页大字、曲线 Y 轴、阈值上限、语音播报全部跟着走（`main.xml` 里 Y 轴刻度文字
`y_hi/y_mid/y_low` 是静态的，换量程要顺手改这三个数）。

## 串口参数

```
9600  8 数据位  偶校验(Even)  1 停止位  无流控
```

对应 `conf.uart`：`baud=9600, databits=8, stopbits=1, parity=uart.Even`。

> **为什么用 8 位而不是 FX 默认的 7 位：** 本平台 uart 驱动的 7 位设置不生效，
> 硬件始终按 8 位采样。PLC 侧必须同步改成 `D8120 = H6087`（b0=1）。

## 报文（可用串口工具直接核对）

HEX 模式发送，接收也建议用 HEX 显示。

**读 D0 一个点**

```
05 30 30 46 46 57 52 30 44 30 30 30 30 30 31 32 41
```

响应（D0=870 时）：

```
02 30 30 46 46 30 33 36 36 03 42 45
```

**读 D0~D1 两个点（本工程采集用的就是这一帧）**

```
05 30 30 46 46 57 52 30 44 30 30 30 30 30 32 32 42
```

响应（D0=870=0x0366，D1=750=0x02EE）：

```
02 30 30 46 46 30 33 36 36 30 32 45 45 03 41 41
```

帧格式约定：

```
请求  ENQ(05) 站号(2) PLC号(2) 命令(2) 延时(1) 软元件(5) 点数/数据 校验(2)
响应  STX(02) 站号(2) PLC号(2) 数据 ETX(03) 校验(2)
写ACK ACK(06) 站号(2) PLC号(2)
写NAK NAK(15) 站号(2) PLC号(2) 错误码(2)
```

校验和范围两处不一样，这是最容易写错的地方：

- **请求**：从站号第一个字符到帧尾累加（不含 ENQ），取低 8 位；
- **响应**：从站号第一个字符到 **ETX（含）** 累加，取低 8 位。

字数据每点 4 个 ASCII 字符，是**十六进制**，不是十进制字符串：`0366` = 870，不是 366。
870 / 40 = **21.75℃**。

## 排障

| 现象 | 原因 |
|---|---|
| 启动后黑屏、日志 `plcui.init 失败` | 屏没初始化成功，或 fb 只有 1 块，或 rotation≠0 |
| 日志 `界面加载失败 E_SCHEMA` | XML 有未支持的属性/标签，或尺寸不等于 1024×600 |
| 日志 `界面加载失败 E_HANDLER` | XML 里 `on-click` 的名字在 handlers 表里没有 |
| 日志 `E_RESOURCE` / 图片白块 | `ui/img` 没打包进脚本区，或 `src` 写错（用 `check_refs.ps1` 查） |
| 中文全是方框 | 固件没开 `LUAT_USE_HZFONT`，或内置字库没编进去 |
| 切页后数据不刷新 | 用了切页前的控件句柄；要按 `plcui.status().page` 重新 `xml:find` |
| 触摸无反应 | 忘了 `plcui.device_bind_touch`，或在 `plcui.init` 之前绑定 |
| 发送后无任何响应 | PLC 在 STOP；`D8120` 改了没重启；A/B 接反；站号不符 |
| 收到 `3F 3F 3F ...` 乱码 | 参数不匹配（7/8 位、波特率），或总线浮空；拔掉 PLC 侧 A/B 重发，若仍有乱码说明是噪声 |
| 收到 `15 ...` NAK | 看错误码：`02` 校验和错、`03` 协议号错、`06` 字符区错、`07` 数据含非十六进制字符 |
| 读回全 0 | 值确实是 0，或模块未转换；先确认响应帧头和校验和正常 |
| 温度显示偏低一半 | 多点读时数据区偏移错（数据从第 6 字节起取） |

## 离线自检

不接 PLC 也能核对拼帧与解析：

```lua
local fx = require "drv_fxlinks"
print(fx.hex(fx.build_frame("WR", "D", 0, "02")))   -- 拼"读 D0~D1 两点"请求
print(fx.parse_frame("\2" .. "00FF" .. "0366" .. "02EE" .. "\3" .. "\xAA").data)
```
