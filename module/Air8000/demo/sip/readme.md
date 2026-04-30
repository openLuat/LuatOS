## 功能模块介绍

1、main.lua：主程序入口；

2、sip_app.lua：短信发送+短信接收+短信转发到企业微信/钉钉/飞书平台功能模块； 

3、audio_drv.lua：音频驱动模块；

4、netdrv_4g.lua：4g网络模块

5、netdrv_wifi.lua：wifi网络模块

6、netdrv_eth_spi.lua：“通过SPI外挂CH390H芯片的以太网卡”驱动模块

7、netdrv_multiple.lua：多网卡（4G网卡、WIFI STA网卡、通过SPI外挂CH390H芯片的以太网卡）驱动模块


## 演示功能概述

使用Air8000开发板测试sip功能

1、4g联网测试sip功能；

2、wifi联网测试sip功能；

3、以太网联网测试sip功能；

## 演示硬件环境

[](https://docs.openluat.com/air8000/luatos/app/image/eth_sip.jpg)

1、Air8000开发板一块+物联网一张+4g天线一根+WIFI天线一根+网线一根：

* 天线装到开发板上对应位置

* 测试4g联网时sip功能：将物联网卡插入开发板的sim卡槽

* 测试wifi联网时sip功能：拔出物联网卡

* 测试以太网联网时sip功能：拔出物联网卡，网线一端连到开发板网口，网线另一端连到路由器网口

2、TYPE-C USB数据线一根，Air8000开发板和数据线的硬件接线方式为：

* Air8000开发板通过TYPE-C USB口供电；

* TYPE-C USB数据线直接插到核心板的TYPE-C USB座子，另外一端连接电脑USB口；

## 演示软件环境

1、Luatools下载调试工具

2、[必须使用Air8000 V2033或者更高版本带audio的固件](https://gitee.com/openLuat/LuatOS/tree/master/module/Air8000/core)（理论上最新版本固件也可以，如果使用最新版本的固件不可以，可以烧录V2033-9固件对比验证）

3、PC端下载MicroSIP软件，用于测试sip通话功能

## 演示核心步骤

1、搭建好硬件环境

2、在main.lua中选择要测试的网卡场景，如：选择测试以太网联网测试sip通话的场景，则注释掉4g和wifi网卡相关代码，打开以太网网卡相关代码，即在netdrv_device.lua脚本中require "netdrv_eth_spi"；

3、烧录内核固件和sip相关demo成功后，自动开机运行；

4、打开MicroSIP，输入sip_app.lua中SIP_CONFIG配置的sip服务器地址，端口，域名，注意：用户名和密码按实际填，尤其是用户名不能与脚本中一样，例如脚本中用户名为1000001，MicroSIP软件用户名不可再填100001；

5、可以看到代码运行结果如下：

以下是使用sip demo演示的日志

日志中如果出现"SIP 服务已就绪"，就可以开始测试通话，本例设置了自动接听，收到来电，通话自动建立，日志如下：

```
[2026-04-21 11:21:41.015][000000004.315] I/user.sip 注册成功，有效期: 600
[2026-04-21 11:21:41.020][000000004.316] I/user.sip SIP 服务已就绪
[2026-04-21 11:21:41.048][000000004.396] I/user.sip req NOTIFY from 180.152.6.34 8910
[2026-04-21 11:22:04.510][000000027.863] I/user.sip req INVITE from 180.152.6.34 8910
[2026-04-21 11:22:04.513][000000027.864] I/user.sip parsing remote SDP v=0
o=FreeSWITCH 1776725529 1776725530 IN IP4 180.152.6.34
s=FreeSWITCH
c=IN IP4 180.152.6.34
t=0 0
m=audio 16196 RTP/AVP 8 0 101
a=rtpmap:8 PCMA/8000
a=rtpmap:0 PCMU/8000
a=rtpmap:101 telephone-event/8000
a=fmtp:101 0-15
a=ptime:20

[2026-04-21 11:22:04.527][000000027.872] I/user.exsip event: call action: incoming
[2026-04-21 11:22:04.535][000000027.872] I/user.sip 来电: "Extension 100000" <sip:100000@180.152.6.34>;tag=mrvaS8r94rX3p
[2026-04-21 11:22:04.538][000000027.873] I/user.来电号码: "Extension 100000" <sip:100000@180.152.6.34>;tag=mrvaS8r94rX3p
[2026-04-21 11:22:04.543][000000027.873] I/user.exsip answering call
[2026-04-21 11:22:04.548][000000027.874] I/user.exsip event: media action: offer
[2026-04-21 11:22:04.554][000000027.874] I/user.sip cmd answer 
[2026-04-21 11:22:04.558][000000027.875] I/user.test ip 0.0.0.0
[2026-04-21 11:22:04.563][000000027.878] I/user.sip answer 200 OK
[2026-04-21 11:22:04.568][000000027.894] I/user.sip req ACK from 180.152.6.34 8910
[2026-04-21 11:22:04.574][000000027.896] I/user.JQsip media session ready table: 0C7CA460
[2026-04-21 11:22:04.578][000000027.896] I/user.exsip event: media action: ready
[2026-04-21 11:22:04.583][000000027.896] I/user.exsip media ready 180.152.6.34 16196 PCMU
[2026-04-21 11:22:04.589][000000027.898] I/user.exsip voip engine started 180.152.6.34:16196 codec=PCMU
[2026-04-21 11:22:04.593][000000027.898] I/user.sip 媒体通道就绪 180.152.6.34:16196
[2026-04-21 11:22:04.598][000000027.898] I/user.sip call established (incoming)
[2026-04-21 11:22:04.603][000000027.899] I/user.exsip event: call action: established
[2026-04-21 11:22:04.608][000000027.900] D/voip voip task started
[2026-04-21 11:22:04.613][000000027.900] D/voip voip start event
[2026-04-21 11:22:04.619][000000027.900] E/voip voip config: remote=180.152.6.34:16196 codec=0 ptime=20
[2026-04-21 11:22:04.624][000000027.901] E/voip voio origin: samples=8000
[2026-04-21 11:22:04.628][000000027.901] E/voip voio frame: samples=160 bytes=320
[2026-04-21 11:22:04.637][000000027.904] D/net adapter 4 connect 180.152.6.34:16196 UDP
[2026-04-21 11:22:04.639][000000027.904] E/voip udp socket created and connected to 180.152.6.34:16196
[2026-04-21 11:22:04.643][000000027.904] luat_i2s_save_old_config 279:i2s1 save old param
[2026-04-21 11:22:04.649][000000027.921] E/voip audio started: multimedia_id=0 sample_rate=8000 backend=1
[2026-04-21 11:22:04.655][000000027.922] I/user.exsip voip state: started
[2026-04-21 11:22:04.660][000000027.923] I/user.voip 状态: started
[2026-04-21 11:22:04.664][000000027.923] I/voip voip running: 180.152.6.34:16196 codec=0 ptime=20
[2026-04-21 11:22:05.961][000000029.319] I/user.sip send OPTIONS ping
[2026-04-21 11:22:05.976][000000029.333] I/user.sip resp 200 OK from 180.152.6.34 8910
[2026-04-21 11:22:08.402][000000031.746] W/voip_jb jb resync: expected_seq 16587 -> 16585 (pending 1)
[2026-04-21 11:22:08.911][000000032.266] W/voip_jb jb resync: expected_seq 16611 -> 16609 (pending 1)
[2026-04-21 11:22:09.566][000000032.922] I/user.voip 统计 - 发送: 250 接收: 215 丢失: 0
[2026-04-21 11:22:10.240][000000033.586] W/voip_jb jb resync: expected_seq 16675 -> 16673 (pending 1)
[2026-04-21 11:22:11.328][000000034.679] I/user.sip req BYE from 180.152.6.34 8910
[2026-04-21 11:22:11.337][000000034.682] I/user.exsip event: media action: stop
[2026-04-21 11:22:11.344][000000034.682] I/user.exsip voip engine stopping
[2026-04-21 11:22:11.351][000000034.683] I/user.sip 媒体通道已关闭
[2026-04-21 11:22:11.356][000000034.683] I/user.sip peer hung up
[2026-04-21 11:22:11.362][000000034.684] I/user.exsip event: call action: ended
[2026-04-21 11:22:11.366][000000034.684] I/user.exsip voip engine stopping
[2026-04-21 11:22:11.371][000000034.684] I/user.sip 通话已结束

```

接听通话结束，在本例中，还可以单击Air8000开发板的boot按键，进行拨号测试，日志如下：

```
[2026-04-21 11:26:09.949][000000273.301] I/user.exsip calling: 100000
[2026-04-21 11:26:09.952][000000273.302] I/user.exsip 拨号成功!!!!!!!
[2026-04-21 11:26:09.957][000000273.302] I/user.sip cmd call 100000
[2026-04-21 11:26:09.962][000000273.304] I/user.test ip 0.0.0.0
[2026-04-21 11:26:09.967][000000273.308] I/user.sip send INVITE sip:100000@180.152.6.34
[2026-04-21 11:26:09.980][000000273.322] I/user.sip resp 407 Proxy Authentication Required from 180.152.6.34 8910
[2026-04-21 11:26:09.983][000000273.333] I/user.exsip event: call action: auth_retry
[2026-04-21 11:26:10.011][000000273.362] I/user.sip resp 100 Trying from 180.152.6.34 8910
[2026-04-21 11:26:10.104][000000273.452] I/user.sip resp 180 Ringing from 180.152.6.34 8910
[2026-04-21 11:26:10.107][000000273.457] I/user.exsip calling: 100000
[2026-04-21 11:26:10.112][000000273.458] I/user.exsip 拨号成功!!!!!!!
[2026-04-21 11:26:10.117][000000273.458] I/user.sip cmd call 100000
[2026-04-21 11:26:10.123][000000273.458] W/user.sip busy
[2026-04-21 11:26:16.016][000000279.370] I/user.sip send OPTIONS ping
[2026-04-21 11:26:16.032][000000279.379] I/user.sip resp 200 OK from 180.152.6.34 8910
[2026-04-21 11:26:19.298][000000282.643] I/user.sip resp 200 OK from 180.152.6.34 8910
[2026-04-21 11:26:19.303][000000282.645] I/user.sip parsing remote SDP v=0
o=FreeSWITCH 1776725794 1776725795 IN IP4 180.152.6.34
s=FreeSWITCH
c=IN IP4 180.152.6.34
t=0 0
m=audio 16186 RTP/AVP 0 101
a=rtpmap:0 PCMU/8000
a=rtpmap:101 telephone-event/8000
a=fmtp:101 0-15
a=ptime:20

[2026-04-21 11:26:19.310][000000282.651] I/user.JQsip media session ready table: 0C7D55D8
[2026-04-21 11:26:19.327][000000282.652] I/user.exsip event: media action: ready
[2026-04-21 11:26:19.335][000000282.652] I/user.exsip media ready 180.152.6.34 16186 PCMU
[2026-04-21 11:26:19.340][000000282.653] I/user.exsip voip engine started 180.152.6.34:16186 codec=PCMU
[2026-04-21 11:26:19.348][000000282.653] I/user.sip 媒体通道就绪 180.152.6.34:16186
[2026-04-21 11:26:19.352][000000282.654] I/user.sip call established (outgoing)
[2026-04-21 11:26:19.361][000000282.654] I/user.exsip event: call action: established
[2026-04-21 11:26:19.365][000000282.655] D/voip voip start event
[2026-04-21 11:26:19.370][000000282.655] E/voip voip config: remote=180.152.6.34:16186 codec=0 ptime=20
[2026-04-21 11:26:19.379][000000282.656] E/voip voio origin: samples=8000
[2026-04-21 11:26:19.383][000000282.656] E/voip voio frame: samples=160 bytes=320
[2026-04-21 11:26:19.388][000000282.667] D/net adapter 4 connect 180.152.6.34:16186 UDP
[2026-04-21 11:26:19.395][000000282.668] E/voip udp socket created and connected to 180.152.6.34:16186
[2026-04-21 11:26:19.400][000000282.668] luat_i2s_save_old_config 279:i2s1 save old param
[2026-04-21 11:26:19.405][000000282.669] E/voip audio started: multimedia_id=0 sample_rate=8000 backend=1
[2026-04-21 11:26:19.413][000000282.670] I/user.exsip voip state: started
[2026-04-21 11:26:19.418][000000282.670] I/user.voip 状态: started
[2026-04-21 11:26:19.422][000000282.671] I/voip voip running: 180.152.6.34:16186 codec=0 ptime=20
[2026-04-21 11:26:24.325][000000287.670] I/user.voip 统计 - 发送: 250 接收: 238 丢失: 0
[2026-04-21 11:26:29.323][000000292.670] I/user.voip 统计 - 发送: 500 接收: 488 丢失: 0
[2026-04-21 11:26:29.665][000000293.009] W/voip_jb jb resync: expected_seq 40902 -> 40860 (pending 2)
[2026-04-21 11:26:29.727][000000293.069] W/voip_jb jb resync: expected_seq 40863 -> 40900 (pending 4)
[2026-04-21 11:26:30.005][000000293.347] I/user.sip req BYE from 180.152.6.34 8910
[2026-04-21 11:26:30.009][000000293.350] I/user.exsip event: media action: stop
[2026-04-21 11:26:30.014][000000293.350] I/user.exsip voip engine stopping
[2026-04-21 11:26:30.022][000000293.351] I/user.sip 媒体通道已关闭
[2026-04-21 11:26:30.026][000000293.351] I/user.sip peer hung up
[2026-04-21 11:26:30.031][000000293.352] I/user.exsip event: call action: ended
[2026-04-21 11:26:30.040][000000293.352] I/user.exsip voip engine stopping
[2026-04-21 11:26:30.045][000000293.352] I/user.sip 通话已结束
[2026-04-21 11:26:30.053][000000293.354] D/voip voip stop event
[2026-04-21 11:26:30.058][000000293.355] luat_i2s_load_old_config 297:i2s0 load old param
[2026-04-21 11:26:30.062][000000293.356] I/user.exsip voip state: stopped
[2026-04-21 11:26:30.070][000000293.357] I/user.voip 状态: stopped
[2026-04-21 11:26:31.000][000000294.344] I/user.sip req BYE from 180.152.6.34 8910
[2026-04-21 11:26:31.002][000000294.347] I/user.sip peer hung up
[2026-04-21 11:26:31.006][000000294.347] I/user.exsip event: call action: ended
[2026-04-21 11:26:31.012][000000294.348] I/user.sip 通话已结束

```