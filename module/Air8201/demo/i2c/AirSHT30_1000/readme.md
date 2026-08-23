## 功能模块介绍

1、main.lua：主程序入口；

2、sht30_app.lua：每隔1秒读取一次温湿度数据；

3、AirSHT30_1000.lua：AirSHT30_1000驱动文件；

## 演示功能概述

AirSHT30_1000是合宙设计生产的一款I2C接口的SHT30温湿度传感器配件板；

本demo演示的核心功能为：

Air8201G/Air8201H模块+AirSHT30_1000配件板，通过BTB扩展板引出I2C1，每隔1秒读取1次温湿度数据；


## 核心板+配件板资料

[Air8201G/Air8201H板子](https://docs.openluat.com/air8201/)

[AirSHT30_1000配件板相关资料](https://docs.openluat.com/accessory/AirSHT30_1000/)


## 演示硬件环境

1、Air8201G 或 Air8201H 板子

2、AirSHT30_1000配件板

3、母对母的杜邦线4根

**Air8201G BTB接线 (I2C1=66/67)：**

| Air8201G BTB引脚 | AirSHT30_1000配件板|
| ------------ | ------------------ |
|     3V3     |         3V3        |
|     GND   |         GND        |
|  66/I2C1SDA  |         SDA        |
| 67/I2C1SCL |         SCL        |

**Air8201H BTB接线 (I2C1=66/67)：**

| Air8201H BTB引脚 | AirSHT30_1000配件板|
| ------------ | ------------------ |
|     3V3     |         3V3        |
|     GND   |         GND        |
|  66/I2C1SDA  |         SDA        |
| 67/I2C1SCL |         SCL        |


## 演示软件环境

1、[Luatools下载调试工具](https://docs.openluat.com/air8201/luatos/common/download/)

2、[Air8201G固件(基于Air780EGH)](https://docs.openluat.com/air780egh/luatos/firmware/version/)

3、[Air8201H固件(基于Air780EHM)](https://docs.openluat.com/air780epm/luatos/firmware/version/#air780ehmluatos)


## 演示操作步骤

1、搭建好演示硬件环境

2、不需要修改demo脚本代码

3、Luatools烧录内核固件和demo脚本代码

4、烧录成功后，自动开机运行

5、通过观察Luatools的运行日志，每隔1秒出现一次类似于下面的打印，就表示测试正常

``` lua
[2026-07-15 20:00:53.652][000000025.847] I/user.read_sht30_task_func temprature 28.36 ℃
[2026-07-15 20:00:53.655][000000025.847] I/user.read_sht30_task_func humidity 47.18 %RH
```
