## 功能模块介绍

1、main.lua：主程序入口；

2、miniz_app.lua：如何对数据压缩解压；

## 演示功能概述

1、创建一个task；

2、演示如何对数据压缩解压；


## 演示硬件环境

![](https://docs.openluat.com/luatos_lesson/image/Evh1bVjatoG1rCxhrdpc9ny7nVf.png)

1、Air8000核心板一块

2、TYPE-C USB数据线一根

3、Air8000核心板和数据线的硬件接线方式为

- Air8000核心板通过TYPE-C USB口连接TYPE-C USB 数据线，数据线的另外一端连接电脑的USB口；
- 核心板正面的 供电/充电 拨动开关 拨到供电一端；
- 核心板背面的 USB ON/USB OFF 拨动开关 拨到USB ON一端；


## 演示软件环境

1、[Luatools下载调试工具](https://docs.openluat.com/air8000/luatos/common/download/)

2、[Air8000 最新版本的内核固件](https://docs.openluat.com/air8000/luatos/firmware/)


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
