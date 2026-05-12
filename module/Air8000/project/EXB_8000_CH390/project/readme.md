## EXB_8000_CH390 综合项目 (project/)

本目录是一个完整的生产级项目，整合了 Socket 长连接、Modbus RTU/TCP 主从站、AirCloud 物联网数据上报、合宙 LBS 定位、网络看门狗等功能。

### 文件结构

```
project/
├── main.lua                  ← 项目入口，调度所有功能模块
├── readme.md                 ← 本文件
│
├── network_watchdog.lua      ← 网络看门狗（180秒超时自动重启）
├── netdrv_device.lua         ← 网络驱动选择器（4G/WiFi/ETH/多网切换/PC）
├── netdrv_eth_static.lua     ← 以太网静态IP驱动（双网口 CH390）
│
├── airlbs_app.lua            ← 合宙 LBS 定位（基站+WiFi，付费服务）
├── aircloud_data.lua         ← AirCloud 物联网数据上报（30秒周期）
├── timer_app.lua             ← 定时器数据发送（10秒周期）
├── led.lua                   ← LED 指示灯驱动（可复用模块）
│
├── param_field_rtu.lua       ← Modbus RTU 主站（字段参数方式）
├── raw_frame_rtu.lua         ← Modbus RTU 主站（原始帧方式）
├── rtu_slave_manage.lua      ← Modbus RTU 从站
│
├── param_field_tcp.lua       ← Modbus TCP 主站（字段参数方式）
├── raw_frame_tcp.lua         ← Modbus TCP 主站（原始帧方式）
├── tcp_slave_manage.lua      ← Modbus TCP 从站
│
├── netdrv/                   ← 网络驱动 + 多网融合路由模块
│   ├── netdrv_4g.lua         # 4G 蜂窝网络驱动
│   ├── netdrv_wifi.lua       # WiFi STA 驱动
│   ├── netdrv_eth_spi.lua    # SPI 以太网驱动
│   ├── netdrv_multiple.lua   # 多网卡自动切换（ETH > WiFi > 4G）
│   ├── netdrv_pc.lua         # PC 模拟器网卡
│   ├── netif_app_1.lua       # 4G 转 WiFi+以太网 多网融合
│   ├── netif_app_2.lua       # 以太网 转 WiFi+以太网 多网融合
│   └── netif_app_3.lua       # WiFi 转 WiFi+以太网 多网融合
│
└── tcp/                      ← TCP Socket 长连接模块
    ├── tcp_client_main.lua   # Socket 连接管理主模
    ├── tcp_client_receiver.lua # Socket 数据接收模块
    └── tcp_client_sender.lua   # Socket 数据发送模块
```

---

### 功能模块说明

#### 1. 网络看门狗 (`network_watchdog.lua`)

- 监控网络通信是否正常，180 秒内未收到喂狗信号则自动重启设备
- 喂狗时机：收到服务器数据 或 TCP 发送成功
- 其他模块通过 `sys.publish("FEED_NETWORK_WATCHDOG")` 喂狗

#### 2. 网络驱动 (`netdrv_device.lua` + `netdrv/`)

| 驱动模块 | 适配器 | 说明 |
|----------|--------|------|
| `netdrv_4g` | `socket.LWIP_GP` | 4G 蜂窝网络 |
| `netdrv_wifi` | `socket.LWIP_STA` | WiFi STA 模式 |
| `netdrv_eth_spi` | `socket.LWIP_ETH` | SPI CH390 以太网 (DHCP) |
| `netdrv_multiple` | 多适配器 | 自动切换：ETH > WiFi > 4G |
| `netdrv_pc` | `socket.ETH0` | PC 模拟器 |

多网融合路由模块 (`netif_app_1/2/3`) 使用 `exnetif.setproxy` 实现：
- **netif_app_1**: 4G WAN → WiFi AP + 以太网 LAN
- **netif_app_2**: 以太网 WAN → WiFi AP + 以太网 LAN
- **netif_app_3**: WiFi STA WAN → WiFi AP + 以太网 LAN

#### 3. Socket 长连接 (`tcp/`)

- 创建 **4 路** socket 连接：TCP、UDP、TCP SSL（无校验）、TCP SSL（单向校验证书）
- 异常自动重连
- 数据发送来源：串口 UART1 数据 或 定时器 Timer 数据
- 接收数据通过 UART1 转发

#### 4. AirCloud 数据上报 (`aircloud_data.lua`)

- 按 AirCloud 平台格式构建 JSON 数据
- 每 30 秒上报一次，包含：4G 信号强度、SIM ICCID、时间戳、设备 IMEI、CPU 温度、VBAT 电压、经纬度

#### 5. 合宙 LBS 定位 (`airlbs_app.lua`)

- 等待网络就绪后进行 NTP 授时
- 扫描基站 + WiFi 信息
- 每 60 秒发起一次定位请求（**付费服务**，需在 iot.openluat.com 购买）
- 定位结果通过 `sys.publish("Airlbs_LOCATION_UPDATE", lat, lng)` 通知其他模块

#### 6. LED 驱动 (`led.lua`)

可复用的通用 LED 控制模块：

```lua
local led = require "led"
led.init({26, 27, 28})       -- 初始化 LED 引脚
led.start()                   -- 启动 LED 闪烁任务
led.set_comm_status(true)     -- 通信成功：LED 轮流闪烁
led.set_comm_status(false)    -- 通信失败：全部熄灭
```

#### 7. 定时器 (`timer_app.lua`)

- 每 10 秒生成递增数据，通过 `sys.publish("SEND_DATA_REQ")` 发送给 Socket 模块

#### 8. Modbus RTU 主站 (`param_field_rtu.lua` / `raw_frame_rtu.lua`)

- 使用 UART1，波特率 115200/8N1
- RS485 方向引脚：GPIO 37
- 从站 ID=1，每 2 秒读保持寄存器 0-1，每 4 秒写保持寄存器 0-1
- **二选一**：`param_field_rtu`（字段参数）或 `raw_frame_rtu`（原始帧）

#### 9. Modbus RTU 从站 (`rtu_slave_manage.lua`)

- 使用 UART3，波特率 115200/8N1
- RS485 方向引脚：GPIO 36，供电引脚：GPIO 29
- 从站 ID=1，支持读线圈/离散输入/保持寄存器/输入寄存器、写线圈/保持寄存器

#### 10. Modbus TCP 主站 (`param_field_tcp.lua` / `raw_frame_tcp.lua`)

- 使用 `socket.LWIP_ETH` 适配器
- 连接 192.168.1.185:6000
- **二选一**：`param_field_tcp`（字段参数）或 `raw_frame_tcp`（原始帧）

#### 11. Modbus TCP 从站 (`tcp_slave_manage.lua`)

- 使用 `socket.LWIP_USER1` 适配器（网口2）
- 监听端口 6000，从站 ID=1
- 等待网卡就绪后创建从站，发布 `TCP_SLAVE_READY` 消息

---

### 硬件引脚总览

| 功能 | 引脚 | 说明 |
|------|------|------|
| CH390 网口1 供电 | GPIO 16 | 以太网 PHY 使能 |
| CH390 网口2 供电 | GPIO 17 | 以太网 PHY 使能 |
| SPI1 CS 网口1 | GPIO 21 | CH390 片选 |
| SPI1 CS 网口2 | GPIO 20 | CH390 片选 |
| RS485 Master 方向 | GPIO 37 | 主站 485 收发控制 |
| RS485 Slave 方向 | GPIO 36 | 从站 485 收发控制 |
| RS485 供电 | GPIO 29 | 485 芯片电源 |
| UART1 | — | Modbus RTU 主站 / 串口数据收发 |
| UART3 | — | Modbus RTU 从站 |
| LED1-3 | GPIO 26,27,28 | 通信状态指示 |

---

### main.lua 配置说明

编辑 `main.lua` 中的 `require` 行来启用/禁用功能：

#### 网络驱动选择（在 `netdrv_device.lua` 中修改）

```lua
require "netdrv_4g"          -- 4G
-- require "netdrv_wifi"     -- WiFi
-- require "netdrv_eth_spi"  -- 以太网 DHCP
-- require "netdrv_multiple" -- 多网切换
```

#### Modbus 主站 API 选择（二选一）

```lua
require "param_field_rtu"   -- RTU 字段参数方式
-- require "raw_frame_rtu"  -- RTU 原始帧方式

-- require "param_field_tcp" -- TCP 字段参数方式
require "raw_frame_tcp"      -- TCP 原始帧方式
```

#### 以太网静态 IP

当需要静态 IP（网口1: 192.168.1.183, 网口2: 192.168.1.185）时，确保 `netdrv_eth_static.lua` 已加载，且 `netdrv_device.lua` 中不要同时加载以太网 DHCP 驱动。

---

### 模块间通信

| 消息名 | 发布者 | 订阅者 | 说明 |
|--------|--------|--------|------|
| `FEED_NETWORK_WATCHDOG` | Socket 模块 | network_watchdog | 喂狗信号 |
| `SEND_DATA_REQ` | timer_app / uart | tcp_client_sender | 发送数据请求 |
| `CONNECTION_SUCCESS` | tcp_client_main | aircloud_data | Socket 连接成功 |
| `TCP_SLAVE_READY` | tcp_slave_manage | main.lua | TCP 从站就绪 |
| `Airlbs_LOCATION_UPDATE` | airlbs_app | aircloud_data | 定位数据更新 |

---

### 依赖扩展库

| 扩展库 | 用途 |
|--------|------|
| `exmodbus` | Modbus RTU/TCP 通信 |
| `exnetif` | 网络适配器管理/多网融合 |
| `excloud` | AirCloud 平台数据上报 |
| `airlbs` | 合宙 LBS 定位 |
| `json` | JSON 编解码 |
| `crypto` | CRC16 校验 |

---

### 启动流程

```
1. network_watchdog  ←  启动网络看门狗
2. netdrv_device     ←  按配置启用网络驱动
3. airlbs_app        ←  等待网络就绪 → NTP 授时 → 循环定位
4. timer_app         ←  启动 10 秒定时器
5. aircloud_data     ←  等待 Socket 连接成功 → 30 秒周期上报
6. led               ←  初始化 LED 驱动
7. tcp_client_main   ←  建立 4 路 Socket 连接
8. rtu_slave_manage  ←  RTU 从站立即启动
9. param_field_rtu   ←  RTU 主站立即启动
10. netdrv_eth_static ←  配置以太网静态 IP（双网口）
11. tcp_slave_manage  ←  等待 LWIP_USER1 就绪 → 创建 TCP 从站
12. raw_frame_tcp     ←  TCP 主站（字段参数方式注释掉）
```

### 注意事项

1. `param_field_rtu` 和 `raw_frame_rtu` 不能同时加载（同一 UART1）
2. `param_field_tcp` 和 `raw_frame_tcp` 不能同时加载（同一适配器）
3. 使用以太网静态 IP 时，`netdrv_device.lua` 中的以太网 DHCP 驱动必须全部注释掉
4. AirLBS 定位为 **付费服务**，需修改 `airlbs_app.lua` 中的 `project_id` 和 `project_key`
5. 网络看门狗超时时间 180 秒，根据实际业务调整
6. Socket 连接的服务器地址需根据实际环境修改（在各 tcp_client 模块中配置）

### 演示核心步骤

1、搭建硬件环境

- 将 TYPE-C USB 数据线一端接在 EXB_8000W_CH390 开发板上，另一端接在电脑上
- 将两根网线分别一端接在 EXB_8000W_CH390 开发板网口1和网口2上，另一端接在路由器/交换机上
- 参考图见 演示硬件环境

2、修改代码

- 两个网口的网关和静态ip需要自己在"netdrv_eth_static.lua "文件下根据实际设置
- modbus tcp 在“param_field”或”raw_frame“文件下create_config参数中修改实际使用的从站ip
- 对于modbus tcp若需要字段参数方式，打开 require "raw_frame_tcp" ，注释掉 require "param_field_tcp" ，反之也成立

- 对于modbus rtu若需要字段参数方式，打开 require "raw_frame_rtu" ，注释掉 require "param_field_rtu" ，反之也成立

4、打开 Luatools 工具，根据要求烧录本次所需要的内核固件和脚本代码

5、烧录成功后，自动开机运行

6、运行成功后后 Luatools 工具上的日志如下：

```lua
[2026-05-12 10:06:48.585][000000000.718] I/user.exmodbus 串口 3 初始化成功，波特率 115200
[2026-05-12 10:06:48.588][000000000.718] I/user.exmodbus_test rtu_slave 创建成功, 从站 ID 为 1
[2026-05-12 10:06:48.592][000000000.719] I/user.exmodbus 已注册从站请求处理回调函数
[2026-05-12 10:06:48.596][000000000.719] I/user.从站回调函数已注册，开始监听主站请求...
[2026-05-12 10:06:48.601][000000000.738] Uart_ChangeBR 1461:uart1, 115200 115203 26000000 3611
[2026-05-12 10:06:48.604][000000000.739] I/user.exmodbus 串口 1 初始化成功，波特率 115200
[2026-05-12 10:06:48.607][000000000.740] I/user.exmodbus_test rtu_master 创建成功
[2026-05-12 10:06:48.611][000000000.741] I/user.led LED初始化完成，引脚: 26, 27, 28
[2026-05-12 10:06:48.614][000000000.742] I/user.led LED任务已启动
[2026-05-12 10:06:48.617][000000000.743] I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2026-05-12 10:06:48.746][000000000.928] I/user.初始化以太网
[2026-05-12 10:06:48.751][000000000.929] I/user.config.opts.spi 1 ,config.type 1
[2026-05-12 10:06:48.754][000000000.929] SPI_HWInit 445:APB MP 102400000
[2026-05-12 10:06:48.757][000000000.929] SPI_HWInit 556:spi1 speed 25600000,25600000,12
[2026-05-12 10:06:48.760][000000000.930] I/user.main open spi 0
[2026-05-12 10:06:48.765][000000000.930] D/ch390h 注册CH390H设备(8) SPI id 1 cs 20 irq 255
[2026-05-12 10:06:48.770][000000000.931] D/ch390h adapter 8 netif init ok
[2026-05-12 10:06:48.775][000000000.932] D/netdrv.ch390x task started
[2026-05-12 10:06:48.780][000000000.932] D/ch390h 注册完成 adapter 8 spi 1 cs 20 irq 255
[2026-05-12 10:06:48.795][000000001.024] I/user.exmodbus_test 等待从站网卡就绪...
[2026-05-12 10:06:48.809][000000001.026] I/user.exmodbus_test 从站网卡未就绪，继续等待...
[2026-05-12 10:06:48.842][000000001.079] network_alloc_ctrl 1387:adapter index 4 is invalid!
[2026-05-12 10:06:48.850][000000001.079] D/socket create fail
[2026-05-12 10:06:48.859][000000001.080] E/user.exmodbus 创建 socket 客户端失败
[2026-05-12 10:06:48.868][000000001.080] I/user.exmodbus TCP 主站任务已启动
[2026-05-12 10:06:48.873][000000001.081] I/user.exmodbus_test tcp_master 创建成功
[2026-05-12 10:06:48.880][000000001.082] I/user.led LED初始化完成，引脚: 26, 27, 28
[2026-05-12 10:06:48.892][000000001.082] W/user.led LED任务已启动，请勿重复启动
[2026-05-12 10:06:48.898][000000001.092] I/user.exmodbus_test rtu_slave 收到主站请求
[2026-05-12 10:06:48.902][000000001.092] I/user.exmodbus_test 读取成功，返回数据:  200, 201
[2026-05-12 10:06:48.908][000000001.096] I/user.exmodbus_test 成功读取到从站 1 保持寄存器 0-1 的值，寄存器 0 数值为 200 ，寄存器 1 数值为 201
[2026-05-12 10:06:48.917][000000001.097] I/user.exmodbus_test 开始写入从站 1 保持寄存器 0-1 的值，寄存器 0 数值为 123 ，寄存器 1 数值为 456
[2026-05-12 10:06:48.923][000000001.103] I/user.exmodbus_test rtu_slave 收到主站请求
[2026-05-12 10:06:48.928][000000001.104] I/user.exmodbus_test 写入成功，写入地址:  0 写入数据:  123
[2026-05-12 10:06:48.932][000000001.104] I/user.exmodbus_test 写入成功，写入地址:  1 写入数据:  456
[2026-05-12 10:06:48.939][000000001.108] I/user.exmodbus_test 成功写入从站 1 保持寄存器 0-1 的值
[2026-05-12 10:06:48.945][000000001.115] D/netdrv.ch390x 初始化MAC DC045A56208F
[2026-05-12 10:06:49.215][000000001.452] W/user.airlbs_multi_cells_wifi_func wait IP_READY 1 8
[2026-05-12 10:06:49.418][000000001.646] W/user.tcp_client_main_task_func wait IP_READY 1 8
[2026-05-12 10:06:49.710][000000001.933] I/user.netdrv 自定义以太网IP地址 192.168.1.185
[2026-05-12 10:06:49.717][000000001.934] I/netdrv 设置IP[8] 192.168.1.185 255.255.255.0 192.168.1.1 ret 0
[2026-05-12 10:06:49.723][000000001.934] I/user.静态ip 192.168.1.185 255.255.255.0 192.168.1.1
[2026-05-12 10:06:49.730][000000001.935] I/user.以太网初始化完成
[2026-05-12 10:06:49.734][000000001.935] I/user.netdrv 订阅socket连接状态变化事件 8101SPIETH
[2026-05-12 10:06:49.741][000000001.936] I/user.初始化以太网
[2026-05-12 10:06:49.745][000000001.937] I/user.config.opts.spi 1 ,config.type 1
[2026-05-12 10:06:49.750][000000001.937] SPI_HWInit 445:APB MP 102400000
[2026-05-12 10:06:49.757][000000001.937] SPI_HWInit 556:spi1 speed 25600000,25600000,12
[2026-05-12 10:06:49.762][000000001.938] I/user.main open spi 0
[2026-05-12 10:06:49.768][000000001.938] D/ch390h 注册CH390H设备(4) SPI id 1 cs 21 irq 255
[2026-05-12 10:06:49.775][000000001.939] D/ch390h adapter 4 netif init ok
[2026-05-12 10:06:49.779][000000001.939] D/ch390h 注册完成 adapter 4 spi 1 cs 21 irq 255
[2026-05-12 10:06:49.783][000000001.950] D/netdrv.ch390x 初始化MAC DC045A566D07
[2026-05-12 10:06:49.804][000000002.027] I/user.exmodbus_test 从站网卡未就绪，继续等待...
[2026-05-12 10:06:50.219][000000002.453] W/user.airlbs_multi_cells_wifi_func wait IP_READY 1 4
[2026-05-12 10:06:50.423][000000002.647] W/user.tcp_client_main_task_func wait IP_READY 1 4
[2026-05-12 10:06:50.428][000000002.659] I/netdrv.ch390x link is up 1 20 100M
[2026-05-12 10:06:50.435][000000002.660] D/netdrv 网卡(8)设置为UP
[2026-05-12 10:06:50.445][000000002.660] D/net network ready 8, setup dns server
[2026-05-12 10:06:50.453][000000002.661] D/netdrv IP_READY 8 192.168.1.185
[2026-05-12 10:06:50.459][000000002.662] D/net 设置DNS服务器 id 8 index 0 ip 223.5.5.5
[2026-05-12 10:06:50.465][000000002.662] D/net 设置DNS服务器 id 8 index 1 ip 114.114.114.114
[2026-05-12 10:06:50.472][000000002.662] I/user.netdrv_eth_spi.ip_ready_func IP_READY 192.168.1.185 255.255.255.0 192.168.1.1 nil
[2026-05-12 10:06:50.476][000000002.663] I/user.dnsproxy 开始监听
[2026-05-12 10:06:50.481][000000002.664] W/user.tcp_client_main_task_func wait IP_READY 1 4
[2026-05-12 10:06:50.487][000000002.665] W/user.airlbs_multi_cells_wifi_func wait IP_READY 1 4
[2026-05-12 10:06:50.716][000000002.940] I/user.netdrv 自定义以太网IP地址 192.168.1.183
[2026-05-12 10:06:50.721][000000002.941] I/netdrv 设置IP[4] 192.168.1.183 255.255.255.0 192.168.1.1 ret 0
[2026-05-12 10:06:50.725][000000002.941] I/user.静态ip 192.168.1.183 255.255.255.0 192.168.1.1
[2026-05-12 10:06:50.732][000000002.942] I/user.以太网初始化完成
[2026-05-12 10:06:50.737][000000002.943] I/user.netdrv 订阅socket连接状态变化事件 Ethernet
[2026-05-12 10:06:50.742][000000002.943] change from 1 to 8
[2026-05-12 10:06:50.792][000000003.028] I/user.exmodbus_test 从站网卡已就绪，index: 8
[2026-05-12 10:06:50.798][000000003.030] I/user.exmodbus TCP 从站任务已启动
[2026-05-12 10:06:50.804][000000003.030] I/user.exmodbus_test tcp_slave 创建成功, 从站 ID 为 1
[2026-05-12 10:06:50.811][000000003.031] I/user.exmodbus 已注册从站请求处理回调函数
[2026-05-12 10:06:50.816][000000003.031] I/user.exmodbus_test 从站回调函数已注册，开始监听主站请求...
[2026-05-12 10:06:50.821][000000003.032] I/user.exmodbus_test 已发布 TCP_SLAVE_READY 消息
[2026-05-12 10:06:50.871][000000003.108] I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2026-05-12 10:06:50.886][000000003.111] I/user.exmodbus_test rtu_slave 收到主站请求
[2026-05-12 10:06:50.891][000000003.112] I/user.exmodbus_test 读取成功，返回数据:  123, 456
[2026-05-12 10:06:50.896][000000003.115] I/user.exmodbus_test 成功读取到从站 1 保持寄存器 0-1 的值，寄存器 0 数值为 123 ，寄存器 1 数值为 456
[2026-05-12 10:06:51.431][000000003.664] I/user.tcp_client_main_task_func recv IP_READY 8 4
[2026-05-12 10:06:51.436][000000003.665] D/socket connect to 115.120.239.161,28824
[2026-05-12 10:06:51.441][000000003.665] D/net adapter 8 connect 115.120.239.161:28824 TCP
[2026-05-12 10:06:51.447][000000003.667] I/user.airlbs_multi_cells_wifi_func recv IP_READY 8 4
[2026-05-12 10:06:51.453][000000003.668] D/sntp query ntp.aliyun.com
[2026-05-12 10:06:51.459][000000003.668] dns_run 676:ntp.aliyun.com state 0 id 1 ipv6 0 use dns server0, try 0
[2026-05-12 10:06:51.466][000000003.669] D/net adatper 8 dns server 223.5.5.5
[2026-05-12 10:06:51.471][000000003.669] D/net dns udp sendto 223.5.5.5:53 from 192.168.1.185
[2026-05-12 10:06:51.475][000000003.698] dns_run 693:dns all done ,now stop
[2026-05-12 10:06:51.484][000000003.698] D/net adapter 8 connect 203.107.6.88:123 UDP
[2026-05-12 10:06:51.490][000000003.708] I/user.tcp_client_main_task_func libnet.connect success
[2026-05-12 10:06:51.496][000000003.711] luat_adc_open 670:adc gain 1658, offset 151
[2026-05-12 10:06:51.501][000000003.711] luat_adc_open 694:adc5 param 0,20,5,32,3, max read:17785994mv
[2026-05-12 10:06:51.507][000000003.712] I/user.CPU TEMP 35.00000
[2026-05-12 10:06:51.515][000000003.713] luat_adc_open 694:adc4 param 1,15,0,32,8, max read:6669748mv
[2026-05-12 10:06:51.521][000000003.714] I/user.VBAT 3.800000
[2026-05-12 10:06:51.527][000000003.731] D/sntp Unix timestamp: 1778551612
[2026-05-12 10:06:52.632][000000004.862] I/netdrv.ch390x link is up 1 21 100M
[2026-05-12 10:06:52.637][000000004.863] D/netdrv 网卡(4)设置为UP
[2026-05-12 10:06:52.643][000000004.863] D/net network ready 4, setup dns server
[2026-05-12 10:06:52.651][000000004.864] D/netdrv IP_READY 4 192.168.1.183
[2026-05-12 10:06:52.656][000000004.865] D/net 设置DNS服务器 id 4 index 0 ip 223.5.5.5
[2026-05-12 10:06:52.664][000000004.865] D/net 设置DNS服务器 id 4 index 1 ip 114.114.114.114
[2026-05-12 10:06:52.668][000000004.866] I/user.netdrv_eth_spi.ip_ready_func IP_READY 192.168.1.183 255.255.255.0 192.168.1.1 nil
[2026-05-12 10:06:52.673][000000004.866] I/user.dnsproxy 开始监听
[2026-05-12 10:06:52.879][000000005.116] I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2026-05-12 10:06:52.894][000000005.120] I/user.exmodbus_test rtu_slave 收到主站请求
[2026-05-12 10:06:52.898][000000005.120] I/user.exmodbus_test 读取成功，返回数据:  123, 456
[2026-05-12 10:06:52.902][000000005.124] I/user.exmodbus_test 成功读取到从站 1 保持寄存器 0-1 的值，寄存器 0 数值为 123 ，寄存器 1 数值为 456
[2026-05-12 10:06:52.907][000000005.124] I/user.exmodbus_test 开始写入从站 1 保持寄存器 0-1 的值，寄存器 0 数值为 123 ，寄存器 1 数值为 456
[2026-05-12 10:06:52.910][000000005.129] I/user.exmodbus_test rtu_slave 收到主站请求
[2026-05-12 10:06:52.915][000000005.129] I/user.exmodbus_test 写入成功，写入地址:  0 写入数据:  123
[2026-05-12 10:06:52.920][000000005.130] I/user.exmodbus_test 写入成功，写入地址:  1 写入数据:  456
[2026-05-12 10:06:52.926][000000005.133] I/user.exmodbus_test 成功写入从站 1 保持寄存器 0-1 的值
[2026-05-12 10:06:53.234][000000005.465] D/airlink.wlan 收到扫描结果 14
[2026-05-12 10:06:53.239][000000005.467] I/user.scan wifi_info 14
[2026-05-12 10:06:53.250][000000005.477] I/user.mac nil
[2026-05-12 10:06:53.253][000000005.477] I/user.硬件型号 Air8000
[2026-05-12 10:06:53.257][000000005.488] I/user.扫描出的数据 {"cells":[[460,0,18500,245494475,-72,9,359,-102,-13,3590]],"macs":[["82:3C:20:94:13:08",-43],["92:5E:44:04:C2:A8",-61],["94:CB:CD:82:DF:B8",-75],["E0:E0:FC:B6:A8:04",-81],["E0:E0:FC:F6:A8:09",-81],["D0:79:80:C6:3A:B0",-82],["62:42:15:31:98:14",-88],["CC:E0:DA:D4:7C:85",-90],["A0:44:5C:EB:C2:B4",-91],["CE:E0:DA:B4:7C:85",-95],["EC:6C:B5:08:15:F8",-95],["90:FB:5D:94:36:9A",-97],["EC:3C:BB:81:38:9C",-97],["EC:3C:BB:81:38:A1",-99]]}
[2026-05-12 10:06:53.266][000000005.492] D/socket connect to airlbs.openluat.com,12413
[2026-05-12 10:06:53.270][000000005.492] dns_run 676:airlbs.openluat.com state 0 id 2 ipv6 0 use dns server0, try 0
[2026-05-12 10:06:53.273][000000005.492] D/net adatper 8 dns server 223.5.5.5
[2026-05-12 10:06:53.276][000000005.493] D/net dns udp sendto 223.5.5.5:53 from 192.168.1.185
[2026-05-12 10:06:53.281][000000005.516] dns_run 693:dns all done ,now stop
[2026-05-12 10:06:53.285][000000005.516] D/net adapter 8 connect 121.40.251.45:12413 UDP
[2026-05-12 10:06:53.289][000000005.518] I/user.airlbs 服务器连上了
[2026-05-12 10:06:53.438][000000005.664] I/user.airlbs wait true true nil
[2026-05-12 10:06:53.444][000000005.667] I/user.定位请求的结果 true 超时时间 0 table: 0C7B3E38 {"result":1,"lng":114.2941742,"lat":34.8074112}
[2026-05-12 10:06:53.451][000000005.667] I/user.多基站请求成功,服务器返回的原始数据 table: 0C7B3E38
[2026-05-12 10:06:53.459][000000005.668] I/user.airlbs多基站+多wifi定位返回的经纬度数据为 {"lat":34.8074112,"lng":114.2941742}
[2026-05-12 10:06:53.466][000000005.669] I/user.airlbs lat 34.8074112
[2026-05-12 10:06:53.472][000000005.669] I/user.airlbs lng 114.2941742
[2026-05-12 10:06:53.477][000000005.672] I/user.airlbs Using 4G device ID: 864793080523348
[2026-05-12 10:06:53.483][000000005.674] dns_run 676:iot.openluat.com state 0 id 3 ipv6 0 use dns server0, try 0
[2026-05-12 10:06:53.489][000000005.674] D/net adatper 8 dns server 223.5.5.5
[2026-05-12 10:06:53.495][000000005.674] D/net dns udp sendto 223.5.5.5:53 from 192.168.1.185
[2026-05-12 10:06:53.502][000000005.676] I/user.aircloud_data 收到定位数据更新 lat: 34.8074112 lng: 114.2941742
[2026-05-12 10:06:53.815][000000005.952] I/mobile sim0 sms ready
[2026-05-12 10:06:53.821][000000005.952] D/mobile cid1, state0
[2026-05-12 10:06:53.826][000000005.953] D/mobile bearer act 0, result 0
[2026-05-12 10:06:53.831][000000005.953] D/mobile NETIF_LINK_ON -> IP_READY
[2026-05-12 10:06:53.834][000000005.954] I/user.netdrv_4g.ip_ready_func IP_READY 10.114.92.27 255.255.255.255 0.0.0.0 nil
[2026-05-12 10:06:53.837][000000005.955] I/user.dnsproxy 开始监听
[2026-05-12 10:06:53.841][000000005.997] dns_run 693:dns all done ,now stop
[2026-05-12 10:06:53.844][000000005.997] D/net adapter 8 connect 121.196.16.94:80 TCP
[2026-05-12 10:06:53.848][000000006.007] D/mobile TIME_SYNC 0 tm 1778551614
[2026-05-12 10:06:53.856][000000006.080] D/socket connect to 192.168.1.185,6000
[2026-05-12 10:06:53.859][000000006.081] D/net adapter 4 connect 192.168.1.185:6000 TCP
[2026-05-12 10:06:53.862][000000006.089] I/user.exmodbus 连接服务器成功
[2026-05-12 10:06:53.865][000000006.092] D/net adapter 8 socket 0 new client from 192.168.1.183:10003
[2026-05-12 10:06:53.868][000000006.094] I/user.exmodbus TCP 从站已启动，监听端口: 6000
[2026-05-12 10:06:53.933][000000006.168] I/http http close c15da64
[2026-05-12 10:06:53.938][000000006.170] I/user.airlbs 获取地址成功, 响应体: {"code": 0, "address": "\u6cb3\u5357\u7701\u5f00\u5c01\u5e02\u9f99\u4ead\u533a\u91d1\u88d5\u8def"}
[2026-05-12 10:06:53.945][000000006.171] I/user.airlbs.get_address 河南省开封市龙亭区金裕路
[2026-05-12 10:06:54.854][000000007.083] I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2026-05-12 10:06:54.859][000000007.090] I/user.exmodbus_test tcp_slave 收到主站请求
[2026-05-12 10:06:54.864][000000007.091] I/user.exmodbus_test 读取成功，返回数据:  200, 201
[2026-05-12 10:06:54.870][000000007.097] I/user.exmodbus_test 成功读取到从站 1 保持寄存器 0-1 的值，寄存器 0 数值为 200 ，寄存器 1 数值为 201
[2026-05-12 10:06:54.875][000000007.098] I/user.exmodbus_test 开始写入从站 1 保持寄存器 0-1 的值
[2026-05-12 10:06:54.880][000000007.106] I/user.exmodbus_test tcp_slave 收到主站请求
[2026-05-12 10:06:54.885][000000007.106] I/user.exmodbus_test 写入成功，写入地址:  0 写入数据:  18
[2026-05-12 10:06:54.891][000000007.107] I/user.exmodbus_test 写入成功，写入地址:  1 写入数据:  52
[2026-05-12 10:06:54.896][000000007.115] I/user.exmodbus_test 成功写入从站 1 保持寄存器 0-1
[2026-05-12 10:06:54.902][000000007.134] I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2026-05-12 10:06:54.908][000000007.137] I/user.exmodbus_test rtu_slave 收到主站请求
[2026-05-12 10:06:54.914][000000007.138] I/user.exmodbus_test 读取成功，返回数据:  123, 456
[2026-05-12 10:06:54.922][000000007.142] I/user.exmodbus_test 成功读取到从站 1 保持寄存器 0-1 的值，寄存器 0 数值为 123 ，寄存器 1 数值为 456
[2026-05-12 10:06:56.894][000000009.116] I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2026-05-12 10:06:56.901][000000009.122] I/user.exmodbus_test tcp_slave 收到主站请求
[2026-05-12 10:06:56.908][000000009.123] I/user.exmodbus_test 读取成功，返回数据:  18, 52
[2026-05-12 10:06:56.914][000000009.130] I/user.exmodbus_test 成功读取到从站 1 保持寄存器 0-1 的值，寄存器 0 数值为 18 ，寄存器 1 数值为 52
[2026-05-12 10:06:56.920][000000009.142] I/user.exmodbus_test 开始读取从站 1 保持寄存器 0-1 的值
[2026-05-12 10:06:56.926][000000009.145] I/user.exmodbus_test rtu_slave 收到主站请求
[2026-05-12 10:06:56.931][000000009.146] I/user.exmodbus_test 读取成功，返回数据:  123, 456
[2026-05-12 10:06:56.935][000000009.149] I/user.exmodbus_test 成功读取到从站 1 保持寄存器 0-1 的值，寄存器 0 数值为 123 ，寄存器 1 数值为 456
[2026-05-12 10:06:56.941][000000009.150] I/user.exmodbus_test 开始写入从站 1 保持寄存器 0-1 的值，寄存器 0 数值为 123 ，寄存器 1 数值为 456
[2026-05-12 10:06:56.944][000000009.154] I/user.exmodbus_test rtu_slave 收到主站请求
[2026-05-12 10:06:56.947][000000009.155] I/user.exmodbus_test 写入成功，写入地址:  0 写入数据:  123
[2026-05-12 10:06:56.950][000000009.156] I/user.exmodbus_test 写入成功，写入地址:  1 写入数据:  456
[2026-05-12 10:06:56.953][000000009.159] I/user.exmodbus_test 成功写入从站 1 保持寄存器 0-1 的值
[2026-05-12 10:06:58.238][000000010.463] I/user.tcp_client_main_task_func libnet.wait true true nil
[2026-05-12 10:06:58.269][000000010.497] I/user.tcp_client_sender.proc send success
[2026-05-12 10:06:58.273][000000010.498] I/user.send_data_cbfunc true timer1
```



