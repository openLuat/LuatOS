## Air8201G websocket demo 说明

> 本目录为 **Air8201G**（基于 Air780EGH 模组）的 websocket demo。Air8201G 引出了 SPI 接口, 既支持 4G 联网, 也支持通过 SPI 外挂 CH390H 以太网卡联网, 因此保留了全部网卡方式(4G、SPI 以太网、多网卡优先级、PC 模拟器)。

## 功能模块介绍

1、main.lua：主程序入口；

2、netdrv_device.lua：网卡驱动设备，可以配置使用 netdrv 文件夹内的四种网卡(单 4G 网卡、单 SPI 以太网卡、单 PC 模拟器网卡、多网卡)中的任何一种；

3、websocket_main.lua：WebSocket client 连接以及数据收发处理主逻辑；

4、websocket_receiver.lua：WebSocket client 数据发送处理模块；

5、websocket_sender.lua：WebSocket client 数据接收处理模块；

6、network_watchdog.lua：网络环境检测看门狗；

7、timer_app.lua：通知 websocket client 定时发送数据到服务器；

8、sntp_app.lua：发起 ntp 时间同步动作；

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

   - 定时器应用功能模块 timer_app.lua，定时产生数据，将数据发送给 server；

   - 特殊命令处理：当收到"echo"命令时，会发送包含时间信息的 JSON 数据；

4、启动网络业务逻辑看门狗 task，监控网络环境；

5、网络就绪后进行 NTP 时间同步。

6、netdrv_device：配置连接外网使用的网卡，支持以下选择（四选一）

   (1) netdrv_4g：4G 网卡

   (2) netdrv_eth_spi：通过 SPI 外挂 CH390H 芯片的以太网卡

   (3) netdrv_multiple：以太网+4G 多网卡优先级

   (4) netdrv_pc：PC 模拟器网卡

## 演示硬件环境

1、Air8201G 整机板一块 + BTB扩展板一块 + 可上网的 SIM 卡一张 + 4G 天线一根；

2、TYPE-C USB 数据线一根 + USB 转串口数据线一根：

- Air8201G BTB扩展板通过 TYPE-C USB 口供电；
- TYPE-C USB 数据线直接插到 BTB扩展板的 TYPE-C USB 座子，另外一端连接电脑 USB 口；

3、可选 AirETH_1000 配件板一块(用于 SPI 以太网联网), 接线方式：

| Air8201G BTB扩展板 | AirETH_1000配件板 |
| --------------- | ----------------- |
| VBAT            | 3.3v              |
| gnd             | gnd               |
| spi_clk         | SCK               |
| spi_cs          | CSS               |
| spi_miso        | SDO               |
| spi_mosi        | SDI               |
| GPIO34          | INT               |

## 演示软件环境

1、Luatools 下载调试工具

2、[Air8201G固件](https://docs.openluat.com/air780egh/luatos/firmware/version/)


## 演示核心步骤

1、搭建好硬件环境；

2、在 netdrv_device.lua 中，按照自己的网卡需求启用对应的 Lua 文件(四种网卡选择其一)：

- 单 4G 网卡：打开 `require "netdrv_4g"`，其余注释掉
- SPI 以太网卡：打开 `require "netdrv_eth_spi"`，其余注释掉
- 多网卡(以太网+4G优先级)：打开 `require "netdrv_multiple"`，其余注释掉
- PC 模拟器：打开 `require "netdrv_pc"`，其余注释掉

3、Luatools 烧录内核固件和修改后的 demo 脚本代码；

4、烧录成功后，自动开机运行，如果出现以下日志，表示 WebSocket 连接成功：
```lua
I/user.WebSocket主任务 连接成功
``