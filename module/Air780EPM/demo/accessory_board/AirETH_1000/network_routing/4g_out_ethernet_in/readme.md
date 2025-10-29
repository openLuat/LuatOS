## 功能模块介绍

1、main.lua：主程序入口；

2、netif_app: 网络管理模块,开启多网融合功能，4G提供网络供以太网设备上网；

## 演示功能概述

1、开启多网融合模式，4G连接外部网络，以太网lan模式为其他以太网设备提供接入

2、​网络监控​，每5秒进行HTTPS连接测试，实时监测4G网络的连接状态

## 演示硬件环境

![](https://docs.openLuat.com/cdn/image/780EPM_AirETH1000.jpg)

1、Air780EPM 核心板一块+可上网的sim卡一张+网线一根：

- sim卡插入核心板的sim卡槽

- 网线一端插入核心板外接的AirETH_1000小板上，另外一端连接需接入以太网的设备

2、TYPE-C USB数据线一根 + 网线一根，Air780EPM核心板和数据线的硬件接线方式为：

- Air780EPM 本核心板通过TYPE-C USB口供电；（外部供电/USB供电 拨动开关 拨到 USB供电一端）

- TYPE-C USB数据线直接插到核心板的TYPE-C USB座子，另外一端连接电脑USB口；

- 核心板与AirETH_1000的接线方式如下：
  
  | Air780EPM核心板 | AirETH_1000配件板 |
  | ------------ | -------------- |
  | vdd          | 3.3v           |
  | gnd          | gnd            |
  | spi0_sclk    | SCK            |
  | spi0_cs      | CSS            |
  | spi0_miso    | SDO            |
  | spi0_mosi    | SDI            |
  | gpio21       | INT            |

## 演示软件环境

1、Luatools下载调试工具

2、[Air780EPM V2014版本固件](https://docs.openluat.com/air780epm/luatos/firmware/version/)（理论上，2025年8月10日之后发布的固件都可以）

## 演示核心步骤

1、搭建好硬件环境，按接线图连接硬件,

2、烧录内核固件和本项目的Lua脚本：main.lua：主程序入口，netif_app.lua：网络管理模块

3、启动设备，观察日志输出：

```lua
[INFO] exnetif setproxy success
[INFO] http执行结果 200 ... 
```

4、其他设备通过以太网接入780EPM，其他设备都能正常上网，则表示验证成功。
