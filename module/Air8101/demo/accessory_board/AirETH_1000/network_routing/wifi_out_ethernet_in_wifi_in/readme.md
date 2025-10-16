## 功能模块介绍

1、main.lua：主程序入口；

2、netif_app: 网络管理模块,开启多网融合功能，wifi提供网络供以太网和wifi设备上网；

## 演示功能概述

1、开启多网融合模式，WIFI连接外部网络，支持以太网lan模式为其他以太网设备提供接入,支持生成WiFi热点为WiFi终端设备提供接入

2、​网络监控​，每5秒进行HTTPS连接测试，实时监测WIFI网络的连接状态

## 演示硬件环境



![](https://docs.openLuat.com/cdn/image/8101_AirETH1000.jpg)

1、Air8101核心板

2、AirETH_1000配件板

3、公对母的杜邦线11根（连接核心板和配件板）

4、网线1根（一端接配件板，一端接路由器）

5、Air8101核心板和AirETH_1000配件板的硬件接线方式为:

- Air8101核心板通过TYPE-C USB口供电（核心板背面的功耗测试开关拨到OFF一端）；如果测试发现软件重启，并且日志中出现  poweron reason 0，表示供电不足，此时再通过直流稳压电源对核心板的VIN管脚进行5V供电；

| Air8101核心板 | AirETH_1000配件板                   |
| ---------- | -------------------------------- |
| 59/3V3     | 3.3v |
| gnd        | gnd                              |
| 28/DCLK    | SCK                              |
| 54/DISP    | CSS                              |
| 55/HSYN    | SDO                              |
| 57/DE      | SDI                              |
| 14/GPIO8   | INT                              |

## 演示软件环境

1、Luatools下载调试工具

2、[Air8101 V1005版本固件](https://docs.openluat.com/air8101/luatos/firmware/)（理论上最新版本固件也可以，如果使用最新版本的固件不可以，可以烧录V1005固件对比验证）

## 演示核心步骤

1、搭建好硬件环境，按接线图连接硬件,

2、按需修改WiFi配置（在netif_app.lua中）：
ssid = "WIFI名称"
password = "WiFi密码"

3、如果使用spi方式外挂网卡，打开SPI方式外挂网卡的代码，注释掉RMII方式外挂网卡的代码

4、内核固件和本项目的Lua脚本：main.lua：主程序入口，netif_app.lua：网络管理模块

5、启动设备，观察日志输出：

```lua
[INFO] exnetif setproxy success
[INFO] http执行结果 200 ... 
```

6、其他设备通过wifi或以太网接入Air8101，其他设备都能正常上网，则表示验证成功。
