## 功能模块介绍

1、main.lua：主程序入口；

2、gpio_app.lua：AirGPIO_1000扩展GPIO输出测试，输入测试，GPIO中断测试；

3、AirGPIO_1000.lua：AirGPIO_1000驱动配置文件；

## 演示功能概述

AirGPIO_1000是合宙设计生产的一款I2C转16路扩展GPIO的配件板；

本demo演示的核心功能为：

Air780EPM核心板+AirGPIO_1000配件板，演示I2C扩展16路GPIO功能；

分输出、输入和中断三种应用场景来演示；


## 核心板+配件板资料

[Air780EPM核心板](https://docs.openluat.com/air780epm/product/shouce/)

[配件板相关资料](https://docs.openluat.com/accessory/AirGPIO_1000/)


## 演示硬件环境

![](https://docs.openluat.com/accessory/AirGPIO_1000/image/connect_Air780EPM.png)

1、Air780EPM核心板

2、AirGPIO_1000配件板

3、母对母的杜邦线8根

4、Air780EPM核心板和AirGPIO_1000配件板的硬件接线方式为

| Air780EPM核心板 | AirGPIO_1000配件板 |
| ------------ | ------------------ |
|     3V3     |         3V3        |
|     GND     |         GND        |
|    66/I2C1SDA    |         SDA        |
| 67/I2C1SCL |         SCL        |
|   23/GPIO2   |         INT        |

- 扩展GPIO输出演示时，无需接线；通过万用表或者示波器检测AirGPIO_1000配件板上的P00电平即可

- 扩展GPIO输入演示时，将AirGPIO_1000配件板上的P10和P11两个引脚通过杜邦线短接；软件上会将P10配置为输出（第一秒输出低电平，第二秒输出高电平，如此循环输出），将P11配置为输入，通过检测P11引脚输入电平的状态来演示

- 扩展GPIO中断演示时，将AirGPIO_1000配件板上的P03和P04两个引脚通过杜邦线短接，将AirGPIO_1000配件板上的P13和P14两个引脚通过杜邦线短接；软件上会将P03和P13配置为输出（第一秒输出低电平，第二秒输出高电平，如此循环输出），将P04和P14配置为中断，通过检测中断函数的触发状态来演示


## 演示软件环境

1、Luatools下载调试工具

2、[Air780EPM最新版本的内核固件](https://docs.openluat.com/air780epm/luatos/firmware/version/)


## 演示操作步骤

1、搭建好演示硬件环境

2、不需要修改demo脚本代码

3、Luatools烧录内核固件和demo脚本代码

4、烧录成功后，自动开机运行

   (1) 通过万用表或者示波器检测AirGPIO_1000配件板上的P00电平，持续1秒输出0V的低电平，持续1秒输出3.3V的高电平，循环输出，表示GPIO输出测试正常；

   (2) 通过观察Luatools的运行日志，首先打印 air_gpio.get(0x11) 0， 再隔一秒打印 air_gpio.get(0x11) 1，再隔一秒打印 air_gpio.get(0x11) 0，如此循环输出，表示GPIO输入测试正常；

   (3) 通过观察Luatools的运行日志，首先打印 P04_int_cbfunc 4 0      P14_int_cbfunc 20 0， 再隔一秒打印  P04_int_cbfunc 4 1      P14_int_cbfunc 20 1，再隔一秒打印 P04_int_cbfunc 4 0      P14_int_cbfunc 20 0，如此循环输出，表示GPIO中断测试正常；

```
[2025-10-15 15:01:49.745][000000002.228] I/user.air_gpio.get(0x11) 1
[2025-10-15 15:01:49.752][000000002.229] I/user.AirGPIO_1000.set enter 16 0
[2025-10-15 15:01:49.757][000000002.230] I/user.AirGPIO_1000.set output 3 255 254
[2025-10-15 15:01:49.762][000000002.230] I/user.gpio_int_callback
[2025-10-15 15:01:49.767][000000002.239] I/user.AirGPIO_1000.set enter 3 0
[2025-10-15 15:01:49.771][000000002.240] I/user.AirGPIO_1000.set output 2 254 246
[2025-10-15 15:01:49.775][000000002.240] I/user.AirGPIO_1000.set enter 19 0
[2025-10-15 15:01:49.779][000000002.241] I/user.AirGPIO_1000.set output 3 254 246
[2025-10-15 15:01:49.784][000000002.242] I/user.gpio_int_callback
[2025-10-15 15:01:49.786][000000002.243] I/user.P04_int_cbfunc 4 0
[2025-10-15 15:01:49.789][000000002.244] I/user.P14_int_cbfunc 20 0
[2025-10-15 15:01:50.719][000000003.223] I/user.AirGPIO_1000.set enter 0 1
[2025-10-15 15:01:50.732][000000003.224] I/user.AirGPIO_1000.set output 2 246 247
[2025-10-15 15:01:50.744][000000003.230] I/user.air_gpio.get(0x11) 0
[2025-10-15 15:01:50.752][000000003.231] I/user.AirGPIO_1000.set enter 16 1
[2025-10-15 15:01:50.759][000000003.232] I/user.AirGPIO_1000.set output 3 246 247
[2025-10-15 15:01:50.767][000000003.232] I/user.gpio_int_callback
[2025-10-15 15:01:50.773][000000003.242] I/user.AirGPIO_1000.set enter 3 1
[2025-10-15 15:01:50.776][000000003.243] I/user.AirGPIO_1000.set output 2 247 255
[2025-10-15 15:01:50.780][000000003.243] I/user.AirGPIO_1000.set enter 19 1
[2025-10-15 15:01:50.785][000000003.244] I/user.AirGPIO_1000.set output 3 247 255
[2025-10-15 15:01:50.788][000000003.245] I/user.gpio_int_callback
[2025-10-15 15:01:50.790][000000003.246] I/user.P04_int_cbfunc 4 1
[2025-10-15 15:01:50.794][000000003.247] I/user.P14_int_cbfunc 20 1
[2025-10-15 15:01:51.727][000000004.224] I/user.AirGPIO_1000.set enter 0 0
[2025-10-15 15:01:51.736][000000004.225] I/user.AirGPIO_1000.set output 2 255 254
[2025-10-15 15:01:51.746][000000004.233] I/user.air_gpio.get(0x11) 1
[2025-10-15 15:01:51.756][000000004.233] I/user.AirGPIO_1000.set enter 16 0
[2025-10-15 15:01:51.765][000000004.234] I/user.AirGPIO_1000.set output 3 255 254
[2025-10-15 15:01:51.770][000000004.234] I/user.gpio_int_callback
[2025-10-15 15:01:51.776][000000004.244] I/user.AirGPIO_1000.set enter 3 0
[2025-10-15 15:01:51.782][000000004.245] I/user.AirGPIO_1000.set output 2 254 246
[2025-10-15 15:01:51.787][000000004.245] I/user.AirGPIO_1000.set enter 19 0
[2025-10-15 15:01:51.793][000000004.246] I/user.AirGPIO_1000.set output 3 254 246
[2025-10-15 15:01:51.796][000000004.247] I/user.gpio_int_callback
[2025-10-15 15:01:51.799][000000004.248] I/user.P04_int_cbfunc 4 0
[2025-10-15 15:01:51.803][000000004.249] I/user.P14_int_cbfunc 20 0
[2025-10-15 15:01:52.721][000000005.225] I/user.AirGPIO_1000.set enter 0 1
[2025-10-15 15:01:52.730][000000005.226] I/user.AirGPIO_1000.set output 2 246 247
[2025-10-15 15:01:52.742][000000005.234] I/user.air_gpio.get(0x11) 0
[2025-10-15 15:01:52.752][000000005.235] I/user.AirGPIO_1000.set enter 16 1
[2025-10-15 15:01:52.760][000000005.236] I/user.AirGPIO_1000.set output 3 246 247
[2025-10-15 15:01:52.770][000000005.236] I/user.gpio_int_callback
[2025-10-15 15:01:52.779][000000005.246] I/user.AirGPIO_1000.set enter 3 1
[2025-10-15 15:01:52.785][000000005.247] I/user.AirGPIO_1000.set output 2 247 255
[2025-10-15 15:01:52.791][000000005.247] I/user.AirGPIO_1000.set enter 19 1
[2025-10-15 15:01:52.798][000000005.248] I/user.AirGPIO_1000.set output 3 247 255
[2025-10-15 15:01:52.803][000000005.249] I/user.gpio_int_callback
[2025-10-15 15:01:52.808][000000005.250] I/user.P04_int_cbfunc 4 1
[2025-10-15 15:01:52.813][000000005.251] I/user.P14_int_cbfunc 20 1
[2025-10-15 15:01:53.721][000000006.226] I/user.AirGPIO_1000.set enter 0 0
[2025-10-15 15:01:53.724][000000006.227] I/user.AirGPIO_1000.set output 2 255 254
```

