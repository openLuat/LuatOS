# AirCAMERA_1020 DEMO

## 演示功能概述

本示例主要是展示 AirCAMERA_1020 的使用，本地拍摄照片后通过 httpplus 扩展库将图片上传至 air32.com

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

### 3、拍照上传核心业务模块（take_photo_http_post.lua）

- 每 30 秒触发一次拍照：AirCAMERA_1020_func()
- 每 3 秒打印一次系统和 LUA 的内存信息：memory_check()
- 配置摄像头信息表：dvp_camera_param
- 初始化摄像头：excamera.open()
- 执行拍照：excamera.photo()
- 上传照片：httpplus.request()
- 关闭摄像头：excamera.close()

## 演示硬件环境

1、Air8101 核心板一块

2、TYPE-C USB 数据线一根

3、合宙标准配件 AirCAMERA_1020 一块

4、Air8101 核心板和合宙标准配件 AirCAMERA_1020 的硬件接线方式为

Air8101 核心板通过 TYPE-C USB 口供电；（背面功耗测试开关拨到 OFF）

TYPE-C USB 数据线直接插到核心板的 TYPE-C USB 座子，另外一端连接电脑 USB 口；

AirCAMERA_1020 配件板 +Air8101 核心板，硬件连接示意图，请跳转至 [https://docs.openluat.com/accessory/AirCAMERA_1020/](https://docs.openluat.com/accessory/AirCAMERA_1020/)：

## 演示软件环境

1、Luatools 下载调试工具：[https://docs.openluat.com/air780epm/common/Luatools/](https://docs.openluat.com/air780epm/common/Luatools/)

2、Air8101 V1006 版本固件：[https://docs.openluat.com/air8101/luatos/firmware/](https://docs.openluat.com/air8101/luatos/firmware/)

## 演示核心步骤

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

5、登录 https://www.air32.cn/upload/data/jpg/ 查看拍摄的照片;

![](https://docs.openluat.com/air8101/luatos/app/accessory/AirCAMERA_1020/image/httpupload.png)