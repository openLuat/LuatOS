## 功能模块介绍

1、main.lua：主程序入口；

2、netdrv_device.lua：网卡驱动设备，可以配置使用netdrv文件夹内的四种网卡(单4g网卡，单wifi网卡，单spi以太网卡，多网卡)中的任何一种网卡；

3、lbsloc2_app.lua：合宙lbsloc2“单基站”定位功能模块； 

## 演示功能概述

使用Air780EPM开发板测试lbsloc2功能：

1、lbsloc2“单基站”定位演示。

2、netdrv_device：配置连接外网使用的网卡，目前支持以下四种选择（四选一）

(1) netdrv_4g：4G网卡

(2) netdrv_eth_spi：通过SPI外挂CH390H芯片的以太网卡

(3) netdrv_multiple：支持以上三种网卡，可以配置三种网卡的优先级

本功能为免费服务，由于单基站定位技术本身的原因，无法提供相对精准的定位服务。

如对定位精度要求较高，可以参考airlbs的demo，选择收费的airlbs定位服务，缴费地址[合宙云平台](https://iot.openluat.com/finance/order)。

## 演示硬件环境

* ![img](https://docs.openluat.com/air780epm/luatos/app/driver/eth/image/RFSvb75NRoEWqYxfCRVcVrOKnsf.jpg)

  1、Air780EPM V1.3版本开发板一块+可上网的sim卡一张+4g天线一根+网线一根：

  - sim卡插入开发板的sim卡槽
  - 天线装到开发板上
  - 网线一端插入开发板网口，另外一端连接可以上外网的路由器网口

  2、TYPE-C USB数据线一根 + USB转串口数据线一根，Air780EPM V1.3版本开发板和数据线的硬件接线方式为：

  - Air780EPM V1.3版本开发板通过TYPE-C USB口供电；（外部供电/USB供电 拨动开关 拨到 USB供电一端）
  - TYPE-C USB数据线直接插到核心板的TYPE-C USB座子，另外一端连接电脑USB口；
  - USB转串口数据线，一般来说，白线连接开发板的UART1_TX，绿线连接开发板的UART1_RX，黑线连接核心板的GND，另外一端连接电脑USB口；

## 演示软件环境

1、Luatools下载调试工具

2、[Air780EPM V2012版本固件](https://gitee.com/link?target=https%3A%2F%2Fdocs.openluat.com%2Fair780epm%2Fluatos%2Ffirmware%2Fversion%2F)（理论上，2025年8月10日之后发布的固件都可以）

## 演示核心步骤

1、搭建好硬件环境

2、demo脚本代码netdrv_device.lua中，按照自己的网卡需求启用对应的Lua文件

- 如果需要单4G网卡，打开require "netdrv_4g"，其余注释掉
- 如果需要以太网卡，打开require "netdrv_eth_spi"，其余注释掉
- 如果需要多网卡，打开require "netdrv_multiple"，其余注释掉；同时netdrv_multiple.lua中的ssid = "茶室-降功耗,找合宙!", password = "Air123456", 修改为自己测试时wifi热点的名称和密码；注意：仅支持2.4G的wifi，不支持5G的wifi

3、烧录内核固件和lbsloc2相关demo成功后，自动开机运行运行

4、可以看到代码运行结果如下，不管是在选择什么网卡场景下，基本都是如下情况：

以下是默认使用4G网卡下使用lbsloc2“单基站”应用场景的定位演示的日志

日志中如果出现以下类似打印则说明定位成功：

lbsLoc2 031.1346219 121.5382010 {}

```
[2025-08-18 15:50:04.995][000000006.372] D/user.lbsLoc2 free.bs.air32.cn 12411

[2025-08-18 15:50:05.001][000000006.372] D/socket connect to free.bs.air32.cn,12411

[2025-08-18 15:50:05.005][000000006.373] dns_run 674:free.bs.air32.cn state 0 id 1 ipv6 0 use dns server2, try 0

[2025-08-18 15:50:05.011][000000006.413] D/mobile TIME_SYNC 0

[2025-08-18 15:50:05.016][000000006.417] dns_run 691:dns all done ,now stop

[2025-08-18 15:50:05.154][000000006.582] D/user.lbsLoc2 rx 0030114326912151830201

[2025-08-18 15:50:05.166][000000006.585] I/user.lbsLoc2 031.1346219 121.5382010 {}

```
