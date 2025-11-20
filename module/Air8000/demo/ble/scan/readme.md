## 功能介绍

1、main.lua：主程序入口；

2、ble_scan.lua文件为演示scan功能的代码文件，主要功能为：

- 初始化蓝牙

- 创建BLE对象

- 设置扫描模式

- 开始扫描

- 在回调函数中处理扫描事件

- 按需停止扫描

3、check_wifi.lua：检查当前Air8000模组的WiFi固件是否为最新版本，若不是则自动启动升级（需插入可联网的SIM卡）。

## 演示功能概述

使用Air8000核心板，演示Air8000蓝牙在观察者模式下扫描蓝牙设备的操作。

## 演示硬件环境

1、Air8000核心板一块

2、TYPE-C USB数据线一根

3、Air8000核心板和数据线的硬件接线方式为

- Air8000核心板通过TYPE-C USB口供电；（正常测试时核心板背面的功耗测试开关拨到ON，正面的白色拨码(供电,充电选择脚)开关拨到供电.）

- TYPE-C USB数据线直接插到核心板的TYPE-C USB座子，另外一端连接电脑USB口；

## 演示软件环境

1、Luatools下载调试工具

[如何使用 LuaTools 烧录软件 - luatos@air8000 - 合宙模组资料中心](https://docs.openluat.com/air8000/luatos/common/download/)

2、[Air8000 V2018版本固件](https://docs.openluat.com/air8000/luatos/firmware/)

## 演示核心步骤

1、搭建好演示硬件环境

2、Luatools烧录内核固件和demo脚本代码

3、烧录成功后，自动开机运行，如果设备出现以下日志，表示scan已启动

```
I/user.ble_scan scan init
```

4、扫描到的蓝牙设备信息会在日志中打印出来，可以自己根据需要修改打印的设备信息。

例如下面这条打印，扫描到了一个广播包，广播包的RSSI为-53dBm，广播包的MAC地址为1E10BA37603C，广播包的广播数据为1EFF060001092022F866C970A5405607E9ABC4E2D1E23E53488A469EB48501，广播包的广播数据长度为62字节。

```
D/user.ble_scan scan report -53 1E10BA37603C 1EFF060001092022F866C970A5405607E9ABC4E2D1E23E53488A469EB48501 62
```


