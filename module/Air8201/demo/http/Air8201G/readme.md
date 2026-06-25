## Air8201G http demo 说明

> 本目录为 **Air8201G**（基于 Air780EGH 模组）的 http demo。Air8201G 引出了 SPI 接口, 既支持 4G 联网, 也支持通过 SPI 外挂 CH390H 以太网卡联网, 因此保留了全部网卡方式(4G、SPI 以太网、多网卡优先级、PC 模拟器)。

## 功能模块介绍

1、main.lua：主程序入口；

2、netdrv_device.lua：网卡驱动设备，可以配置使用 netdrv 文件夹内的四种网卡(单 4G 网卡、单 SPI 以太网卡、单 PC 模拟器网卡、多网卡)中的任何一种；

3、http_app.lua：HTTP 请求功能模块，演示 HTTP GET/POST 等请求；

4、httpplus_app.lua：HTTP 增强功能模块，演示 HTTP 文件上传等功能；

5、netdrv 目录：netdrv_4g(4G网卡)、netdrv_eth_spi(SPI外挂CH390H以太网卡)、netdrv_multiple(以太网+4G多网卡优先级)、netdrv_pc(PC模拟器网卡)。

## 演示功能概述

演示 HTTP 网络请求功能，包括 GET/POST 请求、文件上传下载等。

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

1、搭建好硬件环境；

2、在 netdrv_device.lua 中，按照自己的网卡需求启用对应的 Lua 文件(四种网卡选择其一)：

- 单 4G 网卡：打开 `require "netdrv_4g"`，其余注释掉
- SPI 以太网卡：打开 `require "netdrv_eth_spi"`，其余注释掉
- 多网卡(以太网+4G优先级)：打开 `require "netdrv_multiple"`，其余注释掉

3、烧录内核固件和 demo 脚本代码，开机运行并在 luatools 查看日志。

## 完整代码与说明请参考

[Air780EHM_Air780EHV_Air780EGH/demo/http](https://gitee.com/openLuat/LuatOS/tree/master/module/Air780EHM_Air780EHV_Air780EGH/demo/http)
