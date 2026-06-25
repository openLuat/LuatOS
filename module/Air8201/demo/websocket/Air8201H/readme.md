## Air8201H websocket demo 说明

> 本目录为 **Air8201H**（基于 Air780EHM 模组）的 websocket demo。Air8201H **未引出 SPI 接口, 无法外挂 SPI 以太网卡**, 因此**只支持 4G 联网**, 不提供 SPI 以太网卡(netdrv_eth_spi)与以太网+4G多网卡(netdrv_multiple)两种方式。如需以太网联网请使用 Air8201G。

## 功能模块介绍

1、main.lua：主程序入口；

2、netdrv_device.lua：网卡驱动设备，固定使用 4G 网卡；

3、websocket_main.lua：WebSocket client 连接以及数据收发处理主逻辑；

4、websocket_receiver.lua：WebSocket client 数据发送处理模块；

5、websocket_sender.lua：WebSocket client 数据接收处理模块；

6、network_watchdog.lua：网络环境检测看门狗；

7、timer_app.lua：通知 websocket client 定时发送数据到服务器；

8、uart_app.lua：在 websocket client 和 uart 外设之间透传数据；

9、sntp_app.lua：发起 ntp 时间同步动作；

## 系统消息介绍

1、"IP_READY"：某种网卡已经获取到 ip 信息；

2、"IP_LOSE"：某种网卡已经掉网；

## 用户消息介绍

1、"RECV_DATA_FROM_SERVER"：socket client 收到服务器下发的数据后，通过此消息发布出去；

2、"SEND_DATA_REQ"：其他应用模块发布此消息，通知 WebSocket 客户端发送数据给服务器；

3、"FEED_NETWORK_WATCHDOG"：网络环境检测看门狗的喂狗消息；

## 演示功能概述

1、创建 WebSocket 连接，支持 wss 加密连接；

2、WebSocket 连接出现异常后，自动重连；

3、WebSocket client 按照以下几种逻辑发送数据给 server：

   - 串口应用功能模块 uart_app.lua，通过 uart1 接收到串口数据，将串口数据转发给 server；

   - 定时器应用功能模块 timer_app.lua，定时产生数据，将数据发送给 server；

   - 特殊命令处理：当收到"echo"命令时，会发送包含时间信息的 JSON 数据；

4、WebSocket client 收到 server 数据后，将数据增加前缀后通过 uart1 发送出去；

5、启动网络业务逻辑看门狗 task，监控网络环境；

6、网络就绪后进行 NTP 时间同步。

7、netdrv_device：固定使用 4G 网卡连接外网。

## 演示硬件环境

1、Air8201H 整机板一块 + 可上网的 SIM 卡一张 + 4G 天线一根；

2、TYPE-C USB 数据线一根 + USB 转串口数据线一根：

- Air8201H 整机板通过 TYPE-C USB 口供电；
- TYPE-C USB 数据线直接插到整机板的 TYPE-C USB 座子，另外一端连接电脑 USB 口；
- USB 转串口数据线，白线连接开发板的 UART1_TX，绿线连接开发板的 UART1_RX，黑线连接 GND，另外一端连接电脑 USB 口；

> Air8201H 不支持 SPI 以太网，无需 AirETH_1000 配件板。

## 演示软件环境

1、Luatools 下载调试工具

2、[Air8201H固件](https://docs.openluat.com/air780epm/luatos/firmware/version/)

3、PC 端的串口工具，例如 SSCOM、LLCOM 等；

## 演示核心步骤

1、搭建好硬件环境；

2、netdrv_device.lua 中默认启用 4G 网卡 `require "netdrv_4g"`；

3、Luatools 烧录内核固件和修改后的 demo 脚本代码；

4、烧录成功后，自动开机运行，如果出现以下日志，表示 WebSocket 连接成功：
```lua
I/user.WebSocket主任务 连接成功
```

5、打开 PC 端的串口工具，选择对应的端口，配置波特率 115200，数据位 8，停止位 1，无奇偶校验位；

6、PC 端的串口工具输入"echo"，点击发送，WebSocket 服务器会回复当前时间信息；

7、PC 端的串口工具输入任意数据，点击发送，数据会通过 WebSocket 发送到服务器。

