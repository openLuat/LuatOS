## Air8201H ftp demo 说明

> 本目录为 **Air8201H**（基于 Air780EHM 模组）的 ftp demo。Air8201H **未引出 SPI 接口, 无法外挂 SPI 以太网卡**, 因此**只支持 4G 联网**, 不提供 SPI 以太网卡(netdrv_eth_spi)与以太网+4G多网卡(netdrv_multiple)两种方式。如需以太网联网请使用 Air8201G。

## 功能模块介绍

1、main.lua：主程序入口；

2、netdrv_device.lua：网卡驱动设备，固定使用 4G 网卡；

3、ftp_up_download.lua：FTP 上传下载功能模块；

4、netdrv 目录：netdrv_4g(4G网卡)。

## 演示功能概述

演示 FTP 文件上传与下载功能。

## 演示硬件环境

1、Air8201H 整机板一块 + 可上网的 SIM 卡一张 + 4G 天线一根；

2、TYPE-C USB 数据线一根。

> Air8201H 不支持 SPI 以太网，无需 AirETH_1000 配件板。

## 演示软件环境

1、Luatools 下载调试工具

2、[Air8201H固件](https://docs.openluat.com/air780epm/luatos/firmware/version/#air780ehmluatos)

## 演示核心步骤

1、搭建好硬件环境；

2、netdrv_device.lua 中默认启用 4G 网卡 `require "netdrv_4g"`；

3、修改 ftp_up_download.lua 中的 FTP 服务器地址、用户名、密码等参数；

4、烧录内核固件和 demo 脚本代码，开机运行并在 luatools 查看日志。
