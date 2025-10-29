## 功能模块介绍

1、main.lua：主程序入口；

2、sht30_app.lua：每隔1秒读取一次温湿度数据；

3、AirSHT30_1000.lua：AirSHT30_1000驱动文件；

## 演示功能概述

AirSHT30_1000是合宙设计生产的一款I2C接口的SHT30温湿度传感器配件板；

本demo演示的核心功能为：

Air8000核心板+AirSHT30_1000配件板，每隔1秒读取1次温湿度数据；


## 核心板+配件板资料

[Air8000核心板](https://docs.openluat.com/air8000/product/shouce/#air8000_1)

[AirSHT30_1000配件板相关资料](https://docs.openluat.com/accessory/AirSHT30_1000/)


## 演示硬件环境

![](https://docs.openluat.com/accessory/AirSHT30_1000/image/connect_8000.jpg)

![](https://docs.openluat.com/accessory/AirSHT30_1000/image/8000.png)

1、Air8000核心板

2、AirSHT30_1000配件板

3、母对母的杜邦线4根

| Air8000核心板 | AirSHT30_1000配件板|
| ------------ | ------------------ |
|     VDD_EXT     |         3V3        |
|     GND   |         GND        |
| I2C1_SDA  |         SDA        |
| I2C1_SCL |         SCL        |


## 演示软件环境

1、Luatools下载调试工具

2、[Air8000最新版本的内核固件](https://docs.openluat.com/air8000/luatos/firmware/)


## 演示操作步骤

1、搭建好演示硬件环境

2、不需要修改demo脚本代码

3、Luatools烧录内核固件和demo脚本代码

4、烧录成功后，自动开机运行

5、通过观察Luatools的运行日志，每隔1秒出现一次类似于下面的打印，就表示测试正常

``` lua
[2025-09-23 14:56:38.486][000000007.559] I/user.read_sht30_task_func temprature 27.13 ℃
[2025-09-23 14:56:38.486][000000007.559] I/user.read_sht30_task_func humidity 70.86 %RH
