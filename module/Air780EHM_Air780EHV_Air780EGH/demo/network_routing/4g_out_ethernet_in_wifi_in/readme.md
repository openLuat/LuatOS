## 功能模块介绍

1、main.lua：主程序入口；

2、netif_app: 网络管理模块,开启多网融合功能，4G提供网络供以太网设备上网；

## 演示功能概述

1、开启多网融合模式，4G连接外部网络，以太网lan模式为其他以太网设备提供接入

2、​网络监控​，每5秒进行HTTPS连接测试，实时监测4G网络的连接状态


## 演示硬件环境

![](https://docs.openluat.com/air780ehv/luatos/common/hwenv/image/Air780EHV.png)

1、Air780EXX核心板一块

2、TYPE-C USB数据线一根

3、USB转串口数据线一根

4、Air780EXX核心板和数据线的硬件接线方式为

- Air780EXX核心板通过TYPE-C USB口供电；

- 如果测试发现软件频繁重启，重启原因值为：poweron reason 0，可能是供电不足，此时再通过直流稳压电源对核心板的vbat管脚进行4V供电，或者5V管脚进行5V供电；

- TYPE-C USB数据线直接插到核心板的TYPE-C USB座子，另外一端连接电脑USB口；

- USB转串口数据线，一般来说，白线连接核心板的18/U1TXD，绿线连接核心板的17/U1RXD，黑线连接核心板的gnd，另外一端连接电脑USB口；

5、可选AirETH_1000配件板一块，Air8101核心板和AirETH_1000配件板的硬件接线方式为:

| Air780EXX核心板  |  AirETH_1000配件板 |
| --------------- | ----------------- |
| 3V3             | 3.3v              |
| gnd             | gnd               |
| 86/SPI0CLK      | SCK               |
| 83/SPI0CS       | CSS               |
| 84/SPI0MISO     | SDO               |
| 85/SPI0MOSI     | SDI               |
| 107/GPIO21      | INT               |


## 演示软件环境

1、Luatools下载调试工具

2、[Air780EHM V2012版本固件](https://docs.openluat.com/air780epm/luatos/firmware/version/#air780ehmluatos)、[Air780EHV V2012版本固件](https://docs.openluat.com/air780ehv/luatos/firmware/version/)、[Air780EHG V2012版本固件](https://docs.openluat.com/air780egh/luatos/firmware/version/)（理论上，2025年7月26日之后发布的固件都可以）


## 演示核心步骤

1、搭建好硬件环境，按接线图连接硬件,

2、按需修改WiFi热点配置（在netif_app.lua中）：
ssid = "AP热点名称"
password = "AP热点密码"

4、烧录内核固件和本项目的Lua脚本：main.lua：主程序入口，netif_app.lua：网络管理模块

5、启动设备，观察日志输出：

``` lua
[INFO] exnetif setproxy success
[INFO] http执行结果 200 ... 
```

6、其他设备通过以太网接入780EXX，其他设备都能正常上网，则表示验证成功。
