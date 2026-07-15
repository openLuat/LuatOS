## Air8201 lbsloc2 demo 说明

> 本目录为 Air8201（兼容 Air8201G / Air8201H）的 lbsloc2 demo。Air8201 包含两款型号：Air8201G（基于 Air780EGH 模组）、Air8201H（基于 Air780EHM 模组）。本 demo 仅支持 4G 联网方式，如需 PC 模拟器调试，请修改 netdrv_device.lua。

## 功能模块介绍

1、main.lua：主程序入口；

2、netdrv_device.lua：网卡驱动设备，支持 4G 网卡和 PC 模拟器网卡二选一；

3、lbsloc2_app.lua：合宙 lbsloc2"单基站"定位功能模块；

4、netdrv 目录：netdrv_4g（4G网卡）、netdrv_pc（PC模拟器网卡）。

## 演示功能概述

使用 Air8201 整机板测试 lbsloc2 功能：

1、lbsloc2"单基站"定位演示。

2、netdrv_device：配置连接外网使用的网卡，支持以下两种选择（二选一）：

(1) netdrv_4g：4G网卡

(2) netdrv_pc：PC模拟器网卡

本功能为免费服务，由于单基站定位技术本身的原因，无法提供相对精准的定位服务。

如对定位精度要求较高，可以参考 airlbs 的 demo，选择收费的 airlbs 定位服务，缴费地址[合宙云平台](https://iot.openluat.com/finance/order)。

## 演示硬件环境

1、Air8201 整机板一块 + 可上网的 SIM 卡一张 + 4G 天线一根；

2、TYPE-C USB 数据线一根。

## 演示软件环境

1、Luatools 下载调试工具

2、固件获取地址：

[Air8201G 固件](https://docs.openluat.com/air780egh/luatos/firmware/version/)

[Air8201H 固件](https://docs.openluat.com/air780epm/luatos/firmware/version/)

## 演示核心步骤

1、搭建好硬件环境；

2、在 netdrv_device.lua 中，按照自己的网卡需求启用对应的 Lua 文件（二选一）：

- 4G 网卡：打开 `require "netdrv_4g"`，注释掉 `require "netdrv_pc"`
- PC 模拟器：打开 `require "netdrv_pc"`，注释掉 `require "netdrv_4g"`

3、烧录内核固件和 demo 脚本代码，开机运行并在 luatools 查看日志。
