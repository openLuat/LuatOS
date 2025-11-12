

## 功能模块介绍：

1、main.lua：主程序入口文件，加载以下 4个文件运行。

2、netdrv_device.lua：网卡驱动设备，可以配置使用netdrv文件夹内的四种网卡(单4g网卡，单wifi网卡，单spi以太网卡，多网卡)中的任何一种网卡；

3、sms_forward.lua： 短信转发功能模块文件

4、cc_forward.lua：来电转发功能模块文件

5、sntp_app.lua：时间同步应用功能模块



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

**netdrv_device：**

短信通过http转发到企业微信/钉钉/飞书平台时，配置连接外网使用的网卡，目前支持以下四种选择（四选一）

(1) netdrv_4g：4G网卡

(2) netdrv_wifi：WIFI STA网卡

(3) netdrv_eth_spi：通过SPI外挂CH390H芯片的以太网卡

(4) netdrv_multiple：支持以上三种网卡，可以配置三种网卡的优先级

## 演示硬件环境：

![8000w](https://docs.openluat.com/air780ehv/luatos/common/hwenv/image/Air780EHV.png)

1、Air780EHV/EHM/EGH核心板一块+支持短信和电话功能的手机sim卡一张+网线一根：

* sim卡插入开发板的sim卡槽

* 天线装到开发板上

* 网线一端插入开发板网口，另外一端连接可以上外网的路由器网口

2、TYPE-C USB数据线一根 ，Air780EHV/EHM/EGH核心板和数据线的硬件接线方式为：

Air780EHV/EHM/EGH核心板通过TYPE-C USB口供电；（外部供电/USB供电 拨动开关 拨到 USB供电一端）

TYPE-C USB数据线直接插到开发板的TYPE-C USB座子，另外一端连接电脑USB口；

3、可选 AirETH_1000 配件板一块，Air780EHV/EHM/EGH 核心板和 AirETH_1000 配件板的硬件接线方式为:

| **Air780EHV/EHM/EGH核心板** | **AirETH_1000配件板** |
| ------------------------ |:------------------:|
| 3V3                      | 3.3v               |
| GND                      | GND                |
| 86/SPI0CLK               | SCK                |
| 83/SPI0CS                | CSS                |
| 84/SPI0MISO              | SDO                |
| 85/SPI0MOSI              | SDI                |
| 107/GPIO21               | INT                |



## 演示软件环境：

1、 Luatools 下载调试工具

2、固件版本：
LuatOS-SoC_V2016_Air780EHV_1，固件地址，如有最新固件请用最新 [[https://docs.openluat.com/air780ehv/luatos/firmware/version/](https://docs.openluat.com/air780ehv/luatos/firmware/version/)]

LuatOS-SoC_V2016_Air780EHM_1，固件地址，如有最新固件请用最新 [https://docs.openluat.com/Air780EHM/luatos/firmware/](https://docs.openluat.com/Air780EHM/luatos/firmware/)

LuatOS-SoC_V2016_Air780EGH_1，固件地址，如有最新固件请用最新 [[https://docs.openluat.com/air780egh/luatos/firmware/version/](https://docs.openluat.com/air780egh/luatos/firmware/version/)]

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

* 如果需要pc模拟器网卡，打开require "netdrv_pc"，其余注释掉

* 如果需要多网卡，打开require "netdrv_multiple"，其余注释掉；同时netdrv_multiple.lua中的ssid = "茶室-降功耗,找合宙!", password = "Air123456", 修改为自己测试时wifi热点的名称和密码；注意：仅支持2.4G的wifi，不支持5G的wifi

3、[https://open.feishu.cn/document/ukTMukTMukTM/ucTM5YjL3ETO24yNxkjN?lang=zh-CN](https://open.feishu.cn/document/ukTMukTMukTM/ucTM5YjL3ETO24yNxkjN?lang=zh-CN) 参考此教程，获取飞书，钉钉，企业微信的 webhook 和 secret（加签），在 cc_forward.lua 和 sms_forward.lua 脚本中找到 local webhook_feishu，secret_feishu，webhook_dingding，secret_dingding，webhook_weixin 的参数定义，修改为自己的参数。

4、Luatools 烧录内核固件和修改后的 demo 脚本代码

5、netdrv_device.lua中默认使用require "netdrv_4g"，即单4G网卡。

烧录成功后，代码会自动运行，log 日志打印以太网信息， wif 网络信息、CC_READY 等消息，log 日志打印如下：

```yaml
[2025-11-11 11:38:47.437][000000000.365] self_info 127:model Air780EHV_A10 imei 867920075014846
[2025-11-11 11:38:47.443][000000000.365] self_info 129:firmware[1] TTS+VOLTE
[2025-11-11 11:38:47.452][000000000.365] self_info 131:zone(kbytes) fs 768 script 512
[2025-11-11 11:38:47.456][000000000.366] I/main LuatOS@Air780EHV base 25.03 bsp V2016 32bit
[2025-11-11 11:38:47.461][000000000.366] I/main ROM Build: Oct 10 2025 10:52:53
[2025-11-11 11:38:47.465][000000000.369] W/pins /luadb/pins_AIR780EHV.json not exist!!
[2025-11-11 11:38:47.475][000000000.372] D/main loadlibs luavm 4194296 16096 16096
[2025-11-11 11:38:47.485][000000000.372] D/main loadlibs sys   3211688 104756 105984
[2025-11-11 11:38:47.491][000000000.372] D/main loadlibs psram 3211688 104848 106076
[2025-11-11 11:38:47.496][000000000.390] I/user.main cc_sms_forward 001.000.000
[2025-11-11 11:38:47.500][000000000.397] W/user.cc wait IP_READY 1 1
[2025-11-11 11:38:47.505][000000000.423] W/user.sntp_task_func wait IP_READY 1 1
[2025-11-11 11:38:47.785][000000001.398] W/user.cc wait IP_READY 1 1
[2025-11-11 11:38:47.816][000000001.424] W/user.sntp_task_func wait IP_READY 1 1
[2025-11-11 11:38:48.785][000000002.399] W/user.cc wait IP_READY 1 1
[2025-11-11 11:38:48.815][000000002.425] W/user.sntp_task_func wait IP_READY 1 1
[2025-11-11 11:38:49.789][000000003.400] W/user.cc wait IP_READY 1 1
[2025-11-11 11:38:49.818][000000003.425] W/user.sntp_task_func wait IP_READY 1 1
[2025-11-11 11:38:50.781][000000004.401] W/user.cc wait IP_READY 1 1
[2025-11-11 11:38:50.810][000000004.425] W/user.sntp_task_func wait IP_READY 1 1
[2025-11-11 11:38:51.790][000000005.402] W/user.cc wait IP_READY 1 1
[2025-11-11 11:38:51.821][000000005.426] W/user.sntp_task_func wait IP_READY 1 1
[2025-11-11 11:38:52.725][000000006.328] D/mobile cid1, state0
[2025-11-11 11:38:52.732][000000006.329] D/mobile bearer act 0, result 0
[2025-11-11 11:38:52.742][000000006.329] D/mobile TIME_SYNC 0
[2025-11-11 11:38:52.750][000000006.329] D/mobile NETIF_LINK_ON -> IP_READY
[2025-11-11 11:38:52.760][000000006.330] I/user.netdrv_4g.ip_ready_func IP_READY 10.183.48.180 255.255.255.255 0.0.0.0 nil
[2025-11-11 11:38:52.766][000000006.331] W/user.sntp_task_func recv IP_READY
[2025-11-11 11:38:52.773][000000006.332] D/sntp query ntp.aliyun.com
[2025-11-11 11:38:52.779][000000006.332] dns_run 676:ntp.aliyun.com state 0 id 1 ipv6 0 use dns server0, try 0
[2025-11-11 11:38:52.787][000000006.334] I/user.cc recv IP_READY 1 1
[2025-11-11 11:38:52.795][000000006.388] dns_run 693:dns all done ,now stop
[2025-11-11 11:38:53.031][000000006.649] D/sntp Unix timestamp: 1762832332
[2025-11-11 11:38:53.040][000000006.650] soc_cms_proc 2219:cenc report 1,51,1,15
[2025-11-11 11:38:53.049][000000006.654] I/user.sntp_task_func 时间同步成功 本地时间 Tue Nov 11 11:38:52 2025
[2025-11-11 11:38:53.057][000000006.654] I/user.sntp_task_func 时间同步成功 UTC时间 Tue Nov 11 03:38:52 2025
[2025-11-11 11:38:53.073][000000006.655] I/user.sntp_task_func 时间同步成功 RTC时钟(UTC时间) {"year":2025,"min":38,"hour":3,"mon":11,"sec":52,"day":11}
[2025-11-11 11:38:53.092][000000006.656] I/user.sntp_task_func 时间同步成功 本地时间戳 1762832332
[2025-11-11 11:38:53.102][000000006.657] I/user.sntp_task_func 时间同步成功 本地时间os.date() json格式 {"wday":3,"min":38,"yday":315,"hour":11,"isdst":false,"year":2025,"month":11,"sec":52,"day":11}
[2025-11-11 11:38:53.112][000000006.657] I/user.sntp_task_func 时间同步成功 本地时间os.date(os.time()) 1762861132
[2025-11-11 11:38:53.118][000000006.737] D/mobile NETIF_LINK_ON -> IP_READY
[2025-11-11 11:38:53.132][000000006.738] I/user.netdrv_4g.ip_ready_func IP_READY 10.183.48.180 255.255.255.255 0.0.0.0 nil
[2025-11-11 11:38:54.659][000000008.275] D/mobile ims reg state 0
[2025-11-11 11:38:54.670][000000008.276] D/mobile LUAT_MOBILE_EVENT_CC status 0
[2025-11-11 11:38:54.681][000000008.276] D/mobile LUAT_MOBILE_CC_READY
[2025-11-11 11:38:54.694][000000008.277] I/user.发送短信前wait CC_IND
[2025-11-11 11:38:54.699][000000008.278] I/user.现在可以收发短信
[2025-11-11 11:38:54.704][000000008.278] I/user.mobile.number(id) =  nil
[2025-11-11 11:38:54.714][000000008.278] I/user.mobile.iccid(id) =  89860325743780541565
[2025-11-11 11:38:54.719][000000008.279] I/user.mobile.simid(id) =  0
[2025-11-11 11:38:54.726][000000008.279] I/user.mobile.imsi(index) =  460115726670673
[2025-11-11 11:38:54.733][000000008.279] D/sms pdu len 18
[2025-11-11 11:38:54.744][000000008.281] I/user.通话准备完成，可以拨打电话或者呼入电话了


```

此处短信演示使用了电信卡，发送"102"给"10001"查询余额，会收到电信回复的短信，并转发到飞书、钉钉和微信，log 打印如下：

```bash
[2025-11-11 11:38:54.699][000000008.278] I/user.现在可以收发短信
[2025-11-11 11:38:54.704][000000008.278] I/user.mobile.number(id) =  nil
[2025-11-11 11:38:54.714][000000008.278] I/user.mobile.iccid(id) =  89860325743780541565
[2025-11-11 11:38:54.719][000000008.279] I/user.mobile.simid(id) =  0
[2025-11-11 11:38:54.726][000000008.279] I/user.mobile.imsi(index) =  460115726670673
[2025-11-11 11:38:54.733][000000008.279] D/sms pdu len 18
[2025-11-11 11:38:54.744][000000008.281] I/user.通话准备完成，可以拨打电话或者呼入电话了
[2025-11-11 11:38:55.279][000000008.900] luat_sms_proc 1239:[DIO 1239]: CMI_SMS_SEND_MSG_CNF is in
[2025-11-11 11:38:55.289][000000008.900] I/sms long sms callback seqNum = 1
[2025-11-11 11:38:56.251][000000009.867] luat_sms_proc 1236:[DIO 1236]: CMI_SMS_NEW_MSG_IND is in
[2025-11-11 11:38:56.264][000000009.868] D/sms dcs 2 | 0 | 0 | 0
[2025-11-11 11:38:56.272][000000009.869] I/sms long-sms, wait more frags 2/2
[2025-11-11 11:38:59.153][000000012.766] luat_sms_proc 1236:[DIO 1236]: CMI_SMS_NEW_MSG_IND is in
[2025-11-11 11:38:59.163][000000012.767] D/sms dcs 2 | 0 | 0 | 0
[2025-11-11 11:38:59.175][000000012.767] I/sms long-sms is ok
[2025-11-11 11:38:59.182][000000012.769] I/user.num是 10001
[2025-11-11 11:38:59.195][000000012.770] I/user.收到来自10001的短信：截止到2025年11月11日11时，本机可用余额:45.4元，帐户余额:45.4,欠费:0.0元 查询结果仅供参考，实际费用以出账单为准。更多服务请微信关注【河南电信】公众号，或下载欢go客户端( http://a.189.cn/JJTh4u )。
[2025-11-11 11:38:59.226][000000012.770] I/user.转发到飞书
[2025-11-11 11:38:59.235][000000012.772] I/user.timestamp 1762832338
[2025-11-11 11:38:59.245][000000012.772] I/user.sign hS1xPjJCUwNaWP5j/CZuZ+eVJOJ52rs7MZF1iOWSfcg=
[2025-11-11 11:38:59.257][000000012.773] I/user.url https://open.feishu.cn/open-apis/bot/v2/hook/bb089165-4b73-4f80-9ed0-da0c908b44e5
[2025-11-11 11:38:59.267][000000012.775] I/user.feishu {"content":{"text":"我的id是nil,Tue Nov 11 11:38:58 2025,Air780EHV,    10001发来短信，内容是:截止到2025年11月11日11时，本机可用余额:45.4元，帐户余额:45.4,欠费:0.0元 查询结果仅供参考，实际费用以出账单为准。更多服务请微信关注【河南电信】公众号，或下载欢go客户端( http:\/\/a.189.cn\/JJTh4u )。"},"sign":"hS1xPjJCUwNaWP5j\/CZuZ+eVJOJ52rs7MZF1iOWSfcg=","msg_type":"text","timestamp":"1762832338"}
[2025-11-11 11:38:59.274][000000012.781] dns_run 676:open.feishu.cn state 0 id 2 ipv6 0 use dns server0, try 0
[2025-11-11 11:38:59.285][000000012.825] dns_run 693:dns all done ,now stop
[2025-11-11 11:38:59.700][000000013.317] I/user.给10001发送查询短信 这是第1次发送  发送结果： true
[2025-11-11 11:39:00.405][000000014.017] I/user.feishu 200 {"StatusCode":0,"StatusMessage":"success","code":0,"data":{},"msg":"success"}
[2025-11-11 11:39:00.415][000000014.017] I/user.转发到钉钉
[2025-11-11 11:39:00.428][000000014.019] I/user.timestamp 1762832339000
[2025-11-11 11:39:00.439][000000014.019] I/user.sign kgaeJUMqVQfYzxpqu%2B80dTRY24V0PKZnhrV%2FnjcL69c%3D
[2025-11-11 11:39:00.445][000000014.019] I/user.url https://oapi.dingtalk.com/robot/send?access_token=03f4753ec6aa6f0524fb85907c94b17f3fa0fed3107d4e8f4eee1d4a97855f4d&timestamp=1762832339000&sign=kgaeJUMqVQfYzxpqu%2B80dTRY24V0PKZnhrV%2FnjcL69c%3D
[2025-11-11 11:39:00.462][000000014.021] I/user.dingding {"text":{"content":"我的id是nil,Tue Nov 11 11:38:59 2025,Air780EHV,    10001发来短信，内容是:截止到2025年11月11日11时，本机可用余额:45.4元，帐户余额:45.4,欠费:0.0元 查询结果仅供参考，实际费用以出账单为准。更多服务请微信关注【河南电信】公众号，或下载欢go客户端( http:\/\/a.189.cn\/JJTh4u )。"},"msgtype":"text"}
[2025-11-11 11:39:00.472][000000014.022] dns_run 676:oapi.dingtalk.com state 0 id 3 ipv6 0 use dns server0, try 0
[2025-11-11 11:39:00.486][000000014.066] dns_run 693:dns all done ,now stop
[2025-11-11 11:39:01.117][000000014.738] I/user.dingding 200 {"errcode":0,"errmsg":"ok"}
[2025-11-11 11:39:01.123][000000014.739] I/user.转发到微信
[2025-11-11 11:39:01.128][000000014.739] I/user.timestamp 1762832340000
[2025-11-11 11:39:01.145][000000014.739] I/user.url https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=71017f82-e027-4c5d-a618-eb4ee01750e9&timestamp=1762832340000
[2025-11-11 11:39:01.156][000000014.741] I/user.weixin {"text":{"content":"我的id是nil,Tue Nov 11 11:39:00 2025,Air780EHV,    10001发来短信，内容是:截止到2025年11月11日11时，本机可用余额:45.4元，帐户余额:45.4,欠费:0.0元 查询结果仅供参考，实际费用以出账单为准。更多服务请微信关注【河南电信】公众号，或下载欢go客户端( http:\/\/a.189.cn\/JJTh4u )。"},"msgtype":"text"}
[2025-11-11 11:39:01.174][000000014.742] dns_run 676:qyapi.weixin.qq.com state 0 id 4 ipv6 0 use dns server0, try 0
[2025-11-11 11:39:01.184][000000014.790] dns_run 693:dns all done ,now stop
[2025-11-11 11:39:02.307][000000015.930] I/user.weixin 200 {"errcode":0,"errmsg":"ok"}


```

此处来电转发演示使用了电信卡，用另外手机拨打模组上的电话号码，响铃 4声后自动挂断，log 打印如下：

```lua
[2025-11-11 11:39:31.138][000000044.751] D/mobile LUAT_MOBILE_EVENT_CC status 12
[2025-11-11 11:39:31.147][000000044.752] D/mobile LUAT_MOBILE_EVENT_CC status 1
[2025-11-11 11:39:31.151][000000044.752] I/user.获取最后一次通话的号码
[2025-11-11 11:39:31.160][000000044.754] I/user.来电号码是： 18317857567
[2025-11-11 11:39:31.163][000000044.754] I/user. 来电号码转发到飞书
[2025-11-11 11:39:31.166][000000044.755] I/user.timestamp 1762832370
[2025-11-11 11:39:31.175][000000044.756] I/user.sign Be6GXYvLRzO6iIBvvbkd1MzzecU0Vg+hxwF1uyRmFBc=
[2025-11-11 11:39:31.178][000000044.756] I/user.url https://open.feishu.cn/open-apis/bot/v2/hook/bb089165-4b73-4f80-9ed0-da0c908b44e5
[2025-11-11 11:39:31.182][000000044.757] I/user.feishu {"content":{"text":"我的id是nil,Tue Nov 11 11:39:30 2025,Air780EHV,    18317857567来电"},"sign":"Be6GXYvLRzO6iIBvvbkd1MzzecU0Vg+hxwF1uyRmFBc=","msg_type":"text","timestamp":"1762832370"}
[2025-11-11 11:39:31.190][000000044.759] dns_run 676:open.feishu.cn state 0 id 5 ipv6 0 use dns server0, try 0
[2025-11-11 11:39:31.194][000000044.761] D/mobile LUAT_MOBILE_EVENT_CC status 2
[2025-11-11 11:39:31.231][000000044.847] dns_run 693:dns all done ,now stop
[2025-11-11 11:39:32.101][000000045.724] I/user.feishu 200 {"StatusCode":0,"StatusMessage":"success","code":0,"data":{},"msg":"success"}
[2025-11-11 11:39:32.109][000000045.724] I/user.来电号码转发到钉钉
[2025-11-11 11:39:32.115][000000045.726] I/user.timestamp 1762832371000
[2025-11-11 11:39:32.129][000000045.726] I/user.sign 4%2B1ksJhCL5xqQ8zk%2BKrV7qTXq1EDtYqMISzyT5T2Ykg%3D
[2025-11-11 11:39:32.133][000000045.726] I/user.url https://oapi.dingtalk.com/robot/send?access_token=03f4753ec6aa6f0524fb85907c94b17f3fa0fed3107d4e8f4eee1d4a97855f4d&timestamp=1762832371000&sign=4%2B1ksJhCL5xqQ8zk%2BKrV7qTXq1EDtYqMISzyT5T2Ykg%3D
[2025-11-11 11:39:32.136][000000045.728] I/user.dingding {"text":{"content":"我的id是nil,Tue Nov 11 11:39:31 2025,Air780EHV,    18317857567来电"},"msgtype":"text"}
[2025-11-11 11:39:32.140][000000045.729] dns_run 676:oapi.dingtalk.com state 0 id 6 ipv6 0 use dns server0, try 0
[2025-11-11 11:39:32.178][000000045.776] dns_run 693:dns all done ,now stop
[2025-11-11 11:39:32.782][000000046.390] I/user.dingding 200 {"errcode":0,"errmsg":"ok"}
[2025-11-11 11:39:32.790][000000046.391] I/user.来电号码转发到微信
[2025-11-11 11:39:32.793][000000046.391] I/user.timestamp 1762832371000
[2025-11-11 11:39:32.795][000000046.392] I/user.url https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=71017f82-e027-4c5d-a618-eb4ee01750e9&timestamp=1762832371000
[2025-11-11 11:39:32.802][000000046.393] I/user.weixin {"text":{"content":"我的id是nil,Tue Nov 11 11:39:31 2025,Air780EHV,    18317857567来电"},"msgtype":"text"}
[2025-11-11 11:39:32.806][000000046.394] dns_run 676:qyapi.weixin.qq.com state 0 id 7 ipv6 0 use dns server0, try 0
[2025-11-11 11:39:32.811][000000046.428] dns_run 693:dns all done ,now stop
[2025-11-11 11:39:33.618][000000047.230] I/user.weixin 200 {"errcode":0,"errmsg":"ok"}
[2025-11-11 11:39:37.172][000000050.750] D/mobile LUAT_MOBILE_EVENT_CC status 1
[2025-11-11 11:39:43.140][000000056.750] D/mobile LUAT_MOBILE_EVENT_CC status 1
[2025-11-11 11:39:49.137][000000062.750] D/mobile LUAT_MOBILE_EVENT_CC status 1
[2025-11-11 11:39:49.179][000000062.757] luat_i2s_load_old_config 287:i2s0 old param not saved!
[2025-11-11 11:39:49.204][000000062.757] D/cc VOLTE_EVENT_PLAY_STOP
[2025-11-11 11:39:49.223][000000062.758] D/mobile LUAT_MOBILE_EVENT_CC status 12
[2025-11-11 11:39:49.293][000000062.911] soc_cms_proc 2219:cenc report 1,38,1,7
[2025-11-11 11:39:49.322][000000062.912] D/mobile cid7, state2
[2025-11-11 11:39:51.135][000000064.754] D/mobile LUAT_MOBILE_EVENT_CC status 10


```
