# Air1780P V1.4 开发板默认出厂固件

## 项目简介

基于合宙 Air1780P V1.4 开发板 + AirLCD_1000 屏的默认出厂固件，开机即通过板载以太网口联网、采集传感器、定时上报 AirCloud，并通过 320×480 竖屏展示状态。无 iRTU、无本地 web、无外置看门狗（仅内核软狗）。

固件同时包含出厂产测功能，按 V3 出厂流程开机自动分流。

Air1780P 为 Air780EPM 的“去 4G”版本（Flash 4MB / RAM 4MB），除 SIM1（PIN11-14）、SIM2（PIN62-65）、天线（PIN35）为 NC 外，其余管脚与 Air780EPM 完全兼容，因此本工程以 `Air780EPM_dev_board_V1.3` 为蓝本移植，把 4G 联网替换为板载 CH390H 以太网。

## 与 Air780EPM V1.3 版本的差异

| 项目 | Air780EPM V1.3 | Air1780P V1.4（本工程） |
|------|----------------|--------------------------|
| 主控 | Air780EPM（含 4G） | Air1780P（无 4G / 无射频） |
| 联网 | `netdrv_4g`（4G Cat.1） | `netdrv_eth_spi`（CH390H，SPI0） |
| 网络状态 | CSQ 信号强度 + NET 注册状态 | 以太网 READY / CONNECTING + 本机 IP |
| AirCloud 上报 | 含信号强度、LBS 经纬度 | 去掉信号强度与 LBS，保留设备ID/项目名/时间戳/温湿度/VOC/CPU温度 |
| 屏幕 | 信号 / 网络 / 温湿度 / VOC / 设备 / 版本 | 网络 / 地址 / 温湿度 / VOC / 设备 / 版本 |
| 产测 IMEI/IMSI/ICCID/CSQ/ECNPICFG | 实际读取 | 固定回 `ERROR#`（无 4G/无射频） |
| 产测 MUID | IMEI 或模组 ID | `mcu.unique_id()` 十六进制 |
| 其余（LCD/按键/VOC/485/LED/产测写号/FOTA） | - | 完全沿用 |

## 出厂流程（V3）

`main.lua` 上电后按以下顺序判定：

1. `fskv` 中存在 `retest_flag` → 进入**产测模式（返工产测）**
2. OTP1 为空（未写过任何 prodmeta 数据）→ 进入**产测模式（首次产测）**
3. 其他情况 → 进入**正常模式**

产测模式只加载 `prod_test.lua`，不加载 LCD/按键/业务/UI；正常模式在原业务基础上额外加载 `prod_retest.lua`，仅监听返工指令。

`main.lua` 中 `BOOT_MODE` 可用于调试时强制指定模式：

```lua
local BOOT_MODE = "auto"    -- "auto" 自动分流 / "factory" 强制产测 / "normal" 强制正常模式
```

产测数据全部写入 OTP1（`prodmeta`），不写入 flash。Air1780P 无 `mobile` 库，`prodmeta` 中的飞行模式守卫会自动跳过（`if mobile and mobile.flymode`）。V3 要求 OTP 不加锁。

## 硬件配置

| 组件 | 型号 | 接口 | 引脚 |
|------|------|------|------|
| 主控 | Air1780P | - | - |
| 以太网 | CH390H | SPI0 | 供电使能 GPIO20，片选 GPIO8，DHCP |
| 屏幕 | AirLCD_1000（ST7796） | lcd.HWID_0 | pin_rst=36，GPIO29 控 LCD 电源 + GPIO30 控背光 |
| 按键 | BOOT / PWR | GPIO | GPIO0 / gpio.PWR_KEY |
| VOC | AGS02MA | 硬件 I2C1（0x1A） | PIN66=SDA / PIN67=SCL |
| 温湿度 | 中盛科技气体浓度变送器（RS485 版） | Modbus RTU（UART1） | 485 使能脚 GPIO24 |
| LED | - | GPIO | GPIO27（高电平点亮） |

## 功能特性

- **以太网联网**：`exnetif.set_priority_order` 配置 `ETHERNET = {pwrpin = 20, tp = netdrv.CH390, opts = {spi = 0, cs = 8}}`，DHCP 自动获取 IP；获取 IP 后自动设置 DNS 223.5.5.5 / 114.114.114.114
- **传感器采集**：VOC 空气质量（AGS02MA，硬件 I2C1）+ 485温湿度（Modbus RTU，UART1），默认 60 秒采集一次
- **AirCloud 上报**：excloud TCP 协议，上报设备ID(1293)/项目名(1294)/时间戳/温度/湿度/VOC/CPU温度
- **云端控制**（tag 19）：`cycle:秒数` 改上报频率、`led:blink|on|off` LED 控制
- **屏幕展示**：320×480 竖屏单页，界面由 AirUI 绘制，展示网络（READY/CONNECTING）、地址（本机 IP）、传感器（TEMP/HUM/VOC）、信息（设备ID/版本）
- **FOTA 升级**：基于 `libfota3`，开机后联网并完成时间同步即启动自动检测，默认 24 小时检测一次；检测到新版本自动下载、自动重启升级。`libfota3` 已内置 `Air1780` 型号分支，无需改动
- **软狗**：内核 `wdt`，超时 9s，3s 喂一次

## 目录结构

```
factory/
├── main.lua                  # 入口：V3 开机分流 → 产测模式 / 正常模式
├── prod_test.lua             # 产测模式主程序（USB VUART 指令 + 485 测试 + LED + OTP 写号）
├── prod_retest.lua           # 正常模式返工入口（仅 MODEL_RETEST / MODEL_RETEST?）
├── prodmeta.lua              # OTP1 key=value 存储（EC 平台飞行模式守卫，Air1780P 自动跳过）
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

1. 用 Luatools 烧录 Air1780P 最新内核固件
2. 将本目录所有 `.lua` 脚本烧录到脚本分区（界面为 AirUI 绘制，不需要额外字库文件）
3. 插上网线（开发板 RJ45 接路由器/交换机，需有 DHCP 服务）
4. 上电后自动运行，屏幕显示单页信息（网络 / 地址 / 温湿度 / VOC / 设备信息）
5. 首次烧录（OTP1 为空）上电会进入产测模式，完成产测并下发 `TEST_DONE` 后重启进入正常模式

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
| `IMEI#` | 无 4G，固定失败 | `ERROR#` |
| `IMSI#` | 无 4G，固定失败 | `ERROR#` |
| `ICCID#` | 无 4G，固定失败 | `ERROR#` |
| `CSQ#` | 无 4G，固定失败 | `ERROR#` |
| `MUID#` | 查询模组唯一 ID（`mcu.unique_id` 十六进制） | `MUID#` |
| `VBAT#` | 查询供电电压（mV） | `电压#` |
| `ECNPICFG#` | 无射频，固定失败 | `ERROR#` |
| `LED,1#` / `LED,0#` | LED（GPIO27）点亮 / 熄灭 | `OK#` |
| `MODEL,型号#` | 写 OTP1 的 `PROD`，写后读回校验 | `OK#` / `ERROR#` |
| `MODEL?#` | 读回 `PROD` | `型号#` |
| `HVERSION,版本#` | 写 OTP1 的 `PCB`，写后读回校验 | `OK#` / `ERROR#` |
| `HVERSION#` | 读回 `PCB` | `版本#` |
| `MODEL_RETEST,CONFIRM#` | 写返工标记并重启 | `OK#` |
| `MODEL_RETEST?#` | 查询返工标记 | `true#` / `false#` |
| `RST#` | 重启设备 | `OK#` |
| `TEST_DONE#` | 产测完成，删除返工标记，3 秒后重启 | `OK#` |

说明：

- `MODEL` / `HVERSION` 的写入在独立 CONTROL 协程中执行（OTP 擦写耗时，不能在串口回调中直接执行）。
- 型号/版本字符串不能为空，且不能包含 `,` 或 `=`。
- Air1780P 无 4G/无射频，`IMEI` / `IMSI` / `ICCID` / `CSQ` / `ECNPICFG` 固定返回 `ERROR#`，产测工具需按“跳过/不适用”处理。
- V3 流程不对 OTP 加锁，便于返工重写。

### 485 测试

产测模式下 485 常开，无需 USB 指令触发：

- GPIO1 → 485 芯片供电（常开）
- GPIO23 → 485 vref 拉高
- GPIO24 → 方向控制（0=接收，1=发送）
- UART1，9600 8N1

测试方法：PC 通过 USB 转 485 连接开发板 A/B，发送 `U485_TEST`，设备回 `485TEST\r\n`。

### 返工流程

正常模式下仍可通过 USB 虚拟串口下发返工指令（`prod_retest.lua` 只响应该指令，不影响业务）：

1. 下发 `MODEL_RETEST,CONFIRM#`（魔法字 `CONFIRM` 区分大小写、去首尾空格后全匹配）
2. 设备回 `OK#`，写入 `retest_flag` 并重启
3. 重启后进入产测模式，可重新执行 `MODEL` / `HVERSION` 等写号
4. 下发 `TEST_DONE#`，删除返工标记，3 秒后重启进入正常模式

## 密钥（重要）

`main.lua` 中的 `PROJECT_KEY` 为 AirCloud/FOTA 鉴权共用密钥，当前已使用 Air1780P 项目自己的密钥（具体值见 `main.lua` 中的 `PROJECT_KEY`，不在文档中重复维护）。

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
- **外设范围**：Air1780P 无 4G、无 GNSS、无 WiFi、无音频/蓝牙，默认不含摄像头、外置看门狗。
- **FOTA 升级**：由 `libfota3` 完成，需在合宙 iot.openluat.com 创建项目、生成升级包（本目录脚本整体打包）并发布。`main.lua` 中 `PROJECT_KEY` 必须为真实项目密钥，否则代码会跳过 FOTA 并打印 `PROJECT_KEY 未配置，FOTA 功能跳过`。`VERSION` 必须为 `XXX.YYY.ZZZ` 三段格式，且每次发布需递增。设备无触摸屏，`on_confirm` 已做成自动确认（自动下载 + 自动重启），升级过程中会重启。调试时可发布 `FOTA_CHECK_NOW` 立即检测。
