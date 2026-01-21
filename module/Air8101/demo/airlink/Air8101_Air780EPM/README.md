## 功能模块介绍

1、main.lua：主程序入口；

2、Air780EPM_slave: Air780EPM中运行的程序,作为4G数据出口,airlink从机

Air8101_master: Air8101: Air8101中运行的程序,airlink主机,可以使用4G或wifi网络

## 演示功能概述

本文件中代码用于测试Air8101+780EPM的多网融合(Air8101可以使用wifi和4G网络联网)和数据交互功能
详细操作说明可参考：[4G - luatos@air8101 - 合宙模组资料中心](https://docs.openluat.com/air8101/luatos/app/network_routing/4G/)

## 演示硬件环境

参考：[硬件环境清单](https://docs.openluat.com/air8101/luatos/common/hwenv/)，准备以及组装好基本硬件环境。

### 2.1 Air8101 核心板

![](https://docs.openluat.com/air8101/luatos/app/multinetwork/4G/image/LzuBbS3NxoVu34x4dj7c3d04nDb.jpg)
Air8101 核心板一块 + TYPE-C USB 数据线一根

### 2.2 Air780EPM 开发板

![](https://docs.openluat.com/air8101/luatos/app/multinetwork/4G/image/Q5o4bXvOsoGMe7xQZK2cZ1CFnxf.png)
Air780EPM 开发板一块 +TYPE-C USB 数据线一根 +可上网的sim卡一张 +4g天线一根：

- sim卡插入开发板的sim卡槽

- 天线装到开发板上

### 2.3 接线方式

![](https://docs.openluat.com/air8101/image/airlink-jx.png)

![](https://docs.openluat.com/air8101/luatos/app/network_routing/4G/image/F5C7bdIu8o6ORKx7gnIcSEkGncD.jpg)

![](https://docs.openluat.com/air8101/luatos/app/network_routing/4G/image/VGvhbG3Fhozmrmx8Q2ycotI6nHh.jpg)

## 演示软件环境

1、Luatools下载调试工具

2、内核固件：使用大于等于2002版本号的[内核固件](https://docs.openluat.com/air8101/luatos/firmware/)，开发验证本demo时，还没有正式版本的固件，所以使用[Air8101 临时固件，仅用于验证](http://sh02.air32.cn:43001/air8101v2/LuatOS-SoC_V2001_Air8101_101_20260115_110913.soc)。

3、内核固件：使用大于等于2022版本号的[内核固件](https://docs.openluat.com/air780epm/luatos/firmware/version/)，开发验证本demo时，还没有正式版本的固件，所以使用[Air780EPM 临时固件，仅用于验证](http://sh02.air32.cn:43001/air780epm/LuatOS-SoC_V2021_Air780EPM_1_20260115_155415.soc)。

## 演示核心步骤

1、搭建好硬件环境，按接线图连接硬件,

2、按需修改WiFi配置（在Air8101_slave文件夹network_airlink.lua文件中）：
ssid = "wifi名称"
password = "wifi密码"

4、烧录内核固件和本项目的Lua脚本：
Air780EPM烧录Air780EPM_master文件夹下的 main.lua：主程序入口，network_airlink.lua：airlink多网融合模块
Air8101烧录Air8101_slave文件夹下的 main.lua：主程序入口，network_airlink.lua：airlink多网融合模块

5、启动设备，观察日志输出：
下图为Air780EPM日志输出截图。
![](https://docs.openluat.com/air8101/luatos/app/network_routing/4G/image/image-20250604182632243.png)
下图为Air8101日志输出截图。
![](https://docs.openluat.com/air8101/luatos/app/network_routing/4G/image/image-20250604182828467.png)