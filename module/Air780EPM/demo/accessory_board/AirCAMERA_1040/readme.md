# AirCAMERA_1040 DEMO

## 演示功能概述

本示例主要是展示 AirCAMERA_1040 的使用，本地拍摄照片后通过 httpplus 扩展库将图片上传至 air32.com

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

- 每 30 秒触发一次拍照：AirCAMERA_1040_func()
- 每 3 秒打印一次系统和 LUA 的内存信息：memory_check()
- 配置摄像头信息表：spi_camera_param
- 初始化摄像头：excamera.open()
- 执行拍照：excamera.photo()
- 上传照片：httpplus.request()
- 关闭摄像头：excamera.close()

### 4、扫描二维码应用DEMO（scan_code.lua）

- 每 30 秒触发一次拍照：AirCAMERA_1040_func()
- 每 3 秒打印一次系统和 LUA 的内存信息：memory_check()
- 配置摄像头信息表：spi_camera_param
- 初始化摄像头：excamera.open()
- 执行扫描：excamera.scan()
- 关闭摄像头：excamera.close()

### 5、拍照上传至aircloud平台业务模块（photo_to_aircloud.lua）

- 配置excloud链接，启动心跳包
- 开启自动重连机制，断网后自动重连
- 订阅excloud_post_image_done消息，收到消息后打印上传结果：log.info("excloud_post_image_func", err)
- 每 30 秒触发一次拍照：AirCAMERA_1040_func()
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

1、Air780EPM 开发板一块

2、TYPE-C USB 数据线一根

3、合宙标准配件 AirCAMERA_1040 一个

4、Air780EPM 开发板和合宙标准配件 AirCAMERA_1040 的硬件接线方式为

Air780EPM 开发板通过 TYPE-C USB 口供电；（侧面拨码拨至USB供电）

TYPE-C USB 数据线直接插到开发板的 TYPE-C USB 座子，另外一端连接电脑 USB 口；

AirCAMERA_1040 配件板插入Air780EPM 开发板的SPI摄像头座子中

## 演示软件环境

1、Luatools 下载调试工具：[https://docs.openluat.com/air780epm/common/Luatools/](https://docs.openluat.com/air780epm/common/Luatools/)

2、固件版本：LuatOS-SoC_V2018_Air780EPM_1，固件地址，如有最新固件请用最新 https://docs.openluat.com/air780epm/luatos/firmware/version/


## 演示核心步骤

1、搭建硬件环境;

2、烧录 DEMO 代码;

3、等待自动拍照完成后上传平台，LUATOOLS会有如下打印;
```lua
[2026-04-08 17:36:12.996][000000000.205] I/user.main AirCAMERA_1040_Demo 001.999.000
[2026-04-08 17:36:12.999][000000000.325] W/user.excloud_task_func wait IP_READY 1 1
[2026-04-08 17:36:13.002][000000000.326] I/user.exmux 开发板 DEV_BOARD_780_V1.2 初始化成功
[2026-04-08 17:36:13.504][000000001.326] W/user.excloud_task_func wait IP_READY 1 1
[2026-04-08 17:36:14.408][000000002.166] I/mobile sim0 sms ready
[2026-04-08 17:36:14.412][000000002.167] D/mobile cid1, state0
[2026-04-08 17:36:14.423][000000002.168] D/mobile bearer act 0, result 0
[2026-04-08 17:36:14.430][000000002.168] D/mobile NETIF_LINK_ON -> IP_READY
[2026-04-08 17:36:14.438][000000002.169] I/user.netdrv_4g.ip_ready_func IP_READY 10.122.36.125 255.255.255.255 0.0.0.0 nil
[2026-04-08 17:36:14.445][000000002.173] I/user.[excloud]4G设备 IMEI: 867920071472378 MUID: 20250604131416A755490A2989432885
[2026-04-08 17:36:14.451][000000002.189] I/user.exmtn 读取索引 1
[2026-04-08 17:36:14.457][000000002.189] I/user.exmtn 读取块数配置 2
[2026-04-08 17:36:14.464][000000002.190] I/user.exmtn 读取写入方式配置 0
[2026-04-08 17:36:14.468][000000002.190] I/user.exmtn 配置变化 false
[2026-04-08 17:36:14.473][000000002.193] I/user.exmtn 配置未变化，文件存在，继续写入
[2026-04-08 17:36:14.479][000000002.197] I/user.exmtn 初始化成功: 每个文件 8.00 KB (2 块 × 4096 字节), 总空间 32.00 KB (4 个文件)
[2026-04-08 17:36:14.484][000000002.197] I/user.[excloud]运维日志初始化成功
[2026-04-08 17:36:14.488][000000002.198] I/user.[excloud]excloud.setup 初始化成功 设备ID: 867920071472378
[2026-04-08 17:36:14.494][000000002.198] I/user.excloud初始化成功
[2026-04-08 17:36:14.499][000000002.198] I/user.[excloud]首次连接，获取服务器信息...
[2026-04-08 17:36:14.505][000000002.199] I/user.[excloud]excloud.getip 类型: 3 key: sh5g0OTP7ThOSlGKmE5jiEMbOBqQWyw9-867920071472378
[2026-04-08 17:36:14.512][000000002.205] D/socket connect to gps.openluat.com,443
[2026-04-08 17:36:14.516][000000002.209] dns_run 676:gps.openluat.com state 0 id 1 ipv6 0 use dns server2, try 0
[2026-04-08 17:36:14.520][000000002.231] D/mobile TIME_SYNC 0 tm 1775640975
[2026-04-08 17:36:14.526][000000002.273] dns_run 693:dns all done ,now stop
[2026-04-08 17:36:15.179][000000003.008] I/user.httpplus 服务器已完成响应,开始解析响应
[2026-04-08 17:36:15.211][000000003.037] I/user.[excloud]excloud.getip响应 HTTP Code: 200 Body: 
[2026-04-08 17:36:15.218][000000003.037] {"msg":"ok","conninfo":{"ipv4":"124.71.128.165","port":9108},"imginfo":{"url":"https://gps.openluat.com/aircloud/air_up/image","data_key":"f","data_param":{"key":"8bcWhwHK4pZR7gTbvPUdxL1TAbW5H3C65MFcC","tip":""}},"audinfo":{"url":"https://gps.openluat.com/aircloud/air_up/audio","data_key":"f","data_param":{"key":"8bcWhwHK4pZR7gTbvPUdxL1TAbW5H3C65MFcC","tip":""}},"mtninfo":{"url":"https://gps.openluat.com/aircloud/air_up/file","data_key":"f","data_param":{"key":"8bcWhwHK4pZR7gTbvPUdxL1TAbW5H3C65MFcC","tip":""}},"qrinfo":{"url":"https://gps.openluat.com/#/redirect?key=_5oruyMsMk5Ny5ZajRyBqaZEqqaPjVSb93qH"}}
[2026-04-08 17:36:15.225][000000003.038] I/user.[excloud]excloud.getip响应 HTTP Code: 200 Body: 
[2026-04-08 17:36:15.231][000000003.038] {"msg":"ok","conninfo":{"ipv4":"124.71.128.165","port":9108},"imginfo":{"url":"https://gps.openluat.com/aircloud/air_up/image","data_key":"f","data_param":{"key":"8bcWhwHK4pZR7gTbvPUdxL1TAbW5H3C65MFcC","tip":""}},"audinfo":{"url":"https://gps.openluat.com/aircloud/air_up/audio","data_key":"f","data_param":{"key":"8bcWhwHK4pZR7gTbvPUdxL1TAbW5H3C65MFcC","tip":""}},"mtninfo":{"url":"https://gps.openluat.com/aircloud/air_up/file","data_key":"f","data_param":{"key":"8bcWhwHK4pZR7gTbvPUdxL1TAbW5H3C65MFcC","tip":""}},"qrinfo":{"url":"https://gps.openluat.com/#/redirect?key=_5oruyMsMk5Ny5ZajRyBqaZEqqaPjVSb93qH"}}
[2026-04-08 17:36:15.237][000000003.039] I/user.[excloud]获取到TCP/UDP连接信息 host: 124.71.128.165 port: 9108 key: nil
[2026-04-08 17:36:15.242][000000003.039] I/user.[excloud]获取到图片上传信息
[2026-04-08 17:36:15.247][000000003.040] I/user.[excloud]获取到音频上传信息
[2026-04-08 17:36:15.255][000000003.040] I/user.[excloud]获取到运维日志上传信息
[2026-04-08 17:36:15.262][000000003.040] I/user.[excloud]获取到二维码信息
[2026-04-08 17:36:15.266][000000003.041] I/user.[excloud]excloud.getip 更新配置: 124.71.128.165 9108
[2026-04-08 17:36:15.271][000000003.041] I/user.[excloud]excloud.getip 成功: true 结果: {"ipv4":"124.71.128.165","port":9108}
[2026-04-08 17:36:15.276][000000003.042] I/user.[excloud]服务器信息获取成功 host: 124.71.128.165 port: 9108 transport: tcp
[2026-04-08 17:36:15.280][000000003.042] I/user.[excloud]创建TCP连接
[2026-04-08 17:36:15.286][000000003.043] D/socket connect to 124.71.128.165,9108
[2026-04-08 17:36:15.291][000000003.044] network_socket_connect 1610:network 1-0 local port auto select 51002
[2026-04-08 17:36:15.295][000000003.045] I/user.[excloud]TCP连接结果 true false
[2026-04-08 17:36:15.301][000000003.046] I/user.[excloud]excloud service started
[2026-04-08 17:36:15.306][000000003.046] I/user.excloud服务已开启
[2026-04-08 17:36:15.311][000000003.047] I/user.[excloud]excloud 自动心跳已启动，间隔 300 秒
[2026-04-08 17:36:15.315][000000003.047] I/user.自动心跳已启动
[2026-04-08 17:36:15.323][000000003.127] network_default_socket_callback 1123:before process socket 1,event:0xf2000009(连接成功),state:3(正在连接),wait:2(等待连接完成)
[2026-04-08 17:36:15.328][000000003.127] network_default_socket_callback 1127:after process socket 1,state:5(在线),wait:0(无等待)
[2026-04-08 17:36:15.332][000000003.128] I/user.[excloud]socket cb userdata: 0C1843F0 33554449 0
[2026-04-08 17:36:15.337][000000003.129] I/user.[excloud]socket TCP连接成功
[2026-04-08 17:36:15.342][000000003.129] I/user.用户回调函数 connect_result {"success":true}
[2026-04-08 17:36:15.346][000000003.129] I/user.连接成功
[2026-04-08 17:36:15.352][000000003.133] I/user.[excloud]构建发送数据 16 3 sh5g0OTP7ThOSlGKmE5jiEMbOBqQWyw9-867920071472378-20250604131416A755490A2989432885 
[2026-04-08 17:36:15.357][000000003.134] I/user.[excloud]tlv发送数据长度4 85
[2026-04-08 17:36:15.362][000000003.135] I/user.[excloud]构建消息头 y  r7 
[2026-04-08 17:36:15.371][000000003.137] I/user.用户回调函数 send_result {"sequence_num":1,"success":true,"error_msg":"Send successful"}
[2026-04-08 17:36:15.376][000000003.143] I/user.[excloud]数据发送成功 101 字节
[2026-04-08 17:36:15.385][000000003.207] network_default_socket_callback 1123:before process socket 1,event:0xf2000004(发送成功),state:5(在线),wait:3(等待发送完成)
[2026-04-08 17:36:15.390][000000003.207] network_default_socket_callback 1127:after process socket 1,state:5(在线),wait:0(无等待)
[2026-04-08 17:36:15.395][000000003.208] I/user.[excloud]socket cb userdata: 0C1843F0 33554450 0
[2026-04-08 17:36:15.403][000000003.208] I/user.[excloud]socket 发送完成
[2026-04-08 17:36:15.491][000000003.327] I/user.sys ram 2375920 80156 121112
[2026-04-08 17:36:15.496][000000003.328] I/user.lua ram 1048568 174392 190984
[2026-04-08 17:36:18.498][000000006.328] I/user.sys ram 2375920 80156 121112
[2026-04-08 17:36:18.531][000000006.329] I/user.lua ram 1048568 174712 190984
[2026-04-08 17:36:21.500][000000009.329] I/user.sys ram 2375920 71760 121112
[2026-04-08 17:36:21.518][000000009.330] I/user.lua ram 1048568 175240 190984
[2026-04-08 17:36:24.496][000000012.330] I/user.sys ram 2375920 71760 121112
[2026-04-08 17:36:24.501][000000012.331] I/user.lua ram 1048568 175440 190984
[2026-04-08 17:36:27.508][000000015.331] I/user.sys ram 2375920 71760 121112
[2026-04-08 17:36:27.512][000000015.332] I/user.lua ram 1048568 175632 190984
[2026-04-08 17:36:30.505][000000018.332] I/user.sys ram 2375920 71760 121112
[2026-04-08 17:36:30.511][000000018.333] I/user.lua ram 1048568 175832 190984
[2026-04-08 17:36:33.503][000000021.333] I/user.sys ram 2375920 71760 121112
[2026-04-08 17:36:33.510][000000021.334] I/user.lua ram 1048568 176024 190984
[2026-04-08 17:36:36.506][000000024.334] I/user.sys ram 2375920 71760 121112
[2026-04-08 17:36:36.510][000000024.335] I/user.lua ram 1048568 176216 190984
[2026-04-08 17:36:39.512][000000027.335] I/user.sys ram 2375920 71760 121112
[2026-04-08 17:36:39.524][000000027.336] I/user.lua ram 1048568 176416 190984
[2026-04-08 17:36:42.504][000000030.327] I/user.exmux 设置引脚 pwr2 (23) 为高电平
[2026-04-08 17:36:42.510][000000030.328] I/user.exmux 设置引脚 pwr1 (2) 为高电平
[2026-04-08 17:36:42.513][000000030.328] I/user.exmux 分组 i2c1 打开成功
[2026-04-08 17:36:42.517][000000030.329] I2C_MasterSetup 426:I2C1, Total 65 HCNT 22 LCNT 40
[2026-04-08 17:36:42.522][000000030.329] CSPI_Setup 1924:APB MP 102400000
[2026-04-08 17:36:42.551][000000030.388] I/user.初始化状态 true
[2026-04-08 17:36:42.558][000000030.388] CSPI_Rx 2022:block len 7680, total block 80
[2026-04-08 17:36:42.561][000000030.389] I/user.照片存储路径 /ram/test.jpg
[2026-04-08 17:36:42.564][000000030.389] luat_camera_capture_config 700:0,0,0,0
[2026-04-08 17:36:42.568][000000030.389] luat_camera_capture 676:save file in /ram/test.jpg
[2026-04-08 17:36:42.572][000000030.391] I/user.sys ram 2375920 696088 696224
[2026-04-08 17:36:42.575][000000030.391] I/user.lua ram 1048568 178544 190984
[2026-04-08 17:36:43.126][000000030.955] I/user.摄像头数据 58612
[2026-04-08 17:36:43.138][000000030.956] I/user.拍照完成
[2026-04-08 17:36:43.144][000000030.956] I/user.开始上传图片
[2026-04-08 17:36:43.149][000000030.957] I/user.[excloud]开始文件上传 类型: 1 文件: /ram/test.jpg 大小: 58612
[2026-04-08 17:36:43.155][000000030.957] I/user.[excloud]开始文件上传 类型: 1 文件: test.jpg 大小: 58612
[2026-04-08 17:36:43.160][000000030.958] I/user.[excloud]构建发送数据 23 0 0 
[2026-04-08 17:36:43.164][000000030.959] I/user.[excloud]构建发送数据 784 0 1 
[2026-04-08 17:36:43.169][000000030.960] I/user.[excloud]构建发送数据 785 3 test.jpg 
[2026-04-08 17:36:43.172][000000030.961] I/user.[excloud]构建发送数据 786 0 58612 
[2026-04-08 17:36:43.177][000000030.963] I/user.[excloud]tlv发送数据长度4 36
[2026-04-08 17:36:43.182][000000030.964] I/user.[excloud]构建消息头 y  r7 
[2026-04-08 17:36:43.185][000000030.968] I/user.用户回调函数 send_result {"sequence_num":2,"success":true,"error_msg":"Send successful"}
[2026-04-08 17:36:43.189][000000030.973] I/user.[excloud]数据发送成功 52 字节
[2026-04-08 17:36:43.195][000000030.985] I/user.[excloud]开始发送HTTP请求 URL: https://gps.openluat.com/aircloud/air_up/image
[2026-04-08 17:36:43.199][000000030.989] dns_run 676:gps.openluat.com state 0 id 2 ipv6 0 use dns server2, try 0
[2026-04-08 17:36:43.298][000000031.126] dns_run 693:dns all done ,now stop
[2026-04-08 17:36:43.304][000000031.135] network_default_socket_callback 1123:before process socket 1,event:0xf2000004(发送成功),state:5(在线),wait:3(等待发送完成)
[2026-04-08 17:36:43.308][000000031.135] network_default_socket_callback 1127:after process socket 1,state:5(在线),wait:0(无等待)
[2026-04-08 17:36:43.312][000000031.136] I/user.[excloud]socket cb userdata: 0C1843F0 33554450 0
[2026-04-08 17:36:43.318][000000031.137] I/user.[excloud]socket 发送完成
[2026-04-08 17:36:45.565][000000033.392] I/user.sys ram 2375920 876224 1064884
[2026-04-08 17:36:45.570][000000033.393] I/user.lua ram 1048568 353216 469512
[2026-04-08 17:36:46.436][000000034.268] I/http http close c267f50
[2026-04-08 17:36:46.441][000000034.270] I/user.[excloud]excloud.getip文件上传响应 HTTP Code: 200 Body: {"info":"aircloud./aircloud/air_up/image","code":0,"trace":"code:aircloud./aircloud/air_up/image,  trcace:","log":"^^^","value":{"uri":"/vsa/aircloud_image/FFZDbqsuzrLpbgPfzVd7De/2026-04/867920071472378/20260408173647_test.jpg","size":"57.00KB","thumb":"/vsa/aircloud_image/FFZDbqsuzrLpbgPfzVd7De/2026-04/867920071472378/20260408173647_testt.jpg"}}
[2026-04-08 17:36:46.446][000000034.271] I/user.[excloud]文件上传成功 URL: /vsa/aircloud_image/FFZDbqsuzrLpbgPfzVd7De/2026-04/867920071472378/20260408173647_test.jpg
[2026-04-08 17:36:46.450][000000034.271] I/user.[excloud]构建发送数据 24 0 0 
[2026-04-08 17:36:46.457][000000034.274] I/user.[excloud]构建发送数据 784 0 1 
[2026-04-08 17:36:46.461][000000034.276] I/user.[excloud]构建发送数据 785 3 test.jpg 
[2026-04-08 17:36:46.466][000000034.277] I/user.[excloud]构建发送数据 787 0 0 
[2026-04-08 17:36:46.470][000000034.278] I/user.[excloud]tlv发送数据长度4 36
[2026-04-08 17:36:46.475][000000034.279] I/user.[excloud]构建消息头 y  r7 
[2026-04-08 17:36:46.479][000000034.282] I/user.用户回调函数 send_result {"sequence_num":3,"success":true,"error_msg":"Send successful"}
[2026-04-08 17:36:46.486][000000034.287] I/user.[excloud]数据发送成功 52 字节
[2026-04-08 17:36:46.491][000000034.287] I/user.图片上传成功
[2026-04-08 17:36:46.498][000000034.288] I/user.exmux 设置引脚 pwr2 (23) 为低电平
[2026-04-08 17:36:46.502][000000034.289] I/user.exmux 设置引脚 pwr1 (2) 为低电平
[2026-04-08 17:36:46.507][000000034.289] I/user.exmux 分组 i2c1 关闭成功
[2026-04-08 17:36:46.512][000000034.347] network_default_socket_callback 1123:before process socket 1,event:0xf2000004(发送成功),state:5(在线),wait:3(等待发送完成)
[2026-04-08 17:36:46.519][000000034.347] network_default_socket_callback 1127:after process socket 1,state:5(在线),wait:0(无等待)
[2026-04-08 17:36:46.524][000000034.348] I/user.[excloud]socket cb userdata: 0C1843F0 33554450 0
[2026-04-08 17:36:46.529][000000034.349] I/user.[excloud]socket 发送完成
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

5、登录 https://iot.luatos.com/ 查看拍摄的照片;

![](https://docs.openluat.com/air8101/luatos/app/accessory/AirCAMERA_1020/image/aircloudupload.png)