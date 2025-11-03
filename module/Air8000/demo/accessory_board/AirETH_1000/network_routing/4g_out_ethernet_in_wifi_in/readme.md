## 功能模块介绍

1、main.lua：主程序入口；

2、netif_app: 网络管理模块,开启多网融合功能，4G提供网络供以太网和wifi设备上网；

## 演示功能概述

1、开启多网融合模式，4G连接外部网络，生成WiFi热点为WiFi终端设备提供接入，支持以太网lan模式为其他以太网设备提供接入

2、​网络监控​，每5秒进行HTTPS连接测试，实时监测4G网络的连接状态

## 演示硬件环境

1、Air8000核心板一块+可上网的sim卡一张+网线一根+AirETH_1000板子一个;

![](https://docs.openLuat.com/cdn/image/AirETH_1000.jpg)

2、TYPE-C USB数据线一根 + 杜邦线若干;

* Air8000核心板通过TYPE-C USB口供电；（外部供电/USB供电 拨动开关 拨到 USB供电一端）

* TYPE-C USB数据线直接插到核心板的TYPE-C USB座子，另外一端连接电脑USB口；

* AirETH_1000板子网口与电脑网口通过网线连接；

3、Air8000核心板和AirETH_1000配件板的硬件接线方式为：

| Air8000核心板 | AirETH_1000配件板 |
| ---------- | -------------- |
| vdd        | 3.3v           |
| gnd        | gnd            |
| spi1_sclk  | SCK            |
| spi1_cs    | CSS            |
| spi1_miso  | SDO            |
| spi1_mosi  | SDI            |
| gpio21     | INT            |

## 演示软件环境

1、Luatools下载调试工具

2、[Air8000 V2011版本固件](https://docs.openluat.com/air8000/luatos/firmware/)（理论上，2025年7月26日之后发布的固件都可以）

## 演示核心步骤

1、搭建好硬件环境，按接线图连接硬件,

2、按需修改WiFi热点配置（在netif_app.lua中）：
ssid = "AP热点名称"
password = "AP热点密码"

4、烧录内核固件和本项目的Lua脚本：main.lua：主程序入口，netif_app.lua：网络管理模块

5、启动设备，观察日志输出：

```lua
[INFO] exnetif setproxy success
[INFO] http执行结果 200 ... 
```

6、其他设备通过wifi或以太网接入Air8000，其他设备都能正常上网，则表示验证成功。
