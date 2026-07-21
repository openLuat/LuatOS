## Air8201 http demo 说明

> 本目录为 **Air8201**（基于 Air780EGH / Air780EHM 模组）的 http demo。支持 4G 和 PC 模拟器两种联网方式，无需 SPI 以太网卡，统一适配 Air8201G 和 Air8201H。

## 功能模块介绍

1、main.lua：主程序入口；

2、netdrv_device.lua：网卡驱动设备，可以配置使用 4G 网卡或 PC 模拟器网卡；

3、http_app.lua：HTTP 请求功能模块，演示 HTTP GET/POST 等请求；

4、httpplus_app.lua：HTTP 增强功能模块，演示 HTTP 文件上传等功能；

5、netdrv 目录：netdrv_4g(4G网卡)、netdrv_pc(PC模拟器网卡)。

## 演示功能概述

演示 HTTP 网络请求功能，包括 GET/POST 请求、文件上传下载等。

## 演示硬件环境

1、Air8201 整机板一块 + 可上网的 SIM 卡一张 + 4G 天线一根；

2、TYPE-C USB 数据线一根。

## 演示软件环境

1、Luatools 下载调试工具

2、[Air8201G固件](https://docs.openluat.com/air780egh/luatos/firmware/version/)

3、[Air8201H固件](https://docs.openluat.com/air780epm/luatos/firmware/version/)

## 演示核心步骤

1、搭建好硬件环境；

2、在 netdrv_device.lua 中，按照自己的网卡需求启用对应的 Lua 文件（二选一）：

- 4G 网卡：打开 `require "netdrv_4g"`（默认启用）
- PC 模拟器网卡：注释 `netdrv_4g`，打开 `require "netdrv_pc"`

3、烧录内核固件和 demo 脚本代码，开机运行并在 luatools 查看日志。