## 功能模块介绍：

1、main.lua：主程序入口；

2、netdrv_device.lua：网卡驱动设备，可以配置使用netdrv文件夹内的四种网卡(单4g网卡，单spi以太网卡，多网卡，pc模拟器上的网卡)中的任何一种网卡；

3、netdrv文件夹：四种网卡，单4g网卡、单spi以太网卡、多网卡、pc模拟器上的网卡，供netdrv_device.lua加载配置；

4、ntp_test.lua:   功能演示核心脚本，联网、时间同步、获取时间等,在main.lua中加载运行。

## 演示功能概述：

1.判断是否联网

2.网络就绪后开始时间同步

3.时间同步成功，获取本地时间和UTC时间，按默认间隔时间循环打印获取的时间信息

4.时间同步失败，打印提醒



## 演示硬件环境

![netdrv_multi](https://docs.openluat.com/accessory/AirSPINORFLASH_1000/image/780EPM.jpg)



1、Air780EPM核心板一块+可上网的 sim 卡一张 + 网线一根：

* sim 卡插入核心板的 sim 卡槽

* 网线一端插入AirETH_1000 配件板网口，AirETH_1000 配件板与核心板按下方表格说明接线，另外一端连接可以上外网的路由器网口

2、TYPE-C USB 数据线一根 + USB 转串口数据线一根，Air780EPM核心板和数据线的硬件接线方式为：

* Air780EPM核心板通过 TYPE-C USB 口供电；（USB的拨码开关off/on,拨到on）

* TYPE-C USB 数据线直接插到核心板的 TYPE-C USB 座子，另外一端连接电脑 USB 口；

* 3、可选 AirETH_1000 配件板一块，Air780EPM核心板和 AirETH_1000 配件板的硬件接线方式为:
  
  | Air780EPM核心板 | AirETH_1000 配件板 |
  |:------------:|:---------------:|
  | 3V3          | 3.3v            |
  | GND          | GND             |
  | 86/SPI0CLK   | SCK             |
  | 83/SPI0CS    | CSS             |
  | 84/SPI0MISO  | SDO             |
  | 85/SPI0MOSI  | SDI             |
  | 107/GPIO21   | INT             |

## 演示软件环境

1、 Luatools下载调试工具

2、 Air780EPM固件版本：LuatOS-SoC_V2016_Air780EPM_1，固件地址，如有最新固件请用最新 [https://docs.openluat.com/air780epm/luatos/firmware/](https://docs.openluat.com/air780epm/luatos/firmware/version/)

3、 脚本文件：
   main.lua

   ntp_test.lua

   netdrv_device.lua

   netdrv文件夹

4、 pc 系统 win11（win10 及以上）



## 演示核心步骤

1、搭建好硬件环境

2、demo脚本代码netdrv_device.lua中，按照自己的网卡需求启用对应的Lua文件

* 如果需要单4G网卡，打开require "netdrv_4g"，其余注释掉

* 如果需要以太网卡，打开require "netdrv_eth_spi"，其余注释掉

* 如果需要多网卡，打开require "netdrv_multiple"，其余注释掉；

3、如果使用自定义NTP服务器 地址，脚本文件ntp_test.lua中，在ntp_servers表中修改为自己的服务器地址，并在sntp_sync_loop()函数中，注释sntp时间同步方式2，打开方式1

4、Luatools烧录内核固件和修改后的demo脚本代码

5、烧录成功后，代码会自动运行，查看打印日志，如果正常运行，会打印网络就绪、时间同步成功、本地时间以及URC时间等信息，如下log显示：

```
[2025-11-20 15:20:12.188][000000000.206] I/user.main ntp_demo 001.000.000
[2025-11-20 15:20:12.195][000000000.226] W/user.sntp wait IP_READY 1 1
[2025-11-20 15:20:12.540][000000001.226] W/user.sntp wait IP_READY 1 1
[2025-11-20 15:20:13.552][000000002.227] W/user.sntp wait IP_READY 1 1
[2025-11-20 15:20:14.550][000000003.228] W/user.sntp wait IP_READY 1 1
[2025-11-20 15:20:15.550][000000004.228] W/user.sntp wait IP_READY 1 1
[2025-11-20 15:20:16.544][000000005.229] W/user.sntp wait IP_READY 1 1
[2025-11-20 15:20:16.707][000000005.355] D/mobile cid1, state0
[2025-11-20 15:20:16.711][000000005.356] D/mobile bearer act 0, result 0
[2025-11-20 15:20:16.718][000000005.356] D/mobile NETIF_LINK_ON -> IP_READY
[2025-11-20 15:20:16.723][000000005.357] I/user.netdrv_4g.ip_ready_func IP_READY 10.129.19.238 255.255.255.255 0.0.0.0 nil
[2025-11-20 15:20:16.726][000000005.359] I/user.sntp recv IP_READY 1 1
[2025-11-20 15:20:16.739][000000005.359] I/user.sntp 开始同步：
[2025-11-20 15:20:16.743][000000005.359] D/sntp query ntp.aliyun.com
[2025-11-20 15:20:16.748][000000005.360] dns_run 676:ntp.aliyun.com state 0 id 1 ipv6 0 use dns server2, try 0
[2025-11-20 15:20:16.755][000000005.391] D/mobile TIME_SYNC 0
[2025-11-20 15:20:16.757][000000005.392] I/user.sntp 时间同步成功
[2025-11-20 15:20:16.761][000000005.393] I/user.sntp 本地时间字符串 Thu Nov 20 15:20:17 2025
[2025-11-20 15:20:16.765][000000005.394] I/user.sntp UTC时间字符串 Thu Nov 20 07:20:17 2025
[2025-11-20 15:20:16.768][000000005.395] I/user.sntp 格式化本地时间字符串 2025-11-20 15:20:17
[2025-11-20 15:20:16.776][000000005.395] I/user.sntp 格式化UTC时间字符串 2025-11-20 07:20:17
[2025-11-20 15:20:16.780][000000005.396] I/user.sntp RTC时钟(UTC) {"year":2025,"min":20,"hour":7,"mon":11,"sec":17,"day":20}
[2025-11-20 15:20:16.788][000000005.396] I/user.sntp 本地时间戳 1763623217
[2025-11-20 15:20:16.793][000000005.397] I/user.sntp 本地时间结构 {"wday":5,"min":20,"yday":324,"hour":15,"isdst":false,"year":2025,"month":11,"sec":17,"day":20}
[2025-11-20 15:20:16.796][000000005.398] I/user.sntp 结构时间转时间戳 1763652017
[2025-11-20 15:20:16.799][000000005.398] I/user.tm数据 {"sms":0,"tms":398,"tsec":5,"lms":398,"ndeley":0,"lsec":5,"ssec":0}
[2025-11-20 15:20:16.811][000000005.399] I/user.sntp 高精度时间戳 5.398
[2025-11-20 15:20:16.815][000000005.404] dns_run 693:dns all done ,now stop
[2025-11-20 15:20:16.821][000000005.457] D/sntp Unix timestamp: 1763623217

```
