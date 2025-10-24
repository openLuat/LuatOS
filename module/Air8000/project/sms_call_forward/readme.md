# 8000-SMS

## 功能模块介绍：

1、main.lua：主程序入口文件，加载以下 3 个文件运行。

2、netdrv_multiple.lua：网卡驱动配置文件，可以配置以太网卡,wifi 网卡,单 4g 网卡三种网卡的使用优先级

3、sms_forward.lua： 短信转发功能模块文件

4、cc_forward.lua：来电转发功能模块文件

5、netdrv_pc：pc模拟器上的网卡

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

![8000w](https://docs.openluat.com/accessory/AirSPINORFLASH_1000/image/8000w.jpg)

1、Air8000W 开发板一块 + 正常手机卡一张（三大运营商的都可以）+4g 天线一根 +wifi 天线一根

- sim 卡插入开发板的 sim 卡槽
- 天线装到开发板上

2、TYPE-C USB 数据线一根 ，Air8000W 开发板和数据线的硬件接线方式为：

- Air8000 开发板通过 TYPE-C USB 口供电；（外部供电/USB 供电 拨动开关 拨到 USB 供电一端）
- TYPE-C USB 数据线直接插到开发板的 TYPE-C USB 座子，另外一端连接电脑 USB 口；

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

2、demo 脚本代码 netdrv_multiple.lua 中，ssid = "茶室-降功耗,找合宙!", password = "Air123456", 修改为自己测试时 wifi 热点的名称和密码；注意：仅支持 2.4G 的 wifi，不支持 5G 的 wifi

3、[https://open.feishu.cn/document/ukTMukTMukTM/ucTM5YjL3ETO24yNxkjN?lang=zh-CN](https://open.feishu.cn/document/ukTMukTMukTM/ucTM5YjL3ETO24yNxkjN?lang=zh-CN) 参考此教程，获取飞书，钉钉，企业微信的 webhook 和 secret（加签），在 cc_forward.lua 和 sms_forward.lua 脚本中找到 local webhook_feishu，secret_feishu，webhook_dingding，secret_dingding，webhook_weixin 的参数定义，修改为自己的参数。

4、Luatools 烧录内核固件和修改后的 demo 脚本代码

5、此处演示设置了优先使用 以太网，其次wifi 网络，最低优先级使用 4G 网络.

烧录成功后，代码会自动运行，log 日志打印以太网信息， wif 网络信息、CC_READY 等消息，log 日志打印如下：

```yaml
[2025-10-24 18:54:07.534][000000000.657] I/user.main cc_sms_forward 001.000.000
[2025-10-24 18:54:07.536][000000000.668] W/user.cc wait IP_READY 1 3
[2025-10-24 18:54:07.539][000000000.770] I/user.notify_status function
[2025-10-24 18:54:07.542][000000000.771] I/user.初始化以太网
[2025-10-24 18:54:07.546][000000000.771] I/user.config.opts.spi 1 ,config.type 1
[2025-10-24 18:54:07.551][000000000.772] SPI_HWInit 552:spi1 speed 25600000,25600000,12
[2025-10-24 18:54:07.553][000000000.772] I/user.main open spi 0
[2025-10-24 18:54:07.557][000000000.773] D/ch390h 注册CH390H设备(4) SPI id 1 cs 12 irq 255
[2025-10-24 18:54:07.561][000000000.773] D/ch390h adapter 4 netif init ok
[2025-10-24 18:54:07.564][000000000.774] D/netdrv.ch390x task started
[2025-10-24 18:54:07.568][000000000.774] D/ch390h 注册完成 adapter 4 spi 1 cs 12 irq 255
[2025-10-24 18:54:07.570][000000000.774] I/user.以太网初始化完成
[2025-10-24 18:54:07.574][000000000.775] I/user.netdrv 订阅socket连接状态变化事件 Ethernet
[2025-10-24 18:54:07.578][000000000.775] I/user.WiFi名称: Mayadan
[2025-10-24 18:54:07.583][000000000.776] I/user.密码     : 12345678
[2025-10-24 18:54:07.587][000000000.776] I/user.ping_ip  : nil
[2025-10-24 18:54:07.590][000000000.776] I/user.WiFi STA初始化完成
[2025-10-24 18:54:07.594][000000000.776] I/user.netdrv 订阅socket连接状态变化事件 WiFi
[2025-10-24 18:54:07.604][000000000.777] change from 1 to 4
[2025-10-24 18:54:07.610][000000000.827] D/netdrv.ch390x 初始化MAC 3CAB724406AF
[2025-10-24 18:54:07.615][000000001.669] W/user.cc wait IP_READY 4 4
[2025-10-24 18:54:07.620][000000001.770] I/user.4G网卡开始PING
[2025-10-24 18:54:07.625][000000001.770] I/user.dns_request 4G true
[2025-10-24 18:54:07.736][000000002.670] W/user.cc wait IP_READY 4 4
[2025-10-24 18:54:07.763][000000002.675] I/netdrv.ch390x link is up 1 12 100M
[2025-10-24 18:54:07.772][000000002.676] D/netdrv 网卡(4)设置为UP
[2025-10-24 18:54:07.799][000000002.733] D/ulwip adapter 4 dhcp start netif c149084
[2025-10-24 18:54:07.806][000000002.734] D/DHCP dhcp state 6 tnow 2734 p1 0 p2 0
[2025-10-24 18:54:07.811][000000002.734] D/DHCP dhcp discover 3CAB724406AF
[2025-10-24 18:54:07.819][000000002.734] I/ulwip adapter 4 dhcp payload len 308
[2025-10-24 18:54:08.267][000000003.208] D/airlink wifi sta上线了
[2025-10-24 18:54:08.275][000000003.209] D/netdrv 网卡(2)设置为UP
[2025-10-24 18:54:08.314][000000003.259] D/ulwip adapter 2 dhcp start netif c10d04c
[2025-10-24 18:54:08.321][000000003.259] D/DHCP dhcp state 6 tnow 3259 p1 0 p2 0
[2025-10-24 18:54:08.325][000000003.259] D/DHCP dhcp discover C8C2C68CA00E
[2025-10-24 18:54:08.329][000000003.259] I/ulwip adapter 2 dhcp payload len 308
[2025-10-24 18:54:08.394][000000003.325] D/ulwip 收到DHCP数据包(len=548)
[2025-10-24 18:54:08.400][000000003.325] D/DHCP dhcp state 7 tnow 3325 p1 0 p2 0
[2025-10-24 18:54:08.403][000000003.325] D/DHCP find ip 6e00a8c0 192.168.0.110
[2025-10-24 18:54:08.406][000000003.326] D/DHCP result 2
[2025-10-24 18:54:08.412][000000003.326] D/DHCP select offer, wait ack
[2025-10-24 18:54:08.415][000000003.326] I/ulwip adapter 4 dhcp payload len 338
[2025-10-24 18:54:08.419][000000003.332] D/ulwip 收到DHCP数据包(len=548)
[2025-10-24 18:54:08.421][000000003.332] D/DHCP dhcp state 9 tnow 3332 p1 0 p2 0
[2025-10-24 18:54:08.426][000000003.332] D/DHCP find ip 6e00a8c0 192.168.0.110
[2025-10-24 18:54:08.429][000000003.333] D/DHCP result 5
[2025-10-24 18:54:08.432][000000003.333] D/DHCP DHCP get ip ready
[2025-10-24 18:54:08.435][000000003.333] D/ulwip adapter 4 ip 192.168.0.110
[2025-10-24 18:54:08.437][000000003.333] D/ulwip adapter 4 mask 255.255.255.0
[2025-10-24 18:54:08.442][000000003.333] D/ulwip adapter 4 gateway 192.168.0.1
[2025-10-24 18:54:08.445][000000003.333] D/ulwip adapter 4 lease_time 7200s
[2025-10-24 18:54:08.449][000000003.333] D/ulwip adapter 4 DNS1:114.114.114.114
[2025-10-24 18:54:08.451][000000003.333] D/ulwip adapter 4 DNS2:192.168.0.1
[2025-10-24 18:54:08.455][000000003.334] D/net network ready 4, setup dns server
[2025-10-24 18:54:08.461][000000003.334] D/netdrv IP_READY 4 192.168.0.110
[2025-10-24 18:54:08.466][000000003.336] I/user.ip_ready_handle 192.168.0.110 Ethernet state 3 gw 192.168.0.1
[2025-10-24 18:54:08.469][000000003.336] I/user.eth_ping_ip nil wifi_ping_ip nil
[2025-10-24 18:54:08.472][000000003.336] I/user.dnsproxy 开始监听
[2025-10-24 18:54:08.476][000000003.337] I/user.cc recv IP_READY 4 4
[2025-10-24 18:54:09.326][000000004.258] D/DHCP dhcp state 7 tnow 4258 p1 0 p2 0
[2025-10-24 18:54:09.331][000000004.259] D/DHCP long time no offer, resend
[2025-10-24 18:54:09.336][000000004.259] I/ulwip adapter 2 dhcp payload len 308
[2025-10-24 18:54:09.838][000000004.771] I/user.4G网卡httpdns域名解析失败
[2025-10-24 18:54:09.849][000000004.772] I/user.httpdns baidu.com nil
[2025-10-24 18:54:10.323][000000005.258] D/DHCP dhcp state 7 tnow 5258 p1 0 p2 0
[2025-10-24 18:54:11.330][000000006.258] D/DHCP dhcp state 7 tnow 6258 p1 0 p2 0
[2025-10-24 18:54:11.339][000000006.259] D/DHCP long time no offer, resend
[2025-10-24 18:54:11.346][000000006.259] I/ulwip adapter 2 dhcp payload len 308
[2025-10-24 18:54:11.376][000000006.314] D/ulwip 收到DHCP数据包(len=303)
[2025-10-24 18:54:11.384][000000006.314] D/DHCP dhcp state 7 tnow 6314 p1 0 p2 0
[2025-10-24 18:54:11.389][000000006.314] D/DHCP find ip 8e2ba8c0 192.168.43.142
[2025-10-24 18:54:11.396][000000006.314] D/DHCP result 2
[2025-10-24 18:54:11.401][000000006.314] D/DHCP select offer, wait ack
[2025-10-24 18:54:11.405][000000006.314] I/ulwip adapter 2 dhcp payload len 338
[2025-10-24 18:54:11.486][000000006.413] D/ulwip 收到DHCP数据包(len=333)
[2025-10-24 18:54:11.492][000000006.414] D/DHCP dhcp state 9 tnow 6414 p1 0 p2 0
[2025-10-24 18:54:11.497][000000006.414] D/DHCP find ip 8e2ba8c0 192.168.43.142
[2025-10-24 18:54:11.503][000000006.414] D/DHCP result 5
[2025-10-24 18:54:11.507][000000006.414] D/DHCP DHCP get ip ready
[2025-10-24 18:54:11.510][000000006.414] D/ulwip adapter 2 ip 192.168.43.142
[2025-10-24 18:54:11.513][000000006.414] D/ulwip adapter 2 mask 255.255.255.0
[2025-10-24 18:54:11.519][000000006.414] D/ulwip adapter 2 gateway 192.168.43.1
[2025-10-24 18:54:11.521][000000006.415] D/ulwip adapter 2 lease_time 3600s
[2025-10-24 18:54:11.524][000000006.415] D/ulwip adapter 2 DNS1:192.168.43.1
[2025-10-24 18:54:11.526][000000006.415] D/net network ready 2, setup dns server
[2025-10-24 18:54:11.529][000000006.416] D/netdrv IP_READY 2 192.168.43.142
[2025-10-24 18:54:11.534][000000006.418] I/user.ip_ready_handle 192.168.43.142 WiFi state 3 gw 192.168.43.1
[2025-10-24 18:54:11.536][000000006.418] I/user.eth_ping_ip nil wifi_ping_ip nil
[2025-10-24 18:54:11.540][000000006.418] I/user.dnsproxy 开始监听
[2025-10-24 18:54:12.557][000000007.450] D/mobile cid1, state0
[2025-10-24 18:54:12.562][000000007.451] D/mobile bearer act 0, result 0
[2025-10-24 18:54:12.564][000000007.451] D/mobile NETIF_LINK_ON -> IP_READY
[2025-10-24 18:54:12.567][000000007.453] I/user.ip_ready_handle 10.172.199.213 4G state 1 gw 0.0.0.0
[2025-10-24 18:54:12.570][000000007.453] I/user.eth_ping_ip nil wifi_ping_ip nil
[2025-10-24 18:54:12.574][000000007.453] I/user.dnsproxy 开始监听
[2025-10-24 18:54:12.581][000000007.480] D/mobile TIME_SYNC 0
[2025-10-24 18:54:12.681][000000007.624] soc_cms_proc 2219:cenc report 1,51,1,15
[2025-10-24 18:54:12.778][000000007.718] D/mobile NETIF_LINK_ON -> IP_READY
[2025-10-24 18:54:12.783][000000007.719] I/user.ip_ready_handle 10.172.199.213 4G state 1 gw 0.0.0.0
[2025-10-24 18:54:12.787][000000007.719] I/user.eth_ping_ip nil wifi_ping_ip nil
[2025-10-24 18:54:12.791][000000007.720] I/user.dnsproxy 开始监听
[2025-10-24 18:54:13.831][000000008.772] I/user.Ethernet网卡开始PING
[2025-10-24 18:54:13.839][000000008.773] I/user.dns_request Ethernet true
[2025-10-24 18:54:13.844][000000008.774] D/net adapter 4 connect 223.5.5.5:80 TCP
[2025-10-24 18:54:13.908][000000008.849] I/user.Ethernet网卡httpdns域名解析成功
[2025-10-24 18:54:13.916][000000008.849] I/user.httpdns baidu.com 39.156.70.37
[2025-10-24 18:54:13.921][000000008.850] I/user.设置网卡 Ethernet
[2025-10-24 18:54:13.929][000000008.850] D/net 设置DNS服务器 id 4 index 0 ip 223.5.5.5
[2025-10-24 18:54:13.932][000000008.850] D/net 设置DNS服务器 id 4 index 1 ip 114.114.114.114
[2025-10-24 18:54:13.937][000000008.851] I/user.netdrv_multiple_notify_cbfunc use new adapter Ethernet 4
[2025-10-24 18:54:16.674][000000011.612] D/mobile ims reg state 0
[2025-10-24 18:54:16.681][000000011.613] D/mobile LUAT_MOBILE_EVENT_CC status 0
[2025-10-24 18:54:16.686][000000011.613] D/mobile LUAT_MOBILE_CC_READY

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
