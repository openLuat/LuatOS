## 功能模块介绍

1、main.lua：主程序入口，负责初始化系统环境；

2、log_test.lua：日志功能测试模块，演示Air8101的日志输出功能；

## 演示功能概述

1、log_test：日志输出等级测试

默认日志输出等级为 DEBUG，即输出 debug 及以上级别的日志；

log.setLevel("INFO")： 输出 info 及以上级别的日志；

log.setLevel("WARN")： 输出 warn 及以上级别的日志；

log.setLevel("ERROR")： 输出 error 级别的日志；

log.setLevel("SILENT")： 静默所有日志，即禁止日志有任何内容输出；

## 演示硬件环境

![](https://docs.openluat.com/air1601/luatos/common/download/image/download.jpg)

1、Air1601开发板一块

2、TYPE-C USB数据线一根

3、Air1601开发板和数据线的硬件接线方式为

- Air1601开发板通过TYPE-C USB口连接TYPE-C USB 数据线，数据线的另外一端连接电脑的USB口；
- 在 Air1601 开发板上丝印标注 USB1，为芯片烧录下载接口；
- 若遇到因电脑 USB 端口供电不足导致的烧录失败，也可改用外部稳压电源通过开发板上的 VIN 引脚进行供电；

购买链接：[Air1601开发板 多功能5寸RGB屏 支持AirUI 摄像头 代开发固件-淘宝网](https://item.taobao.com/item.htm?id=1044228452703&pisk=g7HxDK_zIUYm-T9WJtAoI2UYUF-oHQm4wqoCIP4c143-zDKVIcagBV3tWrV6u-Dtycgp0lYqIbItY43T_nzg5P3ifjxkKpmq0Ry_BevHK46Wu23Aco1XfuZLv3qfMjIVRRy6-FClCSJLQq3lG8S1NuazXtZ_GVN7Vl47cONs5zN7Al6bCRg62_Z_vO_1ho97FzrT5Oa_17s7YkE1lRaX20azjRas5St-Vzr_CPG8aFU5cPXtNNVatv6IJO6seoFWZmaSFYKgcSHnDzLB-YpUMyibyOTj2W9QWzkBrQnrJjg04VppyJGEyAFQBKQUDbiLFr2B9_exqqkLhvLAnu2zoWG_wn9j2-UYwo0lc1ex1qkTgjIwY0wjzXzUGQ8z2xD36yPRPEio2rNK6qYPCrcKV4FnEaX3dXu-BWwC4_knpbbl-yEGG3KR_1Pb4Q1kC7_UChGa2yxvB15aa3r8-3KR_1Pb4uUHDhCN_7-P.&spm=a1z10.3-c-s.w4002-24045920836.13.3ff26ee5hNJu5K)

## 准备软件环境

### 4.1 软件环境

1. 烧录工具：[Luatools 下载调试工具](https://docs.openluat.com/air780epm/common/Luatools/)；

2. 内核固件文件（底层 core 固件文件）：[LuatOS-SoC_V1004_Air1601.soc]((https://gitee.com/openLuat/LuatOS/releases/tag/v1004.air1601.release))；

3. .luatos 需要的脚本和资源文件

- 脚本文件：[https://gitee.com/openLuat/LuatOS/tree/master/module/Air1601/demo/log](https://gitee.com/openLuat/LuatOS/tree/master/module/Air1601/demo/log)

- LuatOS 运行所需要的 lib 文件：使用 Luatools 烧录时，勾选 添加默认 lib 选项，使用默认 lib 脚本文件。

准备好软件环境之后，接下来查看[如何烧录项目文件到 Air1601开发板](https://docs.openluat.com/air1601/luatos/common/hwenv/)中，将本篇文章中演示使用的项目文件烧录到 Air1601开发板中。

###  API 介绍

log 库：[https://docs.openluat.com/osapi/core/log/](https://docs.openluat.com/osapi/core/log/)


## 演示核心步骤

1、搭建好硬件环境

2、Luatools烧录内核固件和demo脚本代码

3、烧录成功后，自动开机运行，通过luatools日志可以观察到以下信息：

``` lua
[2026-03-02 10:53:48.510][LTOS/N][000000000.013]:I/user.main project name is  logdemo version is  001.000.000
[2026-03-02 10:53:48.510][LTOS/N][000000000.015]:日志功能测试开始
[2026-03-02 10:53:48.515][LTOS/N][000000000.016]:默认日志级别: 1
[2026-03-02 10:53:48.515][LTOS/N][000000000.016]:测试日志级别: 1
[2026-03-02 10:53:48.520][LTOS/N][000000000.016]:D/user.logdemo debug message
[2026-03-02 10:53:48.520][LTOS/N][000000000.016]:I/user.logdemo info message
[2026-03-02 10:53:48.526][LTOS/N][000000000.016]:W/user.logdemo warn message
[2026-03-02 10:53:48.526][LTOS/N][000000000.016]:E/user.logdemo error message
[2026-03-02 10:53:48.531][LTOS/N][000000000.016]:测试日志级别: INFO
[2026-03-02 10:53:48.531][LTOS/N][000000000.016]:I/user.logdemo info message
[2026-03-02 10:53:48.531][LTOS/N][000000000.016]:W/user.logdemo warn message
[2026-03-02 10:53:48.536][LTOS/N][000000000.016]:E/user.logdemo error message
[2026-03-02 10:53:48.536][LTOS/N][000000000.016]:测试日志级别: WARN
[2026-03-02 10:53:48.541][LTOS/N][000000000.017]:W/user.logdemo warn message
[2026-03-02 10:53:48.546][LTOS/N][000000000.017]:E/user.logdemo error message
[2026-03-02 10:53:48.546][LTOS/N][000000000.017]:测试日志级别: ERROR
[2026-03-02 10:53:48.546][LTOS/N][000000000.017]:E/user.logdemo error message
[2026-03-02 10:53:48.552][LTOS/N][000000000.017]:测试日志级别: SILENT
[2026-03-02 10:53:48.557][LTOS/N][000000000.017]:恢复默认日志输出等级: 1
[2026-03-02 10:53:48.562][LTOS/N][000000000.017]:I/user.logdemo 数值: 123 布尔值: true 表: table: 1C27EDF0
```
