
## 演示功能概述

本demo使用Air780EGH核心板，演示netdrv库操作以太网模块CH390H模块的使用方法，分别实现以下通信功能测试及代码实现：

1、WAN通信测试为通过以太网模块CH390H连接路由器LAN口，在路由器DHCP获取IP地址后可以访问互联网

2、LAN通信测试为4G网络转以太网功能，通过网线将以太网模块CH390H与电脑以太网口连接，电脑可以4G网络访问互联网

## 演示硬件环境

1、Air780EGH核心板一块，TYPE-C USB数据线一根

2、CH390H以太网模块一个，杜邦线若干

3、Air780EHM核心板与CH390H模块硬件接线：

核心板                   CH390模块
GND              <--->  GND
3.3V             <--->  3.3V
(PIN86)SPI0_CLK  <--->  SCK
(PIN85)SPIO_MOSI <--->  SDI
(PIN84)SPI0_MISO <--->  SDO
(PIN83)SPI0_CS   <--->  CSS

4、Air780EGH核心板通过TYPE-C USB口供电；（核心板USB旁边的开关拨到on一端）

## 演示软件环境

1、Luatools下载调试工具

2、[Air780EGH 最新版本固件](https://docs.openluat.com/air780egh/luatos/firmware/version/)

## 演示核心步骤

1、搭建好硬件环境

2、通过Luatools将demo与固件烧录到核心板中

3、功能测试结果描述如下，具体详见相关文档 [Air780EGH 以太网](https://docs.openluat.com/air780egh/luatos/app/driver/eth/)

WAN功能通信测试：

一台已经拨号上网并可以访问互联网资源的路由器，将Air780EGH核心板连接的CH390H通过网线与路由器的LAN口相连，此时如果CH390H运行正常，可以在luatools打印中看到如下打印信息：（注意以下分配的参数与路由器设置有关）

> D/DHCP get ip ready  
> D/ulwip 动态IP：192.168.100.42  
> D/ulwip 子网掩码：255.255.255.0  
> D/ulwip 网关：192.168.100.1  

CH309H 通信正常后，demo会定时向指定网址做http get请求，请求成功如下打印所示：

> dns run 674:httpbin.air32.cn state 0 id 1 ipv6 0 use dns server0, try 0  
> D/ulwip IP_READY 192.168.100.42  
> dns run 674:httpbin.air32.cn state 0 id 1 ipv6 0 use dns server0, try 1  
> dns run 691:dns all done,now stop  
> D/net connect 49.232.89.122:80 TCP  
> I/user http  200   table 0C7F81F0  

LAN功能通信测试：

资费正常的SIM卡插入Air780EGH核心板，将Air780EGH核心板连接的CH390H通过网线与PC电脑的网口相连，打开PC电脑的系统设置，在"网络和Internet"->"以太网"选项页面，等待以太网显示已连接，PC电脑若通过wifi连接此时可以断开wifi，通过以太网连接也可以正常访问互联网资源，可以在luatools打印中看到如下打印信息：

> D/net network_read 4  
> D/net 使用网关作为默认DNS服务器 192.168.4.1  
> I/user ipv4  192.168.4.1  255.255.255.0  192.168.4.1  
> D/socket connect to 255.255.255.255,0  
> D/net connect 255.255.255.255:0 UDP  
> I/user dnsproxy  4  1  
> I/user dnsproxy  开启DNS代理  
> D/socket connect to 255.255.255.255,0  
> D/net connect 255.255.255.255:0 UDP  
> D/socket connect to 223.5.5.5,53  
> D/netdrv NAPT is enabled gw 1  

CH309H 通信正常后，demo会定时向指定网址做http get请求，请求成功如下打印所示：(注意此时使用的是sim卡4G流量，注意流量消耗)

> dns run 674:httpbin.air32.cn state 0 id 1 ipv6 0 use dns server0, try 0  
> D/ulwip IP_READY 192.168.100.42  
> dns run 674:httpbin.air32.cn state 0 id 1 ipv6 0 use dns server0, try 1  
> dns run 691:dns all done,now stop  
> D/net connect 49.232.89.122:80 TCP  
> I/user http  200   table 0C7F81F0  
