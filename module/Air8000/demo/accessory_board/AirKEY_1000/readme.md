## 功能模块介绍

1、main.lua：主程序入口；

2、key_app.lua：使用核心板的GPIO中断检测AirKEY_1000配件板上8个独立按键的按下或者弹起状态；

3、AirKEY_1000.lua：配置主机和AirKEY_1000之间的控制参数；

## 用户消息介绍

1、"KEY1_PRESSUP_IND"：按键消息，publish该消息给其他协程或者给订阅消息的处理函数去执行耗时动作；

2、"KEY2_PRESSUP_IND"：按键消息，publish该消息给其他协程或者给订阅消息的处理函数去执行耗时动作；

3、"KEY3_PRESSUP_IND"：按键消息，publish该消息给其他协程或者给订阅消息的处理函数去执行耗时动作；

4、"KEY4_PRESSUP_IND"：按键消息，publish该消息给其他协程或者给订阅消息的处理函数去执行耗时动作；

5、"KEY5_PRESSUP_IND"：按键消息，publish该消息给其他协程或者给订阅消息的处理函数去执行耗时动作；

6、"KEY5_PRESSUP_IND"：按键消息，publish该消息给其他协程或者给订阅消息的处理函数去执行耗时动作；

7、"KEY7_PRESSUP_IND"：按键消息，publish该消息给其他协程或者给订阅消息的处理函数去执行耗时动作；

8、"KEY8_PRESSUP_IND"：按键消息，publish该消息给其他协程或者给订阅消息的处理函数去执行耗时动作；

## 演示功能概述

AirKEY_1000是合宙设计生产的一款支持8个独立按键的配件板；

本demo演示的核心功能为：

Air8000核心板+AirKEY_1000配件板，使用Air8000核心板的GPIO中断检测AirKEY_1000配件板上8个独立按键的按下或者弹起状态；


## 核心板+配件板资料

[Air8000核心板+配件板相关资料](https://docs.openluat.com/Air8000/product/shouce/)


## 演示硬件环境

![](https://docs.openluat.com/accessory/AirKEY_1000/image/Air8000_connection.jpg)

![](https://docs.openluat.com/accessory/AirSHT30_1000/image/8000.png)

1、Air8000核心板

2、AirKEY_1000配件板

3、母对母的杜邦线9根

4、Air8000核心板和AirKEY_1000配件板的硬件接线方式为

- Air8000核心板通过TYPE-C USB口连接TYPE-C USB 数据线，数据线的另外一端连接电脑的USB口；
- 核心板正面的 供电/充电 拨动开关 拨到供电一端；
- 核心板背面的 USB ON/USB OFF 拨动开关 拨到USB ON一端；

| Air8000核心板 |  AirKEY_1000配件板 |
| ------------ | ------------------ |
|    CAN_RXD/GPIO28    |         K1         |
|    CAN_TXD/GPIO26    |         K2         |
|    CAN_STB/GPIO27    |         K3         |
|    GPIO16    |         K4         |
|    GPIO1    |         K5         |
|    GPIO2    |         K6         |
|    LCD_CS/GPIO35    |         K7         |
|    LCD_CLK/GPIO34    |         K8         |
|     GND     |         G          |


## 演示软件环境

1、[Luatools下载调试工具](https://docs.openluat.com/air780epm/common/Luatools/)

2、[Air8000 最新版本的内核固件](https://docs.openluat.com/air8000/luatos/firmware/)


## 演示操作步骤

1、搭建好演示硬件环境

2、不需要修改demo脚本代码

3、Luatools烧录内核固件和demo脚本代码

4、烧录成功后，自动开机运行

   (1) 按键1弹起时，Luatools的运行日志输出 key1_int_cbfunc pressup，表示按键1测试正常；

   (2) 按键2弹起时，Luatools的运行日志输出 key2_int_cbfunc pressup，表示按键2测试正常；

   (3) 按键3弹起时，Luatools的运行日志输出 key3_int_cbfunc pressup，表示按键3测试正常；

   (4) 按键4弹起时，Luatools的运行日志输出 key4_int_cbfunc pressup，表示按键4测试正常；

   (5) 按键5按下时，Luatools的运行日志输出 key5 pressdown，表示按键5测试正常；

   (6) 按键6按下时，Luatools的运行日志输出 key6 pressdown，表示按键6测试正常；

   (7) 按键7按下时，Luatools的运行日志输出 key7 pressdown，表示按键7测试正常；

   (8) 按键8按下时，Luatools的运行日志输出 key8 pressdown，表示按键8测试正常；

```
[2025-10-20 10:39:08.283][000000006.310] I/user.key1_int_cbfunc pressup 28 1
[2025-10-20 10:39:09.351][000000007.382] I/user.key2_int_cbfunc pressup 26 1
[2025-10-20 10:39:10.818][000000008.855] I/user.key3_int_cbfunc pressup 27 1
[2025-10-20 10:39:11.705][000000009.736] I/user.key4_int_cbfunc pressup 16 1
[2025-10-20 10:39:12.900][000000010.930] I/user.key5678_int_cbfunc 1 0
[2025-10-20 10:39:12.906][000000010.931] I/user.key5 pressdown
[2025-10-20 10:39:13.989][000000012.026] I/user.key5678_int_cbfunc 2 0
[2025-10-20 10:39:13.998][000000012.027] I/user.key6 pressdown
[2025-10-20 10:39:15.457][000000013.491] I/user.key5678_int_cbfunc 35 0
[2025-10-20 10:39:15.462][000000013.492] I/user.key7 pressdown
[2025-10-20 10:39:16.790][000000014.829] I/user.key5678_int_cbfunc 34 0
[2025-10-20 10:39:16.792][000000014.830] I/user.key8 pressdown
```

