# 8301 出厂固件（Air8301_Factory）

基于 **Air8301（主控 Air8000W，4.3 寸 ST6201 屏 + GT911 触摸）** 的出厂固件工程，打通
「继电器控制 → 网口/485 数据服务 → 内置网页 → 触屏本地操作 → 上云 → 远程运维 → FOTA」端到端链路。

- 项目名（PROJECT）：`Air8301_Factory`
- 项目版本（VERSION）：`001.999.000`
- 云服务：合宙 AirCloud（`excloud` 扩展库 / TCP，iot.luatos.com）
- 定位服务：airlbs（多基站 + 多 WiFi，收费服务）
- UI 框架：airui + exwin

---

## 一、功能模块介绍

1、`main.lua`：主程序入口，定义 PROJECT / VERSION，`require "exwin"` 与各功能模块，仅含 require 与 `sys.run()`；

2、`board_init.lua`：8301 上电时序（485 供电、LCD 使能/复位、蜂鸣器预置），并处理恢复出厂设置；

3、`net_config.lua`：网络配置管理（fskv 持久化）——设备名、NTP、时区、WiFi STA / AP、双网口静态 IP、网卡优先级；

4、`net_drv.lua`：多网融合驱动，双 CH390H 以太网静态 IP（含中断引脚）+ WiFi STA + WiFi AP + 4G 统一管理，发布网络状态消息；

5、`netdrv_device.lua`：网络驱动选择入口；

6、`net_watchdog.lua`：网络业务看门狗，多源喂狗，超时兜底判定网卡存活后才软件重启；

7、`time_sync.lua`：NTP 授时（全工程唯一授时点）；

8、`comm_core.lua`：Modbus RTU 主站公共封装层，提供建站、原始帧读写（0x01 / 0x05 / 0x0F）、CRC16-Modbus 组帧与**自校验**、总线互斥与重试；

9、`relay_ctrl.lua`：4 路继电器控制（非隔离口 UART11 主站），单路开/关/翻转、全开/全关、状态回读；**路数唯一配置源 `CH_COUNT`**；

10、`rtu_slave_regmap.lua`：统一寄存器映射表（数据中枢），Modbus RTU 从站（隔离口 UART1）+ 提供寄存器读写回调；

11、`tcp_slave.lua`：网口2 Modbus TCP 从站（192.168.1.185:502），复用同一份寄存器表与回调；

12、`tcp_modbus_master.lua`：网口1 TCP 主站，周期读取建大仁科 TCP 温湿度传感器；

13、`httpsrv_web.lua`：HTTP 服务器 + REST API（网口1，80 端口）+ WiFi AP 服务器（192.168.4.1）；

14、`index.html`：内置网页前端（状态总览、继电器开关、网络配置、通讯监视、FOTA）；

15、`aircloud_data.lua`：AirCloud 数据上报 + 下行命令处理 + 运维日志（4 块追加写入）；

16、`airlbs_app.lua`：airlbs 多基站 + 多 WiFi 定位，周期上报经纬度；

17、`fota_app.lua` / `libfota3.lua`：libfota3 远程升级封装与协议库；

18、`app_main.lua`：业务编排层，汇总设备状态并提供查询接口；

19、硬件外设应用：`di_app.lua` / `do_app.lua` / `buzzer_app.lua` / `led_app.lua` / `watchdog_app.lua`（Air153D 外部看门狗）/ `flash_app.lua`（SPI NAND 挂载）/ `reload_app.lua`（RELOAD 键恢复出厂）；

20、屏幕驱动与 UI：`lcd_st6201_43in.lua` / `tp_gt911.lua` / `theme.lua` / `ui_main.lua` + 15 个 `*_win.lua` 页面。

---

## 二、硬件配置（Air8301）

| 项目 | 配置 |
|------|------|
| RS485_1（隔离口，**Modbus 从站**，接串口板） | UART1，**115200** 8N1，RE/DE = **GPIO2**（uart 内置 RS485 换向），供电 GPIO29 |
| RS485_2（非隔离口，**继电器主站**） | UART11，**9600** 8N1，RE/DE = **GPIO153**（>128，满足 UART11 硬件自动换向），供电 GPIO147 |
| 网口1（内置网页 + TCP 主站） | CH390H，SPI1 / CS=**GPIO12**，INT=**GPIO20**，供电 **GPIO32**，映射 `socket.LWIP_ETH` |
| 网口2（Modbus TCP 从站） | CH390H，SPI1 / CS=**GPIO5**，INT=**CHG_DET（gpio.WAKEUP6）**，供电 **GPIO33**，映射 `socket.LWIP_USER1` |
| 板载 SPI Flash | SPI1 / CS=**GPIO4**（与双 CH390 共用 SPI1，必须等 `NETWORK_INIT_DONE` 后再挂载） |
| LCD | ST6201 4.3 寸 480×272，EN=GPIO28，RST=GPIO36，背光 PWM0 |
| 触摸 | GT911，I2C0，RST=GPIO26，INT=WAKEUP0 |
| 蜂鸣器 | PWM2（PIN98） |
| DO 输出 | GPIO24 / GPIO25（高电平导通） |
| DI 输入 | GPIO16 / GPIO17（对 GND 短接触发） |
| 状态灯 | GPIO21（4G）/ GPIO141（WiFi） |
| 外部看门狗 | Air153D，GPIO27（`exair153x_wdt`，库默认 180 秒喂狗） |
| RELOAD 按键 | WAKEUP2（长按 5 秒恢复出厂设置） |

> SPI1 上同时挂载 网口1 / 网口2 / SPI NAND 三个设备，存在总线争用风险，故两路网口均已配置中断引脚（`opts.irq`）以降低轮询频率。

---

## 三、网络配置

默认参数定义在 `net_config.lua`（可用内置网页修改，fskv 持久化）：

| 项 | 默认值 |
|----|--------|
| 网口1 ETH1 | 静态 **192.168.1.183** / 255.255.255.0 / 网关 192.168.1.1 |
| 网口2 ETH2 | 静态 **192.168.1.185** / 255.255.255.0 / 网关 192.168.1.1 |
| WiFi AP 热点 | SSID **Air8301**，密码 **12345678**，AP IP **192.168.4.1** |
| WiFi STA | 默认 SSID「116」/ 静态 IP 192.168.1.200（继承自 8300 工程，投产前请按现场修改） |
| 网卡优先级 | `wifi` > `eth1` > `eth2` > `4g` |
| NTP / 时区 | ntp.aliyun.com / UTC+8 |
| TCP 温湿度传感器 | **192.168.1.100:500**（建大仁科，按现场修改） |

**访问内置网页的三个入口**

| 入口 | 地址 | 说明 |
|------|------|------|
| 网口1 | `http://192.168.1.183` | 电脑网线直连 ETH1（电脑 IP 建议设 192.168.1.50，避免与 .100/.183/.185 冲突） |
| WiFi 热点 | `http://192.168.4.1` | 手机/电脑连 `Air8301` 热点 |
| Modbus TCP 从站 | `192.168.1.185:502` | 网口2，从站 ID 1 |

---

## 四、Modbus 寄存器映射表

Modbus RTU 从站（RS485_1）与 Modbus TCP 从站（网口2 :502）**共用同一份寄存器表**与同一个回调：

| 地址 | 类型 | 数据项 | 说明 |
|------|------|--------|------|
| `0x0000` | INT16 | 继电器状态位掩码 | bit0 = 通道0 |
| `0x0001`~`0x0004` | INT16 | 继电器各路状态 / 开关 | **读** = 该路实际状态；**写** = 0 断开、非 0 接通 |
| `0x0005-06` | FLOAT | CPU 温度 | IEEE754，**低字在前** |
| `0x0007-08` | FLOAT | VBAT 电压 | IEEE754，**低字在前** |
| `0x0009-12` | STRING（10 寄存器） | LBS 纬度 | 20 字节 |
| `0x0013-1C` | STRING（10 寄存器） | LBS 经度 | 20 字节 |
| `0x001D` | INT16 | 4G 信号强度 | CSQ |
| `0x001E-29` | STRING（12 寄存器） | 设备 IMEI | 24 字节 |
| `0x002A-37` | STRING（14 寄存器） | SIM ICCID | 28 字节 |
| `0x0038-39` | INT32 | 时间戳 | NTP Unix 秒 |
| `0x0050` | INT16 | **继电器控制字（可写）** | 见下 |

**继电器控制字 `0x0050` 取值**

| 写入值 | 含义 |
|--------|------|
| `0x0000` | 全部断开 |
| `0xFFFF` | 全部接通 |
| `0x0001`~`0x0004` | 打开通道 0~3 |
| `0x0101`~`0x0104` | 关闭通道 0~3 |
| `0x0201`~`0x0204` | 翻转通道 0~3 |

支持功能码：**03 / 04**（读保持/输入寄存器）、**06**（写单寄存器）、**10**（写多寄存器）。
其余功能码返回 ILLEGAL_FUNCTION 异常码。

---

## 五、485 / 网口 Modbus 通信测试

### 5.1 串口板（RS485_1 隔离口，115200-8-N-1）测试

串口工具（SSCOM / Modbus Poll / QModMaster）参数：**115200、8、N、1、从站 ID 1、HEX 模式、无流控**。
接线：A→A、B→B

**读寄存器（功能码 03）—— 下列帧的 CRC 均已验算，可直接发送**

| 数据项 | 发送帧（HEX） |
|--------|--------------|
| 继电器状态位掩码 + 4 路状态（5 个寄存器） | `01 03 00 00 00 05 85 C9` |
| 4 路开关寄存器（0x0001~0x0004） | `01 03 00 01 00 04 15 C9` |

其余点位（CPU 温度、VBAT、经纬度、IMEI、ICCID、时间戳）建议用 Modbus Poll 图形化读取，CRC 由工具自动计算：

| 起始地址 | 数量 | 数据项 |
|----------|------|--------|
| `0x0005` | 2 | CPU 温度 |
| `0x0007` | 2 | VBAT 电压 |
| `0x0009` | 10 | LBS 纬度 |
| `0x0013` | 10 | LBS 经度 |
| `0x001D` | 1 | 4G 信号强度 |
| `0x001E` | 12 | 设备 IMEI |
| `0x002A` | 14 | SIM ICCID |
| `0x0038` | 2 | 时间戳 |
| `0x003A` | 2 | 温湿度传感器-温度（FLOAT，来源网口1 TCP 主站读取建大仁科传感器） |
| `0x003C` | 2 | 温湿度传感器-湿度（FLOAT，来源网口1 TCP 主站读取建大仁科传感器） |

**写寄存器（功能码 06 / 10）—— 全链路验证（电脑 → 485_1 从站 → 485_2 主站 → 继电器）**

| 操作 | 发送帧（HEX） |
|------|--------------|
| 通道 0 接通 | `01 06 00 01 00 01 19 CA` |
| 通道 0 断开 | `01 06 00 01 00 00 D8 0A` |
| 通道 1 接通 | `01 06 00 02 00 01 E9 CA` |
| 全部接通（控制字 0xFFFF） | `01 06 00 50 FF FF 88 6B` |
| 全部断开（控制字 0x0000） | `01 06 00 50 00 00 89 DB` |

写入后继电器实物应动作，再发 `01 03 00 00 00 05 85 C9` 读回，状态应同步变化。

### 5.2 继电器模块（RS485_2 非隔离口，9600-8-N-1）测试

- 模块要求：**从站地址 1、波特率 9600、4 路**（与 `relay_ctrl.lua` 一致）
- 三条测试路径：**屏幕「继电器」页**（每路开关 + 批量按钮）、**内置网页「继电器」页**（每路开关）、**AirCloud 下行命令**
- 也可把 USB-485 板接到 RS485_2 用串口助手 **9600** 监听主站发出的帧（点屏幕开关时可见 `01 05 00 00 FF 00 xx xx` 等）

### 5.3 网口2 TCP 从站测试

Modbus Poll 选 **TCP**，目标 `192.168.1.185:502`，从站 1 —— 点位与读写行为与 6.1 完全一致。

### 5.4 失败判因

| 现象 | 排查 |
|------|------|
| 完全无应答 | 接错口（串口板必须接 RS485_1 隔离口）、A/B 接反、未共地、波特率不对、串口工具处于 ASCII 模式 |
| 应答功能码带 0x80 | Modbus 异常码（02 = 地址越界，03 = CRC 错误） |
| 能读不能写 | 可写地址仅 `0x0001~0x0004` 与 `0x0050`，其它地址写会返回异常码 |
| 写成功但继电器不动 | 从站链路已通，问题在 RS485_2 侧（模块地址/波特率/接线） |

---

## 六、内置网页接口（网口1，80 端口）

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/` `/index.html` | 网页前端 |
| GET | `/api/status` | 传感器 + 设备 + 网络状态 |
| GET | `/api/sensor` | 继电器状态 + 温湿度 |
| GET | `/api/network` | 网络状态 |
| GET | `/api/comm/status` | 通讯状态（485 参数 + 寄存器表 + 通讯日志） |
| GET | `/api/relay/status` | 继电器状态（`relay` 为 1 基数组 `[c0,c1,c2,c3]`） |
| POST | `/api/relay/control` | 继电器控制 `{action, channel}`，action = open / close / toggle / all_open / all_close / read |
| GET / POST | `/api/config` | 读取 / 保存网络配置 |
| GET / POST | `/api/wifi/scan` | 触发扫描 / 读取扫描结果 |
| GET / POST | `/api/priority` | 读取 / 保存网卡优先级 |
| POST | `/api/reset` | 恢复默认网络配置 |
| GET | `/api/fota/status` | FOTA 状态 |
| POST | `/api/fota/check` | 触发检测更新 |
| GET | `/api/temp` | 网口 TCP 温湿度 |
| GET | `/api/log?msg=xxx` | 调试日志 |

示例：

```bash
curl http://192.168.1.183/api/relay/status
curl -X POST http://192.168.1.183/api/relay/control \
     -H "Content-Type: application/json" -d "{\"action\":\"toggle\",\"channel\":0}"
```

> 继电器操作是**异步**的（HTTP 回调不能阻塞等待 485 应答），响应为 `accepted`，状态约 0.6~2 秒后刷新。

---

## 七、屏幕 UI

| 页面 | 文件 | 说明 |
|------|------|------|
| 首页 | `idle_win.lua` | 14 个功能入口（5×3 网格） |
| 网络状态 | `network_win.lua` | 4G / 网口 / 系统信息 |
| WiFi | `wifi_win.lua` | 扫描、STA 配置 |
| RS485 | `rs485_win.lua` | ⚠️ 当前为空壳页（见第十二节） |
| 继电器 | `relay_win.lua` | 每路一个滑动开关（通道 0~3）+ 全部接通/断开/回读 |
| 寄存器监视 | `modbus_win.lua` | 寄存器数值对照 |
| DI / DO | `di_win.lua` / `do_win.lua` | 输入状态 / 输出控制 |
| 蜂鸣器 / 状态灯 | `buzzer_win.lua` / `led_win.lua` | 板载外设测试 |
| 看门狗 | `watchdog_win.lua` | 查询 / 手动喂狗 / 启停 |
| Flash | `flash_win.lua` | SPI NAND 挂载状态 |
| 系统信息 | `sysinfo_win.lua` | 版本、IMEI、恢复出厂 |
| 恢复出厂 | `reload_win.lua` | RELOAD 键状态 |
| 远程升级 | `fota_win.lua` | FOTA 检测与触发 |

**首页图标资源**：`idle_win.lua` 引用 `/luadb/hw_*.png`（共 11 个），需从 `hardware_test/src/` 原样复制到烧录文件系统：

```
hw_network.png  hw_wifi.png   hw_rs485.png   hw_di.png      hw_do.png
hw_buzzer.png   hw_led.png    hw_watchdog.png hw_flash.png  hw_sysinfo.png
hw_reload.png
```

缺失只会导致首页图标留白，不影响功能。

---

## 八、AirCloud 云端

### 8.1 上报字段

| 语义 | field | 类型 | 来源 |
|------|-------|------|------|
| 4G 信号强度 | 782 | INTEGER | `mobile.csq()` |
| SIM ICCID | 783 | ASCII | `mobile.iccid()` |
| 温度 | 256 | FLOAT | 网口 TCP 温湿度传感器 |
| 湿度 | 257 | FLOAT | 网口 TCP 温湿度传感器 |
| CPU 温度 | 263 | INTEGER | ADC |
| VBAT 电压 | 799 | INTEGER | ADC |
| 经度 / 纬度 | 512 / 513 | ASCII | airlbs |
| **继电器状态** | **268** | **ASCII** | `relay_ctrl`，格式 `"1,1,0,0"` |

### 8.2 下行命令（JSON，经 CONTROL_COMMAND / IRTU_DOWN 下发）

```
read_all / relay_open{channel} / relay_close{channel} / relay_toggle{channel}
relay_all_open / relay_all_close / relay_read
read_temp / read_humi / read_vbat / read_cpu / read_csq / read_iccid / read_time
```

示例：`{"type":"relay_open","channel":0}`，应答经 `CONTROL_RESPONSE` 以 JSON 回传。

### 8.3 运维日志

`excloud.setup` 中启用 `mtn_log_enabled = true`、`mtn_log_blocks = 4`、`mtn_log_write_way = excloud.MTN_LOG_ADD_WRITE`，
关键业务事件通过 `excloud.mtn_log()` 写入云端，便于远程运维。

