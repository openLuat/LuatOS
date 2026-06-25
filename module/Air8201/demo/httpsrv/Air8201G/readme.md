## Air8201G httpsrv demo 说明

> 本目录为 **Air8201G**（基于 Air780EGH 模组）的 httpsrv demo。Air8201G 引出了 SPI 接口, 支持通过 SPI 外挂 CH390H 以太网卡联网, 因此保留以太网 SPI 模式演示。

## 功能模块介绍

1、main.lua：主程序入口；

2、httpsrv_start.lua：HTTP服务器实现模块，包含服务器初始化、路由处理、文本发送和WiFi扫描功能；

3、index.html：Web控制界面，提供LED控制按钮、文本发送输入框和WiFi扫描功能；

4、netdrv_eth_spi.lua：以太网SPI网卡驱动模块，通过SPI接口连接CH390H芯片实现有线网络连接。

## 演示功能概述

1、HTTP服务器：创建Web服务器，提供Web控制界面

- 支持以太网SPI模式
- HTTP服务器监听80端口，通过网线连接网络，IP地址由路由器DHCP分配
- 支持访问Web控制界面

2、文本发送功能：通过Web界面发送文本数据

- 提供文本发送（/send/text）接口
- 支持在Web界面的输入框中输入文本并发送
- 发送的文本会在设备日志中显示

3、WiFi扫描功能：搜索周围可用的WiFi热点

- 提供开始扫描（/scan/go）接口
- 提供获取扫描结果（/scan/list）接口
- Web界面上有扫描按钮，点击后显示周围WiFi热点列表
- 显示WiFi的SSID和信号强度信息

## 演示硬件环境

1、Air8201G 整机板一块 + BTB扩展板一块 + 可上网的 SIM 卡一张 + 4G 天线一根；

2、TYPE-C USB 数据线一根；

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

1、确保AirETH_1000配件板正确连接到Air8201G BTB扩展板

2、使用网线将AirETH_1000配件板连接到路由器或网络交换机

3、使用Luatools烧录内核固件和demo脚本代码

4、烧录成功后，设备自动开机运行并尝试通过AirETH_1000配件板连接到网络

5、通过Luatools日志查看设备获取的IP地址（例如：192.168.1.101）

6、确保你的电脑连接到同一路由器或网络

7、在浏览器中输入设备的IP地址（如http://192.168.1.101），访问Web控制界面

## Web控制界面功能

在浏览器访问Web控制界面后，你可以使用以下功能：

- 发送文本消息（会显示在设备日志中）
- 点击WiFi扫描按钮，查看周围可用的WiFi热点列表
