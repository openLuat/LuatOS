
## 演示功能概述

使用Air8201H，利用libgnss核心库如何实现定位功能

主要操作为：

打开GNSS，使用AGPS辅助定位

定位成功之后，获取经纬度信息

## 演示硬件环境

1、Air8201H板子一个

2、TYPE-C USB数据线一根

3、gnss天线一根


## 演示软件环境

1、Luatools下载调试工具

2、[Air8201H最新版本固件](https://docs.openluat.com/air780epm/luatos/firmware/version/)

## 演示核心步骤

1、搭建好硬件环境

2、通过Luatools将demo与固件烧录到核心板中

3、烧录好后，板子开机将会在Luatools上看到如下打印：

(1) GNSS开启：

```lua
[2026-07-15 17:03:10.306][000000000.269] I/user.GPS start
[2026-07-15 17:03:10.311][000000000.269] Uart_ChangeBR 1461:uart2, 115200 115203 26000000 3611
[2026-07-15 17:03:10.318][000000000.470] D/gnss Debug ON
[2026-07-15 17:03:10.324][000000000.531] W/user.airlbs_multi_cells_wifi_func wait IP_READY 1 1
[2026-07-15 17:03:10.330][000000000.596] D/gnss >> 
CC0257B
PN N/A
SN N/A
HWVer V2.0
FWVer N1000R2.1.1.11Build12069
Copyright (c), ICOE(Shanghai) Technologies Co.,Ltd.
All rights reserved.


```

(2) GNSS定位成功：

```lua
[2026-07-15 17:03:57.253][000000048.700] I/user.exgnss state FIXED
[2026-07-15 17:03:57.264][000000048.701] I/user.nmea rmc0 {"variation":0,"lat":3447.71509,"min":3,"valid":true,"day":15,"lng":11419.71484,"speed":2.53300,"year":2026,"month":7,"sec":57,"hour":9,"course":220.09599}


```
