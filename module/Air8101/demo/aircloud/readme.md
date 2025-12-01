## 功能模块介绍

1、main.lua：主程序入口；

2、netdrv_device.lua：网卡驱动设备，可以配置使用netdrv文件夹内的四种网卡(单4g网卡，单spi以太网卡，单pc模拟器网卡，多网卡)中的任何一种网卡；

3、excloud.lua： aircloud的实现库

4、excloud_test.lua：aircloud的应用模块，实现了aircloud的应用场景。

## 演示功能概述

使用Air8101核心板测试aircloud功能

AirCloud 概述:AirCloud 是 LuatOS 物联网设备云服务通信协议，提供设备连接、数据上报、远程控制和文件上传等核心功能。excloud 扩展库是 AirCloud 协议的实现，通过该库设备可以快速接入云服务平台，实现远程监控和管理。

本demo演示了excloud扩展库的完整使用流程，包括：
1. 设备连接与认证
2. 数据上报与接收
3. 运维日志管理
4. 文件上传功能
5. 心跳保活机制

## 演示硬件环境

![](https://docs.openluat.com/air8101/luatos/app/image/netdrv_multi.jpg)

1、Air8101核心板一块

2、TYPE-C USB数据线一根

3、Air8101核心板和数据线的硬件接线方式为

- Air8101核心板通过TYPE-C USB口供电；（核心板背面的功耗测试开关拨到OFF一端）

- 如果测试发现软件频繁重启，重启原因值为：poweron reason 0，可能是供电不足，此时再通过直流稳压电源对核心板的vbat管脚进行4V供电，或者VIN管脚进行5V供电；

- TYPE-C USB数据线直接插到核心板的TYPE-C USB座子，另外一端连接电脑USB口；


4、可选AirPHY_1000配件板一块，Air8101核心板和AirPHY_1000配件板的硬件接线方式为:

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

5、可选AirETH_1000配件板一块，Air8101核心板和AirETH_1000配件板的硬件接线方式为:

| Air8101核心板 | AirETH_1000配件板 |
| ------------- | ----------------- |
| 59/3V3        | 3.3v              |
| gnd           | gnd               |
| 28/DCLK       | SCK               |
| 54/DISP       | CSS               |
| 55/HSYN       | SDO               |
| 57/DE         | SDI               |
| 14/GPIO8      | INT               |


## 演示软件环境

1、Luatools下载调试工具

2、[Air8101 V1006版本固件](https://docs.openluat.com/air8101/luatos/firmware/)

## 演示核心步骤

1、搭建好硬件环境

2、demo脚本代码netdrv_device.lua中，按照自己的网卡需求启用对应的Lua文件

- 如果需要单WIFI STA网卡，打开require "netdrv_wifi"，其余注释掉；同时netdrv_wifi.lua中的wlan.connect("茶室-降功耗,找合宙!", "Air123456", 1)，前两个参数，修改为自己测试时wifi热点的名称和密码；注意：仅支持2.4G的wifi，不支持5G的wifi

- 如果需要RMII以太网卡，打开require "netdrv_eth_rmii"，其余注释掉

- 如果需要SPI以太网卡，打开require "netdrv_eth_spi"，其余注释掉

- 如果需要单4G网卡，打开require "netdrv_4g"，其余注释掉

- 如果需要多网卡，打开require "netdrv_multiple"，其余注释掉；同时netdrv_multiple.lua中的ssid = "茶室-降功耗,找合宙!", password = "Air123456", 修改为自己测试时wifi热点的名称和密码；注意：仅支持2.4G的wifi，不支持5G的wifi

3、修改excloud_test.lua文件中excloud.setup接口的相关参数，根据自己需求配置连接协议、是否启用运维日志、项目key、设备类型，是否启用getip等内容。

4、烧录好后，板子开机同时在luatools上查看日志：

```lua
[2025-11-24 17:34:43.669] $luat:I(125):pm:reset native reason: 0
[2025-11-24 17:34:43.669] luat:D(125):pm:boot up by power on
[2025-11-24 17:34:43.669] luat:D(126):pm:poweron reason 0
[2025-11-24 17:34:43.669] luat:D(126):main:STA MAC: C8C2C68C5D3E
[2025-11-24 17:34:43.669] luat:D(126):main:AP  MAC: C8C2C68C5D3F
[2025-11-24 17:34:43.669] luat:D(126):main:BLE MAC: C8C2C68C5D40
[2025-11-24 17:34:43.669] luat:D(126):main:ETH MAC: C8C2C68C5D41
[2025-11-24 17:34:43.669] luat:D(126):main:io voltage set to 3.3V
[2025-11-24 17:34:43.669] luat:I(131):main:LuatOS@Air8101 base 25.03 bsp V1006 32bit
[2025-11-24 17:34:43.669] luat:I(131):main:ROM Build: Aug 31 2025 19:38:24
[2025-11-24 17:34:43.669] luat:D(137):main:loadlibs luavm 1572856 16936 16936
[2025-11-24 17:34:43.669] luat:D(138):main:loadlibs sys   181304 74216 86240
[2025-11-24 17:34:43.669] luat:D(138):main:loadlibs psram 1572864 46632 46712
[2025-11-24 17:34:44.153] luat:U(589):W/user.excloud_task_func wait IP_READY 2 2
[2025-11-24 17:34:44.153] luat:D(594):wlan:event_module 1 event_id 4
[2025-11-24 17:34:45.085] luat:D(1521):wlan:event_module 1 event_id 4
[2025-11-24 17:34:45.163] luat:U(1590):W/user.excloud_task_func wait IP_READY 2 2
[2025-11-24 17:34:45.881] luat:D(2310):wlan:event_module 1 event_id 3
[2025-11-24 17:34:45.881] luat:D(2310):wlan:STA connected vivox200 
[2025-11-24 17:34:45.881] luat:D(2310):DHCP:dhcp state 6 2310 0 0
[2025-11-24 17:34:45.881] luat:D(2311):DHCP:dhcp discover C8C2C68C5D3E
[2025-11-24 17:34:45.881] luat:I(2311):ulwip:adapter 2 dhcp payload len 308
[2025-11-24 17:34:46.145] luat:U(2589):W/user.excloud_task_func wait IP_READY 2 2
[2025-11-24 17:34:46.693] luat:U(3146):I/user.mem.lua 1572856 188432 189696
[2025-11-24 17:34:46.693] luat:U(3147):I/user.mem.sys 181304 83512 86960
[2025-11-24 17:34:46.881] luat:D(3309):DHCP:dhcp state 7 3309 0 0
[2025-11-24 17:34:46.881] luat:D(3310):DHCP:long time no offer, resend
[2025-11-24 17:34:46.881] luat:I(3310):ulwip:adapter 2 dhcp payload len 308
[2025-11-24 17:34:46.881] luat:D(3321):ulwip:收到DHCP数据包(len=310)
[2025-11-24 17:34:46.881] luat:D(3322):DHCP:dhcp state 7 3322 0 0
[2025-11-24 17:34:46.881] luat:D(3322):DHCP:find ip 7718a8c0 192.168.24.119
[2025-11-24 17:34:46.881] luat:D(3322):DHCP:result 2
[2025-11-24 17:34:46.931] luat:D(3322):DHCP:select offer, wait ack
[2025-11-24 17:34:46.931] luat:I(3322):ulwip:adapter 2 dhcp payload len 302
[2025-11-24 17:34:46.931] luat:D(3339):ulwip:收到DHCP数据包(len=310)
[2025-11-24 17:34:46.931] luat:D(3340):DHCP:dhcp state 9 3340 0 0
[2025-11-24 17:34:46.931] luat:D(3340):DHCP:find ip 7718a8c0 192.168.24.119
[2025-11-24 17:34:46.931] luat:D(3340):DHCP:result 5
[2025-11-24 17:34:46.931] luat:D(3340):DHCP:DHCP get ip ready
[2025-11-24 17:34:46.931] luat:D(3340):ulwip:adapter 2 ip 192.168.24.119
[2025-11-24 17:34:46.931] luat:D(3340):ulwip:adapter 2 mask 255.255.255.0
[2025-11-24 17:34:46.931] luat:D(3340):ulwip:adapter 2 gateway 192.168.24.212
[2025-11-24 17:34:46.931] luat:D(3340):ulwip:adapter 2 lease_time 3599s
[2025-11-24 17:34:46.931] luat:D(3340):ulwip:adapter 2 DNS1:192.168.24.212
[2025-11-24 17:34:46.931] luat:D(3340):netdrv:exec wifi_netif_notify_sta_got_ip
[2025-11-24 17:34:46.931] luat:D(3341):net:network ready 2, setup dns server
[2025-11-24 17:34:46.931] luat:D(3341):ulwip:IP_READY 2 192.168.24.119
[2025-11-24 17:34:46.931] luat:U(3343):I/user.netdrv_wifi.ip_ready_func IP_READY {"gw":"192.168.24.212","rssi":-44,"bssid":"DA04CBA995AB"}
[2025-11-24 17:34:46.931] luat:D(3346):lfs:init ok
[2025-11-24 17:34:46.931] luat:U(3352):I/user.exmtn 读取索引 1
[2025-11-24 17:34:46.931] luat:U(3353):I/user.exmtn 读取块数配置 1
[2025-11-24 17:34:46.931] luat:U(3353):I/user.exmtn 读取写入方式配置 1
[2025-11-24 17:34:46.931] luat:U(3353):I/user.exmtn 配置变化 false
[2025-11-24 17:34:46.931] luat:U(3354):I/user.exmtn 配置未变化，文件存在，继续写入
[2025-11-24 17:34:46.931] luat:U(3364):I/user.exmtn 初始化成功: 每个文件 4.00 KB (1 块 × 4096 字节), 总空间 16.00 KB (4 个文件)
[2025-11-24 17:34:46.931] luat:U(3364):I/user.[excloud]运维日志初始化成功
[2025-11-24 17:34:46.931] luat:U(3364):I/user.[excloud]excloud.setup 初始化成功 设备ID: C8C2C68C5D3E
[2025-11-24 17:34:46.931] luat:U(3364):I/user.excloud初始化成功
[2025-11-24 17:34:46.931] luat:U(3364):I/user.[excloud]首次连接，获取服务器信息...
[2025-11-24 17:34:46.931] luat:U(3365):I/user.[excloud]excloud.getip 类型: 3 key: VmhtOb81EgZau6YyuuZJzwF6oUNGCbXi-C8C2C68C5D3E
[2025-11-24 17:34:46.931] luat:D(3367):socket:connect to gps.openluat.com,443
[2025-11-24 17:34:46.931] luat:D(3367):DNS:gps.openluat.com state 0 id 1 ipv6 0 use dns server0, try 0
[2025-11-24 17:34:46.931] luat:D(3367):net:adatper 2 dns server 192.168.24.212
[2025-11-24 17:34:46.931] luat:D(3368):net:dns udp sendto 192.168.24.212:53 from 192.168.24.119
[2025-11-24 17:34:46.931] luat:D(3370):wlan:event_module 2 event_id 0
[2025-11-24 17:34:46.931] luat:I(3378):DNS:dns all done ,now stop
[2025-11-24 17:34:46.931] luat:D(3378):net:connect 1.94.5.143:443 TCP
[2025-11-24 17:34:47.235] luat:U(3670):I/user.mtn_test 4
[2025-11-24 17:34:47.290] luat:U(3720):I/user.httpplus 等待服务器完成响应
[2025-11-24 17:34:47.696] luat:U(4123):I/user.httpplus 等待服务器完成响应
[2025-11-24 17:34:47.696] luat:U(4125):I/user.httpplus 服务器已完成响应,开始解析响应
[2025-11-24 17:34:47.715] luat:U(4140):I/user.[excloud]excloud.getip响应 HTTP Code: 200 Body: luat:U(4140):{"msg":"ok","conninfo":{"ipv4":"124.71.128.165","port":9108},"imginfo":{"url":"https://gps.openluat.com/iot/aircloud/upload/image","data_key":"f","data_param":{"key":"Wx3EpbWaMnFSnfLnSpLACxURCUiX66HMAdD8VW","tip":""}},"audinfo":{"url":"https://gps.openluat.com/iot/aircloud/upload/audio","data_key":"f","data_param":{"key":"Wx3EpbWaMnFSnfLnSpLACxURCUiX66HMAdD8VW","tip":""}},"mtninfo":{"url":"https://gps.openluat.com/iot/aircloud/upload/file","data_key":"f","data_param":{"key":"Wx3EpbWaMnFSnfLnSpLACxURCUiX66HMAdD8VW","tip":""}}}luat:U(4140):
[2025-11-24 17:34:47.715] luat:U(4140):I/user.[excloud]excloud.getip响应 HTTP Code: 200 Body: luat:U(4140):{"msg":"ok","conninfo":{"ipv4":"124.71.128.165","port":9108},"imginfo":{"url":"https://gps.openluat.com/iot/aircloud/upload/image","data_key":"f","data_param":{"key":"Wx3EpbWaMnFSnfLnSpLACxURCUiX66HMAdD8VW","tip":""}},"audinfo":{"url":"https://gps.openluat.com/iot/aircloud/upload/audio","data_key":"f","data_param":{"key":"Wx3EpbWaMnFSnfLnSpLACxURCUiX66HMAdD8VW","tip":""}},"mtninfo":{"url":"https://gps.openluat.com/iot/aircloud/upload/file","data_key":"f","data_param":{"key":"Wx3EpbWaMnFSnfLnSpLACxURCUiX66HMAdD8VW","tip":""}}}luat:U(4141):
[2025-11-24 17:34:47.715] luat:U(4142):I/user.[excloud]获取到TCP/UDP连接信息 host: 124.71.128.165 port: 9108
[2025-11-24 17:34:47.715] luat:U(4142):I/user.[excloud]获取到图片上传信息
[2025-11-24 17:34:47.715] luat:U(4143):I/user.[excloud]获取到音频上传信息
[2025-11-24 17:34:47.715] luat:U(4143):I/user.[excloud]获取到运维日志上传信息
[2025-11-24 17:34:47.715] luat:U(4143):I/user.[excloud]excloud.getip 更新配置: 124.71.128.165 9108
[2025-11-24 17:34:47.715] luat:U(4143):I/user.[excloud]excloud.getip 成功: true 结果: {"ipv4":"124.71.128.165","port":9108}
[2025-11-24 17:34:47.715] luat:U(4144):I/user.[excloud]服务器信息获取成功 host: 124.71.128.165 port: 9108 transport: tcp
[2025-11-24 17:34:47.715] luat:U(4144):I/user.[excloud]创建TCP连接
[2025-11-24 17:34:47.715] luat:D(4145):socket:connect to 124.71.128.165,9108
[2025-11-24 17:34:47.715] luat:U(4145):network_socket_connect 1578:network 0 local port auto select 51282
[2025-11-24 17:34:47.715] luat:D(4145):net:connect 124.71.128.165:9108 TCP
[2025-11-24 17:34:47.715] luat:U(4146):I/user.[excloud]TCP连接结果 true false
[2025-11-24 17:34:47.715] luat:U(4147):I/user.[excloud]excloud service started
[2025-11-24 17:34:47.715] luat:U(4147):I/user.excloud服务已开启
[2025-11-24 17:34:47.715] luat:U(4147):I/user.[excloud]excloud 自动心跳已启动，间隔 300 秒
[2025-11-24 17:34:47.715] luat:U(4148):I/user.自动心跳已启动
[2025-11-24 17:34:47.849] luat:U(4197):network_default_socket_callback 1103:before process socket 1,event:0xf2000009(连接成功),state:3(正在连接),wait:2(等待连接完成)
[2025-11-24 17:34:47.849] luat:U(4197):network_default_socket_callback 1107:after process socket 1,state:5(在线),wait:0(无等待)
[2025-11-24 17:34:47.849] luat:U(4199):I/user.[excloud]socket cb userdata: 60C58268 33554449 0
[2025-11-24 17:34:47.849] luat:U(4200):I/user.[excloud]socket TCP连接成功
[2025-11-24 17:34:47.849] luat:U(4200):I/user.用户回调函数 connect_result {"success":true}
[2025-11-24 17:34:47.849] luat:U(4200):I/user.连接成功
[2025-11-24 17:34:47.849] luat:U(4201):I/user.[excloud]构建发送数据 16 3 VmhtOb81EgZau6YyuuZJzwF6oUNGCbXi-C8C2C68C5D3E-54540D4935 
[2025-11-24 17:34:47.849] luat:U(4201):I/user.[excloud]tlv发送数据长度4 60
[2025-11-24 17:34:47.849] luat:U(4202):                   I/user.[excloud]构建消息头 luat:U(4203):I/user.[excloud]发送消息长度 16 60 76 0200C8C2C68C5D3E0002003C0000001130100038566D68744F62383145675A617536597975755A4A7A7746366F554E47436258692D4338433243363843354433452D35343534304434393335 152
[2025-11-24 17:34:47.849] luat:U(4205):I/user.用户回调函数 send_result {"sequence_num":1,"success":true,"error_msg":"Send successful"}
[2025-11-24 17:34:47.849] luat:U(4205):I/user.发送成功，流水号: 1
[2025-11-24 17:34:47.849] luat:U(4211):I/user.[excloud]数据发送成功 76 字节
```


