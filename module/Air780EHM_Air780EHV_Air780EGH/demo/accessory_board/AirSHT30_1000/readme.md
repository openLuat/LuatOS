## 功能模块介绍

1、main.lua：主程序入口；

2、sht30_app.lua：每隔1秒读取一次温湿度数据；

3、AirSHT30_1000.lua：AirSHT30_1000驱动文件；

## 演示功能概述

AirSHT30_1000是合宙设计生产的一款I2C接口的SHT30温湿度传感器配件板；

本demo演示的核心功能为：

Air780EHM/Air780EHV/Air780EGH核心板+AirSHT30_1000配件板，每隔1秒读取1次温湿度数据；


## 核心板+配件板资料

[Air780EHM/Air780EHV/Air780EGH核心板](https://docs.openluat.com/air780ehv/product/shouce/)

[AirSHT30_1000配件板相关资料](https://docs.openluat.com/accessory/AirSHT30_1000/)


## 演示硬件环境

![](https://docs.openluat.com/accessory/AirSHT30_1000/image/connect_780ehv.png)

1、Air780EHM/Air780EHV/Air780EGH核心板

2、AirSHT30_1000配件板

3、母对母的杜邦线4根

| Air780EHM/Air780EHV/Air780EGH核心板 | AirSHT30_1000配件板|
| ------------ | ------------------ |
|     3V3     |         3V3        |
|     GND   |         GND        |
|  66/I2C1SDA  |         SDA        |
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
[2025-09-22 11:32:35.955][000000203.154] I/user.read_sht30_task_func temprature 27.61 ℃
[2025-09-22 11:32:35.957][000000203.154] I/user.read_sht30_task_func humidity 60.17 %RH
