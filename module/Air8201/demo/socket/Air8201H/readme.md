## Air8201H socket demo 说明

> 本目录为 **Air8201H**（基于 Air780EHM 模组）的 socket demo。Air8201H **未引出 SPI 接口, 无法外挂 SPI 以太网卡**, 因此**只支持 4G 联网**, 不提供 SPI 以太网卡(netdrv_eth_spi)与以太网+4G多网卡(netdrv_multiple)两种方式。如需以太网联网请使用 Air8201G。

## client（长连接客户端）

演示 TCP/UDP/TCP_SSL/TCP_SSL_CA 四路 socket client 长连接功能，支持自动重连、串口透传、定时发送、aircloud 数据上报、网络看门狗等。

### 功能模块介绍

1、main.lua：主程序入口；

2、netdrv_device.lua：网卡驱动设备，固定使用 4G 网卡；

3、tcp 文件夹：tcp client 连接以及数据收发处理逻辑；

4、udp 文件夹：udp client 连接以及数据收发处理逻辑；

5、tcp_ssl 文件夹：tcp ssl client 连接以及数据收发处理逻辑；

6、tcp_ssl_ca 文件夹：tcp ssl client 单向认证连接以及数据收发处理逻辑；

7、network_watchdog.lua：网络环境检测看门狗；

8、timer_app.lua：通知四个 client 定时发送数据到服务器；

9、uart_app.lua：在四个 client 和 uart 外设之间透传数据；

10、aircloud_data.lua：通知四个 client 上报符合 aircloud 规则的数据到 aircloud 平台。

## server（服务器端）

> **Air8201H 不支持 SPI 以太网，无法运行 socket server demo。**
>
> 本 socket server demo 演示的是通过 SPI 以太网卡创建 TCP/UDP 服务器端的功能，该功能依赖 SPI 以太网硬件。如需使用 socket server 功能，请使用 Air8201G。

## 演示硬件环境

1、Air8201H 整机板一块 + 可上网的 SIM 卡一张 + 4G 天线一根；

2、TYPE-C USB 数据线一根 + USB 转串口数据线一根；

> Air8201H 不支持 SPI 以太网，无需 AirETH_1000 配件板。

## 演示软件环境

1、Luatools 下载调试工具

2、[Air8201H固件](https://docs.openluat.com/air780epm/luatos/firmware/version/)

3、PC 端的串口工具，例如 SSCOM、LLCOM 等；

4、PC 端浏览器访问[合宙TCP/UDP web测试工具](https://iot.luatos.com/#/page6/netlab)；

## 完整代码与说明请参考

[Air780EHM_Air780EHV_Air780EGH/demo/socket](https://gitee.com/openLuat/LuatOS/tree/master/module/Air780EHM_Air780EHV_Air780EGH/demo/socket)
