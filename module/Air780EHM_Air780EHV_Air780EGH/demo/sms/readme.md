## 功能模块介绍

1、main.lua：主程序入口；

2、netdrv_device.lua：网卡驱动设备，可以配置使用netdrv文件夹内的四种网卡(单4g网卡，单wifi网卡，单spi以太网卡，多网卡)中的任何一种网卡；

3、sms_app.lua：短信发送+短信接收+短信转发到企业微信/钉钉/飞书平台功能模块； 

4、sntp_app.lua：sntp时间同步功能模块

## 演示功能概述

使用Air780EHV/EHM/EGH 核心板测试sms功能

1、短信发送功能；

2、短信接收功能；

3、netdrv_device：短信通过http转发到企业微信/钉钉/飞书平台时，配置连接外网使用的网卡，目前支持以下四种选择（四选一）

(1) netdrv_4g：4G网卡

(2) netdrv_eth_spi：通过SPI外挂CH390H芯片的以太网卡

(3) netdrv_multiple：支持以上两种网卡，可以配置两种网卡的优先级

(4) netdrv_pc: pc模拟器网卡

4、NTP时间同步

## 演示硬件环境

[](https://docs.openluat.com/air780ehv/luatos/common/hwenv/image/Air780EHV.png)

1、Air780EHV/EHM/EGH 核心板一块+手机sim卡一张：

* sim卡插入开发板的sim卡槽；

* 可选AirETH_1000配件板一块，Air780EXX核心板和AirETH_1000配件板的硬件接线方式为:

| Air780EXX核心板 | AirETH_1000配件板 |
| ------------ | -------------- |
| 3V3          | 3.3v           |
| gnd          | gnd            |
| 86/SPI0CLK   | SCK            |
| 83/SPI0CS    | CSS            |
| 84/SPI0MISO  | SDO            |
| 85/SPI0MOSI  | SDI            |
| 107/GPIO21   | INT            |


2、TYPE-C USB数据线一根 + USB转串口数据线一根，Air780EHV/EHM/EGH 核心板和数据线的硬件接线方式为：

* Air780EHV/EHM/EGH 核心板通过TYPE-C USB口供电；（供电拨动开关 拨到 USB供电一端）

* TYPE-C USB数据线直接插到核心板的TYPE-C USB座子，另外一端连接电脑USB口；

## 演示软件环境

1、Luatools下载调试工具

2、[必须使用Air780EHM V2018或者更高版本](https://docs.openluat.com/air780epm/luatos/firmware/version/)

[必须使用Air780EHV V2018或者更高版本](https://docs.openluat.com/air780ehv/luatos/firmware/version/)

[必须使用Air780EGH V2018或者更高版本](https://docs.openluat.com/air780egh/luatos/firmware/version/)

## 演示核心步骤

1、搭建好硬件环境0

2、demo脚本代码netdrv_device.lua中，按照自己的网卡需求启用对应的Lua文件

* 如果需要单4G网卡，打开require "netdrv_4g"，其余注释掉

* 如果需要以太网卡，打开require "netdrv_eth_spi"，其余注释掉

* 如果需要多网卡，打开require "netdrv_multiple"，其余注释掉；

3、修改sms_forward.lua文件中的webhook_feishu和webhook_dingding以及webhook_weixi，如需加密也可以填写对应app的secret。

3、烧录内核固件和sms相关demo成功后，自动开机运行。

4、可以看到代码运行结果如下，不管是在选择什么网卡场景下，基本都是如下情况：

以下是默认使用4G网卡下使用sms demo演示的日志

日志中如果出现以下类似打印则说明短信转发成功：

```
[2025-11-13 16:43:50.370][000000004.268] I/user.现在可以收发短信

[2025-11-13 16:43:50.375][000000004.268] I/user.mobile.number(id) =  +8617374070417

[2025-11-13 16:43:50.378][000000004.269] I/user.mobile.iccid(id) =  89861123045773964016

[2025-11-13 16:43:50.383][000000004.269] I/user.mobile.simid(id) =  0

[2025-11-13 16:43:50.389][000000004.270] I/user.mobile.imsi(index) =  460115188098492

[2025-11-13 16:43:50.393][000000004.270] D/sms pdu len 18

[2025-11-13 16:43:50.396][000000004.272] I/user.发送查询短信 这是第1次发送  发送结果： 成功

[2025-11-13 16:43:50.401][000000004.272] I/user.等待10分钟

[2025-11-13 16:43:50.764][000000004.689] luat_sms_proc 1239:[DIO 1239]: CMI_SMS_SEND_MSG_CNF is in

[2025-11-13 16:43:50.771][000000004.689] D/sms long sms callback seqNum = 1

[2025-11-13 16:43:50.779][000000004.691] I/user.sms send result true

[2025-11-13 16:43:51.983][000000005.903] luat_sms_proc 1236:[DIO 1236]: CMI_SMS_NEW_MSG_IND is in

[2025-11-13 16:43:51.990][000000005.904] D/sms dcs 2 | 0 | 0 | 0

[2025-11-13 16:43:51.994][000000005.904] I/sms long-sms, wait more frags 2/3

[2025-11-13 16:43:52.312][000000006.234] luat_sms_proc 1236:[DIO 1236]: CMI_SMS_NEW_MSG_IND is in

[2025-11-13 16:43:52.318][000000006.235] D/sms dcs 2 | 0 | 0 | 0

[2025-11-13 16:43:52.323][000000006.235] I/sms long-sms, wait more frags 1/3

[2025-11-13 16:43:52.561][000000006.482] luat_sms_proc 1236:[DIO 1236]: CMI_SMS_NEW_MSG_IND is in

[2025-11-13 16:43:52.568][000000006.482] D/sms dcs 2 | 0 | 0 | 0

[2025-11-13 16:43:52.578][000000006.483] I/sms long-sms, wait more frags 2/3

[2025-11-13 16:43:52.828][000000006.746] luat_sms_proc 1236:[DIO 1236]: CMI_SMS_NEW_MSG_IND is in

[2025-11-13 16:43:52.838][000000006.746] D/sms dcs 2 | 0 | 0 | 0

[2025-11-13 16:43:52.849][000000006.747] I/sms long-sms is ok

[2025-11-13 16:43:52.861][000000006.749] I/user.收到来自短信： 10001

[2025-11-13 16:43:52.869][000000006.749] I/user.num是 10001

[2025-11-13 16:43:52.877][000000006.750] I/user.收到来自10001的短信：尊敬的用户：截至11月13日16时42分，您的账户使用情况如下：
本月消费：15.60元
可用余额：21.84元
仅供参考，实际费用以出账账单为准。更多详情点击：http://a.189.cn/IRAYnu 进入“中国电信”APP。也可关注“浙江电信”微信公众号进行快速查询：https://qy.k189.cn/hfcx?source=dt

[2025-11-13 16:43:52.882][000000006.750] I/user.当前网络 true 1

[2025-11-13 16:43:52.891][000000006.751] I/user.转发到飞书

[2025-11-13 16:43:52.895][000000006.752] I/user.timestamp 1763023432

[2025-11-13 16:43:52.899][000000006.753] I/user.sign QHEIo55ZRHLWyEuYuZ+7Z1wXzNWOcameWshNHBMetrM=

[2025-11-13 16:43:52.902][000000006.753] I/user.url https://open.feishu.cn/open-apis/bot/v2/hook/673d1e1d-0c7e-4d34-b7f0-48bdb4c4d03a

[2025-11-13 16:43:52.909][000000006.755] I/user.feishu 

[2025-11-13 16:43:52.913][000000006.755] {"content":{"text":"我的id是nil,Thu Nov 13 16:43:52 2025,Air780EGH,    10001发来短信，内容是:尊敬的用户：截至11月13日16时42分，您的账户使用情况如下：\n本月消费：15.60元\n可用余额：21.84元\n仅供参考，实际费用以出账账单为准。更多详情点击：http:\/\/a.189.cn\/IRAYnu 进入“中国电信”APP。也可关注“浙江电信”微信公众号进行快速查询：https:\/\/qy.k189.cn\/hfcx?source=dt"},"sign":"QHEIo55ZRHLWyEuYuZ+7Z1wXzNWOcameWshNHBMetrM=","msg_type":"text","timestamp":"1763023432"}

[2025-11-13 16:43:52.918][000000006.761] dns_run 676:open.feishu.cn state 0 id 2 ipv6 0 use dns server2, try 0

[2025-11-13 16:43:52.923][000000006.796] dns_run 693:dns all done ,now stop

[2025-11-13 16:43:53.405][000000007.319] luat_sms_proc 1236:[DIO 1236]: CMI_SMS_NEW_MSG_IND is in

[2025-11-13 16:43:53.411][000000007.322] D/sms dcs 2 | 0 | 0 | 0

[2025-11-13 16:43:53.415][000000007.322] I/sms long-sms, wait more frags 1/3

[2025-11-13 16:43:53.687][000000007.612] luat_sms_proc 1236:[DIO 1236]: CMI_SMS_NEW_MSG_IND is in

[2025-11-13 16:43:53.695][000000007.613] D/sms dcs 2 | 0 | 0 | 0

[2025-11-13 16:43:53.705][000000007.613] I/sms long-sms is ok

[2025-11-13 16:43:54.072][000000007.988] I/user.飞书机器人 success 200 

[2025-11-13 16:43:54.080][000000007.989] {"Request-Id":"1c222dde-8b17-4fda-9abf-2991768ba2ec","X-Lgw-Dst-Svc":"EQwbqA8xDu2dP1kwlU7XzoUdaYWcyx65Bd7EV5Cfg7FDWagbqvSwL6i6ZIZQuk9SPKRp-TLw1YUlWWI1x-qDMK3lcIz3tQMtsb2sNiaoXQANO6idlDedangOCOFppmjl0Vy5medc5dgm3Uvb-DgVlhY97GRJcGcNvC6P_0OcwcSKaS3XH4lhk-viLlzNxzMtJ6jZm7jMW6WDekreEvsQQ6HWqQgpKd0JICazwOIFu96PjqOCkCPiVUUljiIo0UCjP-shVTy85ONU6hMNl_HTYqEQDtSn4k3bchCFVzf7IkrMJ9dQWLR3Pr2KdmtbQfON0SK_a2wWbbp7Bm5MjuhBnVUgauLLrBqDGP25qNzriWz9nX8=","Content-Length":"77","Via":"vcache4.cn1402[378,0]","X-Timestamp":"1763023434.054","x-tt-trace-id":"00-2511131643537EAC40147A978E68587F-67C8D1137A67669F-00","Date":"Thu, 13 Nov 2025 08:43:54 GMT","x-tt-trace-host":"01d37834a09535440d46e83bd3a0cfdf5fc40094e9cf88383df3976d2ca0bd9a896bc5e0b884a8c8636ca2a8b49cd94af7f8fd8c45a543446d0c891f535407f62ea62bc2a07250746a924b3bc7dd92abd898d4600d8b4d6c28fb83755992837c5f","X-Tt-Logid":"202511131643537EAC40147A978E68587F","Server":"Tengine","server-timing":"cdn-cache;desc=MISS,edge;dur=0,origin;dur=378","Tt_stable":"1","x-tt-trace-tag":"id=03;cdn-cache=miss;type=dyn","Content-Type":"application\/json","X-Request-Id":"1c222dde-8b17-4fda-9abf-2991768ba2ec","Timing-Allow-Origin":"*","Connection":"keep-alive","EagleId":"65597d2f17630234336914604e"}

[2025-11-13 16:43:54.096][000000007.989]  {"StatusCode":0,"StatusMessage":"success","code":0,"data":{},"msg":"success"}

[2025-11-13 16:43:55.075][000000008.989] I/user.转发到钉钉

[2025-11-13 16:43:55.077][000000008.991] I/user.timestamp 1763023434000

[2025-11-13 16:43:55.077][000000008.992] I/user.sign l8hDqbTRGULV7bSavPYMaTxmaM59WKmcbifRHwNxzzw%3D

[2025-11-13 16:43:55.078][000000008.992] I/user.url https://oapi.dingtalk.com/robot/send?access_token=bf9fe5c74194b9556cff401b87ac5de46a92bbf15cc226b73d14c28773b86f3b&timestamp=1763023434000&sign=l8hDqbTRGULV7bSavPYMaTxmaM59WKmcbifRHwNxzzw%3D

[2025-11-13 16:43:55.079][000000008.993] I/user.dingding {"text":{"content":"我的id是nil,Thu Nov 13 16:43:54 2025,Air780EGH,    10001发来短信，内容是:尊敬的用户：截至11月13日16时42分，您的账户使用情况如下：\n本月消费：15.60元\n可用余额：21.84元\n仅供参考，实际费用以出账账单为准。更多详情点击：http:\/\/a.189.cn\/IRAYnu 进入“中国电信”APP。也可关注“浙江电信”微信公众号进行快速查询：https:\/\/qy.k189.cn\/hfcx?source=dt"},"msgtype":"text"}

[2025-11-13 16:43:55.079][000000008.995] dns_run 676:oapi.dingtalk.com state 0 id 3 ipv6 0 use dns server2, try 0

[2025-11-13 16:43:55.120][000000009.033] dns_run 693:dns all done ,now stop

[2025-11-13 16:43:55.847][000000009.762] I/user.钉钉机器人 success 200 {"Cache-Control":"no-cache","Date":"Thu, 13 Nov 2025 08:43:55 GMT","Connection":"keep-alive","Server":"DingTalk\/1.0.0","Content-Length":"27","Content-Type":"application\/json"} {"errcode":0,"errmsg":"ok"}

[2025-11-13 16:43:56.848][000000010.763] I/user.转发到微信

[2025-11-13 16:43:56.854][000000010.764] I/user.timestamp 1763023436000

[2025-11-13 16:43:56.856][000000010.764] I/user.url https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=a9dec355-3e0f-45bf-a0b1-0f8813fe6b7d&timestamp=1763023436000

[2025-11-13 16:43:56.859][000000010.765] I/user.weixin {"text":{"content":"我的id是nil,Thu Nov 13 16:43:56 2025,Air780EGH,    10001发来短信，内容是:尊敬的用户：截至11月13日16时42分，您的账户使用情况如下：\n本月消费：15.60元\n可用余额：21.84元\n仅供参考，实际费用以出账账单为准。更多详情点击：http:\/\/a.189.cn\/IRAYnu 进入“中国电信”APP。也可关注“浙江电信”微信公众号进行快速查询：https:\/\/qy.k189.cn\/hfcx?source=dt"},"msgtype":"text"}

[2025-11-13 16:43:56.862][000000010.767] dns_run 676:qyapi.weixin.qq.com state 0 id 4 ipv6 0 use dns server2, try 0

[2025-11-13 16:43:56.895][000000010.818] dns_run 693:dns all done ,now stop

[2025-11-13 16:43:57.681][000000011.601] I/user.企业微信机器人 success 200 {"Content-Type":"application\/json; charset=UTF-8","Server":"nginx","Error-Code":"0","Date":"Thu, 13 Nov 2025 08:43:57 GMT","Connection":"keep-alive","Content-Length":"27","Error-Msg":"ok","X-W-No":"5"} {"errcode":0,"errmsg":"ok"}



```
