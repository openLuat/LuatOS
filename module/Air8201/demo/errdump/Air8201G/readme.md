## Air8201G errdump demo 说明

> 本目录为 **Air8201G**（基于 Air780EGH 模组）的 errdump demo。Air8201G 引出了 SPI 接口, 既支持 4G 联网, 也支持通过 SPI 外挂 CH390H 以太网卡联网, 因此保留了全部网卡方式(4G、SPI 以太网、多网卡优先级、PC 模拟器)。
>
> 由于Air8201G并未有uart引出，故此代码不再展示串口读取异常日志的功能。

## 功能模块介绍

1、main.lua：主程序入口；

2、netdrv_device.lua：网卡驱动设备，可以配置使用 netdrv 文件夹内的四种网卡(单 4G 网卡、单 SPI 以太网卡、单 PC 模拟器网卡、多网卡)中的任何一种；

3、errdump_read.lua：手动读取 errdump 异常日志功能模块；

4、auto_dump_air_srv.lua：自动上报异常日志到合宙服务器中；

5、auto_dump_udp_srv.lua：自动上报异常日志到自建 UDP 服务器中；

6、errdump_tcp 目录：将手动读取到的日志发到 TCP 服务器中；

7、netdrv 目录：netdrv_4g(4G网卡)、netdrv_eth_spi(SPI外挂CH390H以太网卡)、netdrv_multiple(以太网+4G多网卡优先级)、netdrv_pc(PC模拟器网卡)。

## 演示功能概述

本 demo 演示四种 errdump 异常日志上报功能，使用时根据自己需求在 main.lua 中选择要使用的功能，注意不能同时使用自动上报和手动读取功能：

1、自动上报异常日志到 iot 平台；

2、自动上报异常日志到自建 UDP 服务器；

3、手动读取异常日志并通过 TCP 传输。

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

3、PC 端浏览器访问[合宙 TCP/UDP web 测试工具](https://netlab.luatos.com/)

## 演示核心步骤

1、搭建好硬件环境；

2、在 netdrv_device.lua 中，按照自己的网卡需求启用对应的 Lua 文件(四种网卡选择其一)：

- 单 4G 网卡：打开 `require "netdrv_4g"`，其余注释掉
- SPI 以太网卡：打开 `require "netdrv_eth_spi"`，其余注释掉
- 多网卡(以太网+4G优先级)：打开 `require "netdrv_multiple"`，其余注释掉

3、在 main.lua 文件中选择好要使用的功能；

4、烧录内核固件和 demo 脚本代码，开机运行并在 luatools 查看日志。

