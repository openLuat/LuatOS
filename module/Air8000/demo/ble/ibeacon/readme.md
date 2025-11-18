## 功能介绍

1、main.lua：主程序入口；

2、ble_ibeacon.lua文件为演示ibeacon功能的代码文件，主要功能为：

- 初始化蓝牙

- 创建BLE对象

- 配置ibeacon广播参数

- 启动ibeacon广播

- 处理异常情况，如广播异常停止，会跳转到异常处理流程，重新初始化蓝牙并广播。

3、check_wifi.lua：检查当前Air8000模组的WiFi固件是否为最新版本，若不是则自动启动升级（需插入可联网的SIM卡）。

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
