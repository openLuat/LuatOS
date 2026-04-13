# AirCAMERA_1050 DEMO

## 演示功能概述

本示例主要是展示 AirCAMERA_1050 的使用，本地拍摄照片后通过 httpplus 扩展库将图片上传至 air32.com

1、main.lua：主程序入口

2、take_photo_http_post.lua：执行拍照后使用推送照片上传至air32.cn服务器，该服务器为虚拟服务器，仅用于演示，实际使用时请替换为自己的服务器。

3、scan_code.lua：扫描二维码应用DEMO模块

4、netdrv_4g.lua：联网状态检测模块

5、photo_to_aircloud.lua：执行拍照后使用推送照片上传至aircloud平台

注意事项：

- 拍照或者扫描模式需要在摄像头初始化时确定
- 如使用拍照模式就无法使用扫描模式，扫描模式同理
- 需要拍照后执行扫描的话需要重新初始化
- 所以拍照和扫描不可同时使用，如需切换模式需重新初始化

## 演示功能概述

### 1、主程序入口模块（main.lua）

- 初始化项目信息和版本号
- 初始化看门狗，并定时喂狗
- 启动一个循环定时器，每隔 3 秒钟打印一次总内存，实时的已使用内存，历史最高的已使用内存情况方便分析内存使用是否有异常
- 加载 netdrv_4g 4G联网状态检测模块
- 加载 photo_to_aircloud 拍照上传至aircloud平台模块，务必先配置auth_key，否则会报错
- 加载 take_photo_http_post 模块

### 2、4G联网状态检测模块（netdrv_4g.lua）

- 订阅"IP_READY"消息，收到消息后打印联网成功日志
- 订阅"IP_LOSE"消息，收到消息后打印联网失败日志

### 3、拍照上传服务器演示模块（take_photo_http_post.lua）

- 每 30 秒触发一次拍照：AirCAMERA_1050_func()
- 每 3 秒打印一次系统和 LUA 的内存信息：memory_check()
- 配置摄像头信息表：spi_camera_param
- 初始化摄像头：excamera.open()
- 执行拍照：excamera.photo()
- 上传照片：httpplus.request()
- 关闭摄像头：excamera.close()

### 4、扫描二维码应用DEMO（scan_code.lua）

- 每 30 秒触发一次拍照：AirCAMERA_1050_func()
- 每 3 秒打印一次系统和 LUA 的内存信息：memory_check()
- 配置摄像头信息表：spi_camera_param
- 初始化摄像头：excamera.open()
- 执行扫描：excamera.scan()
- 关闭摄像头：excamera.close()

### 5、拍照上传至aircloud平台业务模块（photo_to_aircloud.lua）

- 配置excloud链接，启动心跳包
- 开启自动重连机制，断网后自动重连
- 订阅excloud_post_image_done消息，收到消息后打印上传结果：log.info("excloud_post_image_func", err)
- 每 30 秒触发一次拍照：AirCAMERA_1050_func()
- 每 3 秒打印一次系统和 LUA 的内存信息：memory_check()
- 注册excloud回调：on_excloud_event()
- 配置excloud链接，启动心跳包：excloud_task_func()
- 照片上传任务函数：upload_image_fun()
- 配置摄像头信息表：spi_camera_param
- 初始化摄像头：excamera.open()
- 执行拍照：excamera.photo()
- 上传照片：httpplus.request()
- 关闭摄像头：excamera.close()


## 演示硬件环境

1、Air8000系列 开发板一块

2、TYPE-C USB 数据线一根

3、合宙标准配件 AirCAMERA_1050 一个

4、Air8000系列 开发板和合宙标准配件 AirCAMERA_1050 的硬件接线方式为

Air8000系列 开发板通过 TYPE-C USB 口供电；（侧面拨码拨至USB供电）

TYPE-C USB 数据线直接插到开发板的 TYPE-C USB 座子，另外一端连接电脑 USB 口；

AirCAMERA_1050 配件板插入Air8000系列 开发板的SPI摄像头座子中

## 演示软件环境

1、Luatools 下载调试工具：[https://docs.openluat.com/air780epm/common/Luatools/](https://docs.openluat.com/air780epm/common/Luatools/)

2、固件版本：LuatOS-SoC_V2018_Air8000_1，固件地址，如有最新固件请用最新 https://docs.openluat.com/air8000/luatos/firmware/


## 演示核心步骤

1、搭建硬件环境;

2、烧录 DEMO 代码;

3、等待自动拍照完成后上传平台，LUATOOLS会有如下打印;
```lua
[2026-04-08 11:36:21.662][000000000.378] I/user.main AirCAMERA_1040_Demo 001.999.000
[2026-04-08 11:36:21.667][000000000.537] W/user.excloud_task_func wait IP_READY 1 3
[2026-04-08 11:36:21.676][000000000.538] I/user.exmux 设置引脚 cs2 (20) 为高电平
[2026-04-08 11:36:21.682][000000000.538] I/user.exmux 设置引脚 cs1 (12) 为高电平
[2026-04-08 11:36:21.690][000000000.539] I/user.exmux 设置引脚 pwr1 (140) 为高电平
[2026-04-08 11:36:21.704][000000000.546] I/user.exmux 分组 spi1 打开成功
[2026-04-08 11:36:21.715][000000000.547] I/user.exmux 设置引脚 pwr3 (141) 为高电平
[2026-04-08 11:36:21.729][000000000.552] I/user.exmux 设置引脚 pwr2 (24) 为高电平
[2026-04-08 11:36:21.742][000000000.552] I/user.exmux 设置引脚 pwr1 (164) 为高电平
[2026-04-08 11:36:21.753][000000000.558] I/user.exmux 分组 i2c0 打开成功
[2026-04-08 11:36:21.761][000000000.558] I/user.exmux 开发板 DEV_BOARD_8000_V2.0 初始化成功
[2026-04-08 11:36:21.775][000000001.537] W/user.excloud_task_func wait IP_READY 1 3
[2026-04-08 11:36:22.427][000000002.538] W/user.excloud_task_func wait IP_READY 1 3
[2026-04-08 11:36:23.428][000000003.539] I/user.sys ram 3201504 365428 368600
[2026-04-08 11:36:23.436][000000003.540] I/user.lua ram 4194296 176000 176592
[2026-04-08 11:36:23.440][000000003.541] W/user.excloud_task_func wait IP_READY 1 3
[2026-04-08 11:36:24.457][000000004.542] W/user.excloud_task_func wait IP_READY 1 3
[2026-04-08 11:36:25.435][000000005.543] W/user.excloud_task_func wait IP_READY 1 3
[2026-04-08 11:36:26.430][000000006.541] I/user.sys ram 3201504 366964 368600
[2026-04-08 11:36:26.435][000000006.542] I/user.lua ram 4194296 177488 177488
[2026-04-08 11:36:26.438][000000006.544] W/user.excloud_task_func wait IP_READY 1 3
[2026-04-08 11:36:26.771][000000006.811] I/mobile sim0 sms ready
[2026-04-08 11:36:26.777][000000006.812] D/mobile cid1, state0
[2026-04-08 11:36:26.788][000000006.812] D/mobile bearer act 0, result 0
[2026-04-08 11:36:26.794][000000006.813] D/mobile NETIF_LINK_ON -> IP_READY
[2026-04-08 11:36:26.797][000000006.814] I/user.netdrv_4g.ip_ready_func IP_READY 10.204.173.176 255.255.255.255 0.0.0.0 nil
[2026-04-08 11:36:26.801][000000006.817] I/user.[excloud]4G设备 IMEI: 864793080294593 MUID: 20250918234235A886413A1077757041
[2026-04-08 11:36:26.808][000000006.836] I/user.exmtn 读取索引 1
[2026-04-08 11:36:26.812][000000006.837] I/user.exmtn 读取块数配置 2
[2026-04-08 11:36:26.816][000000006.837] I/user.exmtn 读取写入方式配置 0
[2026-04-08 11:36:26.823][000000006.837] I/user.exmtn 配置变化 false
[2026-04-08 11:36:26.828][000000006.841] I/user.exmtn 配置未变化，文件存在，继续写入
[2026-04-08 11:36:26.835][000000006.844] I/user.exmtn 初始化成功: 每个文件 8.00 KB (2 块 × 4096 字节), 总空间 32.00 KB (4 个文件)
[2026-04-08 11:36:26.842][000000006.845] I/user.[excloud]运维日志初始化成功
[2026-04-08 11:36:26.847][000000006.845] I/user.[excloud]excloud.setup 初始化成功 设备ID: 864793080294593
[2026-04-08 11:36:26.854][000000006.846] I/user.excloud初始化成功
[2026-04-08 11:36:26.858][000000006.846] I/user.[excloud]首次连接，获取服务器信息...
[2026-04-08 11:36:26.862][000000006.846] I/user.[excloud]excloud.getip 类型: 3 key: sh5g0OTP7ThOSlGKmE5jiEMbOBqQWyw9-864793080294593
[2026-04-08 11:36:26.867][000000006.853] D/socket connect to gps.openluat.com,443
[2026-04-08 11:36:26.871][000000006.854] dns_run 676:gps.openluat.com state 0 id 1 ipv6 0 use dns server2, try 0
[2026-04-08 11:36:26.876][000000006.856] D/mobile TIME_SYNC 0 tm 1775619387
[2026-04-08 11:36:26.880][000000006.885] dns_run 693:dns all done ,now stop
[2026-04-08 11:36:27.596][000000007.701] I/user.httpplus 服务器已完成响应,开始解析响应
[2026-04-08 11:36:27.627][000000007.732] I/user.[excloud]excloud.getip响应 HTTP Code: 200 Body: 
[2026-04-08 11:36:27.636][000000007.732] {"msg":"ok","conninfo":{"ipv4":"124.71.128.165","port":9108},"imginfo":{"url":"https://gps.openluat.com/aircloud/air_up/image","data_key":"f","data_param":{"key":"8beGWMVkfgqqH7cj93G3F6fJrz8UhPSA7nGNC","tip":""}},"audinfo":{"url":"https://gps.openluat.com/aircloud/air_up/audio","data_key":"f","data_param":{"key":"8beGWMVkfgqqH7cj93G3F6fJrz8UhPSA7nGNC","tip":""}},"mtninfo":{"url":"https://gps.openluat.com/aircloud/air_up/file","data_key":"f","data_param":{"key":"8beGWMVkfgqqH7cj93G3F6fJrz8UhPSA7nGNC","tip":""}},"qrinfo":{"url":"https://gps.openluat.com/#/redirect?key=_5oruyMsMk5Ny5ZajRxwJqUr2wyQEx3SrcCJ"}}
[2026-04-08 11:36:27.644][000000007.733] I/user.[excloud]excloud.getip响应 HTTP Code: 200 Body: 
[2026-04-08 11:36:27.649][000000007.733] {"msg":"ok","conninfo":{"ipv4":"124.71.128.165","port":9108},"imginfo":{"url":"https://gps.openluat.com/aircloud/air_up/image","data_key":"f","data_param":{"key":"8beGWMVkfgqqH7cj93G3F6fJrz8UhPSA7nGNC","tip":""}},"audinfo":{"url":"https://gps.openluat.com/aircloud/air_up/audio","data_key":"f","data_param":{"key":"8beGWMVkfgqqH7cj93G3F6fJrz8UhPSA7nGNC","tip":""}},"mtninfo":{"url":"https://gps.openluat.com/aircloud/air_up/file","data_key":"f","data_param":{"key":"8beGWMVkfgqqH7cj93G3F6fJrz8UhPSA7nGNC","tip":""}},"qrinfo":{"url":"https://gps.openluat.com/#/redirect?key=_5oruyMsMk5Ny5ZajRxwJqUr2wyQEx3SrcCJ"}}
[2026-04-08 11:36:27.653][000000007.735] I/user.[excloud]获取到TCP/UDP连接信息 host: 124.71.128.165 port: 9108 key: nil
[2026-04-08 11:36:27.660][000000007.735] I/user.[excloud]获取到图片上传信息
[2026-04-08 11:36:27.665][000000007.735] I/user.[excloud]获取到音频上传信息
[2026-04-08 11:36:27.668][000000007.736] I/user.[excloud]获取到运维日志上传信息
[2026-04-08 11:36:27.676][000000007.736] I/user.[excloud]获取到二维码信息
[2026-04-08 11:36:27.682][000000007.737] I/user.[excloud]excloud.getip 更新配置: 124.71.128.165 9108
[2026-04-08 11:36:27.686][000000007.737] I/user.[excloud]excloud.getip 成功: true 结果: {"ipv4":"124.71.128.165","port":9108}
[2026-04-08 11:36:27.696][000000007.738] I/user.[excloud]服务器信息获取成功 host: 124.71.128.165 port: 9108 transport: tcp
[2026-04-08 11:36:27.701][000000007.739] I/user.[excloud]创建TCP连接
[2026-04-08 11:36:27.706][000000007.740] D/socket connect to 124.71.128.165,9108
[2026-04-08 11:36:27.711][000000007.741] network_socket_connect 1610:network 1-0 local port auto select 51002
[2026-04-08 11:36:27.715][000000007.742] I/user.[excloud]TCP连接结果 true false
[2026-04-08 11:36:27.724][000000007.742] I/user.[excloud]excloud service started
[2026-04-08 11:36:27.728][000000007.743] I/user.excloud服务已开启
[2026-04-08 11:36:27.732][000000007.743] I/user.[excloud]excloud 自动心跳已启动，间隔 300 秒
[2026-04-08 11:36:27.738][000000007.744] I/user.自动心跳已启动
[2026-04-08 11:36:27.743][000000007.811] network_default_socket_callback 1123:before process socket 1,event:0xf2000009(连接成功),state:3(正在连接),wait:2(等待连接完成)
[2026-04-08 11:36:27.747][000000007.811] network_default_socket_callback 1127:after process socket 1,state:5(在线),wait:0(无等待)
[2026-04-08 11:36:27.752][000000007.813] I/user.[excloud]socket cb userdata: 0C7D11D0 33554449 0
[2026-04-08 11:36:27.760][000000007.813] I/user.[excloud]socket TCP连接成功
[2026-04-08 11:36:27.764][000000007.814] I/user.用户回调函数 connect_result {"success":true}
[2026-04-08 11:36:27.769][000000007.814] I/user.连接成功
[2026-04-08 11:36:27.775][000000007.818] I/user.[excloud]构建发送数据 16 3 sh5g0OTP7ThOSlGKmE5jiEMbOBqQWyw9-864793080294593-20250918234235A886413A1077757041 
[2026-04-08 11:36:27.780][000000007.819] I/user.[excloud]tlv发送数据长度4 85
[2026-04-08 11:36:27.789][000000007.820] I/user.[excloud]构建消息头 GY 
[2026-04-08 11:36:27.797][000000007.822] I/user.用户回调函数 send_result {"sequence_num":1,"success":true,"error_msg":"Send successful"}
[2026-04-08 11:36:27.805][000000007.829] I/user.[excloud]数据发送成功 101 字节
[2026-04-08 11:36:27.810][000000007.892] network_default_socket_callback 1123:before process socket 1,event:0xf2000004(发送成功),state:5(在线),wait:3(等待发送完成)
[2026-04-08 11:36:27.815][000000007.893] network_default_socket_callback 1127:after process socket 1,state:5(在线),wait:0(无等待)
[2026-04-08 11:36:27.820][000000007.894] I/user.[excloud]socket cb userdata: 0C7D11D0 33554450 0
[2026-04-08 11:36:27.826][000000007.894] I/user.[excloud]socket 发送完成
[2026-04-08 11:36:29.426][000000009.543] I/user.sys ram 3201504 376372 418064
[2026-04-08 11:36:29.435][000000009.544] I/user.lua ram 4194296 176512 195736
[2026-04-08 11:36:32.441][000000012.545] I/user.sys ram 3201504 376608 418064
[2026-04-08 11:36:32.449][000000012.546] I/user.lua ram 4194296 176880 195736
[2026-04-08 11:36:35.440][000000015.547] I/user.sys ram 3201504 367976 418064
[2026-04-08 11:36:35.448][000000015.548] I/user.lua ram 4194296 177392 195736
[2026-04-08 11:36:38.445][000000018.549] I/user.sys ram 3201504 367976 418064
[2026-04-08 11:36:38.449][000000018.550] I/user.lua ram 4194296 177608 195736
[2026-04-08 11:36:41.435][000000021.551] I/user.sys ram 3201504 367976 418064
[2026-04-08 11:36:41.443][000000021.552] I/user.lua ram 4194296 177824 195736
[2026-04-08 11:36:44.438][000000024.553] I/user.sys ram 3201504 367976 418064
[2026-04-08 11:36:44.448][000000024.553] I/user.lua ram 4194296 178024 195736
[2026-04-08 11:36:47.449][000000027.555] I/user.sys ram 3201504 367976 418064
[2026-04-08 11:36:47.456][000000027.555] I/user.lua ram 4194296 178216 195736
[2026-04-08 11:36:50.430][000000030.540] I/user.exmux 该分组设备已经打开: i2c0
[2026-04-08 11:36:50.437][000000030.550] I2C_MasterSetup 426:I2C0, Total 65 HCNT 22 LCNT 40
[2026-04-08 11:36:50.442][000000030.551] CSPI_Setup 1924:APB MP 102400000
[2026-04-08 11:36:50.506][000000030.611] I/user.初始化状态 true
[2026-04-08 11:36:50.513][000000030.611] CSPI_Rx 2022:block len 7680, total block 80
[2026-04-08 11:36:50.517][000000030.612] I/user.照片存储路径 /test.jpg
[2026-04-08 11:36:50.521][000000030.612] luat_camera_capture_config 700:0,0,0,0
[2026-04-08 11:36:50.530][000000030.613] luat_camera_capture 676:save file in /test.jpg
[2026-04-08 11:36:50.535][000000030.614] I/user.sys ram 3201504 992304 992380
[2026-04-08 11:36:50.539][000000030.615] I/user.lua ram 4194296 180232 195736
[2026-04-08 11:36:51.596][000000031.701] I/user.摄像头数据 58223
[2026-04-08 11:36:51.602][000000031.702] I/user.拍照完成
[2026-04-08 11:36:51.606][000000031.703] I/user.开始上传图片
[2026-04-08 11:36:51.617][000000031.708] I/user.[excloud]开始文件上传 类型: 1 文件: /test.jpg 大小: 58223
[2026-04-08 11:36:51.621][000000031.708] I/user.[excloud]开始文件上传 类型: 1 文件: test.jpg 大小: 58223
[2026-04-08 11:36:51.625][000000031.709] I/user.[excloud]构建发送数据 23 0 0 
[2026-04-08 11:36:51.633][000000031.711] I/user.[excloud]构建发送数据 784 0 1 
[2026-04-08 11:36:51.638][000000031.712] I/user.[excloud]构建发送数据 785 3 test.jpg 
[2026-04-08 11:36:51.644][000000031.713] I/user.[excloud]构建发送数据 786 0 58223 
[2026-04-08 11:36:51.650][000000031.714] I/user.[excloud]tlv发送数据长度4 36
[2026-04-08 11:36:51.654][000000031.715] I/user.[excloud]构建消息头 GY 
[2026-04-08 11:36:51.660][000000031.720] I/user.用户回调函数 send_result {"sequence_num":2,"success":true,"error_msg":"Send successful"}
[2026-04-08 11:36:51.666][000000031.726] I/user.[excloud]数据发送成功 52 字节
[2026-04-08 11:36:51.676][000000031.752] I/user.[excloud]开始发送HTTP请求 URL: https://gps.openluat.com/aircloud/air_up/image
[2026-04-08 11:36:51.689][000000031.756] dns_run 676:gps.openluat.com state 0 id 2 ipv6 0 use dns server2, try 0
[2026-04-08 11:36:51.780][000000031.887] dns_run 693:dns all done ,now stop
[2026-04-08 11:36:51.794][000000031.909] network_default_socket_callback 1123:before process socket 1,event:0xf2000004(发送成功),state:5(在线),wait:3(等待发送完成)
[2026-04-08 11:36:51.809][000000031.909] network_default_socket_callback 1127:after process socket 1,state:5(在线),wait:0(无等待)
[2026-04-08 11:36:51.821][000000031.910] I/user.[excloud]socket cb userdata: 0C7D11D0 33554450 0
[2026-04-08 11:36:51.834][000000031.911] I/user.[excloud]socket 发送完成
[2026-04-08 11:36:53.502][000000033.616] I/user.sys ram 3201504 1104536 1305652
[2026-04-08 11:36:53.510][000000033.617] I/user.lua ram 4194296 354032 469472
[2026-04-08 11:36:54.862][000000034.968] I/http http close c152ef4
[2026-04-08 11:36:54.870][000000034.970] I/user.[excloud]excloud.getip文件上传响应 HTTP Code: 200 Body: {"info":"aircloud./aircloud/air_up/image","code":0,"trace":"code:aircloud./aircloud/air_up/image,  trcace:","log":"^^^","value":{"uri":"/vsa/aircloud_image/FFZDbqsuzrLpbgPfzVd7De/2026-04/864793080294593/20260408113655_test.jpg","size":"56.00KB","thumb":"/vsa/aircloud_image/FFZDbqsuzrLpbgPfzVd7De/2026-04/864793080294593/20260408113655_testt.jpg"}}
[2026-04-08 11:36:54.883][000000034.971] I/user.[excloud]文件上传成功 URL: /vsa/aircloud_image/FFZDbqsuzrLpbgPfzVd7De/2026-04/864793080294593/20260408113655_test.jpg
[2026-04-08 11:36:54.889][000000034.972] I/user.[excloud]构建发送数据 24 0 0 
[2026-04-08 11:36:54.899][000000034.973] I/user.[excloud]构建发送数据 784 0 1 
[2026-04-08 11:36:54.905][000000034.975] I/user.[excloud]构建发送数据 785 3 test.jpg 
[2026-04-08 11:36:54.912][000000034.976] I/user.[excloud]构建发送数据 787 0 0 
[2026-04-08 11:36:54.919][000000034.978] I/user.[excloud]tlv发送数据长度4 36
[2026-04-08 11:36:54.929][000000034.979] I/user.[excloud]构建消息头 GY 
[2026-04-08 11:36:54.934][000000034.982] I/user.用户回调函数 send_result {"sequence_num":3,"success":true,"error_msg":"Send successful"}
[2026-04-08 11:36:54.939][000000034.988] I/user.[excloud]数据发送成功 52 字节
[2026-04-08 11:36:54.946][000000034.988] I/user.图片上传成功
[2026-04-08 11:36:54.951][000000035.051] network_default_socket_callback 1123:before process socket 1,event:0xf2000004(发送成功),state:5(在线),wait:3(等待发送完成)
[2026-04-08 11:36:54.955][000000035.051] network_default_socket_callback 1127:after process socket 1,state:5(在线),wait:0(无等待)
[2026-04-08 11:36:54.960][000000035.063] I/user.[excloud]socket cb userdata: 0C7D11D0 33554450 0
[2026-04-08 11:36:54.968][000000035.064] I/user.[excloud]socket 发送完成
[2026-04-08 11:36:54.979][000000035.072] I/user.exmux 设置引脚 pwr3 (141) 为低电平
[2026-04-08 11:36:54.983][000000035.078] I/user.exmux 设置引脚 pwr2 (24) 为低电平
[2026-04-08 11:36:54.989][000000035.079] I/user.exmux 设置引脚 pwr1 (164) 为低电平
[2026-04-08 11:36:54.993][000000035.084] I/user.exmux 分组 i2c0 关闭成功
```

4、等待自动扫描任务完成后，LUATOOLS会有如下打印;
```lua
[2025-11-21 15:19:17.310][000000000.269] I2C_MasterSetup 426:I2C1, Total 65 HCNT 22 LCNT 40
[2025-11-21 15:19:17.313][000000000.332] I/user.初始化状态 true
[2025-11-21 15:19:17.316][000000000.332] CSPI_Rx 2000:block len 7680, total block 40
[2025-11-21 15:19:17.319][000000000.541] I/user.扫码结果 Air780EPM
[2025-11-21 15:19:17.323][000000000.542] I/user.扫描完成，扫描结果为： Air780EPM
[2025-11-21 15:19:17.327][000000000.542] I/user.Scan result : Air780EPM
```

5、登录 https://www.air32.cn/upload/jpg/ 查看拍摄的照片;

![](https://docs.openluat.com/air8101/luatos/app/accessory/AirCAMERA_1020/image/httpupload.png)