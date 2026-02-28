# AirCAMERA_1020 DEMO

## 演示功能概述

本示例主要是展示 AirCAMERA_1020 的使用，本地拍摄照片后通过 httpplus 扩展库将图片上传至 air32.com，本地录制视频后通过 httpplus 扩展库将视频上传至 air32.com

1、main.lua：主程序入口

2、take_photo_http_post.lua：执行拍照后上传照片至 air32.com

3、video_http_post.lua：执行录像后上传视频至 air32.com

4、netdrv_wifi.lua：连接 WIFI

注意：take_photo_http_post.lua 和 video_http_post.lua 只能打开一个不能同时打开

## 演示功能概述

### 1、主程序入口模块（main.lua）

- 初始化项目信息和版本号

- 初始化看门狗，并定时喂狗

- 启动一个循环定时器，每隔 3 秒钟打印一次总内存，实时的已使用内存，历史最高的已使用内存情况方便分析内存使用是否有异常

- 加载 netdrv_wifi 模块（通过 require "netdrv_wifi"）

- 加载 take_photo_http_post 模块（通过 require "take_photo_http_post"）

### 2、WIFI 连接模块（netdrv_wifi.lua）

- 订阅"IP_READY"和"IP_LOSE"

- 根据对应的网络状态执行对应的动作

- 联网成功则配置 DNS

- 联网失败则打印联网失败日志

### 3、拍照上传核心业务模块（take_photo_http_post.lua）

- 每 30 秒触发一次拍照：AirCAMERA_1020_func()

- 每 3 秒打印一次系统和 LUA 的内存信息：memory_check()

- 配置摄像头信息表：dvp_camera_param

- 初始化摄像头：excamera.open()

- 执行拍照：excamera.photo()

- 上传照片：httpplus.request()

- 关闭摄像头：excamera.close()

### 4、录像上传核心业务模块（video_http_post.lua）

- 每 30 秒触发一次录像：AirCAMERA_1020_func()

- 每 10 秒打印一次系统和 LUA 的内存信息：memory_check()

- 配置摄像头信息表：dvp_camera_param

- 初始化摄像头：excamera.open()

- 执行录像：excamera.video()

- 录像结束后关闭摄像头：excamera.close()

- 上传视频：httpplus.request()

## 演示硬件环境

**使用拍照功能的硬件环境：**

1、Air8101 核心板一块

2、TYPE-C USB 数据线一根

3、合宙标准配件 AirCAMERA_1020 一块

4、Air8101 核心板和合宙标准配件 AirCAMERA_1020 的硬件接线方式为

Air8101 核心板通过 TYPE-C USB 口供电；（背面功耗测试开关拨到 OFF）

TYPE-C USB 数据线直接插到核心板的 TYPE-C USB 座子，另外一端连接电脑 USB 口；

AirCAMERA_1020 配件板 +Air8101 核心板，硬件连接示意图如下所示：

![](https://docs.openLuat.com/cdn/image/8101_dvp_photo.jpg)

**使用录像功能的硬件环境：**

1、Air8101 开发板一块，8101 USB 转串口供电下载扩展板一个

2、TYPE-C USB 数据线一根

3、合宙标准配件 AirCAMERA_1020 DVP摄像头一个

4、TF卡一张

5、母对母杜邦线一根

6、Air8101开发板通过USB 转串口供电下载扩展板和TYPE-C USB 数据线连接电脑，母对母杜邦线母头连接开发板SD_3.3V和SWD的3.3V供电相接(B10开发板才需要，B11以及以后的开发板不需要)，TF卡插进卡槽即可。DVP摄像头接入开发板对应槽位即可

实物接线图如下图所示：

![](https://docs.openLuat.com/cdn/image/8101_video.jpg)

## 演示软件环境

1、Luatools 下载调试工具：[https://docs.openluat.com/air780epm/common/Luatools/](https://docs.openluat.com/air780epm/common/Luatools/)

2、Air8101 V2004 版本固件：[https://docs.openluat.com/air8101/luatos/firmware/](https://docs.openluat.com/air8101/luatos/firmware/)

## 演示核心步骤

**使用拍照功能演示的核心步骤：**

1、搭建硬件环境;

2、修改 netdrv_wifi.lua 中的 WIFI 账号密码;

3、烧录 DEMO 代码;

4、等待自动拍照完成后上传平台，LUATOOLS会有如下打印;

```lua
[2025-11-17 14:44:06.904] luat:U(30608):I/user.初始化状态 true
[2025-11-17 14:44:06.904] luat:D(30608):camera:摄像头启动
[2025-11-17 14:44:06.904] luat:U(30609):I/user.照片存储路径 /ram/test.jpg
[2025-11-17 14:44:06.904] luat:D(30609):camera:选定的捕捉模式 0
[2025-11-17 14:44:06.904] luat:D(30609):camera:注册frame_callback, 帧格式 4
[2025-11-17 14:44:06.904] luat:U(30611):I/user.sys ram 175496 83600 125064
[2025-11-17 14:44:06.904] luat:U(30612):I/user.lua ram 1572856 185496 242224
[2025-11-17 14:44:07.375] luat:U(31148):I/user.摄像头数据 47184
[2025-11-17 14:44:07.381] luat:D(31150):camera:执行摄像头停止操作
[2025-11-17 14:44:07.381] luat:U(31152):I/user.拍照完成
[2025-11-17 14:44:07.381] luat:D(31158):socket:connect to upload.air32.cn,80
[2025-11-17 14:44:07.381] luat:D(31158):DNS:upload.air32.cn state 0 id 2 ipv6 0 use dns server0, try 0
[2025-11-17 14:44:07.381] luat:D(31159):net:adatper 2 dns server 223.5.5.5
[2025-11-17 14:44:07.381] luat:D(31159):net:dns udp sendto 223.5.5.5:53 from 192.168.1.119
[2025-11-17 14:44:07.472] luat:I(31217):DNS:dns all done ,now stop
[2025-11-17 14:44:07.472] luat:D(31218):net:connect 49.232.89.122:80 TCP
[2025-11-17 14:44:07.593] luat:U(31352):I/user.httpplus 等待服务器完成响应
[2025-11-17 14:44:07.855] luat:U(31623):I/user.httpplus 等待服务器完成响应
[2025-11-17 14:44:07.855] luat:U(31625):I/user.httpplus 服务器已完成响应,开始解析响应
[2025-11-17 14:44:07.864] luat:U(31634):I/user.http_upload_photo_task_func httpplus.request 200
[2025-11-17 14:44:07.864] luat:D(31635):camera:执行摄像头关闭操作
[2025-11-17 14:44:07.864] cpu1:img_serv:W(1116):img_service_close already close
```

5、登录 https://www.air32.cn/upload/jpg/ 查看拍摄的照片;

![](https://docs.openluat.com/air8101/luatos/app/accessory/AirCAMERA_1020/image/httpupload.png)

**使用录像功能演示的核心步骤：**

1、搭建硬件环境;

2、修改 netdrv_wifi.lua 中的 WIFI 账号密码;

打开 main.lua文件中 require "video_http_post" 同时注释掉 require "take_photo_http_post"

3、烧录 DEMO 代码;

4、等待自动录像完成后上传平台，LUATOOLS会有类似如下打印;

```lua
[2026-02-11 15:03:46.133] luat:I(1352):fatfs:mount success at fat32
[2026-02-11 15:03:46.133] luat:U(1353):I/user.TF卡挂载成功
[2026-02-11 15:03:46.133] luat:U(1354):I/user.剩余空间: 15176.156250000 MB
[2026-02-11 15:03:46.139] ap0:hal:W(1248):gpio: 27 is used.Please confirm unmap isn't impact is working module.!
[2026-02-11 15:03:46.139] luat:D(1361):i2c:i2c(1) gpio init : scl 0 sda 1
[2026-02-11 15:03:46.139] ap0:i2c:W(1249):i2c(1) master_read get ack failed
[2026-02-11 15:03:46.139] ap0:i2c:W(1249):i2c(1) master_read get ack failed
[2026-02-11 15:03:46.363] luat:U(1572):I/user.摄像头初始化状态 true
[2026-02-11 15:03:46.363] luat:U(1573):I/user.开始录制视频 /sd/video_dvp_ 1.mp4
[2026-02-11 15:03:46.363] luat:U(1585):I/user.excamera.mount_tf_card TF卡已经挂载
[2026-02-11 15:03:46.363] luat:U(1586):I/user.excamera.video 开始录制视频到 /sd/video_dvp_ 1.mp4
[2026-02-11 15:03:46.363] luat:U(1586):I/user.excamera.video lua内存: 2097144 171544 174512
[2026-02-11 15:03:46.363] luat:U(1586):I/user.excamera.video sys内存: 238608 72512 72512
[2026-02-11 15:03:46.363] ap0:CAM:W(1474):拍照/录像到文件录 /sd/video_dvp_ 1.mp4
[2026-02-11 15:03:46.380] ap0:CAM:W(1474):选定的捕捉模式 4
[2026-02-11 15:03:46.708] ap0:hal:W(1794):gpio: 27 is used.Please confirm unmap isn't impact is working module.!
[2026-02-11 15:03:46.708] ap0:hal:W(1795):gpio: 27 is used.Please confirm unmap isn't impact is working module.!
[2026-02-11 15:03:46.708] luat:D(1907):i2c:i2c(1) gpio init : scl 0 sda 1
[2026-02-11 15:03:46.708] ap0:i2c:W(1795):i2c(1) master_read get ack failed
[2026-02-11 15:03:46.708] ap0:i2c:W(1795):i2c(1) master_read get ack failed
[2026-02-11 15:03:47.370] wifid:I(2577):[KW:]scanu_confirm:status=0,req_type=0,upload_cnt=10,recv_cnt=45,time=1705885us,result=1,rfcli=0
[2026-02-11 15:03:47.370] wpa:I(2578):Scan completed in 1.704000 seconds
[2026-02-11 15:03:47.370] hitf:I(2578):get scan result:1
[2026-02-11 15:03:47.378] wpa:I(2579):State: SCANNING -> ASSOCIATING
[2026-02-11 15:03:47.378] wifid:I(2580):[KW:]conn vif0-0,auth_type:0,bssid:6924-6068-6ac3,ssid:116,is encryp:8.
[2026-02-11 15:03:47.378] wifid:I(2580):chan_ctxt_add: CTXT0,freq2412MHz,bw20MHz,pwr32dBm
[2026-02-11 15:03:47.378] wifid:I(2580):chan_reg_fix:VIF0,CTXT0,type3,ctxt_s0,nb_vif0
[2026-02-11 15:03:47.378] wifid:I(2581):mm_sta_add:vif 0,sta 0,status 0
[2026-02-11 15:03:47.418] wifid:I(2624):[KW:]auth_send:seq1, txtype0, auth_type0, seq46
[2026-02-11 15:03:47.418] wifid:I(2638):[KW:]sm_auth_handler: status code 0, tx status 0x80800200
[2026-02-11 15:03:47.418] wifid:I(2638):[KW:]assoc_req_send:is ht, seq_num:47
[2026-02-11 15:03:47.424] wifid:I(2642):[KW:]assoc_rsp:status0,tx_s0x80800000
[2026-02-11 15:03:47.424] wifid:I(2642):[KW:]mm_set_vif_state,vif=0,vif_type=0,is_active=1, aid=0x7,rssi=-54
[2026-02-11 15:03:47.424] wpa:I(2643):State: ASSOCIATING -> ASSOCIATED
[2026-02-11 15:03:47.433] wpa:I(2649):State: ASSOCIATED -> 4WAY_HANDSHAKE
[2026-02-11 15:03:47.433] wpa:I(2650):WPA: TK 3c761b19f4874417b9decf4cb47000e9
[2026-02-11 15:03:47.439] wpa:I(2660):State: 4WAY_HANDSHAKE -> 4WAY_HANDSHAKE
[2026-02-11 15:03:47.464] hitf:I(2667):add CCMP
[2026-02-11 15:03:47.464] wpa:I(2667):State: 4WAY_HANDSHAKE -> GROUP_HANDSHAKE
[2026-02-11 15:03:47.464] hitf:I(2668):add CCMP
[2026-02-11 15:03:47.464] wpa:I(2668):State: GROUP_HANDSHAKE -> COMPLETED
[2026-02-11 15:03:47.464] lwip:I(2669):sta ip start
[2026-02-11 15:03:47.464] lwip:I(2669):[KW:]sta:DHCP_DISCOVER()
[2026-02-11 15:03:47.477] lwip:I(2688):[KW:]sta:DHCP_OFFER received in DHCP_STATE_SELECTING state
[2026-02-11 15:03:47.477] lwip:I(2688):[KW:]sta:DHCP_REQUEST(netif=0x280655b4) en   1
[2026-02-11 15:03:47.482] lwip:I(2705):[KW:]sta:DHCP_ACK received
[2026-02-11 15:03:47.485] wifid:I(2706):[KW:]me dhcp done vif:0
[2026-02-11 15:03:47.485] event:W(2707):event <2 0> has no cb
[2026-02-11 15:03:47.491] ap0:lwip:I(2598):sta ip start
[2026-02-11 15:03:47.491] luat:D(2710):wlan:event_module 1 event_id 2
[2026-02-11 15:03:47.491] luat:D(2711):wlan:STA connected 116 
[2026-02-11 15:03:47.491] luat:D(2711):wlan:event_module 2 event_id 0
[2026-02-11 15:03:47.491] luat:D(2711):wlan:ipv4 got!! 192.168.0.107
[2026-02-11 15:03:47.491] luat:D(2711):net:network ready 2, setup dns server
[2026-02-11 15:03:47.505] luat:D(2721):wlan:set dns server to 103.85.84.202
[2026-02-11 15:03:47.505] luat:D(2721):net:设置DNS服务器 id 2 index 3 ip 103.85.84.202
[2026-02-11 15:03:47.505] luat:D(2721):wlan:sta ip 192.168.0.107
[2026-02-11 15:03:47.505] luat:U(2722):I/user.dnsproxy 开始监听
[2026-02-11 15:03:47.505] luat:D(2723):net:设置DNS服务器 id 2 index 0 ip 223.5.5.5
[2026-02-11 15:03:47.505] luat:D(2723):net:设置DNS服务器 id 2 index 1 ip 114.114.114.114
[2026-02-11 15:03:47.505] luat:U(2723):I/user.netdrv_wifi.ip_ready_func IP_READY 192.168.0.107 255.255.255.0 192.168.0.1 nil
[2026-02-11 15:03:47.807] luat:I(3006):mp4box:start flush buffer 262144 bytes 0x609e4720
[2026-02-11 15:03:48.456] luat:I(3655):mp4box:start flush buffer 262144 bytes 0x609e4720
[2026-02-11 15:03:49.109] luat:I(4304):mp4box:start flush buffer 262144 bytes 0x609e4720
[2026-02-11 15:03:49.757] luat:I(4953):mp4box:start flush buffer 262144 bytes 0x609e4720
[2026-02-11 15:03:50.438] luat:I(5648):mp4box:start flush buffer 262144 bytes 0x609e4720
[2026-02-11 15:03:51.089] luat:I(6297):mp4box:start flush buffer 262144 bytes 0x609e4720
[2026-02-11 15:03:51.739] luat:I(6946):mp4box:start flush buffer 262144 bytes 0x609e4720
[2026-02-11 15:03:52.389] luat:I(7595):mp4box:start flush buffer 262144 bytes 0x609e4720
[2026-02-11 15:03:53.038] luat:I(8244):mp4box:start flush buffer 262144 bytes 0x609e4720
[2026-02-11 15:03:53.828] luat:I(9031):mp4box:start flush buffer 262144 bytes 0x609e4720
[2026-02-11 15:03:54.571] luat:I(9773):mp4box:start flush buffer 262144 bytes 0x609e4720
[2026-02-11 15:03:55.363] luat:I(10560):mp4box:start flush buffer 262144 bytes 0x609e4720
[2026-02-11 15:03:56.093] luat:I(11302):mp4box:start flush buffer 262144 bytes 0x609e4720
[2026-02-11 15:03:56.153] luat:U(11355):I/user.系统内存使用情况 238608 113472 113936
[2026-02-11 15:03:56.153] luat:U(11356):I/user.Lua虚拟机内存使用情况 2097144 172704 174512
[2026-02-11 15:03:56.881] luat:I(12089):mp4box:start flush buffer 262144 bytes 0x609e4720
[2026-02-11 15:03:57.624] luat:I(12831):mp4box:start flush buffer 262144 bytes 0x609e4720
[2026-02-11 15:03:58.371] luat:I(13573):mp4box:start flush buffer 262144 bytes 0x609e4720
[2026-02-11 15:03:59.112] luat:I(14315):mp4box:start flush buffer 262144 bytes 0x609e4720
[2026-02-11 15:03:59.948] luat:I(15148):mp4box:start flush buffer 262144 bytes 0x609e4720
[2026-02-11 15:04:00.691] luat:I(15890):mp4box:start flush buffer 262144 bytes 0x609e4720
[2026-02-11 15:04:01.434] luat:I(16632):mp4box:start flush buffer 262144 bytes 0x609e4720
[2026-02-11 15:04:02.194] luat:I(17419):mp4box:start flush buffer 262144 bytes 0x609e4720
[2026-02-11 15:04:02.950] luat:I(18161):mp4box:start flush buffer 262144 bytes 0x609e4720
[2026-02-11 15:04:03.740] luat:I(18948):mp4box:start flush buffer 262144 bytes 0x609e4720
[2026-02-11 15:04:04.484] luat:I(19690):mp4box:start flush buffer 262144 bytes 0x609e4720
[2026-02-11 15:04:05.224] luat:I(20431):mp4box:start flush buffer 262144 bytes 0x609e4720
[2026-02-11 15:04:06.017] luat:I(21219):mp4box:start flush buffer 262144 bytes 0x609e4720
[2026-02-11 15:04:06.158] luat:U(21356):I/user.系统内存使用情况 238608 113472 113936
[2026-02-11 15:04:06.158] luat:U(21357):I/user.Lua虚拟机内存使用情况 2097144 172976 174512
[2026-02-11 15:04:06.796] luat:I(22007):mp4box:start flush buffer 262144 bytes 0x609e4720
[2026-02-11 15:04:07.541] luat:I(22749):mp4box:start flush buffer 262144 bytes 0x609e4720
[2026-02-11 15:04:08.289] luat:I(23491):mp4box:start flush buffer 262144 bytes 0x609e4720
[2026-02-11 15:04:09.079] luat:I(24278):mp4box:start flush buffer 262144 bytes 0x609e4720
[2026-02-11 15:04:09.808] luat:I(25020):mp4box:start flush buffer 262144 bytes 0x609e4720
[2026-02-11 15:04:10.600] luat:I(25807):mp4box:start flush buffer 262144 bytes 0x609e4720
[2026-02-11 15:04:11.343] luat:I(26549):mp4box:start flush buffer 262144 bytes 0x609e4720
[2026-02-11 15:04:12.133] luat:I(27336):mp4box:start flush buffer 262144 bytes 0x609e4720
[2026-02-11 15:04:12.877] luat:I(28078):mp4box:start flush buffer 262144 bytes 0x609e4720
[2026-02-11 15:04:13.638] luat:I(28866):mp4box:start flush buffer 262144 bytes 0x609e4720
[2026-02-11 15:04:14.395] luat:I(29607):mp4box:start flush buffer 262144 bytes 0x609e4720
[2026-02-11 15:04:15.184] luat:I(30395):mp4box:start flush buffer 262144 bytes 0x609e4720
[2026-02-11 15:04:15.933] luat:I(31137):mp4box:start flush buffer 262144 bytes 0x609e4720
[2026-02-11 15:04:16.147] luat:U(31357):I/user.系统内存使用情况 238608 113472 113936
[2026-02-11 15:04:16.147] luat:U(31358):I/user.Lua虚拟机内存使用情况 2097144 173464 174512
[2026-02-11 15:04:16.364] luat:I(31589):mp4box:start flush buffer 153195 bytes 0x609e4720
[2026-02-11 15:04:16.410] luat:I(31612):mp4box:mp4 file size before mdat 10376811
[2026-02-11 15:04:16.440] luat:I(31650):mp4box:总帧数 629, 关键帧数 5 总耗时 29104ms 平均帧率 21 fps
[2026-02-11 15:04:16.440] luat:I(31650):mp4box:mp4 file final size 10385006
[2026-02-11 15:04:16.446] luat:I(31659):mp4box:mp4 file closed, box write finished, file closed
[2026-02-11 15:04:16.503] luat:U(31703):I/user.excamera.video lua内存: 2097144 173648 174512
[2026-02-11 15:04:16.503] luat:U(31704):I/user.excamera.video sys内存: 238608 29976 113936
[2026-02-11 15:04:16.503] luat:U(31704):I/user.excamera.video 视频录制完成 /sd/video_dvp_ 1.mp4
[2026-02-11 15:04:16.503] luat:U(31704):I/user.视频录制成功!
[2026-02-11 15:04:16.503] luat:D(31709):socket:connect to upload.air32.cn,80
[2026-02-11 15:04:16.503] luat:D(31710):DNS:upload.air32.cn state 0 id 1 ipv6 0 use dns server0, try 0
[2026-02-11 15:04:16.503] luat:D(31710):net:adatper 2 dns server 223.5.5.5
[2026-02-11 15:04:16.503] luat:D(31711):net:dns udp sendto 223.5.5.5:53 from 192.168.0.107
[2026-02-11 15:04:17.497] luat:D(32710):DNS:upload.air32.cn state 0 id 1 ipv6 0 use dns server0, try 1
[2026-02-11 15:04:17.497] luat:D(32710):net:adatper 2 dns server 223.5.5.5
[2026-02-11 15:04:17.502] luat:D(32710):net:dns udp sendto 223.5.5.5:53 from 192.168.0.107
[2026-02-11 15:04:18.486] luat:D(33710):net:adatper 2 dns server 223.5.5.5
[2026-02-11 15:04:19.506] luat:D(34710):DNS:upload.air32.cn state 0 id 1 ipv6 0 use dns server0, try 2
[2026-02-11 15:04:19.506] luat:D(34710):net:adatper 2 dns server 223.5.5.5
[2026-02-11 15:04:19.506] luat:D(34710):net:dns udp sendto 223.5.5.5:53 from 192.168.0.107
[2026-02-11 15:04:19.569] luat:I(34778):DNS:dns all done ,now stop
[2026-02-11 15:04:19.569] luat:D(34778):net:adapter 2 connect 49.232.89.122:80 TCP
[2026-02-11 15:04:19.615] luat:I(34822):zbuff:create large size: 128 kbyte, trigger force GC
[2026-02-11 15:04:26.149] luat:U(41358):I/user.系统内存使用情况 238608 30184 113936
[2026-02-11 15:04:26.149] luat:U(41359):I/user.Lua虚拟机内存使用情况 2097144 175144 178464
[2026-02-11 15:04:36.141] luat:U(51359):I/user.系统内存使用情况 238608 30184 113936
[2026-02-11 15:04:36.141] luat:U(51360):I/user.Lua虚拟机内存使用情况 2097144 178128 178464
[2026-02-11 15:04:46.145] luat:U(61360):I/user.系统内存使用情况 238608 30184 113936
[2026-02-11 15:04:46.145] luat:U(61361):I/user.Lua虚拟机内存使用情况 2097144 181456 181456
[2026-02-11 15:04:56.134] luat:U(71361):I/user.系统内存使用情况 238608 30184 113936
[2026-02-11 15:04:56.134] luat:U(71362):I/user.Lua虚拟机内存使用情况 2097144 184568 184568
[2026-02-11 15:05:06.133] luat:U(81362):I/user.系统内存使用情况 238608 30184 113936
[2026-02-11 15:05:06.133] luat:U(81363):I/user.Lua虚拟机内存使用情况 2097144 187392 187392
[2026-02-11 15:05:16.149] luat:U(91363):I/user.系统内存使用情况 238608 30184 113936
[2026-02-11 15:05:16.149] luat:U(91364):I/user.Lua虚拟机内存使用情况 2097144 190736 190736
[2026-02-11 15:05:26.159] luat:U(101365):I/user.系统内存使用情况 238608 30184 113936
[2026-02-11 15:05:26.159] luat:U(101365):I/user.Lua虚拟机内存使用情况 2097144 193848 193848
[2026-02-11 15:05:36.145] luat:U(111366):I/user.系统内存使用情况 238608 30184 113936
[2026-02-11 15:05:36.145] luat:U(111367):I/user.Lua虚拟机内存使用情况 2097144 196672 196672
[2026-02-11 15:05:46.160] luat:U(121367):I/user.系统内存使用情况 238608 30184 113936
[2026-02-11 15:05:46.160] luat:U(121368):I/user.Lua虚拟机内存使用情况 2097144 209904 210000
[2026-02-11 15:05:55.665] luat:U(130877):I/user.httpplus 服务器已完成响应,开始解析响应
[2026-02-11 15:05:55.674] luat:U(130887):I/user.http上传完成，code: 200
[2026-02-11 15:05:55.674] luat:U(130888):I/user.上传成功
[2026-02-11 15:05:56.162] luat:U(131368):I/user.系统内存使用情况 238608 29896 113936
[2026-02-11 15:05:56.162] luat:U(131369):I/user.Lua虚拟机内存使用情况 2097144 241920 241920
[2026-02-11 15:05:59.200] cal:I(134406):idx:39=41+(-2),r:54,xtal:79,pwr_gain:a4ab7120
[2026-02-11 15:06:06.141] luat:U(141369):I/user.系统内存使用情况 238608 29896 113936
[2026-02-11 15:06:06.144] luat:U(141370):I/user.Lua虚拟机内存使用情况 2097144 242120 242120
[2026-02-11 15:06:16.120] ap0:hal:W(151244):gpio: 27 is used.Please confirm unmap isn't impact is working module.!
[2026-02-11 15:06:16.120] ap0:hal:W(151245):gpio: 27 is used.Please confirm unmap isn't impact is working module.!
[2026-02-11 15:06:16.120] luat:D(151358):i2c:i2c(1) gpio init : scl 0 sda 1
[2026-02-11 15:06:16.120] ap0:i2c:W(151246):i2c(1) master_read get ack failed
[2026-02-11 15:06:16.131] ap0:i2c:W(151246):i2c(1) master_read get ack failed
[2026-02-11 15:06:16.338] luat:U(151569):I/user.摄像头初始化状态 true
[2026-02-11 15:06:16.338] luat:U(151569):I/user.开始录制视频 /sd/video_dvp_ 2.mp4
[2026-02-11 15:06:16.345] luat:U(151578):I/user.excamera.mount_tf_card TF卡已经挂载
[2026-02-11 15:06:16.345] luat:U(151579):I/user.excamera.video 开始录制视频到 /sd/video_dvp_ 2.mp4
[2026-02-11 15:06:16.345] luat:U(151579):I/user.excamera.video lua内存: 2097144 243656 243656
[2026-02-11 15:06:16.345] luat:U(151579):I/user.excamera.video sys内存: 238608 72512 113936
[2026-02-11 15:06:16.345] ap0:CAM:W(151467):拍照/录像到文件录 /sd/video_dvp_ 2.mp4
[2026-02-11 15:06:16.345] ap0:CAM:W(151467):选定的捕捉模式 4
[2026-02-11 15:06:16.345] luat:U(151586):I/user.系统内存使用情况 238608 72512 113936
[2026-02-11 15:06:16.345] luat:U(151586):I/user.Lua虚拟机内存使用情况 2097144 243888 243888
[2026-02-11 15:06:16.618] ap0:hal:W(151744):gpio: 27 is used.Please confirm unmap isn't impact is working module.!
[2026-02-11 15:06:16.618] ap0:hal:W(151744):gpio: 27 is used.Please confirm unmap isn't impact is working module.!
[2026-02-11 15:06:16.618] luat:D(151857):i2c:i2c(1) gpio init : scl 0 sda 1
[2026-02-11 15:06:16.618] ap0:i2c:W(151745):i2c(1) master_read get ack failed
[2026-02-11 15:06:16.618] ap0:i2c:W(151745):i2c(1) master_read get ack failed
[2026-02-11 15:06:17.721] luat:I(152956):mp4box:start flush buffer 262144 bytes 0x60a04748
[2026-02-11 15:06:18.374] luat:I(153604):mp4box:start flush buffer 262144 bytes 0x60a04748
[2026-02-11 15:06:19.022] luat:I(154253):mp4box:start flush buffer 262144 bytes 0x60a04748
[2026-02-11 15:06:19.718] luat:I(154948):mp4box:start flush buffer 262144 bytes 0x60a04748
[2026-02-11 15:06:20.371] luat:I(155596):mp4box:start flush buffer 262144 bytes 0x60a04748
[2026-02-11 15:06:21.006] luat:I(156245):mp4box:start flush buffer 262144 bytes 0x60a04748
[2026-02-11 15:06:21.704] luat:I(156940):mp4box:start flush buffer 262144 bytes 0x60a04748
[2026-02-11 15:06:22.351] luat:I(157589):mp4box:start flush buffer 262144 bytes 0x60a04748
[2026-02-11 15:06:23.004] luat:I(158238):mp4box:start flush buffer 262144 bytes 0x60a04748
[2026-02-11 15:06:23.779] luat:I(159025):mp4box:start flush buffer 262144 bytes 0x60a04748
[2026-02-11 15:06:24.542] luat:I(159768):mp4box:start flush buffer 262144 bytes 0x60a04748
[2026-02-11 15:06:25.273] luat:I(160509):mp4box:start flush buffer 262144 bytes 0x60a04748
[2026-02-11 15:06:26.061] luat:I(161296):mp4box:start flush buffer 262144 bytes 0x60a04748
[2026-02-11 15:06:26.355] luat:U(161587):I/user.系统内存使用情况 238608 113472 113936
[2026-02-11 15:06:26.355] luat:U(161587):I/user.Lua虚拟机内存使用情况 2097144 244120 244120
[2026-02-11 15:06:26.793] luat:I(162038):mp4box:start flush buffer 262144 bytes 0x60a04748
[2026-02-11 15:06:27.597] luat:I(162825):mp4box:start flush buffer 262144 bytes 0x60a04748
[2026-02-11 15:06:28.342] luat:I(163567):mp4box:start flush buffer 262144 bytes 0x60a04748
[2026-02-11 15:06:29.039] luat:I(164264):mp4box:start flush buffer 262144 bytes 0x60a04748
[2026-02-11 15:06:29.859] luat:I(165096):mp4box:start flush buffer 262144 bytes 0x60a04748
[2026-02-11 15:06:30.648] luat:I(165884):mp4box:start flush buffer 262144 bytes 0x60a04748
[2026-02-11 15:06:31.390] luat:I(166626):mp4box:start flush buffer 262144 bytes 0x60a04748
[2026-02-11 15:06:32.180] luat:I(167413):mp4box:start flush buffer 262144 bytes 0x60a04748
[2026-02-11 15:06:32.923] luat:I(168155):mp4box:start flush buffer 262144 bytes 0x60a04748
[2026-02-11 15:06:33.669] luat:I(168897):mp4box:start flush buffer 262144 bytes 0x60a04748
[2026-02-11 15:06:34.457] luat:I(169684):mp4box:start flush buffer 262144 bytes 0x60a04748
[2026-02-11 15:06:35.200] luat:I(170426):mp4box:start flush buffer 262144 bytes 0x60a04748
[2026-02-11 15:06:35.963] luat:I(171214):mp4box:start flush buffer 262144 bytes 0x60a04748
[2026-02-11 15:06:36.351] luat:U(171587):I/user.系统内存使用情况 238608 113472 113936
[2026-02-11 15:06:36.351] luat:U(171588):I/user.Lua虚拟机内存使用情况 2097144 244192 244288
[2026-02-11 15:06:36.725] luat:I(171956):mp4box:start flush buffer 262144 bytes 0x60a04748
[2026-02-11 15:06:37.517] luat:I(172743):mp4box:start flush buffer 262144 bytes 0x60a04748
[2026-02-11 15:06:38.246] luat:I(173485):mp4box:start flush buffer 262144 bytes 0x60a04748
[2026-02-11 15:06:39.034] luat:I(174273):mp4box:start flush buffer 262144 bytes 0x60a04748
[2026-02-11 15:06:39.776] luat:I(175015):mp4box:start flush buffer 262144 bytes 0x60a04748
[2026-02-11 15:06:40.517] luat:I(175757):mp4box:start flush buffer 262144 bytes 0x60a04748
[2026-02-11 15:06:41.309] luat:I(176544):mp4box:start flush buffer 262144 bytes 0x60a04748
[2026-02-11 15:06:42.052] luat:I(177286):mp4box:start flush buffer 262144 bytes 0x60a04748
[2026-02-11 15:06:42.842] luat:I(178074):mp4box:start flush buffer 262144 bytes 0x60a04748
[2026-02-11 15:06:43.585] luat:I(178816):mp4box:start flush buffer 262144 bytes 0x60a04748
[2026-02-11 15:06:44.346] luat:I(179603):mp4box:start flush buffer 262144 bytes 0x60a04748
[2026-02-11 15:06:45.103] luat:I(180345):mp4box:start flush buffer 262144 bytes 0x60a04748
[2026-02-11 15:06:45.897] luat:I(181132):mp4box:start flush buffer 262144 bytes 0x60a04748
[2026-02-11 15:06:46.331] luat:I(181584):mp4box:start flush buffer 156768 bytes 0x60a04748
[2026-02-11 15:06:46.379] luat:I(181607):mp4box:mp4 file size before mdat 10380384
[2026-02-11 15:06:46.383] luat:I(181631):mp4box:总帧数 630, 关键帧数 5 总耗时 29150ms 平均帧率 21 fps
[2026-02-11 15:06:46.383] luat:I(181631):mp4box:mp4 file final size 10388591
[2026-02-11 15:06:46.389] luat:I(181644):mp4box:mp4 file closed, box write finished, file closed
[2026-02-11 15:06:46.457] luat:U(181699):I/user.excamera.video lua内存: 2097144 244688 244688
[2026-02-11 15:06:46.457] luat:U(181700):I/user.excamera.video sys内存: 238608 29976 113936
[2026-02-11 15:06:46.457] luat:U(181700):I/user.excamera.video 视频录制完成 /sd/video_dvp_ 2.mp4
[2026-02-11 15:06:46.465] luat:U(181700):I/user.视频录制成功!
[2026-02-11 15:06:46.465] luat:D(181705):socket:connect to upload.air32.cn,80
[2026-02-11 15:06:46.465] luat:D(181706):DNS:upload.air32.cn state 0 id 2 ipv6 0 use dns server0, try 0
[2026-02-11 15:06:46.465] luat:D(181706):net:adatper 2 dns server 223.5.5.5
[2026-02-11 15:06:46.465] luat:D(181706):net:dns udp sendto 223.5.5.5:53 from 192.168.0.107
[2026-02-11 15:06:46.465] luat:U(181708):I/user.系统内存使用情况 238608 30104 113936
[2026-02-11 15:06:46.465] luat:U(181708):I/user.Lua虚拟机内存使用情况 2097144 246136 246136
[2026-02-11 15:06:46.484] luat:I(181738):DNS:dns all done ,now stop
[2026-02-11 15:06:46.484] luat:D(181739):net:adapter 2 connect 49.232.89.122:80 TCP
[2026-02-11 15:06:47.683] luat:I(182919):zbuff:create large size: 128 kbyte, trigger force GC
[2026-02-11 15:06:56.475] luat:U(191708):I/user.系统内存使用情况 238608 30184 113936
[2026-02-11 15:06:56.475] luat:U(191709):I/user.Lua虚拟机内存使用情况 2097144 176280 248736
[2026-02-11 15:07:06.461] luat:U(201709):I/user.系统内存使用情况 238608 30184 113936
[2026-02-11 15:07:06.461] luat:U(201710):I/user.Lua虚拟机内存使用情况 2097144 182520 248736
[2026-02-11 15:07:16.472] luat:U(211710):I/user.系统内存使用情况 238608 30184 113936
[2026-02-11 15:07:16.472] luat:U(211711):I/user.Lua虚拟机内存使用情况 2097144 187104 248736
[2026-02-11 15:07:26.477] luat:U(221711):I/user.系统内存使用情况 238608 30184 113936
[2026-02-11 15:07:26.477] luat:U(221712):I/user.Lua虚拟机内存使用情况 2097144 191968 248736
[2026-02-11 15:07:36.474] luat:U(231712):I/user.系统内存使用情况 238608 30184 113936
[2026-02-11 15:07:36.474] luat:U(231713):I/user.Lua虚拟机内存使用情况 2097144 196816 248736
[2026-02-11 15:07:44.231] cal:I(239466):idx:39=41+(-2),r:54,xtal:79,pwr_gain:a4ab7120
[2026-02-11 15:07:46.476] luat:U(241713):I/user.系统内存使用情况 238608 30184 113936
[2026-02-11 15:07:46.476] luat:U(241714):I/user.Lua虚拟机内存使用情况 2097144 200376 248736
[2026-02-11 15:07:55.161] luat:U(250402):I/user.httpplus 服务器已完成响应,开始解析响应
[2026-02-11 15:07:55.174] luat:U(250412):I/user.http上传完成，code: 200
[2026-02-11 15:07:55.174] luat:U(250412):I/user.上传成功
```

5、登录[Index of /upload/mp4/](https://www.air32.cn/upload/mp4/)查看录制的视频;
