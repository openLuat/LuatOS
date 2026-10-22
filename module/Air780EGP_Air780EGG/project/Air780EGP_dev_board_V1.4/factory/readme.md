# Air780EGP V1.4 开发板默认出厂固件

## 项目简介

基于合宙 Air780EGP V1.4 开发板的默认出厂固件，开机即联网、采集传感器、内置 GNSS 定位、定时上报 AirCloud。无屏幕、无 iRTU、无本地 web、无外置看门狗（仅内核软狗）。

Air780EGP 为 EC7xx 平台（Flash 4MB / RAM 4MB），功能与 Air780EPM 一致，**内部集成 GNSS 与 G-Sensor**；不支持 SD 卡、触摸屏与 LCD（EGP 固件中 `lcd` 与 `libgnss`/`otp` 互斥，本工程需 GNSS+OTP），仅支持 LuatOS 二次开发（不支持 AT 指令）。

## 硬件配置

| 组件 | 型号 | 接口 | 引脚 |
|------|------|------|------|
| 主控 | Air780EGP（内置 GNSS + G-Sensor） | - | GPIO23=Vref（模组内部常高，需保持）；WAKEUP2 内部占用 |
| 按键 | BOOT / PWR | GPIO | GPIO0 / gpio.PWR_KEY |
| VOC | AGS02MA | 硬件 I2C1（0x1A） | PIN66=SDA / PIN67=SCL |
| 温湿度 | 中盛科技气体浓度变送器（RS485 版） | Modbus RTU（UART1） | 485 方向脚 GPIO24（PIN20） |
| LED | - | GPIO | GPIO27（PIN16，高电平点亮） |
| 蜂鸣器 | - | PWM0 | PIN22 = GPIO1（**不可再用于 485 供电**） |

模组内部资源说明：

- 内置 GNSS 固定 **UART2 / 115200**，电源轨道 `pm.power(pm.GPS)`，`exgnss.setup` 无需传 `gnss_volgpio`。
- **GPIO23**：模组内部一直输出高电平，作默认 Vref 使用，为板载上拉电阻（SIM 检测 / USIM2_CLK）提供参考电压，必须全程保持高电平（`main.lua` 中 `gpio.setup(23, 1)`）。
- **WAKEUP2（PIN79）**：模组内部已用作 G-Sensor 中断，不可复用。
- 无 SD 卡（`SPI_CS1`/PIN97 空置）；V1.4 的 GPIO29/GPIO30 为孤立网络，未接外设。
- 无 LCD：EGP 固件中 `lcd` 库与 `libgnss`/`otp` 库不在同一固件内（互斥），本工程需要 GNSS 与 OTP，故不加载 LCD。

## 功能特性

- **4G 联网**：`netdrv_4g`，自动重连
- **定位**：内置 GNSS 优先（`exgnss`，开机常开）；未定位时自动回退 LBS 基站定位（`lbsLoc2`）。上报内容为 ASCII `%.6f` 经纬度 + `LOCATION_METHOD`（2=GNSS，1=LBS）
- **传感器采集**：VOC 空气质量（AGS02MA，硬件 I2C1）+ 485温湿度（Modbus RTU，UART1），默认 60 秒采集一次
- **AirCloud 上报**：excloud TCP 协议，上报信号/设备ID/项目名/时间戳/温度/湿度/VOC/CPU温度/经纬度/定位方式
- **云端控制**（tag 19）：`cycle:秒数` 改上报频率、`led:blink|on|off` LED 控制
- **FOTA 升级**：基于 `libfota3`，开机后联网并完成时间同步即启动自动检测，默认 24 小时检测一次；检测到新版本自动下载、自动重启升级。无触摸屏，不做人工确认
- **软狗**：内核 `wdt`，超时 9s，3s 喂一次

## 目录结构

```
factory/
├── main.lua                  # 入口：硬件初始化 + 加载按键/业务
├── libfota3.lua              # FOTA 升级库（共享库 script/libs/libfota3.lua）
├── app/
│   ├── app_main.lua          # 加载 netdrv/aircloud/sensor/led/fota
│   ├── aircloud/aircloud_app.lua   # AirCloud 上报 + 下行命令 + GNSS/LBS 定位
│   ├── fota/fota_app.lua     # FOTA 升级（自动检测/下载/重启）
│   ├── sensor/
│   │   ├── sensor_app.lua    # VOC + 485温湿度采集
│   │   ├── AirVOC_1000.lua   # VOC 驱动
│   │   └── modbus_th_drv.lua # 485温湿度驱动（Modbus RTU 主站）
│   └── led/led_app.lua       # LED 控制
├── drv/
│   ├── key_drv.lua           # BOOT/PWR 按键
│   ├── netdrv_device.lua     # 网络驱动选择（4G/PC）
│   └── netdrv/
│       ├── netdrv_4g.lua
│       └── netdrv_pc.lua
└── readme.md
```

## 烧录

1. 用 Luatools 烧录 Air780EGP 内核固件（LuatOS-SoC Air780EGP 内核，需含 `libgnss` 与 `otp` 的版本，如 103/104/105/106 号）
2. 将本目录所有 `.lua` 脚本烧录到脚本分区
3. 上电后自动运行（无屏幕，运行日志通过 USB 虚拟串口查看）

> 内核需包含 `LUAT_USE_LIBGNSS`（`exgnss`）等组件，否则定位功能会降级或报错。
> 注意：Air780EGP 官方固件中 `lcd` 与 `libgnss`/`otp` 互斥，含 `lcd` 的固件（如 1/2/7/8 号）没有 GNSS 与 OTP，本工程不使用这类固件。

## 密钥（重要）

`main.lua` 中的 `PROJECT_KEY` 供 AirCloud / FOTA 鉴权共用，当前配置为 Air780EGP V1.4 项目的密钥：

```lua
PROJECT_KEY = "u6cQtTkP2xcDZSARC9cwD7x2iWSFP7vz"
```

若 `PROJECT_KEY` 为空或含 `TODO`，FOTA 会自动跳过。

## 云端命令

| 命令 | 功能 |
|------|------|
| `cycle:60` | 设置上报频率为 60 秒（最小 5 秒） |
| `led:blink` | LED 闪烁 5 秒 |
| `led:on` | LED 常亮 |
| `led:off` | LED 熄灭 |

## 注意事项

- **485 温湿度传感器**：使用中盛科技气体浓度变送器（RS485 版），默认从站地址 1、波特率 9600；温度寄存器 0x001E（16 位有符号，×0.1℃）、湿度寄存器 0x001F（16 位无符号，×0.1%RH）。接线：传感器 A/B 接开发板 RS485 的 A/B，方向脚 GPIO24，传感器供电 8~36V DC。
- **I2C1 总线电源**：V1.4 开发板的 I2C1 总线上挂了 Camera(GPIO2) 与 ES8311(GPIO20)，`sensor_app.lua` 开始采集前直接 `gpio.setup` 拉高这两个电源脚，否则总线会被拉低导致 VOC 读不到。GPIO23 为模组内部常高 Vref，由 `main.lua` 全局拉高，不参与总线电源管理。
- **定位**：内置 GNSS 开机即由 `aircloud_app.lua` 打开并保持常开；上报时 GNSS 已定位则用 GNSS 经纬度（`LOCATION_METHOD=2`），否则回退 LBS 基站定位（`LOCATION_METHOD=1`）。无定位数据时不上报经纬度字段。
- **外设范围**：Air780EGP 内置 GNSS + G-Sensor；**无 SD 卡、无触摸屏、无 LCD、不支持 VoLTE**，仅支持 LuatOS 二次开发（不支持 AT 指令）。V1.4 的 GPIO29/GPIO30 为孤立网络，未接外设。
- **FOTA 升级**：由 `libfota3` 完成，需在合宙 iot.openluat.com 创建项目、生成升级包（脚本打包）并发布。`main.lua` 中 `PROJECT_KEY` 必须为真实项目密钥，否则代码会跳过 FOTA 并打印 `PROJECT_KEY 未配置，FOTA 功能跳过`。`VERSION` 必须为 `XXX.YYY.ZZZ` 三段格式，且每次发布需递增。设备无触摸屏，`on_confirm` 已做成自动确认（自动下载 + 自动重启），升级过程中会重启。调试时可发布 `FOTA_CHECK_NOW` 立即检测。
