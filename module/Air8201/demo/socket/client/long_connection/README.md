## 功能模块介绍

1、main.lua：主程序入口；

2、netdrv_device.lua：网卡驱动设备，可以配置使用4G网卡或PC模拟器网卡；

3、tcp文件夹：tcp client连接以及数据收发处理逻辑；

4、udp文件夹：udp client连接以及数据收发处理逻辑；

5、tcp_ssl文件夹：tcp ssl client连接以及数据收发处理逻辑；

6、tcp_ssl_ca文件夹：tcp ssl client单向认证连接以及数据收发处理逻辑；

7、network_watchdog.lua：网络环境检测看门狗；

8、timer_app.lua：通知四个client定时发送数据到服务器；

9、aircloud_data.lua：通知四个client上报符合aircloud规则的数据到aircloud平台；

## 硬件版本兼容

本 demo 同时兼容 **Air8201G** 和 **Air8201H** 两种硬件版本，仅支持 4G 联网。

## 系统消息介绍

1、"IP_READY"：某种网卡已经获取到ip信息，仅仅获取到了ip信息，能否和外网连通还不确认；

2、"IP_LOSE"：某种网卡已经掉网；

## 用户消息介绍

1、"RECV_DATA_FROM_SERVER"：socket client收到服务器下发的数据后，通过此消息发布出去，给其他应用模块处理；

2、"SEND_DATA_REQ"：其他应用模块发布此消息，通知socket client发送数据给服务器；

3、"FEED_NETWORK_WATCHDOG"：网络环境检测看门狗的喂狗消息，在需要喂狗的地方发布此消息；

4、"CONNECTION_SUCCESS"：socket client连接成功后，通过此消息发布出去，给其他应用模块处理；

## 演示功能概述

1、创建四路socket连接，在目录中对应四个文件夹详情如下

- TCP文件夹功能为创建一个tcp client，连接tcp server；

- UDP文件夹功能为创建一个udp client，连接udp server；

- TCP_SSL文件夹功能为创建一个tcp ssl client，连接tcp ssl server，不做证书校验；

- TCP_SSL_CA文件夹功能为创建一个tcp ssl client，连接tcp ssl server，client仅单向校验server的证书，server不校验client的证书和密钥文件；

2、每一路socket连接出现异常后，自动重连；

3、每一路socket连接，client按照以下逻辑发送数据给server

- 定时器应用功能模块timer_app.lua，定时产生数据，将数据增加send from timer：前缀后发送给server；

- aircloud应用功能模块aircloud_data.lua，定时产生符合Aircloud格式的数据，将数据发送给Aircloud服务器；

4、启动一个网络业务逻辑看门狗task，用来监控网络环境，如果连续长时间工作不正常，重启整个软件系统；

5、netdrv_device：配置连接外网使用的网卡，目前支持以下选择（二选一）

   (1) netdrv_4g：4G网卡（默认）

   (2) netdrv_pc：PC模拟器网卡（仅调试用）


## 演示硬件环境

1、Air8201 整机板一块+SIM卡一张+4g天线一根，所有硬件环境组装好。

2、TYPE-C USB 数据线一根，Air8201 整机板和电脑的硬件接线方式为：

- Air8201 整机板通过 TYPE-C USB 口供电；
- TYPE-C USB 数据线直接插到整机板的 TYPE-C USB 座子，另外一端连接电脑 USB 口；

## 演示软件环境

1、Luatools下载调试工具

2、[Air8201G固件](https://docs.openluat.com/air780egh/luatos/firmware/version/)

3、[Air8201H固件](https://docs.openluat.com/air780epm/luatos/firmware/version/)

4、PC端浏览器访问[合宙TCP/UDP web测试工具](https://iot.luatos.com/#/page6/netlab)；

该工具具体使用方法可以参考[合宙TCP/UDP web测试工具](https://docs.openluat.com/common/TCPUDP_Test/)的说明；

登陆成功后点击"工具等"，进入工具列表，点击"Netlab测试工具"

![netlab所在位置](https://docs.openLuat.com/cdn/image/socket/netlab_local.png)


## 演示核心步骤

1、搭建好硬件环境

2、PC端浏览器访问[合宙TCP/UDP web测试工具](https://iot.luatos.com/#/page6/netlab)；登陆成功后点击"工具等"，进入工具列表，点击"Netlab测试工具"![netlab所在位置](https://docs.openLuat.com/cdn/image/socket/netlab_local.png)，点击 打开TCP 按钮，会创建一个TCP server，将server的地址和端口赋值给tcp_client_main.lua中的SERVER_ADDR和SERVER_PORT两个变量

3、PC端浏览器访问[合宙TCP/UDP web测试工具](https://iot.luatos.com/#/page6/netlab)；登陆成功后点击"工具等"，进入工具列表，点击"Netlab测试工具"![netlab所在位置](https://docs.openLuat.com/cdn/image/socket/netlab_local.png)，点击 打开UDP 按钮，会创建一个UDP server，将server的地址和端口赋值给udp_client_main.lua中的SERVER_ADDR和SERVER_PORT两个变量

4、PC端浏览器访问[合宙TCP/UDP web测试工具](https://iot.luatos.com/#/page6/netlab)；登陆成功后点击"工具等"，进入工具列表，点击"Netlab测试工具"![netlab所在位置](https://docs.openLuat.com/cdn/image/socket/netlab_local.png)，点击 打开TCP SSL 按钮，会创建一个TCP SSL server，将server的地址和端口赋值给tcp_ssl_main.lua中的SERVER_ADDR和SERVER_PORT两个变量

5、demo脚本代码netdrv_device.lua中，默认使用4G网卡 `require "netdrv_4g"`

6、Luatools烧录内核固件和修改后的demo脚本代码

7、烧录成功后，自动开机运行

8、[合宙TCP/UDP web测试工具](https://iot.luatos.com/#/page6/netlab)上创建的TCP server、UDP server、TCP SSL server，一共三个server，可以看到有设备连接上来，每隔5秒钟，会接收到一段类似于 send from timer: 1 的数据，最后面的数字每次加1，类似于以下效果：

``` lua
[2025-06-24 16:47:39.085]send from timer: 1
73656E642066726F6D2074696D65723A2031

[2025-06-24 16:47:43.247]send from timer: 2
73656E642066726F6D2074696D65723A2032

[2025-06-24 16:47:48.241]send from timer: 3
73656E642066726F6D2074696D65723A2033
```

9、[合宙TCP/UDP web测试工具](https://iot.luatos.com/#/page6/netlab)上创建的TCP server、UDP server、TCP SSL server，一共三个server，每隔30秒钟，会接收到一段符合AirCloud格式的数据，类似于以下效果：

``` json
[ { "value": 31, "data_type": 0, "field_meaning": 782 }, { "value": "898608751025C0771365", "data_type": 3, "field_meaning": 783 }, { "value": 1774529029, "data_type": 0, "field_meaning": 1280 }, { "value": "863434088224404", "data_type": 3, "field_meaning": 798 }, { "value": "29.0000000", "data_type": 1, "field_meaning": 256 }, { "value": "3.7309999", "data_type": 0, "field_meaning": 799 }, { "value": "用户utf-8格式自定义数据", "data_type": 5, "field_meaning": 0 } ]
7
```

10、在[合宙TCP/UDP web测试工具](https://iot.luatos.com/#/page6/netlab)的发送编辑框内，输入一段数据，点击发送，可以在日志中看到由对应server发来的数据。

11、注意：第四路连接，连接的是baidu的https网站，连接成功后，Air8201每隔一段时间发数据给服务器，因为发送的不是http合法格式的数据，所以每隔一段时间服务器都会主动断开连接，断开连接后，Air8201会自动重连，如此循环，属于正常现象。
