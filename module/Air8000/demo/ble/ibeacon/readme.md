## 功能介绍

1、main.lua：主程序入口；

2、ble_ibeacon.lua文件为演示ibeacon功能的代码文件，主要功能为：

- 初始化蓝牙

- 创建BLE对象

- 配置ibeacon广播参数

- 启动ibeacon广播

- 处理异常情况，如广播异常停止，会跳转到异常处理流程，重新初始化蓝牙并广播。

3、check_wifi.lua：检查当前Air8000模组的WiFi固件是否为最新版本，若不是则自动启动升级（需插入可联网的SIM卡）。

4、ble_lowpower.lua：控制WiFi和蓝牙的开启和关闭，默认WiFi和蓝牙都是开启状态，无需控制。

## 演示功能概述

使用Air8000核心板演示ibeacon功能。

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

3、nrf connect 蓝牙调试软件

## 演示核心步骤

1、搭建好演示硬件环境

2、Luatools烧录内核固件和demo脚本代码

3、烧录成功后，自动开机运行，如果设备出现以下日志，表示ibeacon广播已启动

```
 I/user.iBeacon 广播已成功启动
```

4、接下来通过蓝牙APP 扫描并查看ibeacon信息

![image](https://docs.openluat.com/cdn/image/ble/ble_ibeacon_1.png)

5、演示ble_lowpower.lua模块的功能

- 控制WiFi和蓝牙的开启和关闭

- 默认WiFi和蓝牙都是开启状态，无需控制

- 每300秒关闭一次WiFi，再开启一次WiFi

如果关闭了WiFi和蓝牙后，Luatools将打印airlink slave timeout，表示Air8000的4G部分和WiFi协处理器通信超时：

```lua
D/airlink slave timeout
```

下面是演示打开ble_lowpower模块后的日志：

```lua
[2026-01-23 14:10:14.526][000000000.241] D/airlink open airlink for air8000s
[2026-01-23 14:10:14.529][000000000.431] I/airlink AIRLINK_READY 430 version 18 t 235
[2026-01-23 14:10:14.536][000000000.434] D/airlink Air8000s启动完成, 等待了 190 ms
[2026-01-23 14:10:14.540][000000000.463] I/user.main project name is  ble_ibeacon version is  001.000.000
[2026-01-23 14:10:14.542][000000000.484] I/user.ble_ibeacon nil
[2026-01-23 14:10:14.545][000000000.484] D/drv.bt 执行luat_bluetooth_init
[2026-01-23 14:10:14.548][000000000.486] I/user.开始广播
[2026-01-23 14:10:14.550][000000000.573] I/user.iBeacon 广播已成功启动
[2026-01-23 14:10:23.495][000000010.473] I/pm pm
[2026-01-23 14:10:23.524][000000010.474] I/user.ble_lowpower 发布: WiFi状态 -> 0
[2026-01-23 14:10:23.526][000000010.474] I/user.ble_ibeacon 收到WiFi状态变化: 0
[2026-01-23 14:10:23.529][000000010.486] I/user.iBeacon 检测到广播停止，准备重新初始化
[2026-01-23 14:10:23.535][000000010.486] I/user.ble_ibeacon 等待5秒后重新广播
[2026-01-23 14:10:28.510][000000015.487] I/user.ble_ibeacon nil
[2026-01-23 14:10:28.526][000000015.487] I/user.ble_scan WiFi关闭，等待WiFi开启...
[2026-01-23 14:10:30.513][000000017.488] I/user.ble_ibeacon 等待5秒后重新广播
[2026-01-23 14:10:35.513][000000022.488] I/user.ble_ibeacon nil
[2026-01-23 14:10:35.526][000000022.488] I/user.ble_scan WiFi关闭，等待WiFi开启...
[2026-01-23 14:10:37.514][000000024.489] I/user.ble_ibeacon 等待5秒后重新广播
[2026-01-23 14:10:42.514][000000029.489] I/user.ble_ibeacon nil
[2026-01-23 14:10:42.529][000000029.489] I/user.ble_scan WiFi关闭，等待WiFi开启...
[2026-01-23 14:10:44.514][000000031.490] I/user.ble_ibeacon 等待5秒后重新广播
[2026-01-23 14:10:49.514][000000036.490] I/user.ble_ibeacon nil
[2026-01-23 14:10:49.545][000000036.490] I/user.ble_scan WiFi关闭，等待WiFi开启...
[2026-01-23 14:10:51.515][000000038.491] I/user.ble_ibeacon 等待5秒后重新广播
[2026-01-23 14:10:53.496][000000040.474] I/pm pm
[2026-01-23 14:10:53.520][000000040.474] I/user.ble_lowpower 发布: WiFi状态 -> 1
[2026-01-23 14:10:53.523][000000040.475] I/user.ble_ibeacon 收到WiFi状态变化: 1
[2026-01-23 14:10:56.516][000000043.491] I/user.ble_ibeacon nil
[2026-01-23 14:10:56.539][000000043.491] D/drv.bt 执行luat_bluetooth_init
[2026-01-23 14:10:56.550][000000043.492] I/user.开始广播
[2026-01-23 14:10:56.602][000000043.577] I/user.iBeacon 广播已成功启动

```