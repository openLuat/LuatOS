## 功能模块介绍

1、main.lua：主程序入口，负责加载 ipv6_info 模块与各协议示例模块（socket/http/mqtt）；

2、ipv6_info.lua：IPv6 功能模块，负责开启 IPv6、查询并打印本机 IPv6 地址，就绪后发布 IPV6_READY 消息；

3、socket_ipv6.lua：TCP client 使用 IPv6 连接服务器的示例，每分钟发送一条 "hello world"；

4、http_ipv6.lua：httpplus 使用 IPv6 发起 HTTP GET 请求的示例，请求一次即结束；

5、mqtt_ipv6.lua：mqtt 使用 IPv6 连接 broker 的示例，每5秒发布一条 "Hello world"；

## 演示功能概述

1、ipv6_info：演示以下几种应用场景的使用方式

- 通过 mobile.ipv6(true) 开启 IPv6（须在 LTE 连接前设置）；
- 联网后通过 socket.localIP() 查询并打印本机 IPv4 / IPv6 地址；
- 地址就绪后发布 IPV6_READY 消息，供各协议示例模块订阅后开始运行；

2、socket_ipv6：演示 TCP client 走 IPv6 连接服务器并周期性通信：

- 订阅 IPV6_READY 后开始连接；
- 通过 libnet.connect 的末参 true 指定走 IPv6；
- 每分钟通过 libnet.tx 发送一条 "hello world"，断开自动重连；

3、http_ipv6：演示 httpplus 优先使用 IPv6 发起一次 HTTP GET 请求：

- 订阅 IPV6_READY 后开始请求；
- 通过 httpplus.request 的 try_ipv6=true 优先尝试 IPv6 地址；
- 请求成功后打印 HTTP 响应码和响应体长度，只请求一次即结束；

4、mqtt_ipv6：演示 mqtt 走 IPv6 连接 broker 并周期性发布消息：

- 订阅 IPV6_READY 后开始连接；
- 通过 mqtt.create 的 opts.ipv6=true 指定走 IPv6；
- 连接成功后订阅下行主题，每5秒向发布主题发送一条 "Hello world"，断开自动重连；

## 演示硬件环境

1、Air780EHM/Air780EHV/Air780EGH核心板一块 + 可上网且开通 IPv6 的 SIM 卡一张 + 4G天线一根：

- SIM卡插入核心板的SIM卡槽；
- 天线装到核心板上；

2、TYPE-C USB数据线一根，Air780EHM/Air780EHV/Air780EGH核心板和数据线的硬件接线方式为：

- Air780EHM/Air780EHV/Air780EGH核心板通过TYPE-C USB口供电；（外部供电/USB供电 拨动开关 拨到 USB供电一端）
- TYPE-C USB数据线直接插到核心板的TYPE-C USB座子，另外一端连接电脑USB口；

## 演示软件环境

1、Luatools下载调试工具

2、固件获取地址：

[Air780EHM 固件](https://docs.openluat.com/air780ehm/luatos/firmware/version/)

[Air780EHV 固件](https://docs.openluat.com/air780ehv/luatos/firmware/version/)

[Air780EGH 固件](https://docs.openluat.com/air780egh/luatos/firmware/version/)

## 演示核心步骤

### 5.1 http_ipv6 演示步骤

1、硬件准备：Air780EHM/Air780EHV/Air780EGH核心板一块 + 可上网且开通 IPv6 的 SIM 卡一张 + 4G天线一根

2、确保SIM卡已正确插入开发板

3、修改main.lua，启用http_ipv6模块（默认启用）：

```lua
-- 加载 ipv6_info 功能模块（开启 IPv6 + 查询地址 + 发布 IPV6_READY 消息）
require "ipv6_info"

-- 加载协议示例模块（按需启用）
require "http_ipv6"
-- require "socket_ipv6"
-- require "mqtt_ipv6"
```

4、确保http_ipv6.lua顶部的 url 指向一个支持 IPv6 的 HTTP 地址（默认使用清华镜像 IPv6 站点，可改成其他目标）

5、Luatools烧录内核固件和demo脚本代码

6、烧录成功后，自动开机运行，通过串口日志可以观察到以下信息：

- 收到 IPV6_READY 后发起 IPv6 HTTP 请求
- 返回 HTTP 响应码与响应体长度，只请求一次即结束

``` lua
I/http_ipv6 收到 IPV6_READY，准备进行 IPv6 HTTP 请求
I/http_ipv6 发起 HTTP IPv6 请求: https://mirrors6.tuna.tsinghua.edu.cn/help/centos/
I/http_ipv6 HTTP 结果 code: 200
I/http_ipv6 HTTP 请求成功，响应体长度: 1024
```

### 5.2 socket_ipv6 演示步骤

1、硬件准备：Air780EHM/Air780EHV/Air780EGH核心板一块 + 可上网且开通 IPv6 的 SIM 卡一张 + 4G天线一根

2、确保SIM卡已正确插入开发板

3、修改main.lua，启用socket_ipv6模块：

```lua
-- 加载 ipv6_info 功能模块（开启 IPv6 + 查询地址 + 发布 IPV6_READY 消息）
require "ipv6_info"

-- 加载协议示例模块（按需启用）
-- require "http_ipv6"
require "socket_ipv6"
-- require "mqtt_ipv6"
```

4、确保socket_ipv6.lua顶部的 SERVER_ADDR / SERVER_PORT 指向一个支持 IPv6 的 TCP server（默认使用合宙 Netlab 分配的测试服务器，可自行去 https://iot.luatos.com/#/page6/netlab 开一个 TCP server 填写）

5、Luatools烧录内核固件和demo脚本代码

6、烧录成功后，自动开机运行，通过串口日志可以观察到以下信息：

- 收到 IPV6_READY 后开始 IPv6 TCP 连接
- 连接成功并每分钟发送一条 "hello world"
- 断开后自动重连

``` lua
I/socket_ipv6 收到 IPV6_READY，准备进行 IPv6 TCP 连接: 115.120.239.161 22644
I/socket_ipv6 IPv6 TCP 连接成功
I/socket_ipv6 已发送: hello world
I/socket_ipv6 已发送: hello world
```

### 5.3  mqtt_ipv6 演示步骤

1、硬件准备：Air780EHM/Air780EHV/Air780EGH核心板一块 + 可上网且开通 IPv6 的 SIM 卡一张 + 4G天线一根

2、确保SIM卡已正确插入开发板

3、修改main.lua，启用mqtt_ipv6模块：

```lua
-- 加载 ipv6_info 功能模块（开启 IPv6 + 查询地址 + 发布 IPV6_READY 消息）
require "ipv6_info"

-- 加载协议示例模块（按需启用）
-- require "http_ipv6"
-- require "socket_ipv6"
require "mqtt_ipv6"
```

4、确保mqtt_ipv6.lua顶部的 SERVER_ADDR / SERVER_PORT 指向一个支持 IPv6 的 MQTT broker（默认使用合宙官方 MQTT 测试服务器 lbsmqtt.airm2m.com:1884）

5、Luatools烧录内核固件和demo脚本代码

6、烧录成功后，自动开机运行，通过串口日志可以观察到以下信息：

- 收到 IPV6_READY 后开始 IPv6 MQTT 连接
- 连接成功、订阅下行主题，并每5秒发布一条 "Hello world"
- 断开后自动重连

``` lua
I/ipv6_info IPv6功能开启状态: true
I/ipv6_info 等待网络就绪(含IPv6前缀分配)...
I/ipv6_info 网络已就绪，开始查询 IPv6 地址
I/ipv6_info IPv4 地址: 10.19.227.140
I/ipv6_info IPv6 地址: 240A:42BC:2E01:9C7:18CF:A231:83F3:9E7D
I/ipv6_info 已发布 IPV6_READY，其他示例可以开始运行
I/mqtt_client_main_task_func 收到 IPV6_READY，准备进行 IPv6 MQTT 连接
I/mqtt_client_main_task_func recv IP_READY 1 1
dns_run 845:lbsmqtt.airm2m.com state 0 id 27744 ipv6 1 use dns server2, try 0
I/mqtt_client_event_cbfunc MQTTCTRL*: 0C7E8308 conack nil nil
I/mqtt_client_main_task_func waitMsg CONNECT true nil
I/mqtt_client_main_task_func connect success
I/mqtt_client_event_cbfunc MQTTCTRL*: 0C7E8308 suback true 0
I/mqtt_client_main_task_func waitMsg SUBSCRIBE true 0
I/mqtt_client_main_task_func subscribe success qos: 0
I/mqtt_client_event_cbfunc MQTTCTRL*: 0C7E8308 sent 0 nil
I/send_data_cbfunc true timer_helloworld
I/mqtt_client_event_cbfunc MQTTCTRL*: 0C7E8308 recv 862288081583054/down testtest {"dup":0,"message_id":0,"retain":0,"qos":0}
I/mqtt_receiver.data 862288081583054/down testtest
I/send_data_cbfunc true timer_helloworld
I/send_data_cbfunc true timer_helloworld
```
