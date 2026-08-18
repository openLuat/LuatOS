## 演示功能概述

### 1.1 远程联网概述

本工程基于 **780EXX 核心板** + **外挂 Air6205 WiFi核心板**，通过 airlink UART 协议验证 780EXX + Air6205 的 STA 和 AP 双模式功能。

设备通过 UART2 连接 Air6205，Air6205 连接路由器 WiFi 热点后，780EXX 即可通过 airlink 协议使用 WiFi 网络进行 HTTP 请求等网络通信；同时开启 AP 热点用于测试 Air6205 的 AP 模式功能。

### 1.2 系统工作原理

```
780EXX核心板 ──UART2(airlink协议)── Air6205(WiFi核心板)
                                            │
                                      连接路由器WiFi热点
                                            │
                                      获取IP地址(192.168.x.x)
                                            │
                            ┌───────────────┴───────────────┐
                       HTTP请求/网络通信           测试AP热点功能(test)

```

1. 设备上电后，通过 airlink UART 协议初始化 Air6205（UART2 配置 + airlink 启动）
2. Air6205 初始化完成后，自动连接预设的 WiFi 热点（SSID: luatos1234）
3. 连接成功后获取 IP 地址，780EXX 即可通过 WiFi 进行 HTTP 等网络通信
4. STA 连接成功后开启 AP 热点（名称: test, 密码: 12345678），用于测试 Air6205 的 AP 模式功能
5. 本 demo 定时发送 HTTP GET 请求，验证联网功能正常

### 1.3 核心功能特性

- **WiFi STA 联网**：780EXX 通过 airlink UART 协议驱动 Air6205 连接 WiFi 热点，验证 STA 模式联网
- **WiFi AP 功能测试**：STA 连接成功后开启 AP 热点，验证 Air6205 的 AP 模式功能
- **HTTP 请求**：联网成功后定时发送 HTTP GET 请求验证网络连通性
- **状态监控**：实时监控 airlink 连接状态和网卡状态

### 1.4 硬件接线

| Air780EXX核心板 | Air6205核心板 |
|-----------------|---------------|
| 28/U2RXD        | U1_TX         |
| 29/U2TXD        | U1_RX         |
| VBAT            | VBAT          |
| GND             | GND           |

> Air6205 通过 UART2 与 780EXX 通信，使用 airlink 协议，波特率 2000000。

### 1.5 注意事项

- Air6205 只需烧录对应固件即可，无需烧录代码
- Air6205 上电后需要约 2 秒完成硬件初始化，请耐心等待

## 演示硬件环境

1. Air780EXX 核心板/开发板一块（如 Air780EHM、Air780EHV）
2. Air6205 WiFi核心板一块
3. 配套天线一套
4. TYPE-C USB数据线一根

Air780Exx 核心板 + Air6205 核心板

![](https://docs.openluat.com/common/image/780EXX+6205-1.jpg)

Air780EXX 开发板 + Air6205 核心板

![](https://docs.openluat.com/common/image/780EXX+6205-2.jpg)

## 演示软件环境

1. Luatools 下载调试工具
2. [Air780EHM 最新固件](https://docs.openluat.com/air780epm/luatos/firmware/780ehm_version/)
3. Air6205 使用大于等于 1022 版本号的[内核固件](https://docs.openluat.com/air6205/product/firmware/)

## 演示核心步骤

1. 按照接线表连接 780EXX 核心板与 Air6205 核心板
2. 通过 Luatools 将 Air780Exx 文件夹下的 main.lua 和 network_airlink.lua 与固件烧录到核心板
3. 烧录完成后，给设备上电，观察串口日志
4. 设备启动后自动初始化 Air6205，连接 WiFi 并测试 AP 功能：

``` lua
[2026-07-20 17:55:42.902][000000000.322] D/airlink 配置心跳最大间隔为 20000ms
[2026-07-20 17:55:43.814][000000002.323] I/user.airlink_wifi_hardware_init 6205模组硬件初始化完成
[2026-07-20 17:55:43.818][000000002.324] Uart_ChangeBR 1461:uart2, 2000000 2000000 26000000 208
[2026-07-20 17:55:43.822][000000002.325] D/airlink 配置UART ID为 2
[2026-07-20 17:55:43.826][000000002.325] D/airlink 初始化AirLink
[2026-07-20 17:55:43.833][000000002.326] D/airlink 启动AirLink UART模式
[2026-07-20 17:55:43.848][000000002.337] I/airlink peer flags: rpc=1 frag=1 raw=0x00000300
[2026-07-20 17:55:43.853][000000002.338] D/airlink wifi sta上线了
[2026-07-20 17:55:43.855][000000002.347] D/airlink wifi ap已开启 0.0.0.0 c11b654
```

5. STA 联网成功，获取 IP 地址：

``` lua
[2026-07-20 17:55:43.944][000000002.441] D/DHCP find ip 8b89a8c0 192.168.137.139
[2026-07-20 17:55:43.962][000000002.453] D/DHCP DHCP acquired IP 192.168.137.139
[2026-07-20 17:55:43.963][000000002.453] D/ulwip adapter 2 ip 192.168.137.139
[2026-07-20 17:55:43.964][000000002.453] D/ulwip adapter 2 mask 255.255.255.0
[2026-07-20 17:55:43.966][000000002.453] D/ulwip adapter 2 gateway 192.168.137.1
[2026-07-20 17:55:43.971][000000002.455] D/netdrv IP_READY 2 192.168.137.139
```

6. AP 热点创建成功：

``` lua
[2026-07-20 17:55:47.104][000000005.592] I/user.开始测试AP功能...
[2026-07-20 17:55:47.125][000000005.625] I/user.AP热点开启结果: true 名称: test 密码: 12345678
```

7. HTTP GET 请求测试成功：

``` lua
[2026-07-20 17:56:11.822][000000030.322] I/user.网卡状态 true
[2026-07-20 17:56:11.827][000000030.323] I/user.发起HTTP GET请求 https://httpbin.luatos.com/bytes/2048
[2026-07-20 17:56:14.239][000000032.743] I/user.HTTP请求成功 响应码 200 响应体长度 2048
```

8. 手机连接 AP 热点后，DHCP 分配 IP 成功：

``` lua
[2026-07-20 17:56:19.049][000000037.548] I/user.dhcpsrv 是discover包 5669562A4B5C 12
[2026-07-20 17:56:19.054][000000037.549] I/user.dhcpsrv 分配ip 5669562A4B5C 192.168.4.100
[2026-07-20 17:56:19.059][000000037.549] I/user.dhcpsrv send offer
[2026-07-20 17:56:19.204][000000037.713] I/user.dhcpsrv 是request包 5669562A4B5C 12
[2026-07-20 17:56:19.210][000000037.714] I/user.dhcpsrv request,发现已经分配的mac地址, send ack 5669562A4B5C 12
```

## 注意事项

1. 如需修改连接的 WiFi 热点，请修改 `network_airlink.lua` 中的 SSID 和密码参数
2. Air6205 上电后需要约 2 秒完成硬件初始化，请耐心等待