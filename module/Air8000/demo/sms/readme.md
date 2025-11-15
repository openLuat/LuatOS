## 功能模块介绍

1、main.lua：主程序入口；

2、netdrv_device.lua：网卡驱动设备，可以配置使用netdrv文件夹内的四种网卡(单4g网卡，单wifi网卡，单spi以太网卡，多网卡)中的任何一种网卡；

3、sms_app.lua：短信发送+短信接收+短信转发到企业微信/钉钉/飞书平台功能模块； 

4、sntp_app.lua：sntp时间同步功能模块

## 演示功能概述

使用Air8000开发板测试sms功能

1、短信发送功能；

2、短信接收功能；

3、netdrv_device：短信通过http转发到企业微信/钉钉/飞书平台时，配置连接外网使用的网卡，目前支持以下四种选择（四选一）

(1) netdrv_4g：4G网卡

(2) netdrv_wifi：WIFI STA网卡

(3) netdrv_eth_spi：通过SPI外挂CH390H芯片的以太网卡

(4) netdrv_multiple：支持以上三种网卡，可以配置三种网卡的优先级

4、NTP时间同步

## 演示硬件环境

[](https://docs.openluat.com/air8000/luatos/app/image/netdrv_multi.jpg)

1、Air8000开发板一块+手机sim卡一张+4g天线一根+wifi天线一根+网线一根：

* sim卡插入开发板的sim卡槽

* 天线装到开发板上

* 网线一端插入开发板网口，另外一端连接可以上外网的路由器网口

2、TYPE-C USB数据线一根 + USB转串口数据线一根，Air8000开发板和数据线的硬件接线方式为：

* Air8000开发板通过TYPE-C USB口供电；（外部供电/USB供电 拨动开关 拨到 USB供电一端）

* TYPE-C USB数据线直接插到核心板的TYPE-C USB座子，另外一端连接电脑USB口；

## 演示软件环境

1、Luatools下载调试工具

2、[必须使用Air8000 V2018或者更高版本](https://gitee.com/openLuat/LuatOS/tree/master/module/Air8000/core)（理论上最新版本固件也可以，如果使用最新版本的固件不可以，可以烧录V2018-1固件对比验证）

## 演示核心步骤

1、搭建好硬件环境

2、demo脚本代码netdrv_device.lua中，按照自己的网卡需求启用对应的Lua文件

* 如果需要单4G网卡，打开require "netdrv_4g"，其余注释掉

* 如果需要单WIFI STA网卡，打开require "netdrv_wifi"，其余注释掉；同时netdrv_wifi.lua中的wlan.connect("茶室-降功耗,找合宙!", "Air123456", 1)，前两个参数，修改为自己测试时wifi热点的名称和密码；注意：仅支持2.4G的wifi，不支持5G的wifi

* 如果需要以太网卡，打开require "netdrv_eth_spi"，其余注释掉

* 如果需要多网卡，打开require "netdrv_multiple"，其余注释掉；同时netdrv_multiple.lua中的ssid = "茶室-降功耗,找合宙!", password = "Air123456", 修改为自己测试时wifi热点的名称和密码；注意：仅支持2.4G的wifi，不支持5G的wifi

3、修改sms_forward.lua文件中的webhook_feishu和webhook_dingding以及webhook_weixi，如需加密也可以填写对应app的secret，打开对应运营商的查话费代码

3、烧录内核固件和sms相关demo成功后，自动开机运行。

4、可以看到代码运行结果如下，不管是在选择什么网卡场景下，基本都是如下情况：

以下是默认使用4G网卡下使用sms demo演示的日志

日志中如果出现以下类似打印则说明短信转发成功：

```
[2025-10-15 20:14:01.867][000000008.505] I/user.现在可以收发短信

[2025-10-15 20:14:01.887][000000008.505] I/user.mobile.number(id) =  +8617374070417

[2025-10-15 20:14:01.910][000000008.506] I/user.mobile.iccid(id) =  89861123045773964016

[2025-10-15 20:14:01.927][000000008.506] I/user.mobile.simid(id) =  0

[2025-10-15 20:14:01.944][000000008.506] I/user.mobile.imsi(index) =  460115188098492

[2025-10-15 20:14:01.961][000000008.507] D/sms pdu len 18

[2025-10-15 20:14:01.979][000000008.508] I/user.发送查询短信 这是第1次发送  发送结果： 成功

[2025-10-15 20:14:02.017][000000008.817] luat_sms_proc 1239:[DIO 1239]: CMI_SMS_SEND_MSG_CNF is in

[2025-10-15 20:14:02.034][000000008.817] I/sms long sms callback seqNum = 1

[2025-10-15 20:14:03.802][000000010.607] luat_sms_proc 1236:[DIO 1236]: CMI_SMS_NEW_MSG_IND is in

[2025-10-15 20:14:03.835][000000010.607] D/sms dcs 2 | 0 | 0 | 0

[2025-10-15 20:14:03.859][000000010.608] I/sms long-sms, wait more frags 3/3

[2025-10-15 20:14:03.943][000000010.751] luat_sms_proc 1236:[DIO 1236]: CMI_SMS_NEW_MSG_IND is in

[2025-10-15 20:14:03.994][000000010.752] D/sms dcs 2 | 0 | 0 | 0

[2025-10-15 20:14:04.012][000000010.752] I/sms long-sms, wait more frags 1/3

[2025-10-15 20:14:04.145][000000010.951] luat_sms_proc 1236:[DIO 1236]: CMI_SMS_NEW_MSG_IND is in

[2025-10-15 20:14:04.165][000000010.951] D/sms dcs 2 | 0 | 0 | 0

[2025-10-15 20:14:04.182][000000010.952] I/sms long-sms is ok

[2025-10-15 20:14:04.198][000000010.954] I/user.收到来自短信： 10001

[2025-10-15 20:14:04.217][000000010.954] I/user.num是 10001

[2025-10-15 20:14:04.238][000000010.955] I/user.收到来自10001的短信：尊敬的用户：截至10月15日20时14分，您的账户使用情况如下：
本月消费：17.61元
可用余额：28.83元
仅供参考，实际费用以出账账单为准。更多详情点击：http://a.189.cn/IRAYnu 进入“中国电信”APP。也可关注“浙江电信”微信公众号进行快速查询：https://qy.k189.cn/hfcx?source=dt

[2025-10-15 20:14:04.262][000000010.955] I/user.当前网络 true 1

[2025-10-15 20:14:04.284][000000010.956] I/user.当前wifi网络情况 true 1

[2025-10-15 20:14:04.306][000000010.956] I/user.转发到飞书

[2025-10-15 20:14:04.323][000000010.957] I/user.timestamp 1760530443

[2025-10-15 20:14:04.340][000000010.958] I/user.sign 4bHYm0YfpVjsdPIEugQBGfjuuyCYnI+Jjaf8K1zYqwo=

[2025-10-15 20:14:04.358][000000010.958] I/user.url https://open.feishu.cn/open-apis/bot/v2/hook/673d1e1d-0c7e-4d34-b7f0-48bdb4c4d03a

[2025-10-15 20:14:04.384][000000010.959] I/user.feishu 

[2025-10-15 20:14:04.403][000000010.959] {"content":{"text":"我的id是nil,Wed Oct 15 20:14:03 2025,Air8000,    10001发来短信，内容是:尊敬的用户：截至10月15日20时14分，您的账户使用情况如下：\n本月消费：17.61元\n可用余额：28.83元\n仅供参考，实际费用以出账账单为准。更多详情点击：http:\/\/a.189.cn\/IRAYnu 进入“中国电信”APP。也可关注“浙江电信”微信公众号进行快速查询：https:\/\/qy.k189.cn\/hfcx?
source=dt"},"sign":"4bHYm0YfpVjsdPIEugQBGfjuuyCYnI+Jjaf8K1zYqwo=","msg_type":"text","timestamp":"1760530443"}
[2025-10-15 20:14:04.430][000000010.964] dns_run 676:open.feishu.cn state 0 id 2 ipv6 0 use dns server2, try 0

[2025-10-15 20:14:04.447][000000010.995] dns_run 693:dns all done ,now stop

[2025-10-15 20:14:06.166][000000012.974] I/user.转发到钉钉

[2025-10-15 20:14:06.225][000000012.975] I/user.timestamp 1760530445000

[2025-10-15 20:14:06.265][000000012.975] I/user.sign N2JtlrhtDtRoAlfEJj2cBQPIXQGO8KMURW2UGday1lA%3D

[2025-10-15 20:14:06.294][000000012.976] I/user.url https://oapi.dingtalk.com/robot/send?access_token=bf9fe5c74194b9556cff401b87ac5de46a92bbf15cc226b73d14c28773b86f3b&timestamp=1760530445000&sign=N2JtlrhtDtRoAlfEJj2cBQPIXQGO8KMURW2UGday1lA%3D

[2025-10-15 20:14:06.357][000000012.977] I/user.dingding {"text":{"content":"我的id是nil,Wed Oct 15 20:14:05 2025,Air8000,    10001发来短信，内容是:尊敬的用户：截至10月15日20时14分，您的账户使用情况如下：\n本月消费：17.61元\n可用余额：28.83元\n仅供参考，实际费用以出账账单为准。更多详情点击：http:\/\/a.189.cn\/IRAYnu 进入“中国电信”APP。也可关注“浙江电信”微信公众号进行快速查询：https:\/\/qy.k189.cn\/hfcx?source=dt"},"msgtype":"text"}
[2025-10-15 20:14:06.401][000000012.979] dns_run 676:oapi.dingtalk.com state 0 id 3 ipv6 0 use dns server2, try 0

[2025-10-15 20:14:06.424][000000013.014] dns_run 693:dns all done ,now stop

[2025-10-15 20:14:08.906][000000015.708] I/user.转发到微信

[2025-10-15 20:14:08.935][000000015.708] I/user.timestamp 1760530448000

[2025-10-15 20:14:08.953][000000015.709] I/user.url https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=a9dec355-3e0f-45bf-a0b1-0f8813fe6b7d&timestamp=1760530448000

[2025-10-15 20:14:08.971][000000015.710] I/user.weixin {"text":{"content":"我的id是nil,Wed Oct 15 20:14:08 2025,Air8000,    10001发来短信，内容是:尊敬的用户：截至10月15日20时14分，您的账户使用情况如下：\n本月消费：17.61元\n可用余额：28.83元\n仅供参考，实际费用以出账账单为准。更多详情点击：http:\/\/a.189.cn\/IRAYnu 进入“中国电信”APP。也可关注“浙江电信”微信公众号进行快速查询：https:\/\/qy.k189.cn\/hfcx?source=dt"},"msgtype":"text"}


```
