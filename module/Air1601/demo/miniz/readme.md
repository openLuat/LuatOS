## 功能模块介绍

1、main.lua：主程序入口；

2、miniz_app.lua：如何对数据压缩解压；

## 演示功能概述

1、创建一个task；

2、演示如何对数据压缩解压；

## 演示硬件环境

参考：[硬件环境清单](https://docs.openluat.com/air1601/luatos/common/hwenv/)，准备以及组装好硬件环境。

## **演示软件环境**

1.[Luatools 工具](https://docs.openluat.com/air780epm/common/Luatools/)；

2.内核固件文件（底层 core 固件文件）：[LuatOS-SoC_V1004_Air1601.soc](https://docs.openluat.com/air1601/luatos/firmware/) ；

## 演示核心步骤

1、搭建好硬件环境

2、Luatools烧录内核固件和demo脚本代码

3、烧录成功后，自动开机运行

4、出现类似于下面的日志，就表示运行成功：

``` lua
[2025-10-28 11:39:11.816][000000000.379] I/user.miniz 压缩过的数据长度:  156 解压后的数据长度： 235
[2025-10-28 11:39:11.821][000000000.380] I/user.压缩前的字符串： 108 abcd1234567890efghijklmnopqrstuvwxyzabcd1234567890efghijklmnopqrstuvwxyzabcd1234567890efghijklmnopqrstuvwxyz
[2025-10-28 11:39:11.826][000000000.383] I/user.压缩后的字符串： 92 780105C0040D80B04A383CCEDDDD9F9E4184C97E9CD7FDBC1FD828E3422A6DACF321A65C6AEB632E8830D98FF3BA9FF7031B655C48A58D753EC4944B6D7DCC051126FB715EF7F37E60A38C0BA9B4B1CE879872A9AD8FB97E17A42785 184
[2025-10-28 11:39:11.832][000000000.383] I/user.解压后的字符串： 108 abcd1234567890efghijklmnopqrstuvwxyzabcd1234567890efghijklmnopqrstuvwxyzabcd1234567890efghijklmnopqrstuvwxyz
[2025-10-28 11:39:11.836][000000000.389] I/user.miniz 压缩前的数据长度:  2048 压缩后的数据长度:  1350
```
