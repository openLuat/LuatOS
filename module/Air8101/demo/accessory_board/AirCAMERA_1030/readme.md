# AirCAMERA_1030 DEMO

## 演示功能概述

本示例主要是展示 AirCAMERA_1030 的使用，本地拍摄照片后通过 httpplus 扩展库将图片上传至 air32.com

1、main.lua：主程序入口

2、take_photo_http_post.lua：执行拍照后上传照片至 air32.com

3、netdrv_wifi.lua：连接 WIFI

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
- 每 30 秒触发一次拍照：AirCAMERA_1030_func()
- 每 3 秒打印一次系统和 LUA 的内存信息：memory_check()
- 配置摄像头信息表：usb_camera_param
- 初始化摄像头：excamera.open()
- 执行拍照：excamera.photo()
- 上传照片：httpplus.request()
- 关闭摄像头：excamera.close()

## 演示硬件环境

1、Air8101 核心板一块

2、TYPE-C USB 数据线一根

3、合宙标准配件 AirCAMERA_1030 一块

4、Air8101 核心板和合宙标准配件 AirCAMERA_1030 的硬件接线方式为

Air8101 核心板通过 TYPE-C USB 口供电；（背面功耗测试开关拨到 OFF）

TYPE-C USB 数据线直接插到核心板的 TYPE-C USB 座子，另外一端连接电脑 USB 口；

AirCAMERA_1030 配件板 + Air8101 核心板，硬件连接示意图：

单路摄像头链接方式
![](https://docs.openluat.com/air8101/luatos/app/accessory/AirCAMERA_1020/image/one_camera.jpg)

四路摄像头链接方式
如图所示，将四路USB摄像头接入HUB中，然后将HUB通过USB口连接到Air8101核心板上;
![](https://docs.openluat.com/air8101/luatos/app/accessory/AirCAMERA_1020/image/four_camera.jpg)

## 演示软件环境

1、Luatools 下载调试工具：[https://docs.openluat.com/air780epm/common/Luatools/](https://docs.openluat.com/air780epm/common/Luatools/)

2、Air8101 V1006 版本固件：[https://docs.openluat.com/air8101/luatos/firmware/](https://docs.openluat.com/air8101/luatos/firmware/)

## 演示核心步骤

1、搭建硬件环境;

2、修改 netdrv_wifi.lua 中的 WIFI 账号密码;

3、烧录 DEMO 代码;
   单路摄像头请将take_photo_http_post.lua中的usb_port_num修改为1;
   四路或多路摄像头请将take_photo_http_post.lua中的usb_port_num修改为4或对应的摄像头数量;

4、
等待单摄像头自动拍照完成后上传平台，LUATOOLS会有如下打印;
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