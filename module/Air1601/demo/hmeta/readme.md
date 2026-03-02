## 功能模块介绍

1、main.lua：主程序入口；

2、hmeta_app.lua：获取模块相关信息包括获取模组名称，硬件版本号，原始芯片型号；

## 演示功能概述

1、创建一个task；

2、在task中的任务处理函数中，每隔三秒钟通过日志输出一次模组名称，硬件版本号，原始芯片型号；


## 演示硬件环境

![](https://docs.openLuat.com/cdn//image/Air1601/1101开发板.JPEG)

1、Air811601开发板一块

2、TYPE-C USB数据线一根

3、Air1601开发板和数据线的硬件接线方式为

- Air1601开发板通过TYPE-C USB口连接TYPE-C USB 数据线，数据线的另外一端连接电脑的USB口；
- Air1601开发板通过TYPE-C USB口供电；


## 演示软件环境

1、[Luatools下载调试工具](https://docs.openluat.com/air8101/luatos/common/download/)

2、[Air1601 最新版本的内核固件](https://gitee.com/openLuat/LuatOS/releases/tag/v1004.air1601.release)


## 演示核心步骤

1、搭建好硬件环境

2、Luatools烧录内核固件和demo脚本代码

3、烧录成功后，自动开机运行

4、出现类似于下面的日志，就表示运行成功：

``` lua
[2026-03-02 10:07:19.590][LTOS/N][000000003.015]:I/user.hmeta Air1601 A10 CCM4211
[2026-03-02 10:07:22.592][LTOS/N][000000006.016]:I/user.hmeta Air1601 A10 CCM4211
[2026-03-02 10:07:25.588][LTOS/N][000000009.016]:I/user.hmeta Air1601 A10 CCM4211
```
