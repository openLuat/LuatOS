## 功能模块介绍

1、main.lua：主程序入口；

2、netdrv_device.lua：网卡驱动设备，可以配置使用netdrv文件夹内的四种网卡(4g airlink网卡，wifi airlink网卡，单spi以太网卡，多网卡)中的任何一种网卡；

3、tcp文件夹：tcp client连接以及数据收发处理逻辑；

4、udp文件夹：udp client连接以及数据收发处理逻辑；

5、tcp_ssl文件夹：tcp ssl client连接以及数据收发处理逻辑；

6、tcp_ssl_ca文件夹：tcp ssl client单向认证连接以及数据收发处理逻辑；

7、network_watchdog.lua：网络环境检测看门狗；

8、timer_app.lua：通知四个client定时发送数据到服务器；

9、uart_app.lua：在四个client和uart外设之间透传数据；


## 系统消息介绍

1、"IP_READY"：某种网卡已经获取到ip信息，仅仅获取到了ip信息，能否和外网连通还不确认；

2、"IP_LOSE"：某种网卡已经掉网；


## 用户消息介绍

1、"RECV_DATA_FROM_SERVER"：socket client收到服务器下发的数据后，通过此消息发布出去，给其他应用模块处理；

2、"SEND_DATA_REQ"：其他应用模块发布此消息，通知socket client发送数据给服务器；

3、"FEED_NETWORK_WATCHDOG"：网络环境检测看门狗的喂狗消息，在需要喂狗的地方发布此消息；


## 演示功能概述

1、创建四路socket连接，在目录中对应四个文件夹详情如下

- TCP文件夹功能为创建一个tcp client，连接tcp server；

- UDP文件夹功能为创建一个udp client，连接udp server；

- TCP_SSL文件夹功能为创建一个tcp ssl client，连接tcp ssl server，不做证书校验；

- TCP_SSL_CA文件夹功能为创建一个tcp ssl client，连接tcp ssl server，client仅单向校验server的证书，server不校验client的证书和密钥文件；

2、每一路socket连接出现异常后，自动重连；

3、每一路socket连接，client按照以下几种逻辑发送数据给server

- 串口应用功能模块uart_app.lua，通过uart1接收到串口数据，将串口数据增加send from uart: 前缀后发送给server；

- 定时器应用功能模块timer_app.lua，定时产生数据，将数据增加send from timer：前缀后发送给server；

4、每一路socket连接，client收到server数据后，将数据增加recv from tcp/udp/tcp ssl/tcp ssl ca（四选一）server: 前缀后，通过uart1发送出去；

5、启动一个网络业务逻辑看门狗task，用来监控网络环境，如果连续长时间工作不正常，重启整个软件系统；

6、netdrv_device：配置连接外网使用的网卡，目前支持以下四种选择（四选一）

   (1) netdrv_4g：4G网卡

   (2) netdrv_wifi：WIFI STA网卡

   (3) netdrv_eth_spi：通过SPI外挂CH390H芯片的以太网卡

   (4) netdrv_multiple：支持以上三种网卡，可以配置三种网卡的优先级




## 演示硬件环境

![](https://docs.openLuat.com/cdn/image/1601-tcp.jpg)

1、Air1601开发板一块+可上网的sim卡一张+网线一根：

- sim卡插入开发板的sim卡槽

- 网线一端插入开发板网口，另外一端连接可以上外网的路由器网口

2、TYPE-C USB数据线两根 + USB转ttl工具一个+三根杜邦线，Air1601开发板和数据线的硬件接线方式为：

- Air1601开发板通过USB口供电；

- TYPE-C USB数据线直接插到开发板的USB1口(串口下载)座子，另外一端连接电脑USB口；

拨码开关位置请参考如下文档串口烧录章节[1601开发板使用说明](https://docs.openluat.com/air1601/product/file/Air1601%E5%BC%80%E5%8F%91%E6%9D%BF%E4%BD%BF%E7%94%A8%E8%AF%B4%E6%98%8E.pdf)

- USB转串口数据线，接线方式如下；

<table>
<tr>
<td>Air1601开发板<br/></td><td>usb转ttl配件板<br/></td></tr>
<tr>
<td>uart1 tx<br/></td><td>rxd<br/></td></tr>
<tr>
<td>uart1 rx<br/></td><td>txd<br/></td></tr>
<tr>
<td>gnd<br/></td><td>gnd<br/></td></tr>
<tr>
</table>

3、使用4g airlink网络接线方式请参考如下文档4g章节[1601开发板使用说明](https://docs.openluat.com/air1601/product/file/Air1601%E5%BC%80%E5%8F%91%E6%9D%BF%E4%BD%BF%E7%94%A8%E8%AF%B4%E6%98%8E.pdf)

4、使用以太网网络接线方式请参考如下文档以太网章节[1601开发板使用说明](https://docs.openluat.com/air1601/product/file/Air1601%E5%BC%80%E5%8F%91%E6%9D%BF%E4%BD%BF%E7%94%A8%E8%AF%B4%E6%98%8E.pdf)

## 演示软件环境

1、Luatools下载调试工具

2、[Air1601 V1010版本固件）](https://docs.openluat.com/air1601/luatos/firmware/)（理论上，2026年4月16日之后发布的固件都可以）

3、PC端的串口工具，例如SSCOM、LLCOM等都可以；

4、PC端浏览器访问[合宙TCP/UDP web测试工具](https://iot.luatos.com/#/page6/netlab)；

详细使用说明参考：[合宙 TCP/UDP web 测试工具使用说明](https://docs.openluat.com/TCPUDP_Test/) 。

## 演示核心步骤


1、搭建好硬件环境

2、PC端浏览器访问[合宙TCP/UDP web测试工具](https://iot.luatos.com/#/page6/netlab)，点击 打开TCP 按钮，会创建一个TCP server，将server的地址和端口赋值给tcp_client_main.lua中的SERVER_ADDR和SERVER_PORT两个变量

3、PC端浏览器访问[合宙TCP/UDP web测试工具](https://iot.luatos.com/#/page6/netlab)，点击 打开UDP 按钮，会创建一个UDP server，将server的地址和端口赋值给udp_client_main.lua中的SERVER_ADDR和SERVER_PORT两个变量

4、PC端浏览器访问[合宙TCP/UDP web测试工具](https://iot.luatos.com/#/page6/netlab)，点击 打开TCP SSL 按钮，会创建一个TCP SSL server，将server的地址和端口赋值给tcp_ssl_main.lua中的SERVER_ADDR和SERVER_PORT两个变量

5、demo脚本代码netdrv_device.lua中，按照自己的网卡需求启用对应的Lua文件

- 如果需要单4G网卡，打开require "netdrv_4g"，其余注释掉

- 如果需要单WIFI STA网卡，打开require "netdrv_wifi"，其余注释掉；同时netdrv_wifi.lua中的exnetif.set_priority_order函数里面的ssid和password，修改为自己测试时wifi热点的名称和密码；注意：仅支持2.4G的wifi，不支持5G的wifi

- 如果需要以太网卡，打开require "netdrv_eth_spi"，其余注释掉

- 如果需要多网卡，打开require "netdrv_multiple"，其余注释掉；同时netdrv_multiple.lua中的ssid = "茶室-降功耗,找合宙!", password = "Air123456", 修改为自己测试时wifi热点的名称和密码；注意：仅支持2.4G的wifi，不支持5G的wifi

6、Luatools烧录内核固件和修改后的demo脚本代码

7、烧录成功后，自动开机运行

8、[合宙TCP/UDP web测试工具](https://iot.luatos.com/#/page6/netlab)上创建的TCP server、UDP server、TCP SSL server，一共三个server，可以看到有设备连接上来，每隔5秒钟，会接收到一段类似于 send from timer: 1 的数据，最后面的数字每次加1，每6s后会收到一个符合aircloud协议的TLV自定义数据，类似于以下效果：

``` lua
[2026-04-16 08:51:02.286]send from timer: 1
73656E642066726F6D2074696D65723A2031

[2026-04-16 08:51:09.411]send from timer: 2
73656E642066726F6D2074696D65723A2032

[2026-04-16 08:51:14.456]send from timer: 3
73656E642066726F6D2074696D65723A2033

[2026-04-16 08:51:19.516]send from timer: 4
73656E642066726F6D2074696D65723A2034

[2026-04-16 08:51:24.576]send from timer: 5
73656E642066726F6D2074696D65723A2035

[2026-04-16 08:51:29.635]send from timer: 6
73656E642066726F6D2074696D65723A2036

[2026-04-16 08:51:31.326]
send from Aircloud_main: [{"value":946684804,"data_type":0,"field_meaning":1280},{"value":-0.0010000,"data_type":1,"field_meaning":256},{"value":-0.0010000,"data_type":0,"field_meaning":799},{"value":"用户utf-8格式自定义数据","data_type":5,"field_meaning":0}]
73656E642066726F6D20416972636C6F75645F6D61696E3A205B7B2276616C7565223A3934363638343830342C22646174615F74797065223A302C226669656C645F6D65616E696E67223A313238307D2C7B2276616C7565223A2D302E303031303030302C22646174615F74797065223A312C226669656C645F6D65616E696E67223A3235367D2C7B2276616C7565223A2D302E303031303030302C22646174615F74797065223A302C226669656C645F6D65616E696E67223A3739397D2C7B2276616C7565223A22E794A8E688B77574662D38E6A0BCE5BC8FE887AAE5AE9AE4B989E695B0E68DAE222C22646174615F74797065223A352C226669656C645F6D65616E696E67223A307D5D
```


9、打开PC端的串口工具，选择对应的端口，配置波特率115200，数据位8，停止位1，无奇偶校验位；

10、PC端的串口工具输入一段数据，点击发送，在[合宙TCP/UDP web测试工具](https://iot.luatos.com/#/page6/netlab)上的四个server页面都可以接收到数据，类似于以下效果：

``` lua
[2026-04-16 08:53:45.863]send from uart: 111
73656E642066726F6D20756172743A203131310D0A
```

11、在[合宙TCP/UDP web测试工具](https://iot.luatos.com/#/page6/netlab)的发送编辑框内，输入一段数据，点击发送，在PC端的串口工具上可以接收到这段数据，并且也能看到是哪一个server发送的，类似于以下效果：

``` lua
tcp_client_receiver.proc recv data len 8
udp_client_receiver.proc recv data len 5 
tcp_ssl_receiver.proc recv data len 4
```

12、注意：第四路连接，连接的是baidu的https网站，连接成功后，Air1601每隔一段时间发数据给服务器，因为发送的不是http合法格式的数据，所以每隔一段时间服务器都会主动断开连接，断开连接后，Air1601会自动重连，如此循环，属于正常现象。
