## 演示功能概述
使用Air8000核心板，搭配AirVIBRATING_1000震动小板，演示滚珠震动传感器的使用
本示例主要是展示exvib1库的使用：

1，震动事件回调：当检测到震动时，会触发回调函数，在回调函数中可以进行相应的处理，例如打印日志、控制其他设备等。

2，震动事件计数：在回调函数中可以统计检测到的震动次数，例如用于记录用户操作次数、触发报警等。

3，震动事件过滤：可以设置过滤参数，例如设置最小震动时间间隔，避免重复触发回调。

## 演示硬件环境

1、Air8000核心板一块

2、TYPE-C USB数据线一根

3、AirVIBRATING_1000震动小板一块

4、Air8000核心板和数据线的硬件接线方式为

- Air8000核心板通过TYPE-C USB口供电；（核心板的拨钮开关拨到USB供电）

- TYPE-C USB数据线直接插到核心板的TYPE-C USB座子，另外一端连接电脑USB口；

5、AirVIBRATING_1000震动小板和Air8000核心板的硬件接线方式为

- 震动小板的VCC引脚连接核心板的VDD_EXT引脚；

- 震动小板的GND引脚连接核心板的GND_EXT引脚；

- 震动小板的INT_BL2529引脚连接核心板的GPIO20引脚；

## 演示软件环境

1、Luatools下载调试工具

2、[Air8000 V2014版本固件](https://docs.openluat.com/air8000/luatos/firmware/)

## 演示核心步骤

1、搭建好硬件环境

2、通过Luatools将demo与固件烧录到核心板中

3、烧录好后，板子开机将会在Luatools上看到如下打印：

```lua
[2025-09-09 13:51:51.417][000000000.584] I/user.Vibration start on gpio 20
[2025-09-09 13:51:56.331][000000005.954] I/user.VIB detected! pulses = 7
[2025-09-09 13:51:56.811][000000006.444] I/user.VIB detected! pulses = 3
[2025-09-09 13:52:00.039][000000009.664] I/user.VIB detected! pulses = 5
[2025-09-09 13:52:01.226][000000010.854] I/user.VIB detected! pulses = 3
[2025-09-09 13:52:02.640][000000012.274] I/user.VIB detected! pulses = 3
[2025-09-09 13:52:03.793][000000013.424] I/user.VIB detected! pulses = 3
[2025-09-09 13:52:04.858][000000014.484] I/user.VIB detected! pulses = 4
```