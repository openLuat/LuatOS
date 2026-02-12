## 功能模块介绍

1、main.lua：主程序入口；

2、netif_app: 网络管理模块,开启多网融合功能，4G提供网络供以太网设备上网；

## 演示功能概述

1、开启多网融合模式，4G连接外部网络，以太网lan模式为其他以太网设备提供接入

2、​网络监控​，每5秒进行HTTPS连接测试，实时监测4G网络的连接状态

## 演示硬件环境

![](https://docs.openluat.com/air780epm/luatos/app/driver/eth/image/RFSvb75NRoEWqYxfCRVcVrOKnsf.jpg)

1、Air780EPM V1.3版本开发板一块+可上网的sim卡一张+4g天线一根+网线一根：

- sim卡插入开发板的sim卡槽

- 天线装到开发板上

- 网线一端插入开发板网口，另外一端连接可以上外网的路由器网口

2、TYPE-C USB数据线一根 Air780EPM V1.3版本开发板和数据线的硬件接线方式为：

- Air780EPM V1.3版本开发板通过TYPE-C USB口供电；（外部供电/USB供电 拨动开关 拨到 USB供电一端）

- TYPE-C USB数据线直接插到核心板的TYPE-C USB座子，另外一端连接电脑USB口；


## 演示软件环境

1、Luatools下载调试工具

2、[Air780EPM V2012版本固件](https://docs.openluat.com/air780epm/luatos/firmware/version/)（理论上，2025年8月10日之后发布的固件都可以）

## 演示核心步骤

1、搭建好硬件环境，按接线图连接硬件,

2、烧录内核固件和本项目的Lua脚本：main.lua：主程序入口，netif_app.lua：网络管理模块

3、启动设备，观察日志输出：

``` lua
[INFO] exnetif setproxy success
[INFO] http执行结果 200 ... 
```

4、其他设备通过以太网接入780EPM，其他设备都能正常上网，则表示验证成功。
