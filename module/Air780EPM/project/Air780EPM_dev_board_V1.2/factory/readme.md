# Air780EPM V1.2 开发板默认出厂固件

## 项目简介

基于合宙 Air780EPM V1.2 开发板 + AirLCD_1000 屏的默认出厂固件，开机即联网、采集传感器、定时上报 AirCloud，并通过 320×480 竖屏展示状态。无 iRTU、无本地 web、无外置看门狗（仅内核软狗）。

## 硬件配置

| 组件 | 型号 | 接口 | 引脚 |
|------|------|------|------|
| 主控 | Air780EPM | - | - |
| 屏幕 | AirLCD_1000（ST7796） | lcd.HWID_0 | pin_rst=36，GPIO28 控 LCD 电源（无背光） |
| 按键 | BOOT / PWR | GPIO | GPIO0 / gpio.PWR_KEY |
| VOC | AGS02MA | 硬件 I2C1（0x1A） | PIN66=SDA / PIN67=SCL |
| 温湿度 | 中盛科技气体浓度变送器（RS485 版） | Modbus RTU（UART1） | 485 使能脚 GPIO25 |
| LED | - | GPIO | GPIO27（高电平点亮） |

## 功能特性

- **4G 联网**：`netdrv_4g`，自动重连
- **传感器采集**：VOC 空气质量（AGS02MA，硬件 I2C1）+ 485温湿度（Modbus RTU，UART1），默认 60 秒采集一次
- **AirCloud 上报**：excloud TCP 协议，上报信号/设备ID/项目名/时间戳/温度/湿度/VOC/CPU温度/LBS 经纬度
- **云端控制**（tag 19）：`cycle:秒数` 改上报频率、`led:blink|on|off` LED 控制
- **屏幕展示**：320×480 竖屏单页，展示网络（信号/网络）、传感器（温度/湿度/空气质量）、信息（设备/版本）
- **FOTA 升级**：基于 `libfota3`，开机后联网并完成时间同步即启动自动检测，默认 24 小时检测一次；检测到新版本自动下载、自动重启升级。无触摸屏，不做人工确认
- **软狗**：内核 `wdt`，超时 9s，3s 喂一次

## 目录结构

```
factory/
├── main.lua                  # 入口：初始化驱动/业务/UI
├── libfota3.lua              # FOTA 升级库（共享库 script/libs/libfota3.lua）
├── app/
│   ├── app_main.lua          # 加载 netdrv/aircloud/sensor/led/fota
│   ├── aircloud/aircloud_app.lua   # AirCloud 上报 + 下行命令
│   ├── fota/fota_app.lua     # FOTA 升级（自动检测/下载/重启）
│   ├── sensor/
│   │   ├── sensor_app.lua    # VOC + 485温湿度采集
│   │   ├── AirVOC_1000.lua   # VOC 驱动
│   │   └── modbus_th_drv.lua # 485温湿度驱动（Modbus RTU 主站）
│   └── led/led_app.lua       # LED 控制
├── drv/
│   ├── lcd_drv.lua           # ST7796 320×480 竖屏（HARDWARE_ENV=DEV_BOARD_V1.2）
│   ├── key_drv.lua           # BOOT/PWR 按键
│   ├── netdrv_device.lua     # 网络驱动选择（4G/PC）
│   └── netdrv/
│       ├── netdrv_4g.lua
│       └── netdrv_pc.lua
├── ui/
│   └── ui_main.lua           # 单页信息展示（网络/传感器/信息）
├── res/
│   ├── customer_font_16.bin  # 16号中文字库（标签用）
│   └── customer_font_32.bin  # 32号中文字库（标题用）
└── readme.md
```

## 烧录

1. 用 Luatools 烧录 Air780EPM 最新内核固件（LuatOS-SoC Air780EPM 1 号固件）
2. 将本目录所有 `.lua` 脚本 + `res/` 下的 `.bin` 字库文件烧录到脚本分区
3. 上电后自动运行，屏幕显示单页信息（网络 / 温湿度 / VOC / 设备信息）

## 密钥（重要）

`main.lua` 中的 `PROJECT_KEY` 为项目真实密钥（AirCloud/FOTA 鉴权共用），需与合宙 iot.openluat.com 上创建的项目一致：

```lua
PROJECT_KEY = "7eKkhm1uL1OeaBPEGz7MZHbKQsr1s5TV"
```

若密钥为空或含 `TODO`（例如换用其他项目时），FOTA 会自动跳过（AirCloud 上报仍按原逻辑运行）。

## 云端命令

| 命令 | 功能 |
|------|------|
| `cycle:60` | 设置上报频率为 60 秒（最小 5 秒） |
| `led:blink` | LED 闪烁 5 秒 |
| `led:on` | LED 常亮 |
| `led:off` | LED 熄灭 |

## 注意事项

- **485 温湿度传感器**：使用中盛科技气体浓度变送器（RS485 版），默认从站地址 1、波特率 9600；温度寄存器 0x001E（16 位有符号，×0.1℃）、湿度寄存器 0x001F（16 位无符号，×0.1%RH）。接线：传感器 A/B 接开发板 RS485 的 A/B，485 使能脚 GPIO25，传感器供电 8~36V DC。
- **I2C1 总线电源**：V1.2 开发板的 I2C1 总线上挂了 Camera(GPIO2) 和 Gsensor(GPIO23)，代码通过 `exmux` 库（`exmux.setup("DEV_BOARD_780_V1.2")` + `exmux.open("i2c1")`）在采集前拉高这两个电源管脚，否则总线会被拉低导致 VOC 读不到。
- **中文字体**：Air780EPM 的 lcd 核心库**未内置中文字体**，因此通过 `res/` 下的自定义字库补充：
  - 标题「合宙设备」：`customer_font_32.bin`（32 号）
  - 中文标签「信号/网络/温度/湿度/空气质量/设备/版本」：`customer_font_16.bin`（16 号）
  - 数值（数字/英文）：`lcd.font_opposansm16` 内置英文点阵

  字库需覆盖上述所有中文，缺字会显示为空白。自行生成时用 u8g2 字体工具，**输出格式必须选 u8g2 bin、编码选 UTF-8**，点阵尺寸建议取 8 的倍数（16×16 / 32×32）。烧录时务必将 `res/` 下的 `.bin` 一起烧入脚本分区，运行时路径为 `/luadb/customer_font_16.bin`、`/luadb/customer_font_32.bin`。
- **屏幕方向**：默认竖屏（direction=0，320×480）。改横屏需将 `lcd_drv.lua` 中 `direction` 改为 1 且 `w/h` 对调。
- **外设范围**：默认不含摄像头、外置看门狗、GNSS（Air780EPM 无内置 GNSS，定位用 LBS 基站）。
- **FOTA 升级**：由 `libfota3` 完成，需在合宙 iot.openluat.com 创建项目、生成升级包（脚本 + `res/` 字库一起打包）并发布。`main.lua` 中 `PROJECT_KEY` 必须为真实项目密钥，否则代码会跳过 FOTA 并打印 `PROJECT_KEY 未配置，FOTA 功能跳过`。`VERSION` 必须为 `XXX.YYY.ZZZ` 三段格式，且每次发布需递增。设备无触摸屏，`on_confirm` 已做成自动确认（自动下载 + 自动重启），升级过程中会重启。调试时可发布 `FOTA_CHECK_NOW` 立即检测。
