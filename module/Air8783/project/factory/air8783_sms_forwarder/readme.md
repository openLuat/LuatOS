## 功能模块介绍

1、main.lua：主程序入口，加载并调度各功能模块；

2、excloud_app.lua：AirCloud（云平台）连接管理功能模块，负责应用层鉴权、心跳保活、运维日志上传以及平台消息分发；

3、sms_bridge.lua：短信与AirCloud协议桥接功能模块，负责短信收发事件与TLV应用报文之间的双向转换和上传；

4、sms_callback.lua：短信事件本地调试日志功能模块，打印短信发送结果与投递状态报告；

5、sms_app.lua：短信测试应用功能模块，开机自动执行上行短信测试用例；



## 系统消息介绍

1、"SMS_READY"：模组短信服务已经就绪；

2、"IP_READY"：网络已经获取到ip信息，仅仅获取到了ip信息，能否和外网连通还不确认；



## 短信事件消息介绍

1、"SMS_SENT"：短信发送结果事件，模组调用短信能力发送短信后由系统发布，msg_ref用于和SMS_REPORT关联;

2、"SMS_REPORT"：短信投递状态报告事件，基站回传短信送达的最终结果；

3、"SMS_INC"：设备收到新短信事件，包含号码、短信内容和元数据；



## 演示功能概述

1、连接云平台：设备上电后，短信服务就绪并且网络就绪后，通过MQTT与AirCloud平台建立连接，并通过TLV报文完成应用层鉴权（用户key+IMEI+MUID）；

2、建立连接后，启动心跳定时上报（默认300秒一次），维持与服务器的连接活性，防止服务器断链；

3、短信上行：设备通过sms_bridge.send_sms发送短信，SMSC接受后触发SMS_SENT事件，桥接功能模块将该发送结果转换为TLV报文上传云平台，例如：

``` lua
field=29 SMS_SEND_RSP
field=1039 SMS_SEQ
field=1040 SMS_CALLEE
field=1041 SMS_CONTENT
field=1042 SMS_STATUS
field=1047 SMS_MSG_REF
```

4、短信投递状态报告：短信送达或失败后，基站回传SMS_REPORT（携带status原因码），桥接功能模块根据状态码映射（0-成功，0x41-空号，0x22-不在线/关机等）转换为TLV报文上传云平台；

5、短信下发：由模组内部代码触发，sms_app.lua直接向目标号码发送短信；

6、运维日志：excloud库将运行日志写进本地缓冲，首次上传（默认60秒）后每30分钟上传一次云平台；


## 演示硬件环境

1、Air8783开发板一块 + 可上网的sim卡一张 ：

- sim卡插入开发板的sim卡卡槽；

2、TYPE-C USB数据线一根，Air8783开发板和数据线的硬件接线方式为：

- Air8783开发板通过USB-A 口接到电脑USB口供电；

![](https://docs.openluat.com/air8000/luatos/app/image/8783短信.jpg)

## 演示软件环境

1、Luatools下载调试工具；

2、[Air8783固件]([Air780EPM固件版本 - luatos@air780epm - 合宙模组资料中心](https://docs.openluat.com/air780epm/luatos/firmware/780epm_version/))，必须使用支持短信SMS功能的固件版本，本demo使用的是2048-106号固件；

3、云平台测试环境：[AirCloud云平台](https://iot.luatos.com/)，需要在合宙iot平台创建项目并归属到对应项目下


## 演示核心步骤

1、搭建好硬件环境，插好sim卡后连接电脑；

2、Luatools烧录内核固件和修改后的demo脚本代码，在"sms_app"中sms_bridge.send_sms函数里面修改要发送的号码和短信内容；

3、烧录成功后，自动开机运行，连接云平台成功后，串口会出现类似日志：

``` lua
[2026-08-07 11:08:49.597][000000008.646] D/sms pdu len 19
[2026-08-07 11:08:49.952][000000009.005] I/user.httpplus 服务器已完成响应
[2026-08-07 11:08:49.956][000000009.008] I/user.[excloud]getip响应 HTTP: 200 Body: 
[2026-08-07 11:08:49.960][000000009.008] {"msg":"ok","conninfo":{"ipv4":"124.71.128.165","port":9108,"auth_key":"gwTdT1TpYK7Q2vKAmVZkmsG2VvjyMqWt"},"imginfo":{"url":"https://api.luatos.com/iot/air_up/image","data_key":"f","data_param":{"key":"2h3WBCJ4UUYfLApJwvwJ4U4cC2mxAQgrUd6Q","tip":""}},"audinfo":{"url":"https://api.luatos.com/iot/air_up/audio","data_key":"f","data_param":{"key":"2h3WBCJ4UUYfLApJwvwJ4U4cC2mxAQgrUd6Q","tip":""}},"mtninfo":{"url":"https://api.luatos.com/iot/air_up/file","data_key":"f","data_param":{"key":"2h3WBCJ4UUYfLApJwvwJ4U4cC2mxAQgrUd6Q","tip":""}}}
[2026-08-07 11:08:49.963][000000009.010] I/user.[excloud]TCP/UDP连接信息 host: 124.71.128.165 port: 9108 key: nil
[2026-08-07 11:08:49.966][000000009.010] I/user.[excloud]获取到图片上传信息
[2026-08-07 11:08:49.969][000000009.011] I/user.[excloud]获取到音频上传信息
[2026-08-07 11:08:49.972][000000009.011] I/user.[excloud]获取到运维日志上传信息
[2026-08-07 11:08:49.975][000000009.011] W/user.[excloud]未获取到二维码信息
[2026-08-07 11:08:49.977][000000009.012] I/user.[excloud]自动获取到auth_key
[2026-08-07 11:08:49.980][000000009.012] I/user.[excloud]getip 更新配置: 124.71.128.165 9108
[2026-08-07 11:08:49.983][000000009.013] I/user.[excloud]getip 成功: true
[2026-08-07 11:08:49.986][000000009.013] I/user.[excloud]服务器信息获取成功 host: 124.71.128.165 port: 9108 transport: tcp
[2026-08-07 11:08:49.989][000000009.014] I/user.[excloud]创建TCP连接
[2026-08-07 11:08:49.991][000000009.015] D/socket connect to 124.71.128.165,9108
[2026-08-07 11:08:49.993][000000009.017] I/user.[excloud]TCP连接结果 true false
[2026-08-07 11:08:49.996][000000009.017] I/user.aircloud system excloud服务启动 transport tcp host 124.71.128.165 port 9108
[2026-08-07 11:08:49.999][000000009.024] I/user.[excloud]excloud service started
[2026-08-07 11:08:50.002][000000009.025] I/user.excloud_app AirCloud连接已启动
[2026-08-07 11:08:50.005][000000009.025] I/user.main 启动完成 网络就绪 短信就绪 AirCloud已启动
[2026-08-07 11:08:50.013][000000009.072] I/user.[excloud]excloud 自动心跳已启动，间隔 300 秒
[2026-08-07 11:08:50.018][000000009.073] I/user.excloud_app 心跳已启动 300 s
[2026-08-07 11:08:50.020][000000009.073] I/user.main 心跳已启动 间隔 300
[2026-08-07 11:08:50.091][000000009.143] I/user.excloud_app 运维日志定时上传已启动 首次 60 s 间隔 1800 s
[2026-08-07 11:08:50.094][000000009.144] I/user.main 运维日志定时上传已启动 间隔 1800
[2026-08-07 11:08:50.154][000000009.215] I/user.[excloud]TCP socket cb userdata: 0C184050 33554449 0
[2026-08-07 11:08:50.157][000000009.216] I/user.aircloud net_conn TCP连接成功 host 124.71.128.165 port 9108
[2026-08-07 11:08:50.218][000000009.266] I/user.[excloud]TCP socket TCP连接成功
[2026-08-07 11:08:50.220][000000009.267] I/user.excloud_app 连接结果 成功
[2026-08-07 11:08:50.223][000000009.267] I/mobile l_mobile_muid called
[2026-08-07 11:08:50.226][000000009.269] I/mobile l_mobile_muid ret=32
[2026-08-07 11:08:50.229][000000009.269] I/user.[excloud] 发送鉴权请求
[2026-08-07 11:08:50.231][000000009.270] I/user.[excloud]构建发送数据 field: 16 type: 3 value: gwTdT1TpYK7Q2vKAmVZkmsG2VvjyMqWt-862323089995180-20260605140024A391855A8910558372
[2026-08-07 11:08:50.236][000000009.271] I/user.[excloud]tlv发送数据长度4 85
[2026-08-07 11:08:50.240][000000009.272] I/user.[excloud]构建消息头 seq: 2 len: 85 flags: 18 dev: 0186232308999518
[2026-08-07 11:08:50.243][000000009.275] I/user.[excloud]数据发送成功 101 字节
[2026-08-07 11:08:50.245][000000009.275] D/mobile ims reg state 0
[2026-08-07 11:08:50.248][000000009.276] I/user.SMS_SENT result= true rp_cause= 0 msg_ref= 10 error_code= 0
[2026-08-07 11:08:50.250][000000009.277] I/user.SMS_SENT SMSC已接受, msg_ref= 10 等待回执...
[2026-08-07 11:08:50.253][000000009.277] I/user.sms_bridge SMS_SENT上报 plat_seq 1786072129 msg_ref 10 status 发送成功 callee 17538215008
[2026-08-07 11:08:50.255][000000009.278] I/user.[excloud]构建发送数据 field: 29 type: 0 value: 0
[2026-08-07 11:08:50.258][000000009.280] I/user.[excloud]构建发送数据 field: 1039 type: 3 value: 1786072129
[2026-08-07 11:08:50.260][000000009.281] I/user.[excloud]构建发送数据 field: 1040 type: 3 value: 17538215008
[2026-08-07 11:08:50.263][000000009.282] I/user.[excloud]构建发送数据 field: 1041 type: 5 value: 301
[2026-08-07 11:08:50.266][000000009.284] I/user.[excloud]构建发送数据 field: 1042 type: 5 value: 发送成功
[2026-08-07 11:08:50.268][000000009.285] I/user.[excloud]构建发送数据 field: 1047 type: 0 value: 10
[2026-08-07 11:08:50.271][000000009.287] I/user.[excloud]tlv发送数据长度4 68
[2026-08-07 11:08:50.275][000000009.287] I/user.[excloud]构建消息头 seq: 3 len: 68 flags: 2 dev: 0186232308999518
[2026-08-07 11:08:50.277][000000009.289] I/user.[excloud]数据发送成功 84 字节
[2026-08-07 11:08:50.279][000000009.290] I/user.sms SMS_SENT上报 plat_seq 1786072129 msg_ref 10 status 发送成功 callee 17538215008
[2026-08-07 11:08:50.343][000000009.401] I/user.[excloud]TCP socket cb userdata: 0C184050 33554452 0
[2026-08-07 11:08:50.346][000000009.402] I/user.[excloud]TCP socket 收到数据 22 字节 01862323089995180001000600000000301100026F6B 44
[2026-08-07 11:08:50.349][000000009.403] I/user.[excloud]解析消息头 设备ID: 862323089995180 序列号: 1 消息长度: 6 协议版本: 0 需要回复: false UDP承载: false 包含auth_key: false
[2026-08-07 11:08:50.351][000000009.404] I/user.[excloud]鉴权成功 ok
[2026-08-07 11:08:50.354][000000009.405] I/user.excloud_app 鉴权成功
[2026-08-07 11:08:50.356][000000009.406] I/user.main AirCloud鉴权成功
[2026-08-07 11:08:50.390][000000009.449] I/user.excloud_app 收到平台消息 seq= 1
[2026-08-07 11:08:50.393][000000009.449] I/user.excloud_app   [1] field=17 type=3 value=ok
[2026-08-07 11:08:50.396][000000009.450] I/user.[excloud]TCP socket cb userdata: 0C184050 33554450 0
[2026-08-07 11:08:50.398][000000009.451] I/user.[excloud]TCP socket 发送完成
[2026-08-07 11:08:50.763][000000009.819] I/user.SMS_REPORT msg_ref= 10 status= 65 str= FAILED_INCOMPAT_DEST phone= 8617538215008 time= 26-08-07 11:08:51
[2026-08-07 11:08:50.765][000000009.819] I/user.SMS_REPORT 目标不可达(空号) 8617538215008
[2026-08-07 11:08:50.771][000000009.820] I/user.sms_bridge SMS_REPORT上报 plat_seq 1786072129 msg_ref 10 status 目标不可达(空号/离线) phone 8617538215008
[2026-08-07 11:08:50.774][000000009.821] I/user.[excloud]构建发送数据 field: 30 type: 0 value: 0
[2026-08-07 11:08:50.778][000000009.823] I/user.[excloud]构建发送数据 field: 1039 type: 3 value: 1786072129
[2026-08-07 11:08:50.781][000000009.824] I/user.[excloud]构建发送数据 field: 1040 type: 3 value: 8617538215008
[2026-08-07 11:08:50.786][000000009.826] I/user.[excloud]构建发送数据 field: 1041 type: 5 value: 301
[2026-08-07 11:08:50.790][000000009.827] I/user.[excloud]构建发送数据 field: 1042 type: 5 value: 目标不可达(空号/离线)
[2026-08-07 11:08:50.792][000000009.828] I/user.[excloud]构建发送数据 field: 1047 type: 0 value: 10
[2026-08-07 11:08:50.795][000000009.830] I/user.[excloud]tlv发送数据长度4 88
[2026-08-07 11:08:50.797][000000009.831] I/user.[excloud]构建消息头 seq: 4 len: 88 flags: 2 dev: 0186232308999518
[2026-08-07 11:08:50.800][000000009.834] I/user.[excloud]数据发送成功 104 字节
[2026-08-07 11:08:50.803][000000009.835] I/user.sms SMS_REPORT上报 plat_seq 1786072129 msg_ref 10 status 目标不可达(空号/离线) phone 8617538215008
[2026-08-07 11:08:50.839][000000009.892] I/user.[excloud]TCP socket cb userdata: 0C184050 33554450 0
[2026-08-07 11:08:50.842][000000009.892] I/user.[excloud]TCP socket 发送完成
[2026-08-07 11:08:51.278][000000010.337] D/sms pdu len 15
[2026-08-07 11:08:51.832][000000010.879] I/user.SMS_SENT result= false rp_cause= 111 msg_ref= 0 error_code= 65535
[2026-08-07 11:08:51.835][000000010.879] I/user.SMS_SENT 发送失败 PROTOCOL_ERROR error_code= 65535
[2026-08-07 11:08:51.838][000000010.880] I/user.sms_bridge SMS_SENT上报 plat_seq 1786072131 msg_ref 0 status 发送失败 callee 10001
[2026-08-07 11:08:51.841][000000010.881] I/user.[excloud]构建发送数据 field: 29 type: 0 value: 0
[2026-08-07 11:08:51.844][000000010.882] I/user.[excloud]构建发送数据 field: 1039 type: 3 value: 1786072131
[2026-08-07 11:08:51.847][000000010.884] I/user.[excloud]构建发送数据 field: 1040 type: 3 value: 10001
[2026-08-07 11:08:51.851][000000010.885] I/user.[excloud]构建发送数据 field: 1041 type: 5 value: 102
[2026-08-07 11:08:51.855][000000010.886] I/user.[excloud]构建发送数据 field: 1042 type: 5 value: 发送失败
[2026-08-07 11:08:51.858][000000010.888] I/user.[excloud]构建发送数据 field: 1047 type: 0 value: 0
[2026-08-07 11:08:51.860][000000010.889] I/user.[excloud]tlv发送数据长度4 62
[2026-08-07 11:08:51.862][000000010.890] I/user.[excloud]构建消息头 seq: 5 len: 62 flags: 2 dev: 0186232308999518
[2026-08-07 11:08:51.867][000000010.893] I/user.[excloud]数据发送成功 78 字节
[2026-08-07 11:08:51.869][000000010.893] I/user.sms SMS_SENT上报 plat_seq 1786072131 msg_ref 0 status 发送失败 callee 10001
[2026-08-07 11:08:51.895][000000010.948] I/user.[excloud]TCP socket cb userdata: 0C184050 33554450 0
[2026-08-07 11:08:51.900][000000010.949] I/user.[excloud]TCP socket 发送完成
[2026-08-07 11:09:39.842][000000058.901] D/sms dcs 8 | 0 | 0 | 0
[2026-08-07 11:09:39.845][000000058.902] I/user.sms_bridge 收到短信上报 106980095566 seq= 1
[2026-08-07 11:09:39.847][000000058.903] I/user.[excloud]构建发送数据 field: 30 type: 0 value: 0
[2026-08-07 11:09:39.858][000000058.905] I/user.[excloud]构建发送数据 field: 1039 type: 3 value: 1
[2026-08-07 11:09:39.861][000000058.907] I/user.[excloud]构建发送数据 field: 1043 type: 3 value: 106980095566
[2026-08-07 11:09:39.863][000000058.909] I/user.[excloud]构建发送数据 field: 1041 type: 5 value: 【中国银行】立秋的第一杯奶茶，安排！点https://mbs.boc.cn/v/rYfyq  领淘宝闪购券，最高省15元。拒收请回复R
[2026-08-07 11:09:39.887][000000058.910] I/user.[excloud]tlv发送数据长度4 172
[2026-08-07 11:09:39.891][000000058.911] I/user.[excloud]构建消息头 seq: 6 len: 172 flags: 2 dev: 0186232308999518
[2026-08-07 11:09:39.893][000000058.914] I/user.[excloud]数据发送成功 188 字节
[2026-08-07 11:09:39.895][000000058.915] I/user.sms 收到短信上报 phone 106980095566 seq 1
[2026-08-07 11:09:39.935][000000058.985] I/user.[excloud]TCP socket cb userdata: 0C184050 33554450 0
[2026-08-07 11:09:39.938][000000058.985] I/user.[excloud]TCP socket 发送完成
[2026-08-07 11:09:50.081][000000069.141] I/user.excloud_app 首次上传运维日志
[2026-08-07 11:09:50.095][000000069.148] I/user.[excloud]运维日志文件检查 /hzmtn1.trc true 0
[2026-08-07 11:09:50.099][000000069.154] I/user.[excloud]运维日志文件检查 /hzmtn2.trc true 0
[2026-08-07 11:09:50.111][000000069.160] I/user.[excloud]运维日志文件检查 /hzmtn3.trc true 1640
[2026-08-07 11:09:50.116][000000069.167] I/user.[excloud]运维日志文件检查 /hzmtn4.trc true 0
[2026-08-07 11:09:50.121][000000069.167] I/user.[excloud]开始上传运维日志 文件数: 1
[2026-08-07 11:09:50.127][000000069.173] I/user.[excloud]开始文件上传 类型: 3 文件: /hzmtn3.trc 大小: 1640
[2026-08-07 11:09:50.131][000000069.174] I/user.[excloud]开始发送HTTP请求 URL: https://api.luatos.com/iot/air_up/file
[2026-08-07 11:09:50.134][000000069.179] D/socket connect to api.luatos.com,443
[2026-08-07 11:09:50.138][000000069.180] dns_run 845:api.luatos.com state 0 id 7523 ipv6 0 use dns server2, try 0
[2026-08-07 11:09:50.173][000000069.220] dns_run 862:dns all done ,now stop
[2026-08-07 11:09:50.794][000000069.852] I/zbuff create large size: 64 kbyte, trigger force GC
[2026-08-07 11:09:51.190][000000070.244] I/user.httpplus 服务器已完成响应
[2026-08-07 11:09:51.192][000000070.247] I/user.[excloud]文件上传响应 HTTP Code: 200 Body: {"info":"iot./iot/air_up/file","code":0,"trace":"iot./iot/air_up/file trcace:","log":"^^^","value":{"uri":"/vsa/aircloud_file/Dn...
[2026-08-07 11:09:51.195][000000070.248] I/user.[excloud]文件上传成功 URL: /vsa/aircloud_file/Dn2wZzL153pU5yZbufKb6S/2026-08/862323089995180/20260807110952_hzmtn3.trc
[2026-08-07 11:09:51.205][000000070.252] I/user.[excloud]文件上传完成
[2026-08-07 11:09:51.208][000000070.253] I/user.[excloud]运维日志上传成功 文件: hzmtn3.trc 大小: 1640
[2026-08-07 11:09:51.211][000000070.254] I/user.[excloud]构建发送数据 field: 27 type: 4 value: {"index":3,"timestamp":1786072191,"status":1}
[2026-08-07 11:09:51.213][000000070.255] I/user.[excloud]tlv发送数据长度4 49
[2026-08-07 11:09:51.215][000000070.256] I/user.[excloud]构建消息头 seq: 7 len: 49 flags: 2 dev: 0186232308999518
[2026-08-07 11:09:51.217][000000070.259] I/user.[excloud]数据发送成功 65 字节
[2026-08-07 11:09:51.220][000000070.263] I/user.[excloud]运维日志文件已清空 /hzmtn3.trc
[2026-08-07 11:09:51.223][000000070.264] I/user.[excloud]运维日志上传完成 成功文件数: 1 失败文件数: 0
[2026-08-07 11:09:51.269][000000070.321] I/user.[excloud]TCP socket cb userdata: 0C184050 33554450 0
[2026-08-07 11:09:51.272][000000070.322] I/user.[excloud]TCP socket 发送完成
```

4、Aircloud平台可以看到如下报文上报
![](https://docs.openluat.com/air8000/luatos/app/image/8783短信aircloud.jpg)



