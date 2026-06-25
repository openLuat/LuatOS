## Air8201G socket demo 说明

> 本目录为 **Air8201G**（基于 Air780EGH 模组）的 socket demo。Air8201G 引出了 SPI 接口, 既支持 4G 联网, 也支持通过 SPI 外挂 CH390H 以太网卡联网, 因此保留了全部网卡方式(4G、SPI 以太网、多网卡优先级、PC 模拟器)。

## client（长连接客户端）

演示 TCP/UDP/TCP_SSL/TCP_SSL_CA 四路 socket client 长连接功能，支持自动重连、串口透传、定时发送、aircloud 数据上报、网络看门狗等。

### 功能模块介绍

1、main.lua：主程序入口；

2、netdrv_device.lua：网卡驱动设备，可以配置使用 netdrv 文件夹内的四种网卡(单 4G 网卡、单 SPI 以太网卡、单 PC 模拟器网卡、多网卡)中的任何一种；

3、tcp 文件夹：tcp client 连接以及数据收发处理逻辑；

4、udp 文件夹：udp client 连接以及数据收发处理逻辑；

5、tcp_ssl 文件夹：tcp ssl client 连接以及数据收发处理逻辑；

6、tcp_ssl_ca 文件夹：tcp ssl client 单向认证连接以及数据收发处理逻辑；

7、network_watchdog.lua：网络环境检测看门狗；

8、timer_app.lua：通知四个 client 定时发送数据到服务器；

9、uart_app.lua：在四个 client 和 uart 外设之间透传数据；

10、aircloud_data.lua：通知四个 client 上报符合 aircloud 规则的数据到 aircloud 平台。

### 网卡选择

- 单 4G 网卡：`require "netdrv_4g"`
- SPI 以太网卡：`require "netdrv_eth_spi"`
- 多网卡(以太网+4G优先级)：`require "netdrv_multiple"`
- PC 模拟器：`require "netdrv_pc"`

## server（服务器端）

演示 TCP/UDP socket server 功能，通过 SPI 以太网卡监听端口，接收 client 连接。

### 功能模块介绍

1、main.lua：主程序入口；

2、netdrv_device.lua：网卡驱动设备，固定使用 SPI 以太网卡；

3、tcp 文件夹：tcp server 连接以及数据收发处理逻辑；

4、udp 文件夹：udp server 连接以及数据收发处理逻辑；

5、timer_app.lua：定时发送数据到 client；

6、uart_app.lua：在 server 和 uart 外设之间透传数据。

## 演示硬件环境

### Air8201G 整机板

1、Air8201G 整机板一块 + 可上网的 SIM 卡一张 + 4G 天线一根；

2、TYPE-C USB 数据线一根 + USB 转串口数据线一根；

3、可选 AirETH_1000 配件板一块(用于 SPI 以太网联网), 接线方式：

| Air8201G BTB扩展板 | AirETH_1000配件板 |
| --------------- | ----------------- |
| 3V3             | 3.3v              |
| GND             | GND               |
| 86/SPI0CLK      | SCK               |
| 83/SPI0CS       | CSS               |
| 84/SPI0MISO     | SDO               |
| 85/SPI0MOSI     | SDI               |
| 22/GPIO1        | INT               |

## 演示软件环境

1、Luatools 下载调试工具

2、[Air780EGH V2012版本固件](https://docs.openluat.com/air780egh/luatos/firmware/version/)

3、PC 端的串口工具，例如 SSCOM、LLCOM 等；

4、PC 端浏览器访问[合宙TCP/UDP web测试工具](https://iot.luatos.com/#/page6/netlab)；
