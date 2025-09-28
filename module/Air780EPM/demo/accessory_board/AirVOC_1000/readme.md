
## 演示功能概述

AirVOC_1000是合宙设计生产的一款I2C接口的VOC(挥发性有机化合物)气体传感器配件板；

主要用于检测甲醛、一氧化碳、可燃气体、酒精、氨气、硫化物、苯系蒸汽、烟雾、其它有害气体的监测；

本demo演示的核心功能为：

Air780EPM开发板+AirVOC_1000配件板，每隔1秒读取1次TVOC空气质量数据；


## 核心板+配件板资料

[Air780EPM开发板+配件板相关资料](https://docs.openluat.com/air780epm/product/shouce/)


## 演示硬件环境

![](https://docs.openluat.com/accessory/AirVOC_1000/image/connect_Air780EPM.png)

1、Air780EPM开发板

2、AirVOC_1000配件板

3、母对母的杜邦线4根

4、Air780EPM开发板和AirVOC_1000配件板的硬件接线方式为

| Air780EPM开发板 | AirVOC_1000配件板  |
| ------------ | ------------------ |
|     3V3（VDD_EXT）     |         3V3        |
|     GND   |         GND        |
| I2C1_SDA（CAMERA_SDA） |         SDA        |
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
[2025-09-25 15:21:52.270][000002162.898] I/user.空气质量 TVOC: ppb 93, ppm 0.093, 等级 1(优)
[2025-09-25 15:21:53.273][000002163.902] I/user.空气质量 TVOC: ppb 93, ppm 0.093, 等级 1(优)
