## 功能介绍

1、main.lua：主程序入口；

2、ble_ibeacon.lua文件为演示ibeacon功能的代码文件，主要功能为：

- 初始化蓝牙

- 创建BLE对象

- 配置ibeacon广播参数

- 启动ibeacon广播

- 处理异常情况，如广播异常停止，会跳转到异常处理流程，重新初始化蓝牙并广播。

## 演示功能概述

使用Air8101核心板演示ibeacon功能。

## 演示硬件环境

1、Air8101核心板一块

2、TYPE-C USB数据线一根

3、Air8101核心板和数据线的硬件接线方式为

- Air8101核心板通过TYPE-C USB口供电；（核心板背面的功耗测试开关拨到OFF一端）

- 如果测试发现软件频繁重启，重启原因值为：poweron reason 0，可能是供电不足，此时再通过直流稳压电源对核心板的vbat管脚进行4V供电，或者VIN管脚进行5V供电；

- TYPE-C USB数据线直接插到核心板的TYPE-C USB座子，另外一端连接电脑USB口；

## 演示软件环境

1、Luatools下载调试工具

2、[Air8101 V1006版本固件](https://docs.openluat.com/air8101/luatos/firmware/)

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