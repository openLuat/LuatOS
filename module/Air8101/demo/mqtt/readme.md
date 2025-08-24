## 功能模块介绍

1、main.lua：主程序入口；

2、netdrv_device.lua：网卡驱动设备，可以配置使用netdrv文件夹内的五种网卡(单wifi网卡，单rmii以太网卡，单spi以太网卡，单4g网卡，多网卡)中的任何一种网卡；

3、mqtt文件夹：mqtt client连接以及数据收发处理逻辑；

4、mqtts文件夹：mqtt ss client（不支持证书校验）连接以及数据收发处理逻辑；

5、mqtts_ca文件夹：mqtt ss client（仅单向校验server端证书）连接以及数据收发处理逻辑；

6、mqtts_mutual_ca文件夹：mqtt ssl client（双向校验证书）连接以及数据收发处理逻辑；

7、network_watchdog.lua：网络环境检测看门狗；

8、timer_app.lua：通知四个mqtt client定时发送数据到服务器；

9、uart_app.lua：在四个mqtt client和uart外设之间透传数据；



## 系统消息介绍

1、"IP_READY"：某种网卡已经获取到ip信息，仅仅获取到了ip信息，能否和外网连通还不确认；

2、"IP_LOSE"：某种网卡已经掉网；



## 用户消息介绍

1、"RECV_DATA_FROM_SERVER"：mqtt client收到服务器下发的publish数据后，通过此消息发布出去，给其他应用模块（uart_app）处理；

2、"SEND_DATA_REQ"：其他应用模块（uart_app，timer_app）发布此消息，通知mqtt client发送publish数据给服务器；

3、"FEED_NETWORK_WATCHDOG"：网络环境检测看门狗的喂狗消息，在需要喂狗的地方发布此消息；



## 演示功能概述

1、创建四路mqtt连接，详情如下

> 注意：代码中的mqtt服务器地址和端口会不定期重启或维护，仅能用作测试用途，不可商用，说不定哪一天就关闭了。用户开发项目时，需要替换为自己的商用服务器地址和端口。

- 创建一个mqtt client，连接mqtt server；

- 创建一个mqtt ssl client，连接mqtt ssl server，不做证书校验；

- 创建一个mqtt ssl client，连接mqtt ssl server，client仅单向校验server的证书，server不校验client的证书和密钥文件；

- 创建一个mqtt ssl client，连接mqtt ssl server，client校验server的证书，server校验client的证书和密钥文件；

2、每一路mqtt连接出现异常后，自动重连；

3、每一路mqtt连接，client按照以下几种逻辑发送数据给server

- 串口应用功能模块uart_app.lua，通过uart1接收到串口数据，将串口数据增加send from uart: 前缀后，使用wlan.getMac().."/uart/up"主题，发送给server；

- 定时器应用功能模块timer_app.lua，定时产生数据，将数据增加send from timer：前缀后，使用wlan.getMac().."/timer/up"主题，发送给server；

4、每一路mqtt连接，client收到server数据后，将数据增加recv from mqtt/mqtt ssl/mqtt ssl ca/mqtt ssl mutual ca（四选一）server: 前缀后，通过uart1发送出去；

5、启动一个网络业务逻辑看门狗task，用来监控网络环境，如果连续长时间工作不正常，重启整个软件系统；

6、netdrv_device：配置连接外网使用的网卡，目前支持以下五种选择（五选一）

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

4、[MQTT客户端软件MQTTX](https://docs.openluat.com/air8101/luatos/common/swenv/#27-mqtt-mqttfx)


## 演示核心步骤

1、搭建好硬件环境

2、demo脚本代码netdrv_device.lua中，按照自己的网卡需求启用对应的Lua文件

- 如果需要单WIFI STA网卡，打开require "netdrv_wifi"，其余注释掉；同时netdrv_wifi.lua中的wlan.connect("茶室-降功耗,找合宙!", "Air123456", 1)，前两个参数，修改为自己测试时wifi热点的名称和密码；注意：仅支持2.4G的wifi，不支持5G的wifi

- 如果需要RMII以太网卡，打开require "netdrv_eth_rmii"，其余注释掉

- 如果需要SPI以太网卡，打开require "netdrv_eth_spi"，其余注释掉

- 如果需要单4G网卡，打开require "netdrv_4g"，其余注释掉

- 如果需要多网卡，打开require "netdrv_multiple"，其余注释掉；同时netdrv_multiple.lua中的ssid = "茶室-降功耗,找合宙!", password = "Air123456", 修改为自己测试时wifi热点的名称和密码；注意：仅支持2.4G的wifi，不支持5G的wifi

3、Luatools烧录内核固件和修改后的demo脚本代码

4、烧录成功后，自动开机运行，如果出现以下日志，表示三路mqtt连接成功

``` lua
I/user.mqtt_client_main_task_func connect success

I/user.mqtts_client_main_task_func connect success

I/user.mqtts_ca_client_main_task_func connect success

I/user.mqtts_m_ca_client_main_task_func connect success
```

5、启动三个MQTTX工具，分别连接上mqtt client、mqtts client、mqtts mutual client对应的server，订阅$mac/timer/up$主题，mac表示设备的wifi mac地址；可以看到，每隔5秒钟，会接收到一段类似于 send from timer: 1 的数据，最后面的数字每次加1；

6、打开PC端的串口工具，选择对应的端口，配置波特率115200，数据位8，停止位1，无奇偶校验位；

7、PC端的串口工具输入一段数据，点击发送，在MQTTX工具订阅的$mac/uart/up$主题下可以接收到数据；

8、在MQTTX工具上，在主题$mac/down$下publish一段数据，点击发送，在PC端的串口工具上可以接收到主题和数据，并且也能看到是哪一个server发送的，类似于以下效果：

``` lua
recv from mqtt server: C8C2C68BF9D5/down,123456798012345678901234567830
recv from mqtt ssl server: C8C2C68BF9D5/down,123456798012345678901234567830
recv from mqtt ssl ca server: C8C2C68BF9D5/down,123456798012345678901234567830
recv from mqtt ssl mutual ca server: C8C2C68BF9D5/down,123456798012345678901234567830
```
