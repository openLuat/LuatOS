
## 演示功能概述

AirGPIO_1000是合宙设计生产的一款I2C转16路扩展GPIO的配件板；

本demo演示的核心功能为：

Air8101核心板+AirGPIO_1000配件板，演示I2C扩展16路GPIO功能；

分输出、输入和中断三种应用场景来演示；


## 演示硬件环境

1、Air8101核心板

2、AirGPIO_1000配件板

3、母对母的杜邦线

4、Air8101核心板和AirGPIO_1000配件板的硬件接线方式为

- 基本连接参考下表

| Air8101核心板 | AirGPIO_1000配件板 |
| ------------ | ------------------ |
|  vbat(3.3V)  |         3V3        |
|     gnd      |         GND        |
|    38/R5     |         SDA        |
|    45/R6     |         SCL        |
|   65/GPIO2   |         INT        |

- 扩展GPIO输出演示时，无需接线；通过万用表或者示波器检测AirGPIO_1000配件板上的P00电平即可

- 扩展GPIO输入演示时，将AirGPIO_1000配件板上的P10和P11两个引脚通过杜邦线短接

- 扩展GPIO中断演示时，将AirGPIO_1000配件板上的P03和P04两个引脚通过杜邦线短接，将AirGPIO_1000配件板上的P13和P14两个引脚通过杜邦线短接


## 演示软件环境

1、[最新版本的内核固件](https://docs.openluat.com/air8101/luatos/firmware/)

2、Luatools下载调试工具

## 演示操作步骤

1、搭建好演示硬件环境

2、不需要修改demo脚本代码

3、Luatools烧录内核固件和demo脚本代码

4、烧录成功后，自动开机运行

   (1) 通过万用表或者示波器检测AirGPIO_1000配件板上的P00电平，持续1秒输出0V的低电平，持续1秒输出3.3V的高电平，循环输出，表示GPIO输出测试正常；

   (2) 通过观察Luatools的运行日志，首先输出 air_gpio.get(0x11) 0， 再隔一秒输出 air_gpio.get(0x11) 1，再隔一秒输出 air_gpio.get(0x11) 0，如此循环输出，表示GPIO输入测试正常；

   (3) 通过观察Luatools的运行日志，首先输出 P04_int_cbfunc 4 0      P04_int_cbfunc 14 0， 再隔一秒输出  P04_int_cbfunc 4 1      P04_int_cbfunc 14 1，再隔一秒输出 P04_int_cbfunc 4 0      P04_int_cbfunc 14 0，如此循环输出，表示GPIO中断测试正常；
   

