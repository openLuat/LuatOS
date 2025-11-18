## 功能模块介绍

1、main.lua：主程序入口；

2、wifi_ap.lua：wifi_ap功能

3、wifi_sta.lua：wifi_sta功能

4、wifi_scan.lua：wifi扫描

5、ap_config_net.lua：wifi_ap配网

6、check_wifi.lua：wifi固件升级

## 演示功能概述

- AP：展示4G网络经过air8000 转为ap 热点，给其他wifi 设备提供上网能力
- STA:展示air8000：使用wifi 路由器上网能力
- ap_config_net：AP方式配网，即通过链接Air8000 wifi 的AP(热点),打开网页配置需要连接的wifi名称和密码
- wifi_scan：扫描周围2.4Gwifi的名称和mac

## 演示硬件环境

![](https://docs.openluat.com/air8000/luatos/app/network_routing/4g_out_ethernet_in_wifi_in/image/ApM9b4W2xoqEuexEyQ6clEOTnjh.png)

1、Air8000开发板一块+可上网的sim卡一张+4g天线一根+wifi天线一根：

- sim卡插入开发板的sim卡槽

- 天线装到开发板上

2、TYPE-C USB数据线一根 Air8000开发板和数据线的硬件接线方式为：

- TYPE-C USB数据线直接插到核心板的TYPE-C USB座子，另外一端连接电脑USB口；

## 演示软件环境

1、Luatools下载调试工具

2、[Air8000 V2016版本固件](https://docs.openluat.com/air8000/luatos/firmware/)（理论上，最新发布的固件都可以）


## 演示核心步骤

1、搭建好硬件环境，按接线图连接硬件,

2、测试wifi功能时按需修改WiFi配置：
ap_config_net.lua和wifi_ap.lua中的wlan.createAP("test", "HZ88888888"),修改生成wifi热点的名称和密码.
wifi_sta.lua中的wlan.connect("test", "HZ88888888")修改需要连接的wifi的名称和密码

3、在main.lua中按照自己的网卡需求启用对应的Lua文件

- 如果需要测试wifi_ap功能，打开require "wifi_ap"，其余注释掉

- 如果需要测试wifi_sta功能，打开require "wifi_sta"，其余注释掉

- 如果需要测试wifi扫描功能，打开require "wifi_scan"，其余注释掉

- 如果需要测试wifi_ap配网功能，打开require "ap_config_net"，其余注释掉

- 如果需要升级wifi固件，打开require "check_wifi"，其余注释掉

4、Luatools烧录内核固件和修改后的demo脚本代码

wifi_ap：电脑连接模块的ap热点,可以ping通模块
![](https://docs.openluat.com/air8000/luatos/app/wifi/ap/image/wlan_ap.png)

wifi_sta：模块连接wifi成功,http请求测试成功
![](https://docs.openluat.com/air8000/luatos/app/wifi/ap/image/wlan-sta.png)

wifi_scan：模块扫描附近2.4Gwifi并打印扫描结果
![](https://docs.openluat.com/air8000/luatos/app/wifi/ap/image/wlan-scan.png)

ap_config_net：电脑连接模块的ap热点,浏览器打开192.168.4.1通过网页配置模块连接对应wifi
![](https://docs.openluat.com/air8000/luatos/app/wifi/ap/image/wlan-apcfgnet.png)

check_wifi：[详情查看升级WiFi文档](https://docs.openluat.com/air8000/luatos/app/updatwifi/update/)