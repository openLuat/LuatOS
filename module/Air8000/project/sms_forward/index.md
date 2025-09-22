# 8000-SMS

## 功能模块介绍：

1、main.lua：主程序入口文件，加载以下 3 个文件运行。

2、netdrv_multiple.lua：网卡驱动配置文件，可以配置以太网卡,wifi 网卡,单 4g 网卡三种网卡的使用优先级

3、sms_forward.lua： 短信转发功能模块文件

4、cc_forward.lua：来电转发功能模块文件

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

1、Air8000W 核心板一块 + 正常手机卡一张（三大运营商的都可以）+4g 天线一根 +wifi 天线一根

- sim 卡插入核心板的 sim 卡槽
- 天线装到核心板上

2、TYPE-C USB 数据线一根 ，Air8000W 核心板和数据线的硬件接线方式为：

- Air8000 核心板通过 TYPE-C USB 口供电；（外部供电/USB 供电 拨动开关 拨到 USB 供电一端）
- TYPE-C USB 数据线直接插到核心板的 TYPE-C USB 座子，另外一端连接电脑 USB 口；

## 演示软件环境：

1、 Luatools 下载调试工具

2、 固件版本：LuatOS-SoC_V2014_Air8000_1，固件地址，如有最新固件请用最新 [https://docs.openluat.com/air8000/luatos/firmware/](https://docs.openluat.com/air8000/luatos/firmware/)

3、 脚本文件：

main.lua

netdrv_multiple.lua：

sms_forward.lua：

cc_forward.lua：

4、 pc 系统 win11（win10 及以上）

5、飞书，钉钉，企业微信等自己需要的机器人。

## 演示核心步骤：

1、搭建好硬件环境

2、demo 脚本代码 netdrv_multiple.lua 中，ssid = "茶室-降功耗,找合宙!", password = "Air123456", 修改为自己测试时 wifi 热点的名称和密码；注意：仅支持 2.4G 的 wifi，不支持 5G 的 wifi

3、[https://open.feishu.cn/document/ukTMukTMukTM/ucTM5YjL3ETO24yNxkjN?lang=zh-CN](https://open.feishu.cn/document/ukTMukTMukTM/ucTM5YjL3ETO24yNxkjN?lang=zh-CN) 参考此教程，获取飞书，钉钉，企业微信的 webhook 和 secret（加签），在 cc_forward.lua 和 sms_forward.lua 脚本中找到 local webhook_feishu，secret_feishu，webhook_dingding，secret_dingding，webhook_weixin 的参数定义，修改为自己的参数。

4、Luatools 烧录内核固件和修改后的 demo 脚本代码

5、此处演示设置了优先使用 wifi 网络，其次是 4G 网络.

烧录成功后，代码会自动运行，log 日志打印 wif 网络信息、CC_READY 等消息，log 日志打印如下：

```yaml
[2025-09-22 10:51:57.930][000000000.358] I/user.main cc_sms_forward 001.000.000
[2025-09-22 10:51:57.942][000000000.470] I/user.notify_status function
[2025-09-22 10:51:57.956][000000000.471] I/user.WiFi名称: Mayadan
[2025-09-22 10:51:57.965][000000000.472] I/user.密码     : 12345678
[2025-09-22 10:51:57.973][000000000.472] I/user.ping_ip  : nil
[2025-09-22 10:51:57.978][000000000.472] I/user.WiFi STA初始化完成
[2025-09-22 10:51:57.983][000000000.473] change from 1 to 2
[2025-09-22 10:51:58.448][000000001.474] I/user.4G网卡开始PING
[2025-09-22 10:51:58.454][000000001.474] I/user.dns_request 4G true
[2025-09-22 10:51:59.022][000000002.004] D/mobile cid1, state0
[2025-09-22 10:51:59.028][000000002.005] D/mobile bearer act 0, result 0
[2025-09-22 10:51:59.031][000000002.006] D/mobile NETIF_LINK_ON -> IP_READY
[2025-09-22 10:51:59.035][000000002.007] I/user.ip_ready_handle 10.41.25.58 4G state 1 gw 0.0.0.0
[2025-09-22 10:51:59.044][000000002.007] I/user.eth_ping_ip nil wifi_ping_ip nil
[2025-09-22 10:51:59.047][000000002.007] I/user.dnsproxy 开始监听
[2025-09-22 10:51:59.052][000000002.014] D/mobile TIME_SYNC 0
[2025-09-22 10:51:59.055][000000002.073] I/user.4G网卡httpdns域名解析成功
[2025-09-22 10:51:59.059][000000002.074] I/user.httpdns baidu.com 220.181.7.203
[2025-09-22 10:51:59.062][000000002.075] I/user.设置网卡 4G
[2025-09-22 10:51:59.066][000000002.075] I/user.netdrv_multiple_notify_cbfunc use new adapter 4G 1
[2025-09-22 10:51:59.071][000000002.076] change from 2 to 1
[2025-09-22 10:51:59.103][000000002.122] soc_cms_proc 2189:cenc report 1,51,1,15
[2025-09-22 10:51:59.168][000000002.188] D/mobile NETIF_LINK_ON -> IP_READY
[2025-09-22 10:51:59.173][000000002.189] I/user.ip_ready_handle 10.41.25.58 4G state 2 gw 0.0.0.0
[2025-09-22 10:51:59.178][000000002.190] I/user.eth_ping_ip nil wifi_ping_ip nil
[2025-09-22 10:51:59.183][000000002.190] I/user.dnsproxy 开始监听
[2025-09-22 10:52:00.221][000000003.247] D/mobile ims reg state 0
[2025-09-22 10:52:00.227][000000003.247] D/mobile LUAT_MOBILE_EVENT_CC status 0
[2025-09-22 10:52:00.232][000000003.247] D/mobile LUAT_MOBILE_CC_READY
```

此处短信演示使用了电信卡，发送"102"给"10001"查询余额，会收到电信回复的短信，并转发到飞书、钉钉和微信，log 打印如下：

```bash
[2025-09-22 10:52:00.239][000000003.248] I/user.发送短信前wait CC_IND
[2025-09-22 10:52:00.243][000000003.249] D/sntp query ntp.aliyun.com
[2025-09-22 10:52:00.248][000000003.249] dns_run 676:ntp.aliyun.com state 0 id 1 ipv6 0 use dns server2, try 0
[2025-09-22 10:52:00.256][000000003.251] I/user.时间同步
[2025-09-22 10:52:00.261][000000003.270] dns_run 693:dns all done ,now stop
[2025-09-22 10:52:00.314][000000003.332] D/sntp Unix timestamp: 1758509523
[2025-09-22 10:52:00.322][000000003.334] I/user.现在可以收发短信
[2025-09-22 10:52:00.326][000000003.334] I/user.mobile.number(id) =  nil
[2025-09-22 10:52:00.330][000000003.334] I/user.mobile.iccid(id) =  89860325743780541565
[2025-09-22 10:52:00.333][000000003.335] I/user.mobile.simid(id) =  0
[2025-09-22 10:52:00.337][000000003.335] I/user.mobile.imsi(index) =  460115726670673
[2025-09-22 10:52:00.340][000000003.335] W/sms pdu len 18
[2025-09-22 10:52:00.346][000000003.337] I/user.给10001发送查询短信 这是第1次发送 true
[2025-09-22 10:52:00.812][000000003.835] luat_sms_proc 1239:[DIO 1239]: CMI_SMS_SEND_MSG_CNF is in
[2025-09-22 10:52:00.817][000000003.836] E/sms long sms callback seqNum = 1
[2025-09-22 10:52:00.921][000000003.947] D/airlink wifi sta上线了
[2025-09-22 10:52:00.952][000000003.956] D/DHCP dhcp state 6 3956 0 0
[2025-09-22 10:52:00.959][000000003.957] D/DHCP dhcp discover C8C2C68CD816
[2025-09-22 10:52:00.962][000000003.957] I/ulwip adapter 2 dhcp payload len 308
[2025-09-22 10:52:00.966][000000003.958] D/netdrv.whale IP_LOSE 2
[2025-09-22 10:52:00.971][000000003.959] I/user.ip_lose_handle WiFi
[2025-09-22 10:52:00.980][000000003.981] D/ulwip 收到DHCP数据包(len=303)
[2025-09-22 10:52:00.984][000000003.982] D/DHCP dhcp state 7 3982 0 0
[2025-09-22 10:52:00.987][000000003.982] D/DHCP find ip d72ba8c0 192.168.43.215
[2025-09-22 10:52:00.995][000000003.982] D/DHCP result 2
[2025-09-22 10:52:01.001][000000003.982] D/DHCP select offer, wait ack
[2025-09-22 10:52:01.005][000000003.982] I/ulwip adapter 2 dhcp payload len 338
[2025-09-22 10:52:01.012][000000004.007] D/ulwip 收到DHCP数据包(len=333)
[2025-09-22 10:52:01.016][000000004.008] D/DHCP dhcp state 9 4008 0 0
[2025-09-22 10:52:01.019][000000004.008] D/DHCP find ip d72ba8c0 192.168.43.215
[2025-09-22 10:52:01.027][000000004.008] D/DHCP result 5
[2025-09-22 10:52:01.032][000000004.008] D/DHCP DHCP get ip ready
[2025-09-22 10:52:01.035][000000004.008] D/ulwip adapter 2 ip 192.168.43.215
[2025-09-22 10:52:01.042][000000004.008] D/ulwip adapter 2 mask 255.255.255.0
[2025-09-22 10:52:01.046][000000004.009] D/ulwip adapter 2 gateway 192.168.43.1
[2025-09-22 10:52:01.050][000000004.009] D/ulwip adapter 2 lease_time 3600s
[2025-09-22 10:52:01.053][000000004.009] D/ulwip adapter 2 DNS1:192.168.43.1
[2025-09-22 10:52:01.062][000000004.009] D/net network ready 2, setup dns server
[2025-09-22 10:52:01.070][000000004.010] D/ulwip IP_READY 2 192.168.43.215
[2025-09-22 10:52:01.073][000000004.012] I/user.ip_ready_handle 192.168.43.215 WiFi state 3 gw 192.168.43.1
[2025-09-22 10:52:01.079][000000004.012] I/user.eth_ping_ip nil wifi_ping_ip nil
[2025-09-22 10:52:01.083][000000004.012] I/user.dnsproxy 开始监听
[2025-09-22 10:52:01.979][000000005.007] luat_sms_proc 1236:[DIO 1236]: CMI_SMS_NEW_MSG_IND is in
[2025-09-22 10:52:01.991][000000005.008] D/sms dcs 2 | 0 | 0 | 0
[2025-09-22 10:52:02.002][000000005.008] I/sms long-sms, wait more frags 2/2
[2025-09-22 10:52:05.202][000000008.219] luat_sms_proc 1236:[DIO 1236]: CMI_SMS_NEW_MSG_IND is in
[2025-09-22 10:52:05.210][000000008.219] D/sms dcs 2 | 0 | 0 | 0
[2025-09-22 10:52:05.214][000000008.220] I/sms long-sms is ok
[2025-09-22 10:52:05.220][000000008.222] I/user.num是 10001
[2025-09-22 10:52:05.224][000000008.222] I/user.收到来自10001的短信：截止到2025年09月22日10时，本机可用余额:64.4元，帐户余额:64.4,欠费:0.0元 查询结果仅供参考，实际费用以出账单为准。更多服务请微信关注【河南电信】公众号，或下载欢go客户端( http://a.189.cn/JJTh4u )。
[2025-09-22 10:52:05.228][000000008.222] I/user.当前网络 true 1
[2025-09-22 10:52:05.231][000000008.223] I/user.当前wifi网络情况 true 2
[2025-09-22 10:52:05.236][000000008.223] I/user.转发到飞书
[2025-09-22 10:52:05.241][000000008.225] I/user.timestamp 1758509527
[2025-09-22 10:52:05.243][000000008.225] I/user.sign Z17kK76tCSB9L+VrkLP8mKYvkpu0lVWEJWKZ7GbVDJ0=
[2025-09-22 10:52:05.249][000000008.226] I/user.url https://open.feishu.cn/open-apis/bot/v2/hook/bb089165-4b73-4f80-9ed0-da0c908b44e5
[2025-09-22 10:52:05.252][000000008.227] I/user.feishu {"content":{"text":"我的id是nil,Mon Sep 22 10:52:07 2025,Air8000,    10001发来短信，内容是:截止到2025年09月22日10时，本机可用余额:64.4元，帐户余额:64.4,欠费:0.0元 查询结果仅供参考，实际费用以出账单为准。更多服务请微信关注【河南电信】公众号，或下载欢go客户端( http:\/\/a.189.cn\/JJTh4u )。"},"sign":"Z17kK76tCSB9L+VrkLP8mKYvkpu0lVWEJWKZ7GbVDJ0=","msg_type":"text","timestamp":"1758509527"}
[2025-09-22 10:52:05.258][000000008.232] dns_run 676:open.feishu.cn state 0 id 2 ipv6 0 use dns server2, try 0
[2025-09-22 10:52:05.261][000000008.251] dns_run 693:dns all done ,now stop
[2025-09-22 10:52:06.117][000000009.147] I/user.feishu 200 {"StatusCode":0,"StatusMessage":"success","code":0,"data":{},"msg":"success"} 当前网络： true 2
[2025-09-22 10:52:07.126][000000010.148] I/user.转发到钉钉
[2025-09-22 10:52:07.139][000000010.150] I/user.timestamp 1758509529000
[2025-09-22 10:52:07.143][000000010.150] I/user.sign 2Q1L9DWjmdMoW1OMmSQMJ7rc3HyPZdt1ollEVQVmf58%3D
[2025-09-22 10:52:07.146][000000010.151] I/user.url https://oapi.dingtalk.com/robot/send?access_token=03f4753ec6aa6f0524fb85907c94b17f3fa0fed3107d4e8f4eee1d4a97855f4d&timestamp=1758509529000&sign=2Q1L9DWjmdMoW1OMmSQMJ7rc3HyPZdt1ollEVQVmf58%3D
[2025-09-22 10:52:07.150][000000010.152] I/user.dingding {"text":{"content":"我的id是nil,Mon Sep 22 10:52:09 2025,Air8000,    10001发来短信，内容是:截止到2025年09月22日10时，本机可用余额:64.4元，帐户余额:64.4,欠费:0.0元 查询结果仅供参考，实际费用以出账单为准。更多服务请微信关注【河南电信】公众号，或下载欢go客户端( http:\/\/a.189.cn\/JJTh4u )。"},"msgtype":"text"}
[2025-09-22 10:52:07.155][000000010.154] dns_run 676:oapi.dingtalk.com state 0 id 3 ipv6 0 use dns server2, try 0
[2025-09-22 10:52:08.135][000000011.153] dns_run 676:oapi.dingtalk.com state 0 id 3 ipv6 0 use dns server2, try 1
[2025-09-22 10:52:10.062][000000013.076] I/user.WiFi网卡开始PING
[2025-09-22 10:52:10.078][000000013.076] I/user.dns_request WiFi true
[2025-09-22 10:52:10.083][000000013.078] D/net connect 223.5.5.5:80 TCP
[2025-09-22 10:52:10.139][000000013.153] dns_run 676:oapi.dingtalk.com state 0 id 3 ipv6 0 use dns server2, try 2
[2025-09-22 10:52:10.201][000000013.218] I/user.WiFi网卡httpdns域名解析成功
[2025-09-22 10:52:10.211][000000013.218] I/user.httpdns baidu.com 220.181.7.203
[2025-09-22 10:52:10.225][000000013.219] I/user.设置网卡 WiFi
[2025-09-22 10:52:10.230][000000013.220] I/user.netdrv_multiple_notify_cbfunc use new adapter WiFi 2
[2025-09-22 10:52:10.235][000000013.220] change from 1 to 2
[2025-09-22 10:52:13.130][000000016.153] dns_run 676:oapi.dingtalk.com state 0 id 3 ipv6 0 use dns server3, try 0
[2025-09-22 10:52:13.161][000000016.188] dns_run 693:dns all done ,now stop
[2025-09-22 10:52:13.832][000000016.848] I/user.dingding 200 {"errcode":0,"errmsg":"ok"} 当前网络： true 2
[2025-09-22 10:52:14.829][000000017.848] I/user.转发到微信
[2025-09-22 10:52:14.836][000000017.850] I/user.timestamp 1758509537000
[2025-09-22 10:52:14.841][000000017.851] I/user.sign foZ%2BwVSF%2BC6V7rwNRDvlUD5V6k1UU0wAMupeyGrHD3Y%3D
[2025-09-22 10:52:14.848][000000017.851] I/user.url https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=36648707-4eba-4d21-9d3a-2244e1e9bc3b&timestamp=1758509537000&sign=
[2025-09-22 10:52:14.853][000000017.852] I/user.weixin {"text":{"content":"我的id是nil,Mon Sep 22 10:52:17 2025,Air8000,    10001发来短信，内容是:截止到2025年09月22日10时，本机可用余额:64.4元，帐户余额:64.4,欠费:0.0元 查询结果仅供参考，实际费用以出账单为准。更多服务请微信关注【河南电信】公众号，或下载欢go客户端( http:\/\/a.189.cn\/JJTh4u )。"},"msgtype":"text"}
[2025-09-22 10:52:14.860][000000017.854] dns_run 676:qyapi.weixin.qq.com state 0 id 1 ipv6 0 use dns server0, try 0
[2025-09-22 10:52:14.863][000000017.854] D/net adatper 2 dns server 192.168.43.1
[2025-09-22 10:52:14.867][000000017.854] D/net dns udp sendto 192.168.43.1:53 from 192.168.43.215
[2025-09-22 10:52:14.890][000000017.908] dns_run 693:dns all done ,now stop
[2025-09-22 10:52:14.895][000000017.909] D/net connect 101.226.141.58:443 TCP
[2025-09-22 10:52:15.688][000000018.716] I/user.weixin 200 {"errcode":0,"errmsg":"ok"} 当前网络： true true 1
```

此处来电转发演示使用了电信卡，用另外手机拨打模组上的电话号码，响铃 3 声后自动挂断，log 打印如下：

```lua
[2025-09-22 10:59:04.001][000000427.015] D/mobile LUAT_MOBILE_EVENT_CC status 12
[2025-09-22 10:59:04.013][000000427.016] D/mobile LUAT_MOBILE_EVENT_CC status 1
[2025-09-22 10:59:04.026][000000427.017] I/user.获取最后一次通话的号码
[2025-09-22 10:59:04.033][000000427.017] I/user.来电号码是 18317857567
[2025-09-22 10:59:04.045][000000427.018] I/user. 来电号码转发到飞书
[2025-09-22 10:59:04.052][000000427.020] I/user.timestamp 1758509946
[2025-09-22 10:59:04.060][000000427.021] I/user.sign 0/ThEtxIC5eD7tpdAZMN8ZjTpviUvboF52agGrm7qso=
[2025-09-22 10:59:04.068][000000427.021] I/user.url https://open.feishu.cn/open-apis/bot/v2/hook/bb089165-4b73-4f80-9ed0-da0c908b44e5
[2025-09-22 10:59:04.079][000000427.022] I/user.feishu {"content":{"text":"我的id是nil,Mon Sep 22 10:59:06 2025,Air8000,    18317857567来电"},"sign":"0\/ThEtxIC5eD7tpdAZMN8ZjTpviUvboF52agGrm7qso=","msg_type":"text","timestamp":"1758509946"}
[2025-09-22 10:59:04.090][000000427.023] dns_run 676:open.feishu.cn state 0 id 2 ipv6 0 use dns server0, try 0
[2025-09-22 10:59:04.097][000000427.024] D/net adatper 2 dns server 192.168.43.1
[2025-09-22 10:59:04.108][000000427.024] D/net dns udp sendto 192.168.43.1:53 from 192.168.43.215
[2025-09-22 10:59:04.115][000000427.026] D/mobile LUAT_MOBILE_EVENT_CC status 2
[2025-09-22 10:59:04.124][000000427.094] dns_run 693:dns all done ,now stop
[2025-09-22 10:59:04.133][000000427.095] D/net connect 221.229.209.220:443 TCP
[2025-09-22 10:59:05.166][000000428.177] I/user.feishu 200 {"StatusCode":0,"StatusMessage":"success","code":0,"data":{},"msg":"success"} true true 1
[2025-09-22 10:59:06.163][000000429.177] I/user.来电号码转发到钉钉
[2025-09-22 10:59:06.175][000000429.179] I/user.timestamp 1758509948000
[2025-09-22 10:59:06.185][000000429.180] I/user.sign %2FVjHC0cAIWwJqTPRez%2FITF4AOa4wPQF4DuTlNn7Dos4%3D
[2025-09-22 10:59:06.200][000000429.180] I/user.url https://oapi.dingtalk.com/robot/send?access_token=03f4753ec6aa6f0524fb85907c94b17f3fa0fed3107d4e8f4eee1d4a97855f4d&timestamp=1758509948000&sign=%2FVjHC0cAIWwJqTPRez%2FITF4AOa4wPQF4DuTlNn7Dos4%3D
[2025-09-22 10:59:06.212][000000429.181] I/user.dingding {"text":{"content":"我的id是nil,Mon Sep 22 10:59:08 2025,Air8000,    18317857567来电"},"msgtype":"text"}
[2025-09-22 10:59:06.222][000000429.183] dns_run 676:oapi.dingtalk.com state 0 id 3 ipv6 0 use dns server0, try 0
[2025-09-22 10:59:06.233][000000429.183] D/net adatper 2 dns server 192.168.43.1
[2025-09-22 10:59:06.244][000000429.183] D/net dns udp sendto 192.168.43.1:53 from 192.168.43.215
[2025-09-22 10:59:06.253][000000429.242] dns_run 693:dns all done ,now stop
[2025-09-22 10:59:06.264][000000429.243] D/net connect 106.11.35.100:443 TCP
[2025-09-22 10:59:07.007][000000430.016] I/user.dingding 200 {"errcode":0,"errmsg":"ok"} true true 1
[2025-09-22 10:59:08.005][000000431.017] I/user.来电号码转发到微信
[2025-09-22 10:59:08.015][000000431.019] I/user.timestamp 1758509950000
[2025-09-22 10:59:08.025][000000431.019] I/user.sign SK6tHgVsVn%2FUhPMaNsb3aRcP9iVAqVAQz1Kwx0GDy7c%3D
[2025-09-22 10:59:08.033][000000431.020] I/user.url https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=36648707-4eba-4d21-9d3a-2244e1e9bc3b&timestamp=1758509950000&sign=
[2025-09-22 10:59:08.045][000000431.021] I/user.weixin {"text":{"content":"我的id是nil,Mon Sep 22 10:59:10 2025,Air8000,    18317857567来电"},"msgtype":"text"}
[2025-09-22 10:59:08.055][000000431.022] dns_run 676:qyapi.weixin.qq.com state 0 id 4 ipv6 0 use dns server0, try 0
[2025-09-22 10:59:08.063][000000431.023] D/net adatper 2 dns server 192.168.43.1
[2025-09-22 10:59:08.075][000000431.023] D/net dns udp sendto 192.168.43.1:53 from 192.168.43.215
[2025-09-22 10:59:08.083][000000431.072] dns_run 693:dns all done ,now stop
[2025-09-22 10:59:08.090][000000431.073] D/net connect 101.226.141.58:443 TCP
[2025-09-22 10:59:08.985][000000431.998] I/user.weixin 200 {"errcode":0,"errmsg":"ok"} true true 1
[2025-09-22 10:59:09.999][000000433.014] D/mobile LUAT_MOBILE_EVENT_CC status 1
[2025-09-22 10:59:16.002][000000439.014] D/mobile LUAT_MOBILE_EVENT_CC status 1
[2025-09-22 10:59:21.995][000000445.014] D/mobile LUAT_MOBILE_EVENT_CC status 1
[2025-09-22 10:59:22.010][000000445.022] luat_i2s_load_old_config 287:i2s0 old param not saved!
[2025-09-22 10:59:22.020][000000445.022] D/cc VOLTE_EVENT_PLAY_STOP
[2025-09-22 10:59:22.028][000000445.023] D/mobile LUAT_MOBILE_EVENT_CC status 12
[2025-09-22 10:59:22.120][000000445.134] soc_cms_proc 2189:cenc report 1,38,1,7
[2025-09-22 10:59:22.134][000000445.135] D/mobile cid7, state2
[2025-09-22 10:59:23.997][000000447.019] D/mobile LUAT_MOBILE_EVENT_CC status 10
```
