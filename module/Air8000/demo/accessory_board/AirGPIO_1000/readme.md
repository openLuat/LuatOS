
## 演示功能概述

AirGPIO_1000是合宙设计生产的一款I2C转16路扩展GPIO的配件板；

本demo演示的核心功能为：

Air8000核心板+AirGPIO_1000配件板，演示I2C扩展16路GPIO功能；

分输出、输入和中断三种应用场景来演示；


## 核心板+配件板资料

[Air8000核心板+配件板相关资料](https://docs.openluat.com/air8000/product/shouce/)


## 演示硬件环境

![](https://docs.openluat.com/accessory/AirGPIO_1000/image/connect_Air8000.jpg)

![](https://docs.openluat.com/accessory/AirSHT30_1000/image/8000.png)

1、Air8000核心板

2、AirGPIO_1000配件板

3、母对母的杜邦线8根

4、Air8000核心板和AirGPIO_1000配件板的硬件接线方式为

| Air8000核心板 | AirGPIO_1000配件板 |
| ------------ | ------------------ |
|     VDD_EXT     |         3V3        |
|     GND     |         GND        |
|  I2C1_SDA  |         SDA        |
| I2C1_SCL |         SCL        |
|   GPIO2   |         INT        |

- 扩展GPIO输出演示时，无需接线；通过万用表或者示波器检测AirGPIO_1000配件板上的P00电平即可

- 扩展GPIO输入演示时，将AirGPIO_1000配件板上的P10和P11两个引脚通过杜邦线短接；软件上会将P10配置为输出（第一秒输出低电平，第二秒输出高电平，如此循环输出），将P11配置为输入，通过检测P11引脚输入电平的状态来演示

- 扩展GPIO中断演示时，将AirGPIO_1000配件板上的P03和P04两个引脚通过杜邦线短接，将AirGPIO_1000配件板上的P13和P14两个引脚通过杜邦线短接；软件上会将P03和P13配置为输出（第一秒输出低电平，第二秒输出高电平，如此循环输出），将P04和P14配置为中断，通过检测中断函数的触发状态来演示


## 演示软件环境

1、Luatools下载调试工具

2、[Air8000最新版本的内核固件](https://docs.openluat.com/air8101/luatos/firmware/)


## 演示操作步骤

1、搭建好演示硬件环境

2、不需要修改demo脚本代码

3、Luatools烧录内核固件和demo脚本代码

4、烧录成功后，自动开机运行

   (1) 通过万用表或者示波器检测AirGPIO_1000配件板上的P00电平，持续1秒输出0V的低电平，持续1秒输出3.3V的高电平，循环输出，表示GPIO输出测试正常；

   (2) 通过观察Luatools的运行日志，首先打印 air_gpio.get(0x11) 0， 再隔一秒打印 air_gpio.get(0x11) 1，再隔一秒打印 air_gpio.get(0x11) 0，如此循环输出，表示GPIO输入测试正常；

   (3) 通过观察Luatools的运行日志，首先打印 P04_int_cbfunc 4 0      P14_int_cbfunc 20 0， 再隔一秒打印  P04_int_cbfunc 4 1      P14_int_cbfunc 20 1，再隔一秒打印 P04_int_cbfunc 4 0      P14_int_cbfunc 20 0，如此循环输出，表示GPIO中断测试正常；

```
[2025-09-24 16:15:09.221][000000054.571] I/user.air_gpio.get(0x11) 1
[2025-09-24 16:15:09.223][000000054.572] I/user.AirGPIO_1000.set enter 16 0
[2025-09-24 16:15:09.223][000000054.573] I/user.AirGPIO_1000.set output 3 255 254
[2025-09-24 16:15:09.228][000000054.573] I/user.gpio_int_callback
[2025-09-24 16:15:09.290][000000054.635] I/user.AirGPIO_1000.set enter 3 0
[2025-09-24 16:15:09.290][000000054.636] I/user.AirGPIO_1000.set output 2 254 246
[2025-09-24 16:15:09.295][000000054.636] I/user.AirGPIO_1000.set enter 19 0
[2025-09-24 16:15:09.300][000000054.637] I/user.AirGPIO_1000.set output 3 254 246
[2025-09-24 16:15:09.300][000000054.638] I/user.gpio_int_callback
[2025-09-24 16:15:09.305][000000054.639] I/user.P04_int_cbfunc 4 0
[2025-09-24 16:15:09.310][000000054.640] I/user.P14_int_cbfunc 20 0
[2025-09-24 16:15:10.184][000000055.532] I/user.AirGPIO_1000.set enter 0 1
[2025-09-24 16:15:10.187][000000055.533] I/user.AirGPIO_1000.set output 2 246 247
[2025-09-24 16:15:10.228][000000055.573] I/user.air_gpio.get(0x11) 0
[2025-09-24 16:15:10.228][000000055.574] I/user.AirGPIO_1000.set enter 16 1
[2025-09-24 16:15:10.233][000000055.575] I/user.AirGPIO_1000.set output 3 246 247
[2025-09-24 16:15:10.238][000000055.575] I/user.gpio_int_callback
[2025-09-24 16:15:10.288][000000055.638] I/user.AirGPIO_1000.set enter 3 1
[2025-09-24 16:15:10.288][000000055.639] I/user.AirGPIO_1000.set output 2 247 255
[2025-09-24 16:15:10.293][000000055.639] I/user.AirGPIO_1000.set enter 19 1
[2025-09-24 16:15:10.298][000000055.640] I/user.AirGPIO_1000.set output 3 247 255
[2025-09-24 16:15:10.298][000000055.641] I/user.gpio_int_callback
[2025-09-24 16:15:10.305][000000055.642] I/user.P04_int_cbfunc 4 1
[2025-09-24 16:15:10.308][000000055.643] I/user.P14_int_cbfunc 20 1
[2025-09-24 16:15:11.190][000000056.534] I/user.AirGPIO_1000.set enter 0 0
[2025-09-24 16:15:11.200][000000056.535] I/user.AirGPIO_1000.set output 2 255 254
```

