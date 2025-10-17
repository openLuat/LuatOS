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

Air780EPM核心板+AirKEY_1000配件板，使用Air780EPM核心板的GPIO中断检测AirKEY_1000配件板上8个独立按键的按下或者弹起状态；


## 核心板+配件板资料

[Air780EPM核心板+配件板相关资料](https://docs.openluat.com/Air780EPM/product/shouce/)


## 演示硬件环境

![](https://docs.openluat.com/accessory/AirKEY_1000/image/Air780EPM_connect.jpg)

1、Air780EPM核心板

2、AirKEY_1000配件板

3、母对母的杜邦线9根

4、Air780EPM核心板和AirKEY_1000配件板的硬件接线方式为

- Air780EPM核心板通过TYPE-C USB口连接TYPE-C USB 数据线，数据线的另外一端连接电脑的USB口；
- 核心板正面的 ON/OFF 拨动开关 拨到ON一端；

| Air780EPM核心板 |  AirKEY_1000配件板 |
| ------------ | ------------------ |
|    25/GPIO26    |         K1         |
|    107/GPIO21    |         K2         |
|    20/GPIO24    |         K3         |
|    19/GPIO22    |         K4         |
|    99/GPIO23    |         K5         |
|    106/GPIO25    |         K6         |
|    78/GPIO28    |         K7         |
|    16/GPIO27    |         K8         |
|     GND     |         G          |


## 演示软件环境

1、[Luatools下载调试工具](https://docs.openluat.com/air780epm/common/Luatools/)

2、[Air780EPM 最新版本的内核固件](https://docs.openluat.com/air780epm/luatos/firmware/version/)


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
[2025-10-17 17:11:50.721][000000017.690] I/user.key1_int_cbfunc pressup 26 1
[2025-10-17 17:11:51.867][000000018.832] I/user.key2_int_cbfunc pressup 21 1
[2025-10-17 17:11:53.408][000000020.378] I/user.key3_int_cbfunc pressup 24 1
[2025-10-17 17:11:54.785][000000021.744] I/user.key4_int_cbfunc pressup 22 1
[2025-10-17 17:11:56.077][000000023.043] I/user.key5678_int_cbfunc 23 0
[2025-10-17 17:11:56.082][000000023.043] I/user.key5 pressdown
[2025-10-17 17:11:56.244][000000023.213] I/user.key5678_int_cbfunc 23 0
[2025-10-17 17:11:56.249][000000023.213] I/user.key5 pressdown
[2025-10-17 17:11:58.053][000000025.013] I/user.key5678_int_cbfunc 25 0
[2025-10-17 17:11:58.053][000000025.013] I/user.key6 pressdown
[2025-10-17 17:11:59.426][000000026.394] I/user.key5678_int_cbfunc 28 0
[2025-10-17 17:11:59.428][000000026.394] I/user.key7 pressdown
[2025-10-17 17:12:00.847][000000027.816] I/user.key5678_int_cbfunc 27 0
[2025-10-17 17:12:00.854][000000027.816] I/user.key8 pressdown
```

