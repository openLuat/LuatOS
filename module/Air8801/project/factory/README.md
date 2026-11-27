# K8801 出厂（factory）整机工程

> 工程名（`PROJECT`）如 `K8801_TTL_RTP_7_1024x600_1`，版本 `001.000.001`。
> 配置驱动架构：**换屏型、换分辨率、换串口电平，只改 `main.lua` 的 `PROJECT` 一行**，
> 其余由 `core/platform_loader.lua` 的 `parse_model()` + `config/air8801_config.lua` 的屏幕 profile 驱动。
>
> 开机进入 AirUI 桌面，从「功能测试」执行检测；结果显示在当前开机的列表上，并写入 CH343 调试日志。
> 引脚依据 `AIR8801_V0_20261117_2100.pdf` 第 1～5 页。

---

## 一、PROJECT 命名规范

```
K8801_<TTL|232>_<LCD|CTP|RTP>_<尺寸>_<宽>x<高>[_<尾段>]
  K8801    : 整机型号
  TTL/232  : 串口电平（TTL 收发器不贴 / 232 收发器实贴，测试时 GPIO12 供电）
  LCD      : 裸屏，板上没有触摸芯片
  CTP      : 电容触摸（GT911）
  RTP      : 电阻触摸（NS2009 四线）
  7        : 屏幕尺寸（寸），当前只做 7 寸
  宽*高     : 1024*600 / 800x480 / 1280x800
  尾段      : 当前只用 -1，原样保留在型号里，程序不解释其含义；省略按 -1
```

`PROJECT` 必须是 ASCII 型号字符串（LuaTools 工程标识；云端 FOTA 也按它鉴权）。
本工程是厂测整包，不走云端 FOTA，故不设 `PROJECT_KEY`。

### 可选型号（7 寸 1024×600）

| PROJECT（`main.lua`） | 屏 | 触摸 | 串口 | profile |
| --- | --- | --- | --- | --- |
| `K8801_TTL_LCD_7_1024x600_1` | 7 寸 1024×600 | 裸屏 | TTL | `1024x600` |
| `K8801_232_LCD_7_1024x600_1` | 7 寸 1024×600 | 裸屏 | RS232 | `1024x600` |
| `K8801_TTL_CTP_7_1024x600_1` | 7 寸 1024×600 | GT911 电容 | TTL | `1024x600` |
| `K8801_232_CTP_7_1024x600_1` | 7 寸 1024×600 | GT911 电容 | RS232 | `1024x600` |
| `K8801_TTL_RTP_7_1024x600_1` | 7 寸 1024×600 | NS2009 四线电阻 | TTL | `1024x600` |
| `K8801_232_RTP_7_1024x600_1` | 7 寸 1024×600 | NS2009 四线电阻 | RS232 | `1024x600` |

当前实物：7 寸 1024×600 电阻触摸 + TTL，首板 = `K8801_TTL_RTP_7_1024x600_1`
（原 `Air8801_7inch_1024x600_Resistive_000_V000`）。`800x480` / `1280x800` 未列入上表，但语法合法：
`config/air8801_config.lua` 的 `panels` 里已有 `800x480` / `1280x800`，直接写
`K8801_TTL_CTP_7_800x480_1` 就能跑。

型号由 `core/platform_loader.lua` 的 `parse_model()` 解析，各段直接落到配置：

| 型号段 | 落到哪 | 界面影响 |
| --- | --- | --- |
| `TTL` / `232` | `cfg.serial.mode` = `ttl` / `rs232` | 功能测试页只出现「TTL 串口」或「RS232 串口」一项 |
| `LCD` | `cfg.touch_mode = "none"` | 跳过触摸初始化，标定项与校准入口消失 |
| `CTP` | `cfg.touch_mode = "capacitive"` | GT911，芯片自带绝对坐标，无需标定 |
| `RTP` | `cfg.touch_mode = "resistive"` | NS2009，首次开机进四点标定 |
| `宽*高` | `cfg.panel` = `1024x600` / `800x480` / `1280x800` | 分辨率、字号、RGB 时序 |
| `-1` | 不参与解析 | 只作为型号尾段原样保留，程序不解释其含义；当前只接受 `-1`，其他尾段后续再加 |

裸屏（`LCD`）没有触摸芯片：`air8801_touch.enabled()` 为 false，`boot_ui` 跳过 GT911/NS2009 初始化，
「触摸校准」项与左栏校准入口一起消失，其余测试项照常。同一份代码覆盖裸屏 / 电容 / 电阻三种整机，
不靠运行期菜单让人猜硬件。

型号不合法（如旧的 `Air8801_7inch_1024x600_Resistive_000_V000`）时回退出厂默认屏，日志打
`PROJECT 是旧 Air8801 命名，请改成 K8801 型号`。屏仍能点亮，但型号与实装不符，产线核对日志里的 `型号解析` 一行。

### 串口电平由型号决定

J101 同一组引脚既能走 TTL 也能走 RS232，单板只贴一条支路，所以电平写在型号里、不放进界面：

| 型号段 | 硬件 | 测试期间 GPIO12 | 功能测试页 |
| --- | --- | --- | --- |
| `TTL` | J101-2/3 直出 3.3 V TTL，收发器不贴 | 保持低 | 只显示「TTL 串口」 |
| `232` | U232 与外围实贴，接电脑串口 / USB-RS232 | 拉高供电 | 只显示「RS232 串口」 |

界面上永远只有一项，结果统一记在 `serial`，换型号不会多出第二行。开机日志
`串口通道 ttl J101 直出 TTL · GPIO12 保持低` 用来核对实机。

---

## 二、硬件与固件环境

| 项目 | 规格 |
| --- | --- |
| 主控 / 模组 | **K8801 V0**（原 Air8801 V0），芯片 **Air1101 / CCM4211**（须 CCM4211 专用底包，非 Air1101 通用固件；启动时会校验 `hmeta.chip()`） |
| 屏接口 | RGB565 40 针（J200），`LCD_DISP = GPIO15`，`LCD_3V3` 随 VBAT 上电，背光由 PWM3 驱动 |
| 首板屏 | QT-TPM169-7.0，7 英寸 1024×600，像素时钟 51 MHz |
| 屏型覆盖 | 裸屏（`LCD`，无触摸）/ 电容（`CTP`，GT911）/ 电阻（`RTP`，NS2009），由 `PROJECT` 的屏型段决定 |
| 触摸（电阻） | 纳芯微 **NS2009**，四线电阻，I²C1（SDA GPIO38 / SCL GPIO39），PENIRQ = GPIO51（WAKEUP），A0 = GPIO14（默认拉低 → 地址 0x48），需四点标定 |
| 触摸（电容） | **GT911**，I²C1，INT = GPIO51，RST = GPIO14，自带绝对坐标、无需标定 |
| 调试 / 下载 | USB2 Type-C 经 CH343K，hzadb CUSTOM `0x40` 通道当产测串口用 |
| 内核固件 | CCM4211 专用底包，LuaTools 选「底层和脚本」烧录 |
| 依赖库 | `airui`（LVGL GUI）、`display`（RGB 帧缓冲）、`tp`（NS2009 标定 / GT911）、`fskv`（面板与标定存档）、`spi` / `fatfs`（SD）、`uart`、`pwm`、`hzadb`（调试口） |
| 存储与容量限制 | 脚本与资源受底包分区大小约束（超限表现为整包刷不进/分区报错）。图片资源走 `/luadb`，按真机 PNG 门槛：单张 `宽×高 ≤ 262144` 且必须单 IDAT 块 |

---

## 三、目录结构

```
Air8801/
├── project/
│   └── factory/                # 出厂整机工程，Luatools 直接选这个目录
│       ├── README.md
│       ├── main.lua            # 唯一入口：设 PROJECT（K8801 型号，含屏型与电平），串联 5 阶段初始化
│       ├── fruit.hzv           # 视频 small 档（336×224 / 105 帧 / 1.17 MiB，4/5 寸屏用）
│       ├── fruit_hd.hzv        # 视频 hd 档（828×552 / 68 帧 / 2.04 MiB，7 寸以上屏用）
│       ├── app/
│       │   ├── app_main.lua            # 业务层总装：按顺序 require 设置项 / 文件管理
│       │   ├── debug/air8801_debug.lua # 调试口指令（hzadb CUSTOM 0x40：PING / PANEL / TP_CAL）
│       │   ├── factory/air8801_factory.lua # 功能测试流程：分步下发、结果汇总、写日志
│       │   ├── common/status_provider_app.lua # 状态栏时间源
│       │   ├── file_manager/file_manager_app.lua # 文件管理业务层
│       │   └── settings/               # 设置项业务层（关于/显示/存储/内存/时间）
│       ├── config/air8801_config.lua   # 屏幕 profile（分辨率/时序/字号）+ 触摸 + 板级引脚（唯一硬件数据源）
│       ├── core/platform_loader.lua    # PROJECT → parse_model() → air8801_config.load + 板级输出上电
│       ├── drv/
│       │   ├── lcd/
│       │   │   ├── lcd_common.lua      # LCD/TP 驱动加载 + AirUI 分段初始化 + 密度缩放
│       │   │   └── lcd_display_rgb.lua # RGB 屏驱动（display.init 分配 FB）
│       │   ├── tp/air8801_touch.lua    # NS2009 / GT911 统一入口 + 电阻标定存档
│       │   └── periph/air8801_board.lua# 背光 PWM3 / 蜂鸣器 / 板级输出（RS232_EN、SD_EN）
│       ├── shared/                     # exwin / hzadb / factory_hzadb / sys 共享库
│       ├── ui/                         # 界面层：boot_ui / idle_win / 功能测试页 / 设置页 / 视频页
│       └── res/                        # 图片资源（桌面图标、logo）
└── tools/                      # 开发工具，**不在烧录目录里**
    ├── hzv_mini.py             # 生成 project/factory/ 下的 fruit.hzv 与 fruit_hd.hzv
    ├── fruit_full.hzv          # 原始片 480×320 / 1.91 MiB，仅作压缩输入
    └── serial_echo.py          # 串口回传上位机：收到即回发，配合 TTL/RS232 串口测试
```

> **`tools/` 必须在 `factory/` 外面。** Luatools 按「所选目录」整体打包，不读 INI 清单。
> 把 `tools/` 放进 `factory/` 会把 1.91 MiB 的原始片一起编进脚本区，
> 4 MiB 分区立刻报「文件总数据量超过固件脚本区空间」。当前烧录目录合计 3.7 MiB。

---

## 四、屏幕与触摸怎么选（优先级）

1. **调试口 `PANEL,<profile>,<touch>#` 写进 fskv 的临时覆盖**（重启仍生效）
   —— 只用于 bring-up 阶段试例外屏。出厂前必须执行 `PANEL,RESET#` 清掉，否则整机型号与实装屏对不上。
   `<touch>` 接受 `resistive` / `capacitive` / `none`（裸屏）。
2. **`main.lua` 的 `PROJECT`** 经 `parse_model()` 解析出的屏 + 触摸 + 串口电平 —— 正常量产只走这一条。
3. 两者都无效 → 回退出厂默认（7 寸 1024×600 电阻屏 + TTL）并打 warn。

整包按当前配置初始化 GT911 电容触摸或 NS2009 电阻触摸；裸屏（`LCD` 型号）不初始化触摸芯片。
电容模式将 GPIO14 拉低 20 ms，配置 I²C1，再由核心库执行 GT911 复位、识别和 GPIO51 下降沿中断绑定；
电阻模式保持 TP2 复位，并恢复已有电阻标定。

### 调试口指令（hzadb CUSTOM 0x40）

修改配置前可用 `PANEL?#` 核对当前值，即使画面或触摸尚未适配也可以在调试口修改。

| 指令 | 结果 |
| --- | --- |
| `PING#` | 应答 `PONG#`，验证 CH343 的双向调试链路 |
| `PANEL?#` | `PANEL=<profile>,<touch>,PROJECT=<整机型号>,SOURCE=project\|fskv` |
| `PANEL,1024x600,resistive#` | 保存首板电阻屏配置，回 `PANEL=SAVED,REBOOT#` 后重启 |
| `PANEL,800x480,resistive#` | 保存 800×480 电阻屏，回 `PANEL=SAVED,REBOOT#` 后重启 |
| `PANEL,5in,capacitive#` / `PANEL,7in,capacitive#` | 切换 5 寸 / 7 寸 GT911 电容屏，保存并重启 |
| `PANEL,9in,capacitive#` / `PANEL,10in,capacitive#` | 切换 9 寸 / 10 寸 GT911 电容屏，保存并重启 |
| `PANEL,RESET#` | 清掉调试口覆盖，回到 `PROJECT` 出厂配置，回 `PANEL=RESET,REBOOT#` 后重启 |
| `TP_CAL#` / `TP_CAL?#` | 启动电阻标定 / 查询 `RUNNING`、`SAVED` 或失败状态 |

> `SOURCE=project` 表示按 `PROJECT` 出厂配置运行；`SOURCE=fskv` 表示被调试口覆盖，出厂前用 `PANEL,RESET#` 清掉。

### 首板接线（电阻屏）

| 秦唐触摸 FPC | Air8801 TP1 |
| --- | --- |
| 1 · X− | 3 · XN |
| 2 · Y− | 4 · YN |
| 3 · X+ | 1 · XP |
| 4 · Y+ | 2 · YP |

电阻标定按分辨率保存（fskv 键 `air8801_cal_<profile>`）。更换同分辨率面板后从「触摸 → 重新标定」重做。

---

## 五、屏参配置

| 屏参 profile | 分辨率 | 像素时钟 | 适用面板 |
| --- | --- | --- | --- |
| `1024x600` | 1024 × 600 | 51 MHz | 首板 QT-TPM169-7.0，按该 LCD 规格核对 |
| `800x480` | 800 × 480 | 33 MHz | 0700A001 / HX8264 |
| `480x272` | 480 × 272 | 15 MHz | 4.3 寸工装屏，按实装规格核对 |
| `5in` | 800 × 480 | 50 MHz | 5 寸电容屏 |
| `7in` | 1024 × 600 | 50 MHz | 7 寸电容屏 |
| `9in` | 1024 × 600 | 50 MHz | 9 寸电容屏 |
| `10in` | 1024 × 600 | 50 MHz | 10 寸电容屏 |

四档电容配置共用时序 HBP/HSW/HFP = 140/20/160、VBP/VSW/VFP = 20/3/12，并按尺寸设置 UI 密度。
具体面板的像素时钟、前后沿和采样边沿以实装规格为准。

### Air8603 屏幕兼容性

按两板原理图第 3 页核对，Air8603 P1 与 Air8801 J200 的 40 针 LCD 主信号同脚。1/2 为 LED_K/LED_A，
3/29/36 为地，4 为 3.3 V，30～34 为 CLK/DISP/HSYNC/VSYNC/DE。两板使用 RGB565 高位数据，Air8603 的 RGB 低位脚留空，
Air8801 在 5～7、13～14、21～23 通过 0 Ω 电阻复制部分高位。P1 的 37～40 留空，J200 的 37～40 接 XP/YN/XN/YP。
电容屏接入 J200 前核对 37～40 为 NC，以及排线间距、触点面和背光规格。

两板 TP2 的 1～6 脚均为 RESET、3.3 V、GND、INT、SDA、SCL。Air8603 图中四个外部上拉为 4.7 kΩ，Air8801 V0 为 47 kΩ。
若电容屏上电后无应答，先查 TP2 上的 I²C 电平、上升沿及复位时序。电容模式使用 TP2，电阻模式使用 TP1 或 J200 的电阻触摸四线。
TP1/J200 和 TP2 共用 WAKEUP 中断，按当前模式接一套触摸。

Air8603 的 50 针 J2 为屏供 AVDD、VGH、VGL、VCOM。Air8801 的 J200 缺这些偏置电源和相应针位，
AirLCD_1070、1090、1100 等需要这些偏置的原版屏需带供电和针位转换的转接板。带 SPI 初始化线的 5 寸 NV3052C、
ST7701S 方案也需要额外硬件连线。尺寸配置用于针位符合 J200、3.3 V 供电、免 SPI 初始化的 RGB 屏。
[Air8603 显示接口说明](https://docs.openluat.com/air8603/product/)

---

## 六、烧录及首次上板

1. 根据屏厂提供的 LCD 针位表核对电源、背光极性、RGB 和控制脚，并确认排线间距、触点面及 Pin 1 方向。核对通过后断电接 J200。当前总成图提供 40 针外形和分辨率，完整针位和 RGB 时序待确认。
2. 将独立触摸排线按上表转接到 TP1。触摸电极由板载 NS2009 驱动，TP1 信号脚无需外加 5 V。
3. J101-1 接板上标注的 5–12 V 输入，J101-4 接 GND。USB2 Type-C 经 CH343K 连接电脑，用于下载和日志。LuaTools 载入 Air8801 的 CCM4211 厂测整包，选「底层和脚本」下载；脚本目录选本目录 `Air8801/project/factory/`（`tools/` 不要一起加）。只改脚本时添加 `main.lua`、`fruit.hzv` 与 `app/`、`config/`、`core/`、`drv/`、`shared/`、`ui/`、`res/`。
4. 检查冷启动出图，依次按住并松开四个标定十字。保存后依次跑五色显示、两档背光和九点触摸，再重启确认标定恢复。图纸标注的背光亮度测试条件为 60 mA，K8801 V0 按原理图标称约 40 mA，首板按实际背光亮度验收。
5. 出厂前核对 `PANEL?#` 的 `SOURCE=project`，且 `PROJECT` 与实际实装的屏、触摸一致。

---

## 七、台架测试

| 项目 | 原理图及验收 |
| --- | --- |
| RGB 显示 | 第 3 页 J200，GPIO15 为 LCD_DISP，LCD_3V3 随 VBAT 上电。依次查看红、绿、蓝、白、黑，目测缺色、花屏和亮点后判定。 |
| 背光 | 第 3 页 JW1160，PWM3 经 BL 驱动。进页面分别切换 20% 和 40%，确有亮度变化后确认，离开页面恢复设定亮度。 |
| 电阻触摸 | 第 3 页 TP1 和 U101，I²C1，WAKEUP/GPIO51 为 PENIRQ。R218 默认把 A0 接地，NS2009 地址为 0x48。四点标定后依次测四角、四边和中心，九点全部响应才通过，再重启确认标定恢复。 |
| 电容触摸 | 第 3 页 TP2，I²C1，GPIO14 复位，WAKEUP/GPIO51 为中断。切换到电容配置并重启后执行同一套九点测试。 |
| 蜂鸣器 | 第 1 页 D120、Q440，PWM1/GPIO65 播放约 180 ms 短音。听到后点「通过」，测试结束 GPIO65 回到低电平。 |
| SD/TF | 第 1 页 J100，SPI1 GPIO8/9/10/11 为 CS/CLK/MISO/MOSI，GPIO74 高电平使能 SD_3V3。插 FAT 格式卡，写入、读回比对并删除 8192 字节临时文件，最后卸载、关闭 SPI 和供电。挂载失败可重插后重测。 |
| SPI Flash | 第 5 页 U200 W25Q32，SPI6。向根文件系统新建临时文件，写入、读回比对并删除 8192 字节。 |
| 串口回传 | 第 4 页 J101，通道由型号里的 `TTL` / `232` 段决定，功能测试页只出现对应的一项：<br>`TTL` 型号：J101-2 板端 TX / J101-3 板端 RX 接 3.3 V TTL 上位机（USB-TTL 小板），参考地 J101-4，测试期间 GPIO12 保持低，界面显示「TTL 串口」；<br>`232` 型号：确认 U232 与收发支路实贴、R246/R247 到 R428/R429 的 TTL 旁路断开后，RS232 侧接电脑串口或 USB-RS232，界面显示「RS232 串口」，测试期间 GPIO12 拉高给收发器供电。 |

**串口项改成和电脑回传，不再需要短接 TX/RX 的工装**，一轮流程只有三步：

1. 点「发 3 字节」，设备经 UART2（9600 8N1）发出 3 个字节 `A8K`；
2. 在电脑上把这 3 个字节发回（串口助手手敲发送，或用 `../tools/serial_echo.py`
   自动回显：`pip install pyserial` 后 `python serial_echo.py COM5`）；
3. 设备 10 s 内收到 `A8K` 即判通过。

发出后界面只提示一次「已发 A8K，请在 10 s 内回传」，等待期间不再刷新；日志也只有两行
（`串口已发 TTL A8K 等上位机回传 10s` 与最终结果）。判定只看「3 字节是否出现在回传数据里」，所以电脑端多发
回车、带提示符都不影响。超时报「10s 未收到回传」，收到但不是 `A8K` 报「收到 N 字节但不是 A8K」，
后者查大小写、波特率与校验位。

---

## 八、新增机型（同芯片换屏）

型号是**解析式**的，不是映射表，所以分两种情况：

**A. 换屏型 / 换电平（分辨率不变）—— 不改任何代码**，只改 `PROJECT`：

```lua
PROJECT = "K8801_232_CTP_7_1024x600_1"   -- 232 电平 + 电容触摸
```

**B. 换分辨率 —— 只补 profile**：

1. `config/air8801_config.lua` 的 `panels` 加一份 profile（`w/h/pclk_hz/inches/font`，
   电容屏再加 `timing` 与 `touch = "capacitive"`）；
2. `main.lua` 的 `PROJECT` 直接写新型号（如 `K8801_TTL_CTP_7_800x480_1`），
   `parse_model()` 会自动把 `800x480` 转成 profile 键 `800x480`；
3. `main.lua` 头部「当前可选型号」表补一行；
4. 上电看日志 `型号解析` / `面板就绪` 两行，确认 `panel` / `touch` / 电平与实装一致。

> 型号语法不对、或分辨率在 `panels` 里没有 profile 时，`parse_model()` 返回 nil，
> 回退出厂默认屏并打 warn —— 不会黑屏，但产线必须核对该 warn。

---

## 九、底包说明

- 底包必须是 CCM4211 专用固件（`core/platform_loader.lua` 启动时校验 `hmeta.chip() == "CCM4211"`，否则打
  `Air8801 需要 CCM4211 底包` 并停在上电阶段）。
- 烧录用 LuaTools 选「底层和脚本」下载整包，脚本目录选本目录；日常改脚本只添加 `main.lua`、`fruit.hzv` 与 `app/`、`config/`、`core/`、`drv/`、`shared/`、`ui/`、`res/`，不动底包。
- `tools/` 是开发工具目录，整目录不参与烧录：`fruit_full.hzv`（1.91 MiB 原始片）和两个 Python 脚本都不要加进去。换片或改画质在 `Air8801/` 下跑 `python tools/hzv_mini.py`，一次生成 `fruit.hzv`（336×224，4/5 寸）与 `fruit_hd.hzv`（828×552，7 寸以上）两份；脚本末尾会打印「固件校验: PASS/FAIL」，FAIL 不要烧。
- 两份视频按屏宽自动挑：`ui/video_win.lua` 的 `asset_names()` 在屏宽 ≥ 1024 时优先 `fruit_hd.hzv`，否则优先 `fruit.hzv`；两支互为兜底，只烧一支也能播。
- 脚本区容量以 Luatools 下载结束那行 `脚本区总空间:4096KB,已使用xxxxKB` 为准（本机 Air1601_A10 底包实测 4096KB），当前工程连同两份视频约 3.6 MiB。

> 整包文件名里的 `001.000.001` 是 `VERSION`，不是 `PROJECT`；换机型后建议同步重打包，避免整包名与整机型号脱节。

---

## 十、故障排除

1. **日志有 `PROJECT 不是合法 K8801 型号，回退出厂默认屏` 或 `PROJECT 是旧 Air8801 命名…`**：
   型号语法写错了（漏段、用了旧命名、或分辨率在 `panels` 里没有 profile）。
   按本文件第一节改成标准型号，如 `K8801_TTL_RTP_7_1024x600_1`；不改也能开机，但屏/触摸/电平都按默认跑。
2. **日志有 `调试口面板覆盖生效，与 PROJECT 出厂配置不一致`**：fskv 里残留 bring-up 阶段的面板覆盖。
   调试口发 `PANEL,RESET#` 清掉并重启，`PANEL?#` 应回到 `SOURCE=project`。
3. **裸屏型号标定项不见了**：正常。`LCD` 型号 `touch_mode = "none"`，`boot_ui` 不初始化触摸，
   功能测试页的「触摸校准」显示「无触摸」。若实装的是触摸屏，说明型号屏型段写成了 `LCD`。
4. **屏不亮**：先看有没有 `板级输出初始化失败` / `RGB 初始化失败`；确认 CCM4211 底包（`Air8801 需要 CCM4211 底包` 说明刷错固件）、J200 接线与背光 PWM3。
5. **触摸无响应**：电阻查 TP1 转接、NS2009 地址 0x48、PENIRQ=GPIO51；电容查 TP2 的 I²C 电平、上拉（47 kΩ）、GPIO14 复位时序。
6. **触摸坐标错乱 / 上下颠倒**：电阻屏未完成四点标定（NS2009 芯片原点在左下），进「触摸 → 重新标定」；电容屏无此问题。
7. **换分辨率后触摸整体偏移**：旧标定按 profile 分开存（`air8801_cal_<profile>`），换 profile 后需重标一次。
8. **画面花屏 / 条纹**：按实装屏规格书核对 profile 里的 `pclk_hz` 与 HBP/HSW/HFP、VBP/VSW/VFP；电容四档共用同一套时序。
9. **整包刷不进去 / 分区报错**：脚本或根文件系统超出底包分区，删资源或按底包分区重新打包后再烧。
10. **串口回传项报「10s 未收到回传」**：先确认那 3 个字节 `A8K` 真的发回了（不是只在电脑屏幕上看设备发来的内容），
   再看 J101-2/3 是否与上位机 RX/TX 交叉接、是否共地；RS232 型号还要确认 U232 实贴、GPIO12 能拉高。
11. **串口回传项报「收到 N 字节但不是 A8K」**：字节被改写，查上位机的波特率 / 校验位 / 停止位
   （应 9600 8N1）与是否开了流控；RS232 型号再查收发器电平与线缆长度。
