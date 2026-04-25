## 功能模块介绍

1、main.lua：主程序入口；

2、helloworld_app.lua：每3秒打印1次hello world；

## 演示功能概述

1、创建一个task；

2、在task中的任务处理函数中，每隔三秒钟通过日志输出一次hello world；

## 演示硬件环境

参考：[硬件环境清单](https://docs.openluat.com/air1601/luatos/common/hwenv/)，准备以及组装好硬件环境。

## 演示软件环境

1.[Luatools 工具](https://docs.openluat.com/air780epm/common/Luatools/)；

2.内核固件文件（底层 core 固件文件）：本demo开发测试时使用的固件为[Air6101 V1010 版本固件](https://docs.openluat.com/air1601/luatos/firmware/)，本demo对固件版本没有什么特殊要求，所以你如果要测试本demo时，可以直接使用最新版本的内核固件；如果发现最新版本的内核固件测试有问题，可以使用我们开发本demo时使用的内核固件版本来对比测试；

## 演示核心步骤

1、搭建好硬件环境

2、Luatools烧录内核固件和demo脚本代码

3、烧录成功后，自动开机运行

4、出现类似于下面的日志，就表示运行成功：

``` lua
[2026-04-15 16:28:00.277][LTOS/N][000000201.039]:I/user.hello world
[2026-04-15 16:28:03.265][LTOS/N][000000204.039]:I/user.hello world
[2026-04-15 16:28:06.249][LTOS/N][000000207.039]:I/user.hello world
[2026-04-15 16:28:09.246][LTOS/N][000000210.040]:I/user.hello world
[2026-04-15 16:28:12.245][LTOS/N][000000213.040]:I/user.hello world
[2026-04-15 16:28:15.229][LTOS/N][000000216.040]:I/user.hello world
[2026-04-15 16:28:18.217][LTOS/N][000000219.041]:I/user.hello world

```
