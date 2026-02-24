## 功能模块介绍

1、main.lua：主程序入口

2、netdrv_wifi.lua：连接 WIFI

3、rtmp_app.lua：USB摄像头RTMP推流功能模块

## 演示功能概述

本示例主要是展示 AirCAMERA_1030 的rtmp推流功能

1、 USB 摄像头初始化、帧率配置与H264视频编码

2、通过HTTP请求获取RTMP推流地址

3、连接RTMP服务器并进行视频推流

## 演示硬件环境

1、Air8101 核心板一块

2、TYPE-C USB 数据线一根

3、合宙标准配件 AirCAMERA_1030 配件板 一块

4、Air8101 核心板和合宙标准配件 AirCAMERA_1030 的硬件接线方式为

Air8101 核心板通过 TYPE-C USB 口供电；（背面功耗测试开关拨到 OFF）

TYPE-C USB 数据线直接插到核心板的 TYPE-C USB 座子，另外一端连接电脑 USB 口；

AirCAMERA_1030 配件板与 Air8101核心板连接说明：

将 AirCAMERA_1030 配件板 直接接入 Air8101核心板 的USB接口即可

参考[AirCAMERA_1030 - 合宙模组资料中心](https://docs.openluat.com/accessory/AirCAMERA_1030/)

AirCAMERA_1030 配件板 + AirMICROSD_1000 配件板+ Air8101 核心板，硬件连接示意图：

![](https://docs.openLuat.com/cdn/image/8101_usb_rtmp.jpg)

## 演示软件环境

1、Luatools下载调试工具

2、[Air8101 V2002版本](https://gitee.com/openLuat/LuatOS/tree/master/module/Air8101/core)（理论上最新版本固件也可以，如果使用最新版本的固件不可以，可以烧录V2002-101固件对比验证）

## 演示核心步骤

1、搭建好硬件环境

2、修改rtmp_app.lua中的PostBody参数

3、烧录内核固件和相关demo成功后，自动开机运行。

4、可以看到代码运行结果如下，日志中如果出现以下类似打印则说明rtmp推流成功：

```lua
[2026-01-22 16:54:11.734] lwip:I(3420):[KW:]sta:DHCP_DISCOVER()
[2026-01-22 16:54:11.807] lwip:I(3450):[KW:]sta:DHCP_OFFER received in DHCP_STATE_SELECTING state
[2026-01-22 16:54:11.807] lwip:I(3450):[KW:]sta:DHCP_REQUEST(netif=0x280655b4) en   1
[2026-01-22 16:54:12.212] lwip:I(3886):[KW:]sta:DHCP_ACK received
[2026-01-22 16:54:12.212] wifid:I(3887):[KW:]me dhcp done vif:0
[2026-01-22 16:54:12.212] event:W(3888):event <2 0> has no cb
[2026-01-22 16:54:12.212] ap1:lwip:I(3775):sta ip start
[2026-01-22 16:54:12.212] luat:D(3891):wlan:event_module 1 event_id 2
[2026-01-22 16:54:12.212] luat:D(3891):wlan:STA connected 茶室-降功耗,找合宙! 
[2026-01-22 16:54:12.212] luat:D(3892):wlan:event_module 2 event_id 0
[2026-01-22 16:54:12.212] luat:D(3892):wlan:ipv4 got!! 192.168.31.234
[2026-01-22 16:54:12.212] luat:D(3892):net:network ready 2, setup dns server
[2026-01-22 16:54:12.288] luat:D(3902):wlan:sta ip 192.168.31.234
[2026-01-22 16:54:12.288] luat:D(3902):net:设置DNS服务器 id 2 index 0 ip 223.5.5.5
[2026-01-22 16:54:12.288] luat:D(3902):net:设置DNS服务器 id 2 index 1 ip 114.114.114.114
[2026-01-22 16:54:12.288] luat:U(3903):I/user.netdrv_wifi.ip_ready_func IP_READY 192.168.31.234 255.255.255.0 192.168.31.1 nil
[2026-01-22 16:54:12.288] luat:U(3903):I/user.dnsproxy 开始监听
[2026-01-22 16:54:12.288] luat:U(3904):I/user.打印设备的ID号 C8C2C68C5DEA
[2026-01-22 16:54:12.288] luat:U(3904):I/user.打印的URL http://video.luatos.com:10030/api-system/deviceVideo/get/C8C2C68C5DEA
[2026-01-22 16:54:12.288] luat:I(3905):http:http idp:1
[2026-01-22 16:54:12.288] luat:D(3906):DNS:video.luatos.com state 0 id 1 ipv6 0 use dns server0, try 0
[2026-01-22 16:54:12.288] luat:D(3906):net:adatper 2 dns server 223.5.5.5
[2026-01-22 16:54:12.288] luat:D(3906):net:dns udp sendto 223.5.5.5:53 from 192.168.31.234
[2026-01-22 16:54:12.288] luat:I(3935):DNS:dns all done ,now stop
[2026-01-22 16:54:12.288] luat:D(3935):net:adapter 2 connect 180.152.6.34:10030 TCP
[2026-01-22 16:54:12.288] luat:I(3969):http:http close 0x609c1a68
[2026-01-22 16:54:12.288] luat:U(3972):I/user.打印的请求code 200
[2026-01-22 16:54:12.288] luat:U(3973):I/user.打印的请求body {"msg":"操作成功","code":200,"data":{"urlList":["rtmp://180.152.6.34:1935/stream1live/93ecc063_8d75_4356_82ea_6a78914b649d_0001"],"deviceId":"93ecc063_8d75_4356_82ea_6a78914b649d","deviceChannels":1}}
[2026-01-22 16:54:12.288] luat:U(3974):I/user.请求得到的RTMP地址 rtmp://180.152.6.34:1935/stream1live/93ecc063_8d75_4356_82ea_6a78914b649d_0001
[2026-01-22 16:54:12.288] luat:D(3974):sntp:query ntp.aliyun.com
[2026-01-22 16:54:12.288] luat:D(3975):DNS:ntp.aliyun.com state 0 id 2 ipv6 0 use dns server0, try 0
[2026-01-22 16:54:12.288] luat:D(3975):net:adatper 2 dns server 223.5.5.5
[2026-01-22 16:54:12.288] luat:D(3975):net:dns udp sendto 223.5.5.5:53 from 192.168.31.234
[2026-01-22 16:54:12.288] ap1:pm_ap:E(3862):Invalid gpio_id: 255
[2026-01-22 16:54:12.288] ap1:usb_driv:I(3863):USB_DRV_USB_OPEN!
[2026-01-22 16:54:12.288] ap1:uvc_stre:W(3866):uvc_camera_device_power_on, port:5, device:0
[2026-01-22 16:54:12.288] ap1:uvc_stre:W(3867):uvc_camera_device_power_on, port:5, device:0, ret:-17413
[2026-01-22 16:54:12.543] luat:I(4165):DNS:dns all done ,now stop
[2026-01-22 16:54:12.543] luat:D(4165):net:adapter 2 connect 203.107.6.88:123 UDP
[2026-01-22 16:54:12.543] luat:D(4184):sntp:Unix timestamp: 1769072055
[2026-01-22 16:54:12.842] luat:U(4515):I/user.摄像头初始化 0
[2026-01-22 16:54:12.866] luat:D(4524):rtmp:RTMP上下文创建成功: rtmp://180.152.6.34:1935/stream1live/93ecc063_8d75_4356_82ea_6a78914b649d_0001
[2026-01-22 16:54:12.866] luat:D(4524):rtmp:RTMP回调函数已设置
[2026-01-22 16:54:12.866] luat:U(4525):I/user.开始连接到推流服务器...
[2026-01-22 16:54:17.858] luat:I(9525):rtmp_push:RTMP: State changed from 0 to 1
[2026-01-22 16:54:17.858] luat:D(9525):rtmp:RTMP状态(1)回调消息入队 0x2802d090 0x609a01f0
[2026-01-22 16:54:17.858] luat:D(9526):rtmp:RTMP发起连接请求: 成功
[2026-01-22 16:54:17.858] luat:U(9527):I/user.rtmp 开始推流...
[2026-01-22 16:54:17.858] luat:U(9529):I/user.rtmp状态变化 1
[2026-01-22 16:54:17.939] luat:I(9543):rtmp_push:RTMP: Sending handshake (C0+C1)...
[2026-01-22 16:54:17.939] luat:I(9543):rtmp_push:RTMP: State changed from 1 to 2
[2026-01-22 16:54:17.939] luat:D(9543):rtmp:RTMP状态(2)回调消息入队 0x2802d010 0x609a01f0
[2026-01-22 16:54:17.939] luat:U(9545):I/user.rtmp状态变化 2
[2026-01-22 16:54:17.939] luat:I(9559):rtmp_push:RTMP: Received complete S0+S1 (1537 bytes), sending C2...
[2026-01-22 16:54:17.939] luat:I(9560):rtmp_push:RTMP: C2 sent successfully (exactly 1536 bytes, S1 echo)
[2026-01-22 16:54:18.025] luat:I(9660):rtmp_push:RTMP: Received 1523 bytes after C2, handshake confirmed
[2026-01-22 16:54:18.025] luat:I(9660):rtmp_push:RTMP: command sent successfully: connect (tx_id=1, payload_size=175 bytes)
[2026-01-22 16:54:18.025] luat:I(9660):rtmp_push:RTMP: State changed from 2 to 3
[2026-01-22 16:54:18.025] luat:D(9660):rtmp:RTMP状态(3)回调消息入队 0x2802d080 0x609a01f0
[2026-01-22 16:54:18.025] luat:I(9660):rtmp_push:RTMP: Connect command sent successfully
[2026-01-22 16:54:18.025] luat:U(9661):I/user.rtmp状态变化 3
[2026-01-22 16:54:18.025] luat:U(9662):I/user.rtmp状态变化 已连接到推流服务器
[2026-01-22 16:54:18.025] luat:I(9687):rtmp_push:RTMP: Received Set Chunk Size from server: 60000, updated local chunk_size
[2026-01-22 16:54:18.025] luat:I(9687):rtmp_push:RTMP: Sent setChunkSize: 60000
[2026-01-22 16:54:18.025] luat:I(9687):rtmp_push:RTMP: command sent successfully: releaseStream (tx_id=2, payload_size=70 bytes)
[2026-01-22 16:54:18.025] luat:I(9687):rtmp_push:RTMP: command sent successfully: FCPublish (tx_id=3, payload_size=66 bytes)
[2026-01-22 16:54:18.025] luat:I(9688):rtmp_push:RTMP: command sent successfully: createStream (tx_id=4, payload_size=25 bytes)
[2026-01-22 16:54:18.151] luat:I(9748):rtmp_push:RTMP: command sent successfully: publish (tx_id=5, payload_size=71 bytes)
[2026-01-22 16:54:18.151] luat:I(9788):rtmp_push:RTMP: Metadata payload size: 175 bytes
[2026-01-22 16:54:18.151] luat:I(9788):rtmp_push:RTMP: Metadata @setDataFrame sent successfully
[2026-01-22 16:54:18.151] luat:I(9788):rtmp_push:RTMP: Metadata sent, ready to send video data
[2026-01-22 16:54:18.151] luat:I(9788):rtmp_push:RTMP: State changed from 3 to 4
[2026-01-22 16:54:18.151] luat:D(9788):rtmp:RTMP状态(4)回调消息入队 0x2802cff8 0x609a01f0
[2026-01-22 16:54:18.151] ap1:CAM:W(9673):拍照/录像到文件录 rtmp
[2026-01-22 16:54:18.151] ap1:CAM:W(9674):选定的捕捉模式 6
[2026-01-22 16:54:18.151] ap1:CAM:W(9674):RTMP传输模式
[2026-01-22 16:54:18.151] ap1:uvc_pipe:E(9674):init_encoder_buffer 65 mux_sram_decode_buffer:0x28034200
[2026-01-22 16:54:18.151] luat:U(9792):I/user.rtmp状态变化 4
[2026-01-22 16:54:18.151] luat:U(9792):I/user.rtmp状态变化 已开始推流
[2026-01-22 16:54:18.425] luat:I(9925):rtmp_push:RTMP: Sending IDR frame, len=10887
[2026-01-22 16:54:20.250] luat:I(11919):rtmp_push:RTMP: Sending IDR frame, len=9447
[2026-01-22 16:54:22.322] luat:I(13990):rtmp_push:RTMP: Sending IDR frame, len=10095
[2026-01-22 16:54:22.857] luat:I(14533):rtmp_push:RTMP stats: total=427 kB packets=69 I=3 (29kB) P=66 (182kB) dropped=0 (0kB) queue=0 avg=718 kbps win=0 kbps
[2026-01-22 16:54:24.317] luat:I(15985):rtmp_push:RTMP: Sending IDR frame, len=10895
[2026-01-22 16:54:26.306] luat:I(17984):rtmp_push:RTMP: Sending IDR frame, len=10815
[2026-01-22 16:54:28.306] luat:I(19982):rtmp_push:RTMP: Sending IDR frame, len=8579
[2026-01-22 16:54:30.304] luat:I(21986):rtmp_push:RTMP: Sending IDR frame, len=5071
[2026-01-22 16:54:32.295] luat:I(23981):rtmp_push:RTMP: Sending IDR frame, len=5163
[2026-01-22 16:54:32.856] luat:I(24535):rtmp_push:RTMP stats: total=1582 kB packets=219 I=8 (69kB) P=211 (717kB) dropped=0 (0kB) queue=0 avg=872 kbps win=0 kbps
[2026-01-22 16:54:34.374] luat:I(26043):rtmp_push:RTMP: Sending IDR frame, len=5207
[2026-01-22 16:54:36.357] luat:I(28047):rtmp_push:RTMP: Sending IDR frame, len=5023
[2026-01-22 16:54:38.378] luat:I(30046):rtmp_push:RTMP: Sending IDR frame, len=6807
[2026-01-22 16:54:40.370] luat:I(32045):rtmp_push:RTMP: Sending IDR frame, len=11759
[2026-01-22 16:54:42.371] luat:I(34043):rtmp_push:RTMP: Sending IDR frame, len=8423
[2026-01-22 16:54:42.870] luat:I(34540):rtmp_push:RTMP stats: total=2973 kB packets=368 I=13 (105kB) P=355 (1376kB) dropped=0 (0kB) queue=0 avg=979 kbps win=0 kbps

```

## 合宙音视频后台查看

打开[合宙视频物联网大数据平台](https://video.luatos.com:8083/login?redirect=/real-time)
输入自己的IOT账号和密码然后输入验证码，点击登录

![](https://docs.openLuat.com/cdn/image/8101_rtmp_1.jpg)

新增设备

![](https://docs.openLuat.com/cdn/image/8101_rtmp_2.jpg)

![](https://docs.openLuat.com/cdn/image/8101_rtmp_3.jpg)

查看推流视频

![](https://docs.openLuat.com/cdn/image/8101_rtmp_4.jpg)
