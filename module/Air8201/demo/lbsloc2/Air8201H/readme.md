## Air8201H lbsloc2 demo 说明

> 本目录为 **Air8201H**（基于 Air780EHM 模组）的 lbsloc2 demo。Air8201H **未引出 SPI 接口, 无法外挂 SPI 以太网卡**, 因此**只支持 4G 联网**, 不提供 SPI 以太网卡(netdrv_eth_spi)与以太网+4G多网卡(netdrv_multiple)两种方式。如需以太网联网请使用 Air8201G。

## 功能模块介绍

1、main.lua：主程序入口；

2、netdrv_device.lua：网卡驱动设备，固定使用 4G 网卡；

3、lbsloc2_app.lua：合宙 lbsloc2"单基站"定位功能模块；

4、netdrv 目录：netdrv_4g(4G网卡)。

## 演示功能概述

使用 Air8201H 整机板测试 lbsloc2 功能：

1、lbsloc2"单基站"定位演示。

2、netdrv_device：固定使用 4G 网卡连接外网。

本功能为免费服务，由于单基站定位技术本身的原因，无法提供相对精准的定位服务。

如对定位精度要求较高，可以参考 airlbs 的 demo，选择收费的 airlbs 定位服务，缴费地址[合宙云平台](https://iot.openluat.com/finance/order)。

## 演示硬件环境

1、Air8201H 整机板一块 + 可上网的 SIM 卡一张 + 4G 天线一根；

2、TYPE-C USB 数据线一根。

> Air8201H 不支持 SPI 以太网，无需 AirETH_1000 配件板。

## 演示软件环境

1、Luatools 下载调试工具

2、[Air8201H固件](https://docs.openluat.com/air780epm/luatos/firmware/version/)（理论上，2025年8月10日之后发布的固件都可以）

## 演示核心步骤

1、搭建好硬件环境；

2、netdrv_device.lua 中默认启用 4G 网卡 `require "netdrv_4g"`；

3、烧录内核固件和 demo 脚本代码，开机运行并在 luatools 查看日志。
