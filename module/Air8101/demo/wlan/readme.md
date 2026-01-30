## 功能模块介绍

1、main.lua：主程序入口；

2、wifi_sta.lua：wifi_sta功能

3、wifi_scan.lua：wifi扫描

4、ap_config_net.lua：wifi_ap配网

## 演示功能概述

- STA:展示air8101：使用wifi 路由器上网能力
- ap_config_net：AP方式配网，即通过链接air8101 wifi 的AP(热点),打开网页配置需要连接的wifi名称和密码
- wifi_scan：扫描周围2.4Gwifi的名称和mac

## 演示硬件环境

### Air8101 核心板

![](https://docs.openluat.com/air8101/luatos/app/multinetwork/4G/image/LzuBbS3NxoVu34x4dj7c3d04nDb.jpg)
Air8101 核心板一块 + TYPE-C USB 数据线一根

## 演示软件环境

1、Luatools下载调试工具

2、内核固件：[Air8101 V1006 版本固件](https://docs.openluat.com/air8101/luatos/firmware/)如有更新可以使用最新固件。

## 演示核心步骤

1、搭建好硬件环境，按接线图连接硬件,

2、测试wifi功能时按需修改WiFi配置：
ap_config_net.lua中的wlan.createAP("test", "HZ88888888"),修改生成wifi热点的名称和密码.
wifi_sta.lua中的wlan.connect("test", "HZ88888888")修改需要连接的wifi的名称和密码

3、在main.lua中按照自己的网卡需求启用对应的Lua文件

- 如果需要测试wifi_sta功能，打开require "wifi_sta"，其余注释掉

- 如果需要测试wifi扫描功能，打开require "wifi_scan"，其余注释掉

- 如果需要测试wifi_ap配网功能，打开require "ap_config_net"，其余注释掉

4、Luatools烧录内核固件和修改后的demo脚本代码

wifi_sta：模块连接wifi成功,http请求测试成功
![](https://docs.openluat.com/air8101/luatos/app/image/8101-wlan4.png)

wifi_scan：模块扫描附近2.4Gwifi并打印扫描结果
![](https://docs.openluat.com/air8101/luatos/app/image/8101-wlan3.png)

ap_config_net：电脑连接模块的ap热点,浏览器打开192.168.4.1通过网页配置模块连接对应wifi
![](https://docs.openluat.com/air8101/luatos/app/image/8101-wlan1.png)
