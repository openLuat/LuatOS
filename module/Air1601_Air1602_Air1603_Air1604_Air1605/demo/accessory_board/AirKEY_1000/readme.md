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

[Air1601开发板](https://docs.openluat.com/air1601/product/shouce/#air1601_2)

[AirKEY_1000配件板相关资料](https://docs.openluat.com/accessory/AirKEY_1000/)


## 演示硬件环境

参考：[硬件环境清单](https://docs.openluat.com/air1601/luatos/common/hwenv/)，准备以及组装好硬件环境。

![](https://docs.openluat.com/air1601/luatos/app/accessory/AirKEY_1000/image/1601-key_1000.jpg)

1、Air1601开发板一块

2、TYPE-C USB数据线一根

3、AirKEY_1000配件板

4、母对母的杜邦线9根

5、Air1601开发板和数据线的硬件接线方式为

- Air1601开发板通过TYPE-C USB口连接TYPE-C USB 数据线，数据线的另外一端连接电脑的USB口；
- 在 Air1601 开发板上丝印标注 USB1，为芯片烧录下载接口；
- 若遇到因电脑 USB 端口供电不足导致的烧录失败，也可改用外部稳压电源通过开发板上的 VIN 引脚进行供电；

购买链接：[Air1601开发板 多功能5寸RGB屏 支持AirUI 摄像头 代开发固件-淘宝网](https://item.taobao.com/item.htm?id=1044228452703&pisk=g7HxDK_zIUYm-T9WJtAoI2UYUF-oHQm4wqoCIP4c143-zDKVIcagBV3tWrV6u-Dtycgp0lYqIbItY43T_nzg5P3ifjxkKpmq0Ry_BevHK46Wu23Aco1XfuZLv3qfMjIVRRy6-FClCSJLQq3lG8S1NuazXtZ_GVN7Vl47cONs5zN7Al6bCRg62_Z_vO_1ho97FzrT5Oa_17s7YkE1lRaX20azjRas5St-Vzr_CPG8aFU5cPXtNNVatv6IJO6seoFWZmaSFYKgcSHnDzLB-YpUMyibyOTj2W9QWzkBrQnrJjg04VppyJGEyAFQBKQUDbiLFr2B9_exqqkLhvLAnu2zoWG_wn9j2-UYwo0lc1ex1qkTgjIwY0wjzXzUGQ8z2xD36yPRPEio2rNK6qYPCrcKV4FnEaX3dXu-BWwC4_knpbbl-yEGG3KR_1Pb4Q1kC7_UChGa2yxvB15aa3r8-3KR_1Pb4uUHDhCN_7-P.&spm=a1z10.3-c-s.w4002-24045920836.13.3ff26ee5hNJu5K)

Air1601开发板与AirKEY_1000配件板连接方式如下：

| Air1601 开发板 |  AirKEY_1000配件板 |
| ------------ | ------------------ |
|    RX1/GPIO3    |         K1         |
|    TX1/GPIO2    |         K2         |
|    RX2/GPIO55    |         K3         |
|    TX2/GPIO54    |         K4         |
|    CS0/GPIO8    |         K5         |
|    CLK1/GPIO9    |         K6         |
|    MISO1/GPIO10    |         K7         |
|    GPIO12    |         K8         |
|     GND     |         G          |


## 演示软件环境

1、[Luatools下载调试工具](https://docs.openluat.com/air780epm/common/Luatools/)

2、内核固件文件（底层 core 固件文件）：

本demo开发测试时使用的固件为[LuatOS-SoC_V1012_Air1601_101.soc](https://docs.openluat.com/air1601/luatos/firmware/)，本demo对固件版本没有什么特殊要求，所以你如果要测试本demo时，可以直接使用最新版本的内核固件；如果发现最新版本的内核固件测试有问题，可以使用我们开发本demo时使用的内核固件版本来对比测试。


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
[2026-05-07 10:33:55.428][LTOS/N][000000009.230]:I/user.key1_int_cbfunc pressup 3 0
[2026-05-07 10:34:00.192][LTOS/N][000000013.972]:I/user.key2_int_cbfunc pressup 2 0
[2026-05-07 10:34:01.987][LTOS/N][000000015.782]:I/user.key3_int_cbfunc pressup 55 0
[2026-05-07 10:34:03.509][LTOS/N][000000017.302]:I/user.key4_int_cbfunc pressup 54 0
[2026-05-07 10:34:04.949][LTOS/N][000000018.736]:I/user.key5678_int_cbfunc 8 0
[2026-05-07 10:34:04.956][LTOS/N][000000018.736]:I/user.key5 pressdown
[2026-05-07 10:34:07.130][LTOS/N][000000020.912]:I/user.key5678_int_cbfunc 9 0
[2026-05-07 10:34:07.132][LTOS/N][000000020.912]:I/user.key6 pressdown
[2026-05-07 10:34:09.357][LTOS/N][000000023.146]:I/user.key5678_int_cbfunc 10 0
[2026-05-07 10:34:09.367][LTOS/N][000000023.146]:I/user.key7 pressdown
[2026-05-07 10:34:11.084][LTOS/N][000000024.872]:I/user.key5678_int_cbfunc 12 0
[2026-05-07 10:34:11.089][LTOS/N][000000024.872]:I/user.key8 pressdown
```

