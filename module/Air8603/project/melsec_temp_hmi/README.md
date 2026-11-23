# melsec_temp_hmi — 双路温度监控大屏（Air8603W1 + FX3U）

> **看门狗提醒**
>
> 860X 板载合宙 Air153D 硬件看门狗，PIN47 = GPIO57 经 NPN 三极管驱 WTDOG。
> 不喂约 12 分钟芯片会拉复位，表现是"跑一阵子自己重启"。本工程在 `main.lua` 里
> 用 `exair153x_wdt` 起了自动喂狗（`config.board.wdt_pin = 57`）；固件不带这个库会
> 降级成一条 warning。板子上没有这颗芯片就把 `wdt_pin` 设成 `false`。

LuatOS 工程（Lua 5.3 + AirUI），通过 RS485 计算机链接（格式 4）读取 FX-32MT 的 AD 原始值，在 10 寸 1024×600 屏上显示温度、趋势、报警与阈值设定。

界面是纯矢量画的：卡片、环形表、趋势曲线全部由 `airui.shape` 的图元拼出来，不依赖任何图片素材（除了五个导航图标）。

## 一、目录

```
melsec_temp_hmi/
├─ README.md            本文件（不随工程下载）
├─ code/                ← 烧录时把「这个目录」当工程根打开
│  ├─ main.lua
│  ├─ config.lua
│  ├─ board.lua
│  ├─ ui_home.lua
│  ├─ fx.lua
│  ├─ theme.lua
│  ├─ fx3u.lua
│  ├─ signal.lua
│  ├─ alarm_mgr.lua
│  ├─ store.lua
│  ├─ sound.lua
│  └─ *.png             7 个 96×96 透明图标（必须平铺在脚本根，路径 /luadb/xx.png）
└─ preview/*.png        五页效果图 + 报警弹窗（离线渲染，不随工程下载）
```

**注意两点**：

1. LuatOS 只会自动运行脚本分区根目录的 `main.lua`。所以烧录时在 Luatools 里选的工程目录必须是 `code`，不是它的上一层——否则 `main.lua` 会落到 `/luadb/code/main.lua`，板子上什么都不会跑。
2. 图标必须平铺在脚本根目录，路径写 `/luadb/xxx.png`。这正是所有官方 demo 的写法；放在 `res/icons/` 这类子目录里，PC 模拟器会找不到（真机倒是能认）。

| 文件 | 职责 |
|---|---|
| `main.lua` | 入口：初始化、采样调度、界面回调 |
| `config.lua` | **唯一参数表**，串口/协议/阈值/屏参都在这 |
| `board.lua` | 屏、触摸、AirUI 框架、**中文字库**、背光 |
| `fx3u.lua` | 计算机链接协议：组帧、校验、收发状态机、超时重试 |
| `signal.lua` | AD → 温度换算（0.1℃ 整数）、一阶滤波、故障判定 |
| `alarm_mgr.lua` | 报警状态机：预警/报警、回差、8 条记录、消音、复位 |
| `store.lua` | 阈值与报警记录的掉电保持（fskv + json） |
| `sound.lua` | 报警语音播报（TTS → exaudio → DAC → HT6873） |
| `theme.lua` | 设计令牌：配色 / 几何 / 字号 + 少量控件封装 |
| `fx.lua` | 绘图工具层：图元池、颜色混算、缓动、环形表/刻度/趋势等复合图元 |
| `ui_home.lua` | 五个页面的全部界面代码 |

## 二、页面结构

五页常驻内存，启动时一次建好，之后用容器 `set_hidden` 切换（AirUI 容器不支持运行时改尺寸，也不便重建）：

| 页面 | 内容 |
|---|---|
| 总览 | 两个环形表通道卡（温度大数字 + 270° 弧 + 预警/报警区）+ 双路趋势 + 最近 5 条报警 + 运行状态 + 消音/复位 |
| 趋势 | 大图（自绘，纵轴自适应）+ 10/30/60 分钟切换 + 右侧当前值/区间最高最低 |
| 报警 | 8 条记录表 + 全部/报警/预警/已恢复筛选 + 表尾统计 |
| 设定 | 两路 × 预警/报警 四组 ±0.1/±1.0 步进 + 量程条 + 本机参数 + 保存/恢复出厂 |
| 设备 | RTT/成功率/帧数/运行时长四个 KPI + 6 行寄存器映射 + 板卡信息 |

底部五个等宽页签切换，选中态为加强底色 + 强调色描边 + 底部指示条。

### 关键设计决定

| 决定 | 原因 |
|---|---|
| 卡片是 `airui.shape`，不是 `airui.container` | container 就是 `lv_obj_create`，默认带 `SCROLLABLE` 标志。子对象包围盒超出内容区 1px 就会画出滚动条，真机上表现为"卡片里多一圈方角细框"。shape 的 C 代码硬编码了 `remove_flag(SCROLLABLE\|CLICKABLE)`，永远不会出滚动条 |
| 趋势自己画，不用 `airui.chart` | chart 的 `y_min/y_max` 只能在创建时定一次，之后 `set_y_axis` 只改标签不动绘图映射 —— 26℃ 的数据画在 0–100 的纵轴上就是贴着底边一条直线。自绘之后纵轴按数据自适应，还顺带解决了"轴标签只能打整数、显示不了工程量"的问题 |
| 环形表用 `arc` 图元 | 折线逼近在弧宽 10px 时顶点全靠圆头去补，段数不够会数出"珠子"，段数够多又是几十个图元的开销。arc 由 `lv_draw_arc` 直出，任意扫角都是几何意义上的圆 |
| 数值走指数缓动 | 弧和数字一起平滑逼近，不做硬跳变。缓动跑在 10 Hz 定时器里，稳定后不再重绘 |

### 帧预算

1024×600 的 RGB 屏没有 GPU，整屏重绘一次就是 61 万像素。所以：

- 卡片底板、环形表轨道与刻度：**只在构建时画一次**；
- 每路通道的进度弧单独占一个 176×176 的小 shape，**只在数值变化时** `set_items`；
- 趋势图每次落点（3 秒）重绘一次，采样到 200（总览）/ 300（趋势页）列；
- 文字只在值真的变了才 `set_text`（LVGL 每次 set_text 都要重新排版）。

## 三、接线

| PLC 扩展口（丝印 `RS232/RS485`） | Air8603W1 `J21` |
|---|---|
| 1 脚 A(+) | `485_1A` |
| 6 脚 B(−) | `485_1B` |
| 5 或 9 脚 GND | `GND1` |
| — | `VISO1` 悬空（那是隔离电源输出） |

`J22` 在 W1 上不装器件，`J7` 是 UART2 的 TTL，别接。

## 四、烧录

1. 用 Luatools 打开 **`code` 目录**（不是它的上一层），选择 **Air8603 W 系列固件**（WiFi 版；4G 型号需另烧专用 4G 固件）。
2. 编译并下载脚本（下载口是板载 Type-C 的 USB2，不是 485 口）。下载后设备上应是 `/luadb/main.lua` + `/luadb/*.png`。
3. 上电后串口日志应出现：
   ```
   board  display.init  true
   board  font_load(hzfont)  true
   board  airui.init ok
   ui     界面已构建 1.x.x
   fx3u   init uart 1 9600 8E1 de 65
   main   阈值已恢复 ...
   ```
4. 若 `display.init` 返回 false：核对 `config.lua` 里的时序参数与屏规格书。

## 五、关键参数（`config.lua`）

| 参数 | 默认 | 说明 |
|---|---|---|
| `uart.uart_id` | 1 | W1 的 UART1 → J21 |
| `uart.de_pin` | 65 | 485_EN1，方向脚。**必须传给 `uart.setup` 第 8 参数**，不能只靠 `gpio.set` |
| `uart.pwr_pin` | 64 | 485 功能总供电，必须先拉高，否则收发器不上电 |
| `uart.rs485_native` | true | 方向控制交给固件；置 false 改用手翻 GPIO（仅在固件不认第 8 参数时用） |
| `uart.rs485_delay` | **2000** | 发完到转接收的延迟 us。**不是越大越好**：填 20000（20ms）会把总线攥在自己手里，PLC 的应答撞上自己的发送器，100% 超时。同板实测 2000 可用 |
| `plc.crlf` | true | 格式 4 必须带 CR LF；改 `false` 即格式 1（D8120 要同步改 `H6387`） |
| `plc.poll_ms` | 330 | 轮询周期，300–500ms 合适 |
| `plc.log_frames` | true | 打印收发原始报文（十六进制 + 控制码）。调试期开，稳定后关 |
| `alarm.popup` | true | 新报警弹窗 |
| `alarm.popup_auto_hide` | 20000 | 弹窗自动收起 ms（0 = 必须手动关） |
| `alarm.speech` | true | 语音播报总开关 |
| `alarm.speech_gap` | 10000 | 报警持续期间的重播间隔 ms（0 = 只播一次） |
| `audio.pa_pin` | 73 | AUDIOPA_EN = GPIO73（HT6873 高有效） |
| `audio.vol` | 20 | 音量 0-100 |
| `scale` | 4000 → 1000 | AD 0–4000 对应 0–100.0℃ |

## 六、与 PC 端的一致性

`fx3u.lua` 的帧构造与 `solution/fx3u_bench.py` 完全一致（已在现场验证通过）：

```
读 D100~D102：05 30 30 46 46 57 52 41 44 30 31 30 30 30 33 33 45 0D 0A
应答：       02 30 30 46 46 30 34 30 45 ... 03 41 46 0D 0A
写应答：     06 30 30 46 46 0D 0A        ← 只有 6 字节，不能按固定长度等
```

排查顺序固定为：**PC 能读通 → 再怀疑屏端**。屏端读不到时，先把 485 线挪回 PC 跑一次 `fx3u_bench.py read 100 3`，能立刻区分是 PLC 侧还是屏端的问题。

## 七、待确认项（首次上机需核对）

1. **`display.init` 的接口**：本工程按 `display.init("custom", {...})` 写（与出厂工程 `drv/lcd/lcd_display_rgb.lua` 一致）。早期固件若是 `lcd.init`，改 `board.lua` 里那一个调用即可。
2. **触摸**：`tp.init("gt911", params)` —— 名字必须是 `gt911`。调用前要自己 `i2c.setup(1, 0, true)`，`w/h` 必须给 1024×600。返回值交给 `airui.device_bind_touch`。引脚 `pin_rst=14` / `pin_int=51` 已按出厂配置写好。
3. **图标路径**：固定 `/luadb/xxx.png`（常量 `ICON_DIR`），图标和 `.lua` 平铺在脚本根目录。airui 的 `src` 要完整 VFS 路径，没有 plcui 那层资源表。首次加载前做一次 `io.exists` 检查，图标整批缺失就只打一条 warning 并跳过，不会每张图刷三条错误日志。要挪位置改 `ICON_DIR` 一处。
4. **报警音**：喇叭接 J13，`main.lua` 末尾留了接入位置。声音走 Air1103 通路（`exaudio` / `audio`），需按固件实际接口接。

## 八、启动日志解读

正常应该看到：

```
board  display.init  true
board  font_load(hzfont)  true
board  airui.init ok 0.x.x
board  backlight on 3 90
board  tp.init ok
ui     界面已构建
fx3u   init UART1 9600 8E1 内置485 换向 DE=GPIO65 delay=2000us pwr=GPIO64
fx3u   时间基准 ticks/50Hz，一格 20ms timeout=500ms
fx3u   TX 19B 05 30 30 46 46 57 52 30 44 30 31 30 30 30 33 32 44 0D 0A | ENQ00FFWR0D0100032DCRLF
fx3u   RX 22B 02 30 30 46 46 30 31 30 30 30 32 35 38 30 32 42 43 03 36 36 0D 0A | STX00FF0100025802BCETX66CRLF
main   阈值已恢复 ...
```

`fx3u init` 那一行要特别看一眼：
- `内置485 换向 DE=GPIO65 delay=2000us` → 正确，方向脚已交给 `uart.setup`
- `手动换向 DE=GPIO65` → 说明 `rs485_native=false` 或内置模式初始化失败，走的是 Lua 翻脚；能用，但时序精度差一档
- 完全没有这行 / `uart.setup 失败` → 串口没打开，后面一定全是超时

常见异常：

| 日志 | 含义 | 处理 |
|---|---|---|
| `W/hzfont 未注册，无法设置字号` | **没调 `airui.font_load`** | 界面全是 14 号默认字体、汉字全空白。`board.airui()` 里已有这一步，若被跳过说明固件没有 `font_load` |
| `E/tp tp_name:tp_gt911 not found` | **驱动名写错了**，不是缺驱动 | 内核注册的名字是 `gt911`，`tp_gt911` 是出厂配置里的外设 id。写错时 `tp.init` 返回 nil，界面照常显示但点不动。见第十章 |
| `tp.init 失败 … I2C 扫描: 无设备` | 供电或排线问题 | GT911 在 0x5D 或 0x14；一个地址都没有说明屏排线/触摸供电没到位 |
| `tp.init 失败 … I2C 扫描: 0x5D` | 芯片在，但初始化被拒 | 多半是 `w/h` 没给或给了 0（input 适配器以 EINVAL 静默拒绝），或 `i2c.setup` 没做 |
| `attempt to index a airui.xxx value` + `Lua VM exit!! reboot in 1000ms` | 往组件 userdata 上挂了自定义字段 | 见第十章。把状态放在普通表里，别挂在 label/shape 上 |
| `fx3u uart.write 返回 -1` | 方向脚没被固件接管，驱动拒绝发送 | 检查 `uart.setup` 有没有传第 8/9/10 参数；程序会自动降级为手动换向并打这条日志 |
| `超时重试 1/2` 每秒刷屏 + `本帧收到 0 字节` | 物理层不通：DE 没换向 / 485 没供电 / A B 接反 | 确认 init 日志的换向模式、`de_pin=65`、`pwr_pin=64` 已拉高；万用表量 A B 之间应有 1~2V 静态偏置 |
| `本帧收到 N 字节` 但解析不出 | 收到的字节数不为 0，说明线路通但**格式对不上** | 先核对 PLC 的 D8120：格式4 要 `H E387` + `crlf=true`；格式1 要 `H 6387` + `crlf=false`。再看校验位是不是 8E1 |
| `E/pwm setup ch 3` + `背光 PWM 设置失败` | 该固件未开放 PWM3，或引脚复用未在 LuatIO 里配 | 不影响显示与通信；**若屏常暗**，按固件手册配置 PWM3 复用，或在 `config.lua` 改 `bl_pwm_ch` |
| `fx3u 配置缺失: xxx` | `config.uart` / `config.plc` 里某个字段少了 | 按提示补字段；`init` 会返回 false，采样不会启动 |
| `bad argument #N to 'xxx' (number expected, got nil)` | 某处参数是 nil | 先看上一行 `fx3u 配置缺失`，多半是同一个原因 |

## 九、PC 模拟器调试

LuatOS 的 PC 模拟器可以直接跑这套代码，无需硬件：

1. 把 `config.lua` 里 `plc.enable` 改成 `false`——不轮询、不刷超时日志，只调界面。
2. 运行后应该**只有一个 `AIRUI` 窗口**。

> 如果出现两个窗口（`AIRUI` + `custom`）：那是 `display.init` 在 PC 上另开了 SDL 窗口。
> `board.lua` 已按出厂驱动的做法加了 `rtos.bsp() == "PC"` 判断，PC 下跳过 `display.init`。

模拟器里能验证：布局、字号、颜色、按钮点击、设定的加减与校验。
验证不了：真实时序、多帧缓冲、触摸驱动、485 通信。

## 十、AirUI 踩坑清单

这一版界面之所以能出效果，关键是下面这几条。**全都对着 `components/airui` 的 C 源码核过，文档注释有滞后**：

| 坑 | 现象 | 真相 |
|---|---|---|
| **没有 `airui.font_load`** | 所有汉字不显示、所有 `font_size` 失效 | `label:set_font_size` 走 `airui_text_font_apply_hzfont()`，该函数第一句就是 `if (luat_hzfont_get_state() != READY) { 只打一条 warning; return NOT_SUPPORTED; }`。必须先 `airui.font_load{type="hzfont"}`（`path` 传 nil 用内置字库） |
| **小数坐标** | 图元凭空消失 | C 层用 `lua_tointeger` 读字段，Lua 5.3 只接受"整数值的浮点"。传 `3.7` 得到 0 → 线宽 0 / 透明度 0。`fx.lua` 里所有写入都过一遍 `math.floor` |
| **`arc` 图元是有的** | 以为只能拿圆点拼弧 | `luat_lib_airui_shape.c` 的 @api 里明确列了 `type="arc"`：`cx/cy/r/start_angle/end_angle/color/width/opacity/rounded`。0 度在 3 点钟、顺时针为正、`r` 是**外半径** |
| **`rect` 含端点** | 卡片右下缺一条边 | `x2 = x + w`，想正好铺满要传 `w - 1` |
| **容器会画滚动条** | 卡片里多一圈方角细框 | 见第二章。要么用 shape，要么保证子对象不超出内容区 |
| **容器不能改尺寸** | — | 只能 `destroy` 重建；改样式可以 |
| **`align` 要常量** | 文字对齐不生效 | 传 `airui.TEXT_ALIGN_*`（数值常量），不要传字符串 |
| **重绘靠脏区** | 隐藏页面里 `set_items` 不渲染 | 切页后补一次重绘（`M.go` 里 `defer` 40ms 重画趋势） |
| ~~hzfont 缺字形~~ **（已证伪）** | — | 之前照着 `jf_ev_dash` 的注释以为没有 `·` `°` `℃`，实测**都有**：直接解析 `components/hzfont/src/hzfont_ttf_lib.c` 里的内置 MiSans（7619 字），`℃`=glyph 7610、`°`=7605、`·`=7362、`→`=7509、`●`=7512，轮廓都不为空。温度单位已统一成 `℃`。分隔符仍用 `|` 只是审美选择，不是限制 |
| **不能给组件挂字段** | 直接崩：`attempt to index a airui.label value` → `Lua VM exit!! reboot in 1000ms` | 组件是 userdata，没有 `__newindex`。`ui.rows[i] = airui.label{...}; ui.rows[i].foo = ...` 必崩。要带附加状态就包一层普通表：`ui.rows[i] = { val = ..., state = ... }` |
| **`font_load` 的 `cache_size` 是白名单** | 日志 `W/hzfont cache_size_invalid=1400 use_default=256` | 只接受 `{128, 256, 512, 1024, 2048}`（`luat_hzfont.c` 的 `HZFONT_CACHE_ALLOWED`）。写别的值会被静默换成 256 —— 字号档位多时会不断淘汰重建字形。本工程用 1024 |
| **`tp.init` 的驱动名是 `gt911`** | 界面能显示但完全点不动，日志只有一行 `tp_name:tp_gt911 not found` | `tp_gt911` 是出厂配置里给外设起的 id，不是内核驱动名。另外 `i2c.setup(port, 0, true)` 必须自己做（第三参 true = 轮询，避免"只有触摸时"报 I2C 错），`w/h` 必须给真值 |
| **忘记喂外部看门狗** | 跑 10 几分钟后整机自动重启，日志里没有任何线索 | 860X 板载 Air153D，喂狗脚 GPIO57（PIN47 经 NPN 驱 WTDOG）。要 `require("exair153x_wdt").init{wdt_pin=57}`，它和 LuatOS 自带的 `wdt`（软件看门狗）是两颗不同的东西，两个都要 |
| **PNG 不能有多个 IDAT 块** | `W/image png hw probe failed: /luadb/xx.png, multiple IDAT blocks are not supported by hardware` | 固件硬件解码器只认单个 IDAT。Edge 无头截图生成的 PNG 恒为「主块 + 6 字节尾巴」两段，于是每张图都退回软件解码。用 `devtools/png_single_idat.py <目录>` 合并（只重排 IDAT，不解压不重压，像素零改动） |
| **图标别放子目录** | `D/vfs fopen /luadb/res/icons/xx.png rb not found` + 每张图三条 `failed to get image info` | airui 的 `src` 是完整 VFS 路径，没有资源表可映射。图标必须和 `.lua` 平铺在 `/luadb/` 根目录，路径写 `/luadb/xx.png`。plcui 那套（`melsec_hmi_plcui`）能在 XML 里写裸文件名，是因为它有 `luat_plcui_image_path()` 做资源映射，airui 没有 |
| **`mcu.ticks()` 不是毫秒** | 500ms 超时实际等 10 秒才触发，日志上表现为"一帧之后静默很久" | `mcu.ticks()` 是**节拍数**，一格的长度随平台变（Air1603 是 20ms，`mcu.hz()`=50）。直接当毫秒用，时间轴会拉长 20 倍。正解：优先 `mcu.ticks2(1)`（直接给毫秒，`h*1000000+l`），退回 `ticks*1000/mcu.hz()`。init 日志会打"时间基准"，一眼能看出口径 |
| **`uart.setup` 必须传第 8/9/10 参数** | 100% 超时，`超时重试 1/2` 刷屏，偶尔 `checksum` | 完整签名 `uart.setup(id, baud, data_bits, stop_bits, parity, bit_order, buff_size, rs485_gpio, rs485_level, rs485_delay, ...)`。只传前 5 个时 `pin485 = 0xffffffff`，固件不驱动方向脚，**TX 一个字节都上不了 A/B 总线**。见第九章 |
| **发送窗口会回采自己** | 偶发校验错 | 半双工收发器会把发出去的字节灌回 RX。发送前 `uart.rxClear`，窗口内（`(字节数+2)×12` 位）收到的字节全丢 |

另外：`airui.chart` 那套参数（`type/y_min/y_max/point_count/update_mode/line_color/hdiv/vdiv/legend/fill_fade/y_axis`）**全是构造参数**，没有对应的 setter；首序列在创建时自动生成、`id = 1`。本工程已不用 chart，但换回去时注意这点。

## 十一、行为约定

- **通讯中断**：数值显示 `--.-` 并转灰，顶栏显示"通讯中断"，**不会冻结在最后一个值**。
- **输入异常**：AD ≥ 30000 时该通道显示"故障"，不参与报警判断。
- **报警弹窗**：新报警触发瞬间弹模态框（全屏遮罩挡住底层点击），级别色边框 + 大字号当前值 + 两个按钮。`config.alarm.popup_auto_hide` 默认 20 秒自动收起（0 = 必须手动关），期间再来新报警会刷新内容并重新计时。
- **语音播报**：弹窗同时播 TTS「报警，通道二，当前八十二摄氏度」。报警持续期间每 `speech_gap`（默认 10 秒）重播一次，消音 / 复位 / 两路都回落才停。
  - 文案是**每轮现取**的，不是触发时冻结：30.0℃ 触发后升到 31.2，重复播报就念「当前三十一摄氏度」。
  - 温度回落到阈值以下（但仍未跌破回差、记录还挂着"未恢复"）时**自动闭嘴**——屏上继续标着报警是对的，但再念「当前 30 度」就自相矛盾。
  - 从阈值之上跌到之下的那一次，会插播一句「预警已回落，通道一，当前二十九摄氏度」；**同一段报警只播一次**，避免在阈值附近来回抖时反复念。跌破回差正式恢复后播报停，标志位也复位。
  - TTS 念小数会说成"六十八点四"，所以四舍五入到整度；通道用中文数字。
- **消音**：只停声音，不停判断；**新报警到来时自动解除消音**。
- **复位**：未恢复的记录保留并标"已确认"，已恢复的清掉。
- **阈值**：预警与报警强制留 0.5℃ 间隔，改一个会顶开另一个；改完立即生效并落盘。
- **掉电保持**：阈值与报警记录存 fskv，重启后恢复；趋势曲线不保存。

## 十二、离线预览（不用接板子）

开发脚本**不随工程下载，也不放在交付目录里**，单独归档在工作区 `devtools/`：

```
C:\Users\24211\WorkBuddy\2026-11-13-14-22-52\devtools\
├─ render.py        界面离线渲染（lupa + 假 airui → SVG → Edge 截图）
├─ test_fx3u.py     协议层离线自测（桩化 uart/gpio/mcu，验证组帧、解析、重试）
├─ png_single_idat.py  把 PNG 的多个 IDAT 合并成一个（硬件解码器要求）
└─ make_icons.py    图标 SVG → PNG
```

`render.py` 起一个 Lua 运行时（lupa），塞进去一个**只记录不绘制**的假 `airui`，跑的是**真实的 `ui_home.lua`**，把控件树翻成 SVG 再交给 Edge 无头模式截图。

```bash
cd C:\Users\24211\WorkBuddy\2026-11-13-14-22-52
python devtools/render.py            # 五页全出
python devtools/render.py overview   # 只出总览
python devtools/test_fx3u.py         # 协议层自测（不需要板子）
```

`test_fx3u.py` 把 `uart` / `gpio` / `mcu` 全打成桩，验证六件事：构造函数传了 10 个参数且第 8 是 DE 脚、组帧字节正确、发送窗口内的回环被丢弃、真实应答能解析出数值、校验错能识别、超时按 `retry` 次数重发。改完 `fx3u.lua` 先跑它，能挡掉绝大多数低级错误。

输出在 `%TEMP%\uirender\*.png`，归档副本在本工程的 `preview/`。

它验证的是：布局、间距、字号、配色、图元几何、换行与截断。
它验证不了：LVGL 的真实渲染细节（抗锯齿、字体度量）、触摸、时序。

改完界面先跑一遍预览，比烧板子快得多；预览没问题再上机，能省掉大量来回。
