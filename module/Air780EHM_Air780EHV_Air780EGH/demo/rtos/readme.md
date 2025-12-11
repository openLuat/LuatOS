## 功能模块介绍

1、main.lua:主程序入口；

2、rtos_app:对rtos核心库的各项功能进行测试，包括系统信息查询、内存信息获取、内存自动回收配置以及性能测试；

## 演示功能概述

1、对rtos核心库的各项功能进行测试，包括系统信息查询、内存信息获取、内存自动回收配置以及性能测试

## 演示硬件环境

1、Air780EHM/Air780EHV/Air780EGH核心板一块;

![](https://docs.openluat.com/accessory/AirSPINORFLASH_1000/image/780EHV.jpg)

2、TYPE-C USB数据线一根

* Air780EHM/Air780EHV/Air780EGH核心板通过 TYPE-C USB 口供电；
* TYPE-C USB 数据线直接插到核心板的 TYPE-C USB 座子，另外一端连接电脑 USB 口；

## 演示软件环境

1、Luatools下载调试工具

2、[Air780EHM V2018版本固件](https://docs.openluat.com/air780epm/luatos/firmware/version/)

[Air780EHV V2018版本固件](https://docs.openluat.com/air780ehv/luatos/firmware/version/)

[Air780EGH V2018版本固件](https://docs.openluat.com/air780egh/luatos/firmware/version/)

## 演示核心步骤

1、搭建好硬件环境

2、Luatools烧录内核固件和demo脚本代码

3、烧录成功后，自动开机运行

4、可以看到代码运行结果如下：

日志中如果出现以下类似以下打印则说明rtos功能正常

```lua
[2025-12-08 11:30:58.055][000000000.264] I/user.main rtos_demo 001.000.000
[2025-12-08 11:30:58.074][000000000.272] I/user.固件信息 版本: V2018 1
[2025-12-08 11:30:58.120][000000000.272] I/user.编译信息 日期: Nov  7 2025 BSP: Air780EHM
[2025-12-08 11:30:58.144][000000000.273] I/user.完整描述 LuatOS-SoC_V2018_Air780EHM
[2025-12-08 11:30:58.181][000000000.273] I/user.内存信息 Lua - 总: 4194296 已用: 36384 峰值: 36384 系统 - 总: 3211632 已用: 104576 峰值: 105336
[2025-12-08 11:30:58.203][000000000.273] D/rtos mem collect param 100,80,90 -> 200,75,85
[2025-12-08 11:30:58.222][000000000.274] I/user.RTOS测试 所有测试已启动
[2025-12-08 11:30:59.423][000000002.307] D/mobile cid1, state0
[2025-12-08 11:30:59.432][000000002.308] D/mobile bearer act 0, result 0
[2025-12-08 11:30:59.437][000000002.308] D/mobile NETIF_LINK_ON -> IP_READY
[2025-12-08 11:30:59.444][000000002.337] D/mobile TIME_SYNC 0
[2025-12-08 11:31:07.338][000000010.289] I/user.性能测试 1000次nop耗时: 16 毫秒


```
