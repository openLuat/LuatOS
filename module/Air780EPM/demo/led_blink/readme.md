## 功能模块介绍

1、main.lua：主程序入口；

2、led_blink_app.lua：控制开发板上的网络灯1秒闪烁1次；

## 演示功能概述

1、创建一个task；

2、在task中的任务处理函数中，每隔一秒钟切换灯的状态并打印灯对应状态；


## 演示硬件环境

![](https://docs.openluat.com/air780epm/luatos/app/socket/http/image/HrcxbSkXeojNIGx09TDcCbwknCb.png)

1、Air780EPM开发板一块

2、TYPE-C USB数据线一根

4、Air780EPM开发板和数据线的硬件接线方式为

- Air780EPM开发板通过TYPE-C USB口连接TYPE-C USB 数据线，数据线的另外一端连接电脑的USB口；
- 开发板正面的 USB供电/外部供电 拨动开关 拨到USB供电一端；


## 演示软件环境

1、[Luatools下载调试工具](https://docs.openluat.com/air780epm/luatos/common/download/)

2、[Air780EPM 最新版本的内核固件](https://docs.openluat.com/air780epm/luatos/firmware/version/)


## 演示核心步骤

1、搭建好硬件环境

2、Luatools烧录内核固件和demo脚本代码

3、烧录成功后，自动开机运行

4、出现类似于下面的日志且核心板上的蓝灯1秒闪烁1次，就表示运行成功：

``` lua
[2025-11-21 10:09:15.776][000000008.744] I/user.led_blink_app led： off
[2025-11-21 10:09:16.778][000000009.745] I/user.led_blink_app led： on
[2025-11-21 10:09:17.784][000000010.746] I/user.led_blink_app led： off
[2025-11-21 10:09:18.780][000000011.747] I/user.led_blink_app led： on
[2025-11-21 10:09:19.784][000000012.748] I/user.led_blink_app led： off
[2025-11-21 10:09:20.778][000000013.748] I/user.led_blink_app led： on
```

![](https://docs.openluat.com/air780epm/luatos/common/hwenv/image/Air780EPM_led.png)
