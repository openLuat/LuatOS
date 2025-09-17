## 功能模块介绍：

1、main.lua：主程序入口；

2、netdrv_device.lua：加载网络驱动设备功能模块；

3、4g-eth-wifi.lua：模组通过4G提供网络供以太网和wifi设备上网；

4、wifi-eth-wifi: 模组通过WIFI提供网络供以太网和wifi设备上网；

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

[2025-09-17 14:35:54.732][000000000.369] SPI_HWInit 552:spi1 speed 25600000,25600000,12

[2025-09-17 14:35:54.746][000000000.370] I/user.netdrv_eth_spi spi open result 0

[2025-09-17 14:35:54.759][000000000.370] D/ch390h 注册CH390H设备 SPI id 1 cs 12 irq 255

[2025-09-17 14:35:54.771][000000000.371] D/netdrv.ch390x task started

[2025-09-17 14:35:54.781][000000000.371] D/ch390h ch390注册完成

[2025-09-17 14:35:54.790][000000000.383] W/user.http_app_task_func wait IP_READY 4 3

[2025-09-17 14:35:54.797][000000000.435] D/netdrv.ch390x 初始化MAC 701988D3008A

[2025-09-17 14:35:54.808][000000000.435] D/netdrv.ch390x luat_netif_init 执行完成 1

[2025-09-17 14:35:55.217][000000001.383] W/user.http_app_task_func wait IP_READY 4 4

[2025-09-17 14:35:55.929][000000002.067] D/mobile cid1, state0

[2025-09-17 14:35:55.943][000000002.068] D/mobile bearer act 0, result 0

[2025-09-17 14:35:55.956][000000002.068] D/mobile NETIF_LINK_ON -> IP_READY

[2025-09-17 14:35:55.962][000000002.069] W/user.http_app_task_func wait IP_READY 4 4

[2025-09-17 14:35:55.972][000000002.106] D/mobile TIME_SYNC 0

[2025-09-17 14:35:56.894][000000003.070] W/user.http_app_task_func wait IP_READY 4 4

[2025-09-17 14:35:57.902][000000004.071] W/user.http_app_task_func wait IP_READY 4 4

[2025-09-17 14:35:58.669][000000004.842] I/netdrv.ch390x link is up 1 12 100M

[2025-09-17 14:35:58.673][000000004.852] D/DHCP dhcp state 6 4852 0 0

[2025-09-17 14:35:58.678][000000004.852] D/DHCP dhcp discover 701988D3008A

[2025-09-17 14:35:58.682][000000004.853] I/ulwip adapter 4 dhcp payload len 308

[2025-09-17 14:35:58.903][000000005.072] W/user.http_app_task_func wait IP_READY 4 4

[2025-09-17 14:35:59.543][000000005.709] D/ulwip 收到DHCP数据包(len=286)

[2025-09-17 14:35:59.551][000000005.709] I/ulwip dhcp data not for us len=286 mac 3CAB72441DFC

[2025-09-17 14:35:59.684][000000005.851] D/DHCP dhcp state 7 5851 0 0

[2025-09-17 14:35:59.693][000000005.852] D/DHCP long time no offer, resend

[2025-09-17 14:35:59.702][000000005.852] I/ulwip adapter 4 dhcp payload len 308

[2025-09-17 14:35:59.707][000000005.863] D/ulwip 收到DHCP数据包(len=286)

[2025-09-17 14:35:59.710][000000005.863] D/DHCP dhcp state 7 5863 0 0

[2025-09-17 14:35:59.716][000000005.863] D/DHCP find ip 6303a8c0 192.168.3.99

[2025-09-17 14:35:59.719][000000005.863] D/DHCP result 2

[2025-09-17 14:35:59.723][000000005.863] D/DHCP select offer, wait ack

[2025-09-17 14:35:59.726][000000005.864] I/ulwip adapter 4 dhcp payload len 338

[2025-09-17 14:35:59.731][000000005.875] D/ulwip 收到DHCP数据包(len=336)

[2025-09-17 14:35:59.735][000000005.875] D/DHCP dhcp state 9 5875 0 0

[2025-09-17 14:35:59.738][000000005.875] D/DHCP find ip 6303a8c0 192.168.3.99

[2025-09-17 14:35:59.742][000000005.875] D/DHCP result 5

[2025-09-17 14:35:59.745][000000005.875] D/DHCP DHCP get ip ready

[2025-09-17 14:35:59.751][000000005.875] D/ulwip adapter 4 ip 192.168.3.99

[2025-09-17 14:35:59.755][000000005.876] D/ulwip adapter 4 mask 255.255.255.0

[2025-09-17 14:35:59.759][000000005.876] D/ulwip adapter 4 gateway 192.168.3.1

[2025-09-17 14:35:59.763][000000005.876] D/ulwip adapter 4 lease_time 604800s

[2025-09-17 14:35:59.767][000000005.876] D/ulwip adapter 4 DNS1:192.168.3.1

[2025-09-17 14:35:59.771][000000005.876] D/net network ready 4, setup dns server

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
