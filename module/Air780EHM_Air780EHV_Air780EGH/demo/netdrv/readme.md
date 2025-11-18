## 功能模块介绍

1、main.lua：主程序入口；

2、netdrv_eth_wan.lua：以太网wan

3、netdrv_eth_lan.lua：以太网lan

4、netdrv_4g_multiple.lua：4G连接外部网络，以太网lan模式为其他以太网设备提供接入 

5、netdrv_eth_multiple：双以太网口，以太网WAN->以太网LAN

## 演示功能概述

1、演示 netdrv核心库+dnsproxy扩展库+dhcpsrv扩展库 开启以太网或双以太网口,4G,以太网多网融合功能.

## 演示硬件环境

![](image/780EHM双网口.png)

2.2.1 Air780EHM/Air780EHV/Air780EGH 核心板一块 + 可上网的 sim 卡一张 +4g 天线一根 + 网线两根：

- sim 卡插入开发板的 sim 卡槽
- 天线装到开发板上
- 网线一端插入AirETH_1000配件板网口，另外一端可以连接电脑

2.2.2 TYPE-C USB 数据线一根 + USB 转串口数据线一根，Air780EHM/Air780EHV/Air780EGH 核心板和数据线的硬件接线方式为：

- Air780EHM/Air780EHV/Air780EGH 核心板通过 TYPE-C USB 口供电；（外部供电/USB 供电 拨动开关 拨到 USB 供电一端）
- TYPE-C USB 数据线直接插到核心板的 TYPE-C USB 座子，另外一端连接电脑 USB 口；

2.2.3 必选 AirETH_1000配件板两块，Air780EHM/Air780EHV/Air780EGH 核心板和 AirETH_1000配件板的硬件接线方式为:


这块配件板以太网接口接路由器

<table>
<tr>
<td>Air780EHM/Air780EHV/Air780EGH核心板<br/></td><td>AirETH_1000配件板<br/></td></tr>
<tr>
<td>3V3<br/></td><td>3.3v<br/></td></tr>
<tr>
<td>GND<br/></td><td>GND<br/></td></tr>
<tr>
<td>86/SPI0CLK<br/></td><td>SCK<br/></td></tr>
<tr>
<td>83/SPI0CS<br/></td><td>CSS<br/></td></tr>
<tr>
<td>84/SPI0MISO<br/></td><td>SDO<br/></td></tr>
<tr>
<td>85/SPI0MOSI<br/></td><td>SDI<br/></td></tr>
<tr>
<td>107/GPIO21<br/></td><td>INT<br/></td></tr>
</table>


这块配件板以太网接口接电脑

| Air780EHM/Air780EHV/Air780EGH核心板 |  AirETH_1000配件板 |
| --------------- | ----------------- |
| 24/VDD_EXT      | 3.3v              |
| gnd             | gnd               |
| UART3_TX        | SCK               |
| UART2_RX        | CSS               |
| UART3_RX        | SDO               |
| UART2_TX        | SDI               |
| nil             | INT               |


## 演示软件环境

1、Luatools下载调试工具

3、内核固件：[Air780EXX V2018 版本固件](https://docs.openluat.com/air780egh/luatos/firmware/version/)；如有更新可以使用最新固件。


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


