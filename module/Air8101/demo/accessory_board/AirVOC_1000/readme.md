## 功能模块介绍

1、main.lua：主程序入口；

2、voc_app.lua：每隔1秒读取一次TVOC数据；

3、AirVOC_1000.lua：AirVOC_1000驱动文件；

## 演示功能概述

AirVOC_1000是合宙设计生产的一款I2C接口的VOC(挥发性有机化合物)气体传感器配件板；

主要用于检测甲醛、一氧化碳、可燃气体、酒精、氨气、硫化物、苯系蒸汽、烟雾、其它有害气体的监测；

本demo演示的核心功能为：

Air8101核心板+AirVOC_1000配件板，每隔1秒读取1次TVOC空气质量数据；


## 核心板+配件板资料

[Air8101核心板+配件板相关资料](https://docs.openluat.com/air8101/product/shouce/#air8101_1)


## 演示硬件环境

![](https://docs.openluat.com/air8101/product/file/AirVOC_1000/hw_connection.jpg)

1、Air8101核心板

2、AirVOC_1000配件板

3、母对母的杜邦线4根

4、Air8101核心板和AirVOC_1000配件板的硬件接线方式为

- Air8101核心板通过TYPE-C USB口供电（核心板背面的功耗测试开关拨到OFF一端），此种供电方式下，vbat引脚为3.3V，可以直接给AirVOC_1000配件板供电；

- 为了演示方便，所以Air8101核心板上电后直接通过vbat引脚给AirVOC_1000配件板提供了3.3V的供电；

- 客户在设计实际项目时，一般来说，需要通过一个GPIO来控制LDO给配件板供电，这样可以灵活地控制配件板的供电，可以使项目的整体功耗降到最低；

| Air8101核心板 | AirVOC_1000配件板  |
| ------------ | ------------------ |
|     vbat     |         3V3        |
|     gnd      |         GND        |
|    38/R5     |         SDA        |
|    45/R6     |         SCL        |


## 演示软件环境

1、Luatools下载调试工具

2、[Air8101最新版本的内核固件](https://docs.openluat.com/air8101/luatos/firmware/)


## 演示操作步骤

1、搭建好演示硬件环境

2、不需要修改demo脚本代码

3、Luatools烧录内核固件和demo脚本代码

4、烧录成功后，自动开机运行

5、通过观察Luatools的运行日志，每隔1秒出现一次类似于下面的打印，就表示测试正常

``` lua
[2025-06-16 21:00:56.415] I/user.空气质量	TVOC: ppb 96, ppm 0.096, 等级 1(优)
[2025-06-16 21:00:57.425] I/user.空气质量	TVOC: ppb 98, ppm 0.098, 等级 1(优)