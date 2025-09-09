## 功能模块介绍

1、main.lua：主程序入口；

2、netdrv_device.lua：网卡驱动设备，可以配置使用netdrv文件夹内的四种网卡(单4g网卡，单wifi网卡，单spi以太网卡，多网卡)中的任何一种网卡；

3、errdump_read.lua：手动读取errdump异常日志功能模块；

4、errdump_tcp文件夹：将手动读取到的日志发到tcp服务器中。

5、uart_app.lua：uart应用层，用于将手动读取的异常日志通过串口发出去；

6、auto_dump_air_srv.lua：自动上报异常日志到合宙服务器中；

7、auto_dump_udp_srv.lua：自动上报异常日志到自建udp服务器中；注：1、必须udp服务器；2、收到模组上报的异常日志后要回复一个大写的OK。

## 系统消息介绍

1、"IP_READY"：某种网卡已经获取到ip信息，仅仅获取到了ip信息，能否和外网连通还不确认；

2、"IP_LOSE"：某种网卡已经掉网；

## 用户消息介绍

1、"ERRDUMP_DATA_SEND_UART"：手动读取到的异常日志通过此消息发送到uart应用层；

2、"SEND_DATA_REQ"：手动读取到异常日志后发布此消息，通知socket client发送数据给服务器；

## 演示功能概述

1、主要是使用Air8000开发板演示四种errdump异常日志上报功能，使用的时候根据自己需求在main.lua文件中选择要使用的功能，注意不能同时使用自动上报和手动读取功能。

    （1）自动上报异常日志到iot平台

    （2）自动上报异常日志到自建udp服务器

    （3）手动读取异常日志并通过串口传输

    （4）手动读取异常日志并通过tcp传输

2、netdrv_device：配置连接外网使用的网卡，目前支持以下四种选择（四选一）

    （1） netdrv_4g：4G网卡

    （2） netdrv_wifi：WIFI STA网卡

    （3） netdrv_eth_spi：通过SPI外挂CH390H芯片的以太网卡

    （4） netdrv_multiple：支持以上三种网卡，可以配置三种网卡的优先级

## 演示硬件环境

![](https://docs.openluat.com/air8000/luatos/app/image/netdrv_multi.jpg)

1、Air8000开发板一块+可上网的sim卡一张+4g天线一根+wifi天线一根+网线一根：

- sim卡插入开发板的sim卡槽

- 天线装到开发板上

- 网线一端插入开发板网口，另外一端连接可以上外网的路由器网口

2、TYPE-C USB数据线一根 + USB转串口数据线一根，Air8000开发板和数据线的硬件接线方式为：

- Air8000开发板通过TYPE-C USB口供电；（外部供电/USB供电 拨动开关 拨到 USB供电一端）

- TYPE-C USB数据线直接插到开发板的TYPE-C USB座子，另外一端连接电脑USB口；

- USB转串口数据线，一般来说，白线连接开发板的UART1_TX，绿线连接开发板的UART1_RX，黑线连接开发板的GND，另外一端连接电脑USB口；

## 演示软件环境

1、Luatools下载调试工具

2、[Air8000 V2014版本固件）](https://docs.openluat.com/air8000/luatos/firmware/)

3、PC端浏览器访问[合宙TCP/UDP web测试工具](https://netlab.luatos.com/)；

## 演示开发步骤

1、搭建好硬件环境

2、在main.lua文件中选择好要使用的功能，通过Luatools将demo与固件烧录到开发板中

3、烧录好后，板子开机同时在luatools上查看日志：

可以看到设备打印的死机日志以及errdump ok!字样

```lua
[2025-07-15 16:17:59.681][000000034.674] D/errDump errdump ok!
[2025-07-15 16:18:14.479][000000049.480] dns_run 674:dev_msg1.openluat.com state 0 id 4 ipv6 0 use dns server2, try 0
[2025-07-15 16:18:14.634][000000049.625] dns_run 691:dns all done ,now stop
[2025-07-15 16:18:14.728][000000049.721] D/errDump errdump ok!
[2025-07-15 16:18:25.443][000000060.434] E/user.coroutine.resume	auto_dump_air_srv.lua:42: attempt to index a nil value (global 'lllllllllog')
stack traceback:
	auto_dump_air_srv.lua:42: in function <errdump_test.lua:30>
[2025-07-15 16:18:25.944][000000060.934] E/main Luat:
[2025-07-15 16:18:25.961][000000060.935] E/main auto_dump_air_srv.lua:42: attempt to index a nil value (global 'lllllllllog')
stack traceback:
	auto_dump_air_srv.lua:42: in function <errdump_test.lua:30>

```

烧录不同的功能代码，可以在对应的平台看到如下信息：

```lua
errdump_demo_LuatOS-SoC_V2009_Air8000,001.000.000,866597072472820,866597072472820, 测试一下用户的记录功能
errdump_demo_LuatOS-SoC_V2009_Air8000,001.000.000,866597072472820,866597072472820, poweron reason:3 auto_dump_air_srv.lua:42: attempt to index a nil value (global 'lllllllllog') stack traceback: auto_dump_air_srv.lua:42: in function <errdump_test.lua:30>
```