
## 演示功能概述

将使用Air780EGH核心板，演示PWM控制GPIO引脚输出PWM波形，以及控制GPIO引脚输出呼吸灯效果。

## 演示硬件环境

1、Air780EGH核心板一块

2、TYPE-C USB数据线一根

3、Air780EGH核心板和数据线的硬件接线方式为

- Air780EGH核心板通过TYPE-C USB口供电；（核心板USB旁边的开关拨到on一端）

- TYPE-C USB数据线直接插到核心板的TYPE-C USB座子，另外一端连接电脑USB口；

## 演示软件环境

1、Luatools下载调试工具

2、[Air780EGH V2008版本固件](https://docs.openluat.com/air780egh/luatos/firmware/version/)（测试使用V2008 1号固件）

## 演示核心步骤

1、搭建好演示硬件环境

2、通过Luatools将demo与固件烧录到核心板中

3、烧录成功后，自动开机运行

4、接下来通过示波器查看波形，使用发光二极管演示呼吸灯效果。
