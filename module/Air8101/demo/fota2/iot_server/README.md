## 功能模块介绍

### iot服务器fota功能演示

1、main.lua：主程序入口；

2、netdrv_device.lua：网卡驱动设备，可以配置使用netdrv文件夹内的四种网卡(单4g网卡，单wifi网卡，单spi以太网卡，多网卡)中的任何一种网卡；

3、update.lua：使用合宙iot服务器进行远程升级功能模块，简单升级演示；

4、tcp_iot文件夹：通过tcp服务器下发升级指令（指令格式使用json字符串，包含是否升级参数），控制设备启动air_srv_fota功能模块，使用合宙iot服务器进行升级；

5、air_srv_fota.lua：合宙服务器升级功能模块；

6、psm_power_fota.lua：低功耗fota功能模块，此场景是针对psm状态下升级没完成就进入休眠导致升级失败的情况写的一个例子。需要注意的是此场景与上面两种场景不能同时使用；


## 系统消息介绍

1、"IP_READY"：某种网卡已经获取到ip信息，仅仅获取到了ip信息，能否和外网连通还不确认；

2、"IP_LOSE"：某种网卡已经掉网；



## 用户消息介绍

1、"RECV_DATA_FROM_SERVER"：socket client收到服务器下发的数据后，通过此消息发布出去，给其他应用模块处理；

2、"SEND_DATA_REQ"：其他应用模块发布此消息，通知socket client发送数据给服务器；



## 演示功能概述

1、此demo演示了三种场景：

   (1) fota升级简单演示：使用合宙iot服务器进行远程升级功能模块，简单升级演示；

   (2) tcp服务器下发升级指令：通过tcp服务器下发升级指令（指令格式使用json字符串，包含是否升级参数），控制设备使用fota功能模块；

   (3) psm低功耗fota：低功耗fota功能模块，此场景是针对psm状态下升级没完成就进入休眠导致升级失败的情况写的一个例子；

2、netdrv_device：配置连接外网使用的网卡，目前支持以下四种选择（四选一）

   (1) netdrv_4g：4G网卡

   (2) netdrv_wifi：WIFI STA网卡

   (3) netdrv_eth_spi：通过SPI外挂CH390H芯片的以太网卡

   (4) netdrv_multiple：支持以上三种网卡，可以配置三种网卡的优先级


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

3、PC端浏览器访问[合宙TCP/UDP web测试工具](https://netlab.luatos.com/)；


## 演示核心步骤

1、搭建好硬件环境

2、PC端浏览器访问[合宙TCP/UDP web测试工具](https://netlab.luatos.com/)，点击 打开TCP 按钮，会创建一个TCP server，将server的地址和端口赋值给tcp_iot_main.lua中的SERVER_ADDR和SERVER_PORT两个变量

4、demo脚本代码netdrv_device.lua中，按照自己的网卡需求启用对应的Lua文件

- 如果需要单4G网卡，打开require "netdrv_4g"，其余注释掉

- 如果需要单WIFI STA网卡，打开require "netdrv_wifi"，其余注释掉；同时netdrv_wifi.lua中的wlan.connect("茶室-降功耗,找合宙!", "Air123456", 1)，前两个参数，修改为自己测试时wifi热点的名称和密码；注意：仅支持2.4G的wifi，不支持5G的wifi

- 如果需要以太网卡，打开require "netdrv_eth_spi"，其余注释掉

- 如果需要多网卡，打开require "netdrv_multiple"，其余注释掉；同时netdrv_multiple.lua中的ssid = "茶室-降功耗,找合宙!", password = "Air123456", 修改为自己测试时wifi热点的名称和密码；注意：仅支持2.4G的wifi，不支持5G的wifi

5、Luatools烧录内核固件和修改后的demo脚本代码

6、使用Luatools制作升级包，先把新旧版本分别生成量产文件，然后再制作升级包，工具上栏 luatOS->固件工具->差分包/整包升级包制作，将制作好的升级包配置到合宙iot服务器自己项目下，或上传到自建服务器上面；

7、烧录成功后，自动开机运行

8、可以看到升级过程如下，不管是什么场景下升级，基本都是如下日志情况：

``` lua
--没有升级之前可以看到如下打印
I/user.fota 脚本版本号 001.000.000 core版本号 V2010

I/user.fota_task_func recv IP_READY 1
I/user.开始检查升级

I/user.升级包下载成功,重启模块


--升级之后可以看到如下打印
I/user.fota 脚本版本号 001.000.001 core版本号 V2012
--升级重启之后还是会检查升级，所以会有如下打印属于正常情况，其中"code": 27 是合宙iot服务器返回的状态码，意思是已经是最新版本了。
I/user.fota -9 {"code": 27, "msg": "\u5df2\u662f\u6700\u65b0\u7248\u672c"}
I/user.使用合宙服务器,接下来解析body里的code
I/user.已是最新版本 1.设备的固件/脚本版本高于或等于云平台上的版本号 2.用户项目升级配置中未添加该设备 3.云平台升级配置中，是否升级配置为否
I/user.fota 4


```
9、对于psm休眠状态下的升级的场景，可以通过iot平台查看是否成功，在iot平台的升级日志页面搜索模组的imei，可以看到有两条升级结果“成功”和“已是最新版本”。模组升级成功后会自动进入psm休眠状态。可以通过电流查看休眠情况。