## 功能模块介绍

1、main.lua：主程序入口；

2、sht30_app.lua：每隔1秒读取一次温湿度数据；

3、AirSHT30_1000.lua：AirSHT30_1000驱动文件；

## 演示功能概述

AirSHT30_1000是合宙设计生产的一款I2C接口的SHT30温湿度传感器配件板；

本demo演示的核心功能为：

Air1601开发板+AirSHT30_1000配件板，每隔1秒读取1次温湿度数据；


## 核心板+配件板资料

[Air1601开发板](https://docs.openluat.com/air1601/product/shouce/#air1601_2)

[AirSHT30_1000配件板相关资料](https://docs.openluat.com/accessory/AirSHT30_1000/)


## 演示硬件环境

参考：[硬件环境清单](https://docs.openluat.com/air1601/luatos/common/hwenv/)，准备以及组装好硬件环境。

![](https://docs.openluat.com/air1601/luatos/common/download/image/download.jpg)

![](https://docs.openluat.com/air1601/luatos/app/accessory/AirSHT30_1000/image/i2c.png)

1、Air1601开发板一块

2、TYPE-C USB数据线一根

3、AirSHT30_1000配件板

4、母对母的杜邦线4根

5、Air1601开发板和数据线的硬件接线方式为

- Air1601开发板通过TYPE-C USB口连接TYPE-C USB 数据线，数据线的另外一端连接电脑的USB口；
- 在 Air1601 开发板上丝印标注 USB1，为芯片烧录下载接口；
- 若遇到因电脑 USB 端口供电不足导致的烧录失败，也可改用外部稳压电源通过开发板上的 VIN 引脚进行供电；

购买链接：[Air1601开发板 多功能5寸RGB屏 支持AirUI 摄像头 代开发固件-淘宝网](https://item.taobao.com/item.htm?id=1044228452703&pisk=g7HxDK_zIUYm-T9WJtAoI2UYUF-oHQm4wqoCIP4c143-zDKVIcagBV3tWrV6u-Dtycgp0lYqIbItY43T_nzg5P3ifjxkKpmq0Ry_BevHK46Wu23Aco1XfuZLv3qfMjIVRRy6-FClCSJLQq3lG8S1NuazXtZ_GVN7Vl47cONs5zN7Al6bCRg62_Z_vO_1ho97FzrT5Oa_17s7YkE1lRaX20azjRas5St-Vzr_CPG8aFU5cPXtNNVatv6IJO6seoFWZmaSFYKgcSHnDzLB-YpUMyibyOTj2W9QWzkBrQnrJjg04VppyJGEyAFQBKQUDbiLFr2B9_exqqkLhvLAnu2zoWG_wn9j2-UYwo0lc1ex1qkTgjIwY0wjzXzUGQ8z2xD36yPRPEio2rNK6qYPCrcKV4FnEaX3dXu-BWwC4_knpbbl-yEGG3KR_1Pb4Q1kC7_UChGa2yxvB15aa3r8-3KR_1Pb4uUHDhCN_7-P.&spm=a1z10.3-c-s.w4002-24045920836.13.3ff26ee5hNJu5K)

Air1601开发板与AirSHT30_1000配件板连接方式如下：

| Air1601开发板 | AirSHT30_1000配件板|
| ------------ | ------------------ |
|     VDD_EXT     |         3V3        |
|     GND   |         GND        |
| TX5 |         SDA        |
| RX5 |         SCL        |

## 演示软件环境

1、Luatools下载调试工具

2、内核固件文件（底层 core 固件文件）：

本demo开发测试时使用的固件为[LuatOS-SoC_V1012_Air1601_101.soc](https://docs.openluat.com/air1601/luatos/firmware/)，本demo对固件版本没有什么特殊要求，所以你如果要测试本demo时，可以直接使用最新版本的内核固件；如果发现最新版本的内核固件测试有问题，可以使用我们开发本demo时使用的内核固件版本来对比测试。


## 演示操作步骤

1、搭建好演示硬件环境

2、使用Air1601开发板不需要修改demo脚本代码

3、使用Air1601开发板，需要在`sht30_app.lua`中将`air_sht30.open(0)`和`gpio.setup(164, 1, gpio.PULLUP)`打开，同时屏蔽掉`air_sht30.open(1)`

3、Luatools烧录内核固件和demo脚本代码

4、烧录成功后，自动开机运行

5、通过观察Luatools的运行日志，每隔1秒出现一次类似于下面的打印，就表示测试正常

``` lua
[2025-09-23 14:56:38.486][000000007.559] I/user.read_sht30_task_func temprature 27.13 ℃
[2025-09-23 14:56:38.486][000000007.559] I/user.read_sht30_task_func humidity 70.86 %RH
