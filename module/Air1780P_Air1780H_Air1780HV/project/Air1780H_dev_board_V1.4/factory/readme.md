# Air1780H V1.4 开发板默认出厂固件

## 项目简介

基于合宙 Air1780H V1.4 开发板 + AirLCD_1000 屏的默认出厂固件，开机即通过板载以太网口联网、采集传感器、定时上报 AirCloud，并通过 320×480 竖屏展示状态。无 iRTU、无本地 web、无外置看门狗（仅内核软狗）。

Air1780H 为 Air780EHM 的“去 4G”版本（Flash 8MB / RAM 8MB），与 Air1780P 一样支持 LCD 及 AirUI。除 SIM1（PIN11-14）、SIM2（PIN62-65）、天线（PIN35）为 NC 外，其余管脚与 Air780EHM 完全兼容，因此本工程以 `Air780EHM` 系列为参考，把 4G 联网替换为板载 CH390H 以太网。V1.4 底板与 Air1780P 工程完全相同。

## 与 Air1780P / Air780EHM 版本的差异

| 项目 | Air780EHM（含 4G） | Air1780H V1.4（本工程） |
|------|--------------------|--------------------------|
| 主控 | Air780EHM（含 4G） | Air1780H（无 4G / 无射频，8MB Flash / 8MB RAM） |
| 联网 | `netdrv_4g`（4G Cat.1） | `netdrv_eth_spi`（CH390H，SPI0） |
| 网络状态 | CSQ 信号强度 + NET 注册状态 | 以太网 READY / CONNECTING + 本机 IP |
| AirCloud 上报 | 含信号强度、LBS 经纬度 | 去掉信号强度与 LBS，保留设备ID/项目名/时间戳/温湿度/VOC/CPU温度 |
| 屏幕 | 信号 / 网络 / 温湿度 / VOC / 设备 / 版本 | 网络 / 地址 / 温湿度 / VOC / 设备 / 版本 |
| 其余（LCD/按键/VOC/485/LED/FOTA） | - | 完全沿用 Air1780P V1.4 工程 |

## 硬件配置

| 组件 | 型号 | 接口 | 引脚 |
|------|------|------|------|
| 主控 | Air1780H | - | - |
| 以太网 | CH390H | SPI0 | 供电使能 GPIO20，片选 GPIO8，DHCP |
| 屏幕 | AirLCD_1000（ST7796） | lcd.HWID_0 | pin_rst=36，GPIO29 控 LCD 电源 + GPIO30 控背光 |
| 按键 | BOOT / PWR | GPIO | GPIO0 / gpio.PWR_KEY |
| VOC | AGS02MA | 硬件 I2C1（0x1A） | PIN66=SDA / PIN67=SCL |
| 温湿度 | 中盛科技气体浓度变送器（RS485 版） | Modbus RTU（UART1） | 485 使能脚 GPIO24 |
| LED | - | GPIO | GPIO27（高电平点亮） |

## 功能特性

- **以太网联网**：`exnetif.set_priority_order` 配置 `ETHERNET = {pwrpin = 20, tp = netdrv.CH390, opts = {spi = 0, cs = 8}}`，DHCP 自动获取 IP；获取 IP 后自动设置 DNS 223.5.5.5 / 114.114.114.114
- **传感器采集**：VOC 空气质量（AGS02MA，硬件 I2C1）+ 485温湿度（Modbus RTU，UART1），默认 60 秒采集一次
- **AirCloud 上报**：excloud TCP 协议，上报设备ID(798)/项目名(802)/时间戳/温度/湿度/VOC/CPU温度
- **云端控制**（tag 19）：`cycle:秒数` 改上报频率、`led:blink|on|off` LED 控制
- **屏幕展示**：320×480 竖屏单页，界面由 AirUI 绘制，展示网络（READY/CONNECTING）、地址（本机 IP）、传感器（TEMP/HUM/VOC）、信息（设备ID/版本）
- **FOTA 升级**：基于 `libfota3`，开机后联网并完成时间同步即启动自动检测，默认 24 小时检测一次；检测到新版本自动下载、自动重启升级。`libfota3` 已内置 `Air1780` 型号分支，无需改动
- **软狗**：内核 `wdt`，超时 9s，3s 喂一次

## 目录结构

```
factory/
├── main.lua                  # 入口：加载驱动 / 业务 / UI
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
│   ├── lcd_drv.lua           # ST7796 320×480 竖屏 + AirUI 初始化（HARDWARE_ENV=DEV_BOARD_780_V1.4）
│   ├── key_drv.lua           # BOOT/PWR 按键
│   ├── netdrv_device.lua     # 网络驱动选择（以太网/PC 模拟器）
│   └── netdrv/
│       ├── netdrv_eth_spi.lua  # CH390H 以太网（SPI0）
│       └── netdrv_pc.lua       # PC 模拟器（socket.ETH0）
├── ui/
│   └── ui_main.lua           # AirUI 单页信息展示（网络/地址/传感器/信息）
└── readme.md
```

## 烧录

1. 用 Luatools 烧录 Air1780H 最新内核固件
2. 将本目录所有 `.lua` 脚本烧录到脚本分区（界面为 AirUI 绘制，不需要额外字库文件）
3. 插上网线（开发板 RJ45 接路由器/交换机，需有 DHCP 服务）
4. 上电后自动运行，屏幕显示单页信息（网络 / 地址 / 温湿度 / VOC / 设备信息）

## 密钥（重要）

`main.lua` 中的 `PROJECT_KEY` 为 AirCloud/FOTA 鉴权共用密钥，当前已使用 Air1780H 项目自己的密钥（具体值见 `main.lua` 中的 `PROJECT_KEY`，不在文档中重复维护）。

如需更换，请在合宙 iot.openluat.com 对应项目下获取新密钥并替换 `main.lua` 中的值。若 `PROJECT_KEY` 为空或含 `TODO`，FOTA 会自动跳过。

## 云端命令

| 命令 | 功能 |
|------|------|
| `cycle:60` | 设置上报频率为 60 秒（最小 5 秒） |
| `led:blink` | LED 闪烁 5 秒 |
| `led:on` | LED 常亮 |
| `led:off` | LED 熄灭 |

## 注意事项

- **以太网**：开发板板载 CH390H，通过 SPI0 连接，GPIO20 为芯片供电使能、GPIO8 为片选。网线需接入带 DHCP 的路由器/交换机；若网络环境无 DHCP，需要另行配置静态 IP。自定义 DNS（223.5.5.5 / 114.114.114.114）在 `IP_READY` 回调中设置，专网/国外网络请按需去掉。
- **485 温湿度传感器**：使用中盛科技气体浓度变送器（RS485 版），默认从站地址 1、波特率 9600；温度寄存器 0x001E（16 位有符号，×0.1℃）、湿度寄存器 0x001F（16 位无符号，×0.1%RH）。接线：传感器 A/B 接开发板 RS485 的 A/B，485 使能脚 GPIO24，传感器供电 8~36V DC。
- **I2C1 总线电源**：V1.4 开发板沿用 V1.3 的 I2C1 供电设计（Camera GPIO2、ES8311 GPIO20、Gsensor GPIO23、LCD GPIO29），代码通过 `exmux` 库在采集前拉高这些电源管脚。注意 `exmux` 库目前只支持板级名 `DEV_BOARD_780_V1.3`，因此 `sensor_app.lua` 中固定调用 `exmux.setup("DEV_BOARD_780_V1.3")`，请勿改成 V1.4。
- **HARDWARE_ENV**：固定为 `"DEV_BOARD_780_V1.4"`，`lcd_drv.lua` 与 `modbus_th_drv.lua` 中已将 V1.4 与 V1.3 并列判断（LCD 电源/背光 GPIO29/GPIO30、485 方向脚 GPIO24），请勿改成 `"DEV_BOARD_V1.4"`，否则会走到默认引脚分支。
- **中文字体**：界面由 AirUI 绘制，中文使用固件内置的 16 号中文点阵主题字体，无需外挂字库文件。
  `lcd_drv.lua` 会尝试加载 hzfont（12~255 号中文），本固件未内置该字库时会打印一条告警并自动回退到主题字体，不影响使用。
  注意：AirUI 的 label 不要传 `font_size`（非 16 号会走 hzfont 分支并回退），本工程所有 label 均使用默认主题字体。
- **屏幕方向**：默认竖屏（direction=0，320×480）。改横屏需将 `lcd_drv.lua` 中 `direction` 改为 1 且 `w/h` 对调。
- **外设范围**：Air1780H 无 4G、无 GNSS、无 WiFi、无音频/蓝牙，默认不含摄像头、外置看门狗；与 Air1780P 一样支持 LCD 及 AirUI，Flash/RAM 为 8MB/8MB。
- **FOTA 升级**：由 `libfota3` 完成，需在合宙 iot.openluat.com 创建项目、生成升级包（本目录脚本整体打包）并发布。`main.lua` 中 `PROJECT_KEY` 必须为真实项目密钥，否则代码会跳过 FOTA 并打印 `PROJECT_KEY 未配置，FOTA 功能跳过`。`VERSION` 必须为 `XXX.YYY.ZZZ` 三段格式，且每次发布需递增。设备无触摸屏，`on_confirm` 已做成自动确认（自动下载 + 自动重启），升级过程中会重启。调试时可发布 `FOTA_CHECK_NOW` 立即检测。
