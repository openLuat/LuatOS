## 功能模块介绍

1、main.lua：主程序入口；

2、hmeta_app.lua：获取模块相关信息包括获取模组名称，硬件版本号，原始芯片型号；

## 演示功能概述

1、创建一个task；

2、在task中的任务处理函数中，每隔三秒钟通过日志输出一次模组名称，硬件版本号，原始芯片型号；


## 演示硬件环境

![](https://docs.openluat.com/air780ehv/luatos/common/hwenv/image/Air780EHV2.png)

1、Air780EHM/Air780EHV/Air780EGH核心板一块

2、TYPE-C USB数据线一根

3、Air780EHM/Air780EHV/Air780EGH核心板和数据线的硬件接线方式为

- Air780EHM/Air780EHV/Air780EGH核心板通过TYPE-C USB口连接TYPE-C USB 数据线，数据线的另外一端连接电脑的USB口；
- 核心板正面的 ON/OFF 拨动开关 拨到ON一端；


## 演示软件环境

1、[Luatools下载调试工具](https://docs.openluat.com/air780ehv/luatos/common/download/)

2、[Air780EHM 最新版本的内核固件](https://docs.openluat.com/air780epm/luatos/firmware/version/)

3、[Air780EHV 最新版本的内核固件](https://docs.openluat.com/air780ehv/luatos/firmware/version/)

4、[Air780EGH 最新版本的内核固件](https://docs.openluat.com/air780egh/luatos/firmware/version/)


## 演示核心步骤

1、搭建好硬件环境

2、Luatools烧录内核固件和demo脚本代码

3、烧录成功后，自动开机运行

4、出现类似于下面的日志，就表示运行成功：

``` lua
[2025-10-20 17:53:50.355][000000006.254] I/user.hmeta Air780EHV A11 EC718HM
[2025-10-20 17:53:53.353][000000009.254] I/user.hmeta Air780EHV A11 EC718HM
[2025-10-20 17:53:56.356][000000012.254] I/user.hmeta Air780EHV A11 EC718HM

```
