## 功能模块介绍

1、main.lua：主程序入口；

2、gpio_app.lua：AirGPIO_1000扩展GPIO输出测试，输入测试，GPIO中断测试；

3、AirGPIO_1000.lua：AirGPIO_1000驱动配置文件；

## 演示功能概述

AirGPIO_1000是合宙设计生产的一款I2C转16路扩展GPIO的配件板；

本demo演示的核心功能为：

Air1601开发板+AirGPIO_1000配件板，演示I2C扩展16路GPIO功能；

分输出、输入和中断三种应用场景来演示；


## 核心板+配件板资料

[Air1601开发板](https://docs.openluat.com/air1601/product/shouce/#air1601_2)

[AirGPIO_1000配件板相关资料](https://docs.openluat.com/accessory/AirGPIO_1000/)


## 演示硬件环境

参考：[硬件环境清单](https://docs.openluat.com/air1601/luatos/common/hwenv/)，准备以及组装好硬件环境。

![](https://docs.openluat.com/air1601/luatos/common/download/image/download.jpg)

![](https://docs.openluat.com/air1601/luatos/app/accessory/AirSHT30_1000/image/i2c.png)

1、Air1601开发板一块

2、TYPE-C USB数据线一根

3、AirGPIO_1000配件板

4、母对母的杜邦线4根

5、Air1601开发板和数据线的硬件接线方式为

- Air1601开发板通过TYPE-C USB口连接TYPE-C USB 数据线，数据线的另外一端连接电脑的USB口；
- 在 Air1601 开发板上丝印标注 USB1，为芯片烧录下载接口；
- 若遇到因电脑 USB 端口供电不足导致的烧录失败，也可改用外部稳压电源通过开发板上的 VIN 引脚进行供电；

购买链接：[Air1601开发板 多功能5寸RGB屏 支持AirUI 摄像头 代开发固件-淘宝网](https://item.taobao.com/item.htm?id=1044228452703&pisk=g7HxDK_zIUYm-T9WJtAoI2UYUF-oHQm4wqoCIP4c143-zDKVIcagBV3tWrV6u-Dtycgp0lYqIbItY43T_nzg5P3ifjxkKpmq0Ry_BevHK46Wu23Aco1XfuZLv3qfMjIVRRy6-FClCSJLQq3lG8S1NuazXtZ_GVN7Vl47cONs5zN7Al6bCRg62_Z_vO_1ho97FzrT5Oa_17s7YkE1lRaX20azjRas5St-Vzr_CPG8aFU5cPXtNNVatv6IJO6seoFWZmaSFYKgcSHnDzLB-YpUMyibyOTj2W9QWzkBrQnrJjg04VppyJGEyAFQBKQUDbiLFr2B9_exqqkLhvLAnu2zoWG_wn9j2-UYwo0lc1ex1qkTgjIwY0wjzXzUGQ8z2xD36yPRPEio2rNK6qYPCrcKV4FnEaX3dXu-BWwC4_knpbbl-yEGG3KR_1Pb4Q1kC7_UChGa2yxvB15aa3r8-3KR_1Pb4uUHDhCN_7-P.&spm=a1z10.3-c-s.w4002-24045920836.13.3ff26ee5hNJu5K)

Air1601开发板与AirGPIO_1000配件板连接方式如下：

| Air1601开发板 | AirGPIO_1000配件板 |
| ------------ | ------------------ |
|     VDD_EXT     |         3V3        |
|     GND     |         GND        |
|  TX5  |         SDA        |
| RX5 |         SCL        |
|   GPIO12   |         INT        |

- 扩展GPIO输出演示时，无需接线；通过万用表或者示波器检测AirGPIO_1000配件板上的P00电平即可

- 扩展GPIO输入演示时，将AirGPIO_1000配件板上的P10和P11两个引脚通过杜邦线短接；软件上会将P10配置为输出（第一秒输出低电平，第二秒输出高电平，如此循环输出），将P11配置为输入，通过检测P11引脚输入电平的状态来演示

- 扩展GPIO中断演示时，将AirGPIO_1000配件板上的P03和P04两个引脚通过杜邦线短接，将AirGPIO_1000配件板上的P13和P14两个引脚通过杜邦线短接；软件上会将P03和P13配置为输出（第一秒输出低电平，第二秒输出高电平，如此循环输出），将P04和P14配置为中断，通过检测中断函数的触发状态来演示


## 演示软件环境

1、Luatools下载调试工具

2、内核固件文件（底层 core 固件文件）：

本demo开发测试时使用的固件为[LuatOS-SoC_V1013_Air1601_101.soc](https://docs.openluat.com/air1601/luatos/firmware/)，本demo对固件版本没有什么特殊要求，所以你如果要测试本demo时，可以直接使用最新版本的内核固件；如果发现最新版本的内核固件测试有问题，可以使用我们开发本demo时使用的内核固件版本来对比测试。


## 演示操作步骤

1、搭建好演示硬件环境

2、不需要修改demo脚本代码

3、Luatools烧录内核固件和demo脚本代码

4、烧录成功后，自动开机运行

   (1) 通过万用表或者示波器检测AirGPIO_1000配件板上的P00电平，持续1秒输出0V的低电平，持续1秒输出3.3V的高电平，循环输出，表示GPIO输出测试正常；

   (2) 通过观察Luatools的运行日志，首先打印 air_gpio.get(0x11) 0， 再隔一秒打印 air_gpio.get(0x11) 1，再隔一秒打印 air_gpio.get(0x11) 0，如此循环输出，表示GPIO输入测试正常；

   (3) 通过观察Luatools的运行日志，首先打印 P04_int_cbfunc 4 0      P14_int_cbfunc 20 0， 再隔一秒打印  P04_int_cbfunc 4 1      P14_int_cbfunc 20 1，再隔一秒打印 P04_int_cbfunc 4 0      P14_int_cbfunc 20 0，如此循环输出，表示GPIO中断测试正常；

```
[2026-05-06 16:11:09.549][LTOS/N][000000542.580]:I/user.air_gpio.get(0x11) 1
[2026-05-06 16:11:09.584][LTOS/N][000000542.580]:I/user.AirGPIO_1000.set enter 16 0
[2026-05-06 16:11:09.604][LTOS/N][000000542.580]:I/user.AirGPIO_1000.set output 3 255 254
[2026-05-06 16:11:09.619][LTOS/N][000000542.581]:I/user.gpio_int_callback
[2026-05-06 16:11:09.714][LTOS/N][000000542.750]:I/user.AirGPIO_1000.set enter 3 0
[2026-05-06 16:11:09.746][LTOS/N][000000542.750]:I/user.AirGPIO_1000.set output 2 254 246
[2026-05-06 16:11:09.760][LTOS/N][000000542.750]:I/user.AirGPIO_1000.set enter 19 0
[2026-05-06 16:11:09.775][LTOS/N][000000542.751]:I/user.AirGPIO_1000.set output 3 254 246
[2026-05-06 16:11:09.783][LTOS/N][000000542.751]:I/user.gpio_int_callback
[2026-05-06 16:11:09.791][LTOS/N][000000542.751]:I/user.P04_int_cbfunc 4 0
[2026-05-06 16:11:09.799][LTOS/N][000000542.752]:I/user.P14_int_cbfunc 20 0
[2026-05-06 16:11:10.416][LTOS/N][000000543.441]:I/user.AirGPIO_1000.set enter 0 1
[2026-05-06 16:11:10.427][LTOS/N][000000543.442]:I/user.AirGPIO_1000.set output 2 246 247
[2026-05-06 16:11:10.556][LTOS/N][000000543.581]:I/user.air_gpio.get(0x11) 0
[2026-05-06 16:11:10.567][LTOS/N][000000543.581]:I/user.AirGPIO_1000.set enter 16 1
[2026-05-06 16:11:10.578][LTOS/N][000000543.581]:I/user.AirGPIO_1000.set output 3 246 247
[2026-05-06 16:11:10.586][LTOS/N][000000543.582]:I/user.gpio_int_callback
[2026-05-06 16:11:10.726][LTOS/N][000000543.751]:I/user.AirGPIO_1000.set enter 3 1
[2026-05-06 16:11:10.736][LTOS/N][000000543.752]:I/user.AirGPIO_1000.set output 2 247 255
[2026-05-06 16:11:10.744][LTOS/N][000000543.752]:I/user.AirGPIO_1000.set enter 19 1
[2026-05-06 16:11:10.755][LTOS/N][000000543.752]:I/user.AirGPIO_1000.set output 3 247 255
[2026-05-06 16:11:10.764][LTOS/N][000000543.752]:I/user.gpio_int_callback
[2026-05-06 16:11:10.775][LTOS/N][000000543.753]:I/user.P04_int_cbfunc 4 1
[2026-05-06 16:11:10.784][LTOS/N][000000543.753]:I/user.P14_int_cbfunc 20 1
[2026-05-06 16:11:11.401][LTOS/N][000000544.442]:I/user.AirGPIO_1000.set enter 0 0
[2026-05-06 16:11:11.410][LTOS/N][000000544.443]:I/user.AirGPIO_1000.set output 2 255 254
```

