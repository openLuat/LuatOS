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

![netdrv_multi](https://docs.openluat.com/accessory/AirSPINORFLASH_1000/image/780EHV.jpg)



1、Air780EHM/EHV/EGH核心板一块+可上网的 sim 卡一张 +网线一根：

* sim 卡插入核心板的 sim 卡槽

* 网线一端插入AirETH_1000 配件板网口，AirETH_1000 配件板与核心板按下方表格说明接线，另外一端连接可以上外网的路由器网口

2、TYPE-C USB 数据线一根 + USB 转串口数据线一根，Air780EHM/EHV/EGH核心板和数据线的硬件接线方式为：

* Air780EHM/EHV/EGH核心板通过 TYPE-C USB 口供电；（USB的拨码开关off/on,拨到on）

* TYPE-C USB 数据线直接插到核心板的 TYPE-C USB 座子，另外一端连接电脑 USB 口；

3、可选 AirETH_1000 配件板一块，Air780EHM/EHV/EGH 核心板和 AirETH_1000 配件板的硬件接线方式为:

| Air780EHM/EHV/EGH核心板 | AirETH_1000配件板 |
|:--------------------:|:--------------:|
| 3V3                  | 3.3v           |
| GND                  | GND            |
| 86/SPI0CLK           | SCK            |
| 83/SPI0CS            | CSS            |
| 84/SPI0MISO          | SDO            |
| 85/SPI0MOSI          | SDI            |
| 107/GPIO21           | INT            |



## 演示软件环境

1、 Luatools下载调试工具

2、 Air780EHM固件版本：LuatOS-SoC_V2016_Air780EHM_1，固件地址，如有最新固件请用最新 [https://docs.openluat.com/air780ehm/luatos/firmware/](https://docs.openluat.com/air780ehm/luatos/firmware/version/)



      Air780EHV固件版本：LuatOS-SoC_V2016_Air780EHV_1，固件地址，如有最新固件请用最新 [https://docs.openluat.com/air780ehv/luatos/firmware/](https://docs.openluat.com/air780ehv/luatos/firmware/version/)



      Air780EGH固件版本：LuatOS-SoC_V2016_Air780EGH_1，固件地址，如有最新固件请用最新 [https://docs.openluat.com/air780egh/luatos/firmware/](https://docs.openluat.com/air780egh/luatos/firmware/version/)



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
[2025-11-20 15:15:36.331][000000000.260] I/user.main ntp_demo 001.000.000
[2025-11-20 15:15:36.348][000000000.282] W/user.sntp wait IP_READY 1 1
[2025-11-20 15:15:36.836][000000001.283] W/user.sntp wait IP_READY 1 1
[2025-11-20 15:15:37.831][000000002.284] W/user.sntp wait IP_READY 1 1
[2025-11-20 15:15:37.937][000000002.334] D/mobile cid1, state0
[2025-11-20 15:15:37.947][000000002.335] D/mobile bearer act 0, result 0
[2025-11-20 15:15:37.951][000000002.336] D/mobile NETIF_LINK_ON -> IP_READY
[2025-11-20 15:15:37.956][000000002.337] I/user.netdrv_4g.ip_ready_func IP_READY 10.28.141.84 255.255.255.255 0.0.0.0 nil
[2025-11-20 15:15:37.959][000000002.340] I/user.sntp recv IP_READY 1 1
[2025-11-20 15:15:37.968][000000002.340] I/user.sntp 开始同步：
[2025-11-20 15:15:37.975][000000002.341] D/sntp query ntp.aliyun.com
[2025-11-20 15:15:37.978][000000002.341] dns_run 676:ntp.aliyun.com state 0 id 1 ipv6 0 use dns server0, try 0
[2025-11-20 15:15:37.985][000000002.352] D/mobile TIME_SYNC 0
[2025-11-20 15:15:37.987][000000002.354] I/user.sntp 时间同步成功
[2025-11-20 15:15:37.992][000000002.354] I/user.sntp 本地时间字符串 Thu Nov 20 15:15:38 2025
[2025-11-20 15:15:37.995][000000002.355] I/user.sntp UTC时间字符串 Thu Nov 20 07:15:38 2025
[2025-11-20 15:15:38.004][000000002.356] I/user.sntp 格式化本地时间字符串 2025-11-20 15:15:38
[2025-11-20 15:15:38.008][000000002.357] I/user.sntp 格式化UTC时间字符串 2025-11-20 07:15:38
[2025-11-20 15:15:38.011][000000002.358] I/user.sntp RTC时钟(UTC) {"year":2025,"min":15,"hour":7,"mon":11,"sec":38,"day":20}
[2025-11-20 15:15:38.019][000000002.358] I/user.sntp 本地时间戳 1763622938
[2025-11-20 15:15:38.023][000000002.359] I/user.sntp 本地时间结构 {"wday":5,"min":15,"yday":324,"hour":15,"isdst":false,"year":2025,"month":11,"sec":38,"day":20}
[2025-11-20 15:15:38.029][000000002.360] I/user.sntp 结构时间转时间戳 1763651738
[2025-11-20 15:15:38.037][000000002.360] I/user.tm数据 {"sms":0,"tms":360,"tsec":2,"lms":360,"ndeley":0,"lsec":2,"ssec":0}
[2025-11-20 15:15:38.040][000000002.361] I/user.sntp 高精度时间戳 2.360
[2025-11-20 15:15:38.045][000000002.375] dns_run 693:dns all done ,now stop
[2025-11-20 15:15:38.053][000000002.430] D/sntp Unix timestamp: 1763622938

```
