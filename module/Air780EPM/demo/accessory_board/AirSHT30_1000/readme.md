
## 演示功能概述

AirSHT30_1000是合宙设计生产的一款I2C接口的SHT30温湿度传感器配件板；

本demo演示的核心功能为：

Air780EPM开发板+AirSHT30_1000配件板，每隔1秒读取1次温湿度数据；


## 核心板+配件板资料

[Air780EPM开发板+配件板相关资料](https://docs.openluat.com/air780epm/product/shouce/)


## 演示硬件环境

![](https://docs.openluat.com/accessory/AirSHT30_1000/image/connect_780epm.png)

1、Air780EPM开发板

2、AirSHT30_1000配件板

3、母对母的杜邦线4根

| Air780EPM开发板 | AirSHT30_1000配件板|
| ------------ | ------------------ |
|     3V3（VDD_EXT）     |         3V3        |
|     GND   |         GND        |
|  I2C1_SDA（CAMERA_SDA）  |         SDA        |
| I2C1_SCL（CAMERA_SCL） |         SCL        |


## 演示软件环境

1、Luatools下载调试工具

2、[Air780EPM最新版本的内核固件](https://docs.openluat.com/air780epm/luatos/firmware/version/)


## 演示操作步骤

1、搭建好演示硬件环境

2、不需要修改demo脚本代码

3、Luatools烧录内核固件和demo脚本代码

4、烧录成功后，自动开机运行

5、通过观察Luatools的运行日志，每隔1秒出现一次类似于下面的打印，就表示测试正常

``` lua
[2025-09-18 15:29:03.155][000000001.262] I/user.read_sht30_task_func temprature 27.43 ℃
[2025-09-18 15:29:03.159][000000001.262] I/user.read_sht30_task_func humidity 57.58 %RH
