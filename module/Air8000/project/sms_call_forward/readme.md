# 8000-SMS

## 功能模块介绍：

1、main.lua：主程序入口文件，加载以下 4个文件运行。

2、netdrv_device.lua：网卡驱动设备，可以配置使用netdrv文件夹内的四种网卡(单4g网卡，单wifi网卡，单spi以太网卡，多网卡)中的任何一种网卡；

3、sms_forward.lua： 短信转发功能模块文件

4、cc_forward.lua：来电转发功能模块文件

5、sntp_app.lua：时间同步应用功能模块

6、netdrv_pc：pc模拟器上的网卡

## 演示功能概述：

**sms_forward.lua：**

1、配置飞书，钉钉，企业微信机器人的 webhook 和 secret（加签）。

2、send_sms()，发送短信的功能函数，等待 CC_IND 消息后，手机卡可以进行收发短信。

3、receive_sms()，接收短信处理的功能函数，收到短信后获取来信号码和短信内容，通过回调函数 sms_handler(num, txt)转发到指定的机器人。

**cc_forward.lua：**

1、配置飞书，钉钉，企业微信机器人的 webhook 和 secret（加签）。

2、cc_setup()，初始化电话功能，做好接收来电的准备。

3、cc_state(state)，电话状态判断并获取来电号码，来电或者挂断等不同情况做不同处理。

4、cc_forward()，来电号码信息转发到指定机器人

## 演示硬件环境：

![8000w](https://docs.openluat.com/air8000/luatos/app/image/netdrv_multi.jpg)

1、Air8000开发板一块+可上网的sim卡一张+4g天线一根+wifi天线一根+网线一根：

* sim卡插入开发板的sim卡槽

* 天线装到开发板上

* 网线一端插入开发板网口，另外一端连接可以上外网的路由器网口

2、TYPE-C USB数据线一根 ，Air8000开发板和数据线的硬件接线方式为：

* Air8000开发板通过TYPE-C USB口供电；（外部供电/USB供电 拨动开关 拨到 USB供电一端）

* TYPE-C USB数据线直接插到开发板的TYPE-C USB座子，另外一端连接电脑USB口；

## 演示软件环境：

1、 Luatools 下载调试工具

2、 固件版本：LuatOS-SoC_V2014_Air8000_1，固件地址，如有最新固件请用最新 [https://docs.openluat.com/air8000/luatos/firmware/](https://docs.openluat.com/air8000/luatos/firmware/)

3、 脚本文件：

main.lua

netdrv_device.lua：

sms_forward.lua：

cc_forward.lua：

netdrv文件夹

4、 pc 系统 win11（win10 及以上）

5、飞书，钉钉，企业微信等自己需要的机器人。

## 演示核心步骤：

1、搭建好硬件环境

2、demo脚本代码netdrv_device.lua中，按照自己的网卡需求启用对应的Lua文件

* 如果需要单4G网卡，打开require "netdrv_4g"，其余注释掉

* 如果需要单WIFI STA网卡，打开require "netdrv_wifi"，其余注释掉；同时netdrv_wifi.lua中的wlan.connect("茶室-降功耗,找合宙!", "Air123456", 1)，前两个参数，修改为自己测试时wifi热点的名称和密码；注意：仅支持2.4G的wifi，不支持5G的wifi

* 如果需要以太网卡，打开require "netdrv_eth_spi"，其余注释掉

* 如果需要多网卡，打开require "netdrv_multiple"，其余注释掉；同时netdrv_multiple.lua中的ssid = "茶室-降功耗,找合宙!", password = "Air123456", 修改为自己测试时wifi热点的名称和密码；注意：仅支持2.4G的wifi，不支持5G的wifi

3、[https://open.feishu.cn/document/ukTMukTMukTM/ucTM5YjL3ETO24yNxkjN?lang=zh-CN](https://open.feishu.cn/document/ukTMukTMukTM/ucTM5YjL3ETO24yNxkjN?lang=zh-CN) 参考此教程，获取飞书，钉钉，企业微信的 webhook 和 secret（加签），在 cc_forward.lua 和 sms_forward.lua 脚本中找到 local webhook_feishu，secret_feishu，webhook_dingding，secret_dingding，webhook_weixin 的参数定义，修改为自己的参数。

4、Luatools 烧录内核固件和修改后的 demo 脚本代码

5、此处打开netdrv_device.lua中require "netdrv_multiple"来演示多网卡，优先使用 以太网，其次wifi 网络，最低优先级使用 4G 网络.

注意，netdrv_device.lua中默认使用require "netdrv_4g"，即单4G网卡。

烧录成功后，代码会自动运行，log 日志打印以太网信息， wif 网络信息、CC_READY 等消息，log 日志打印如下：

```yaml
[2025-11-06 11:27:02.399][000000000.643] I/user.main cc_sms_forward 001.000.000
[2025-11-06 11:27:02.405][000000000.655] W/user.cc wait IP_READY 1 3
[2025-11-06 11:27:02.420][000000000.760] I/user.notify_status function
[2025-11-06 11:27:02.433][000000000.762] I/user.初始化以太网
[2025-11-06 11:27:02.442][000000000.762] I/user.config.opts.spi 1 ,config.type 1
[2025-11-06 11:27:02.450][000000000.762] SPI_HWInit 552:spi1 speed 25600000,25600000,12
[2025-11-06 11:27:02.454][000000000.763] I/user.main open spi 0
[2025-11-06 11:27:02.459][000000000.763] D/ch390h 注册CH390H设备(4) SPI id 1 cs 12 irq 255
[2025-11-06 11:27:02.465][000000000.764] D/ch390h adapter 4 netif init ok
[2025-11-06 11:27:02.470][000000000.764] D/netdrv.ch390x task started
[2025-11-06 11:27:02.479][000000000.764] D/ch390h 注册完成 adapter 4 spi 1 cs 12 irq 255
[2025-11-06 11:27:02.486][000000000.765] I/user.以太网初始化完成
[2025-11-06 11:27:02.496][000000000.765] I/user.netdrv 订阅socket连接状态变化事件 Ethernet
[2025-11-06 11:27:02.508][000000000.766] I/user.WiFi名称: Mayadan
[2025-11-06 11:27:02.515][000000000.766] I/user.密码     : 12345678
[2025-11-06 11:27:02.520][000000000.766] I/user.ping_ip  : nil
[2025-11-06 11:27:02.528][000000000.767] I/user.WiFi STA初始化完成
[2025-11-06 11:27:02.539][000000000.767] I/user.netdrv 订阅socket连接状态变化事件 WiFi
[2025-11-06 11:27:02.546][000000000.768] change from 1 to 4
[2025-11-06 11:27:02.556][000000000.783] W/user.sntp_task_func wait IP_READY 4 4
[2025-11-06 11:27:02.561][000000000.831] D/netdrv.ch390x 初始化MAC 3CAB724406AF
[2025-11-06 11:27:02.572][000000001.656] W/user.cc wait IP_READY 4 4
[2025-11-06 11:27:02.579][000000001.761] I/user.4G网卡开始PING
[2025-11-06 11:27:02.590][000000001.762] I/user.dns_request 4G true
[2025-11-06 11:27:02.594][000000001.783] W/user.sntp_task_func wait IP_READY 4 4
[2025-11-06 11:27:02.643][000000002.473] D/airlink wifi sta上线了
[2025-11-06 11:27:02.652][000000002.473] D/netdrv 网卡(2)设置为UP
[2025-11-06 11:27:02.658][000000002.530] D/ulwip adapter 2 dhcp start netif c10d068
[2025-11-06 11:27:02.662][000000002.531] D/DHCP dhcp state 6 tnow 2531 p1 0 p2 0
[2025-11-06 11:27:02.669][000000002.531] D/DHCP dhcp discover C8C2C68CA00E
[2025-11-06 11:27:02.674][000000002.531] I/ulwip adapter 2 dhcp payload len 308
[2025-11-06 11:27:02.678][000000002.611] I/netdrv.ch390x link is up 1 12 100M
[2025-11-06 11:27:02.684][000000002.612] D/netdrv 网卡(4)设置为UP
[2025-11-06 11:27:02.690][000000002.657] W/user.cc wait IP_READY 4 4
[2025-11-06 11:27:02.694][000000002.661] D/ulwip adapter 4 dhcp start netif c1491d4
[2025-11-06 11:27:02.704][000000002.662] D/DHCP dhcp state 6 tnow 2662 p1 0 p2 0
[2025-11-06 11:27:02.716][000000002.662] D/DHCP dhcp discover 3CAB724406AF
[2025-11-06 11:27:02.723][000000002.662] I/ulwip adapter 4 dhcp payload len 308
[2025-11-06 11:27:02.730][000000002.783] W/user.sntp_task_func wait IP_READY 4 4
[2025-11-06 11:27:03.121][000000003.284] D/ulwip 收到DHCP数据包(len=548)
[2025-11-06 11:27:03.130][000000003.284] D/DHCP dhcp state 7 tnow 3284 p1 0 p2 0
[2025-11-06 11:27:03.142][000000003.284] D/DHCP find ip 6600a8c0 192.168.0.102
[2025-11-06 11:27:03.149][000000003.285] D/DHCP result 2
[2025-11-06 11:27:03.155][000000003.285] D/DHCP select offer, wait ack
[2025-11-06 11:27:03.160][000000003.285] I/ulwip adapter 4 dhcp payload len 338
[2025-11-06 11:27:03.167][000000003.291] D/ulwip 收到DHCP数据包(len=548)
[2025-11-06 11:27:03.172][000000003.291] D/DHCP dhcp state 9 tnow 3291 p1 0 p2 0
[2025-11-06 11:27:03.177][000000003.291] D/DHCP find ip 6600a8c0 192.168.0.102
[2025-11-06 11:27:03.183][000000003.292] D/DHCP result 5
[2025-11-06 11:27:03.189][000000003.292] D/DHCP DHCP get ip ready
[2025-11-06 11:27:03.195][000000003.292] D/ulwip adapter 4 ip 192.168.0.102
[2025-11-06 11:27:03.200][000000003.292] D/ulwip adapter 4 mask 255.255.255.0
[2025-11-06 11:27:03.205][000000003.292] D/ulwip adapter 4 gateway 192.168.0.1
[2025-11-06 11:27:03.212][000000003.292] D/ulwip adapter 4 lease_time 7200s
[2025-11-06 11:27:03.217][000000003.292] D/ulwip adapter 4 DNS1:192.168.6.1
[2025-11-06 11:27:03.222][000000003.292] D/ulwip adapter 4 DNS2:192.168.0.1
[2025-11-06 11:27:03.228][000000003.293] D/net network ready 4, setup dns server
[2025-11-06 11:27:03.232][000000003.293] D/netdrv IP_READY 4 192.168.0.102
[2025-11-06 11:27:03.238][000000003.295] W/user.sntp_task_func recv IP_READY
[2025-11-06 11:27:03.243][000000003.295] D/sntp query ntp.aliyun.com
[2025-11-06 11:27:03.248][000000003.295] dns_run 676:ntp.aliyun.com state 0 id 1 ipv6 0 use dns server0, try 0
[2025-11-06 11:27:03.251][000000003.296] D/net adatper 4 dns server 192.168.6.1
[2025-11-06 11:27:03.255][000000003.296] D/net dns udp sendto 192.168.6.1:53 from 192.168.0.102
[2025-11-06 11:27:03.263][000000003.297] I/user.ip_ready_handle 192.168.0.102 Ethernet state 3 gw 192.168.0.1
[2025-11-06 11:27:03.267][000000003.298] I/user.eth_ping_ip nil wifi_ping_ip nil
[2025-11-06 11:27:03.270][000000003.298] I/user.dnsproxy 开始监听
[2025-11-06 11:27:03.279][000000003.299] I/user.cc recv IP_READY 4 4
[2025-11-06 11:27:03.284][000000003.316] dns_run 693:dns all done ,now stop
[2025-11-06 11:27:03.287][000000003.316] D/net adapter 4 connect 203.107.6.88:123 UDP
[2025-11-06 11:27:03.293][000000003.353] D/sntp Unix timestamp: 1762399623
[2025-11-06 11:27:03.298][000000003.355] I/user.sntp_task_func 时间同步成功 本地时间 Thu Nov  6 11:27:03 2025
[2025-11-06 11:27:03.307][000000003.355] I/user.sntp_task_func 时间同步成功 UTC时间 Thu Nov  6 03:27:03 2025
[2025-11-06 11:27:03.314][000000003.356] I/user.sntp_task_func 时间同步成功 RTC时钟(UTC时间) {"year":2025,"min":27,"hour":3,"mon":11,"sec":3,"day":6}
[2025-11-06 11:27:03.325][000000003.356] I/user.sntp_task_func 时间同步成功 本地时间戳 1762399623
[2025-11-06 11:27:03.330][000000003.357] I/user.sntp_task_func 时间同步成功 本地时间os.date() json格式 {"wday":5,"min":27,"yday":310,"hour":11,"isdst":false,"year":2025,"month":11,"sec":3,"day":6}
[2025-11-06 11:27:03.341][000000003.358] I/user.sntp_task_func 时间同步成功 本地时间os.date(os.time()) 1762428423
[2025-11-06 11:27:03.370][000000003.530] D/DHCP dhcp state 7 tnow 3530 p1 0 p2 0
[2025-11-06 11:27:03.377][000000003.531] D/DHCP long time no offer, resend
[2025-11-06 11:27:03.382][000000003.531] I/ulwip adapter 2 dhcp payload len 308
[2025-11-06 11:27:04.358][000000004.530] D/DHCP dhcp state 7 tnow 4530 p1 0 p2 0
[2025-11-06 11:27:04.593][000000004.763] I/user.4G网卡httpdns域名解析失败
[2025-11-06 11:27:04.604][000000004.764] I/user.httpdns baidu.com nil
[2025-11-06 11:27:05.221][000000005.381] D/ulwip 收到DHCP数据包(len=303)
[2025-11-06 11:27:05.236][000000005.382] D/DHCP dhcp state 7 tnow 5382 p1 0 p2 0
[2025-11-06 11:27:05.244][000000005.382] D/DHCP maybe get same ack, drop 62d2b3a0,62d2b3a1
[2025-11-06 11:27:05.247][000000005.382] D/DHCP result 0
[2025-11-06 11:27:05.252][000000005.382] E/ulwip adapter 2 ip4_dhcp_run error -1
[2025-11-06 11:27:05.258][000000005.383] D/ulwip 收到DHCP数据包(len=303)
[2025-11-06 11:27:05.263][000000005.383] D/DHCP dhcp state 7 tnow 5383 p1 0 p2 0
[2025-11-06 11:27:05.268][000000005.383] D/DHCP find ip 8e2ba8c0 192.168.43.142
[2025-11-06 11:27:05.272][000000005.383] D/DHCP result 2
[2025-11-06 11:27:05.280][000000005.384] D/DHCP select offer, wait ack
[2025-11-06 11:27:05.283][000000005.384] I/ulwip adapter 2 dhcp payload len 338
[2025-11-06 11:27:05.287][000000005.397] D/ulwip 收到DHCP数据包(len=333)
[2025-11-06 11:27:05.293][000000005.397] D/DHCP dhcp state 9 tnow 5397 p1 0 p2 0
[2025-11-06 11:27:05.297][000000005.397] D/DHCP find ip 8e2ba8c0 192.168.43.142
[2025-11-06 11:27:05.301][000000005.398] D/DHCP result 5
[2025-11-06 11:27:05.307][000000005.398] D/DHCP DHCP get ip ready
[2025-11-06 11:27:05.311][000000005.398] D/ulwip adapter 2 ip 192.168.43.142
[2025-11-06 11:27:05.315][000000005.398] D/ulwip adapter 2 mask 255.255.255.0
[2025-11-06 11:27:05.318][000000005.398] D/ulwip adapter 2 gateway 192.168.43.1
[2025-11-06 11:27:05.323][000000005.398] D/ulwip adapter 2 lease_time 3600s
[2025-11-06 11:27:05.328][000000005.398] D/ulwip adapter 2 DNS1:192.168.43.1
[2025-11-06 11:27:05.332][000000005.399] D/net network ready 2, setup dns server
[2025-11-06 11:27:05.335][000000005.399] D/netdrv IP_READY 2 192.168.43.142
[2025-11-06 11:27:05.347][000000005.400] I/user.ip_ready_handle 192.168.43.142 WiFi state 3 gw 192.168.43.1
[2025-11-06 11:27:05.352][000000005.401] I/user.eth_ping_ip nil wifi_ping_ip nil
[2025-11-06 11:27:05.357][000000005.401] I/user.dnsproxy 开始监听
[2025-11-06 11:27:07.108][000000007.201] D/mobile cid1, state0
[2025-11-06 11:27:07.113][000000007.201] D/mobile bearer act 0, result 0
[2025-11-06 11:27:07.122][000000007.202] D/mobile NETIF_LINK_ON -> IP_READY
[2025-11-06 11:27:07.128][000000007.203] I/user.ip_ready_handle 10.154.242.60 4G state 1 gw 0.0.0.0
[2025-11-06 11:27:07.135][000000007.203] I/user.eth_ping_ip nil wifi_ping_ip nil
[2025-11-06 11:27:07.141][000000007.204] I/user.dnsproxy 开始监听
[2025-11-06 11:27:07.149][000000007.275] D/mobile TIME_SYNC 0
[2025-11-06 11:27:07.153][000000007.322] soc_cms_proc 2219:cenc report 1,51,1,15
[2025-11-06 11:27:07.341][000000007.504] D/mobile NETIF_LINK_ON -> IP_READY
[2025-11-06 11:27:07.349][000000007.505] I/user.ip_ready_handle 10.154.242.60 4G state 1 gw 0.0.0.0
[2025-11-06 11:27:07.361][000000007.506] I/user.eth_ping_ip nil wifi_ping_ip nil
[2025-11-06 11:27:07.377][000000007.506] I/user.dnsproxy 开始监听
[2025-11-06 11:27:08.591][000000008.764] I/user.Ethernet网卡开始PING
[2025-11-06 11:27:08.599][000000008.765] I/user.dns_request Ethernet true
[2025-11-06 11:27:08.606][000000008.766] D/net adapter 4 connect 223.5.5.5:80 TCP
[2025-11-06 11:27:08.651][000000008.825] I/user.Ethernet网卡httpdns域名解析成功
[2025-11-06 11:27:08.656][000000008.825] I/user.httpdns baidu.com 220.181.7.203
[2025-11-06 11:27:08.660][000000008.826] I/user.设置网卡 Ethernet
[2025-11-06 11:27:08.669][000000008.826] D/net 设置DNS服务器 id 4 index 0 ip 223.5.5.5
[2025-11-06 11:27:08.678][000000008.827] D/net 设置DNS服务器 id 4 index 1 ip 114.114.114.114
[2025-11-06 11:27:08.684][000000008.827] I/user.netdrv_multiple_notify_cbfunc use new adapter Ethernet 4
[2025-11-06 11:27:10.368][000000010.527] D/mobile ims reg state 0
[2025-11-06 11:27:10.381][000000010.528] D/mobile LUAT_MOBILE_EVENT_CC status 0
[2025-11-06 11:27:10.388][000000010.528] D/mobile LUAT_MOBILE_CC_READY
[2025-11-06 11:27:10.392][000000010.529] I/user.发送短信前wait CC_IND
[2025-11-06 11:27:10.402][000000010.530] I/user.现在可以收发短信

```

此处短信演示使用了电信卡，发送"102"给"10001"查询余额，会收到电信回复的短信，并转发到飞书、钉钉和微信，log 打印如下：

```bash
[2025-10-24 18:54:16.756][000000011.691] I/user.现在可以收发短信
[2025-10-24 18:54:16.760][000000011.691] I/user.mobile.number(id) =  nil
[2025-10-24 18:54:16.764][000000011.691] I/user.mobile.iccid(id) =  89860325743780541565
[2025-10-24 18:54:16.768][000000011.692] I/user.mobile.simid(id) =  0
[2025-10-24 18:54:16.772][000000011.692] I/user.mobile.imsi(index) =  460115726670673
[2025-10-24 18:54:16.777][000000011.692] D/sms pdu len 18
[2025-10-24 18:54:16.907][000000011.852] I/user.WiFi网卡开始PING
[2025-10-24 18:54:16.915][000000011.853] I/user.dns_request WiFi true
[2025-10-24 18:54:16.920][000000011.854] D/net adapter 2 connect 223.5.5.5:80 TCP
[2025-10-24 18:54:17.792][000000012.726] luat_sms_proc 1239:[DIO 1239]: CMI_SMS_SEND_MSG_CNF is in
[2025-10-24 18:54:17.799][000000012.726] I/sms long sms callback seqNum = 1
[2025-10-24 18:54:18.476][000000013.409] I/user.WiFi网卡httpdns域名解析成功
[2025-10-24 18:54:18.486][000000013.410] I/user.httpdns baidu.com 220.181.7.203
[2025-10-24 18:54:18.946][000000013.885] luat_sms_proc 1236:[DIO 1236]: CMI_SMS_NEW_MSG_IND is in
[2025-10-24 18:54:18.951][000000013.886] D/sms dcs 2 | 0 | 0 | 0
[2025-10-24 18:54:18.958][000000013.887] I/sms long-sms, wait more frags 1/2
[2025-10-24 18:54:21.469][000000016.410] I/user.4G网卡开始PING
[2025-10-24 18:54:21.480][000000016.410] I/user.dns_request 4G true
[2025-10-24 18:54:21.640][000000016.578] I/user.4G网卡httpdns域名解析成功
[2025-10-24 18:54:21.647][000000016.578] I/user.httpdns baidu.com 220.181.7.203
[2025-10-24 18:54:22.309][000000017.246] luat_sms_proc 1236:[DIO 1236]: CMI_SMS_NEW_MSG_IND is in
[2025-10-24 18:54:22.317][000000017.247] D/sms dcs 2 | 0 | 0 | 0
[2025-10-24 18:54:22.320][000000017.247] I/sms long-sms is ok
[2025-10-24 18:54:22.323][000000017.249] I/user.num是 10001
[2025-10-24 18:54:22.327][000000017.249] I/user.收到来自10001的短信：截止到2025年10月24日18时，本机可用余额:50.63元，帐户余额:50.63,欠费:0.0元 查询结果仅供参考，实际费用以出账单为准。更多服务请微信关注【河南电信】公众号，或下载欢go客户端( http://a.189.cn/JJTh4u )。
[2025-10-24 18:54:22.335][000000017.250] I/user.转发到飞书
[2025-10-24 18:54:22.342][000000017.252] I/user.timestamp 1761303263
[2025-10-24 18:54:22.345][000000017.252] I/user.sign awgZFT0rgM/LneXnL095BaG//GNHfLq+5/ISWt2Uoow=
[2025-10-24 18:54:22.347][000000017.253] I/user.url https://open.feishu.cn/open-apis/bot/v2/hook/bb089165-4b73-4f80-9ed0-da0c908b44e5
[2025-10-24 18:54:22.351][000000017.254] I/user.feishu {"content":{"text":"我的id是nil,Fri Oct 24 18:54:23 2025,Air8000,    10001发来短信，内容是:截止到2025年10月24日18时，本机可用余额:50.63元，帐户余额:50.63,欠费:0.0元 查询结果仅供参考，实际费用以出账单为准。更多服务请微信关注【河南电信】公众号，或下载欢go客户端( http:\/\/a.189.cn\/JJTh4u )。"},"sign":"awgZFT0rgM\/LneXnL095BaG\/\/GNHfLq+5\/ISWt2Uoow=","msg_type":"text","timestamp":"1761303263"}
[2025-10-24 18:54:22.356][000000017.260] dns_run 676:open.feishu.cn state 0 id 2 ipv6 0 use dns server0, try 0
[2025-10-24 18:54:22.359][000000017.260] D/net adatper 4 dns server 223.5.5.5
[2025-10-24 18:54:22.362][000000017.260] D/net dns udp sendto 223.5.5.5:53 from 192.168.0.110
[2025-10-24 18:54:22.364][000000017.293] dns_run 693:dns all done ,now stop
[2025-10-24 18:54:22.372][000000017.294] D/net adapter 4 connect 1.194.220.72:443 TCP
[2025-10-24 18:54:23.135][000000018.070] I/user.feishu 200 {"StatusCode":0,"StatusMessage":"success","code":0,"data":{},"msg":"success"}
[2025-10-24 18:54:23.145][000000018.071] I/user.转发到钉钉
[2025-10-24 18:54:23.153][000000018.073] I/user.timestamp 1761303264000
[2025-10-24 18:54:23.157][000000018.073] I/user.sign oXkYEXnC6p9QLr4hR8Hw8Qykz%2F2vdF7L8BjXAOVbdKY%3D
[2025-10-24 18:54:23.160][000000018.073] I/user.url https://oapi.dingtalk.com/robot/send?access_token=03f4753ec6aa6f0524fb85907c94b17f3fa0fed3107d4e8f4eee1d4a97855f4d&timestamp=1761303264000&sign=oXkYEXnC6p9QLr4hR8Hw8Qykz%2F2vdF7L8BjXAOVbdKY%3D
[2025-10-24 18:54:23.163][000000018.074] I/user.dingding {"text":{"content":"我的id是nil,Fri Oct 24 18:54:24 2025,Air8000,    10001发来短信，内容是:截止到2025年10月24日18时，本机可用余额:50.63元，帐户余额:50.63,欠费:0.0元 查询结果仅供参考，实际费用以出账单为准。更多服务请微信关注【河南电信】公众号，或下载欢go客户端( http:\/\/a.189.cn\/JJTh4u )。"},"msgtype":"text"}
[2025-10-24 18:54:23.170][000000018.076] dns_run 676:oapi.dingtalk.com state 0 id 3 ipv6 0 use dns server0, try 0
[2025-10-24 18:54:23.172][000000018.076] D/net adatper 4 dns server 223.5.5.5
[2025-10-24 18:54:23.175][000000018.076] D/net dns udp sendto 223.5.5.5:53 from 192.168.0.110
[2025-10-24 18:54:23.179][000000018.105] dns_run 693:dns all done ,now stop
[2025-10-24 18:54:23.185][000000018.106] D/net adapter 4 connect 106.11.43.136:443 TCP
[2025-10-24 18:54:23.725][000000018.658] I/user.dingding 200 {"errcode":0,"errmsg":"ok"}
[2025-10-24 18:54:23.742][000000018.659] I/user.转发到微信
[2025-10-24 18:54:23.746][000000018.660] I/user.timestamp 1761303264000
[2025-10-24 18:54:23.752][000000018.660] I/user.url https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=71017f82-e027-4c5d-a618-eb4ee01750e9&timestamp=1761303264000
[2025-10-24 18:54:23.756][000000018.661] I/user.weixin {"text":{"content":"我的id是nil,Fri Oct 24 18:54:24 2025,Air8000,    10001发来短信，内容是:截止到2025年10月24日18时，本机可用余额:50.63元，帐户余额:50.63,欠费:0.0元 查询结果仅供参考，实际费用以出账单为准。更多服务请微信关注【河南电信】公众号，或下载欢go客户端( http:\/\/a.189.cn\/JJTh4u )。"},"msgtype":"text"}
[2025-10-24 18:54:23.763][000000018.663] dns_run 676:qyapi.weixin.qq.com state 0 id 4 ipv6 0 use dns server0, try 0
[2025-10-24 18:54:23.767][000000018.663] D/net adatper 4 dns server 223.5.5.5
[2025-10-24 18:54:23.771][000000018.663] D/net dns udp sendto 223.5.5.5:53 from 192.168.0.110
[2025-10-24 18:54:23.776][000000018.692] dns_run 693:dns all done ,now stop
[2025-10-24 18:54:23.778][000000018.693] D/net adapter 4 connect 101.91.40.24:443 TCP
[2025-10-24 18:54:24.509][000000019.450] I/user.weixin 200 {"errcode":0,"errmsg":"ok"}

```

此处来电转发演示使用了电信卡，用另外手机拨打模组上的电话号码，响铃 4声后自动挂断，log 打印如下：

```lua
[2025-10-24 18:55:03.753][000000058.690] D/mobile LUAT_MOBILE_EVENT_CC status 12
[2025-10-24 18:55:03.759][000000058.691] D/mobile LUAT_MOBILE_EVENT_CC status 1
[2025-10-24 18:55:03.765][000000058.692] I/user.获取最后一次通话的号码
[2025-10-24 18:55:03.767][000000058.692] I/user.来电号码是： 18317857567
[2025-10-24 18:55:03.774][000000058.693] I/user. 来电号码转发到飞书
[2025-10-24 18:55:03.777][000000058.694] I/user.timestamp 1761303304
[2025-10-24 18:55:03.780][000000058.695] I/user.sign ilEYzlFdmUkoV2j8A6E3s+rDt0F132O7Mr3wwNxm76M=
[2025-10-24 18:55:03.783][000000058.696] I/user.url https://open.feishu.cn/open-apis/bot/v2/hook/bb089165-4b73-4f80-9ed0-da0c908b44e5
[2025-10-24 18:55:03.790][000000058.697] I/user.feishu {"content":{"text":"我的id是nil,Fri Oct 24 18:55:04 2025,Air8000,    18317857567来电"},"sign":"ilEYzlFdmUkoV2j8A6E3s+rDt0F132O7Mr3wwNxm76M=","msg_type":"text","timestamp":"1761303304"}
[2025-10-24 18:55:03.795][000000058.699] dns_run 676:open.feishu.cn state 0 id 5 ipv6 0 use dns server0, try 0
[2025-10-24 18:55:03.797][000000058.699] D/net adatper 4 dns server 223.5.5.5
[2025-10-24 18:55:03.801][000000058.700] D/net dns udp sendto 223.5.5.5:53 from 192.168.0.110
[2025-10-24 18:55:03.806][000000058.701] D/mobile LUAT_MOBILE_EVENT_CC status 2
[2025-10-24 18:55:03.810][000000058.723] dns_run 693:dns all done ,now stop
[2025-10-24 18:55:03.815][000000058.724] D/net adapter 4 connect 1.194.220.72:443 TCP
[2025-10-24 18:55:04.614][000000059.553] I/user.feishu 200 {"StatusCode":0,"StatusMessage":"success","code":0,"data":{},"msg":"success"}
[2025-10-24 18:55:04.619][000000059.553] I/user.来电号码转发到钉钉
[2025-10-24 18:55:04.624][000000059.555] I/user.timestamp 1761303305000
[2025-10-24 18:55:04.626][000000059.555] I/user.sign pwTUpkuxUSnUiN5XmXLXXL5%2FPTYD22icTHW09YslWN4%3D
[2025-10-24 18:55:04.630][000000059.556] I/user.url https://oapi.dingtalk.com/robot/send?access_token=03f4753ec6aa6f0524fb85907c94b17f3fa0fed3107d4e8f4eee1d4a97855f4d&timestamp=1761303305000&sign=pwTUpkuxUSnUiN5XmXLXXL5%2FPTYD22icTHW09YslWN4%3D
[2025-10-24 18:55:04.634][000000059.557] I/user.dingding {"text":{"content":"我的id是nil,Fri Oct 24 18:55:05 2025,Air8000,    18317857567来电"},"msgtype":"text"}
[2025-10-24 18:55:04.637][000000059.559] dns_run 676:oapi.dingtalk.com state 0 id 6 ipv6 0 use dns server0, try 0
[2025-10-24 18:55:04.641][000000059.559] D/net adatper 4 dns server 223.5.5.5
[2025-10-24 18:55:04.652][000000059.559] D/net dns udp sendto 223.5.5.5:53 from 192.168.0.110
[2025-10-24 18:55:04.656][000000059.588] dns_run 693:dns all done ,now stop
[2025-10-24 18:55:04.659][000000059.589] D/net adapter 4 connect 106.11.35.100:443 TCP
[2025-10-24 18:55:05.255][000000060.198] I/user.dingding 200 {"errcode":0,"errmsg":"ok"}
[2025-10-24 18:55:05.262][000000060.199] I/user.来电号码转发到微信
[2025-10-24 18:55:05.267][000000060.199] I/user.timestamp 1761303306000
[2025-10-24 18:55:05.271][000000060.200] I/user.url https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=71017f82-e027-4c5d-a618-eb4ee01750e9&timestamp=1761303306000
[2025-10-24 18:55:05.276][000000060.201] I/user.weixin {"text":{"content":"我的id是nil,Fri Oct 24 18:55:06 2025,Air8000,    18317857567来电"},"msgtype":"text"}
[2025-10-24 18:55:05.279][000000060.202] dns_run 676:qyapi.weixin.qq.com state 0 id 7 ipv6 0 use dns server0, try 0
[2025-10-24 18:55:05.283][000000060.203] D/net adatper 4 dns server 223.5.5.5
[2025-10-24 18:55:05.289][000000060.203] D/net dns udp sendto 223.5.5.5:53 from 192.168.0.110
[2025-10-24 18:55:05.317][000000060.246] dns_run 693:dns all done ,now stop
[2025-10-24 18:55:05.326][000000060.247] D/net adapter 4 connect 101.226.141.58:443 TCP
[2025-10-24 18:55:06.065][000000061.005] I/user.weixin 200 {"errcode":0,"errmsg":"ok"}
[2025-10-24 18:55:08.398][000000063.332] D/DHCP dhcp state 1 tnow 63332 p1 3603332 p2 6303332
[2025-10-24 18:55:09.749][000000064.690] D/mobile LUAT_MOBILE_EVENT_CC status 1
[2025-10-24 18:55:11.477][000000066.413] D/DHCP dhcp state 1 tnow 66413 p1 1806414 p2 3156414
[2025-10-24 18:55:15.759][000000070.689] D/mobile LUAT_MOBILE_EVENT_CC status 1
[2025-10-24 18:55:21.758][000000076.689] D/mobile LUAT_MOBILE_EVENT_CC status 1
[2025-10-24 18:55:21.766][000000076.698] luat_i2s_load_old_config 287:i2s0 old param not saved!
[2025-10-24 18:55:21.772][000000076.699] D/cc VOLTE_EVENT_PLAY_STOP
[2025-10-24 18:55:21.777][000000076.699] D/mobile LUAT_MOBILE_EVENT_CC status 12
[2025-10-24 18:55:21.948][000000076.886] soc_cms_proc 2219:cenc report 1,38,1,7
[2025-10-24 18:55:21.960][000000076.887] D/mobile cid7, state2
[2025-10-24 18:55:23.764][000000078.694] D/mobile LUAT_MOBILE_EVENT_CC status 10

```


