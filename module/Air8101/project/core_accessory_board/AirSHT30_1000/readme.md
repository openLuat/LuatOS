
## 演示功能概述

AirSHT30_1000是合宙设计生产的一款I2C接口的SHT30温湿度传感器配件板；

本demo演示的核心功能为：

Air8101核心板+AirSHT30_1000配件板，每隔1秒读取1次温湿度数据；


## 核心板+配件板资料

[Air8101核心板+配件板相关资料](https://docs.openluat.com/air8101/product/shouce/#air8101_1)


## 演示硬件环境

![](https://docs.openluat.com/air8101/product/file/AirSHT30_1000/hw_connection.jpg)

1、Air8101核心板

2、AirSHT30_1000配件板

3、母对母的杜邦线4根

4、Air8101核心板和AirSHT30_1000配件板的硬件接线方式为

- Air8101核心板通过TYPE-C USB口供电（核心板背面的功耗测试开关拨到OFF一端），此种供电方式下，vbat引脚为3.3V，可以直接给AirSHT30_1000配件板供电；

- 为了演示方便，所以Air8101核心板上电后直接通过vbat引脚给AirSHT30_1000配件板提供了3.3V的供电；

- 客户在设计实际项目时，一般来说，需要通过一个GPIO来控制LDO给配件板供电，这样可以灵活地控制配件板的供电，可以使项目的整体功耗降到最低；

| Air8101核心板 | AirSHT32_1000配件板|
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
[2025-06-16 16:29:43.039] I/user.read_sht30_task_func	temprature	26.73 ℃
[2025-06-16 16:29:43.039] I/user.read_sht30_task_func	humidity	56.62 %RH