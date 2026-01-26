# AirCAMERA_1030 DEMO

## 演示功能概述

本示例主要是展示 AirCAMERA_1030 的使用，本地拍摄照片或者视频录制后通过 httpplus 扩展库将图片或者视频上传至 air32.com

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
- 加载 video_http_post 模块（通过 require "video_http_post"）

### 2、WIFI 连接模块（netdrv_wifi.lua）

- 订阅"IP_READY"和"IP_LOSE"
- 根据对应的网络状态执行对应的动作
- 联网成功则配置 DNS
- 联网失败则打印联网失败日志

### 3、拍照上传核心业务模块（http_upload_file.lua）

- 订阅 IP_READY 信息，确认联网后执行拍照上传任务
- 每 30 秒触发一次拍照：AirCAMERA_1030_func()
- 每 3 秒打印一次系统和 LUA 的内存信息：memory_check()
- 配置摄像头信息表：usb_camera_param
- 初始化摄像头：excamera.open()
- 执行拍照：excamera.photo()
- 上传照片：httpplus.request()
- 关闭摄像头：excamera.close()

### 4、录像上传核心业务模块（video_http_post.lua）

- 订阅 IP_READY 信息，确认联网后执行录像上传任务
- tf卡挂载，打印tf卡内存信息：fatfs.mount()
- 摄像头初始化以后录制一个时长为30s的视频：excamera.video()
- 上传视频：httpplus.request()

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

四路摄像头链接方式
如图所示，将四路USB摄像头接入HUB中，然后将HUB通过USB口连接到Air8101核心板上;

![](https://docs.openLuat.com/cdn/image/8101_多usb_摄像头拍照.jpg)

**使用录像功能的硬件环境：**

1、Air8101 核心板一块

2、TYPE-C USB 数据线一根

3、合宙标准配件 AirCAMERA_1030 + AirMICROSD_1000 配件板 各一块

4、Air8101 核心板和合宙标准配件 AirCAMERA_1030 的硬件接线方式为

Air8101 核心板通过 TYPE-C USB 口供电；（背面功耗测试开关拨到 OFF）

Air8101 核心板正面的 5V/3.3V 拨动开关，拨到5V的一端

TYPE-C USB 数据线直接插到核心板的 TYPE-C USB 座子，另外一端连接电脑 USB 口；

AirMICROSD_1000 配件板与 Air8101核心板连接说明：

| Air8101核心板 | AirMICROSD_1000配件板 |
| ---------- | ------------------ |
| 59/3V3     | 3V3                |
| gnd        | gnd                |
| 9/GPIO6    | CD                 |
| 67/GPIO4   | D0                 |
| 66/GPIO3   | CMD                |
| 65/GPIO2   | CLK                |

 单路摄像头链接方式

![](https://docs.openLuat.com/cdn/image/8101_usb_摄像头录像.jpg)

四路摄像头链接方式

此方式下需要将8101核心板上的拨码开关拨动到5V供电

如图所示，将四路USB摄像头接入HUB中，然后将HUB通过USB口连接到Air8101核心板上;

![](https://docs.openLuat.com/cdn/image/8101_多usb_摄像头录像.jpg)

## 演示软件环境

1、Luatools 下载调试工具：[https://docs.openluat.com/air780epm/common/Luatools/](https://docs.openluat.com/air780epm/common/Luatools/)

2、Air8101 V1006 版本固件：[https://docs.openluat.com/air8101/luatos/firmware/](https://docs.openluat.com/air8101/luatos/firmware/)

## 演示核心步骤

**使用拍照功能演示的核心步骤：**

1、搭建硬件环境;

2、修改 netdrv_wifi.lua 中的 WIFI 账号密码;打开 main.lua文件中 require "take_photo_http_post" 同时注释掉 require "video_http_post"

3、烧录 DEMO 代码;
   单路摄像头请将take_photo_http_post.lua中的usb_port_num修改为1;
   四路或多路摄像头请将take_photo_http_post.lua中的usb_port_num修改为4或对应的摄像头数量;

4、等待单摄像头自动拍照完成后上传平台，LUATOOLS会有如下打印;

```lua
[2025-12-03 10:13:16.931] luat:U(83052):I/user.初始化状态 true 这是第1个摄像头
[2025-12-03 10:13:16.931] luat:U(83053):I/user.照片存储路径 /ram/test.jpg
[2025-12-03 10:13:17.053] luat:U(83187):I/user.摄像头数据 54696
[2025-12-03 10:13:17.053] luat:U(83188):I/user.拍照完成
[2025-12-03 10:13:17.053] luat:U(83189):I/user.这是第1个摄像头拍的
[2025-12-03 10:13:17.082] luat:D(83196):socket:connect to upload.air32.cn,80
[2025-12-03 10:13:17.082] luat:D(83197):DNS:upload.air32.cn state 0 id 9 ipv6 0 use dns server0, try 0
[2025-12-03 10:13:17.082] luat:D(83197):net:adatper 2 dns server 223.5.5.5
[2025-12-03 10:13:17.082] luat:D(83198):net:dns udp sendto 223.5.5.5:53 from 192.168.1.118
[2025-12-03 10:13:17.113] luat:I(83227):DNS:dns all done ,now stop
[2025-12-03 10:13:17.113] luat:D(83228):net:adapter 2 connect 49.232.89.122:80 TCP
[2025-12-03 10:13:17.408] luat:U(83520):I/user.httpplus 等待服务器完成响应
[2025-12-03 10:13:17.964] luat:U(84077):I/user.sys ram 233472 35256 35336
[2025-12-03 10:13:17.964] luat:U(84077):I/user.lua ram 2097144 730984 792808
[2025-12-03 10:13:18.399] luat:U(84521):I/user.httpplus 等待服务器完成响应
[2025-12-03 10:13:19.390] luat:U(85522):I/user.httpplus 等待服务器完成响应
[2025-12-03 10:13:20.411] luat:U(86523):I/user.httpplus 等待服务器完成响应
[2025-12-03 10:13:20.971] luat:U(87078):I/user.sys ram 233472 35256 35336
[2025-12-03 10:13:20.971] luat:U(87078):I/user.lua ram 2097144 732128 792808
[2025-12-03 10:13:21.402] luat:U(87524):I/user.httpplus 等待服务器完成响应
[2025-12-03 10:13:22.032] luat:U(88145):I/user.httpplus 等待服务器完成响应
[2025-12-03 10:13:22.032] luat:U(88150):I/user.httpplus 服务器已完成响应,开始解析响应
[2025-12-03 10:13:22.048] luat:U(88162):I/user.http_upload_photo_task_func httpplus.request 200
[2025-12-03 10:13:23.969] luat:U(90079):I/user.sys ram 233472 33376 35336
[2025-12-03 10:13:23.969] luat:U(90080):I/user.lua ram 2097144 693112 792808

```

等待4路摄像头自动轮切拍照完成后上传平台，LUATOOLS会有如下打印；

```lua
[2025-12-03 10:42:38.748] luat:U(3494):I/user.初始化状态 true 这是第1个摄像头
[2025-12-03 10:42:38.748] luat:U(3494):I/user.照片存储路径 /ram/test.jpg
[2025-12-03 10:42:38.748] luat:D(3495):net:network ready 2, setup dns server
[2025-12-03 10:42:38.748] luat:D(3496):net:设置DNS服务器 id 2 index 0 ip 223.5.5.5
[2025-12-03 10:42:38.764] luat:D(3497):net:设置DNS服务器 id 2 index 1 ip 114.114.114.114
[2025-12-03 10:42:38.764] luat:U(3497):I/user.netdrv_wifi.ip_ready_func IP_READY 192.168.1.118 255.255.255.0 192.168.1.1 nil
[2025-12-03 10:42:38.764] luat:U(3497):I/user.dnsproxy 开始监听
[2025-12-03 10:42:38.764] luat:D(3498):wlan:sta ip 192.168.1.118
[2025-12-03 10:42:38.764] luat:D(3498):wlan:设置STA网卡可用
[2025-12-03 10:42:38.764] luat:D(3498):net:设置DNS服务器 id 2 index 0 ip 223.5.5.5
[2025-12-03 10:42:38.764] luat:D(3499):net:设置DNS服务器 id 2 index 1 ip 114.114.114.114
[2025-12-03 10:42:38.764] luat:U(3499):I/user.netdrv_wifi.ip_ready_func IP_READY 192.168.1.118 255.255.255.0 192.168.1.1 nil
[2025-12-03 10:42:38.764] luat:U(3499):I/user.dnsproxy 开始监听
[2025-12-03 10:42:39.755] luat:U(4491):I/user.摄像头数据 19572
[2025-12-03 10:42:39.755] luat:U(4492):I/user.拍照完成
[2025-12-03 10:42:39.755] luat:U(4493):I/user.这是第1个摄像头拍的
[2025-12-03 10:42:39.755] luat:D(4497):socket:connect to upload.air32.cn,80
[2025-12-03 10:42:39.755] luat:D(4498):DNS:upload.air32.cn state 0 id 1 ipv6 0 use dns server0, try 0
[2025-12-03 10:42:39.755] luat:D(4498):net:adatper 2 dns server 223.5.5.5
[2025-12-03 10:42:39.755] luat:D(4499):net:dns udp sendto 223.5.5.5:53 from 192.168.1.118
[2025-12-03 10:42:40.018] luat:I(4753):DNS:dns all done ,now stop
[2025-12-03 10:42:40.018] luat:D(4753):net:adapter 2 connect 49.232.89.122:80 TCP
[2025-12-03 10:42:40.127] luat:U(4861):I/user.httpplus 等待服务器完成响应
[2025-12-03 10:42:40.329] luat:U(5076):I/user.httpplus 等待服务器完成响应
[2025-12-03 10:42:40.340] luat:U(5079):I/user.httpplus 服务器已完成响应,开始解析响应
[2025-12-03 10:42:40.340] luat:U(5089):I/user.http_upload_photo_task_func httpplus.request 200
[2025-12-03 10:42:41.036] luat:U(5780):I/user.sys ram 233472 33832 35792
[2025-12-03 10:42:41.036] luat:U(5781):I/user.lua ram 2097144 181512 205912
[2025-12-03 10:42:44.036] luat:U(8782):I/user.sys ram 233472 33832 35792
[2025-12-03 10:42:44.036] luat:U(8783):I/user.lua ram 2097144 181832 205912
[2025-12-03 10:42:47.041] luat:U(11784):I/user.sys ram 233472 33832 35792
[2025-12-03 10:42:47.041] luat:U(11785):I/user.lua ram 2097144 182064 205912
[2025-12-03 10:42:48.038] ap1:uvc_stre:W(12678):uvc_camera_device_power_on, port:5, device:0
[2025-12-03 10:42:48.038] ap1:uvc_stre:W(12678):uvc_camera_device_power_on, port:1, device:0, ret:0
[2025-12-03 10:42:48.038] ap1:CHERRY_U:E(12680):!!!config->fps 30
[2025-12-03 10:42:48.065] ap1:CHERRY_U:E(12681):!!!custom fps 15
[2025-12-03 10:42:48.065] luat:U(12797):I/user.初始化状态 true 这是第2个摄像头
[2025-12-03 10:42:48.065] luat:U(12797):I/user.照片存储路径 /ram/test.jpg
[2025-12-03 10:42:48.507] luat:U(13248):I/user.摄像头数据 20259
[2025-12-03 10:42:48.507] luat:U(13249):I/user.拍照完成
[2025-12-03 10:42:48.507] luat:U(13250):I/user.这是第2个摄像头拍的
[2025-12-03 10:42:48.507] luat:D(13254):socket:connect to upload.air32.cn,80
[2025-12-03 10:42:48.507] luat:D(13254):DNS:upload.air32.cn state 0 id 2 ipv6 0 use dns server0, try 0
[2025-12-03 10:42:48.507] luat:D(13255):net:adatper 2 dns server 223.5.5.5
[2025-12-03 10:42:48.507] luat:D(13255):net:dns udp sendto 223.5.5.5:53 from 192.168.1.118
[2025-12-03 10:42:48.558] luat:I(13276):DNS:dns all done ,now stop
[2025-12-03 10:42:48.558] luat:D(13277):net:adapter 2 connect 49.232.89.122:80 TCP
[2025-12-03 10:42:48.615] luat:U(13358):I/user.httpplus 等待服务器完成响应
[2025-12-03 10:42:48.957] luat:U(13715):I/user.httpplus 等待服务器完成响应
[2025-12-03 10:42:48.957] luat:U(13717):I/user.httpplus 服务器已完成响应,开始解析响应
[2025-12-03 10:42:48.975] luat:U(13727):I/user.http_upload_photo_task_func httpplus.request 200
[2025-12-03 10:42:50.051] luat:U(14786):I/user.sys ram 233472 33832 35792
[2025-12-03 10:42:50.051] luat:U(14787):I/user.lua ram 2097144 210240 236904
[2025-12-03 10:42:53.048] luat:U(17788):I/user.sys ram 233472 33832 35792
[2025-12-03 10:42:53.048] luat:U(17789):I/user.lua ram 2097144 210480 236904
[2025-12-03 10:42:56.046] luat:U(20790):I/user.sys ram 233472 33832 35792
[2025-12-03 10:42:56.046] luat:U(20790):I/user.lua ram 2097144 210688 236904
[2025-12-03 10:42:58.037] ap1:uvc_stre:W(22678):uvc_camera_device_power_on, port:5, device:0
[2025-12-03 10:42:58.037] ap1:uvc_stre:W(22678):uvc_camera_device_power_on, port:1, device:0, ret:0
[2025-12-03 10:42:58.037] ap1:CHERRY_U:E(22680):!!!config->fps 30
[2025-12-03 10:42:58.037] ap1:CHERRY_U:E(22680):!!!custom fps 15
[2025-12-03 10:42:58.329] luat:U(23063):I/user.初始化状态 true 这是第3个摄像头
[2025-12-03 10:42:58.329] luat:U(23064):I/user.照片存储路径 /ram/test.jpg
[2025-12-03 10:42:58.454] luat:U(23197):I/user.摄像头数据 36352
[2025-12-03 10:42:58.454] luat:U(23198):I/user.拍照完成
[2025-12-03 10:42:58.454] luat:U(23199):I/user.这是第3个摄像头拍的
[2025-12-03 10:42:58.479] luat:D(23206):socket:connect to upload.air32.cn,80
[2025-12-03 10:42:58.479] luat:D(23206):DNS:upload.air32.cn state 0 id 3 ipv6 0 use dns server0, try 0
[2025-12-03 10:42:58.479] luat:D(23207):net:adatper 2 dns server 223.5.5.5
[2025-12-03 10:42:58.479] luat:D(23207):net:dns udp sendto 223.5.5.5:53 from 192.168.1.118
[2025-12-03 10:42:58.479] luat:I(23231):DNS:dns all done ,now stop
[2025-12-03 10:42:58.479] luat:D(23231):net:adapter 2 connect 49.232.89.122:80 TCP
[2025-12-03 10:42:58.655] luat:U(23403):I/user.httpplus 等待服务器完成响应
[2025-12-03 10:42:59.042] luat:U(23791):I/user.sys ram 233472 35712 35792
[2025-12-03 10:42:59.042] luat:U(23792):I/user.lua ram 2097144 252608 314400
[2025-12-03 10:42:59.151] luat:U(23898):I/user.httpplus 等待服务器完成响应
[2025-12-03 10:42:59.162] luat:U(23901):I/user.httpplus 服务器已完成响应,开始解析响应
[2025-12-03 10:42:59.162] luat:U(23911):I/user.http_upload_photo_task_func httpplus.request 200
[2025-12-03 10:43:02.049] luat:U(26793):I/user.sys ram 233472 33832 35792
[2025-12-03 10:43:02.049] luat:U(26794):I/user.lua ram 2097144 255232 314400
[2025-12-03 10:43:05.046] luat:U(29795):I/user.sys ram 233472 33832 35792
[2025-12-03 10:43:05.046] luat:U(29796):I/user.lua ram 2097144 255448 314400
[2025-12-03 10:43:08.043] ap1:uvc_stre:W(32678):uvc_camera_device_power_on, port:5, device:0
[2025-12-03 10:43:08.043] ap1:uvc_stre:W(32678):uvc_camera_device_power_on, port:1, device:0, ret:0
[2025-12-03 10:43:08.043] ap1:CHERRY_U:E(32679):!!!config->fps 30
[2025-12-03 10:43:08.043] ap1:CHERRY_U:E(32679):!!!custom fps 15
[2025-12-03 10:43:08.292] luat:U(33054):I/user.初始化状态 true 这是第4个摄像头
[2025-12-03 10:43:08.292] luat:U(33054):I/user.照片存储路径 /ram/test.jpg
[2025-12-03 10:43:08.292] luat:U(33056):I/user.sys ram 233472 35584 35792
[2025-12-03 10:43:08.292] luat:U(33056):I/user.lua ram 2097144 257648 314400
[2025-12-03 10:43:09.301] luat:U(34051):I/user.摄像头数据 19328
[2025-12-03 10:43:09.301] luat:U(34053):I/user.拍照完成
[2025-12-03 10:43:09.301] luat:U(34053):I/user.这是第4个摄像头拍的
[2025-12-03 10:43:09.301] luat:D(34057):socket:connect to upload.air32.cn,80
[2025-12-03 10:43:09.301] luat:D(34057):DNS:upload.air32.cn state 0 id 4 ipv6 0 use dns server0, try 0
[2025-12-03 10:43:09.301] luat:D(34058):net:adatper 2 dns server 223.5.5.5
[2025-12-03 10:43:09.301] luat:D(34058):net:dns udp sendto 223.5.5.5:53 from 192.168.1.118
[2025-12-03 10:43:09.392] luat:I(34126):DNS:dns all done ,now stop
[2025-12-03 10:43:09.392] luat:D(34126):net:adapter 2 connect 49.232.89.122:80 TCP
[2025-12-03 10:43:09.610] luat:U(34348):I/user.httpplus 等待服务器完成响应
[2025-12-03 10:43:10.318] luat:U(35057):I/user.httpplus 等待服务器完成响应
[2025-12-03 10:43:10.318] luat:U(35060):I/user.httpplus 服务器已完成响应,开始解析响应
[2025-12-03 10:43:10.342] luat:U(35070):I/user.http_upload_photo_task_func httpplus.request 200
[2025-12-03 10:43:11.322] luat:U(36058):I/user.sys ram 233472 33832 35792
[2025-12-03 10:43:11.322] luat:U(36059):I/user.lua ram 2097144 282960 314400
[2025-12-03 10:43:14.317] luat:U(39060):I/user.sys ram 233472 33832 35792
[2025-12-03 10:43:14.317] luat:U(39061):I/user.lua ram 2097144 283176 314400
[2025-12-03 10:43:17.329] luat:U(42062):I/user.sys ram 233472 33832 35792
[2025-12-03 10:43:17.329] luat:U(42062):I/user.lua ram 2097144 283384 314400
[2025-12-03 10:43:18.039] ap0:uvc_stre:W(42678):uvc_camera_device_power_on, port:5, device:0
[2025-12-03 10:43:18.039] ap0:uvc_stre:W(42678):uvc_camera_device_power_on, port:1, device:0, ret:0
[2025-12-03 10:43:18.039] ap1:CHERRY_U:E(42679):!!!config->fps 30
[2025-12-03 10:43:18.039] ap1:CHERRY_U:E(42680):!!!custom fps 15
[2025-12-03 10:43:18.318] luat:U(43055):I/user.初始化状态 true 这是第1个摄像头
[2025-12-03 10:43:18.318] luat:U(43056):I/user.照片存储路径 /ram/test.jpg
[2025-12-03 10:43:18.505] luat:U(43251):I/user.摄像头数据 20172
[2025-12-03 10:43:18.505] luat:U(43252):I/user.拍照完成
[2025-12-03 10:43:18.505] luat:U(43253):I/user.这是第1个摄像头拍的
[2025-12-03 10:43:18.518] luat:D(43257):socket:connect to upload.air32.cn,80
[2025-12-03 10:43:18.518] luat:D(43257):DNS:upload.air32.cn state 0 id 5 ipv6 0 use dns server0, try 0
[2025-12-03 10:43:18.518] luat:D(43258):net:adatper 2 dns server 223.5.5.5
[2025-12-03 10:43:18.518] luat:D(43258):net:dns udp sendto 223.5.5.5:53 from 192.168.1.118
[2025-12-03 10:43:18.518] luat:I(43270):DNS:dns all done ,now stop
[2025-12-03 10:43:18.518] luat:D(43270):net:adapter 2 connect 49.232.89.122:80 TCP
[2025-12-03 10:43:18.707] luat:U(43455):I/user.httpplus 等待服务器完成响应
[2025-12-03 10:43:19.440] luat:U(44184):I/user.httpplus 等待服务器完成响应
[2025-12-03 10:43:19.440] luat:U(44187):I/user.httpplus 服务器已完成响应,开始解析响应
[2025-12-03 10:43:19.451] luat:U(44195):I/user.http_upload_photo_task_func httpplus.request 200
[2025-12-03 10:43:20.323] luat:U(45064):I/user.sys ram 233472 33832 35792
[2025-12-03 10:43:20.323] luat:U(45065):I/user.lua ram 2097144 311256 337952
```

5、登录 https://www.air32.cn/upload/data/jpg/ 查看拍摄的照片;

![](https://docs.openluat.com/air8101/luatos/app/accessory/AirCAMERA_1020/image/httpupload.png)

**使用录像功能演示的核心步骤：**

1、搭建硬件环境;

2、修改 netdrv_wifi.lua 中的 WIFI 账号密码; 打开 main.lua文件中 require "video_http_post" 同时注释掉 require "take_photo_http_post"

3、烧录 DEMO 代码; 单路摄像头请将video_http_post.lua中的usb_port_num修改为1; 四路或多路摄像头请将video_http_post.lua中的usb_port_num修改为4或对应的摄像头数量;

4、等待单摄像头自动录像完成后上传平台，LUATOOLS会有如下打印;

```lua
[2026-01-16 17:32:27.006] luat:U(1977):I/user.触发第 1 个摄像头视频录制
[2026-01-16 17:32:27.006] ap1:pm_ap:E(1867):Invalid gpio_id: 255
[2026-01-16 17:32:27.006] ap1:usb_driv:I(1867):USB_DRV_USB_OPEN!
[2026-01-16 17:32:27.006] ap1:uvc_stre:W(1871):uvc_camera_device_power_on, port:5, device:0
[2026-01-16 17:32:27.006] ap1:uvc_stre:W(1871):uvc_camera_device_power_on, port:5, device:0, ret:-17413
[2026-01-16 17:32:27.194] os:I(2170):psram:0x607a0000,size:131072
[2026-01-16 17:32:27.199] luat:U(2194):I/user.摄像头初始化状态 true USB端口: 1
[2026-01-16 17:32:27.199] luat:U(2195):I/user.开始录制视频到 /sd/video_usb1_2.mp4
[2026-01-16 17:32:27.199] luat:U(2196):I/user.excamera.video 开始录制视频到 /sd/video_usb1_2.mp4
[2026-01-16 17:32:27.199] luat:U(2196):I/user.excamera.video lua内存: 2097144 164536 168528
[2026-01-16 17:32:27.199] luat:U(2196):I/user.excamera.video sys内存: 238224 39256 39256
[2026-01-16 17:32:27.199] ap1:CAM:W(2081):拍照/录像到文件录 /sd/video_usb1_2.mp4
[2026-01-16 17:32:27.199] ap1:CAM:W(2081):选定的捕捉模式 4
[2026-01-16 17:32:28.654] wifid:I(3634):[KW:]scanu_start_req:ssid=茶室-降功耗,找合宙!
[2026-01-16 17:32:29.468] luat:I(4441):mp4box:start flush buffer 262144 bytes 0x60a0eb78
[2026-01-16 17:32:30.272] luat:I(5242):mp4box:start flush buffer 262144 bytes 0x60a0eb78
[2026-01-16 17:32:30.365] wifid:I(5339):[KW:]scanu_confirm:status=0,req_type=0,upload_cnt=8,recv_cnt=27,time=1706223us,result=1,rfcli=0
[2026-01-16 17:32:30.365] wpa:I(5340):Scan completed in 1.704000 seconds
[2026-01-16 17:32:30.365] hitf:I(5340):get scan result:1
[2026-01-16 17:32:30.365] wpa:I(5341):State: SCANNING -> ASSOCIATING
[2026-01-16 17:32:30.365] wifid:I(5342):[KW:]conn vif0-0,auth_type:0,bssid:de8c-21f9-aa02,ssid:茶室-降功耗,找合宙!,is encryp:8.
[2026-01-16 17:32:30.365] wifid:I(5343):chan_ctxt_add: CTXT1,freq2452MHz,bw20MHz,pwr30dBm
[2026-01-16 17:32:30.365] wifid:I(5343):chan_reg_fix:VIF0,CTXT1,type3,ctxt_s0,nb_vif0
[2026-01-16 17:32:30.365] wifid:I(5344):mm_sta_add:vif 0,sta 1,status 0
[2026-01-16 17:32:30.585] wifid:I(5553):[KW:]auth_send:seq1, txtype0, auth_type0, seq93
[2026-01-16 17:32:30.585] wifid:I(5559):[KW:]sm_auth_handler: status code 0, tx status 0x80800100
[2026-01-16 17:32:30.585] wifid:I(5559):[KW:]assoc_req_send:is ht, seq_num:94
[2026-01-16 17:32:30.585] wifid:I(5567):[KW:]assoc_rsp:status0,tx_s0x80800000
[2026-01-16 17:32:30.605] wifid:I(5567):[KW:]mm_set_vif_state,vif=0,vif_type=0,is_active=1, aid=0x3,rssi=-45
[2026-01-16 17:32:30.605] wpa:I(5569):State: ASSOCIATING -> ASSOCIATED
[2026-01-16 17:32:30.605] wpa:I(5577):State: ASSOCIATED -> 4WAY_HANDSHAKE
[2026-01-16 17:32:30.605] wpa:I(5577):WPA: TK c5e69b344c8cc0925dd94e492f35f80b
[2026-01-16 17:32:30.605] wpa:I(5586):State: 4WAY_HANDSHAKE -> 4WAY_HANDSHAKE
[2026-01-16 17:32:30.605] hitf:I(5603):add CCMP
[2026-01-16 17:32:30.605] wpa:I(5603):State: 4WAY_HANDSHAKE -> GROUP_HANDSHAKE
[2026-01-16 17:32:30.634] hitf:I(5604):add CCMP
[2026-01-16 17:32:30.634] wpa:I(5604):State: GROUP_HANDSHAKE -> COMPLETED
[2026-01-16 17:32:30.634] lwip:I(5605):sta ip start
[2026-01-16 17:32:30.634] lwip:I(5605):[KW:]sta:DHCP_DISCOVER()
[2026-01-16 17:32:30.634] lwip:I(5622):[KW:]sta:DHCP_OFFER received in DHCP_STATE_SELECTING state
[2026-01-16 17:32:30.634] lwip:I(5622):[KW:]sta:DHCP_REQUEST(netif=0x28065588) en   1
[2026-01-16 17:32:31.056] luat:I(6035):mp4box:start flush buffer 262144 bytes 0x60a0eb78
[2026-01-16 17:32:31.196] lwip:I(6167):[KW:]sta:DHCP_ACK received
[2026-01-16 17:32:31.196] wifid:I(6168):[KW:]me dhcp done vif:0
[2026-01-16 17:32:31.196] event:W(6170):event <2 0> has no cb
[2026-01-16 17:32:31.196] ap1:lwip:I(6056):sta ip start
[2026-01-16 17:32:31.196] luat:D(6173):wlan:event_module 1 event_id 2
[2026-01-16 17:32:31.196] luat:D(6173):wlan:STA connected 茶室-降功耗,找合宙! 
[2026-01-16 17:32:31.196] luat:D(6174):wlan:event_module 2 event_id 0
[2026-01-16 17:32:31.196] luat:D(6174):wlan:ipv4 got!! 192.168.31.234
[2026-01-16 17:32:31.196] luat:D(6174):net:network ready 2, setup dns server
[2026-01-16 17:32:31.276] luat:D(6251):wlan:sta ip 192.168.31.234
[2026-01-16 17:32:31.276] luat:U(6253):I/user.dnsproxy 开始监听
[2026-01-16 17:32:31.276] luat:D(6253):net:设置DNS服务器 id 2 index 0 ip 223.5.5.5
[2026-01-16 17:32:31.276] luat:D(6253):net:设置DNS服务器 id 2 index 1 ip 114.114.114.114
[2026-01-16 17:32:31.276] luat:U(6254):I/user.netdrv_wifi.ip_ready_func IP_READY 192.168.31.234 255.255.255.0 192.168.31.1 nil
[2026-01-16 17:32:31.856] luat:I(6829):mp4box:start flush buffer 262144 bytes 0x60a0eb78
[2026-01-16 17:32:32.187] cal:I(7179):idx:41=41+(0),r:54,xtal:75,pwr_gain:a4ab7131
[2026-01-16 17:32:32.579] luat:I(7557):mp4box:start flush buffer 262144 bytes 0x60a0eb78
[2026-01-16 17:32:33.375] luat:I(8357):mp4box:start flush buffer 262144 bytes 0x60a0eb78
[2026-01-16 17:32:34.302] luat:I(9280):mp4box:start flush buffer 262144 bytes 0x60a0eb78
[2026-01-16 17:32:35.490] luat:I(10467):mp4box:start flush buffer 262144 bytes 0x60a0eb78
[2026-01-16 17:32:36.594] luat:I(11591):mp4box:start flush buffer 262144 bytes 0x60a0eb78
[2026-01-16 17:32:37.003] luat:U(11977):I/user.系统内存使用情况 238224 128312 128760
[2026-01-16 17:32:37.003] luat:U(11978):I/user.Lua虚拟机内存使用情况 2097144 165736 168528
[2026-01-16 17:32:37.287] luat:I(12260):mp4box:start flush buffer 262144 bytes 0x60a0eb78
[2026-01-16 17:32:37.943] luat:I(12924):mp4box:start flush buffer 262144 bytes 0x60a0eb78
[2026-01-16 17:32:38.349] luat:I(13330):mp4box:start flush buffer 262144 bytes 0x60a0eb78
[2026-01-16 17:32:38.879] luat:I(13852):mp4box:start flush buffer 262144 bytes 0x60a0eb78
[2026-01-16 17:32:39.528] luat:I(14517):mp4box:start flush buffer 262144 bytes 0x60a0eb78
[2026-01-16 17:32:40.000] luat:I(14983):mp4box:start flush buffer 262144 bytes 0x60a0eb78
[2026-01-16 17:32:40.408] luat:I(15379):mp4box:start flush buffer 262144 bytes 0x60a0eb78
[2026-01-16 17:32:40.936] luat:I(15910):mp4box:start flush buffer 262144 bytes 0x60a0eb78
[2026-01-16 17:32:41.264] luat:I(16237):mp4box:start flush buffer 262144 bytes 0x60a0eb78
[2026-01-16 17:32:41.659] luat:I(16637):mp4box:start flush buffer 262144 bytes 0x60a0eb78
[2026-01-16 17:32:42.050] luat:I(17029):mp4box:start flush buffer 262144 bytes 0x60a0eb78
[2026-01-16 17:32:42.382] luat:I(17365):mp4box:start flush buffer 262144 bytes 0x60a0eb78
[2026-01-16 17:32:42.791] luat:I(17764):mp4box:start flush buffer 262144 bytes 0x60a0eb78
[2026-01-16 17:32:43.183] luat:I(18163):mp4box:start flush buffer 262144 bytes 0x60a0eb78
[2026-01-16 17:32:43.649] luat:I(18624):mp4box:start flush buffer 262144 bytes 0x60a0eb78
[2026-01-16 17:32:43.981] luat:I(18951):mp4box:start flush buffer 262144 bytes 0x60a0eb78
[2026-01-16 17:32:44.451] luat:I(19420):mp4box:start flush buffer 262144 bytes 0x60a0eb78
[2026-01-16 17:32:44.971] luat:I(19948):mp4box:start flush buffer 262144 bytes 0x60a0eb78
[2026-01-16 17:32:46.020] luat:I(21004):mp4box:start flush buffer 262144 bytes 0x60a0eb78
[2026-01-16 17:32:47.003] luat:U(21979):I/user.系统内存使用情况 238224 128360 128760
[2026-01-16 17:32:47.003] luat:U(21980):I/user.Lua虚拟机内存使用情况 2097144 166032 168528
[2026-01-16 17:32:47.014] luat:I(21996):mp4box:start flush buffer 262144 bytes 0x60a0eb78
[2026-01-16 17:32:48.084] luat:I(23062):mp4box:start flush buffer 262144 bytes 0x60a0eb78
[2026-01-16 17:32:49.185] luat:I(24183):mp4box:start flush buffer 262144 bytes 0x60a0eb78
[2026-01-16 17:32:50.271] luat:I(25239):mp4box:start flush buffer 262144 bytes 0x60a0eb78
[2026-01-16 17:32:51.322] luat:I(26306):mp4box:start flush buffer 262144 bytes 0x60a0eb78
[2026-01-16 17:32:52.395] luat:I(27366):mp4box:start flush buffer 262144 bytes 0x60a0eb78
[2026-01-16 17:32:53.583] luat:I(28553):mp4box:start flush buffer 262144 bytes 0x60a0eb78
[2026-01-16 17:32:54.638] luat:I(29620):mp4box:start flush buffer 262144 bytes 0x60a0eb78
[2026-01-16 17:32:55.769] luat:I(30741):mp4box:start flush buffer 262144 bytes 0x60a0eb78
[2026-01-16 17:32:56.836] luat:I(31807):mp4box:start flush buffer 262144 bytes 0x60a0eb78
[2026-01-16 17:32:57.008] luat:U(31981):I/user.系统内存使用情况 238224 128360 128760
[2026-01-16 17:32:57.008] luat:U(31982):I/user.Lua虚拟机内存使用情况 2097144 166264 168528
[2026-01-16 17:32:57.245] luat:I(32241):mp4box:start flush buffer 102901 bytes 0x60a0eb78
[2026-01-16 17:32:57.292] luat:I(32267):mp4box:mp4 file size before mdat 10326517
[2026-01-16 17:32:57.298] luat:I(32291):mp4box:总帧数 445, 关键帧数 4 总耗时 29406ms 平均帧率 15 fps
[2026-01-16 17:32:57.298] luat:I(32291):mp4box:mp4 file final size 10332500
[2026-01-16 17:32:57.311] luat:I(32300):mp4box:mp4 file closed, box write finished, file closed
[2026-01-16 17:32:57.311] luat:U(32301):I/user.excamera.video lua内存: 2097144 166480 168528
[2026-01-16 17:32:57.311] luat:U(32302):I/user.excamera.video sys内存: 238224 122120 128760
[2026-01-16 17:32:57.311] luat:U(32302):I/user.excamera.video 视频录制完成 /sd/video_usb1_2.mp4
[2026-01-16 17:32:57.435] luat:U(32412):I/user.视频录制成功!
[2026-01-16 17:32:57.441] luat:D(32420):socket:connect to upload.air32.cn,80
[2026-01-16 17:32:57.441] luat:D(32420):DNS:upload.air32.cn state 0 id 1 ipv6 0 use dns server0, try 0
[2026-01-16 17:32:57.441] luat:D(32420):net:adatper 2 dns server 223.5.5.5
[2026-01-16 17:32:57.441] luat:D(32421):net:dns udp sendto 223.5.5.5:53 from 192.168.31.234
[2026-01-16 17:32:57.622] luat:I(32603):DNS:dns all done ,now stop
[2026-01-16 17:32:57.622] luat:D(32603):net:adapter 2 connect 49.232.89.122:80 TCP
[2026-01-16 17:32:57.748] luat:I(32740):zbuff:create large size: 128 kbyte, trigger force GC
[2026-01-16 17:33:07.009] luat:U(41983):I/user.系统内存使用情况 238224 120472 128760
[2026-01-16 17:33:07.009] luat:U(41984):I/user.Lua虚拟机内存使用情况 2097144 172288 172288
[2026-01-16 17:33:17.131] luat:U(52129):I/user.系统内存使用情况 238224 120472 128760
[2026-01-16 17:33:17.131] luat:U(52130):I/user.Lua虚拟机内存使用情况 2097144 180488 180488
[2026-01-16 17:33:27.258] luat:U(62235):I/user.系统内存使用情况 238224 120472 128760
[2026-01-16 17:33:27.258] luat:U(62236):I/user.Lua虚拟机内存使用情况 2097144 188048 188048
[2026-01-16 17:33:37.584] luat:U(72557):I/user.系统内存使用情况 238224 120472 128760
[2026-01-16 17:33:37.584] luat:U(72558):I/user.Lua虚拟机内存使用情况 2097144 196152 196152
[2026-01-16 17:33:47.570] luat:U(82558):I/user.系统内存使用情况 238224 120472 128760
[2026-01-16 17:33:47.570] luat:U(82559):I/user.Lua虚拟机内存使用情况 2097144 203728 203728
[2026-01-16 17:33:53.080] luat:U(88049):I/user.httpplus 等待服务器完成响应
[2026-01-16 17:33:53.224] luat:U(88193):I/user.httpplus 服务器已完成响应,开始解析响应
[2026-01-16 17:33:53.224] luat:U(88202):I/user.http上传完成，状态码: 200
[2026-01-16 17:33:53.224] luat:U(88203):I/user.上传成功


```

等待4路摄像头自动轮切录像完成后上传平台，LUATOOLS会有如下打印；

```lua
[2026-01-16 17:11:28.263] luat:U(1974):I/user.触发第 1 个摄像头视频录制
[2026-01-16 17:11:28.263] ap1:pm_ap:E(1863):Invalid gpio_id: 255
[2026-01-16 17:11:28.263] ap1:usb_driv:I(1863):USB_DRV_USB_OPEN!
[2026-01-16 17:11:28.263] ap1:uvc_stre:W(1867):uvc_camera_device_power_on, port:5, device:0
[2026-01-16 17:11:28.263] ap1:uvc_stre:W(1867):uvc_camera_device_power_on, port:5, device:0, ret:-17413
[2026-01-16 17:11:28.387] os:I(2101):psram:0x607a0000,size:131072
[2026-01-16 17:11:28.987] luat:U(2706):I/user.摄像头初始化状态 true USB端口: 1
[2026-01-16 17:11:28.987] luat:U(2707):I/user.开始录制视频到 /sd/video_usb1_2.mp4
[2026-01-16 17:11:28.987] luat:U(2707):I/user.excamera.video 开始录制视频到 /sd/video_usb1_2.mp4
[2026-01-16 17:11:28.987] luat:U(2708):I/user.excamera.video lua内存: 2097144 164536 168528
[2026-01-16 17:11:28.987] luat:U(2708):I/user.excamera.video sys内存: 238224 39256 39256
[2026-01-16 17:11:28.987] ap1:CAM:W(2592):拍照/录像到文件录 /sd/video_usb1_2.mp4
[2026-01-16 17:11:28.987] ap1:CAM:W(2592):选定的捕捉模式 4
[2026-01-16 17:11:29.332] wifid:I(3036):[KW:]conn vif0-0,auth_type:3,bssid:de8c-21f9-aa02,ssid:茶室-降功耗,找合宙!,is encryp:8.
[2026-01-16 17:11:30.417] luat:D(4139):wlan:STA connected 茶室-降功耗,找合宙! 
[2026-01-16 17:11:30.417] luat:D(4139):wlan:event_module 2 event_id 0
[2026-01-16 17:11:30.417] luat:D(4139):wlan:ipv4 got!! 192.168.31.234
[2026-01-16 17:11:30.417] luat:D(4140):net:network ready 2, setup dns server
[2026-01-16 17:11:30.417] luat:D(4150):wlan:sta ip 192.168.31.234
[2026-01-16 17:11:30.417] luat:U(4151):I/user.dnsproxy 开始监听
[2026-01-16 17:11:30.417] luat:D(4152):net:设置DNS服务器 id 2 index 0 ip 223.5.5.5
[2026-01-16 17:11:30.417] luat:D(4152):net:设置DNS服务器 id 2 index 1 ip 114.114.114.114
[2026-01-16 17:11:30.417] luat:U(4153):I/user.netdrv_wifi.ip_ready_func IP_READY 192.168.31.234 255.255.255.0 192.168.31.1 nil
[2026-01-16 17:11:31.310] luat:I(5032):mp4box:start flush buffer 262144 bytes 0x60a0f4e0
[2026-01-16 17:11:32.455] luat:I(6168):mp4box:start flush buffer 262144 bytes 0x60a0f4e0
[2026-01-16 17:11:33.523] luat:I(7232):mp4box:start flush buffer 262144 bytes 0x60a0f4e0
[2026-01-16 17:11:34.653] luat:I(8366):mp4box:start flush buffer 262144 bytes 0x60a0f4e0
[2026-01-16 17:11:35.712] luat:I(9430):mp4box:start flush buffer 262144 bytes 0x60a0f4e0
[2026-01-16 17:11:36.858] luat:I(10565):mp4box:start flush buffer 262144 bytes 0x60a0f4e0
[2026-01-16 17:11:37.850] luat:I(11567):mp4box:start flush buffer 262144 bytes 0x60a0f4e0
[2026-01-16 17:11:38.256] luat:U(11973):I/user.系统内存使用情况 238224 128776 129256
[2026-01-16 17:11:38.256] luat:U(11974):I/user.Lua虚拟机内存使用情况 2097144 165736 168528
[2026-01-16 17:11:38.976] luat:I(12698):mp4box:start flush buffer 262144 bytes 0x60a0f4e0
[2026-01-16 17:11:40.111] luat:I(13832):mp4box:start flush buffer 262144 bytes 0x60a0f4e0
[2026-01-16 17:11:41.182] luat:I(14897):mp4box:start flush buffer 262144 bytes 0x60a0f4e0
[2026-01-16 17:11:42.252] luat:I(15963):mp4box:start flush buffer 262144 bytes 0x60a0f4e0
[2026-01-16 17:11:43.387] luat:I(17099):mp4box:start flush buffer 262144 bytes 0x60a0f4e0
[2026-01-16 17:11:44.447] luat:I(18164):mp4box:start flush buffer 262144 bytes 0x60a0f4e0
[2026-01-16 17:11:45.589] luat:I(19299):mp4box:start flush buffer 262144 bytes 0x60a0f4e0
[2026-01-16 17:11:46.653] luat:I(20363):mp4box:start flush buffer 262144 bytes 0x60a0f4e0
[2026-01-16 17:11:47.758] luat:I(21494):mp4box:start flush buffer 262144 bytes 0x60a0f4e0
[2026-01-16 17:11:48.263] luat:U(21974):I/user.系统内存使用情况 238224 128776 129256
[2026-01-16 17:11:48.263] luat:U(21975):I/user.Lua虚拟机内存使用情况 2097144 166000 168528
[2026-01-16 17:11:48.829] luat:I(22566):mp4box:start flush buffer 262144 bytes 0x60a0f4e0
[2026-01-16 17:11:49.984] luat:I(23699):mp4box:start flush buffer 262144 bytes 0x60a0f4e0
[2026-01-16 17:11:50.599] cal:I(24315):idx:41=41+(0),r:54,xtal:75,pwr_gain:a4ab7131
[2026-01-16 17:11:51.045] luat:I(24762):mp4box:start flush buffer 262144 bytes 0x60a0f4e0
[2026-01-16 17:11:52.103] luat:I(25827):mp4box:start flush buffer 262144 bytes 0x60a0f4e0
[2026-01-16 17:11:53.250] luat:I(26963):mp4box:start flush buffer 262144 bytes 0x60a0f4e0
[2026-01-16 17:11:54.310] luat:I(28029):mp4box:start flush buffer 262144 bytes 0x60a0f4e0
[2026-01-16 17:11:55.374] luat:I(29096):mp4box:start flush buffer 262144 bytes 0x60a0f4e0
[2026-01-16 17:11:56.511] luat:I(30231):mp4box:start flush buffer 262144 bytes 0x60a0f4e0
[2026-01-16 17:11:57.587] luat:I(31298):mp4box:start flush buffer 262144 bytes 0x60a0f4e0
[2026-01-16 17:11:58.245] luat:U(31976):I/user.系统内存使用情况 238224 128824 129256
[2026-01-16 17:11:58.245] luat:U(31977):I/user.Lua虚拟机内存使用情况 2097144 166264 168528
[2026-01-16 17:11:58.718] luat:I(32431):mp4box:start flush buffer 262144 bytes 0x60a0f4e0
[2026-01-16 17:11:59.004] luat:I(32717):mp4box:start flush buffer 75336 bytes 0x60a0f4e0
[2026-01-16 17:11:59.012] luat:I(32736):mp4box:mp4 file size before mdat 7153224
[2026-01-16 17:11:59.052] luat:I(32763):mp4box:总帧数 448, 关键帧数 4 总耗时 29783ms 平均帧率 15 fps
[2026-01-16 17:11:59.052] luat:I(32763):mp4box:mp4 file final size 7159243
[2026-01-16 17:11:59.052] luat:I(32773):mp4box:mp4 file closed, box write finished, file closed
[2026-01-16 17:11:59.052] luat:U(32774):I/user.excamera.video lua内存: 2097144 166480 168528
[2026-01-16 17:11:59.052] luat:U(32774):I/user.excamera.video sys内存: 238224 122584 129256
[2026-01-16 17:11:59.052] luat:U(32774):I/user.excamera.video 视频录制完成 /sd/video_usb1_2.mp4
[2026-01-16 17:11:59.162] luat:U(32885):I/user.视频录制成功!
[2026-01-16 17:11:59.169] luat:D(32893):socket:connect to upload.air32.cn,80
[2026-01-16 17:11:59.169] luat:D(32893):DNS:upload.air32.cn state 0 id 1 ipv6 0 use dns server0, try 0
[2026-01-16 17:11:59.169] luat:D(32893):net:adatper 2 dns server 223.5.5.5
[2026-01-16 17:11:59.169] luat:D(32893):net:dns udp sendto 223.5.5.5:53 from 192.168.31.234
[2026-01-16 17:11:59.209] luat:I(32933):DNS:dns all done ,now stop
[2026-01-16 17:11:59.209] luat:D(32934):net:adapter 2 connect 49.232.89.122:80 TCP
[2026-01-16 17:11:59.258] luat:I(32970):zbuff:create large size: 128 kbyte, trigger force GC
[2026-01-16 17:12:08.363] luat:U(42080):I/user.系统内存使用情况 238224 120936 129256
[2026-01-16 17:12:08.363] luat:U(42081):I/user.Lua虚拟机内存使用情况 2097144 172544 172544
[2026-01-16 17:12:18.361] luat:U(52081):I/user.系统内存使用情况 238224 120936 129256
[2026-01-16 17:12:18.361] luat:U(52082):I/user.Lua虚拟机内存使用情况 2097144 179696 179696
[2026-01-16 17:12:28.362] luat:U(62082):I/user.系统内存使用情况 238224 120936 129256
[2026-01-16 17:12:28.362] luat:U(62083):I/user.Lua虚拟机内存使用情况 2097144 186744 186744
[2026-01-16 17:12:38.719] luat:U(72443):I/user.系统内存使用情况 238224 120936 129256
[2026-01-16 17:12:38.719] luat:U(72444):I/user.Lua虚拟机内存使用情况 2097144 194312 194312
[2026-01-16 17:12:40.304] luat:U(74034):I/user.httpplus 等待服务器完成响应
[2026-01-16 17:12:40.335] luat:U(74066):I/user.httpplus 服务器已完成响应,开始解析响应
[2026-01-16 17:12:40.340] luat:U(74075):I/user.http上传完成，状态码: 200
[2026-01-16 17:12:40.340] luat:U(74076):I/user.上传成功
[2026-01-16 17:12:40.340] luat:U(74077):I/user.触发第 2 个摄像头视频录制
[2026-01-16 17:12:40.340] ap1:uvc_stre:W(73963):uvc_camera_device_power_on, port:5, device:0
[2026-01-16 17:12:40.340] ap1:uvc_stre:W(73964):uvc_camera_device_power_on, port:1, device:0, ret:0
[2026-01-16 17:12:40.360] luat:U(74091):I/user.摄像头初始化状态 true USB端口: 2
[2026-01-16 17:12:40.360] luat:U(74092):I/user.开始录制视频到 /sd/video_usb2_74.mp4
[2026-01-16 17:12:40.360] luat:U(74092):I/user.excamera.video 开始录制视频到 /sd/video_usb2_74.mp4
[2026-01-16 17:12:40.360] luat:U(74092):I/user.excamera.video lua内存: 2097144 201224 201640
[2026-01-16 17:12:40.360] luat:U(74093):I/user.excamera.video sys内存: 238224 122480 129256
[2026-01-16 17:12:40.360] ap1:CAM:W(73978):拍照/录像到文件录 /sd/video_usb2_74.mp4
[2026-01-16 17:12:40.360] ap1:CAM:W(73978):选定的捕捉模式 4
[2026-01-16 17:12:40.660] cal:I(74379):idx:41=41+(0),r:54,xtal:75,pwr_gain:a4ab7131
[2026-01-16 17:12:41.536] luat:I(75274):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:12:42.151] luat:I(75874):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:12:42.737] luat:I(76467):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:12:43.335] luat:I(77060):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:12:43.935] luat:I(77664):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:12:44.530] luat:I(78257):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:12:45.125] luat:I(78851):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:12:45.726] luat:I(79453):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:12:46.262] luat:I(79983):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:12:46.858] luat:I(80577):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:12:47.438] luat:I(81170):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:12:48.046] luat:I(81773):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:12:48.639] luat:I(82365):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:12:48.718] luat:U(82445):I/user.系统内存使用情况 238224 128824 129256
[2026-01-16 17:12:48.718] luat:U(82446):I/user.Lua虚拟机内存使用情况 2097144 201696 201696
[2026-01-16 17:12:49.240] luat:I(82964):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:12:50.294] luat:I(84017):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:12:51.425] luat:I(85147):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:12:52.477] luat:I(86203):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:12:53.541] luat:I(87270):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:12:54.669] luat:I(88390):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:12:55.735] luat:I(89455):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:12:56.841] luat:I(90574):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:12:57.837] luat:I(91576):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:12:58.715] luat:U(92447):I/user.系统内存使用情况 238224 128824 129256
[2026-01-16 17:12:58.715] luat:U(92448):I/user.Lua虚拟机内存使用情况 2097144 201912 201912
[2026-01-16 17:12:59.105] luat:I(92829):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:13:00.162] luat:I(93895):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:13:01.231] luat:I(94950):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:13:02.338] luat:I(96079):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:13:03.417] luat:I(97137):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:13:04.513] luat:I(98257):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:13:05.602] luat:I(99324):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:13:06.784] luat:I(100514):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:13:07.848] luat:I(101569):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:13:08.730] luat:U(102449):I/user.系统内存使用情况 238224 128776 129256
[2026-01-16 17:13:08.730] luat:U(102450):I/user.Lua虚拟机内存使用情况 2097144 202152 202152
[2026-01-16 17:13:08.907] luat:I(102635):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:13:10.043] luat:I(103764):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:13:10.439] luat:I(104160):mp4box:start flush buffer 91402 bytes 0x60a56f68
[2026-01-16 17:13:10.442] luat:I(104183):mp4box:mp4 file size before mdat 8742154
[2026-01-16 17:13:10.471] luat:I(104203):mp4box:总帧数 446, 关键帧数 4 总耗时 29472ms 平均帧率 15 fps
[2026-01-16 17:13:10.471] luat:I(104203):mp4box:mp4 file final size 8748149
[2026-01-16 17:13:10.481] luat:I(104213):mp4box:mp4 file closed, box write finished, file closed
[2026-01-16 17:13:10.481] luat:U(104214):I/user.excamera.video lua内存: 2097144 202360 202360
[2026-01-16 17:13:10.481] luat:U(104214):I/user.excamera.video sys内存: 238224 122584 129256
[2026-01-16 17:13:10.481] luat:U(104215):I/user.excamera.video 视频录制完成 /sd/video_usb2_74.mp4
[2026-01-16 17:13:10.598] luat:U(104325):I/user.视频录制成功!
[2026-01-16 17:13:10.606] luat:D(104337):socket:connect to upload.air32.cn,80
[2026-01-16 17:13:10.606] luat:D(104337):DNS:upload.air32.cn state 0 id 2 ipv6 0 use dns server0, try 0
[2026-01-16 17:13:10.606] luat:D(104337):net:adatper 2 dns server 223.5.5.5
[2026-01-16 17:13:10.606] luat:D(104337):net:dns udp sendto 223.5.5.5:53 from 192.168.31.234
[2026-01-16 17:13:10.606] luat:I(104356):DNS:dns all done ,now stop
[2026-01-16 17:13:10.606] luat:D(104357):net:adapter 2 connect 49.232.89.122:80 TCP
[2026-01-16 17:13:10.662] luat:I(104395):zbuff:create large size: 128 kbyte, trigger force GC
[2026-01-16 17:13:18.864] luat:U(112585):I/user.系统内存使用情况 238224 120936 129256
[2026-01-16 17:13:18.864] luat:U(112586):I/user.Lua虚拟机内存使用情况 2097144 172072 206128
[2026-01-16 17:13:29.098] luat:U(122835):I/user.系统内存使用情况 238224 120936 129256
[2026-01-16 17:13:29.098] luat:U(122835):I/user.Lua虚拟机内存使用情况 2097144 179816 206128
[2026-01-16 17:13:39.453] luat:U(133189):I/user.系统内存使用情况 238224 120936 129256
[2026-01-16 17:13:39.453] luat:U(133189):I/user.Lua虚拟机内存使用情况 2097144 187400 206128
[2026-01-16 17:13:40.682] cal:I(134421):idx:41=41+(0),r:54,xtal:75,pwr_gain:a4ab7131
[2026-01-16 17:13:49.449] luat:U(143190):I/user.系统内存使用情况 238224 120936 129256
[2026-01-16 17:13:49.449] luat:U(143190):I/user.Lua虚拟机内存使用情况 2097144 194448 206128
[2026-01-16 17:13:59.460] luat:U(153191):I/user.系统内存使用情况 238224 120936 129256
[2026-01-16 17:13:59.460] luat:U(153192):I/user.Lua虚拟机内存使用情况 2097144 202024 206128
[2026-01-16 17:13:59.589] luat:U(153347):I/user.httpplus 等待服务器完成响应
[2026-01-16 17:13:59.635] luat:U(153375):I/user.httpplus 服务器已完成响应,开始解析响应
[2026-01-16 17:13:59.641] luat:U(153385):I/user.http上传完成，状态码: 200
[2026-01-16 17:13:59.641] luat:U(153385):I/user.上传成功
[2026-01-16 17:13:59.641] luat:U(153386):I/user.触发第 3 个摄像头视频录制
[2026-01-16 17:13:59.641] ap1:uvc_stre:W(153273):uvc_camera_device_power_on, port:5, device:0
[2026-01-16 17:13:59.641] ap1:uvc_stre:W(153273):uvc_camera_device_power_on, port:1, device:0, ret:0
[2026-01-16 17:13:59.641] luat:U(153400):I/user.摄像头初始化状态 true USB端口: 3
[2026-01-16 17:13:59.641] luat:U(153401):I/user.开始录制视频到 /sd/video_usb3_153.mp4
[2026-01-16 17:13:59.668] luat:U(153401):I/user.excamera.video 开始录制视频到 /sd/video_usb3_153.mp4
[2026-01-16 17:13:59.668] luat:U(153401):I/user.excamera.video lua内存: 2097144 207880 208296
[2026-01-16 17:13:59.668] luat:U(153402):I/user.excamera.video sys内存: 238224 122480 129256
[2026-01-16 17:13:59.668] ap1:CAM:W(153287):拍照/录像到文件录 /sd/video_usb3_153.mp4
[2026-01-16 17:13:59.668] ap1:CAM:W(153287):选定的捕捉模式 4
[2026-01-16 17:14:00.901] luat:I(154652):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:14:01.517] luat:I(155247):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:14:02.102] luat:I(155840):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:14:02.707] luat:I(156444):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:14:03.299] luat:I(157037):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:14:03.894] luat:I(157631):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:14:04.491] luat:I(158224):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:14:05.092] luat:I(158827):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:14:05.678] luat:I(159420):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:14:06.282] luat:I(160013):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:14:06.879] luat:I(160616):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:14:07.538] luat:I(161279):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:14:08.136] luat:I(161873):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:14:08.735] luat:I(162467):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:14:09.456] luat:U(163192):I/user.系统内存使用情况 238224 128824 129256
[2026-01-16 17:14:09.456] luat:U(163194):I/user.Lua虚拟机内存使用情况 2097144 208360 208360
[2026-01-16 17:14:09.852] luat:I(163597):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:14:10.978] luat:I(164720):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:14:12.107] luat:I(165846):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:14:13.208] luat:I(166967):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:14:14.291] luat:I(168034):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:14:15.354] luat:I(169093):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:14:16.487] luat:I(170222):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:14:17.538] luat:I(171280):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:14:18.641] luat:I(172402):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:14:19.447] luat:U(173195):I/user.系统内存使用情况 238224 128776 129256
[2026-01-16 17:14:19.447] luat:U(173195):I/user.Lua虚拟机内存使用情况 2097144 208592 208592
[2026-01-16 17:14:19.780] luat:I(173536):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:14:20.849] luat:I(174594):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:14:21.976] luat:I(175716):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:14:23.033] luat:I(176774):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:14:24.097] luat:I(177843):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:14:25.212] luat:I(178962):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:14:26.281] luat:I(180023):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:14:27.414] luat:I(181155):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:14:28.511] luat:I(182276):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:14:29.451] luat:U(183196):I/user.系统内存使用情况 238224 128824 129256
[2026-01-16 17:14:29.451] luat:U(183197):I/user.Lua虚拟机内存使用情况 2097144 208800 208800
[2026-01-16 17:14:29.592] luat:I(183335):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:14:29.702] luat:I(183469):mp4box:start flush buffer 18964 bytes 0x60a56f68
[2026-01-16 17:14:29.707] luat:I(183474):mp4box:mp4 file size before mdat 8669716
[2026-01-16 17:14:29.765] luat:I(183501):mp4box:总帧数 444, 关键帧数 4 总耗时 29486ms 平均帧率 15 fps
[2026-01-16 17:14:29.765] luat:I(183501):mp4box:mp4 file final size 8675687
[2026-01-16 17:14:29.765] luat:I(183511):mp4box:mp4 file closed, box write finished, file closed
[2026-01-16 17:14:29.765] luat:U(183512):I/user.excamera.video lua内存: 2097144 209008 209008
[2026-01-16 17:14:29.765] luat:U(183512):I/user.excamera.video sys内存: 238224 122584 129256
[2026-01-16 17:14:29.765] luat:U(183512):I/user.excamera.video 视频录制完成 /sd/video_usb3_153.mp4
[2026-01-16 17:14:29.874] luat:U(183623):I/user.视频录制成功!
[2026-01-16 17:14:29.879] luat:D(183635):socket:connect to upload.air32.cn,80
[2026-01-16 17:14:29.879] luat:D(183635):DNS:upload.air32.cn state 0 id 3 ipv6 0 use dns server0, try 0
[2026-01-16 17:14:29.879] luat:D(183635):net:adatper 2 dns server 223.5.5.5
[2026-01-16 17:14:29.879] luat:D(183635):net:dns udp sendto 223.5.5.5:53 from 192.168.31.234
[2026-01-16 17:14:29.897] luat:I(183657):DNS:dns all done ,now stop
[2026-01-16 17:14:29.897] luat:D(183658):net:adapter 2 connect 49.232.89.122:80 TCP
[2026-01-16 17:14:30.064] luat:I(183801):zbuff:create large size: 128 kbyte, trigger force GC
[2026-01-16 17:14:39.428] luat:U(193198):I/user.系统内存使用情况 238224 120936 129256
[2026-01-16 17:14:39.428] luat:U(193199):I/user.Lua虚拟机内存使用情况 2097144 173120 212768
[2026-01-16 17:14:49.447] luat:U(203199):I/user.系统内存使用情况 238224 120936 129256
[2026-01-16 17:14:49.447] luat:U(203200):I/user.Lua虚拟机内存使用情况 2097144 180856 212768
[2026-01-16 17:14:59.446] luat:U(213200):I/user.系统内存使用情况 238224 120936 129256
[2026-01-16 17:14:59.446] luat:U(213201):I/user.Lua虚拟机内存使用情况 2097144 187904 212768
[2026-01-16 17:15:09.445] luat:U(223201):I/user.系统内存使用情况 238224 120936 129256
[2026-01-16 17:15:09.445] luat:U(223201):I/user.Lua虚拟机内存使用情况 2097144 194952 212768
[2026-01-16 17:15:10.714] cal:I(224471):idx:41=41+(0),r:54,xtal:75,pwr_gain:a4ab7131
[2026-01-16 17:15:19.424] luat:U(233202):I/user.系统内存使用情况 238224 120936 129256
[2026-01-16 17:15:19.424] luat:U(233203):I/user.Lua虚拟机内存使用情况 2097144 201992 212768
[2026-01-16 17:15:19.610] luat:U(233370):I/user.httpplus 等待服务器完成响应
[2026-01-16 17:15:19.610] luat:U(233372):I/user.httpplus 服务器已完成响应,开始解析响应
[2026-01-16 17:15:19.618] luat:U(233381):I/user.http上传完成，状态码: 200
[2026-01-16 17:15:19.618] luat:U(233382):I/user.上传成功
[2026-01-16 17:15:19.618] luat:U(233383):I/user.触发第 4 个摄像头视频录制
[2026-01-16 17:15:19.618] ap1:uvc_stre:W(233269):uvc_camera_device_power_on, port:5, device:0
[2026-01-16 17:15:19.618] ap1:uvc_stre:W(233269):uvc_camera_device_power_on, port:1, device:0, ret:0
[2026-01-16 17:15:19.618] luat:U(233397):I/user.摄像头初始化状态 true USB端口: 4
[2026-01-16 17:15:19.618] luat:U(233397):I/user.开始录制视频到 /sd/video_usb4_233.mp4
[2026-01-16 17:15:19.618] luat:U(233398):I/user.excamera.video 开始录制视频到 /sd/video_usb4_233.mp4
[2026-01-16 17:15:19.650] luat:U(233398):I/user.excamera.video lua内存: 2097144 207824 212768
[2026-01-16 17:15:19.650] luat:U(233398):I/user.excamera.video sys内存: 238224 122480 129256
[2026-01-16 17:15:19.650] ap1:CAM:W(233284):拍照/录像到文件录 /sd/video_usb4_233.mp4
[2026-01-16 17:15:19.650] ap1:CAM:W(233284):选定的捕捉模式 4
[2026-01-16 17:15:20.956] luat:I(234715):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:15:21.681] luat:I(235442):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:15:22.408] luat:I(236171):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:15:23.066] luat:I(236828):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:15:23.806] luat:I(237565):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:15:24.528] luat:I(238285):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:15:25.251] luat:I(239014):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:15:25.910] luat:I(239680):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:15:26.646] luat:I(240409):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:15:27.379] luat:I(241138):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:15:28.116] luat:I(241866):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:15:28.840] luat:I(242596):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:15:29.452] luat:U(243203):I/user.系统内存使用情况 238224 128824 129256
[2026-01-16 17:15:29.452] luat:U(243204):I/user.Lua虚拟机内存使用情况 2097144 208264 212768
[2026-01-16 17:15:29.971] luat:I(243720):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:15:31.021] luat:I(244782):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:15:32.154] luat:I(245906):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:15:33.193] luat:I(246968):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:15:34.327] luat:I(248090):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:15:35.388] luat:I(249152):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:15:36.516] luat:I(250276):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:15:37.581] luat:I(251339):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:15:38.648] luat:I(252400):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:15:39.446] luat:U(253205):I/user.系统内存使用情况 238224 128776 129256
[2026-01-16 17:15:39.446] luat:U(253206):I/user.Lua虚拟机内存使用情况 2097144 208512 212768
[2026-01-16 17:15:39.761] luat:I(253525):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:15:40.820] luat:I(254587):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:15:41.953] luat:I(255709):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:15:43.014] luat:I(256772):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:15:44.077] luat:I(257834):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:15:45.177] luat:I(258958):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:15:46.263] luat:I(260019):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:15:47.316] luat:I(261082):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:15:48.445] luat:I(262207):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:15:49.437] luat:U(263207):I/user.系统内存使用情况 238224 128776 129256
[2026-01-16 17:15:49.437] luat:U(263208):I/user.Lua虚拟机内存使用情况 2097144 208712 212768
[2026-01-16 17:15:49.501] luat:I(263267):mp4box:start flush buffer 262144 bytes 0x60a56f68
[2026-01-16 17:15:49.708] luat:I(263465):mp4box:start flush buffer 36586 bytes 0x60a56f68
[2026-01-16 17:15:49.708] luat:I(263475):mp4box:mp4 file size before mdat 8163050
[2026-01-16 17:15:49.717] luat:I(263501):mp4box:总帧数 446, 关键帧数 4 总耗时 29482ms 平均帧率 15 fps
[2026-01-16 17:15:49.717] luat:I(263502):mp4box:mp4 file final size 8169045
[2026-01-16 17:15:49.726] luat:I(263511):mp4box:mp4 file closed, box write finished, file closed
[2026-01-16 17:15:49.726] luat:U(263512):I/user.excamera.video lua内存: 2097144 208920 212768
[2026-01-16 17:15:49.726] luat:U(263512):I/user.excamera.video sys内存: 238224 122584 129256
[2026-01-16 17:15:49.737] luat:U(263512):I/user.excamera.video 视频录制完成 /sd/video_usb4_233.mp4
[2026-01-16 17:15:49.850] luat:U(263623):I/user.视频录制成功!
[2026-01-16 17:15:49.850] luat:D(263635):socket:connect to upload.air32.cn,80
[2026-01-16 17:15:49.850] luat:D(263635):DNS:upload.air32.cn state 0 id 4 ipv6 0 use dns server0, try 0
[2026-01-16 17:15:49.850] luat:D(263635):net:adatper 2 dns server 223.5.5.5
[2026-01-16 17:15:49.850] luat:D(263635):net:dns udp sendto 223.5.5.5:53 from 192.168.31.234
[2026-01-16 17:15:49.897] luat:I(263657):DNS:dns all done ,now stop
[2026-01-16 17:15:49.897] luat:D(263658):net:adapter 2 connect 49.232.89.122:80 TCP
[2026-01-16 17:15:49.927] luat:I(263695):zbuff:create large size: 128 kbyte, trigger force GC
[2026-01-16 17:15:59.639] luat:U(273401):I/user.系统内存使用情况 238224 120936 129256
[2026-01-16 17:15:59.639] luat:U(273402):I/user.Lua虚拟机内存使用情况 2097144 173640 212768
[2026-01-16 17:16:09.838] luat:U(283601):I/user.系统内存使用情况 238224 120936 129256
[2026-01-16 17:16:09.838] luat:U(283602):I/user.Lua虚拟机内存使用情况 2097144 181368 212768
[2026-01-16 17:16:20.081] luat:U(293855):I/user.系统内存使用情况 238224 120936 129256
[2026-01-16 17:16:20.081] luat:U(293856):I/user.Lua虚拟机内存使用情况 2097144 188944 212768
[2026-01-16 17:16:25.749] cal:I(299514):idx:41=41+(0),r:54,xtal:75,pwr_gain:a4ab7131
[2026-01-16 17:16:30.268] luat:U(304064):I/user.系统内存使用情况 238224 120936 129256
[2026-01-16 17:16:30.268] luat:U(304064):I/user.Lua虚拟机内存使用情况 2097144 196512 212768
[2026-01-16 17:16:34.611] luat:U(308381):I/user.httpplus 等待服务器完成响应
[2026-01-16 17:16:34.673] luat:U(308455):I/user.httpplus 服务器已完成响应,开始解析响应
[2026-01-16 17:16:34.685] luat:U(308465):I/user.http上传完成，状态码: 200
[2026-01-16 17:16:34.685] luat:U(308465):I/user.上传成功
```

5、登录 [https://www.air32.cn/upload/data/mp4/](https://www.air32.cn/upload/data/mp4/) 查看拍摄的视频;

![](https://docs.openLuat.com/cdn/image/8101_usb摄像头演示.jpg)
