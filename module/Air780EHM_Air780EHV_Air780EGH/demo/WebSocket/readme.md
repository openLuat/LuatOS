## 功能模块介绍

1、main.lua：主程序入口；

2、netdrv_device.lua：网卡驱动设备，可以配置使用netdrv文件夹内的四种网卡(单4g网卡，单wifi网卡，单spi以太网卡，多网卡)中的任何一种网卡；

3、websocket_main.lua：WebSocket client连接以及数据收发处理主逻辑；

4、websocket_receiver.lua：WebSocket client数据发送处理模块；

5、websocket_sender.lua：WebSocket client数据接收处理模块；

6、network_watchdog.lua：网络环境检测看门狗；

7、timer_app.lua：通知websocket client定时发送数据到服务器；

8、uart_app.lua：在websocket client和uart外设之间透传数据；

9、sntp_app.lua；发起ntp时间同步动作；

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

6、在网络就绪后进行NTP时间同步，确保设备时间准确，为收到"echo"命令时发送包含时间信息的JSON数据提供可靠的时间基准,避免出现发送的时间和日志时间不一致的问题。

7、netdrv_device：配置连接外网使用的网卡，目前支持以下五种选择（五选一）

   (1) netdrv_4g：通过SPI外挂4G模组的4G网卡

   (2) netdrv_wifi：WIFI STA网卡

   (3) netdrv_eth_rmii：通过MAC层的rmii接口外挂PHY芯片（LAN8720Ai）的以太网卡

   (4) netdrv_eth_spi：通过SPI外挂CH390H芯片的以太网卡

   (5) netdrv_multiple：支持以上(2)、(3)、(4)三种网卡，可以配置三种网卡的优先级


## 演示硬件环境

![](https://docs.openluat.com/air8101/luatos/app/image/netdrv_multi.jpg)

1、Air8101核心板一块

2、TYPE-C USB数据线一根

3、USB转串口数据线一根

4、Air8101核心板和数据线的硬件接线方式为

- Air8101核心板通过TYPE-C USB口供电；（核心板背面的功耗测试开关拨到OFF一端）

- 如果测试发现软件频繁重启，重启原因值为：poweron reason 0，可能是供电不足，此时再通过直流稳压电源对核心板的vbat管脚进行4V供电，或者VIN管脚进行5V供电；

- TYPE-C USB数据线直接插到核心板的TYPE-C USB座子，另外一端连接电脑USB口；

- USB转串口数据线，一般来说，白线连接核心板的12/U1TX，绿线连接核心板的11/U1RX，黑线连接核心板的gnd，另外一端连接电脑USB口；

5、可选AirPHY_1000配件板一块，Air8101核心板和AirPHY_1000配件板的硬件接线方式为:

| Air8101核心板 | AirPHY_1000配件板 |
| ------------- | ----------------- |
| 59/3V3        | 3.3v              |
| gnd           | gnd               |
| 5/D2          | RX1               |
| 72/D1         | RX0               |
| 71/D3         | CRS               |
| 4/D0          | MDIO              |
| 6/D4          | TX0               |
| 74/PCK        | MDC               |
| 70/D5         | TX1               |
| 7/D6          | TXEN              |
| 不接          | NC                |
| 69/D7         | CLK               |

6、可选AirETH_1000配件板一块，Air8101核心板和AirETH_1000配件板的硬件接线方式为:

| Air8101核心板 | AirETH_1000配件板 |
| ------------- | ----------------- |
| 59/3V3        | 3.3v              |
| gnd           | gnd               |
| 28/DCLK       | SCK               |
| 54/DISP       | CSS               |
| 55/HSYN       | SDO               |
| 57/DE         | SDI               |
| 14/GPIO8      | INT               |

7、可选Air780EHM/Air780EHV/Air780EGH/Air780EPM核心板或者开发板一块，Air8101核心板和Air780EHM/Air780EHV/Air780EGH/Air780EPM核心板或者开发板的硬件接线方式为:

| Air8101核心板 | Air780EHM/Air780EHV/Air780EGH/Air780EPM核心板 |
| ------------- | --------------------------------------------- |
| gnd           | GND                                           |
| 54/DISP       | 83/SPI0CS                                     |
| 55/HSYN       | 84/SPI0MISO                                   |
| 57/DE         | 85/SPI0MOSI                                   |
| 28/DCLK       | 86/SPI0CLK                                    |
| 43/R2         | 19/GPIO22                                     |
| 75/GPIO28     | 22/GPIO1                                      |


| Air8101核心板 | Air780EHM/Air780EHV/Air780EGH/Air780EPM开发板 |
| ------------- | --------------------------------------------- |
| gnd           | GND                                           |
| 54/DISP       | SPI_CS                                        |
| 55/HSYN       | SPI_MISO                                      |
| 57/DE         | SPI_MOSI                                      |
| 28/DCLK       | SPI_CLK                                       |
| 43/R2         | GPIO22                                        |
| 75/GPIO28     | GPIO1                                         |


## 演示软件环境

1、Luatools下载调试工具

2、[Air8101 V1005版本固件](https://docs.openluat.com/air8101/luatos/firmware/)（理论上，2025年7月26日之后发布的固件都可以）

3、PC端的串口工具，例如SSCOM、LLCOM等都可以



## 演示核心步骤

1、搭建好硬件环境

2、demo脚本代码netdrv_device.lua中，按照自己的网卡需求启用对应的Lua文件：

- 如果需要单WIFI STA网卡，打开require "netdrv_wifi"，其余注释掉；同时netdrv_wifi.lua中的wlan.connect("茶室-降功耗,找合宙!", "Air123456", 1)，前两个参数，修改为自己测试时wifi热点的名称和密码；注意：仅支持2.4G的wifi，不支持5G的wifi

- 如果需要RMII以太网卡，打开require "netdrv_eth_rmii"，其余注释掉

- 如果需要SPI以太网卡，打开require "netdrv_eth_spi"，其余注释掉

- 如果需要单4G网卡，打开require "netdrv_4g"，其余注释掉

- 如果需要多网卡，打开require "netdrv_multiple"，其余注释掉；同时netdrv_multiple.lua中的ssid = "茶室-降功耗,找合宙!", password = "Air123456", 修改为自己测试时wifi热点的名称和密码；注意：仅支持2.4G的wifi，不支持5G的wifi

3、Luatools烧录内核固件和修改后的demo脚本代码

4、烧录成功后，自动开机运行，如果出现以下日志，表示WebSocket连接成功：
``` lua
I/user.WebSocket主任务 连接成功
```

5、打开PC端的串口工具，选择对应的端口，配置波特率115200，数据位8，停止位1，无奇偶校验位；勾选“DRT"和"Hex显示"。

6、PC端的串口工具输入"echo"，点击发送，WebSocket服务器会回复当前时间信息；
``` lua
 I/user.WebSocket接收处理 提取echo消息 Sat 2025-09-04 19:46:19
```

7、PC端的串口工具输入任意数据，点击发送，数据会通过WebSocket发送到服务器；

8、PC端的串口工具，发送一段非"echo"数据，会出现以下日志，并且能看到是WebSocket server发送的，类似于以下效果：
``` lua
I/user.准备发送数据到服务器，长度 5
I/user.原始数据: AAAAA
I/user.UART发送到服务器的数据包类型 string
I/user.转发普通数据
I/user.WebSocket发送任务等待消息 SEND_REQ nil nil
I/user.WebSocket发送任务 收到发送请求
I/user.wbs_sender 发送成功 长度 5

```

 

