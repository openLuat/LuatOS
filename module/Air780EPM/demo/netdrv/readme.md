## 功能模块介绍

1、main.lua：主程序入口；

2、netdrv_eth_wan.lua：以太网wan

3、netdrv_eth_lan.lua：以太网lan

4、netdrv_4g_multiple.lua：4G连接外部网络，以太网lan模式为其他以太网设备提供接入 

5、netdrv_eth_multiple：双以太网口，以太网WAN->以太网LAN

## 演示功能概述

1、演示 netdrv核心库+dnsproxy扩展库+dhcpsrv扩展库 开启以太网或双以太网口,4G,以太网多网融合功能.

## 演示硬件环境

### Air780EPM 开发板

![](https://docs.openluat.com/air8101/luatos/app/multinetwork/4G/image/Q5o4bXvOsoGMe7xQZK2cZ1CFnxf.png)
Air780EPM V1.3开发板一块 +TYPE-C USB 数据线一根 +可上网的sim卡一张 +4g天线一根+网线两根根：

- sim卡插入开发板的sim卡槽

- 天线装到开发板上

2、网线接线说明：

- netdrv_eth_wan 模块以太网口接路由器LAN口或交换机

- netdrv_eth_lan 模块以太网口接电脑或需要上网的设备

- netdrv_4g_multiple 模块以太网口接电脑或需要上网的设备

- netdrv_eth_multiple 模块以太网WAN接路由器LAN口或交换机,AirETH_1000配件板LAN口接需要上网的设备

- AirETH_1000配件板接到开发板上 可以用电脑接AirETH_1000配件板网口

| Air780EPM开发板  |  AirETH_1000配件板 |
| --------------- | ----------------- |
| LCD座子的VCC供电 | 3.3v              |
| gnd             | gnd               |
| UART3_TX        | SCK               |
| UART2_RX        | CSS               |
| UART3_RX        | SDO               |
| UART2_TX        | SDI               |
| nil             | INT               |

3、TYPE-C USB数据线一根 Air780EPM开发板和数据线的硬件接线方式为：

- TYPE-C USB数据线直接插到核心板的TYPE-C USB座子，另外一端连接电脑USB口；

## 演示软件环境

1、Luatools下载调试工具

3、内核固件：[Air780EPM V2018 版本固件](https://docs.openluat.com/air780epm/luatos/firmware/version/)；如有更新可以使用最新固件。


## 演示核心步骤

1、搭建好硬件环境，按接线图连接硬件,

2、在main.lua中按照自己的网卡需求启用对应的Lua文件

- 如果需要开启以太网lan，打开require "netdrv_eth_lan"，其余注释掉

- 如果需要开启以太网wan，打开require "netdrv_eth_wan"，其余注释掉

- 如果需要开启4G转以太网的多网融合，打开require "netdrv_4g_multiple"，其余注释掉

- 如果需要开启双以太网口的多网融合，打开require "netdrv_eth_multiple.lua"，其余注释掉

3、Luatools烧录内核固件和修改后的demo脚本代码
netdrv_eth_lan：
模块以太网接口接其他设备，这里演示使用电脑连接，可以dhcp获取ip，可以ping通模块
![](https://docs.openluat.com/air780epm/luatos/app/socket/netdrv/image/780epm-netdrv2.png)

netdrv_eth_wan：
模块以太网口接路由器，模块成功联网并http请求成功
![](https://docs.openluat.com/air780epm/luatos/app/socket/netdrv/image/780epm-netdrv1.png)

netdrv_4g_multiple：
4G作为数据出口，这里使用电脑连接模块以太网接口上网
![](https://docs.openluat.com/air780epm/luatos/app/socket/netdrv/image/780epm-netdrv4.png)

netdrv_eth_multiple：
模块以太网口WAN接路由器LAN口，这里使用电脑连接模块LAN口，dhcp获取到ip，测试网络正常
![](https://docs.openluat.com/air780epm/luatos/app/socket/netdrv/image/780epm-netdrv3.png)


