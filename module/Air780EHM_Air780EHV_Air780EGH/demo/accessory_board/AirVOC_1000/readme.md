## 功能模块介绍

1、main.lua：主程序入口；

2、voc_app.lua：每隔1秒读取一次TVOC数据；

3、AirVOC_1000.lua：AirVOC_1000驱动文件；

## 演示功能概述

AirVOC_1000是合宙设计生产的一款I2C接口的VOC(挥发性有机化合物)气体传感器配件板；

主要用于检测甲醛、一氧化碳、可燃气体、酒精、氨气、硫化物、苯系蒸汽、烟雾、其它有害气体的监测；

本demo演示的核心功能为：

Air780EHM/Air780EHV/Air780EGH核心板+AirVOC_1000配件板，每隔1秒读取1次TVOC空气质量数据；


## 核心板+配件板资料

[Air780EHM/Air780EHV/Air780EGH核心板](https://docs.openluat.com/air780ehv/product/shouce/)

[AirVOC_1000配件板相关资料](https://docs.openluat.com/accessory/AirVOC_1000/)


## 演示硬件环境

![](https://docs.openluat.com/accessory/AirVOC_1000/image/connect_Air780ehv.jpg)

1、Air780EHM/Air780EHV/Air780EGH核心板

2、AirVOC_1000配件板

3、母对母的杜邦线4根

4、Air780EHM/Air780EHV/Air780EGH核心板和AirVOC_1000配件板的硬件接线方式为

| Air780EHM/Air780EHV/Air780EGH核心板 | AirVOC_1000配件板  |
| ------------ | ------------------ |
|     3V3     |         3V3        |
|     GND   |         GND        |
| 66/I2C1SDA |         SDA        |
| 67/I2C1SCL |         SCL        |


## 演示软件环境

1、[Luatools下载调试工具](https://docs.openluat.com/air780ehv/luatos/common/download/)

2、[Air780EHM 最新版本的内核固件](https://docs.openluat.com/air780epm/luatos/firmware/version/)

3、[Air780EHV 最新版本的内核固件](https://docs.openluat.com/air780ehv/luatos/firmware/version/)

4、[Air780EGH 最新版本的内核固件](https://docs.openluat.com/air780egh/luatos/firmware/version/)


## 演示操作步骤

1、搭建好演示硬件环境

2、不需要修改demo脚本代码

3、Luatools烧录内核固件和demo脚本代码

4、烧录成功后，自动开机运行

5、通过观察Luatools的运行日志，每隔1秒出现一次类似于下面的打印，就表示测试正常

``` lua
[2025-09-25 17:36:49.445][000007163.359] I/user.空气质量 TVOC: ppb 91, ppm 0.091, 等级 1(优)
[2025-09-25 17:36:50.452][000007164.363] I/user.空气质量 TVOC: ppb 91, ppm 0.091, 等级 1(优)
