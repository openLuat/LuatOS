## 功能模块介绍

1、main.lua：主程序入口；

2、netdrv_device.lua：网卡驱动设备，可以配置使用netdrv文件夹内的三种网卡(单4g网卡，单spi以太网卡，多网卡)中的任何一种网卡；

3、websocket_main.lua：WebSocket client连接以及数据收发处理主逻辑；

4、websocket_receiver.lua：WebSocket client数据发送处理模块；

5、websocket_sender.lua：WebSocket client数据接收处理模块；

6、network_watchdog.lua：网络环境检测看门狗；

7、timer_app.lua：通知websocket client定时发送数据到服务器；

8、uart_app.lua：在websocket client和uart外设之间透传数据；

## 系统消息介绍

1、"IP_READY"：某种网卡已经获取到ip信息，仅仅获取到了ip信息，能否和外网连通还不确认；

2、"IP_LOSE"：某种网卡已经掉网；


## 用户消息介绍

1、"RECV_DATA_FROM_SERVER"：socket client收到服务器下发的数据后，通过此消息发布出去，给其他应用模块处理；

2、"SEND_DATA_REQ"：其他应用模块发布此消息，通知WebSocket 客户端发送数据给服务器；

3、"FEED_NETWORK_WATCHDOG"：网络环境检测看门狗的喂狗消息，在需要喂狗的地方发布此消息；


## 演示功能概述

1、创建WebSocket连接，详情如下：

   注意：代码中的WebSocket服务器地址和端口会不定期重启或维护，仅能用作测试用途，不可商用，说不定哪一天就关闭了。用户开发项目时，需要替换为自己的商用服务器地址和端口。

   创建一个WebSocket client，连接WebSocket server；

   支持wss加密连接；

2、WebSocket连接出现异常后，自动重连；

3、WebSocket client按照以下几种逻辑发送数据给server：

   串口应用功能模块uart_app.lua，通过uart1接收到串口数据，将串口数据转发给server；

   定时器应用功能模块timer_app.lua，定时产生数据，将数据发送给server；

   特殊命令处理：当收到"echo"命令时，会发送包含时间信息的JSON数据；

4、WebSocket client收到server数据后，将数据增加"收到WebSocket服务器数据: "前缀后，通过uart1发送出去；

5、启动一个网络业务逻辑看门狗task，用来监控网络环境，如果连续长时间工作不正常，重启整个软件系统；

6、netdrv_device：配置连接外网使用的网卡，目前支持以下三种选择（三选一）

   (1) netdrv_4g：4G网卡

   (2) netdrv_eth_spi：通过SPI外挂CH390H芯片的以太网卡

   (3) netdrv_multiple：支持以上三种网卡，可以配置三种网卡的优先级


## 演示硬件环境

![](https://docs.openluat.com/air780epm/luatos/app/driver/eth/image/RFSvb75NRoEWqYxfCRVcVrOKnsf.jpg)

1、 Air780EPM V1.3 版本开发板一块 + 可上网的 sim 卡一张 +4g 天线一根 + 网线一根：

- sim卡插入开发板的sim卡槽

- 天线装到开发板上

- 网线一端插入开发板网口，另外一端连接可以上外网的路由器网口

2、TYPE-C USB数据线一根 + USB转串口数据线一根，Air8000开发板和数据线的硬件接线方式为：

- Air780EPM开发板通过TYPE-C USB口供电；（外部供电/USB供电 拨动开关 拨到 USB供电一端）

- TYPE-C USB数据线直接插到核心板的TYPE-C USB座子，另外一端连接电脑USB口；

- USB转串口数据线，一般来说，白线连接开发板的 UART1_TX，绿线连接开发板的 UART1_RX，黑线连接核心板的 GND，另外一端连接电脑USB口；


## 演示软件环境

1、Luatools下载调试工具 [https://docs.openluat.com/air780epm/common/Luatools/]

2、Air780EPM V2012 版本固件（理论上，2025 年 7 月 26 日之后发布的固件都可以）

3、PC端的串口工具，例如SSCOM、LLCOM等都可以；


## 演示核心步骤

1、搭建好硬件环境

2、demo脚本代码netdrv_device.lua中，按照自己的网卡需求启用对应的Lua文件：

    如果需要单4G网卡，打开require "netdrv_4g"，其余注释掉

    如果需要以太网卡，打开require "netdrv_eth_spi"，其余注释掉

    如果需要多网卡，打开require "netdrv_multiple"，其余注释掉。

3、Luatools烧录内核固件和修改后的demo脚本代码

4、烧录成功后，自动开机运行，如果出现以下日志，表示WebSocket连接成功：
``` lua
I/user.WebSocket发送任务 WebSocket连接成功
```

5、打开PC端的串口工具，选择对应的端口，配置波特率115200，数据位8，停止位1，无奇偶校验位；勾选“DRT"和"Hex显示"。

6、PC端的串口工具输入"echo"，点击发送，WebSocket服务器会回复当前时间信息；
``` lua
 收到WebSocket服务器数据: Wed 2025-08-27 17:34:17
```

7、PC端的串口工具输入任意数据，点击发送，数据会通过WebSocket发送到服务器；

8、PC端的串口工具，发送一段非"echo"数据，会出现以下日志，并且能看到是WebSocket server发送的，类似于以下效果：
``` lua
I/user.准备发送数据到服务器，长度 7
I/user.原始数据: AAAAA
I/user.UART发送到服务器的数据包类型 string
I/user.转发普通数据
I/user.WebSocket发送任务等待消息 SEND_REQ nil nil
I/user.WebSocket发送任务 收到发送请求
I/user.wbs_sender 发送成功 长度 7

```

 

