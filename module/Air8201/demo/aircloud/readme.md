## Air8201 aircloud demo 说明

> 本目录为 **Air8201**（兼容 Air8201G/Air8201H）的 aircloud demo。

## 功能模块介绍

1、main.lua：主程序入口；

2、netdrv_device.lua：网卡驱动设备，可以配置使用 netdrv 文件夹内的网卡(4G 网卡、PC 模拟器网卡)；

3、excloud_test.lua：aircloud 的应用模块，实现了 aircloud 的应用场景；

4、netdrv 目录：netdrv_4g(4G网卡)、netdrv_pc(PC模拟器网卡)。

## 演示功能概述

AirCloud 是 LuatOS 物联网设备云服务通信协议, 提供设备连接、数据上报、远程控制和文件上传等核心功能。excloud 扩展库是 AirCloud 协议的实现, 通过该库设备可以快速接入云服务平台。

本 demo 演示了 excloud 扩展库的完整使用流程, 包括：设备连接与认证、数据上报与接收、运维日志管理、文件上传功能、心跳保活机制。

## 演示硬件环境

1、Air8201 整机板一块 + 可上网的 SIM 卡一张 + 4G 天线一根；

2、TYPE-C USB 数据线一根。

## 演示软件环境

1、Luatools 下载调试工具

2、[Air8201G固件(基于Air780EGH)](https://docs.openluat.com/air780egh/luatos/firmware/version/)

3、[Air8201H固件(基于Air780EHM)](https://docs.openluat.com/air780epm/luatos/firmware/version/#air780ehmluatos)

## 演示核心步骤

1、搭建好硬件环境；

2、netdrv_device.lua 中默认启用 4G 网卡 `require "netdrv_4g"`(如在 PC 模拟器上测试, 可改用 `require "netdrv_pc"`)；

3、修改 excloud_test.lua 中 excloud.setup 接口的相关参数；

4、烧录内核固件和 demo 脚本代码，开机运行并在 luatools 查看日志。

