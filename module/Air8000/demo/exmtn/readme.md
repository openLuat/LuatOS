## 功能模块介绍：

1. main.lua：主程序入口

2. exmtn_base ：功能模块，在main.lua中require使用,详细逻辑请看exmtn_base.lua

3. exmtn_aircloud ：功能模块，在main.lua中require使用,详细逻辑请看exmtn_aircloud.lua

4. netdrv_device.lua：网卡驱动设备，可以配置使用netdrv文件夹内的五种网卡(单4g网卡，单wifi网卡，单spi以太网卡，多网卡，pc模拟器上的网卡)中的任何一种网卡

5. netdrv文件夹：五种网卡，单4g网卡、单wifi网卡，、单spi以太网卡、多网卡、pc模拟器上的网卡，供netdrv_device.lua加载配置
   
   
   
   

## 演示功能概述：

exmtn_base核心逻辑：

1.初始化exmtn,并获取配置状态

2.输出日志并写入日志到运维日志文件

3.读取并打印四个运维日志文件中的内容



exmtn_aircloud核心逻辑：

1.联网判断，初始化exmtn

2.输出日志并写入日志到运维日志文件

2.开启excloud服务,并启动心跳保活机制

3.上传运维日志：当服务器下发 "运维日志上传请求" 时， excloud会自动扫描日志文件并上传到云端



## 演示硬件环境：

![](https://docs.openluat.com/air8000/luatos/app/driver/can/image/It2KbkiQMowvrJxPv7Sc1yQknRf.png)



1、Air8000开发板一块+可上网的sim卡一张+4g天线一根+wifi天线一根+网线一根：

* sim卡插入开发板的sim卡槽

* 天线装到开发板上

* 网线一端插入开发板网口，另外一端连接可以上外网的路由器网口

2、TYPE-C USB数据线一根 ，Air8000开发板和数据线的硬件接线方式为：

* Air8000开发板通过TYPE-C USB口供电；（外部供电/USB供电 拨动开关 拨到 USB供电一端）

* TYPE-C USB数据线直接插到开发板的TYPE-C USB座子，另外一端连接电脑USB口；
  
  

## 演示软件环境：

1. Luatools 下载调试工具

2. 固件版本：LuatOS-SoC_V2018_Air8000_1，固件地址，如有最新固件请用最新 [https://docs.openluat.com/air8000/luatos/firmware/](https://docs.openluat.com/air8000/luatos/firmware/)

3. pc 系统 win11（win10 及以上）

## 演示核心步骤：

1、搭建好硬件环境

2、demo脚本代码netdrv_device.lua中，按照自己的网卡需求启用对应的Lua文件

如果需要单4G网卡，打开require "netdrv_4g"，其余注释掉

如果需要单WIFI STA网卡，打开require "netdrv_wifi"，其余注释掉；同时netdrv_wifi.lua中的wlan.connect("茶室-降功耗,找合宙!", "Air123456", 1)，前两个参数，修改为自己测试时wifi热点的名称和密码；注意：仅支持2.4G的wifi，不支持5G的wifi

如果需要以太网卡，打开require "netdrv_eth_spi"，其余注释掉

如果需要多网卡，打开require "netdrv_multiple"，其余注释掉；同时netdrv_multiple.lua中的ssid = "茶室-降功耗,找合宙!", password = "Air123456", 修改为自己测试时wifi热点的名称和密码；注意：仅支持2.4G的wifi，不支持5G的wifi

3、exmtn_cloud.lua脚本中,主函数mtn_cloud()中，excloud.setup的配置参数auth_key，注意修改为自己的项目key

4、main.lua中加载exmtn_base功能模块或者exmtn_aircloud功能模块，二者选择其一即可，另一个注释。

5、Luatools烧录内核固件和修改后的demo脚本代码

6、烧录成功后，代码会自动运行，查看打印日志，如果正常运行，会打印相关日志

exmtn_aircloud.lua运行日志如下：打印写入的运维日志内容(内容按需修改)、运维日志初始化、获取配置状态、创建TCP连接、上传运维日志到云平台等。



```
[2025-12-29 16:18:00.024][000000000.437] I/user.main Air8000_exmtn_demo 001.000.000
[2025-12-29 16:18:00.053][000000000.566] I/user.test mtn info_log 1
[2025-12-29 16:18:00.061][000000000.570] W/user.test mtn warn_log 1
[2025-12-29 16:18:00.067][000000000.573] E/user.test mtn error_log 1
[2025-12-29 16:18:00.071][000000000.575] I/user.
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
 1
[2025-12-29 16:18:00.075][000000000.578] W/user.excloud_task_func wait IP_READY 1 3
[2025-12-29 16:18:00.927][000000001.580] W/user.excloud_task_func wait IP_READY 1 3
[2025-12-29 16:18:01.926][000000002.578] I/user.test mtn info_log 2
[2025-12-29 16:18:01.933][000000002.580] W/user.test mtn warn_log 2
[2025-12-29 16:18:01.937][000000002.582] E/user.test mtn error_log 2
[2025-12-29 16:18:01.943][000000002.584] I/user.
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
 2
[2025-12-29 16:18:01.948][000000002.587] W/user.excloud_task_func wait IP_READY 1 3
[2025-12-29 16:18:02.116][000000002.736] D/mobile cid1, state0
[2025-12-29 16:18:02.119][000000002.736] D/mobile bearer act 0, result 0
[2025-12-29 16:18:02.123][000000002.737] D/mobile NETIF_LINK_ON -> IP_READY
[2025-12-29 16:18:02.130][000000002.738] I/user.netdrv_4g.ip_ready_func IP_READY 10.86.13.93 255.255.255.255 0.0.0.0 nil
[2025-12-29 16:18:02.133][000000002.742] I/user.[excloud]4G设备 IMEI: 866597072472093 MUID: 20250402111619A292646A6746598757
[2025-12-29 16:18:02.137][000000002.754] I/user.exmtn 读取索引 3
[2025-12-29 16:18:02.143][000000002.755] I/user.exmtn 读取块数配置 1
[2025-12-29 16:18:02.149][000000002.755] I/user.exmtn 读取写入方式配置 0
[2025-12-29 16:18:02.153][000000002.755] I/user.exmtn 配置变化 false
[2025-12-29 16:18:02.157][000000002.758] I/user.exmtn 配置未变化，文件存在，继续写入
[2025-12-29 16:18:02.162][000000002.762] I/user.exmtn 初始化成功: 每个文件 4.00 KB (1 块 × 4096 字节), 总空间 16.00 KB (4 个文件)
[2025-12-29 16:18:02.166][000000002.762] I/user.[excloud]运维日志初始化成功
[2025-12-29 16:18:02.169][000000002.763] I/user.[excloud]excloud.setup 初始化成功 设备ID: 866597072472093
[2025-12-29 16:18:02.173][000000002.763] I/user.excloud初始化成功
[2025-12-29 16:18:02.178][000000002.768] I/user.获取配置状态 table: 0C7DCE20
[2025-12-29 16:18:02.181][000000002.768] I/user.当前 exmtn 的配置状态 enabled: true cur_index: 3 block_size: 4096 blocks_per_file: 1 file_limit: 4096 write_way: 0
[2025-12-29 16:18:02.184][000000002.769] I/user.[excloud]首次连接，获取服务器信息...
[2025-12-29 16:18:02.190][000000002.769] I/user.[excloud]excloud.getip 类型: 3 key: Cr8AYD0C2rKqE2vwJ9hWfMMDmQpJuARk-866597072472093
[2025-12-29 16:18:02.194][000000002.775] D/socket connect to gps.openluat.com,443
[2025-12-29 16:18:02.198][000000002.775] dns_run 676:gps.openluat.com state 0 id 1 ipv6 0 use dns server0, try 0
[2025-12-29 16:18:02.200][000000002.801] D/mobile TIME_SYNC 0
[2025-12-29 16:18:02.206][000000002.843] dns_run 693:dns all done ,now stop
[2025-12-29 16:18:02.714][000000003.373] I/user.httpplus 等待服务器完成响应
[2025-12-29 16:18:02.855][000000003.510] I/user.httpplus 等待服务器完成响应
[2025-12-29 16:18:02.861][000000003.522] I/user.httpplus 服务器已完成响应,开始解析响应
[2025-12-29 16:18:02.901][000000003.557] I/user.[excloud]excloud.getip响应 HTTP Code: 200 Body: 
[2025-12-29 16:18:02.910][000000003.557] {"msg":"ok","conninfo":{"ipv4":"124.71.128.165","port":9108},"imginfo":{"url":"https://gps.openluat.com/iot/aircloud/upload/image","data_key":"f","data_param":{"key":"WxiLkjmnR3BYAMjPsp3urdebxf3CbXBhPcBnV6","tip":""}},"audinfo":{"url":"https://gps.openluat.com/iot/aircloud/upload/audio","data_key":"f","data_param":{"key":"WxiLkjmnR3BYAMjPsp3urdebxf3CbXBhPcBnV6","tip":""}},"mtninfo":{"url":"https://gps.openluat.com/iot/aircloud/upload/file","data_key":"f","data_param":{"key":"WxiLkjmnR3BYAMjPsp3urdebxf3CbXBhPcBnV6","tip":""}}}
[2025-12-29 16:18:02.915][000000003.558] I/user.[excloud]excloud.getip响应 HTTP Code: 200 Body: 
[2025-12-29 16:18:02.921][000000003.558] {"msg":"ok","conninfo":{"ipv4":"124.71.128.165","port":9108},"imginfo":{"url":"https://gps.openluat.com/iot/aircloud/upload/image","data_key":"f","data_param":{"key":"WxiLkjmnR3BYAMjPsp3urdebxf3CbXBhPcBnV6","tip":""}},"audinfo":{"url":"https://gps.openluat.com/iot/aircloud/upload/audio","data_key":"f","data_param":{"key":"WxiLkjmnR3BYAMjPsp3urdebxf3CbXBhPcBnV6","tip":""}},"mtninfo":{"url":"https://gps.openluat.com/iot/aircloud/upload/file","data_key":"f","data_param":{"key":"WxiLkjmnR3BYAMjPsp3urdebxf3CbXBhPcBnV6","tip":""}}}
[2025-12-29 16:18:02.927][000000003.559] I/user.[excloud]获取到TCP/UDP连接信息 host: 124.71.128.165 port: 9108
[2025-12-29 16:18:02.931][000000003.560] I/user.[excloud]获取到图片上传信息
[2025-12-29 16:18:02.938][000000003.560] I/user.[excloud]获取到音频上传信息
[2025-12-29 16:18:02.942][000000003.561] I/user.[excloud]获取到运维日志上传信息
[2025-12-29 16:18:02.946][000000003.561] I/user.[excloud]excloud.getip 更新配置: 124.71.128.165 9108
[2025-12-29 16:18:02.951][000000003.561] I/user.[excloud]excloud.getip 成功: true 结果: {"ipv4":"124.71.128.165","port":9108}
[2025-12-29 16:18:02.958][000000003.562] I/user.[excloud]服务器信息获取成功 host: 124.71.128.165 port: 9108 transport: tcp
[2025-12-29 16:18:02.962][000000003.562] I/user.[excloud]创建TCP连接
[2025-12-29 16:18:02.968][000000003.563] D/socket connect to 124.71.128.165,9108
[2025-12-29 16:18:02.973][000000003.564] network_socket_connect 1608:network 0 local port auto select 50642
[2025-12-29 16:18:02.977][000000003.565] I/user.[excloud]TCP连接结果 true false
[2025-12-29 16:18:02.983][000000003.565] I/user.[excloud]excloud service started
[2025-12-29 16:18:02.988][000000003.566] I/user.excloud服务已开启
[2025-12-29 16:18:02.994][000000003.566] I/user.[excloud]excloud 自动心跳已启动，间隔 300 秒
[2025-12-29 16:18:02.998][000000003.566] I/user.自动心跳已启动
[2025-12-29 16:18:03.002][000000003.608] network_default_socket_callback 1123:before process socket 1,event:0xf2000009(连接成功),state:3(正在连接),wait:2(等待连接完成)
[2025-12-29 16:18:03.010][000000003.609] network_default_socket_callback 1127:after process socket 1,state:5(在线),wait:0(无等待)
[2025-12-29 16:18:03.016][000000003.610] I/user.[excloud]socket cb userdata: 0C7DA8D0 33554449 0
[2025-12-29 16:18:03.022][000000003.611] I/user.[excloud]socket TCP连接成功
[2025-12-29 16:18:03.028][000000003.614] I/user.[excloud]构建发送数据 16 3 Cr8AYD0C2rKqE2vwJ9hWfMMDmQpJuARk-866597072472093-20250402111619A292646A6746598757 
[2025-12-29 16:18:03.032][000000003.615] I/user.[excloud]tlv发送数据长度4 85
[2025-12-29 16:18:03.038][000000003.617] I/user.[excloud]构建消息头 e $r	 
[2025-12-29 16:18:03.044][000000003.618] I/user.[excloud]发送消息长度 16 85 101 0186659707247209000200550000001130100051437238415944304332724B71453276774A396857664D4D446D51704A7541526B2D3836363539373037323437323039332D3230323530343032313131363139413239323634364136373436353938373537 202
[2025-12-29 16:18:03.049][000000003.624] I/user.[excloud]数据发送成功 101 字节
[2025-12-29 16:18:03.059][000000003.668] network_default_socket_callback 1123:before process socket 1,event:0xf2000004(发送成功),state:5(在线),wait:3(等待发送完成)
[2025-12-29 16:18:03.062][000000003.669] network_default_socket_callback 1127:after process socket 1,state:5(在线),wait:0(无等待)
[2025-12-29 16:18:03.066][000000003.670] I/user.[excloud]socket cb userdata: 0C7DA8D0 33554450 0
[2025-12-29 16:18:03.071][000000003.670] I/user.[excloud]socket 发送完成
[2025-12-29 16:18:03.926][000000004.587] I/user.test mtn info_log 3
[2025-12-29 16:18:03.931][000000004.592] W/user.test mtn warn_log 3
[2025-12-29 16:18:03.937][000000004.597] E/user.test mtn error_log 3
[2025-12-29 16:18:03.943][000000004.602] I/user.
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
 3
[2025-12-29 16:18:03.948][000000004.607] I/user.
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
 3
[2025-12-29 16:18:05.959][000000006.612] I/user.test mtn info_log 4
[2025-12-29 16:18:05.967][000000006.617] W/user.test mtn warn_log 4
[2025-12-29 16:18:05.974][000000006.621] E/user.test mtn error_log 4
[2025-12-29 16:18:05.981][000000006.626] I/user.
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
 4
...
...
[2025-12-29 16:18:55.246][000000055.907] I/user.
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
 28
[2025-12-29 16:18:57.251][000000057.912] I/user.test mtn info_log 29
[2025-12-29 16:18:57.260][000000057.917] W/user.test mtn warn_log 29
[2025-12-29 16:18:57.267][000000057.922] E/user.test mtn error_log 29
[2025-12-29 16:18:57.274][000000057.927] I/user.
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
 29
[2025-12-29 16:18:57.279][000000057.932] I/user.
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
 29
[2025-12-29 16:18:58.346][000000058.997] network_default_socket_callback 1123:before process socket 1,event:0xf2000005(有新的数据),state:5(在线),wait:5(等待任意网络变化)
[2025-12-29 16:18:58.357][000000058.997] network_default_socket_callback 1127:after process socket 1,state:5(在线),wait:0(无等待)
[2025-12-29 16:18:58.364][000000059.000] I/user.[excloud]socket cb userdata: 0C7DA8D0 33554452 0
[2025-12-29 16:18:58.370][000000059.001] I/user.[excloud]socket 收到数据 20 字节 0186659707247209000100040000000030190000 40
[2025-12-29 16:18:58.375][000000059.002] I/user.[excloud]收到运维日志上传请求
[2025-12-29 16:18:58.382][000000059.003] I/user.开始处理运维日志上传请求 文件总数: 4 最新序号: 4
[2025-12-29 16:18:58.386][000000059.005] I/user.构建运维日志响应TLV 文件总数: 4 最新序号: 4
[2025-12-29 16:18:58.392][000000059.006] I/user.[excloud]构建发送数据 26 4 
[2025-12-29 16:18:58.399][000000059.007] I/user.[excloud]tlv发送数据长度4 20
[2025-12-29 16:18:58.403][000000059.008] I/user.[excloud]构建消息头 e $r	 
[2025-12-29 16:18:58.408][000000059.010] I/user.[excloud]发送消息长度 16 20 36 01866597072472090003001400000001401A001003150004000000040314000400000004 72
[2025-12-29 16:18:58.415][000000059.017] I/user.[excloud]数据发送成功 36 字节
[2025-12-29 16:18:58.419][000000059.017] I/user.运维日志上传响应已发送 文件总数: 4 最新序号: 4
[2025-12-29 16:18:58.427][000000059.081] network_default_socket_callback 1123:before process socket 1,event:0xf2000004(发送成功),state:5(在线),wait:3(等待发送完成)
[2025-12-29 16:18:58.431][000000059.081] network_default_socket_callback 1127:after process socket 1,state:5(在线),wait:0(无等待)
[2025-12-29 16:18:58.436][000000059.082] I/user.[excloud]socket cb userdata: 0C7DA8D0 33554450 0
[2025-12-29 16:18:58.443][000000059.083] I/user.[excloud]socket 发送完成
[2025-12-29 16:18:58.470][000000059.124] I/user.[excloud]构建发送数据 27 4 
[2025-12-29 16:18:58.475][000000059.125] I/user.[excloud]tlv发送数据长度4 35
[2025-12-29 16:18:58.480][000000059.126] I/user.[excloud]构建消息头 e $r	 
[2025-12-29 16:18:58.489][000000059.127] I/user.[excloud]发送消息长度 16 35 51 01866597072472090004002300000001401B001F031700040000000003140004000000013318000B2F687A6D746E312E747263 102
[2025-12-29 16:18:58.494][000000059.132] I/user.[excloud]数据发送成功 51 字节
[2025-12-29 16:18:58.501][000000059.133] I/user.运维日志上传状态发送成功 状态: 0 文件序号: 1 文件名: /hzmtn1.trc 文件大小: 4352
[2025-12-29 16:18:58.506][000000059.133] I/user.[excloud]开始上传运维日志文件 文件: /hzmtn1.trc 大小: 4352
[2025-12-29 16:18:58.512][000000059.136] I/user.[excloud]excloud.upload_mtnlog 文件路径: /hzmtn1.trc 文件名: /hzmtn1.trc
[2025-12-29 16:18:58.521][000000059.137] I/user.[excloud]excloud.upload_mtnlog 文件路径: /hzmtn1.trc 文件名: /hzmtn1.trc
[2025-12-29 16:18:58.527][000000059.140] I/user.[excloud]开始文件上传 类型: 3 文件: /hzmtn1.trc 大小: 4352
[2025-12-29 16:18:58.536][000000059.140] I/user.[excloud]开始文件上传 类型: 3 文件: /hzmtn1.trc 大小: 4352
[2025-12-29 16:18:58.542][000000059.147] I/user.[excloud]开始发送HTTP请求 URL: https://gps.openluat.com/iot/aircloud/upload/file
[2025-12-29 16:18:58.550][000000059.149] dns_run 676:gps.openluat.com state 0 id 2 ipv6 0 use dns server0, try 0
[2025-12-29 16:18:58.556][000000059.190] network_default_socket_callback 1123:before process socket 1,event:0xf2000004(发送成功),state:5(在线),wait:3(等待发送完成)
[2025-12-29 16:18:58.561][000000059.190] network_default_socket_callback 1127:after process socket 1,state:5(在线),wait:0(无等待)
[2025-12-29 16:18:58.569][000000059.191] I/user.[excloud]socket cb userdata: 0C7DA8D0 33554450 0
[2025-12-29 16:18:58.577][000000059.192] I/user.[excloud]socket 发送完成
[2025-12-29 16:18:58.588][000000059.222] dns_run 693:dns all done ,now stop
[2025-12-29 16:18:59.309][000000059.971] I/user.test mtn info_log 30
[2025-12-29 16:18:59.495][000000060.152] W/user.test mtn warn_log 30
[2025-12-29 16:18:59.503][000000060.157] E/user.test mtn error_log 30
[2025-12-29 16:18:59.509][000000060.161] I/user.
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
 30
[2025-12-29 16:18:59.513][000000060.166] I/user.
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
 30
[2025-12-29 16:18:59.523][000000060.173] I/user.[excloud]excloud.getip文件上传响应 HTTP Code: 200 Body: {"info":"iot./iot/aircloud/upload/file","code":0,"trace":"code:iot./iot/aircloud/upload/file,  trcace:","log":"^^^","value":{"uri":"/vsa/aircloud_file/9L4DEkR6SQQpGyHYbR77gU/2025-12/866597072472093/20251229161902_hzmtn1.trc","size":"4.00KB"}}
[2025-12-29 16:18:59.528][000000060.174] I/user.[excloud]文件上传成功 URL: /vsa/aircloud_file/9L4DEkR6SQQpGyHYbR77gU/2025-12/866597072472093/20251229161902_hzmtn1.trc
[2025-12-29 16:18:59.535][000000060.174] I/user.运维日志文件上传成功 文件: /hzmtn1.trc 大小: 4352
[2025-12-29 16:18:59.541][000000060.177] I/user.[excloud]构建发送数据 27 4 
[2025-12-29 16:18:59.544][000000060.178] I/user.[excloud]tlv发送数据长度4 28
[2025-12-29 16:18:59.552][000000060.179] I/user.[excloud]构建消息头 e $r	 
[2025-12-29 16:18:59.558][000000060.181] I/user.[excloud]发送消息长度 16 28 44 01866597072472090005001C00000001401B0018031700040000000103140004000000010316000400001100 88
[2025-12-29 16:18:59.566][000000060.186] I/user.[excloud]数据发送成功 44 字节
[2025-12-29 16:18:59.570][000000060.186] I/user.运维日志上传状态发送成功 状态: 1 文件序号: 1 文件名: /hzmtn1.trc 文件大小: 4352
[2025-12-29 16:18:59.577][000000060.187] I/user.运维日志上传进度 当前文件: 1 总数: 4 文件名: /hzmtn1.trc 状态: success
[2025-12-29 16:18:59.584][000000060.192] I/user.[excloud]构建发送数据 27 4 
[2025-12-29 16:18:59.589][000000060.194] I/user.[excloud]tlv发送数据长度4 35
[2025-12-29 16:18:59.594][000000060.195] I/user.[excloud]构建消息头 e $r	 
[2025-12-29 16:18:59.598][000000060.196] I/user.[excloud]发送消息长度 16 35 51 01866597072472090006002300000001401B001F031700040000000003140004000000023318000B2F687A6D746E322E747263 102
[2025-12-29 16:18:59.604][000000060.200] I/user.[excloud]数据发送成功 51 字节
[2025-12-29 16:18:59.610][000000060.201] I/user.运维日志上传状态发送成功 状态: 0 文件序号: 2 文件名: /hzmtn2.trc 文件大小: 4144
[2025-12-29 16:18:59.616][000000060.201] I/user.[excloud]开始上传运维日志文件 文件: /hzmtn2.trc 大小: 4144
[2025-12-29 16:18:59.623][000000060.205] I/user.[excloud]excloud.upload_mtnlog 文件路径: /hzmtn2.trc 文件名: /hzmtn2.trc
[2025-12-29 16:18:59.628][000000060.205] I/user.[excloud]excloud.upload_mtnlog 文件路径: /hzmtn2.trc 文件名: /hzmtn2.trc
[2025-12-29 16:18:59.634][000000060.208] I/user.[excloud]开始文件上传 类型: 3 文件: /hzmtn2.trc 大小: 4144
[2025-12-29 16:18:59.640][000000060.208] I/user.[excloud]开始文件上传 类型: 3 文件: /hzmtn2.trc 大小: 4144
[2025-12-29 16:18:59.646][000000060.215] I/user.[excloud]开始发送HTTP请求 URL: https://gps.openluat.com/iot/aircloud/upload/file
[2025-12-29 16:18:59.652][000000060.216] dns_run 676:gps.openluat.com state 0 id 3 ipv6 0 use dns server0, try 0
[2025-12-29 16:18:59.656][000000060.251] dns_run 693:dns all done ,now stop
[2025-12-29 16:18:59.660][000000060.254] network_default_socket_callback 1123:before process socket 1,event:0xf2000004(发送成功),state:5(在线),wait:3(等待发送完成)
[2025-12-29 16:18:59.665][000000060.254] network_default_socket_callback 1127:after process socket 1,state:5(在线),wait:3(等待发送完成)
[2025-12-29 16:18:59.672][000000060.332] network_default_socket_callback 1123:before process socket 1,event:0xf2000004(发送成功),state:5(在线),wait:3(等待发送完成)
[2025-12-29 16:18:59.679][000000060.332] network_default_socket_callback 1127:after process socket 1,state:5(在线),wait:0(无等待)
[2025-12-29 16:18:59.685][000000060.334] I/user.[excloud]socket cb userdata: 0C7DA8D0 33554450 0
[2025-12-29 16:18:59.689][000000060.335] I/user.[excloud]socket 发送完成
[2025-12-29 16:19:00.413][000000061.069] I/user.[excloud]excloud.getip文件上传响应 HTTP Code: 200 Body: {"info":"iot./iot/aircloud/upload/file","code":0,"trace":"code:iot./iot/aircloud/upload/file,  trcace:","log":"^^^","value":{"uri":"/vsa/aircloud_file/9L4DEkR6SQQpGyHYbR77gU/2025-12/866597072472093/20251229161903_hzmtn2.trc","size":"4.00KB"}}
[2025-12-29 16:19:00.421][000000061.070] I/user.[excloud]文件上传成功 URL: /vsa/aircloud_file/9L4DEkR6SQQpGyHYbR77gU/2025-12/866597072472093/20251229161903_hzmtn2.trc
[2025-12-29 16:19:00.427][000000061.070] I/user.运维日志文件上传成功 文件: /hzmtn2.trc 大小: 4144
[2025-12-29 16:19:00.434][000000061.074] I/user.[excloud]构建发送数据 27 4 
[2025-12-29 16:19:00.438][000000061.075] I/user.[excloud]tlv发送数据长度4 28
[2025-12-29 16:19:00.441][000000061.076] I/user.[excloud]构建消息头 e $r	 
[2025-12-29 16:19:00.448][000000061.077] I/user.[excloud]发送消息长度 16 28 44 01866597072472090007001C00000001401B0018031700040000000103140004000000020316000400001030 88
[2025-12-29 16:19:00.453][000000061.082] I/user.[excloud]数据发送成功 44 字节
[2025-12-29 16:19:00.457][000000061.083] I/user.运维日志上传状态发送成功 状态: 1 文件序号: 2 文件名: /hzmtn2.trc 文件大小: 4144
[2025-12-29 16:19:00.463][000000061.084] I/user.运维日志上传进度 当前文件: 2 总数: 4 文件名: /hzmtn2.trc 状态: success
[2025-12-29 16:19:00.468][000000061.089] I/user.[excloud]构建发送数据 27 4 
[2025-12-29 16:19:00.472][000000061.090] I/user.[excloud]tlv发送数据长度4 35
[2025-12-29 16:19:00.478][000000061.092] I/user.[excloud]构建消息头 e $r	 
[2025-12-29 16:19:00.483][000000061.093] I/user.[excloud]发送消息长度 16 35 51 01866597072472090008002300000001401B001F031700040000000003140004000000033318000B2F687A6D746E332E747263 102
[2025-12-29 16:19:00.487][000000061.097] I/user.[excloud]数据发送成功 51 字节
[2025-12-29 16:19:00.493][000000061.098] I/user.运维日志上传状态发送成功 状态: 0 文件序号: 3 文件名: /hzmtn3.trc 文件大小: 4352
[2025-12-29 16:19:00.498][000000061.098] I/user.[excloud]开始上传运维日志文件 文件: /hzmtn3.trc 大小: 4352
[2025-12-29 16:19:00.502][000000061.101] I/user.[excloud]excloud.upload_mtnlog 文件路径: /hzmtn3.trc 文件名: /hzmtn3.trc
[2025-12-29 16:19:00.508][000000061.102] I/user.[excloud]excloud.upload_mtnlog 文件路径: /hzmtn3.trc 文件名: /hzmtn3.trc
[2025-12-29 16:19:00.512][000000061.105] I/user.[excloud]开始文件上传 类型: 3 文件: /hzmtn3.trc 大小: 4352
[2025-12-29 16:19:00.518][000000061.105] I/user.[excloud]开始文件上传 类型: 3 文件: /hzmtn3.trc 大小: 4352
[2025-12-29 16:19:00.524][000000061.113] I/user.[excloud]开始发送HTTP请求 URL: https://gps.openluat.com/iot/aircloud/upload/file
[2025-12-29 16:19:00.530][000000061.115] dns_run 676:gps.openluat.com state 0 id 4 ipv6 0 use dns server0, try 0
[2025-12-29 16:19:00.535][000000061.129] dns_run 693:dns all done ,now stop
[2025-12-29 16:19:00.550][000000061.141] network_default_socket_callback 1123:before process socket 1,event:0xf2000004(发送成功),state:5(在线),wait:3(等待发送完成)
[2025-12-29 16:19:00.558][000000061.141] network_default_socket_callback 1127:after process socket 1,state:5(在线),wait:3(等待发送完成)
[2025-12-29 16:19:00.563][000000061.189] network_default_socket_callback 1123:before process socket 1,event:0xf2000004(发送成功),state:5(在线),wait:3(等待发送完成)
[2025-12-29 16:19:00.572][000000061.189] network_default_socket_callback 1127:after process socket 1,state:5(在线),wait:0(无等待)
[2025-12-29 16:19:00.577][000000061.190] I/user.[excloud]socket cb userdata: 0C7DA8D0 33554450 0
[2025-12-29 16:19:00.586][000000061.191] I/user.[excloud]socket 发送完成
[2025-12-29 16:19:01.272][000000061.932] I/user.[excloud]excloud.getip文件上传响应 HTTP Code: 200 Body: {"info":"iot./iot/aircloud/upload/file","code":0,"trace":"code:iot./iot/aircloud/upload/file,  trcace:","log":"^^^","value":{"uri":"/vsa/aircloud_file/9L4DEkR6SQQpGyHYbR77gU/2025-12/866597072472093/20251229161904_hzmtn3.trc","size":"4.00KB"}}
[2025-12-29 16:19:01.280][000000061.933] I/user.[excloud]文件上传成功 URL: /vsa/aircloud_file/9L4DEkR6SQQpGyHYbR77gU/2025-12/866597072472093/20251229161904_hzmtn3.trc
[2025-12-29 16:19:01.286][000000061.933] I/user.运维日志文件上传成功 文件: /hzmtn3.trc 大小: 4352
[2025-12-29 16:19:01.291][000000061.937] I/user.[excloud]构建发送数据 27 4 
[2025-12-29 16:19:01.295][000000061.938] I/user.[excloud]tlv发送数据长度4 28
[2025-12-29 16:19:01.300][000000061.939] I/user.[excloud]构建消息头 e $r	 
[2025-12-29 16:19:01.306][000000061.940] I/user.[excloud]发送消息长度 16 28 44 01866597072472090009001C00000001401B0018031700040000000103140004000000030316000400001100 88
[2025-12-29 16:19:01.310][000000061.945] I/user.[excloud]数据发送成功 44 字节
[2025-12-29 16:19:01.313][000000061.946] I/user.运维日志上传状态发送成功 状态: 1 文件序号: 3 文件名: /hzmtn3.trc 文件大小: 4352
[2025-12-29 16:19:01.317][000000061.947] I/user.运维日志上传进度 当前文件: 3 总数: 4 文件名: /hzmtn3.trc 状态: success
[2025-12-29 16:19:01.324][000000061.952] I/user.[excloud]构建发送数据 27 4 
[2025-12-29 16:19:01.328][000000061.953] I/user.[excloud]tlv发送数据长度4 35
[2025-12-29 16:19:01.333][000000061.954] I/user.[excloud]构建消息头 e $r	 
[2025-12-29 16:19:01.339][000000061.956] I/user.[excloud]发送消息长度 16 35 51 0186659707247209000A002300000001401B001F031700040000000003140004000000043318000B2F687A6D746E342E747263 102
[2025-12-29 16:19:01.342][000000061.960] I/user.[excloud]数据发送成功 51 字节
[2025-12-29 16:19:01.346][000000061.960] I/user.运维日志上传状态发送成功 状态: 0 文件序号: 4 文件名: /hzmtn4.trc 文件大小: 4144
[2025-12-29 16:19:01.354][000000061.961] I/user.[excloud]开始上传运维日志文件 文件: /hzmtn4.trc 大小: 4144
[2025-12-29 16:19:01.357][000000061.964] I/user.[excloud]excloud.upload_mtnlog 文件路径: /hzmtn4.trc 文件名: /hzmtn4.trc
[2025-12-29 16:19:01.361][000000061.965] I/user.[excloud]excloud.upload_mtnlog 文件路径: /hzmtn4.trc 文件名: /hzmtn4.trc
[2025-12-29 16:19:01.368][000000061.967] I/user.[excloud]开始文件上传 类型: 3 文件: /hzmtn4.trc 大小: 4144
[2025-12-29 16:19:01.373][000000061.968] I/user.[excloud]开始文件上传 类型: 3 文件: /hzmtn4.trc 大小: 4144
[2025-12-29 16:19:01.377][000000061.975] I/user.[excloud]开始发送HTTP请求 URL: https://gps.openluat.com/iot/aircloud/upload/file
[2025-12-29 16:19:01.384][000000061.977] dns_run 676:gps.openluat.com state 0 id 5 ipv6 0 use dns server0, try 0
[2025-12-29 16:19:01.387][000000061.992] dns_run 693:dns all done ,now stop
[2025-12-29 16:19:01.391][000000062.010] network_default_socket_callback 1123:before process socket 1,event:0xf2000004(发送成功),state:5(在线),wait:3(等待发送完成)
[2025-12-29 16:19:01.397][000000062.010] network_default_socket_callback 1127:after process socket 1,state:5(在线),wait:3(等待发送完成)
[2025-12-29 16:19:01.401][000000062.058] network_default_socket_callback 1123:before process socket 1,event:0xf2000004(发送成功),state:5(在线),wait:3(等待发送完成)
[2025-12-29 16:19:01.406][000000062.058] network_default_socket_callback 1127:after process socket 1,state:5(在线),wait:0(无等待)
[2025-12-29 16:19:01.411][000000062.059] I/user.[excloud]socket cb userdata: 0C7DA8D0 33554450 0
[2025-12-29 16:19:01.417][000000062.060] I/user.[excloud]socket 发送完成
[2025-12-29 16:19:01.811][000000062.472] I/user.test mtn info_log 31
[2025-12-29 16:19:01.819][000000062.477] W/user.test mtn warn_log 31
[2025-12-29 16:19:01.826][000000062.482] E/user.test mtn error_log 31
[2025-12-29 16:19:01.833][000000062.487] I/user.
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
 31
[2025-12-29 16:19:01.837][000000062.492] I/user.
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
 31
[2025-12-29 16:19:02.151][000000062.808] I/user.[excloud]excloud.getip文件上传响应 HTTP Code: 200 Body: {"info":"iot./iot/aircloud/upload/file","code":0,"trace":"code:iot./iot/aircloud/upload/file,  trcace:","log":"^^^","value":{"uri":"/vsa/aircloud_file/9L4DEkR6SQQpGyHYbR77gU/2025-12/866597072472093/20251229161905_hzmtn4.trc","size":"4.00KB"}}
[2025-12-29 16:19:02.162][000000062.809] I/user.[excloud]文件上传成功 URL: /vsa/aircloud_file/9L4DEkR6SQQpGyHYbR77gU/2025-12/866597072472093/20251229161905_hzmtn4.trc
[2025-12-29 16:19:02.169][000000062.809] I/user.运维日志文件上传成功 文件: /hzmtn4.trc 大小: 4144
[2025-12-29 16:19:02.175][000000062.813] I/user.[excloud]构建发送数据 27 4 
[2025-12-29 16:19:02.180][000000062.814] I/user.[excloud]tlv发送数据长度4 28
[2025-12-29 16:19:02.184][000000062.815] I/user.[excloud]构建消息头 e $r	 
[2025-12-29 16:19:02.189][000000062.816] I/user.[excloud]发送消息长度 16 28 44 0186659707247209000B001C00000001401B0018031700040000000103140004000000040316000400001030 88
[2025-12-29 16:19:02.195][000000062.821] I/user.[excloud]数据发送成功 44 字节
[2025-12-29 16:19:02.203][000000062.822] I/user.运维日志上传状态发送成功 状态: 1 文件序号: 4 文件名: /hzmtn4.trc 文件大小: 4144
[2025-12-29 16:19:02.209][000000062.823] I/user.运维日志上传进度 当前文件: 4 总数: 4 文件名: /hzmtn4.trc 状态: success
[2025-12-29 16:19:02.217][000000062.823] I/user.运维日志上传完成 成功: 4 失败: 0 总计: 4
[2025-12-29 16:19:02.249][000000062.824] I/user.运维日志上传完成 成功: 4 失败: 0 总计: 4
[2025-12-29 16:19:02.278][000000062.880] network_default_socket_callback 1123:before process socket 1,event:0xf2000004(发送成功),state:5(在线),wait:3(等待发送完成)
[2025-12-29 16:19:02.284][000000062.880] network_default_socket_callback 1127:after process socket 1,state:5(在线),wait:0(无等待)
[2025-12-29 16:19:02.290][000000062.881] I/user.[excloud]socket cb userdata: 0C7DA8D0 33554450 0
[2025-12-29 16:19:02.294][000000062.882] I/user.[excloud]socket 发送完成


```

下图是操作服务器平台下发"运维日志上传请求"指令 ，并查看运维日志上传到平台的步骤：

 登录[aircloud云平台](https://iot.luatos.com/)-->

1、点击AirCloud,选择AirCloud运维日志(公测)-->

2、在AirCloud运维日志(公测)页面-->

3、输入设备的imei号-->

4、单击通知设备上传运维日志-->

5、页面显示命令下发成功、同时luatools工具打印"收到运维日志上传请求"的日志-->

6、单击更新-->

7、查看上传的运维日志文件、luatools工具也会打印"发送完成"的日志-->

8、下载上传到平台的运维日志进行查看

![](https://docs.openluat.com/air8000/luatos/app/image/exmtn_aircloud.jpg)



exmtn_base.lua运行日志如下：打印写入的运维日志、exmtn初始化、获取配置状态、读取运维日志文件的内容等。

```
[2025-12-22 12:34:16.214][000000000.773] I/user.main Air8000_exmtn_demo 001.000.000
[2025-12-22 12:34:16.231][000000000.805] I/user.exmtn 读取索引 3
[2025-12-22 12:34:16.254][000000000.805] I/user.exmtn 读取块数配置 1
[2025-12-22 12:34:16.271][000000000.806] I/user.exmtn 读取写入方式配置 0
[2025-12-22 12:34:16.287][000000000.806] I/user.exmtn 配置变化 false
[2025-12-22 12:34:16.304][000000000.809] I/user.exmtn 配置未变化，文件存在，继续写入
[2025-12-22 12:34:16.320][000000000.813] I/user.exmtn 初始化成功: 每个文件 4.00 KB (1 块 × 4096 字节), 总空间 16.00 KB (4 个文件)
[2025-12-22 12:34:16.336][000000000.813] I/user.初始化结果 true
[2025-12-22 12:34:16.350][000000000.814] I/user.获取配置状态 table: 0C7F2838
[2025-12-22 12:34:16.364][000000000.815] I/user.当前 exmtn 的配置状态 enabled: true cur_index: 3 block_size: 4096 blocks_per_file: 1 file_limit: 4096 write_way: 0
[2025-12-22 12:34:16.378][000000000.815] I/user.test mtn info_log 1
[2025-12-22 12:34:16.392][000000000.820] W/user.test mtn warn_log 1
[2025-12-22 12:34:16.406][000000000.825] E/user.test mtn error_log 1
[2025-12-22 12:34:16.420][000000000.831] I/user.
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
 1
[2025-12-22 12:34:17.639][000000002.311] D/mobile cid1, state0
[2025-12-22 12:34:17.654][000000002.312] D/mobile bearer act 0, result 0
[2025-12-22 12:34:17.662][000000002.312] D/mobile NETIF_LINK_ON -> IP_READY
[2025-12-22 12:34:17.671][000000002.314] I/user.netdrv_4g.ip_ready_func IP_READY 10.211.12.17 255.255.255.255 0.0.0.0 nil
[2025-12-22 12:34:17.679][000000002.329] D/mobile TIME_SYNC 0
[2025-12-22 12:34:18.124][000000002.836] I/user.test mtn info_log 2
[2025-12-22 12:34:18.133][000000002.841] W/user.test mtn warn_log 2
[2025-12-22 12:34:18.140][000000002.846] E/user.test mtn error_log 2
[2025-12-22 12:34:18.154][000000002.851] I/user.
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
 2
[2025-12-22 12:34:20.153][000000004.857] I/user.test mtn info_log 3
[2025-12-22 12:34:20.162][000000004.862] W/user.test mtn warn_log 3
[2025-12-22 12:34:20.173][000000004.867] E/user.test mtn error_log 3
[2025-12-22 12:34:20.187][000000004.872] I/user.
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
 3
[2025-12-22 12:34:21.136][000000005.835] I/user.mtn_read 开始读取运维日志文件...
[2025-12-22 12:34:21.157][000000005.840] I/user.mtn_read 文件 /hzmtn1.trc 内容: 
[2025-12-22 12:34:21.166][000000005.840] [2025-12-22 12:33:29.586][000000014.586] E/user.test mtn error_log 8
[2025-12-22 12:33:30.752][000000014.752] I/user.
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
 8
[2025-12-22 12:33:32.757][000000016.757] I/user.test mtn info_log 9
[2025-12-22 12:33:32.761][000000016.761] W/user.test mtn warn_log 9
[2025-12-22 12:33:32.768][000000016.768] E/user.test mtn error_log 9
[2025-12-22 12:33:32.773][000000016.773] I/user.
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
 9
...
...
[2025-12-22 12:33:56.028][000000041.028] I/user.test mtn info_log 21
[2025-12-22 12:33:56.033][000000041.033] W/user.test mtn warn_log 21
[2025-12-22 12:33:56.038][000000041.038] E/user.test mtn error_log 21
[2025-12-22 12:33:56.044][000000041.044] I/user.
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
 21
[2025-12-22 12:33:58.048][000000043.048] I/user.test mtn info_log 22
[2025-12-22 12:33:58.053][000000043.053] W/user.test mtn warn_log 22
[2025-12-22 12:33:58.058][000000043.058] E/user.test mtn error_log 22
[2025-12-22 12:33:58.063][000000043.063] I/user.
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
 22

[2025-12-22 12:34:21.202][000000005.851] I/user.mtn_read 文件 /hzmtn3.trc 为空
[2025-12-22 12:34:21.209][000000005.855] I/user.mtn_read 文件 /hzmtn4.trc 内容: 
[2025-12-22 12:34:21.216][000000005.856] [2000-01-01 08:00:00.368][000000000.368] I/user.test mtn info_log 1
[2000-01-01 08:00:00.373][000000000.373] W/user.test mtn warn_log 1
[2000-01-01 08:00:00.377][000000000.377] E/user.test mtn error_log 1
[2000-01-01 08:00:00.383][000000000.383] I/user.
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
 1
[2000-01-01 08:00:02.389][000000002.389] I/user.test mtn info_log 2
[2000-01-01 08:00:02.394][000000002.394] W/user.test mtn warn_log 2
[2000-01-01 08:00:02.399][000000002.399] E/user.test mtn error_log 2
[2000-01-01 08:00:02.404][000000002.404] I/user.
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
 2
[2025-12-22 12:33:19.409][000000004.409] I/user.test mtn info_log 3
[2025-12-22 12:33:19.415][000000004.415] W/user.test mtn warn_log 3
[2025-12-22 12:33:19.420][000000004.420] E/user.test mtn error_log 3
[2025-12-22 12:33:19.425][000000004.425] I/user.
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
 3
[2025-12-22 12:33:21.430][000000006.430] I/user.test mtn info_log 4
[2025-12-22 12:33:21.435][000000006.435] W/user.test mtn warn_log 4
[2025-12-22 12:33:21.441][000000006.441] E/user.test mtn error_log 4
[2025-12-22 12:33:21.446][000000006.446] I/user.
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
 4
[2025-12-22 12:33:23.451][000000008.451] I/user.test mtn info_log 5
[2025-12-22 12:33:23.456][000000008.456] W/user.test mtn warn_log 5
[2025-12-22 12:33:23.461][000000008.461] E/user.test mtn error_log 5
[2025-12-22 12:33:23.467][000000008.467] I/user.
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
 5
[2025-12-22 12:33:25.472][000000010.472] I/user.test mtn info_log 6
[2025-12-22 12:33:25.478][000000010.478] W/user.test mtn warn_log 6
[2025-12-22 12:33:25.482][000000010.482] E/user.test mtn error_log 6
[2025-12-22 12:33:25.488][000000010.488] I/user.
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
 6
[2025-12-22 12:33:27.493][000000012.493] I/user.test mtn info_log 7
[2025-12-22 12:33:27.499][000000012.499] W/user.test mtn warn_log 7
[2025-12-22 12:33:27.504][000000012.504] E/user.test mtn error_log 7
[2025-12-22 12:33:27.510][000000012.510] I/user.
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
 7
[2025-12-22 12:33:29.515][000000014.515] I/user.test mtn info_log 8
[2025-12-22 12:33:29.521][000000014.521] W/user.test mtn warn_log 8

[2025-12-22 12:34:21.225][000000005.857] I/user.mtn_read 运维日志文件读取完成

```
