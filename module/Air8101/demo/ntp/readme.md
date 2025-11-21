## 功能模块介绍：

1、main.lua：主程序入口；

2、netdrv_device.lua：网卡驱动设备，可以配置使用netdrv文件夹内的五种网卡(单wifi网卡，单rmii以太网卡，单spi以太网卡，多网卡，pc模拟器上的网卡)中的任何一种网卡；

3、netdrv文件夹：五种网卡，单wifi网卡、单rmii以太网卡、单spi以太网卡、多网卡、pc模拟器上的网卡，供netdrv_device.lua加载配置；

4、ntp_test.lua:   功能演示核心脚本，联网、时间同步、获取时间等,在main.lua中加载运行。

## 演示功能概述：

1.判断是否联网

2.网络就绪后开始时间同步

3.时间同步成功，获取本地时间和UTC时间，按默认间隔时间循环打印获取的时间信息

4.时间同步失败，打印提醒



## 演示硬件环境

![netdrv_multi](https://docs.openluat.com/accessory/AirSPINORFLASH_1000/image/8101.jpg)



1、Air8101核心板一块

2、TYPE-C USB数据线一根

3、Air8101核心板和数据线的硬件接线方式为

* Air8101核心板通过TYPE-C USB口供电；（核心板背面的功耗测试开关拨到OFF一端）

* 如果测试发现软件频繁重启，重启原因值为：poweron reason 0，可能是供电不足，此时再通过直流稳压电源对核心板的vbat管脚进行4V供电，或者VIN管脚进行5V供电；

* TYPE-C USB数据线直接插到核心板的TYPE-C USB座子，另外一端连接电脑USB口；

4、可选AirETH_1000配件板一块，Air8101核心板和AirPHY_1000配件板的硬件接线方式为:

| Air8101核心板 | AirETH_1000配件板 |
|:----------:|:--------------:|
| 59/3V3     | 3.3v           |
| GND        | GND            |
| 28/DCLK    | SCK            |
| 54/DISP    | CSS            |
| 55/HSYN    | SDO            |
| 57/DE      | SDI            |
| 14/GPIO8   | INT            |

5、可选AirPHY_1000配件板一块，Air8101核心板和AirPHY_1000配件板的硬件接线方式为:

| Air8101核心板 | AirPHY_1000配件板 |
| ---------- | -------------- |
| 59/3V3     | 3.3v           |
| gnd        | gnd            |
| 5/D2       | RX1            |
| 72/D1      | RX0            |
| 71/D3      | CRS            |
| 4/D0       | MDIO           |
| 6/D4       | TX0            |
| 74/PCK     | MDC            |
| 70/D5      | TX1            |
| 7/D6       | TXEN           |
| 不接         | NC             |
| 69/D7      | CLK            |



## 演示软件环境

1、 Luatools下载调试工具

2、 固件版本：LuatOS-SoC_V1006_Air8101_1.soc，固件地址，如有最新固件请用最新 [https://docs.openluat.com/air8101/luatos/firmware/](https://docs.openluat.com/air8101/luatos/firmware/)



3、 脚本文件：
   main.lua

   ntp_test.lua

   netdrv_device.lua

   netdrv文件夹

4、 pc 系统 win11（win10 及以上）



## 演示核心步骤

1、搭建好硬件环境

2、demo脚本代码netdrv_device.lua中，按照自己的网卡需求启用对应的Lua文件

* 如果需要单WIFI STA网卡，打开require "netdrv_wifi"，其余注释掉；同时netdrv_wifi.lua中的wlan.connect("茶室-降功耗,找合宙!", "Air123456", 1)，前两个参数，修改为自己测试时wifi热点的名称和密码；注意：仅支持2.4G的wifi，不支持5G的wifi

* 如果需要RMII以太网卡，打开require "netdrv_eth_rmii"，其余注释掉

* 如果需要SPI以太网卡，打开require "netdrv_eth_spi"，其余注释掉
  
  

* 如果需要多网卡，打开require "netdrv_multiple"，其余注释掉；同时netdrv_multiple.lua中的ssid = "茶室-降功耗,找合宙!", password = "Air123456", 修改为自己测试时wifi热点的名称和密码；注意：仅支持2.4G的wifi，不支持5G的wifi

3、如果使用自定义NTP服务器 地址，脚本文件ntp_test.lua中，在ntp_servers表中修改为自己的服务器地址，并在sntp_sync_loop()函数中，注释sntp时间同步方式2，打开方式1

4、Luatools烧录内核固件和修改后的demo脚本代码

5、烧录成功后，代码会自动运行，查看打印日志，如果正常运行，会打印网络就绪、时间同步成功、本地时间以及URC时间等信息，如下log显示：

```
[2025-11-20 16:00:39.719] luat:D(4481):ulwip:IP_READY 2 192.168.43.169
[2025-11-20 16:00:39.719] luat:U(4483):I/user.netdrv_wifi.ip_ready_func IP_READY {"gw":"192.168.43.1","rssi":-32,"bssid":"5285FA8C4113"}
[2025-11-20 16:00:39.719] luat:U(4483):I/user.sntp recv IP_READY 2 2
[2025-11-20 16:00:39.719] luat:U(4484):I/user.sntp 开始同步：
[2025-11-20 16:00:39.719] luat:D(4484):sntp:query ntp.aliyun.com
[2025-11-20 16:00:39.719] luat:D(4484):DNS:ntp.aliyun.com state 0 id 1 ipv6 0 use dns server0, try 0
[2025-11-20 16:00:39.719] luat:D(4484):net:adatper 2 dns server 192.168.43.1
[2025-11-20 16:00:39.719] luat:D(4484):net:dns udp sendto 192.168.43.1:53 from 192.168.43.169
[2025-11-20 16:00:39.719] luat:D(4488):wlan:event_module 2 event_id 0
[2025-11-20 16:00:39.719] luat:I(4503):DNS:dns all done ,now stop
[2025-11-20 16:00:39.719] luat:D(4503):net:connect 203.107.6.88:123 UDP
[2025-11-20 16:00:39.784] luat:D(4538):sntp:Unix timestamp: 1763625640
[2025-11-20 16:00:39.784] luat:U(4539):I/user.sntp 时间同步成功
[2025-11-20 16:00:39.784] luat:U(4539):I/user.sntp 本地时间字符串 Thu Nov 20 16:00:40 2025
[2025-11-20 16:00:39.784] luat:U(4540):I/user.sntp UTC时间字符串 Thu Nov 20 08:00:40 2025
[2025-11-20 16:00:39.784] luat:U(4540):I/user.sntp 格式化本地时间字符串 2025-11-20 16:00:40
[2025-11-20 16:00:39.784] luat:U(4541):I/user.sntp 格式化UTC时间字符串 2025-11-20 08:00:40
[2025-11-20 16:00:39.784] luat:U(4541):I/user.sntp RTC时钟(UTC) {"year":2025,"min":0,"hour":8,"mon":11,"sec":40,"day":20}
[2025-11-20 16:00:39.784] luat:U(4542):I/user.sntp 本地时间戳 1763625640
[2025-11-20 16:00:39.784] luat:U(4542):I/user.sntp 本地时间结构 {"wday":5,"min":0,"yday":324,"hour":16,"isdst":false,"year":2025,"month":11,"sec":40,"day":20}
[2025-11-20 16:00:39.784] luat:U(4543):I/user.sntp 结构时间转时间戳 1763654440
[2025-11-20 16:00:39.784] luat:U(4544):I/user.tm数据 {"sms":394,"tms":937,"vaild":true,"tsec":1763625639,"lms":543,"ndeley":0,"lsec":4,"ssec":1763625635}
[2025-11-20 16:00:39.784] luat:U(4544):I/user.sntp 高精度时间戳 1763625639.937

```
