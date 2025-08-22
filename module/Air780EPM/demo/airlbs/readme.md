## 功能模块介绍

1、main.lua：主程序入口；

2、netdrv_device.lua：网卡驱动设备，可以配置使用netdrv文件夹内的四种网卡(单4g网卡，单wifi网卡，单spi以太网卡，多网卡)中的任何一种网卡；

3、airlbs_app.lua：合宙airlbs“多基站”、“多基站+多wifi”两种应用场景的定位功能模块； 

## 演示功能概述

使用Air780EPM V1.3开发板测试airlbs功能

1、airlbs“多基站”、“多基站+多wifi”两种应用场景的定位演示。

2、netdrv_device：配置连接外网使用的网卡，目前支持以下四种选择（四选一）

(1) netdrv_4g：4G网卡

(2) netdrv_eth_spi：通过SPI外挂CH390H芯片的以太网卡

(3) netdrv_multiple：支持以上三种网卡，可以配置三种网卡的优先级

本功能为收费项目，相对于免费的单 LBS 定位服务来说，定位精度更高，缴费地址[合宙云平台](https://iot.openluat.com/finance/order)。

如需免费的单基站定位服务，可参考lbsloc2的相关demo，但是由于单基站定位技术本身的原因，无法提供相对精准的定位服务。

## 演示硬件环境

![img](https://docs.openluat.com/air780epm/luatos/app/driver/eth/image/RFSvb75NRoEWqYxfCRVcVrOKnsf.jpg)

1、Air780EPM V1.3版本开发板一块+可上网的sim卡一张+4g天线一根+网线一根：

- sim卡插入开发板的sim卡槽
- 天线装到开发板上
- 网线一端插入开发板网口，另外一端连接可以上外网的路由器网口

2、TYPE-C USB数据线一根 + USB转串口数据线一根，Air780EPM V1.3版本开发板和数据线的硬件接线方式为：

- Air780EPM V1.3版本开发板通过TYPE-C USB口供电；（外部供电/USB供电 拨动开关 拨到 USB供电一端）
- TYPE-C USB数据线直接插到核心板的TYPE-C USB座子，另外一端连接电脑USB口；

## 演示软件环境

1、Luatools下载调试工具

2、[Air780EPM V2012版本固件](https://gitee.com/link?target=https%3A%2F%2Fdocs.openluat.com%2Fair780epm%2Fluatos%2Ffirmware%2Fversion%2F)（理论上，2025年8月10日之后发布的固件都可以）

## 演示核心步骤

1、搭建好硬件环境

2、demo脚本代码netdrv_device.lua中，按照自己的网卡需求启用对应的Lua文件

- 如果需要单4G网卡，打开require "netdrv_4g"，其余注释掉
- 如果需要以太网卡，打开require "netdrv_eth_spi"，其余注释掉
- 如果需要多网卡，打开require "netdrv_multiple"，其余注释掉

3、修改airlbs_app.lua文件中的airlbs_project_id和airlbs_project_key，对应[合宙云平台](https://iot.openluat.com/lbs/project-list)我的项目里面的key_id和key。

3、烧录内核固件和airlbs相关demo成功后，自动开机运行。

4、可以看到代码运行结果如下，不管是在选择什么网卡场景下，基本都是如下情况：

以下是默认使用4G网卡下使用airlbs“多基站”、“多基站+多wifi”两种应用场景的定位演示的日志

日志中如果出现以下类似打印则说明定位成功：

多基站定位返回的经纬度数据为 {"lat":31.1354542,"lng":121.5423279}

多基站+多wifi定位返回的经纬度数据为 {"lat":31.1334343,"lng":121.5450211}

```
[2025-08-18 18:27:06.254][000000006.164] I/user.netdrv_4g.ip_ready_func IP_READY 10.63.114.98 255.255.255.255 0.0.0.0 nil

[2025-08-18 18:27:06.261][000000006.192] D/mobile TIME_SYNC 0

[2025-08-18 18:27:06.267][000000006.196] dns_run 691:dns all done ,now stop

[2025-08-18 18:27:06.271][000000006.213] I/user.扫描出的数据 {"cells":[[460,0,6278,28455710,-59,-1,333,-87,-11,3590]]}

[2025-08-18 18:27:06.277][000000006.214] D/socket connect to airlbs.openluat.com,12413

[2025-08-18 18:27:06.282][000000006.214] dns_run 674:airlbs.openluat.com state 0 id 2 ipv6 0 use dns server2, try 0

[2025-08-18 18:27:06.287][000000006.238] D/sntp Unix timestamp: 1755512826

[2025-08-18 18:27:06.291][000000006.245] dns_run 691:dns all done ,now stop

[2025-08-18 18:27:06.297][000000006.247] I/user.airlbs 服务器连上了

[2025-08-18 18:27:06.326][000000006.296] I/user.airlbs wait true true nil

[2025-08-18 18:27:06.334][000000006.298] I/user.定位请求的结果 true 超时时间 0 table: 0C7F1C60

[2025-08-18 18:27:06.340][000000006.299] I/user.多基站请求成功,服务器返回的原始数据 table: 0C7F1C60

[2025-08-18 18:27:06.349][000000006.299] I/user.airlbs多基站定位返回的经纬度数据为 {"lat":31.1354542,"lng":121.5423279}

[2025-08-18 18:27:07.955][000000007.944] D/airlink.wlan 收到扫描结果 11

[2025-08-18 18:27:07.964][000000007.946] I/user.scan wifi_info 11

[2025-08-18 18:27:08.114][000000008.095] I/user.扫描出的数据 {"cells":[[460,0,6278,28455710,-59,0,333,-85,-9,3590],[460,0,6278,140674719,null,0,108,-93,-17,3590]],"macs":[["40:31:3C:D7:B4:BB",-77],["8C:DE:F9:21:02:AA",-78],["68:77:24:19:60:EE",-82],["02:E7:E3:BF:CC:73",-91],["80:89:17:56:DA:25",-91],["02:E7:E3:9F:CC:73",-93],["02:E7:E3:AF:CC:73",-95],["92:76:9F:13:21:BD",-95],["22:08:89:26:DF:44",-96],["00:E7:E3:FF:CC:73",-96],["72:85:C4:8E:EF:EA",-99]]}

[2025-08-18 18:27:08.120][000000008.096] D/socket connect to airlbs.openluat.com,12413

[2025-08-18 18:27:08.126][000000008.096] dns_run 674:airlbs.openluat.com state 0 id 3 ipv6 0 use dns server2, try 0

[2025-08-18 18:27:08.145][000000008.127] dns_run 691:dns all done ,now stop

[2025-08-18 18:27:08.150][000000008.128] I/user.airlbs 服务器连上了

[2025-08-18 18:27:08.192][000000008.176] I/user.airlbs wait true true nil

[2025-08-18 18:27:08.197][000000008.178] I/user.定位请求的结果 true 超时时间 0 table: 0C7EDAD0

[2025-08-18 18:27:08.204][000000008.179] [2025-08-18 18:28:36.976][000000096.887] I/user.airlbs多基站+多wifi定位返回的经纬度数据为 {"lat":31.1334343,"lng":121.5450211}

[2025-08-18 18:28:36.988][000000096.887] I/user.airlbs lat 31.1334343

[2025-08-18 18:28:36.999][000000096.888] I/user.airlbs lng 121.5450211


```







