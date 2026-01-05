## 功能模块介绍

1、main.lua：主程序入口；

2、netdrv_eth_wan.lua：以太网wan

3、netdrv_eth_lan.lua：以太网lan

4、netdrv_eth_multiple.lua：以太网连接外部网络,生成WiFi热点为WiFi终端设备提供接入 

5、netdrv_wifi_multiple.lua：WIFI连接外部网络,支持以太网lan模式为其他以太网设备提供接入,支持生成WiFi热点为WiFi终端设备提供接入

## 演示功能概述

1、演示 netdrv核心库+dnsproxy扩展库+dhcpsrv扩展库 开启以太网或wifi单网卡,4G,wifi,以太网多网融合功能.

## 演示硬件环境

![](https://docs.openluat.com/air8101/product/file/AirPHY_1000/hw_connection.jpg)

![](https://docs.openluat.com/air8101/product/file/AirPHY_1000/hw_connection1.jpg)

1、Air8101核心板

2、AirPHY_1000配件板

3、公对母的杜邦线11根（连接核心板和配件板）

4、网线1根（一端接配件板，一端接路由器）

5、Air8101核心板和AirPHY_1000配件板的硬件接线方式为

- Air8101核心板通过TYPE-C USB口供电（核心板背面的功耗测试开关拨到OFF一端）；如果测试发现软件重启，并且日志中出现  poweron reason 0，表示供电不足，此时再通过直流稳压电源对核心板的VIN管脚进行5V供电；

| Air8101核心板 | AirPHY_1000配件板  |
| ------------ | ------------------ |
|    59/3V3    |         3.3v       |
|     gnd      |         gnd        |
|     5/D2     |         RX1        |
|    72/D1     |         RX0        |
|    71/D3     |         CRS        |
|     4/D0     |         MDIO       |
|     6/D4     |         TX0        |
|    74/PCK    |         MDC        |
|    70/D5     |         TX1        |
|     7/D6     |         TXEN       |
|     不接     |          NC        |
|    69/D7     |         CLK        |

可选AirETH_1000配件板一块，Air8101核心板和AirETH_1000配件板的硬件接线方式为:

| Air8101核心板   |  AirETH_1000配件板 |
| --------------- | ----------------- |
| 59/3V3          | 3.3v              |
| gnd             | gnd               |
| 28/DCLK         | SCK               |
| 54/DISP         | CSS               |
| 55/HSYN         | SDO               |
| 57/DE           | SDI               |
| 14/GPIO8        | INT               |


2、网线接线说明：

- netdrv_eth_wan 模块以太网口接路由器LAN口或交换机

- netdrv_eth_lan 模块以太网口接电脑或需要上网的设备

- netdrv_wifi_multiple 模块以太网口接电脑或需要上网的设备

- netdrv_eth_multiple 模块以太网口接路由器LAN口或交换机

3、TYPE-C USB数据线一根 Air8101核心板和数据线的硬件接线方式为：

- TYPE-C USB数据线直接插到核心板的TYPE-C USB座子，另外一端连接电脑USB口；

## 演示软件环境

1、Luatools下载调试工具

2、[Air8101 V1006版本固件](https://docs.openluat.com/air8101/luatos/firmware/)（理论上，最新发布的固件都可以）


## 演示核心步骤

1、搭建好硬件环境，按接线图连接硬件,

2、测试wifi功能时按需修改WiFi配置：
netdrv_eth_multiple中的wlan.createAP("test", "HZ88888888"),修改生成wifi热点的名称和密码.
netdrv_wifi_multiple中的wlan.connect("test", "HZ88888888")修改需要连接的wifi的名称和密码

3、在main.lua中按照自己的网卡需求启用对应的Lua文件

- 使用phy以太网扩展板时直接运行即可，使用eth以太网扩展板时需要将local is_RMII = true 修改为local is_RMII = false

- 如果需要开启以太网lan，打开require "netdrv_eth_lan"，其余注释掉

- 如果需要开启以太网wan，打开require "netdrv_eth_wan"，其余注释掉

- 如果需要开启以太网转wifi的多网融合，打开require "netdrv_eth_multiple.lua"，其余注释掉

- 如果需要开启wifi转以太网的多网融合，打开require "netdrv_wifi_multiple"，其余注释掉

4、Luatools烧录内核固件和修改后的demo脚本代码
netdrv_eth_lan：
模块以太网接口接其他设备，这里演示使用电脑连接，可以dhcp获取ip，可以ping通模块
![](https://docs.openluat.com/air8101/luatos/app/netdrv/image/8101-netdrv1.png)

netdrv_eth_wan：
模块以太网口接路由器，模块成功联网并http请求成功
![](https://docs.openluat.com/air8101/luatos/app/netdrv/image/8101-netdrv3.png)

netdrv_eth_multiple：
模块以太网口接路由器LAN口，并开启wifi_ap热点，这里使用电脑连接模块发出的热点，dhcp获取到ip，测试网络正常
![](https://docs.openluat.com/air8101/luatos/app/netdrv/image/8101-netdrv2.png)

netdrv_wifi_multiple：
模块连接路由器wifi，并开启以太网LAN口，这里使用电脑连接模块以太网接口，测试网络正常
![](https://docs.openluat.com/air8101/luatos/app/netdrv/image/8101-netdrv2.png)


