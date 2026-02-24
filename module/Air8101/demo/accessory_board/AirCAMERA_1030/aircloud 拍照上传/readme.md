# AirCAMERA_1030 DEMO

## 演示功能概述

本示例主要是展示 AirCAMERA_1030 的使用，本地拍摄照片或者视频录制后通过 httpplus 扩展库将图片或者视频上传至 aircloud平台

1、main.lua：主程序入口

2、take_photo_http_post.lua：执行拍照后上传照片至 aircloud平台

4、netdrv_wifi.lua：连接 WIFI

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

### 3、拍照上传核心业务模块（http_upload_file.lua）

- 订阅 IP_READY 信息，确认联网后执行拍照上传任务
- 每 10 秒触发一次拍照：AirCAMERA_1030_func()
- 每 10 秒打印一次系统和 LUA 的内存信息：memory_check()
- 配置摄像头信息表：usb_camera_param
- 初始化摄像头：excamera.open()
- 执行拍照：excamera.photo()
- 上传照片：excloud.upload_image()
- 关闭摄像头：excamera.close()

## 演示硬件环境

**使用拍照功能的硬件环境：**

1、Air8101 核心板一块

2、TYPE-C USB 数据线一根

3、合宙标准配件 AirCAMERA_1030 一块

4、Air8101 核心板和合宙标准配件 AirCAMERA_1030 的硬件接线方式为

Air8101 核心板通过 TYPE-C USB 口供电；（背面功耗测试开关拨到 OFF）

Air8101 核心板正面的 5V/3.3V 拨动开关，拨到5V的一端

TYPE-C USB 数据线直接插到核心板的 TYPE-C USB 座子，另外一端连接电脑 USB 口；

AirCAMERA_1030 配件板 + Air8101 核心板，硬件连接示意图：

单路摄像头链接方式

![](https://docs.openLuat.com/cdn/image/8101_usb_摄像头拍照.jpg)

## 演示软件环境

1、Luatools 下载调试工具：[https://docs.openluat.com/air780epm/common/Luatools/](https://docs.openluat.com/air780epm/common/Luatools/)

2、Air8101 V2002 版本固件：[https://docs.openluat.com/air8101/luatos/firmware/](https://docs.openluat.com/air8101/luatos/firmware/)

## 演示核心步骤

**使用拍照功能演示的核心步骤：**

1、搭建硬件环境;

2、修改 netdrv_wifi.lua 中的 WIFI 账号密码;打开 main.lua文件中 require "take_photo_http_post" 

3、烧录 DEMO 代码;
   单路摄像头请将take_photo_http_post.lua中的usb_port_num修改为1;
   将take_photo_http_post.lua中excloud_task_func函数中excloud.setup()接口中auth_key改为模组在iot平台中对应的项目key

4、等待摄像头自动拍照完成后上传平台，LUATOOLS会有如下打印;

```lua
[2026-02-02 14:34:22.950] luat:U(3979):I/user.netdrv_wifi.ip_ready_func IP_READY 192.168.0.109 255.255.255.0 192.168.0.1 nil
[2026-02-02 14:34:22.999] luat:I(4008):DNS:dns all done ,now stop
[2026-02-02 14:34:22.999] luat:D(4008):net:adapter 2 connect 1.94.5.143:443 TCP
[2026-02-02 14:34:23.082] luat:U(4102):I/user.dnsproxy 开始监听
[2026-02-02 14:34:23.518] luat:U(4553):I/user.httpplus 服务器已完成响应,开始解析响应
[2026-02-02 14:34:23.549] luat:U(4570):I/user.[excloud]excloud.getip响应 HTTP Code: 200 Body: luat:U(4570):{"msg":"ok","conninfo":{"ipv4":"124.71.128.165","port":9108},"imginfo":{"url":"https://gps.openluat.com/iot/aircloud/upload/image","data_key":"f","data_param":{"key":"7ncH1zGBnNYNjoubiU3B6J7meUtFchBP96vvt","tip":""}},"audinfo":{"url":"https://gps.openluat.com/iot/aircloud/upload/audio","data_key":"f","data_param":{"key":"7ncH1zGBnNYNjoubiU3B6J7meUtFchBP96vvt","tip":""}},"mtninfo":{"url":"https://gps.openluat.com/iot/aircloud/upload/file","data_key":"f","data_param":{"key":"7ncH1zGBnNYNjoubiU3B6J7meUtFchBP96vvt","tip":""}}}luat:U(4570):
[2026-02-02 14:34:23.555] luat:U(4570):I/user.[excloud]excloud.getip响应 HTTP Code: 200 Body: luat:U(4571):{"msg":"ok","conninfo":{"ipv4":"124.71.128.165","port":9108},"imginfo":{"url":"https://gps.openluat.com/iot/aircloud/upload/image","data_key":"f","data_param":{"key":"7ncH1zGBnNYNjoubiU3B6J7meUtFchBP96vvt","tip":""}},"audinfo":{"url":"https://gps.openluat.com/iot/aircloud/upload/audio","data_key":"f","data_param":{"key":"7ncH1zGBnNYNjoubiU3B6J7meUtFchBP96vvt","tip":""}},"mtninfo":{"url":"https://gps.openluat.com/iot/aircloud/upload/file","data_key":"f","data_param":{"key":"7ncH1zGBnNYNjoubiU3B6J7meUtFchBP96vvt","tip":""}}}luat:U(4571):
[2026-02-02 14:34:23.555] luat:U(4572):I/user.[excloud]获取到TCP/UDP连接信息 host: 124.71.128.165 port: 9108
[2026-02-02 14:34:23.555] luat:U(4572):I/user.[excloud]获取到图片上传信息
[2026-02-02 14:34:23.555] luat:U(4572):I/user.[excloud]获取到音频上传信息
[2026-02-02 14:34:23.555] luat:U(4572):I/user.[excloud]获取到运维日志上传信息
[2026-02-02 14:34:23.555] luat:U(4572):I/user.[excloud]excloud.getip 更新配置: 124.71.128.165 9108
[2026-02-02 14:34:23.555] luat:U(4573):I/user.[excloud]excloud.getip 成功: true 结果: {"ipv4":"124.71.128.165","port":9108}
[2026-02-02 14:34:23.555] luat:U(4573):I/user.[excloud]服务器信息获取成功 host: 124.71.128.165 port: 9108 transport: tcp
[2026-02-02 14:34:23.555] luat:U(4573):I/user.[excloud]创建TCP连接
[2026-02-02 14:34:23.555] luat:D(4574):socket:connect to 124.71.128.165,9108
[2026-02-02 14:34:23.555] luat:U(4575):network_socket_connect 1610:network 2-0 local port auto select 52002
[2026-02-02 14:34:23.555] luat:D(4575):net:adapter 2 connect 124.71.128.165:9108 TCP
[2026-02-02 14:34:23.555] luat:U(4576):I/user.[excloud]TCP连接结果 true false
[2026-02-02 14:34:23.555] luat:U(4576):I/user.[excloud]excloud service started
[2026-02-02 14:34:23.555] luat:U(4576):I/user.excloud服务已开启
[2026-02-02 14:34:23.555] luat:U(4577):I/user.[excloud]excloud 自动心跳已启动，间隔 300 秒
[2026-02-02 14:34:23.555] luat:U(4578):I/user.自动心跳已启动
[2026-02-02 14:34:23.608] luat:U(4608):network_default_socket_callback 1123:before process socket 1,event:0xf2000009(连接成功),state:3(正在连接),wait:2(等待连接完成)
[2026-02-02 14:34:23.608] luat:U(4609):network_default_socket_callback 1127:after process socket 1,state:5(在线),wait:0(无等待)
[2026-02-02 14:34:23.608] luat:U(4610):I/user.[excloud]socket cb userdata: 609615E8 33554449 0
[2026-02-02 14:34:23.608] luat:U(4611):I/user.[excloud]socket TCP连接成功
[2026-02-02 14:34:23.608] luat:U(4613):I/user.[excloud]构建发送数据 16 3 jqDKVo10JaU82v9h5sEprAWDfdwQEgMa-C8C2C68C5DEA-54540D2936 
[2026-02-02 14:34:23.608] luat:U(4614):I/user.[excloud]tlv发送数据长度4 60
[2026-02-02 14:34:23.608] luat:U(4615):                   I/user.[excloud]构建消息头 luat:U(4615):I/user.[excloud]发送消息长度 16 60 76 0200C8C2C68C5DEA0002003C00000011301000386A71444B566F31304A6155383276396835734570724157446664775145674D612D4338433243363843354445412D35343534304432393336 152
[2026-02-02 14:34:23.608] luat:U(4624):I/user.[excloud]数据发送成功 76 字节
[2026-02-02 14:34:23.635] luat:U(4649):network_default_socket_callback 1123:before process socket 1,event:0xf2000004(发送成功),state:5(在线),wait:3(等待发送完成)
[2026-02-02 14:34:23.635] luat:U(4649):network_default_socket_callback 1127:after process socket 1,state:5(在线),wait:0(无等待)
[2026-02-02 14:34:23.635] luat:U(4650):I/user.[excloud]socket cb userdata: 609615E8 33554450 0
[2026-02-02 14:34:23.635] luat:U(4650):I/user.[excloud]socket 发送完成
[2026-02-02 14:34:24.145] cal:I(5160):idx:41=42+(-1),r:54,xtal:77,pwr_gain:a4ab7131
[2026-02-02 14:34:31.910] luat:U(12924):I/user.sys ram 238200 46160 48224
[2026-02-02 14:34:31.910] luat:U(12924):I/user.lua ram 2097144 378392 511712
[2026-02-02 14:34:31.910] ap1:uvc_stre:W(12813):uvc_camera_device_power_on, port:5, device:0
[2026-02-02 14:34:31.910] ap1:uvc_stre:W(12813):uvc_camera_device_power_on, port:1, device:0, ret:0
[2026-02-02 14:34:31.923] luat:U(12939):I/user.初始化状态 true 这是第1个摄像头
[2026-02-02 14:34:31.923] luat:U(12940):I/user.照片存储路径 /ram/test.jpg
[2026-02-02 14:34:31.923] ap1:CAM:W(12827):拍照/录像到文件录 /ram/test.jpg
[2026-02-02 14:34:31.923] ap1:CAM:W(12827):选定的捕捉模式 1
[2026-02-02 14:34:32.382] luat:U(13393):I/user.摄像头数据 68703
[2026-02-02 14:34:32.382] luat:U(13394):I/user.拍照完成
[2026-02-02 14:34:32.382] luat:U(13395):I/user.这是第1个摄像头拍的
[2026-02-02 14:34:32.382] luat:U(13395):I/user.照片存储路径 /ram/test.jpg
[2026-02-02 14:34:32.382] luat:U(13395):I/user.文件存在，大小: 68703
[2026-02-02 14:34:41.914] luat:U(22924):I/user.sys ram 238200 46080 48224
[2026-02-02 14:34:41.914] luat:U(22925):I/user.lua ram 2097144 450632 581168
[2026-02-02 14:34:41.914] ap1:uvc_stre:W(22813):uvc_camera_device_power_on, port:5, device:0
[2026-02-02 14:34:41.914] ap1:uvc_stre:W(22813):uvc_camera_device_power_on, port:1, device:0, ret:0
[2026-02-02 14:34:41.914] luat:U(22939):I/user.初始化状态 true 这是第1个摄像头
[2026-02-02 14:34:41.929] luat:U(22940):I/user.照片存储路径 /ram/test.jpg
[2026-02-02 14:34:41.929] ap1:CAM:W(22827):拍照/录像到文件录 /ram/test.jpg
[2026-02-02 14:34:41.929] ap1:CAM:W(22827):选定的捕捉模式 1
[2026-02-02 14:34:42.370] luat:U(23394):I/user.摄像头数据 69022
[2026-02-02 14:34:42.375] luat:U(23395):I/user.拍照完成
[2026-02-02 14:34:42.375] luat:U(23395):I/user.这是第1个摄像头拍的
[2026-02-02 14:34:42.375] luat:U(23395):I/user.照片存储路径 /ram/test.jpg
[2026-02-02 14:34:42.375] luat:U(23396):I/user.文件存在，大小: 69022
[2026-02-02 14:34:42.497] luat:U(23518):I/user.开始上传图片
[2026-02-02 14:34:42.497] luat:U(23519):I/user.[excloud]开始文件上传 类型: 1 文件: /ram/test.jpg 大小: 69022
[2026-02-02 14:34:42.497] luat:U(23519):I/user.[excloud]开始文件上传 类型: 1 文件: test.jpg 大小: 69022
[2026-02-02 14:34:42.497] luat:U(23519):I/user.[excloud]构建发送数据 23 0 0 
[2026-02-02 14:34:42.497] luat:U(23520):I/user.[excloud]构建发送数据 784 0 1 
[2026-02-02 14:34:42.497] luat:U(23521):I/user.[excloud]构建发送数据 785 3 test.jpg 
[2026-02-02 14:34:42.497] luat:U(23522):I/user.[excloud]构建发送数据 786 0 69022 
[2026-02-02 14:34:42.497] luat:U(23522):I/user.[excloud]tlv发送数据长度4 36
[2026-02-02 14:34:42.562] luat:U(23523):                   I/user.[excloud]构建消息头 luat:U(23524):I/user.[excloud]发送消息长度 16 36 52 0200C8C2C68C5DEA00030024000000010017000400000000031000040000000133110008746573742E6A70670312000400010D9E 104
[2026-02-02 14:34:42.562] luat:U(23532):I/user.[excloud]数据发送成功 52 字节
[2026-02-02 14:34:42.562] luat:U(23557):I/user.[excloud]开始发送HTTP请求 URL: https://gps.openluat.com/iot/aircloud/upload/image
[2026-02-02 14:34:42.562] luat:I(23561):http:http idp:1
[2026-02-02 14:34:42.562] luat:D(23562):DNS:gps.openluat.com state 0 id 2 ipv6 0 use dns server0, try 0
[2026-02-02 14:34:42.562] luat:D(23562):net:adatper 2 dns server 223.5.5.5
[2026-02-02 14:34:42.562] luat:D(23562):net:dns udp sendto 223.5.5.5:53 from 192.168.0.109
[2026-02-02 14:34:42.583] luat:U(23568):network_default_socket_callback 1123:before process socket 1,event:0xf2000004(发送成功),state:5(在线),wait:3(等待发送完成)
[2026-02-02 14:34:42.583] luat:U(23568):network_default_socket_callback 1127:after process socket 1,state:5(在线),wait:0(无等待)
[2026-02-02 14:34:42.583] luat:U(23568):I/user.[excloud]socket cb userdata: 609615E8 33554450 0
[2026-02-02 14:34:42.583] luat:U(23569):I/user.[excloud]socket 发送完成
[2026-02-02 14:34:42.685] luat:I(23702):DNS:dns all done ,now stop
[2026-02-02 14:34:42.685] luat:D(23702):net:adapter 2 connect 1.94.5.143:443 TCP
[2026-02-02 14:34:43.298] cal:I(24313):idx:15=15+(0),r:54,xtal:76,pwr_gain:a4ab7090
[2026-02-02 14:34:44.943] luat:I(25969):http:http close 0x60a2bef8
[2026-02-02 14:34:44.948] luat:U(25971):I/user.[excloud]excloud.getip文件上传响应 HTTP Code: 200 Body: {"info":"iot./iot/aircloud/upload/image","code":0,"trace":"code:iot./iot/aircloud/upload/image,  trcace:","log":"^^^","value":{"uri":"/vsa/aircloud_image/E9MJkUWoD5TFMMPhHG88Ai/2026-02/C8C2C68C5DEA/20260202143446_test.jpg","size":"67.00KB","thumb":"/vsa/aircloud_image/E9MJkUWoD5TFMMPhHG88Ai/2026-02/C8C2C68C5DEA/20260202143446_testt.jpg"}}
[2026-02-02 14:34:44.948] luat:U(25972):I/user.[excloud]文件上传成功 URL: /vsa/aircloud_image/E9MJkUWoD5TFMMPhHG88Ai/2026-02/C8C2C68C5DEA/20260202143446_test.jpg
[2026-02-02 14:34:44.948] luat:U(25972):I/user.[excloud]构建发送数据 24 0 0 
[2026-02-02 14:34:44.948] luat:U(25973):I/user.[excloud]构建发送数据 784 0 1 
[2026-02-02 14:34:44.948] luat:U(25974):I/user.[excloud]构建发送数据 785 3 test.jpg 
[2026-02-02 14:34:44.948] luat:U(25975):I/user.[excloud]构建发送数据 787 0 0 
[2026-02-02 14:34:44.948] luat:U(25975):I/user.[excloud]tlv发送数据长度4 36
[2026-02-02 14:34:44.948] luat:U(25976):                   I/user.[excloud]构建消息头 luat:U(25977):I/user.[excloud]发送消息长度 16 36 52 0200C8C2C68C5DEA00040024000000010018000400000000031000040000000133110008746573742E6A70670313000400000000 104
[2026-02-02 14:34:44.948] luat:U(25985):I/user.[excloud]数据发送成功 52 字节
[2026-02-02 14:34:44.948] luat:U(25985):I/user.图片上传成功


```

5、登录[合宙Iot设备管理平台](https://iot.luatos.com/#/page6/aircloud_photos)查看拍摄的照片;

![](https://docs.openLuat.com/cdn/image/8101_aircloud_photo.jpg)
