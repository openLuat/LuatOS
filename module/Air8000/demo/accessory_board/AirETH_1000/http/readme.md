## 功能模块介绍：

1、main.lua：主程序入口；

2、netdrv_device.lua：加载网络驱动设备功能模块；

3、http_app.lua：加载http应用功能模块；

## 演示功能概述

1、模组连接4G网络通过以太网口传输给其他设备供网 

## 演示硬件环境

1、Air8000核心板一块+可上网的sim卡一张+网线一根+AirETH_1000板子一个;

[](https://docs.openLuat.com/cdn/image/AirETH_1000.jpg)

![lan](E:\文档池\新建文件夹\luatos-doc-pool\docs\root\docs\air8000\luatos\app\image\lan.jpg)

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

演示软件环境
------

1、Luatools下载调试工具

2、[Air8000 V2014版本固件](https://docs.openluat.com/air8000/luatos/firmware/)（理论上，2025年9月12日之后发布的固件都可以） 

## 演示核心步骤

1、搭建好硬件环境，按接线图连接硬件。

2、烧录内核固件和本项目的Lua脚本：main.lua：主程序入口(需要在main.lua文件中打开require"netdrv_device"和require"http_app")

3、启动设备，观察日志输出：

出现类似如下打印，就表示成功。

```
[2025-09-17 14:35:59.774][000000005.877] D/ulwip IP_READY 4 192.168.3.99

[2025-09-17 14:35:59.777][000000005.878] I/user.netdrv_eth_spi.ip_ready_func IP_READY 192.168.3.99 255.255.255.0 
192.168.3.1 nil

[2025-09-17 14:35:59.783][000000005.879] I/user.http_app_task_func recv IP_READY 4 4

[2025-09-17 14:35:59.786][000000005.883] dns_run 676:www.air32.cn state 0 id 1 ipv6 0 use dns server0, try 0

[2025-09-17 14:35:59.789][000000005.883] D/net adatper 4 dns server 192.168.3.1

[2025-09-17 14:35:59.793][000000005.883] D/net dns udp sendto 192.168.3.1:53 from 192.168.3.99

[2025-09-17 14:35:59.799][000000005.891] dns_run 693:dns all done ,now stop

[2025-09-17 14:35:59.802][000000005.891] D/net connect 49.232.89.122:443 TCP

[2025-09-17 14:36:00.215][000000006.395] I/user.http_app_get1 success 200 {"Transfer-Encoding":"chunked","Date":"Wed, 17 Sep 2025 06:36:02 GMT","Connection":"keep-alive","Server":"openresty\/1.27.1.2","Content-Type":"text\/html"} 2416

[2025-09-17 14:36:00.226][000000006.396] dns_run 676:www.luatos.com state 0 id 2 ipv6 0 use dns server0, try 0


```
