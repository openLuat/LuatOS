## 功能模块介绍

1、main.lua：主程序入口；

2、helloworld_app.lua：每3秒打印1次hello world；

## 演示功能概述

1、创建一个task；

2、在task中的任务处理函数中，每隔三秒钟通过日志输出一次hello world；

## 演示硬件环境

1、Air724UG核心板一块（或EVB_Air724UG_A14开发板）

2、USB数据线一根（Micro-USB接口，俗称老安卓口）

3、Air724UG核心板/开发板和数据线的硬件接线方式为

- 核心板/开发板通过USB口连接USB数据线，数据线的另外一端连接电脑的USB口；
- 数据线不仅用于为测试板供电，还用于查看抓取lua脚本上层和底层core日志；

## 演示软件环境

1.[Luatools 工具](https://docs.openluat.com/Luatools/)；

2.内核固件文件（底层core固件文件）：本demo开发测试时使用的固件为[LuatOS-SoC_V1008_Air724UG 版本固件](https://docs.openluat.com/air724_soc/luatos/firmware/version/)，本demo对固件版本没有什么特殊要求，所以你如果要测试本demo时，可以直接使用最新版本的内核固件；如果发现最新版本的内核固件测试有问题，可以使用我们开发本demo时使用的内核固件版本来对比测试；

## 演示核心步骤

1、搭建好硬件环境

2、Luatools烧录内核固件和demo脚本代码

3、烧录成功后，自动开机运行

4、出现类似于下面的日志，就表示运行成功：

``` lua
[2026-08-13 10:00:00.123][LTOS/N][000000003.471]:I/user.hello world
[2026-08-13 10:00:03.122][LTOS/N][000000006.471]:I/user.hello world
[2026-08-13 10:00:06.121][LTOS/N][000000009.472]:I/user.hello world
[2026-08-13 10:00:09.120][LTOS/N][000000012.472]:I/user.hello world
[2026-08-13 10:00:12.119][LTOS/N][000000015.472]:I/user.hello world
[2026-08-13 10:00:15.118][LTOS/N][000000018.473]:I/user.hello world
```