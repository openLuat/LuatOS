## 功能模块介绍

1、main.lua：主程序入口；

2、netdrv_device.lua：网卡驱动设备，可以配置使用netdrv文件夹内的四种网卡(单wifi网卡，单spi以太网卡，多网卡)中的任何一种网卡；

3、airlbs_app.lua：合宙airlbs“多wifi”应用场景的定位功能模块； 

## 演示功能概述

使用Air8101核心板测试airlbs功能

1、airlbs“多wifi”应用场景的定位演示。

2、netdrv_device：配置连接外网使用的网卡，目前支持以下四种选择（三选一）

(1) netdrv_wifi：WIFI STA网卡

(2) netdrv_eth_spi：通过SPI外挂CH390H芯片的以太网卡

(3) netdrv_multiple：支持以上三种网卡，可以配置两种网卡的优先级

本功能为收费项目，相对于免费的单 LBS 定位服务来说，定位精度更高，缴费地址[合宙云平台](https://iot.openluat.com/finance/order)。


## 演示硬件环境

![](https://docs.openLuat.com/cdn/image/8101核心板.jpg)

1、Air8101核心板一块：

2、TYPE-C USB数据线一根 ，Air8101核心板和数据线的硬件接线方式为：

* Air8101核心板通过TYPE-C USB口供电；（5V / 3.3V 供电 拨动开关 拨到 3.3V供电一端，功耗测试开关 拨到 OFF）

* TYPE-C USB数据线直接插到开发板的TYPE-C USB座子，另外一端连接电脑USB口；

3、可选AirETH_1000配件板一块，Air8101核心板和AirETH_1000配件板的硬件接线方式为:

| Air8101核心板 | AirETH_1000配件板 |
| ---------- | -------------- |
| 59/3V3     | 3.3v           |
| gnd        | gnd            |
| 28/DCLK    | SCK            |
| 54/DISP    | CSS            |
| 55/HSYN    | SDO            |
| 57/DE      | SDI            |
| 14/GPIO8   | INT            |

## 演示软件环境

1、Luatools下载调试工具

2、[Air8101 V1006版本](https://docs.openluat.com/air8101/luatos/firmware/)（理论上最新版本固件也可以，如果使用最新版本的固件不可以，可以烧录V2012-1固件对比验证）

## 演示核心步骤

1、搭建好硬件环境

2、demo脚本代码netdrv_device.lua中，按照自己的网卡需求启用对应的Lua文件

- 如果需要单WIFI STA网卡，打开require "netdrv_wifi"，其余注释掉；同时netdrv_wifi.lua中的wlan.connect("茶室-降功耗,找合宙!", "Air123456", 1)，前两个参数，修改为自己测试时wifi热点的名称和密码；注意：仅支持2.4G的wifi，不支持5G的wifi

- 如果需要以太网卡，打开require "netdrv_eth_spi"，其余注释掉

- 如果需要多网卡，打开require "netdrv_multiple"，其余注释掉；同时netdrv_multiple.lua中的ssid = "茶室-降功耗,找合宙!", password = "Air123456", 修改为自己测试时wifi热点的名称和密码；注意：仅支持2.4G的wifi，不支持5G的wifi

3、修改airlbs_app.lua文件中的airlbs_project_id和airlbs_project_key，对应[合宙云平台](https://iot.openluat.com/lbs/project-list)我的项目里面的key_id和key。

3、烧录内核固件和airlbs相关demo成功后，自动开机运行。

4、可以看到代码运行结果如下，不管是在选择什么网卡场景下，基本都是如下情况：

以下是默认使用WIFI网卡下使用airlbs“多wifi”两种应用场景的定位演示的日志

日志中如果出现以下类似打印则说明定位成功：

多wifi定位返回的经纬度数据为 {"lat":31.1342087,"lng":121.5439911}

```lua
[2025-12-23 11:05:48.657] luat:D(7947):wlan:scan wifi 结果 10
[2025-12-23 11:05:48.657] luat:U(7948):I/user.scan wifi_info 10
[2025-12-23 11:05:48.765] luat:U(7949):I/user.mac M01C8C2C68C5D7A
[2025-12-23 11:05:48.765] luat:U(7950):I/user.硬件型号 Air8101
[2025-12-23 11:05:48.765] luat:U(7951):I/user.muid ae7863d6e562b04c01c5d788837d417f
[2025-12-23 11:05:48.765] luat:U(7955):I/user.扫描出的数据 {"macs":[["8C:DE:F9:21:02:AA",-50],["92:76:9F:13:21:BD",-36],["82:89:17:C4:9D:9A",-36],["40:31:3C:D7:B4:BB",-47],["7C:B5:9B:54:77:6A",-53],["7E:B5:9B:54:77:6A",-53],["24:DA:33:40:31:40",-64],["24:DA:33:40:31:41",-67],["14:D8:64:E4:C6:5D",-76],["00:90:4D:4C:93:CE",-78]]}
[2025-12-23 11:05:48.765] luat:D(7957):socket:connect to airlbs.openluat.com,12413
[2025-12-23 11:05:48.765] luat:D(7957):DNS:airlbs.openluat.com state 0 id 2 ipv6 0 use dns server0, try 0
[2025-12-23 11:05:48.765] luat:D(7957):net:adatper 2 dns server 192.168.31.1
[2025-12-23 11:05:48.765] luat:D(7958):net:dns udp sendto 192.168.31.1:53 from 192.168.31.122
[2025-12-23 11:05:48.765] luat:I(7971):DNS:dns all done ,now stop
[2025-12-23 11:05:48.765] luat:D(7972):net:adapter 2 connect 121.40.251.45:12413 UDP
[2025-12-23 11:05:48.765] luat:U(7973):I/user.airlbs 服务器连上了
[2025-12-23 11:05:48.765] luat:U(7990):I/user.airlbs wait true true nil
[2025-12-23 11:05:48.765] luat:U(7992):I/user.定位请求的结果 true 超时时间 0 table: 609AE8D8
[2025-12-23 11:05:48.765] luat:U(7992):I/user.多wifi请求成功,服务器返回的原始数据 table: 609AE8D8
[2025-12-23 11:05:48.765] luat:U(7993):I/user.多wifi定位返回的经纬度数据为 {"lat":31.1342218,"lng":121.5439879}
[2025-12-23 11:05:48.765] luat:U(7993):I/user.airlbs lat 31.1342218
[2025-12-23 11:05:48.765] luat:U(7993):I/user.airlbs lng 121.5439879


```
