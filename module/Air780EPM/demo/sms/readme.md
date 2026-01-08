## 功能模块介绍

1、main.lua：主程序入口；

2、sms_app.lua：短信发送+短信接收+短信转发到企业微信/钉钉/飞书平台功能模块； 

3、sntp_app.lua：sntp时间同步功能模块

## 演示功能概述

使用Air780EPM 开发板测试sms功能

1、短信发送功能；

2、短信接收功能；

3、NTP时间同步

## 演示硬件环境

![img](https://docs.openluat.com/air780epm/luatos/app/driver/eth/image/RFSvb75NRoEWqYxfCRVcVrOKnsf.jpg)

1、Air780EPM V1.3版本开发板一块+手机sim卡一张+4g天线一根：

- sim卡插入开发板的sim卡槽

- 天线装到开发板上

2、TYPE-C USB数据线一根 + USB转串口数据线一根，Air780EPM V1.3版本开发板和数据线的硬件接线方式为：

- Air780EPM V1.3版本开发板通过TYPE-C USB口供电；（外部供电/USB供电 拨动开关 拨到 USB供电一端）

- TYPE-C USB数据线直接插到开发板的TYPE-C USB座子，另外一端连接电脑USB口；

## 演示软件环境

1、Luatools下载调试工具

2、[必须使用Air780EPM V2018或者更高版本](https://docs.openluat.com/air780epm/luatos/firmware/version/)（理论上最新版本固件也可以，如果使用最新版本的固件不可以，可以烧录V2018-106固件对比验证）

## 演示核心步骤

1、搭建好硬件环境

2、修改sms_forward.lua文件中的webhook_feishu和webhook_dingding以及webhook_weixi，如需加密也可以填写对应app的secret。

3、烧录内核固件和sms相关demo成功后，自动开机运行。

4、可以看到代码运行结果如下，基本都是如下情况：

以下是使用sms demo演示的日志

日志中如果出现以下类似打印则说明短信转发成功：

```
[2025-11-13 17:06:24.610][000000007.198] I/user.现在可以收发短信

[2025-11-13 17:06:24.618][000000007.199] I/user.mobile.number(id) =  +8617374070417

[2025-11-13 17:06:24.621][000000007.199] I/user.mobile.iccid(id) =  89861123045773964016

[2025-11-13 17:06:24.627][000000007.199] I/user.mobile.simid(id) =  0

[2025-11-13 17:06:24.631][000000007.200] I/user.mobile.imsi(index) =  460115188098492

[2025-11-13 17:06:24.636][000000007.200] D/sms pdu len 18

[2025-11-13 17:06:24.639][000000007.202] I/user.发送查询短信 这是第1次发送  发送结果： 成功

[2025-11-13 17:06:24.644][000000007.202] I/user.等待10分钟

[2025-11-13 17:06:24.790][000000007.384] luat_sms_proc 1239:[DIO 1239]: CMI_SMS_SEND_MSG_CNF is in

[2025-11-13 17:06:24.797][000000007.385] D/sms long sms callback seqNum = 1

[2025-11-13 17:06:24.801][000000007.386] I/user.sms send result true

[2025-11-13 17:06:26.549][000000009.138] luat_sms_proc 1236:[DIO 1236]: CMI_SMS_NEW_MSG_IND is in

[2025-11-13 17:06:26.572][000000009.138] D/sms dcs 2 | 0 | 0 | 0

[2025-11-13 17:06:26.587][000000009.139] I/sms long-sms, wait more frags 1/3

[2025-11-13 17:06:26.653][000000009.245] luat_sms_proc 1236:[DIO 1236]: CMI_SMS_NEW_MSG_IND is in

[2025-11-13 17:06:26.658][000000009.246] D/sms dcs 2 | 0 | 0 | 0

[2025-11-13 17:06:26.664][000000009.246] I/sms long-sms, wait more frags 2/3

[2025-11-13 17:06:26.861][000000009.455] luat_sms_proc 1236:[DIO 1236]: CMI_SMS_NEW_MSG_IND is in

[2025-11-13 17:06:26.889][000000009.455] D/sms dcs 2 | 0 | 0 | 0

[2025-11-13 17:06:26.908][000000009.455] I/sms long-sms is ok

[2025-11-13 17:06:26.924][000000009.457] I/user.收到来自短信： 10001

[2025-11-13 17:06:26.942][000000009.457] I/user.num是 10001

[2025-11-13 17:06:26.956][000000009.458] I/user.收到来自10001的短信：尊敬的用户：截至11月13日17时6分，您的账户使用情况如下：
本月消费：15.60元
可用余额：21.84元
仅供参考，实际费用以出账账单为准。更多详情点击：http://a.189.cn/IRAYnu 进入“中国电信”APP。也可关注“浙江电信”微信公众号进行快速查询：https://qy.k189.cn/hfcx?source=dt

[2025-11-13 17:06:26.974][000000009.458] I/user.当前网络 true 1

[2025-11-13 17:06:26.987][000000009.458] I/user.转发到飞书

[2025-11-13 17:06:26.995][000000009.460] I/user.timestamp 1763024786

[2025-11-13 17:06:27.003][000000009.460] I/user.sign 5cVjGl0UHK4BZiBTdjBfjzTE8a35JEmTQK/rXf75oLg=

[2025-11-13 17:06:27.015][000000009.460] I/user.url https://open.feishu.cn/open-apis/bot/v2/hook/673d1e1d-0c7e-4d34-b7f0-48bdb4c4d03a

[2025-11-13 17:06:27.025][000000009.462] I/user.feishu 

[2025-11-13 17:06:27.040][000000009.462] {"content":{"text":"我的id是nil,Thu Nov 13 17:06:26 2025,Air780EPM,    10001发来短信，内容是:尊敬的用户：截至11月13日17时6分，您的账户使用情况如下：\n本月消费：15.60元\n可用余额：21.84元\n仅供参考，实际费用以出账账单为准。更多详情点击：http:\/\/a.189.cn\/IRAYnu 进入“中国电信”APP。也可关注“浙江电信”微信公众号进行快速查询：https:\/\/qy.k189.cn\/hfcx?source=dt"},"sign":"5cVjGl0UHK4BZiBTdjBfjzTE8a35JEmTQK\/rXf75oLg=","msg_type":"text","timestamp":"1763024786"}

[2025-11-13 17:06:27.054][000000009.467] dns_run 676:open.feishu.cn state 0 id 2 ipv6 0 use dns server2, try 0

[2025-11-13 17:06:27.067][000000009.488] dns_run 693:dns all done ,now stop

[2025-11-13 17:06:27.978][000000010.568] I/user.飞书机器人 success 200 

[2025-11-13 17:06:27.991][000000010.568] {"Request-Id":"8b2b41bb-44fb-407e-a8ec-d7227179de61","X-Lgw-Dst-Svc":"aiRj-YZHJsmNioW5sRb1upcRDZKIYZgCiYCAuFKmezjGgFkw3Oe1lIOCyvhP_Tbkq8sMeWcR51hfWhQREaNR7XZZN_6jaoXyeKbKzxpJrUso_-lOboFMGg6LjrNjJrjvrdYhVd5fvKkNKkUf-sAMG-BN_ukN8d0A5HuDZNRFu4krRWwvY3Ee1UEjwIIS9IiHAGYb7HVYNS_NasM_sSXDswFx41MqTr9m9Yl_tY5bwOh1P0-dZRPL2GI61HqmhbaL0wR3NG8_Ppr3ZtvmLstaKA_CtycSJNqyd967TLYAUGPnCt6yyCMhH5skrUex-z6yzeQBM-jA8QLlaoPYrminYmhniN8NbRk0DiUjymWP9z8vGgs=","Content-Length":"77","Via":"vcache10.cn1402[393,0]","X-Timestamp":"1763024787.823","x-tt-trace-id":"00-251113170627B62D987D40E5B056503D-528A6D0B755B43FB-00","Date":"Thu, 13 Nov 2025 09:06:27 GMT","x-tt-trace-host":"01aa075810167c68795fcfe90f58fc27e8e757cc9914653a0080ebb138fb9e2e3f9b6bc2a8693e676821e360d1544d5c7a26bf0e1b103a5e197317b89ab6e941264ec78bcf2248fb662438b17b75f606f9cf951d77da3c828cae140a86c9d631d9","X-Tt-Logid":"20251113170627B62D987D40E5B056503D","Server":"Tengine","server-timing":"cdn-cache;desc=MISS,edge;dur=0,origin;dur=393","Tt_stable":"1","x-tt-trace-tag":"id=03;cdn-cache=miss;type=dyn","Content-Type":"application\/json","X-Request-Id":"8b2b41bb-44fb-407e-a8ec-d7227179de61","Timing-Allow-Origin":"*","Connection":"keep-alive","EagleId":"65597d1e17630247874392399e"}

[2025-11-13 17:06:28.006][000000010.568]  {"StatusCode":0,"StatusMessage":"success","code":0,"data":{},"msg":"success"}

[2025-11-13 17:06:28.973][000000011.569] I/user.转发到钉钉

[2025-11-13 17:06:28.979][000000011.570] I/user.timestamp 1763024788000

[2025-11-13 17:06:28.983][000000011.571] I/user.sign HOgxLj23Pl%2B3%2FMJ%2BAAyU%2FJXz7AwAMk%2BvqK0CrcxJqXA%3D

[2025-11-13 17:06:28.987][000000011.571] I/user.url https://oapi.dingtalk.com/robot/send?access_token=bf9fe5c74194b9556cff401b87ac5de46a92bbf15cc226b73d14c28773b86f3b&timestamp=1763024788000&sign=HOgxLj23Pl%2B3%2FMJ%2BAAyU%2FJXz7AwAMk%2BvqK0CrcxJqXA%3D

[2025-11-13 17:06:29.005][000000011.572] I/user.dingding {"text":{"content":"我的id是nil,Thu Nov 13 17:06:28 2025,Air780EPM,    10001发来短信，内容是:尊敬的用户：截至11月13日17时6分，您的账户使用情况如下：\n本月消费：15.60元\n可用余额：21.84元\n仅供参考，实际费用以出账账单为准。更多详情点击：http:\/\/a.189.cn\/IRAYnu 进入“中国电信”APP。也可关注“浙江电信”微信公众号进行快速查询：https:\/\/qy.k189.cn\/hfcx?source=dt"},"msgtype":"text"}

[2025-11-13 17:06:29.023][000000011.574] dns_run 676:oapi.dingtalk.com state 0 id 3 ipv6 0 use dns server2, try 0

[2025-11-13 17:06:29.034][000000011.631] dns_run 693:dns all done ,now stop

[2025-11-13 17:06:29.767][000000012.360] I/user.钉钉机器人 success 200 {"Cache-Control":"no-cache","Date":"Thu, 13 Nov 2025 09:06:29 GMT","Connection":"keep-alive","Server":"DingTalk\/1.0.0","Content-Length":"27","Content-Type":"application\/json"} {"errcode":0,"errmsg":"ok"}

[2025-11-13 17:06:30.766][000000013.361] I/user.转发到微信

[2025-11-13 17:06:30.788][000000013.361] I/user.timestamp 1763024790000

[2025-11-13 17:06:30.809][000000013.362] I/user.url https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=a9dec355-3e0f-45bf-a0b1-0f8813fe6b7d&timestamp=1763024790000

[2025-11-13 17:06:30.823][000000013.363] I/user.weixin {"text":{"content":"我的id是nil,Thu Nov 13 17:06:30 2025,Air780EPM,    10001发来短信，内容是:尊敬的用户：截至11月13日17时6分，您的账户使用情况如下：\n本月消费：15.60元\n可用余额：21.84元\n仅供参考，实际费用以出账账单为准。更多详情点击：http:\/\/a.189.cn\/IRAYnu 进入“中国电信”APP。也可关注“浙江电信”微信公众号进行快速查询：https:\/\/qy.k189.cn\/hfcx?source=dt"},"msgtype":"text"}

[2025-11-13 17:06:30.841][000000013.365] dns_run 676:qyapi.weixin.qq.com state 0 id 4 ipv6 0 use dns server2, try 0

[2025-11-13 17:06:30.853][000000013.408] dns_run 693:dns all done ,now stop

[2025-11-13 17:06:31.647][000000014.239] I/user.企业微信机器人 success 200 {"Content-Type":"application\/json; charset=UTF-8","Server":"nginx","Error-Code":"0","Date":"Thu, 13 Nov 2025 09:06:31 GMT","Connection":"keep-alive","Content-Length":"27","Error-Msg":"ok","X-W-No":"4"} {"errcode":0,"errmsg":"ok"}



```
