## 功能模块介绍

1、main.lua：主程序入口；

2、netdrv_device.lua：网卡驱动设备，可以配置使用netdrv文件夹内的四种网卡(单4g网卡，单wifi网卡，单spi以太网卡，多网卡)中的任何一种网卡；

3、mqtt文件夹：mqtt client连接以及数据收发处理逻辑；

4、mqtts文件夹：mqtt ss client（不支持证书校验）连接以及数据收发处理逻辑；

5、mqtts_ca文件夹：mqtt ss client（仅单向校验server端证书）连接以及数据收发处理逻辑；

6、network_watchdog.lua：网络环境检测看门狗；

7、timer_app.lua：通知三个mqtt client定时发送数据到服务器；

8、uart_app.lua：在三个mqtt client和uart外设之间透传数据；



## 系统消息介绍

1、"IP_READY"：某种网卡已经获取到ip信息，仅仅获取到了ip信息，能否和外网连通还不确认；

2、"IP_LOSE"：某种网卡已经掉网；



## 用户消息介绍

1、"RECV_DATA_FROM_SERVER"：mqtt client收到服务器下发的publish数据后，通过此消息发布出去，给其他应用模块（uart_app）处理；

2、"SEND_DATA_REQ"：其他应用模块（uart_app，timer_app）发布此消息，通知mqtt client发送publish数据给服务器；

3、"FEED_NETWORK_WATCHDOG"：网络环境检测看门狗的喂狗消息，在需要喂狗的地方发布此消息；



## 演示功能概述

1、创建三路mqtt连接，详情如下

- 创建一个mqtt client，连接mqtt server；

- 创建一个mqtt ssl client，连接mqtt ssl server，不做证书校验；

- 创建一个mqtt ssl client，连接mqtt ssl server，client仅单向校验server的证书，server不校验client的证书和密钥文件；

2、每一路mqtt连接出现异常后，自动重连；

3、每一路mqtt连接，client按照以下几种逻辑发送数据给server

- 串口应用功能模块uart_app.lua，通过uart1接收到串口数据，将串口数据增加send from uart: 前缀后，使用mobile.imei().."/uart/up"主题，发送给server；

- 定时器应用功能模块timer_app.lua，定时产生数据，将数据增加send from timer：前缀后，使用mobile.imei().."/timer/up"主题，发送给server；

4、每一路mqtt连接，client收到server数据后，将数据增加recv from mqtt/mqtt ssl/mqtt ssl ca（三选一）server: 前缀后，通过uart1发送出去；

5、启动一个网络业务逻辑看门狗task，用来监控网络环境，如果连续长时间工作不正常，重启整个软件系统；

6、netdrv_device：配置连接外网使用的网卡，目前支持以下四种选择（四选一）

   (1) netdrv_4g：4G网卡

   (2) netdrv_wifi：WIFI STA网卡

   (3) netdrv_eth_spi：通过SPI外挂CH390H芯片的以太网卡

   (4) netdrv_multiple：支持以上三种网卡，可以配置三种网卡的优先级



## 演示硬件环境

![](https://docs.openluat.com/air8000/luatos/app/image/netdrv_multi.jpg)

1、Air8000开发板一块+可上网的sim卡一张+4g天线一根+wifi天线一根+网线一根：

- sim卡插入开发板的sim卡槽

- 天线装到开发板上

- 网线一端插入开发板网口，另外一端连接可以上外网的路由器网口

2、TYPE-C USB数据线一根 + USB转串口数据线一根，Air8000开发板和数据线的硬件接线方式为：

- Air8000开发板通过TYPE-C USB口供电；（外部供电/USB供电 拨动开关 拨到 USB供电一端）

- TYPE-C USB数据线直接插到核心板的TYPE-C USB座子，另外一端连接电脑USB口；

- USB转串口数据线，一般来说，白线连接开发板的UART1_TX，绿线连接开发板的UART1_RX，黑线连接核心板的GND，另外一端连接电脑USB口；


## 演示软件环境

1、Luatools下载调试工具

2、[Air8000 V2011版本固件](https://docs.openluat.com/air8000/luatos/firmware/)（理论上最新版本固件也可以，如果使用最新版本的固件不可以，可以烧录V2011固件对比验证）

3、PC端的串口工具，例如SSCOM、LLCOM等都可以

4、[MQTT客户端软件MQTTX](https://docs.openluat.com/air8000/luatos/common/swenv/#27-mqttmqttx)


## 演示核心步骤

1、搭建好硬件环境

2、demo脚本代码netdrv_device.lua中，按照自己的网卡需求启用对应的Lua文件

- 如果需要单4G网卡，打开require "netdrv_4g"，其余注释掉

- 如果需要单WIFI STA网卡，打开require "netdrv_wifi"，其余注释掉；同时netdrv_wifi.lua中的wlan.connect("茶室-降功耗,找合宙!", "Air123456", 1)，前两个参数，修改为自己测试时wifi热点的名称和密码；注意：仅支持2.4G的wifi，不支持5G的wifi

- 如果需要以太网卡，打开require "netdrv_eth_spi"，其余注释掉

- 如果需要多网卡，打开require "netdrv_multiple"，其余注释掉；同时netdrv_multiple.lua中的ssid = "茶室-降功耗,找合宙!", password = "Air123456", 修改为自己测试时wifi热点的名称和密码；注意：仅支持2.4G的wifi，不支持5G的wifi

3、Luatools烧录内核固件和修改后的demo脚本代码

4、烧录成功后，自动开机运行，如果出现以下日志，表示三路mqtt连接成功

``` lua
I/user.mqtt_client_main_task_func connect success

I/user.mqtts_client_main_task_func connect success

I/user.mqtts_ca__client_main_task_func connect success
```

5、启动两个MQTTX工具，分别连接上mqtt client和mqtts client对应的server，订阅$imei/up主题，$imei表示设备的imei号；
   可以看到，每隔5秒钟，会接收到一段类似于 send from timer: 1 的数据，最后面的数字每次加1；

6、打开PC端的串口工具，选择对应的端口，配置波特率115200，数据位8，停止位1，无奇偶校验位；

7、PC端的串口工具输入一段数据，点击发送，在MQTTX工具订阅的$imei/up主题下可以接收到数据；

8、在MQTTX工具上，在主题$imei/down下publish一段数据，点击发送，在PC端的串口工具上可以接收到主题和数据，并且也能看到是哪一个server发送的，类似于以下效果：

``` lua
recv from mqtt server: 864793080144269/down,123456798012345678901234567830
recv from mqtt ssl server: 864793080144269/down,123456798012345678901234567830
recv from mqtt ca ssl server: 864793080144269/down,123456798012345678901234567830
```
