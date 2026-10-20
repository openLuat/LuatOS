# Air780EGP V1.4 开发板默认出厂固件

## 项目简介

基于合宙 Air780EGP V1.4 开发板的默认出厂固件，开机即联网、采集传感器、内置 GNSS 定位、定时上报 AirCloud。无屏幕、无 iRTU、无本地 web、无外置看门狗（仅内核软狗）。

Air780EGP 为 EC7xx 平台（Flash 4MB / RAM 4MB），功能与 Air780EPM 一致，**内部集成 GNSS 与 G-Sensor**；不支持 SD 卡、触摸屏与 LCD（EGP 固件中 `lcd` 与 `libgnss`/`otp` 互斥，本工程需 GNSS+OTP），仅支持 LuatOS 二次开发（不支持 AT 指令）。

固件同时包含出厂产测功能，按 V3 出厂流程开机自动分流。

## 出厂流程（V3）

`main.lua` 上电后按以下顺序判定：

1. `fskv` 中存在 `retest_flag` → 进入**产测模式（返工产测）**
2. OTP1 为空（未写过任何 prodmeta 数据）→ 进入**产测模式（首次产测）**
3. 其他情况 → 进入**正常模式**

产测模式只加载 `prod_test.lua`，不加载按键/业务；正常模式在原业务基础上额外加载 `prod_retest.lua`，仅监听返工指令。

`main.lua` 中 `BOOT_MODE` 可用于调试时强制指定模式：

```lua
local BOOT_MODE = "normal"  -- 当前固定正常模式；量产时改回 "auto" 自动分流
```

取值：`"auto"` 按 V3 自动判定 / `"factory"` 强制产测 / `"normal"` 强制正常模式。

产测数据全部写入 OTP1（`prodmeta`），不写入 flash；移芯 EC7xx 平台在擦写 OTP 前会自动进入飞行模式，写完退出。V3 要求 OTP 不加锁。

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
├── main.lua                  # 入口：V3 开机分流 → 产测模式 / 正常模式
├── prod_test.lua             # 产测模式主程序（USB VUART 指令 + 485/GNSS 测试 + LED + OTP 写号）
├── prod_retest.lua           # 正常模式返工入口（仅 MODEL_RETEST / MODEL_RETEST?）
├── prodmeta.lua              # OTP1 key=value 存储（含 EC 平台飞行模式补丁）
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
4. 首次烧录（OTP1 为空）上电会进入产测模式，完成产测并下发 `TEST_DONE` 后重启进入正常模式

> 内核需包含 `LUAT_USE_LIBGNSS`（`exgnss`）、`otp`（`prodmeta`）等组件，否则产测/定位功能会降级或报错。
> 注意：Air780EGP 官方固件中 `lcd` 与 `libgnss`/`otp` 互斥，含 `lcd` 的固件（如 1/2/7/8 号）没有 GNSS 与 OTP，本工程不使用这类固件。

## 产测模式

### 通道与协议

- 通道：USB 虚拟串口 `uart.VUART_0`，115200 8N1
- 协议：`命令#` 或 `命令,数据#`（以 `#` 结尾）
- 回复：成功 `OK#`，失败 `ERROR#`，查询类命令直接返回值 + `#`
- 命令名不区分大小写（内部统一转大写匹配）；参数原样使用，区分大小写

### 指令表

| 指令 | 功能 | 回复 |
|------|------|------|
| `VERSION#` | 查询固件版本 | `PROJECT_VERSION#` |
| `IMEI#` | 查询 IMEI | `IMEI#` |
| `IMSI#` | 查询 IMSI | `IMSI#` |
| `ICCID#` | 查询 ICCID | `ICCID#` |
| `CSQ#` | 查询信号强度 | `CSQ#` |
| `MUID#` | 查询模组唯一 ID | `MUID#` |
| `VBAT#` | 查询供电电压（mV） | `电压#` |
| `ECNPICFG#` | 查询射频校准标志 | `true#` / `false#` |
| `LED,1#` / `LED,0#` | LED（GPIO27）点亮 / 熄灭 | `OK#` |
| `GPSTEST,1#` | 开启内置 GNSS，NMEA 透传到 USB（并下发 `$CFGTP` 提速到 5Hz） | `OK#` |
| `GPSTEST,0#` | 关闭内置 GNSS | `OK#` |
| `GPSFIX?#` | 查询是否已定位（需先 `GPSTEST,1#`） | `true#` / `false#` |
| `MODEL,型号#` | 写 OTP1 的 `PROD`，写后读回校验 | `OK#` / `ERROR#` |
| `MODEL?#` | 读回 `PROD` | `型号#` |
| `HVERSION,版本#` | 写 OTP1 的 `PCB`，写后读回校验 | `OK#` / `ERROR#` |
| `HVERSION#` | 读回 `PCB` | `版本#` |
| `MODEL_RETEST,CONFIRM#` | 写返工标记并重启 | `OK#` |
| `MODEL_RETEST?#` | 查询返工标记 | `true#` / `false#` |
| `RST#` | 重启设备（重启前先关闭 GNSS） | `OK#` |
| `TEST_DONE#` | 产测完成：关闭 GNSS、删除返工标记，3 秒后重启 | `OK#` |

说明：

- `MODEL` / `HVERSION` 的写入在独立 CONTROL 协程中执行（OTP 擦写需先进入飞行模式，`mobile.flymode` 为同步阻塞调用，不能在串口回调中直接执行）。
- 型号/版本字符串不能为空，且不能包含 `,` 或 `=`。
- `ECNPICFG` 依赖固件开启 `LUAT_USE_MOBILE_ECNPICFG`，未开启时返回 `ERROR#`。
- `GPSTEST` / `GPSFIX?` 依赖固件内置 `exgnss` 库，不可用时 `GPSTEST` 返回 `ERROR#`、`GPSFIX?` 返回 `false#`。
- 内置 GNSS 定位需在开阔处进行，冷启动首次定位通常需要数十秒；产测时建议先 `GPSTEST,1#`，用上位机看 NMEA 或轮询 `GPSFIX?#`。
- V3 流程不对 OTP 加锁，便于返工重写。

### 485 测试

产测模式下 485 常开，无需 USB 指令触发：

- 485_3V3 由 LP5907 常开供电（无 GPIO 开关）
- VREF（GPIO23）由 `main.lua` 统一拉高（模组内部常高，不能拉低）
- GPIO24 → 方向控制（0=接收，1=发送）
- UART1，9600 8N1

测试方法：PC 通过 USB 转 485 连接开发板 A/B，发送 `U485_TEST`，设备回 `485TEST\r\n`。

> V1.4 的 GPIO1（PIN22）已改为 PWM0 蜂鸣器输出，产测代码不再把 GPIO1 当 485 芯片供电拉高。

### 返工流程

正常模式下仍可通过 USB 虚拟串口下发返工指令（`prod_retest.lua` 只响应该指令，不影响业务）：

1. 下发 `MODEL_RETEST,CONFIRM#`（魔法字 `CONFIRM` 区分大小写、去首尾空格后全匹配）
2. 设备回 `OK#`，写入 `retest_flag` 并重启
3. 重启后进入产测模式，可重新执行 `MODEL` / `HVERSION` 等写号
4. 下发 `TEST_DONE#`，删除返工标记，3 秒后重启进入正常模式

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
