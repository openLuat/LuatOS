## 功能模块介绍

1、main.lua：主程序入口；

2、sip_app_main.lua：sip主入口;

3、sip_app_key.lua：按键相关处理;

4、audio_drv.lua：音频驱动模块；

5、netdrv_4g.lua：4g网络模块

6、netdrv_wifi.lua：wifi网络模块

7、netdrv_eth_spi.lua：“通过SPI外挂CH390H芯片的以太网卡”驱动模块

8、netdrv_multiple.lua：多网卡（4G网卡、WIFI STA网卡、通过SPI外挂CH390H芯片的以太网卡）驱动模块


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
[2026-05-08 11:04:41.975][000000129.901] I/user.sip req INVITE from 180.152.6.34 8910
[2026-05-08 11:04:41.978][000000129.902] I/user.sip parsing remote SDP v=0
o=FreeSWITCH 1778192669 1778192670 IN IP4 180.152.6.34
s=FreeSWITCH
c=IN IP4 180.152.6.34
t=0 0
m=audio 16812 RTP/AVP 8 0 101
a=rtpmap:8 PCMA/8000
a=rtpmap:0 PCMU/8000
a=rtpmap:101 telephone-event/8000
a=fmtp:101 0-15
a=ptime:20

[2026-05-08 11:04:41.989][000000129.909] I/user.JQsip emit_event call incoming function
[2026-05-08 11:04:41.990][000000129.910] I/user.exsip event: call action: incoming
[2026-05-08 11:04:41.991][000000129.910] I/user.sip_callback STATE_READY call incoming table: 0C7A8A50 nil
[2026-05-08 11:04:41.993][000000129.911] I/user.sip_callback call event sub_event= incoming
[2026-05-08 11:04:41.994][000000129.911] I/user.sip_callback 来电: "Extension 100000" <sip:100000@180.152.6.34>;tag=6S188emrg3Fge 7fab6c02-c52d-123f-2697-441a4c127a21 nil nil nil
[2026-05-08 11:04:41.996][000000129.911] I/user.JQsip emit_event call ringing function
[2026-05-08 11:04:41.997][000000129.912] I/user.exsip event: call action: ringing
[2026-05-08 11:04:41.997][000000129.912] I/user.sip_callback STATE_READY call ringing table: 0C7A8780 nil
[2026-05-08 11:04:41.998][000000129.913] I/user.sip_callback call event sub_event= ringing
[2026-05-08 11:04:42.000][000000129.913] I/user.sip_callback 对方响铃中
[2026-05-08 11:04:42.001][000000129.913] I/user.JQsip emit_event media offer function
[2026-05-08 11:04:42.001][000000129.914] I/user.exsip event: media action: offer
[2026-05-08 11:04:42.002][000000129.914] I/user.sip_app_main_task_func waitMsg STATE_READY sip_callback MSG_INCOMING "Extension 100000" <sip:100000@180.152.6.34>;tag=6S188emrg3Fge
[2026-05-08 11:04:42.003][000000129.915] I/user.sip_app_main_task_func after process STATE_INCOMING
[2026-05-08 11:04:42.004][000000129.916] I/user.sip_app_key 呼入中
[2026-05-08 11:04:45.137][000000133.053] I/user.sip_app_key 按下BOOT键
[2026-05-08 11:04:45.138][000000133.054] I/user.sip_app_key 呼入中，接听
[2026-05-08 11:04:45.139][000000133.055] I/user.sip_app_main_task_func waitMsg STATE_INCOMING sip_app_key MSG_ACCEPT nil
[2026-05-08 11:04:45.139][000000133.055] I/user.exsip answering call
[2026-05-08 11:04:45.140][000000133.056] I/user.sip_app_main_task_func after process STATE_INCOMING
[2026-05-08 11:04:45.140][000000133.056] I/user.sip cmd answer 
[2026-05-08 11:04:45.144][000000133.057] W/user.sip no incoming
[2026-05-08 11:04:45.146][000000133.057] I/user.sip cmd answer 
[2026-05-08 11:04:45.151][000000133.058] I/user.test ip 192.168.1.101
[2026-05-08 11:04:45.153][000000133.061] I/user.sip answer 200 OK
[2026-05-08 11:04:45.160][000000133.076] I/user.sip req ACK from 180.152.6.34 8910
[2026-05-08 11:04:45.162][000000133.078] I/user.JQsip media session ready table: 0C7A61D0
[2026-05-08 11:04:45.163][000000133.078] I/user.JQsip emit_event media ready function
[2026-05-08 11:04:45.164][000000133.078] I/user.exsip event: media action: ready
[2026-05-08 11:04:45.165][000000133.079] I/user.exsip media ready 180.152.6.34 16812 PCMU
[2026-05-08 11:04:45.166][000000133.080] I/user.exsip voip engine started 180.152.6.34:16812 codec=PCMU adapter nil
[2026-05-08 11:04:45.167][000000133.080] I/user.sip_callback STATE_INCOMING media ready table: 0C7A61D0 nil
[2026-05-08 11:04:45.169][000000133.080] I/user.sip_callback 媒体通道就绪 180.152.6.34:16812
[2026-05-08 11:04:45.172][000000133.081] I/user.sip call established (incoming)
[2026-05-08 11:04:45.173][000000133.081] I/user.JQsip emit_event call established function
[2026-05-08 11:04:45.174][000000133.081] I/user.exsip event: call action: established
[2026-05-08 11:04:45.175][000000133.082] I/user.sip_callback STATE_INCOMING call connected table: 0C7A60A8 nil
[2026-05-08 11:04:45.179][000000133.082] I/user.sip_callback call event sub_event= connected
[2026-05-08 11:04:45.182][000000133.082] I/user.sip_callback 通话已建立
[2026-05-08 11:04:45.185][000000133.083] I/user.sip_app_main_task_func waitMsg STATE_INCOMING sip_callback MSG_CONNECTED nil
[2026-05-08 11:04:45.188][000000133.084] I/user.sip_app_main_task_func after process STATE_CONNECTED
[2026-05-08 11:04:45.189][000000133.084] I/user.sip_app_key 通话建立成功
[2026-05-08 11:04:45.190][000000133.085] D/voip voip start event
[2026-05-08 11:04:45.191][000000133.085] E/voip voip config: remote=180.152.6.34:16812 codec=0 ptime=20
[2026-05-08 11:04:45.192][000000133.086] E/voip voio origin: samples=8000
[2026-05-08 11:04:45.193][000000133.086] E/voip voio frame: samples=160 bytes=320
[2026-05-08 11:04:45.196][000000133.092] I/voip aec ready frame=160 tail_ms=120 denoise=1
[2026-05-08 11:04:45.197][000000133.101] D/net adapter 4 connect 180.152.6.34:16812 UDP
[2026-05-08 11:04:45.198][000000133.101] E/voip udp socket created and connected to 180.152.6.34:16812
[2026-05-08 11:04:45.199][000000133.102] luat_i2s_save_old_config 279:i2s1 save old param
[2026-05-08 11:04:45.200][000000133.103] E/voip audio started: multimedia_id=0 sample_rate=8000 backend=1
[2026-05-08 11:04:45.201][000000133.103] I/user.exsip voip state: started
[2026-05-08 11:04:45.202][000000133.104] I/user.sip_callback STATE_CONNECTED voip state started nil
[2026-05-08 11:04:45.205][000000133.104] I/user.sip_callback VoIP状态: started
[2026-05-08 11:04:45.208][000000133.105] I/voip voip running: 180.152.6.34:16812 codec=0 ptime=20
[2026-05-08 11:04:50.188][000000138.103] I/user.sip_callback STATE_CONNECTED voip stats table: 0C7A5950 nil
[2026-05-08 11:04:50.199][000000138.103] I/user.sip_callback VoIP统计 - 发送: 249 接收: 237 丢失: 0
[2026-05-08 11:04:51.711][000000139.637] I/user.sip req BYE from 180.152.6.34 8910
[2026-05-08 11:04:51.727][000000139.639] I/user.JQsip emit_event media stop function
[2026-05-08 11:04:51.728][000000139.640] I/user.exsip event: media action: stop
[2026-05-08 11:04:51.730][000000139.640] I/user.exsip voip engine stopping
[2026-05-08 11:04:51.731][000000139.641] I/user.sip_callback STATE_CONNECTED media stop table: 0C7A3F58 nil
[2026-05-08 11:04:51.735][000000139.641] I/user.sip_callback 媒体通道已关闭，关闭原因： peer_hangup
[2026-05-08 11:04:51.739][000000139.641] I/user.sip peer hung up
[2026-05-08 11:04:51.741][000000139.642] I/user.JQsip emit_event call ended function
[2026-05-08 11:04:51.742][000000139.642] I/user.exsip event: call action: ended
[2026-05-08 11:04:51.743][000000139.643] I/user.exsip voip engine stopping
[2026-05-08 11:04:51.744][000000139.643] I/user.sip_callback STATE_CONNECTED call ended table: 0C7A3EB0 nil
[2026-05-08 11:04:51.749][000000139.643] I/user.sip_callback call event sub_event= ended
[2026-05-08 11:04:51.753][000000139.644] I/user.sip_callback 通话已结束，结束原因为： peer_hangup 通话对象： table: 0C7A8198
[2026-05-08 11:04:51.757][000000139.645] I/user.sip_app_main_task_func waitMsg STATE_CONNECTED sip_callback MSG_DISCONNECTED nil
[2026-05-08 11:04:51.762][000000139.645] I/user.sip_app_main_task_func after process STATE_READY
[2026-05-08 11:04:51.764][000000139.646] I/user.sip_app_key 通话已断开
[2026-05-08 11:04:51.765][000000139.647] D/voip voip stop event
[2026-05-08 11:04:51.765][000000139.647] luat_i2s_load_old_config 297:i2s0 load old param
[2026-05-08 11:04:51.766][000000139.650] I/user.exsip voip state: stopped
[2026-05-08 11:04:51.767][000000139.651] I/user.sip_callback STATE_READY voip state stopped nil
[2026-05-08 11:04:51.771][000000139.651] I/user.sip_callback VoIP状态: stopped

```

接听通话结束，在本例中，还可以单击Air8000开发板的boot按键，进行拨号测试，日志如下：

```
[2026-05-08 11:02:51.252][000000019.059] I/user.sip_callback STATE_INITING register ok table: 0C7C5238 nil
[2026-05-08 11:02:51.260][000000019.060] I/user.sip_callback 注册成功，有效期: 600 SIP响应头: table: 0C7C6948
[2026-05-08 11:02:51.268][000000019.060] I/user.sip_callback STATE_INITING ready nil nil nil
[2026-05-08 11:02:51.276][000000019.061] I/user.sip_callback SIP 服务已就绪 当前SIP状态: STATE_INITING
[2026-05-08 11:02:51.287][000000019.061] I/user.sip_app_main_task_func waitMsg STATE_INITING sip_callback MSG_READY nil
[2026-05-08 11:02:51.295][000000019.062] I/user.sip_app_main_task_func after process STATE_READY
[2026-05-08 11:02:51.300][000000019.062] I/user.sip_app_key SIP应用已初始化
[2026-05-08 11:02:51.303][000000019.117] I/user.sip req NOTIFY from 180.152.6.34 8910
[2026-05-08 11:03:00.119][000000028.040] I/user.sip_app_key 按下BOOT键
[2026-05-08 11:03:00.123][000000028.041] I/user.sip_app_main_task_func waitMsg STATE_READY sip_app_key MSG_DIAL 100000
[2026-05-08 11:03:00.135][000000028.042] I/user.exsip calling: 100000
[2026-05-08 11:03:00.138][000000028.042] I/user.sip_app_main_task_func after process STATE_DIALING
[2026-05-08 11:03:00.142][000000028.043] I/user.sip cmd call 100000
[2026-05-08 11:03:00.147][000000028.043] W/user.sip not online
[2026-05-08 11:03:00.150][000000028.043] I/user.sip cmd call 100000
[2026-05-08 11:03:00.155][000000028.046] I/user.test ip 192.168.1.101
[2026-05-08 11:03:00.159][000000028.047] I/user.sip setting call timeout 30 seconds
[2026-05-08 11:03:00.163][000000028.050] I/user.sip send INVITE sip:100000@180.152.6.34
[2026-05-08 11:03:00.166][000000028.065] I/user.sip resp 407 Proxy Authentication Required from 180.152.6.34 8910
[2026-05-08 11:03:00.170][000000028.075] I/user.JQsip emit_event call auth_retry function
[2026-05-08 11:03:00.173][000000028.076] I/user.exsip event: call action: auth_retry
[2026-05-08 11:03:00.191][000000028.105] I/user.sip resp 100 Trying from 180.152.6.34 8910
[2026-05-08 11:03:00.283][000000028.209] I/user.sip resp 180 Ringing from 180.152.6.34 8910
[2026-05-08 11:03:00.287][000000028.211] I/user.sip invite provisional response 180 Ringing
[2026-05-08 11:03:00.292][000000028.212] I/user.JQsip emit_event call ringing function
[2026-05-08 11:03:00.296][000000028.212] I/user.exsip event: call action: ringing
[2026-05-08 11:03:00.305][000000028.213] I/user.sip_callback STATE_DIALING call ringing table: 0C7BB4D8 nil
[2026-05-08 11:03:00.317][000000028.213] I/user.sip_callback call event sub_event= ringing
[2026-05-08 11:03:00.325][000000028.213] I/user.sip_callback 对方响铃中
[2026-05-08 11:03:03.537][000000031.452] I/user.sip resp 200 OK from 180.152.6.34 8910
[2026-05-08 11:03:03.541][000000031.455] I/user.sip parsing remote SDP v=0
o=FreeSWITCH 1778193583 1778193584 IN IP4 180.152.6.34
s=FreeSWITCH
c=IN IP4 180.152.6.34
t=0 0
m=audio 15800 RTP/AVP 0 101
a=rtpmap:0 PCMU/8000
a=rtpmap:101 telephone-event/8000
a=fmtp:101 0-15
a=ptime:20

[2026-05-08 11:03:03.549][000000031.457] I/user.sip stopping call timeout timer
[2026-05-08 11:03:03.555][000000031.461] I/user.JQsip media session ready table: 0C7B8940
[2026-05-08 11:03:03.561][000000031.462] I/user.JQsip emit_event media ready function
[2026-05-08 11:03:03.565][000000031.462] I/user.exsip event: media action: ready
[2026-05-08 11:03:03.568][000000031.462] I/user.exsip media ready 180.152.6.34 15800 PCMU
[2026-05-08 11:03:03.572][000000031.463] I/user.exsip voip engine started 180.152.6.34:15800 codec=PCMU adapter nil
[2026-05-08 11:03:03.576][000000031.464] I/user.sip_callback STATE_DIALING media ready table: 0C7B8940 nil
[2026-05-08 11:03:03.586][000000031.464] I/user.sip_callback 媒体通道就绪 180.152.6.34:15800
[2026-05-08 11:03:03.597][000000031.464] I/user.sip call established (outgoing)
[2026-05-08 11:03:03.602][000000031.465] I/user.JQsip emit_event call established function
[2026-05-08 11:03:03.605][000000031.465] I/user.exsip event: call action: established
[2026-05-08 11:03:03.609][000000031.466] I/user.sip_callback STATE_DIALING call connected table: 0C7B8200 nil
[2026-05-08 11:03:03.618][000000031.466] I/user.sip_callback call event sub_event= connected
[2026-05-08 11:03:03.628][000000031.466] I/user.sip_callback 通话已建立
[2026-05-08 11:03:03.636][000000031.467] I/user.sip_app_main_task_func waitMsg STATE_DIALING sip_callback MSG_CONNECTED nil
[2026-05-08 11:03:03.647][000000031.468] I/user.sip_app_main_task_func after process STATE_CONNECTED
[2026-05-08 11:03:03.650][000000031.468] I/user.sip_app_key 通话建立成功
[2026-05-08 11:03:03.654][000000031.469] D/voip voip task started
[2026-05-08 11:03:03.657][000000031.470] D/voip voip start event
[2026-05-08 11:03:03.662][000000031.470] E/voip voip config: remote=180.152.6.34:15800 codec=0 ptime=20
[2026-05-08 11:03:03.665][000000031.470] E/voip voio origin: samples=8000
[2026-05-08 11:03:03.668][000000031.470] E/voip voio frame: samples=160 bytes=320
[2026-05-08 11:03:03.672][000000031.476] I/voip aec ready frame=160 tail_ms=120 denoise=1
[2026-05-08 11:03:03.676][000000031.477] D/net adapter 4 connect 180.152.6.34:15800 UDP
[2026-05-08 11:03:03.680][000000031.478] E/voip udp socket created and connected to 180.152.6.34:15800
[2026-05-08 11:03:03.683][000000031.478] luat_i2s_save_old_config 279:i2s1 save old param
[2026-05-08 11:03:03.686][000000031.479] E/voip audio started: multimedia_id=0 sample_rate=8000 backend=1
[2026-05-08 11:03:03.690][000000031.480] I/user.exsip voip state: started
[2026-05-08 11:03:03.695][000000031.480] I/user.sip_callback STATE_CONNECTED voip state started nil
[2026-05-08 11:03:03.703][000000031.481] I/user.sip_callback VoIP状态: started
[2026-05-08 11:03:03.713][000000031.481] I/voip voip running: 180.152.6.34:15800 codec=0 ptime=20
[2026-05-08 11:03:04.919][000000032.846] W/voip_jb jb resync: expected_seq 45125 -> 45123 (pending 1)
[2026-05-08 11:03:08.562][000000036.480] I/user.sip_callback STATE_CONNECTED voip stats table: 0C7B7E58 nil
[2026-05-08 11:03:08.577][000000036.480] I/user.sip_callback VoIP统计 - 发送: 249 接收: 236 丢失: 0
[2026-05-08 11:03:10.942][000000038.866] W/voip_jb jb resync: expected_seq 45424 -> 45422 (pending 1)
[2026-05-08 11:03:12.976][000000040.906] W/voip_jb jb resync: expected_seq 45524 -> 45520 (pending 1)
[2026-05-08 11:03:13.088][000000041.009] I/user.sip req BYE from 180.152.6.34 8910
[2026-05-08 11:03:13.095][000000041.012] I/user.JQsip emit_event media stop function
[2026-05-08 11:03:13.098][000000041.012] I/user.exsip event: media action: stop
[2026-05-08 11:03:13.101][000000041.013] I/user.exsip voip engine stopping
[2026-05-08 11:03:13.104][000000041.013] I/user.sip_callback STATE_CONNECTED media stop table: 0C7B6420 nil
[2026-05-08 11:03:13.113][000000041.014] I/user.sip_callback 媒体通道已关闭，关闭原因： peer_hangup
[2026-05-08 11:03:13.122][000000041.014] I/user.sip peer hung up
[2026-05-08 11:03:13.126][000000041.014] I/user.JQsip emit_event call ended function
[2026-05-08 11:03:13.130][000000041.015] I/user.exsip event: call action: ended
[2026-05-08 11:03:13.133][000000041.015] I/user.exsip voip engine stopping
[2026-05-08 11:03:13.136][000000041.016] I/user.sip_callback STATE_CONNECTED call ended table: 0C7B6378 nil
[2026-05-08 11:03:13.151][000000041.016] I/user.sip_callback call event sub_event= ended
[2026-05-08 11:03:13.160][000000041.016] I/user.sip_callback 通话已结束，结束原因为： peer_hangup 通话对象： table: 0C7C25B8
[2026-05-08 11:03:13.170][000000041.017] I/user.sip_app_main_task_func waitMsg STATE_CONNECTED sip_callback MSG_DISCONNECTED nil
[2026-05-08 11:03:13.180][000000041.018] I/user.sip_app_main_task_func after process STATE_READY
[2026-05-08 11:03:13.184][000000041.018] I/user.sip_app_key 通话已断开


```