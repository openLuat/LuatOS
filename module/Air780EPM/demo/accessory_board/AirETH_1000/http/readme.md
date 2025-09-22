## 功能模块介绍：

1、main.lua：主程序入口；

2、netdrv_device.lua：加载网络驱动设备功能模块；

3、http_lua：加载http应用模块；

## 演示功能概述

1、以太网给模组供网，通过连接http测试连通。

## 演示硬件环境

1、Air780EPM核心板一块+可上网的sim卡一张+网线一根+AirETH_1000板子一个;

[](https://docs.openLuat.com/cdn/image/780EPM_AirETH1000.jpg)

<img title="" src="https://docs.openLuat.com/cdn/image/780EPM_AirETH1000.jpg" alt="lan" style="zoom:25%;">

2、TYPE-C USB数据线一根 + 杜邦线若干;

* Air780EPM核心板通过TYPE-C USB口供电；（外部供电/USB供电 拨动开关 拨到 USB供电一端）

* TYPE-C USB数据线直接插到核心板的TYPE-C USB座子，另外一端连接电脑USB口；

* AirETH_1000板子网口与电脑网口通过网线连接；

3、Air780EPM核心板和AirETH_1000配件板的硬件接线方式为：

| Air780EPM核心板 | AirETH_1000配件板 |
| ------------ | -------------- |
| 3.3V         | 3.3v           |
| gnd          | gnd            |
| spi0_sclk    | SCK            |
| spi0_cs      | CSS            |
| spi0_miso    | SDO            |
| spi0_mosi    | SDI            |
| gpio21       | INT            |

演示软件环境
------

1、Luatools下载调试工具

2、[Air780EPM V2014版本固件](https://docs.openluat.com/air780EPM/luatos/firmware/)（理论上，2025年9月12日之后发布的固件都可以） 

## 演示核心步骤

1、搭建好硬件环境，按接线图连接硬件。

2、烧录内核固件和本项目的Lua脚本：main.lua：主程序入口(需要在main.lua文件中打开require"netdrv_device"和require"http_app")

3、启动设备，观察日志输出：

出现类似如下打印，就表示成功。

```
[2025-09-18 11:31:29.931][000000003.367] I/user.netdrv_eth_spi.ip_ready_func IP_READY 192.168.0.52 255.255.255.0 192.168.0.1 nil

[2025-09-18 11:31:29.934][000000003.368] I/user.http_app_task_func recv IP_READY 4 

[2025-09-18 11:31:29.938][000000003.372] dns_run 676:www.air32.cn state 0 id 1 ipv6 0 use dns server0, try

[2025-09-18 11:31:29.942][000000003.372] D/net adatper 4 dns server 192.168.0.1

[2025-09-18 11:31:29.944][000000003.372] D/net dns udp sendto 192.168.0.1:53 from 192.168.0.52

[2025-09-18 11:31:29.948][000000003.384] dns_run 693:dns all done ,now stop

[2025-09-18 11:31:29.950][000000003.385] D/net connect 49.232.89.122:443 TCP

[2025-09-18 11:31:30.641][000000004.123] I/user.http_app_get1 success 200 {"Transfer-Encoding":"chunked","Date":"Thu, 18 Sep 2025 03:31:33 GMT","Connection":"keep-alive","Server":"openresty\/1.27.1.2","Content-Type":"text\/html"} 2416

```
