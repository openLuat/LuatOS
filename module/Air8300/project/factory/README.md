# 8300出厂固件

> 合宙 **Air8300** 工控板出厂固件（LuatOS / Lua 脚本），**产测与出货双模合一**：新板首次上电进产测模式，`TEST_DONE#` 后重启进入用户模式，一套固件完成产线测试与整机出货。

| 项目 | 内容 |
|------|------|
| 硬件型号 | **Air8300**（主控 Air8000W，EC718HM） |
| 项目标识 | `PROJECT = "Air8300_DataCollector"` |
| 固件版本 | `VERSION = "001.999.001"` |
| 软件框架 | LuatOS（Lua 脚本） |
| 工程代码 | `firmware/code/`（Luatools 烧录此目录） |
| 设计文档 | `firmware/doc/` |
| 产测通道 | USB 虚拟串口 `uart.VUART_0`，115200 8N1，指令以 `#` 结尾 |

---

## 1 功能概览

| 能力 | 说明 |
|------|------|
| 多网融合 | WiFi(STA/AP) + 双以太网口（双 CH390）+ 4G，`exnetif` 优先级调度，支持运行时切网与配置持久化 |
| Modbus 主站 | 隔离485（UART1）控制 **4 路继电器模块**；WiFi(STA) 经 Modbus TCP 采集**以太网温湿度变送器** |
| Modbus 从站 | 非隔离485（UART3）+ 网口2（TCP :502），对外暴露保持寄存器 `0x0000~0x003C` |
| 继电器控制 | 4 路单路开/关/翻转、全开、全关、状态回读；支持 Web 与 AirCloud 云端下发 |
| 三色LED控制 | 红/绿/蓝三路**互斥**（同一时刻只亮一路，GPIO27/28/26），**无自动灯效**；仅由 AirCloud 云端命令（`led_set`/`led_off`/`led_read`）或 Web 控制页下发；下行**兼容 Tag 19/21/1281** 三种通道 |
| 状态上报 | 继电器状态经 ① Web 页面 ② Modbus 从站寄存器 ③ AirCloud 字段 268 三条路径提供 |
| 本地管理 | 网口1 HTTP 服务（:80）全屏自适应 Web 界面（网络/通讯/监控/控制/升级/配置） |
| 远程运维 | 合宙 `iot.openluat.com` FOTA 差分包升级 + AirCloud 运维日志 |
| 定位 | 多基站 + 多 WiFi 定位（`airlbs_app`），经纬度上报云端 |
| 产测能力 | 同一固件内置产测模式，18 条产线指令（见《产测指令文档.md》） |

---

## 2 双模分发机制

`main.lua` 开机按 `BOOT_MODE` 与 `fskv` 标记 `test_done` 分流：

| `BOOT_MODE` | `fskv.test_done` | 运行模式 |
|-------------|------------------|----------|
| `"auto"`（出厂默认） | 无 | **产测模式**（新板首次上电） |
| `"auto"` | 有 | **用户模式** |
| `"factory"` | 任意 | **产测模式**（强制重测，无需清 fskv） |
| `"normal"` | 任意 | **用户模式**（调试时跳过产测） |

```
上电 → 打印 PROJECT/VERSION → 软狗 wdt.init(9000) + 3s 喂狗 → fskv.init()
     → get_boot_mode()
        ├─ 产测模式：require "factory"（独占 VUART_0，仅加载产测模块）
        └─ 用户模式：打印 OTP 的 PROD / PCB → require 全部业务模块 → FOTA 检测
```

**关键点**

- 两种模式外设资源（UART1 / UART3 / 双网口 / 三色 LED / `pins` 复用）**天然互斥**，分流保证同一时刻只加载一套，不存在资源争用；产测模式下业务模块完全不加载（不占内存、不初始化外设）。
- `test_done` 存于 **fskv**（重刷脚本固件不丢）；`PROD`（工业型号）/ `PCB`（硬件版本）存于 **OTP**（FOTA 与整片重刷均不丢）。
- 软狗位于分流之前，两种模式均受保护；FOTA 检测保留在**用户模式分支**内，产测流程不受升级动作干扰。

---

## 3 快速开始

### 3.1 设备烧录

1. Air8300 通过 USB 连接电脑，Luatools 选择脚本目录 **`firmware/code/`**；
2. 选择对应 Air8000W（Air8300）底层固件，下载脚本；
3. 复位后看日志首行应为 `I/user.main Air8300_DataCollector 001.999.001`。

### 3.2 产测模式（产线）

新板（或已清 `test_done` 的板）上电即进产测模式，用串口工具（SSCOM / Luatools 串口工具）打开**USB 虚拟串口**，115200 8N1，发送以 `#` 结尾的指令：

```
VERSION#                     读取固件版本
IMEI# / MUID# / VBAT#        模组信息与供电电压
IMSI# / ICCID# / CSQ#        插卡信息（需插 SIM 卡）
ECNPICFG#                    读取 RF 校准标志位
MODEL,Air8300#   MODEL?#     OTP 写入 / 读回工业模组型号
HVERSION,V1.0#   HVERSION#   OTP 写入 / 读回硬件版本
LED_TEST,R# / G# / B# / 0#   三色 LED
ETH_TEST,1# / ETH_TEST,2#    网口1 / 网口2 DHCP 获取 IP
U485_TEST#                   485 一发一收（A 接 A、B 接 B）
TEST_DONE#                   标记完成 → 3 秒后重启进入用户模式
```

完整指令表、管脚定义、推荐测试流程、常见问题见 **`firmware/doc/产测指令文档.md`**。

产测完成重启后进入用户模式，常用入口：

| 入口 | 地址 |
|------|------|
| 网口1 Web 管理 | http://192.168.1.183 |
| WiFi AP Web 管理 | http://192.168.4.1（AP SSID：`Air8300`） |
| Modbus TCP 从站 | 网口2 192.168.1.185 : 502，从站地址 1，寄存器 `0x0000~0x003C` |
| 温湿度变送器 | 192.168.1.100 : 500（经 WiFi(STA) 所在路由器访问） |

启动日志会打印产测阶段写入的 `模组型号 PROD: xxx` / `硬件版本 PCB: xxx`。

**三色LED控制入口**（两处，均走同一 `led.lua` 驱动，状态天然一致）：

- **Web**：控制页「三色LED指示控制」红/绿/蓝/灭四个互斥按钮（状态每 3 秒自动刷新）；
- **AirCloud**：云端下发控制命令，**同时兼容三种下行 Tag**——19（`CONTROL_COMMAND` 控制命令）、21（`IRTU_DOWN` iRTU 下行指令）、1281（`RANDOM_DATA` 自定义下行消息）；应答经 `CONTROL_RESPONSE`（Tag 20）回传。载荷支持 **JSON** 与**文本短命令**两种写法。

| 下发内容 | 效果 |
|----------|------|
| `{"type":"led_set","color":"red"}` | 红灯亮（其余熄灭）；`color` 可取 `red`/`green`/`blue`/`off`（不区分大小写） |
| `{"type":"led_off"}` | 全灭 |
| `{"type":"led_read"}` | 回读当前点亮颜色，应答 `{"ok":true,"led":"red"}` |

**文本短命令（兼容 iRTU 风格 / 平台文本输入框）**：

| 下发内容 | 等价效果 |
|----------|----------|
| `led:red` / `led,red` / `led_set,blue` | 点亮对应颜色（同 `led_set`，`color` 取 `red`/`green`/`blue`/`off`） |
| `led:off` / `led_off` | 全灭 |
| `led` / `led_read` | 回读 LED 当前状态 |
| `relay:open,0` / `relay:close,1` / `relay:toggle,2` | 继电器开 / 关 / 翻转（通道 0~3） |
| `relay:read` / `read_all` | 回读继电器状态 / 读取全部数据 |

> 分隔符支持 `:`、`,`、`#`；命令名不区分大小写；无法识别的载荷会被忽略并打印「无效命令」（不改变设备状态）。

**下发无响应时怎么查**：设备收到每条下行 TLV 都会打印
`I/user.aircloud 下行TLV field: XX type: YY value: ...`
—— 无此日志说明命令未到设备（查平台下发状态与设备是否在线）；若 field 不是 19/21/1281，说明平台走的是其它下行字段。

> LED 为**三路互斥**器件，同一时刻只点亮一路，不支持混色与亮度调节；上电默认全灭。

### 4.4 重测与调试

| 场景 | 操作 |
|------|------|
| 单板重测 | 将 `main.lua` 的 `BOOT_MODE` 临时改为 `"factory"` 后重烧；或清除 `fskv` 的 `test_done` 后重启 |
| 调试业务 | `BOOT_MODE` 置 `"normal"`；或先执行一次 `TEST_DONE#` |
| 清除产测标记 | `fskv.del("test_done")` 后重启 |

---

## 5 硬件资源分配

| 资源 | 用途 | 参数 |
|------|------|------|
| UART1 + GPIO37（隔离485） | 继电器 RTU 主站 | 9600 8N1，从站 1，线圈 `0x0000~0x0003` |
| UART3 + GPIO36（非隔离485） | RTU 从站（上位机） | 9600 8N1，从站 1 |
| 网口1（CH390，`LWIP_ETH`） | Web 服务 :80 | 静态 192.168.1.183 |
| 网口2（CH390_2，`LWIP_USER1`） | Modbus TCP 从站 :502 | 静态 192.168.1.185 |
| WiFi STA | 温湿度变送器 TCP 主站（经路由器） | DHCP |
| WiFi AP | 热点直连 Web | 192.168.4.1 |
| 4G（`LWIP_GP`） | AirCloud 上报 / 定位 | exnetif 调度 |
| GPIO27 / 28 / 26 | LED 红 / 绿 / 蓝（**三路互斥**） | `led.lua`（被动控制：AirCloud 命令 / Web 控制页，无自动灯效） |
| GPIO29 | RS485 芯片供电 | 上电拉高 |

> 双 CH390 共用 SPI1，初始化时必须**同时拉高 GPIO16 与 GPIO17**（产测代码已固化），否则 SPI 电平混乱导致通讯失败。

