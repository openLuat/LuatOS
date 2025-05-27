
## 演示功能概述

AirKEY_1000是合宙设计生产的一款支持8个独立按键的配件板；

本demo演示的核心功能为：

Air8101核心板+AirKEY_1000配件板，使用Air8101核心板的GPIO中断检测AirKEY_1000配件板上8个独立按键的按下或者弹起状态；


## 演示硬件环境

1、Air8101核心板

2、AirKEY_1000配件板

3、母对母的杜邦线

4、Air8101核心板和AirKEY_1000配件板的硬件接线方式为

- Air8101核心板通过TYPE-C USB口供电（核心板背面的功耗测试开关拨到OFF一端）

| Air8101核心板 |  AirKEY_1000配件板 |
| ------------ | ------------------ |
|     40/R1    |         K1         |
|     39/R3    |         K2         |
|     38/R5    |         K3         |
|     37/R7    |         K4         |
|     36/G1    |         K5         |
|     35/G3    |         K6         |
|     34/G5    |         K7         |
|     33/G7    |         K8         |
|     gnd      |         G          |


## 演示软件环境

1、[最新版本的内核固件](https://docs.openluat.com/air8101/luatos/firmware/)

2、Luatools下载调试工具

## 演示操作步骤

1、搭建好演示硬件环境

2、不需要修改demo脚本代码

3、Luatools烧录内核固件和demo脚本代码

4、烧录成功后，自动开机运行

   (1) 按键1弹起时，Luatools的运行日志输出 key1_int_cbfunc pressup，表示按键1测试正常；

   (1) 按键2弹起时，Luatools的运行日志输出 key2_int_cbfunc pressup，表示按键2测试正常；

   (1) 按键3弹起时，Luatools的运行日志输出 key3_int_cbfunc pressup，表示按键3测试正常；

   (1) 按键4弹起时，Luatools的运行日志输出 key4_int_cbfunc pressup，表示按键4测试正常；

   (1) 按键5按下时，Luatools的运行日志输出 key5 pressdown，表示按键5测试正常；

   (1) 按键6按下时，Luatools的运行日志输出 key6 pressdown，表示按键6测试正常；

   (1) 按键7按下时，Luatools的运行日志输出 key7 pressdown，表示按键7测试正常；

   (1) 按键8按下时，Luatools的运行日志输出 key8 pressdown，表示按键8测试正常；
   

