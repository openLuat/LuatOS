## 功能模块介绍

1、main.lua：主程序入口；

2、netdrv_device.lua：网卡驱动设备，可以配置使用netdrv文件夹内的四种网卡(单4g网卡，单spi以太网卡，单pc模拟器网卡，多网卡)中的任何一种网卡；

3、excloud.lua： aircloud的实现库

4、excloud_test.lua：aircloud的应用模块，实现了aircloud的应用场景。

## 演示功能概述

使用Air780EHM_Air780EHV_Air780EGH 核心板测试aircloud功能

AirCloud 概述:AirCloud 是 LuatOS 物联网设备云服务通信协议，提供设备连接、数据上报、远程控制和文件上传等核心功能。excloud 扩展库是 AirCloud 协议的实现，通过该库设备可以快速接入云服务平台，实现远程监控和管理。

本demo演示了excloud扩展库的完整使用流程，包括：
1. 设备连接与认证
2. 数据上报与接收
3. 运维日志管理
4. 文件上传功能
5. 心跳保活机制

## 演示硬件环境

![](https://docs.openluat.com/air780ehv/luatos/common/hwenv/image/Air780EHV.png)

1、Air780EHM_Air780EHV_Air780EGH 核心板一块+可上网的sim卡一张+4g天线一根：

- sim卡插入开发板的sim卡槽
- 天线装到开发板上

2、TYPE-C USB数据线一根 ，Air780EHM_Air780EHV_Air780EGH 核心板和数据线的硬件接线方式为：

- Air780EHM_Air780EHV_Air780EGH 核心板通过TYPE-C USB口供电；（外部供电/USB供电 拨动开关 拨到 USB供电一端）
- TYPE-C USB数据线直接插到核心板的TYPE-C USB座子，另外一端连接电脑USB口；

3、可选AirETH_1000配件板一块，Air780EXX核心板和AirETH_1000配件板的硬件接线方式为:

| Air780EXX核心板  |  AirETH_1000配件板 |
| --------------- | ----------------- |
| 3V3             | 3.3v              |
| gnd             | gnd               |
| 86/SPI0CLK      | SCK               |
| 83/SPI0CS       | CSS               |
| 84/SPI0MISO     | SDO               |
| 85/SPI0MOSI     | SDI               |
| 22/GPIO1     | INT               |


## 演示软件环境

1、Luatools下载调试工具

2、[Air780EHM V2018版本固件](https://docs.openluat.com/air780epm/luatos/firmware/version/)

3、[Air780EHV V2018版本固件](https://docs.openluat.com/air780ehv/luatos/firmware/version/)

4、[Air780EGH V2018版本固件](https://docs.openluat.com/air780egh/luatos/firmware/version/)

## 演示核心步骤

1、搭建好硬件环境

2、demo脚本代码netdrv_device.lua中，按照自己的网卡需求启用对应的Lua文件

- 如果需要单4G网卡，打开require "netdrv_4g"，其余注释掉
- 如果需要以太网卡，打开require "netdrv_eth_spi"，其余注释掉
- 如果需要多网卡，打开require "netdrv_multiple"，其余注释掉

3、修改excloud_test.lua文件中excloud.setup接口的相关参数，根据自己需求配置连接协议、是否启用运维日志、项目key、设备类型，是否启用getip等内容。

4、烧录好后，板子开机同时在luatools上查看日志：

```lua
[2025-10-16 17:59:41.066][000000003.897] I/user.[excloud]excloud.setup 初始化成功 设备ID: 862419074072389
[2025-10-16 17:59:41.072][000000003.897] I/user.excloud初始化成功
[2025-10-16 17:59:41.074][000000003.897] I/user.[excloud]首次连接，获取服务器信息...
[2025-10-16 17:59:41.077][000000003.898] I/user.[excloud]excloud.getip 类型: 3 key: VmhtOb81EgZau6YyuuZJzwF6oUNGCbXi-862419074072389
[2025-10-16 17:59:41.080][000000003.904] D/socket connect to gps.openluat.com,443
[2025-10-16 17:59:41.083][000000003.904] dns_run 676:gps.openluat.com state 0 id 1 ipv6 0 use dns server2, try 0
[2025-10-16 17:59:41.144][000000003.969] dns_run 693:dns all done ,now stop
[2025-10-16 17:59:41.706][000000004.539] I/user.httpplus 等待服务器完成响应
[2025-10-16 17:59:41.862][000000004.693] I/user.httpplus 等待服务器完成响应
[2025-10-16 17:59:41.893][000000004.712] I/user.httpplus 服务器已完成响应,开始解析响应
[2025-10-16 17:59:41.924][000000004.745] I/user.[excloud]excloud.getip响应 HTTP Code: 200 Body: {"msg":"ok","conninfo":{"ipv4":"124.71.128.165","port":9108},"imginfo":{"url":"https://gps.openluat.com/iot/aircloud/upload/image","data_key":"f","data_param":{"key":"WMi7G6Kcx8H7UoknB2Knt8btqbDvTAEvAWeQgg","tip":""}},"audinfo":{"url":"https://gps.openluat.com/iot/aircloud/upload/audio","data_key":"f","data_param":{"key":"WMi7G6Kcx8H7UoknB2Knt8btqbDvTAEvAWeQgg","tip":""}}} Body: nil Cannot serialise userdata: type not supported
[2025-10-16 17:59:41.933][000000004.746] I/user.[excloud]excloud.getip响应 JSON: ok
[2025-10-16 17:59:41.938][000000004.747] I/user.[excloud]excloud.getip 124.71.128.165 9108
[2025-10-16 17:59:41.943][000000004.748] I/user.[excloud]excloud.getip 成功: true 结果: {"audinfo":{"data_param":{"key":"WMi7G6Kcx8H7UoknB2Knt8btqbDvTAEvAWeQgg","tip":""},"data_key":"f","url":"https:\/\/gps.openluat.com\/iot\/aircloud\/upload\/audio"},"imginfo":{"data_param":{"key":"WMi7G6Kcx8H7UoknB2Knt8btqbDvTAEvAWeQgg","tip":""},"data_key":"f","url":"https:\/\/gps.openluat.com\/iot\/aircloud\/upload\/image"},"msg":"ok","conninfo":{"ipv4":"124.71.128.165","port":9108}}
[2025-10-16 17:59:41.947][000000004.748] I/user.[excloud]获取服务器信息结果 true {"audinfo":{"data_param":{"key":"WMi7G6Kcx8H7UoknB2Knt8btqbDvTAEvAWeQgg","tip":""},"data_key":"f","url":"https:\/\/gps.openluat.com\/iot\/aircloud\/upload\/audio"},"imginfo":{"data_param":{"key":"WMi7G6Kcx8H7UoknB2Knt8btqbDvTAEvAWeQgg","tip":""},"data_key":"f","url":"https:\/\/gps.openluat.com\/iot\/aircloud\/upload\/image"},"msg":"ok","conninfo":{"ipv4":"124.71.128.165","port":9108}} 图片url https://gps.openluat.com/iot/aircloud/upload/image
[2025-10-16 17:59:41.952][000000004.749] I/user.[excloud]创建TCP连接
[2025-10-16 17:59:41.959][000000004.750] D/socket connect to 124.71.128.165,9108
[2025-10-16 17:59:41.962][000000004.750] network_socket_connect 1605:network 0 local port auto select 50642
[2025-10-16 17:59:41.965][000000004.751] I/user.[excloud]TCP连接结果 true false
[2025-10-16 17:59:41.969][000000004.752] I/user.[excloud]excloud service started
[2025-10-16 17:59:41.976][000000004.752] I/user.excloud服务已开启
[2025-10-16 17:59:41.979][000000004.753] I/user.[excloud]excloud 自动心跳已启动，间隔 300 秒
[2025-10-16 17:59:41.983][000000004.792] network_default_socket_callback 1120:before process socket 1,event:0xf2000009(连接成功),state:3(正在连接),wait:2(等待连接完成)
[2025-10-16 17:59:41.985][000000004.792] network_default_socket_callback 1124:after process socket 1,state:5(在线),wait:0(无等待)
[2025-10-16 17:59:41.997][000000004.793] I/user.[excloud]socket cb userdata: 0C199080 33554449 0
[2025-10-16 17:59:42.002][000000004.794] I/user.[excloud]socket TCP连接成功
[2025-10-16 17:59:42.006][000000004.794] I/user.用户回调函数 connect_result {"success":true}
[2025-10-16 17:59:42.008][000000004.794] I/user.连接成功
[2025-10-16 17:59:42.011][000000004.797] I/user.[excloud]发送数据333 16 3 VmhtOb81EgZau6YyuuZJzwF6oUNGCbXi-862419074072389-20250228145308A686442A0057563473
[2025-10-16 17:59:42.014][000000004.798] I/user.[excloud]tlv发送数据长度4 85
[2025-10-16 17:59:42.020][000000004.799] I/user.[excloud]构建消息头 $ @r8
[2025-10-16 17:59:42.023][000000004.801] I/user.[excloud]发送消息长度 16 85 101 0186241907407238000100550000001130100051566D68744F62383145675A617536597975755A4A7A7746366F554E47436258692D3836323431393037343037323338392D3230323530323238313435333038413638363434324130303537353633343733 202
[2025-10-16 17:59:42.027][000000004.802] I/user.用户回调函数 send_result {"sequence_num":0,"success":true,"error_msg":"Send successful"}
[2025-10-16 17:59:42.031][000000004.802] I/user.发送成功，流水号: 0
[2025-10-16 17:59:42.035][000000004.803] I/user.[excloud]数据发送成功 101 字节
[2025-10-16 17:59:42.041][000000004.848] network_default_socket_callback 1120:before process socket 1,event:0xf2000004(发送成功),state:5(在线),wait:3(等待发送完成)
[2025-10-16 17:59:42.045][000000004.848] network_default_socket_callback 1124:after process socket 1,state:5(在线),wait:0(无等待)
[2025-10-16 17:59:42.048][000000004.849] I/user.[excloud]socket cb userdata: 0C199080 33554450 0
[2025-10-16 17:59:42.057][000000004.849] I/user.[excloud]socket 发送完成
[2025-10-16 17:59:47.455][000000010.283] I/user.开始上传图片
[2025-10-16 17:59:47.461][000000010.284] I/user.[excloud]开始文件上传 类型: 1 文件: test.jpg 大小: 199658
[2025-10-16 17:59:47.465][000000010.286] I/user.[excloud]发送数据333 23 4 
[2025-10-16 17:59:47.471][000000010.287] I/user.[excloud]tlv发送数据长度4 32
[2025-10-16 17:59:47.483][000000010.289] I/user.[excloud]构建消息头 $ @r8
[2025-10-16 17:59:47.486][000000010.290] I/user.[excloud]发送消息长度 16 32 48 018624190740723800020020000000014017001C031000040000000133110008746573742E6A70670312000400030BEA 96
[2025-10-16 17:59:47.509][000000010.291] I/user.用户回调函数 send_result {"sequence_num":1,"success":true,"error_msg":"Send successful"}
[2025-10-16 17:59:47.514][000000010.291] I/user.发送成功，流水号: 1
[2025-10-16 17:59:47.518][000000010.292] I/user.[excloud]数据发送成功 48 字节
[2025-10-16 17:59:47.523][000000010.295] D/socket connect to gps.openluat.com,443
[2025-10-16 17:59:47.529][000000010.296] dns_run 676:gps.openluat.com state 0 id 2 ipv6 0 use dns server2, try 0
[2025-10-16 17:59:47.545][000000010.326] dns_run 693:dns all done ,now stop
[2025-10-16 17:59:47.549][000000010.352] network_default_socket_callback 1120:before process socket 1,event:0xf2000004(发送成功),state:5(在线),wait:3(等待发送完成)
[2025-10-16 17:59:47.554][000000010.352] network_default_socket_callback 1124:after process socket 1,state:5(在线),wait:0(无等待)
[2025-10-16 17:59:47.557][000000010.353] I/user.[excloud]socket cb userdata: 0C199080 33554450 0
[2025-10-16 17:59:47.561][000000010.353] I/user.[excloud]socket 发送完成
[2025-10-16 17:59:49.789][000000012.616] I/user.httpplus 等待服务器完成响应
[2025-10-16 17:59:49.913][000000012.744] I/user.httpplus 等待服务器完成响应
[2025-10-16 17:59:49.961][000000012.792] I/user.httpplus 服务器已完成响应,开始解析响应
[2025-10-16 17:59:50.006][000000012.825] I/user.[excloud]excloud.getip文件上传响应 HTTP Code: 200 Body: {"info":"iot./iot/aircloud/upload/image->iam-server./iam/tenant/getbyoid/6268048492107342913","code":0,"trace":"code:iot./iot/aircloud/upload/image->iam-server./iam/tenant/getbyoid/6268048492107342913,  trcace:clear 1 temp suc infos.","log":"^^^","value":{"uri":"/vsna/luatos/336677/aircloud_image/5411605038321602040/2025-10/test.jpg","size":"194.00KB","thumb":"/vsna/luatos/336677/aircloud_image/5411605038321602040/2025-10/testt.jpg"}}
[2025-10-16 17:59:50.024][000000012.825] Body:
[2025-10-16 17:59:50.035][000000012.825]  nil Cannot serialise userdata: type not supported
[2025-10-16 17:59:50.050][000000012.826] E/user.文件上传失败 服务器返回错误: nil 响应: nil
[2025-10-16 17:59:50.064][000000012.829] I/user.[excloud]发送数据333 24 4 
[2025-10-16 17:59:50.077][000000012.830] I/user.[excloud]tlv发送数据长度4 32
[2025-10-16 17:59:50.090][000000012.831] I/user.[excloud]构建消息头 $ @r8
[2025-10-16 17:59:50.103][000000012.832] I/user.[excloud]发送消息长度 16 32 48 018624190740723800030020000000014018001C031000040000000133110008746573742E6A70670313000400000000 96
[2025-10-16 17:59:50.114][000000012.834] I/user.用户回调函数 send_result {"sequence_num":2,"success":true,"error_msg":"Send successful"}
[2025-10-16 17:59:50.127][000000012.835] I/user.发送成功，流水号: 2
[2025-10-16 17:59:50.140][000000012.835] I/user.[excloud]数据发送成功 48 字节
[2025-10-16 17:59:50.153][000000012.835] E/user.图片上传失败: 服务器返回错误: nil
[2025-10-16 17:59:50.169][000000012.876] network_default_socket_callback 1120:before process socket 1,event:0xf2000004(发送成功),state:5(在线),wait:3(等待发送完成)
[2025-10-16 17:59:50.182][000000012.876] network_default_socket_callback 1124:after process socket 1,state:5(在线),wait:0(无等待)
[2025-10-16 17:59:50.191][000000012.877] I/user.[excloud]socket cb userdata: 0C199080 33554450 0
[2025-10-16 17:59:50.205][000000012.877] I/user.[excloud]socket 发送完成
[2025-10-16 18:00:11.918][000000034.753] I/user.[excloud]发送数据333 782 0 22
[2025-10-16 18:00:11.941][000000034.755] I/user.[excloud]发送数据333 783 3 8 
[2025-10-16 18:00:11.955][000000034.755] I/user.[excloud]tlv发送数据长度4 13
[2025-10-16 18:00:11.969][000000034.757] I/user.[excloud]构建消息头 $ @r8
[2025-10-16 18:00:11.984][000000034.758] I/user.[excloud]发送消息长度 16 13 29 01862419074072380004000D00000001030E000400000016330F000138 58
[2025-10-16 18:00:11.994][000000034.762] I/user.用户回调函数 send_result {"sequence_num":3,"success":true,"error_msg":"Send successful"}
[2025-10-16 18:00:12.010][000000034.762] I/user.发送成功，流水号: 3
[2025-10-16 18:00:12.022][000000034.762] I/user.[excloud]数据发送成功 29 字节
[2025-10-16 18:00:12.035][000000034.763] I/user.数据发送成功
[2025-10-16 18:00:12.049][000000034.873] network_default_socket_callback 1120:before process socket 1,event:0xf2000004(发送成功),state:5(在线),wait:3(等待发送完成)
[2025-10-16 18:00:12.061][000000034.874] network_default_socket_callback 1124:after process socket 1,state:5(在线),wait:0(无等待)
[2025-10-16 18:00:12.075][000000034.874] I/user.[excloud]socket cb userdata: 0C199080 33554450 0
[2025-10-16 18:00:12.086][000000034.875] I/user.[excloud]socket 发送完成
```

