## 功能模块介绍

1、main.lua：主程序入口；

2、netdrv_device.lua：网卡驱动设备，可以配置使用netdrv文件夹内的两种网卡(4G网卡、PC模拟器网卡)中的一种；

3、websocket_main.lua：WebSocket client连接以及数据收发处理主逻辑；

4、websocket_receiver.lua：WebSocket client数据接收处理模块；

5、websocket_sender.lua：WebSocket client数据发送处理模块；

6、network_watchdog.lua：网络环境检测看门狗；

7、timer_app.lua：通知websocket client定时发送数据到服务器；

8、sntp_app.lua：发起ntp时间同步动作；

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

3、WebSocket client按以下逻辑发送数据给server：

   定时器应用功能模块timer_app.lua，定时产生数据，将数据发送给server；

   特殊命令处理：当收到"echo"命令时，会发送包含时间信息的JSON数据；

4、启动一个网络业务逻辑看门狗task，用来监控网络环境，如果连续长时间工作不正常，重启整个软件系统；

5、在网络就绪后进行NTP时间同步，确保设备时间准确，为收到"echo"命令时发送包含时间信息的JSON数据提供可靠的时间基准,避免出现发送的时间和日志时间不一致的问题。

6、netdrv_device：配置连接外网使用的网卡，目前支持以下两种选择（二选一）

   (1) netdrv_4g：4G网卡

   (2) netdrv_pc：PC模拟器网卡（仅开发调试使用）

## 演示硬件环境

1、Air8201 整机板 + 可上网的 SIM 卡 + 4G 天线；

2、TYPE-C USB 数据线，连接电脑供电和下载；

## 演示软件环境

1、Luatools下载调试工具

2. [Air8201G固件](https://docs.openluat.com/air780egh/luatos/firmware/version/)

3. [Air8201H固件](https://docs.openluat.com/air780epm/luatos/firmware/version/)

## 演示核心步骤

1、搭建好硬件环境

2、demo脚本代码netdrv_device.lua中，按照自己的网卡需求启用对应的Lua文件：

- 如果需要4G网卡，打开require "netdrv_4g"，其余注释掉

- 如果需要PC模拟器网卡调试，打开require "netdrv_pc"，其余注释掉

3、Luatools烧录内核固件和修改后的demo脚本代码

4、烧录成功后，自动开机运行，如果出现以下日志，表示WebSocket连接成功：
``` lua
I/user.WebSocket主任务 连接成功
```

5、在日志中可以看到定时器发送的数据和服务器的回复；

6、当收到服务器转发的"echo"消息时，会返回当前时间信息：
``` lua
I/user.WebSocket接收处理 提取echo消息 Sat 2025-09-04 19:46:19
```
