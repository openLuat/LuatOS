
## 演示功能概述

将使用Air8000核心板，演示Air8000蓝牙在观察者模式下扫描蓝牙设备的操作。

## 演示硬件环境

1、Air8000核心板一块

2、TYPE-C USB数据线一根

3、Air8000核心板和数据线的硬件接线方式为

- Air8000核心板通过TYPE-C USB口供电；（核心板USB旁边的开关拨到 "充电" 一端）

- TYPE-C USB数据线直接插到核心板的TYPE-C USB座子，另外一端连接电脑USB口；

## 演示软件环境

1、Luatools下载调试工具

[如何使用 LuaTools 烧录软件 - luatos@air8000 - 合宙模组资料中心](https://docs.openluat.com/air8000/luatos/common/download/)

2、[Air8000 固件](https://gitee.com/openLuat/LuatOS/tree/master/module/Air8000/core)

3、[Air8000 BLE扫描代码](https://gitee.com/openLuat/LuatOS/blob/master/module/Air8000/demo/ble/scan)

## 演示核心步骤

1、核心板通过usb数据线连接到电脑上

2、通过Luatools将demo与固件烧录到核心板中

3、烧录成功后，自动开机运行

4、通过luatools日志查看扫描到的设备信息