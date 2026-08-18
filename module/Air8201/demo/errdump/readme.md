## Air8201 errdump demo 说明

> 本目录为 **Air8201**（兼容 Air8201G/Air8201H）的 errdump demo。

## 功能模块介绍

1、main.lua：主程序入口；

2、netdrv_device.lua：网卡驱动设备，可以配置使用 netdrv 文件夹内的网卡(4G 网卡、PC 模拟器网卡)；

3、errdump_read.lua：手动读取 errdump 异常日志功能模块；

4、auto_dump_air_srv.lua：自动上报异常日志到合宙服务器中；

5、auto_dump_udp_srv.lua：自动上报异常日志到自建 UDP 服务器中；

6、uart_app.lua：uart 应用层，用于将手动读取的异常日志通过串口发出去；

7、errdump_tcp 目录：将手动读取到的日志发到 TCP 服务器中；

8、netdrv 目录：netdrv_4g(4G网卡)、netdrv_pc(PC模拟器网卡)。

## 演示功能概述

本 demo 演示四种 errdump 异常日志上报功能，使用时根据自己需求在 main.lua 中选择要使用的功能，注意不能同时使用自动上报和手动读取功能：

1、自动上报异常日志到 iot 平台；

2、自动上报异常日志到自建 UDP 服务器；

3、手动读取异常日志并通过串口传输；

4、手动读取异常日志并通过 TCP 传输。

## 演示硬件环境

1、Air8201 整机板一块 + 可上网的 SIM 卡一张 + 4G 天线一根；

2、TYPE-C USB 数据线一根 + USB 转串口数据线一根（手动读取并串口传输时需要）。

## 演示软件环境

1、Luatools 下载调试工具

2、[Air8201G固件(基于Air780EGH)](https://docs.openluat.com/air780egh/luatos/firmware/version/)

3、[Air8201H固件(基于Air780EHM)](https://docs.openluat.com/air780epm/luatos/firmware/version/#air780ehmluatos)

4、PC 端浏览器访问[合宙 TCP/UDP web 测试工具](https://netlab.luatos.com/)

## 演示核心步骤

1、搭建好硬件环境；

2、netdrv_device.lua 中默认启用 4G 网卡 `require "netdrv_4g"`(如在 PC 模拟器上测试, 可改用 `require "netdrv_pc"`)；

3、在 main.lua 文件中选择好要使用的功能；

4、烧录内核固件和 demo 脚本代码，开机运行并在 luatools 查看日志。
