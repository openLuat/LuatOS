## 功能模块介绍

1、main.lua：主程序入口；

2、netdrv_device.lua：网卡驱动设备，可以配置使用netdrv文件夹内的三种网卡(单wifi ap网卡，单wifi sta网卡，单spi以太网卡)中的任何一种网卡；

3、tcp文件夹：tcp server以及数据收发处理逻辑；

4、udp文件夹：udp server以及数据收发处理逻辑；

5、timer_app.lua：通知server定时发送数据给client；

6、uart_app.lua：server和uart外设之间透传数据；

> 注意：
> 
> 一个tcp server仅支持一路client连接；
> 
> UDP 协议本身是无连接的，这意味着任何在同一局域网下的客户端都可以向服务器的 IP 和端口发送数据包；

## 系统消息介绍

1、"IP_READY"：某种网卡已经获取到ip信息，仅仅获取到了ip信息，能否和外网连通还不确认；

2、"IP_LOSE"：某种网卡已经掉网；

## 用户消息介绍

1、"RECV_DATA_FROM_CLIENT"：tcp/udp server收到客户端上发的数据后，通过此消息发布出去，给其他应用模块处理；

2、"SEND_DATA_REQ"：其他应用模块发布此消息，通知tcp/udp server发送数据给客户端；

## 演示功能概述

1、创建tcp/udp server，在目录中对应两个文件夹详情如下

- TCP文件夹功能为创建一个tcp server，等待tcp client连接；

- UDP文件夹功能为创建一个udp server，等待udp client连接；

2、tcp/udp server 与client连接成功后，server按照以下几种逻辑发送数据给client

- 串口应用功能模块uart_app.lua，通过uart1接收到串口数据，将串口数据增加send from uart: 前缀后发送给client；

- 定时器应用功能模块timer_app.lua，定时产生数据，将数据增加send from timer：前缀后发送给client；

3、netdrv_device：配置连接外网使用的网卡，目前支持以下三种选择（三选一）

   (1) netdrv_wifi_ap：WIFI AP网卡

   (2) netdrv_wifi_sta：WIFI STA网卡

   (3) netdrv_eth_spi：通过SPI外挂CH390H芯片的以太网卡


## 演示硬件环境

![](https://docs.openluat.com/air8000/luatos/app/image/netdrv_multi.jpg)

1、Air8000开发板一块+wifi天线一根+网线一根：

- 天线装到开发板上

- 网线一端插入开发板网口，另外一端连接可以上外网的路由器网口

2、TYPE-C USB数据线一根 + USB转串口数据线一根，Air8000开发板和数据线的硬件接线方式为：

- Air8000开发板通过TYPE-C USB口供电；（外部供电/USB供电 拨动开关 拨到 USB供电一端）

- TYPE-C USB数据线直接插到开发板的TYPE-C USB座子，另外一端连接电脑USB口；

- USB转串口数据线，一般来说，白线连接开发板的UART1_TX，绿线连接开发板的UART1_RX，黑线连接开发板的GND，另外一端连接电脑USB口；


## 演示软件环境

1、Luatools下载调试工具

2、[Air8000 V2016版本固件](https://docs.openluat.com/air8000/luatos/firmware/)（理论上，2025年7月26日之后发布的固件都可以）

3、PC端的串口工具，建议使用SSCOM（SSCOM可以创建TCP客户端或UDP客户端，测试TCP/UDP 通信功能）

## 演示核心步骤

1、搭建好硬件环境

2、demo脚本代码netdrv_device.lua中，按照自己的网卡需求启用对应的Lua文件

- 如果需要单WIFI AP网卡，打开require "netdrv_wifi_ap"，其余注释掉；同时netdrv_wifi_ap.lua中的wlan.createAP("LuatOS" .. mobile.imei(), "12345678")，表示创建wifi的名称和密码，根据自己需求改动即可；

- 如果需要单WIFI STA网卡，打开require "netdrv_wifi_sta"，其余注释掉；同时netdrv_wifi_sta.lua中的wlan.connect("茶室-降功耗,找合宙!", "Air123456", 1)，前两个参数，修改为自己测试时wifi热点的名称和密码；注意：仅支持2.4G的wifi，不支持5G的wifi

- 如果需要以太网卡，打开require "netdrv_eth_spi"，其余注释掉


3、demo脚本代码中，测试TCP server和UDP server时，需要修改的地方如下：

- 测试TCP server时，main.lua打开 require "tcp_server_main"，注释掉 require "udp_server_main"；同时timer_app.lua和uart_app.lua中的enable_tcp设为true，enable_udp设为false。

- 测试UDP server时，main.lua打开 require "udp_server_main"，注释掉 require "tcp_server_main"；同时timer_app.lua和uart_app.lua中的enable_udp设为true，enable_tcp设为false。

4、Luatools烧录内核固件和修改后的demo脚本代码

5、烧录成功后，自动开机运行

6、TCP演示：

（1）根据烧录日志，找到TCP server的ip，此外 port 在示例代码中默认是50003

ip获取方式，是在每个netdrv网卡文件中的 ip_ready_func接口中，此处演示WIFI_STA网卡的情况下，如何找到创建的TCP server的ip

```lua
local function ip_ready_func(ip, adapter)
    if adapter == socket.LWIP_STA then
        log.info("netdrv_wifi.ip_ready_func", "IP_READY: ", ip, json.encode(wlan.getInfo()))
    end
end
```
luatools日志打印如下：

![image](https://docs.openLuat.com/cdn/image/socket/tcp_ip_ready.png)

（2）PC 端打开一个TCP客户端，连接到Air8000开发板创建的TCP server （本例使用SSCOM打开一个TCP客户端）:

端口号：选择TCPCLient

远程：填写TCP server的ip地址 和TCP监听的port ，默认是50003

本地：填写本地PC端的IP地址

![image](https://docs.openLuat.com/cdn/image/socket/tcp_client.png)

成功连接之后，即可收到TCP server主动发送的第一条消息：

![image](https://docs.openLuat.com/cdn/image/socket/tcp_client1.png)

（3）另外再打开一个PC端的串口工具连接到Air8000开发板的uart1, 做串口收发，选择对应的端口，配置波特率115200，数据位8，停止位1，无奇偶校验位

（4）PC端的串口工具输入一段数据 "hello client!"，点击发送，在作为TCP客户端的SSCOM上可以收到此数据；在作为TCP 客户端的SSCOM输入一段数据 "i am tcp client"，点击发送，在PC端的串口工具上可以收到此数据，如下所示：

![image](https://docs.openLuat.com/cdn/image/socket/tcp_client2.png)


7、UDP演示：

（1）根据烧录日志，找到UDP server的ip，此外 port 在示例代码中默认是50003

ip获取方式，是在每个netdrv网卡文件中的 ip_ready_func接口中，此处演示WIFI_STA网卡的情况下，如何找到创建的UDP server的ip

```lua
local function ip_ready_func(ip, adapter)
    if adapter == socket.LWIP_STA then
        log.info("netdrv_wifi.ip_ready_func", "IP_READY: ", ip, json.encode(wlan.getInfo()))
    end
end
```
luatools日志打印如下：

![image](https://docs.openLuat.com/cdn/image/socket/udp_ip_ready.png)

（2）PC 端打开一个UDP客户端，连接到Air8000开发板创建的UDP server （本例使用SSCOM打开一个UDP客户端）:

端口号：选择UDP

远程：填写UDP server的ip地址 和UDP监听的port ，默认是50003

本地：填写本地PC端的IP地址, 本例填写的port是50000

![image](https://docs.openLuat.com/cdn/image/socket/udp_client.png)

成功连接之后，即可收到UDP server主动发送的第一条消息：

![image](https://docs.openLuat.com/cdn/image/socket/udp_client1.png)

（3）另外再打开一个PC端的串口工具连接到Air8000开发板的uart1, 做串口收发，选择对应的端口，配置波特率115200，数据位8，停止位1，无奇偶校验位

（4）PC端的串口工具输入一段数据 "hello udp server!"，点击发送，在作为UDP客户端的SSCOM上可以收到此数据；在作为UDP 客户端的SSCOM输入一段数据 "i am udp client"，点击发送，在PC端的串口工具上可以收到此数据，如下所示： 

![image](https://docs.openLuat.com/cdn/image/socket/udp_client2.png)

8、注意事项

UDP server 在未收到 client发的数据时，会每隔15秒向255.255.255.255 发送一条心跳广播消息，同时timer_app定时发送功能 由于无法确定客户端的ip和port, 会打印 "尚未收到客户端数据, 无法确定目标IP和端口" 的错误提示；

UDP server 在收到client 发的数据后，会记录下来发送消息的client的ip和port，然后通过timer_app 每隔5秒向client发送数据。

目前只能支持局域网内的client连接，不支持公网ip连接。