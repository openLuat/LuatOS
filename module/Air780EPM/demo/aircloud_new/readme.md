# Air780EPM + excloud 云平台通信示例演示说明

本示例基于 **LuatOS** 与 **excloud 扩展库**，使用 **Air780EPM** 开发板演示接入合宙 **AirCloud 云平台**（iot.luatos.com）的完整流程。

## 功能模块介绍

1、main.lua：主程序入口，声明 PROJECT/VERSION，通过 require 统一加载各业务模块，最后进入 sys.run() 事件循环；

2、netdrv_device.lua：网络驱动设备模块，可按需选择 netdrv 目录下的网卡驱动之一（默认 require "netdrv_4g"，其余已注释）：

- netdrv/netdrv_4g.lua：4G 蜂窝网卡驱动（默认，监听 IP_READY/IP_LOSE）；
- netdrv/netdrv_eth_spi.lua：SPI 外挂以太网卡驱动；
- netdrv/netdrv_multiple.lua：多网卡优先级驱动；
- netdrv/netdrv_pc.lua：PC 模拟器网卡驱动；

3、config.lua：全局业务配置模块，集中管理传输协议、服务器发现（getip）、重连策略、心跳、业务上报周期、运维日志等配置项，供其它模块 require 引用；

4、excloud_main.lua：excloud 服务核心模块，负责 excloud.setup / excloud.on / excloud.open、等待网络就绪、自动心跳、连接与鉴权状态管理、全局事件回调及下行消息分发（控制命令分发到 excloud_cmd、运维日志信令分发到 excloud_upload 等）；

5、excloud_cmd.lua：服务器控制命令模块，解析 CONTROL_COMMAND 下发的 JSON 命令，按字段消息 tag 路由到注册的处理器执行（GPIO 电平、设置电压、工作状态、休眠模式、唤醒间隔、联网方式、电池参数等模拟动作），并通过 CONTROL_RESPONSE 逐条回传执行结果；

6、excloud_report.lua：业务数据上报模块，封装单条/批量 TLV 数据上报（温度、湿度、4G 信号强度、电池电压、开机原因、工作状态等模拟数据），提供周期上报与一次性触发上报（trigger_report）；

7、excloud_upload.lua：文件上传模块，支持图片 / 音频上传与运维日志记录上传（云平台信令触发 / 业务主动触发 / 定时自动上传三种方式），鉴权成功后自动上传 test.jpg 图片与 test.mp3 音频；

8、excloud.lua：AirCloud 协议扩展库（位于工程根目录），main.lua 及各业务模块通过 require("excloud") 引用，烧录时需与脚本一同打包，保证 require 可找到；

9、test.jpg / test.mp3：演示用真实图片 / 音频资源，随工程编译进设备 /luadb/ 目录，鉴权成功后自动上传到云平台。

## 演示功能概述

本示例使用 Air780EPM 开发板演示 excloud 扩展库接入合宙 AirCloud 云平台的核心功能，包括：

1. 设备连接与认证：4G 网卡就绪后，自动通过 getip 服务器发现获取服务器地址、端口与鉴权参数，建立 TCP 连接并完成设备鉴权（use_getip 默认开启，无需手动配置 host/port/auth_key）；
2. 心跳保活：鉴权成功后自动启动心跳，默认每 300 秒发送一次时间戳心跳，维持设备在线状态；
3. 业务数据上报：鉴权成功后启动周期上报任务，默认每 60 秒上报一次环境与设备状态等 TLV 数据（温度、湿度、信号强度、电池电压等，示例为模拟数据）；
4. 远程控制：接收平台下发的 CONTROL_COMMAND 控制命令，按字段消息 tag 路由执行并回传 CONTROL_RESPONSE 执行结果（示例内置 GPIO_LEVEL(775)、SET_VOLTAGE(800)、WORK_STATUS(265)、SLEEP_MODE(778)、WAKE_INTERVAL(779)、NETWORK_TYPE(781)、BATTERY_LEVEL(771) 等模拟处理器）；
5. 文件上传：鉴权成功后自动上传真实图片 test.jpg 与真实音频 test.mp3，演示图片 / 音频上传完整链路；运维日志每 60 秒记录一条，默认每 3600 秒自动上传一次（也支持云平台信令触发与业务主动触发）；
6. 自动重连与异常处理：网络断开后按重连策略自动重连，保证链路稳定；各模块对解析失败、执行异常均有防呆与错误码回传处理。

## 演示硬件环境

![img](https://docs.openluat.com/air780epm/luatos/app/driver/eth/image/RFSvb75NRoEWqYxfCRVcVrOKnsf.jpg)

1、Air780EPM 开发板一块 + 可上网的 SIM 卡一张 + 4G 天线一根：

- SIM 卡插入开发板的 SIM 卡槽；
- 4G 天线安装到开发板天线座；

2、TYPE-C USB 数据线一根，开发板与电脑的连接方式为：

- 开发板通过 TYPE-C USB 口供电（外部供电 / USB 供电拨动开关拨到 USB 供电一侧）；
- TYPE-C USB 数据线一端插入开发板的 TYPE-C USB 座子，另一端连接电脑 USB 口（供电、烧录与日志打印共用）。

## 演示软件环境

1、Luatools 下载调试工具：[Luatools 下载](https://docs.openluat.com/air780epm/luatos/common/download/)

2、内核固件：使用最新版本的 [Air780EPM LuatOS 内核固件](https://docs.openluat.com/air780epm/luatos/firmware/780epm_version/)

3、脚本文件：该目录下的 main.lua、config.lua、excloud_main.lua、excloud_cmd.lua、excloud_report.lua、excloud_upload.lua、netdrv_device.lua 及 netdrv 目录下的网卡驱动文件；

4、演示资源文件：test.jpg、test.mp3（与 main.lua 同级，随工程编译进 /luadb/ 目录）。

## 演示核心步骤

1、搭建好硬件环境（开发板 + SIM 卡 + 4G 天线 + USB 连接电脑），开发板上电；

2、网卡驱动选择（可选）：默认使用 4G 网卡，无需修改；如需切换 SPI 以太网卡、多网卡或 PC 模拟器网卡，编辑 netdrv_device.lua，打开对应的 require 行并注释其余行即可；

3、业务参数配置（可选）：config.lua 已给出默认可直接运行的配置（transport="tcp"、use_getip=true、自动重连、自动心跳、周期上报、运维日志自动上传均开启），可按需修改传输协议、心跳间隔、上报周期等参数；

4、烧录固件与脚本：使用 Luatools 先烧录 Air780EPM 内核固件，再新建/选择工程，将 air780epm 目录下的全部 Lua 脚本（含 excloud.lua、test.jpg、test.mp3）加入工程并下载到开发板；

5、启动设备，在 Luatools 上观察日志输出：

```
[2026-09-02 18:04:11.318] 工具提示: soc log port COM4打开成功
[2026-09-02 18:04:11.894] 工具提示: ap log port COM6打开成功
[2026-09-02 18:04:11.920] 工具提示: 用户虚拟串口 COM5
[2026-09-02 18:04:11.945][000000000.000] main_entry 708:SDK base line V017_p001.026
[2026-09-02 18:04:11.950][000000000.007] am_service_init 1388:Air780EPM_A11
[2026-09-02 18:04:11.956][000000000.007] am_get_chip_type 874:6bef6,8,4,6d,8,EC718PM
[2026-09-02 18:04:11.962][000000000.007] am_service_init 1396:APB MP 102400000
[2026-09-02 18:04:11.968][000000000.061] bsp_user_init_io 390:io volt 3.3v 21
[2026-09-02 18:04:11.972][000000000.061] BSP_CustomInit 558:hardfault mode init 4
[2026-09-02 18:04:11.976][000000000.061] Uart_ChangeBR 1461:uart0, 6000000 6028985 26000000 69
[2026-09-02 18:04:11.980][000000000.083] I/pm poweron: Power/Reset
[2026-09-02 18:04:11.983][000000000.083] luat_pm_get_poweron_reason 332:ap 2, cp 2
[2026-09-02 18:04:11.986][000000000.083] I/pm poweron reason: 0 0 5
[2026-09-02 18:04:11.988][000000000.328] self_info 125:model Air780EPM_A11 imei 866597079394597 dbversion 0x75e76a43
[2026-09-02 18:04:11.989][000000000.328] self_info 127:firmware[106] SMS fs 168kbyte script 176kbyte
[2026-09-02 18:04:11.994][000000000.330] D/vfs fopen /apns.bin rb not found
[2026-09-02 18:04:11.999][000000000.330] D/vfs fopen /luadb/apns.bin rb not found
[2026-09-02 18:04:12.005][000000000.330] I/main LuatOS@Air780EPM base 26.04 bsp V2050 64bit
[2026-09-02 18:04:12.011][000000000.331] I/main ROM Build: Aug 21 2026 19:57:11
[2026-09-02 18:04:12.020][000000000.333] W/pins /luadb/pins_air780epm.json not exist!!
[2026-09-02 18:04:12.027][000000000.335] D/main loadlibs luavm 1048568 16736 16736
[2026-09-02 18:04:12.033][000000000.335] D/main loadlibs sys   2371416 107952 108104
[2026-09-02 18:04:12.042][000000000.335] D/main loadlibs psram 2371416 107952 108104
[2026-09-02 18:04:12.049][000000000.404] D/user.httpplus version -> 202607021200
[2026-09-02 18:04:12.058][000000000.417] D/user.exmtn version -> 202608262000
[2026-09-02 18:04:12.066][000000000.422] D/user.excloud version -> 202609011645
[2026-09-02 18:04:12.072][000000000.459] I/user.excloud_demo 周期上报任务启动，等待鉴权成功...
[2026-09-02 18:04:12.080][000000000.472] I/user.excloud_demo 已注册单文件上传结果回调
[2026-09-02 18:04:12.087][000000000.473] I/user.excloud_demo 运维日志记录任务启动
[2026-09-02 18:04:12.096][000000000.473] I/user.excloud_demo 自动上传运维日志任务启动，周期: 3600 秒
[2026-09-02 18:04:12.105][000000000.474] I/user.excloud_demo 真实图片上传任务启动，等待鉴权成功...
[2026-09-02 18:04:12.113][000000000.474] I/user.excloud_demo 真实音频上传任务启动，等待鉴权成功...
[2026-09-02 18:04:12.122][000000000.479] I/user.excloud_demo 等待默认网卡就绪...
[2026-09-02 18:04:12.128][000000000.479] W/user.excloud_demo 等待默认网卡 IP_READY...
[2026-09-02 18:04:12.610][000000001.479] W/user.excloud_demo 等待默认网卡 IP_READY...
[2026-09-02 18:04:13.086][000000002.479] W/user.excloud_demo 等待默认网卡 IP_READY...
[2026-09-02 18:04:14.078][000000003.479] W/user.excloud_demo 等待默认网卡 IP_READY...
[2026-09-02 18:04:15.092][000000004.479] W/user.excloud_demo 等待默认网卡 IP_READY...
[2026-09-02 18:04:16.086][000000005.479] W/user.excloud_demo 等待默认网卡 IP_READY...
[2026-09-02 18:04:17.123][000000006.403] I/mobile sim0 sms ready
[2026-09-02 18:04:17.125][000000006.404] D/mobile cid1, state0
[2026-09-02 18:04:17.126][000000006.404] D/mobile bearer act 0, result 0
[2026-09-02 18:04:17.137][000000006.405] D/mobile NETIF_LINK_ON -> IP_READY
[2026-09-02 18:04:17.141][000000006.406] I/user.netdrv_4g.ip_ready_func IP_READY 10.7.108.242 255.255.255.255 0.0.0.0 nil
[2026-09-02 18:04:17.145][000000006.435] D/mobile TIME_SYNC 0 tm 1788343457
[2026-09-02 18:04:17.153][000000006.479] I/user.excloud_demo 默认网卡已就绪
[2026-09-02 18:04:17.166][000000006.481] I/mobile l_mobile_muid called
[2026-09-02 18:04:17.176][000000006.483] I/mobile l_mobile_muid ret=32
[2026-09-02 18:04:17.180][000000006.483] I/user.[excloud]4G设备 IMEI: 866597079394597 MUID: 20250423004303A306343A5153735787
[2026-09-02 18:04:17.186][000000006.491] D/vfs fopen /exmtn.trc rb not found
[2026-09-02 18:04:17.190][000000006.492] I/user.exmtn 配置变化 false
[2026-09-02 18:04:17.195][000000006.494] D/vfs fopen /hzmtn1.trc rb not found
[2026-09-02 18:04:17.198][000000006.497] D/vfs fopen /hzmtn2.trc rb not found
[2026-09-02 18:04:17.202][000000006.499] D/vfs fopen /hzmtn3.trc rb not found
[2026-09-02 18:04:17.206][000000006.501] D/vfs fopen /hzmtn4.trc rb not found
[2026-09-02 18:04:17.211][000000006.502] I/user.exmtn 配置未变化，文件不存在，创建文件
[2026-09-02 18:04:17.216][000000006.516] luat_pm_get_poweron_reason 332:ap 2, cp 2
[2026-09-02 18:04:17.223][000000006.517] I/user.exmtn 开机原因: 0 0 5 0
[2026-09-02 18:04:17.227][000000006.527] I/user.exmtn 初始化成功: 每个文件 4.00 KB (1 块 × 4096 字节), 总空间 16.00 KB (4 个文件)
[2026-09-02 18:04:17.231][000000006.528] I/user.[excloud]运维日志初始化成功
[2026-09-02 18:04:17.235][000000006.528] I/user.[excloud]setup 初始化成功 设备ID: 866597079394597
[2026-09-02 18:04:17.238][000000006.529] I/user.excloud_demo excloud.setup 成功
[2026-09-02 18:04:17.245][000000006.529] I/user.excloud_demo 已注册 excloud 全局回调
[2026-09-02 18:04:17.248][000000006.530] I/user.[excloud]首次连接，获取服务器信息...
[2026-09-02 18:04:17.252][000000006.530] I/mobile l_mobile_muid called
[2026-09-02 18:04:17.255][000000006.532] I/mobile l_mobile_muid ret=32
[2026-09-02 18:04:17.259][000000006.533] I/user.[excloud]getip 类型: 3 key: unusedkey-866597079394597-20250423004303A306343A5153735787
[2026-09-02 18:04:17.263][000000006.539] D/socket connect to api.luatos.com,443
[2026-09-02 18:04:17.266][000000006.539] dns_run 845:api.luatos.com state 0 id 98 ipv6 0 use dns server0, try 0
[2026-09-02 18:04:17.269][000000006.541] I/user.excloud_demo excloud.setup 已完成，开始周期记录运维日志
[2026-09-02 18:04:17.275][000000006.542] I/user.demo 周期记录 sys_uptime=1788343457 tag=excloud_demo
[2026-09-02 18:04:17.279][000000006.618] dns_run 862:dns all done ,now stop
[2026-09-02 18:04:18.379][000000007.766] I/user.httpplus 服务器已完成响应
[2026-09-02 18:04:18.383][000000007.768] I/user.[excloud]getip响应 HTTP: 200 Body: 
[2026-09-02 18:04:18.387][000000007.769] {"msg":"ok","conninfo":{"ipv4":"124.71.128.165","port":9108,"auth_key":"qmI90LfExPfIVGrSXnyLr1A7IMcvNvXN"},"imginfo":{"url":"https://api.luatos.com/iot/air_up/image","data_key":"f","data_param":{"key":"2YAU1e8x9zfKkRxCVziM1XiXUrcYhKPhajVA","tip":""}},"audinfo":{"url":"https://api.luatos.com/iot/air_up/audio","data_key":"f","data_param":{"key":"2YAU1e8x9zfKkRxCVziM1XiXUrcYhKPhajVA","tip":""}},"mtninfo":{"url":"https://api.luatos.com/iot/air_up/file","data_key":"f","data_param":{"key":"2YAU1e8x9zfKkRxCVziM1XiXUrcYhKPhajVA","tip":""}}}
[2026-09-02 18:04:18.392][000000007.770] I/user.[excloud]TCP/UDP连接信息 host: 124.71.128.165 port: 9108 key: nil
[2026-09-02 18:04:18.397][000000007.771] I/user.[excloud]获取到图片上传信息
[2026-09-02 18:04:18.400][000000007.771] I/user.[excloud]获取到音频上传信息
[2026-09-02 18:04:18.403][000000007.771] I/user.[excloud]获取到运维日志上传信息
[2026-09-02 18:04:18.405][000000007.772] W/user.[excloud]未获取到二维码信息
[2026-09-02 18:04:18.409][000000007.772] I/user.[excloud]通过getip获取到IP地址，更新host: 124.71.128.165
[2026-09-02 18:04:18.413][000000007.773] I/user.[excloud]通过getip获取到端口号，更新port: 9108
[2026-09-02 18:04:18.416][000000007.773] I/user.[excloud]通过getip获取到auth_key，更新auth_key: qmI90LfExPfIVGrSXnyLr1A7IMcvNvXN
[2026-09-02 18:04:18.419][000000007.774] I/user.[excloud]getip 成功: true
[2026-09-02 18:04:18.422][000000007.774] I/user.[excloud]通过getip获取到服务器信息成功，对于用户已手动配置的字段，不会被getip覆盖
[2026-09-02 18:04:18.430][000000007.775] I/user.[excloud]创建TCP连接
[2026-09-02 18:04:18.434][000000007.776] D/socket connect to 124.71.128.165,9108
[2026-09-02 18:04:18.437][000000007.777] I/user.[excloud]TCP连接结果 true false
[2026-09-02 18:04:18.445][000000007.778] I/user.aircloud system excloud服务启动 transport tcp host 124.71.128.165 port 9108
[2026-09-02 18:04:18.448][000000007.787] I/user.[excloud]excloud service started
[2026-09-02 18:04:18.451][000000007.788] I/user.excloud_demo excloud.open 成功
[2026-09-02 18:04:18.454][000000007.818] I/user.[excloud]TCP socket cb userdata: 0C17EC88 33554449 0
[2026-09-02 18:04:18.459][000000007.819] I/user.aircloud net_conn TCP连接成功 host 124.71.128.165 port 9108
[2026-09-02 18:04:18.519][000000007.919] I/user.[excloud]TCP socket TCP连接成功
[2026-09-02 18:04:18.522][000000007.920] I/user.excloud_demo [回调] connect_result {"success":true}
[2026-09-02 18:04:18.525][000000007.921] I/user.excloud_demo 连接成功
[2026-09-02 18:04:18.528][000000007.922] I/mobile l_mobile_muid called
[2026-09-02 18:04:18.534][000000007.923] I/mobile l_mobile_muid ret=32
[2026-09-02 18:04:18.538][000000007.924] I/user.[excloud] 发送鉴权请求
[2026-09-02 18:04:18.541][000000007.925] I/user.[excloud]构建发送数据 field: 16 type: 3 value: qmI90LfExPfIVGrSXnyLr1A7IMcvNvXN-866597079394597-20250423004303A306343A5153735787
[2026-09-02 18:04:18.544][000000007.926] I/user.[excloud]tlv发送数据长度4 85
[2026-09-02 18:04:18.547][000000007.927] I/user.[excloud]构建消息头 seq: 2 len: 85 flags: 18 dev: 0186659707939459
[2026-09-02 18:04:18.552][000000007.930] I/user.excloud_demo [回调] send_result {"sequence_num":2,"success":true,"error_msg":"Send successful"}
[2026-09-02 18:04:18.555][000000007.930] I/user.excloud_demo 发送成功，流水号: 2
[2026-09-02 18:04:18.558][000000007.931] I/user.[excloud]数据发送成功 101 字节
[2026-09-02 18:04:18.582][000000007.975] I/user.[excloud]TCP socket cb userdata: 0C17EC88 33554450 0
[2026-09-02 18:04:18.585][000000007.976] I/user.[excloud]TCP socket 发送完成
[2026-09-02 18:04:18.628][000000008.024] I/user.[excloud]TCP socket cb userdata: 0C17EC88 33554452 0
[2026-09-02 18:04:18.632][000000008.026] I/user.[excloud]解析消息头 设备ID: 866597079394597 序列号: 1 消息长度: 6 协议版本: 0 需要回复: false UDP承载: false 包含auth_key: false
[2026-09-02 18:04:18.635][000000008.027] I/user.[excloud]鉴权成功 ok
[2026-09-02 18:04:18.638][000000008.028] I/user.excloud_demo [回调] auth_result {"sequence_num":1,"success":true,"message":"ok"}
[2026-09-02 18:04:18.665][000000008.028] I/user.excloud_demo 鉴权成功
[2026-09-02 18:04:18.669][000000008.029] I/user.[excloud]excloud 自动心跳已启动，间隔 300 秒
[2026-09-02 18:04:18.671][000000008.030] I/user.excloud_demo [回调] message {"header":{"protocol_version":0,"msg_length":6,"device_id":"866597079394597","need_reply":false,"sequence_num":1,"has_auth_key":false,"is_udp":false},"tlvs":[{"value":"ok","type":3,"raw_value":"ok","length":2,"field":17}]}
[2026-09-02 18:04:18.674][000000008.031] I/user.excloud_demo 收到消息，流水号: 1
[2026-09-02 18:04:18.679][000000008.031] I/user.excloud_demo 下行TLV字段 含义: 17 类型: 3 值: ok
[2026-09-02 18:04:18.682][000000008.032] I/user.excloud_demo 收到鉴权回复（库内部已自动处理，此处仅为演示）
[2026-09-02 18:04:19.065][000000008.459] I/user.excloud_demo 已鉴权成功，开始周期上报，周期: 60 秒
[2026-09-02 18:04:19.083][000000008.460] I/user.[excloud]构建发送数据 field: 256 type: 1 value: 26.500000000000
[2026-09-02 18:04:19.098][000000008.463] I/user.[excloud]构建发送数据 field: 257 type: 1 value: 60.000000000000
[2026-09-02 18:04:19.102][000000008.464] I/user.[excloud]构建发送数据 field: 782 type: 0 value: 23
[2026-09-02 18:04:19.106][000000008.466] I/user.[excloud]构建发送数据 field: 771 type: 0 value: 3700
[2026-09-02 18:04:19.111][000000008.468] I/user.[excloud]构建发送数据 field: 776 type: 0 value: 1
[2026-09-02 18:04:19.116][000000008.470] I/user.[excloud]tlv发送数据长度4 40
[2026-09-02 18:04:19.123][000000008.471] I/user.[excloud]构建消息头 seq: 3 len: 40 flags: 2 dev: 0186659707939459
[2026-09-02 18:04:19.139][000000008.474] I/user.excloud_demo [回调] send_result {"sequence_num":3,"success":true,"error_msg":"Send successful"}
[2026-09-02 18:04:19.163][000000008.474] I/user.excloud_demo 发送成功，流水号: 3
[2026-09-02 18:04:19.186][000000008.475] I/user.[excloud]数据发送成功 56 字节
[2026-09-02 18:04:19.209][000000008.475] I/user.excloud_demo 主动触发运维日志上传
[2026-09-02 18:04:19.214][000000008.481] I/user.[excloud]运维日志文件检查 /hzmtn1.trc true 309
[2026-09-02 18:04:19.218][000000008.485] I/user.[excloud]运维日志文件检查 /hzmtn2.trc true 0
[2026-09-02 18:04:19.225][000000008.490] I/user.[excloud]运维日志文件检查 /hzmtn3.trc true 0
[2026-09-02 18:04:19.230][000000008.494] I/user.[excloud]运维日志文件检查 /hzmtn4.trc true 0
[2026-09-02 18:04:19.233][000000008.494] I/user.[excloud]开始上传运维日志 文件数: 1
[2026-09-02 18:04:19.237][000000008.495] I/user.excloud_demo [回调] mtn_log_upload_start {"file_count":1}
[2026-09-02 18:04:19.241][000000008.495] I/user.excloud_demo 运维日志上传开始，文件数量: 1
[2026-09-02 18:04:19.245][000000008.500] I/user.[excloud]开始文件上传 类型: 3 文件: /hzmtn1.trc 大小: 309
[2026-09-02 18:04:19.248][000000008.500] I/user.[excloud]开始发送HTTP请求 URL: https://api.luatos.com/iot/air_up/file
[2026-09-02 18:04:19.258][000000008.505] D/socket connect to api.luatos.com,443
[2026-09-02 18:04:19.263][000000008.506] dns_run 845:api.luatos.com state 0 id 99 ipv6 0 use dns server0, try 0
[2026-09-02 18:04:19.278][000000008.508] I/user.excloud_demo 鉴权成功，开始检查待上传图片
[2026-09-02 18:04:19.285][000000008.508] I/user.excloud_demo 开始上传真实图片，设备路径: /luadb/test.jpg 平台文件名: test.jpg
[2026-09-02 18:04:19.292][000000008.509] I/user.[excloud]开始文件上传 类型: 1 文件: /luadb/test.jpg 大小: 6292
[2026-09-02 18:04:19.296][000000008.510] I/user.[excloud]构建发送数据 field: 23 type: 0 value: 0
[2026-09-02 18:04:19.303][000000008.512] I/user.[excloud]构建发送数据 field: 784 type: 0 value: 1
[2026-09-02 18:04:19.306][000000008.513] I/user.[excloud]构建发送数据 field: 785 type: 3 value: test.jpg
[2026-09-02 18:04:19.310][000000008.515] I/user.[excloud]构建发送数据 field: 786 type: 0 value: 6292
[2026-09-02 18:04:19.314][000000008.517] I/user.[excloud]tlv发送数据长度4 36
[2026-09-02 18:04:19.317][000000008.518] I/user.[excloud]构建消息头 seq: 4 len: 36 flags: 2 dev: 0186659707939459
[2026-09-02 18:04:19.320][000000008.520] I/user.excloud_demo [回调] send_result {"sequence_num":4,"success":true,"error_msg":"Send successful"}
[2026-09-02 18:04:19.324][000000008.521] I/user.excloud_demo 发送成功，流水号: 4
[2026-09-02 18:04:19.330][000000008.521] I/user.[excloud]数据发送成功 52 字节
[2026-09-02 18:04:19.333][000000008.522] I/user.[excloud]开始发送HTTP请求 URL: https://api.luatos.com/iot/air_up/image
[2026-09-02 18:04:19.336][000000008.524] D/socket connect to api.luatos.com,443
[2026-09-02 18:04:19.339][000000008.526] I/user.excloud_demo 鉴权成功，开始检查待上传音频
[2026-09-02 18:04:19.344][000000008.526] I/user.excloud_demo 开始上传真实音频，设备路径: /luadb/test.mp3 平台文件名: test.mp3
[2026-09-02 18:04:19.348][000000008.527] I/user.[excloud]开始文件上传 类型: 2 文件: /luadb/test.mp3 大小: 39968
[2026-09-02 18:04:19.352][000000008.528] I/user.[excloud]构建发送数据 field: 23 type: 0 value: 0
[2026-09-02 18:04:19.357][000000008.530] I/user.[excloud]构建发送数据 field: 784 type: 0 value: 2
[2026-09-02 18:04:19.365][000000008.531] I/user.[excloud]构建发送数据 field: 785 type: 3 value: test.mp3
[2026-09-02 18:04:19.369][000000008.533] I/user.[excloud]构建发送数据 field: 786 type: 0 value: 39968
[2026-09-02 18:04:19.374][000000008.535] I/user.[excloud]tlv发送数据长度4 36
[2026-09-02 18:04:19.377][000000008.535] I/user.[excloud]构建消息头 seq: 5 len: 36 flags: 2 dev: 0186659707939459
[2026-09-02 18:04:19.381][000000008.538] I/user.excloud_demo [回调] send_result {"sequence_num":5,"success":true,"error_msg":"Send successful"}
[2026-09-02 18:04:19.385][000000008.538] I/user.excloud_demo 发送成功，流水号: 5
[2026-09-02 18:04:19.388][000000008.538] I/user.[excloud]数据发送成功 52 字节
[2026-09-02 18:04:19.398][000000008.539] I/user.[excloud]开始发送HTTP请求 URL: https://api.luatos.com/iot/air_up/audio
[2026-09-02 18:04:19.408][000000008.541] D/socket connect to api.luatos.com,443
[2026-09-02 18:04:19.415][000000008.593] dns_run 862:dns all done ,now stop
[2026-09-02 18:04:19.427][000000008.640] I/user.[excloud]TCP socket cb userdata: 0C17EC88 33554450 0
[2026-09-02 18:04:19.438][000000008.641] I/user.[excloud]TCP socket 发送完成
[2026-09-02 18:04:20.599][000000009.997] I/zbuff create large size: 64 kbyte, trigger force GC
[2026-09-02 18:04:20.646][000000010.041] I/zbuff create large size: 64 kbyte, trigger force GC
[2026-09-02 18:04:20.693][000000010.089] I/zbuff create large size: 64 kbyte, trigger force GC
[2026-09-02 18:04:21.256][000000010.650] I/user.httpplus 服务器已完成响应
[2026-09-02 18:04:21.261][000000010.653] I/user.[excloud]文件上传响应 HTTP Code: 200 Body: {"info":"iot./iot/air_up/file","code":0,"trace":"iot./iot/air_up/file trcace:","log":"^^^","value":{"uri":"/vsa/aircloud_file/F1...
[2026-09-02 18:04:21.265][000000010.655] I/user.[excloud]文件上传成功 URL: /vsa/aircloud_file/F1NewGerZ2mf9NUVEyFvQw/2026-09/866597079394597/20260902180422_hzmtn1.trc
[2026-09-02 18:04:21.272][000000010.660] I/user.[excloud]文件上传完成
[2026-09-02 18:04:21.276][000000010.660] I/user.[excloud]运维日志上传成功 文件: hzmtn1.trc 大小: 309
[2026-09-02 18:04:21.280][000000010.661] I/user.[excloud]构建发送数据 field: 27 type: 4 value: {"index":1,"timestamp":1788343461,"status":1}
[2026-09-02 18:04:21.284][000000010.663] I/user.[excloud]tlv发送数据长度4 49
[2026-09-02 18:04:21.289][000000010.664] I/user.[excloud]构建消息头 seq: 6 len: 49 flags: 2 dev: 0186659707939459
[2026-09-02 18:04:21.292][000000010.667] I/user.excloud_demo [回调] send_result {"sequence_num":6,"success":true,"error_msg":"Send successful"}
[2026-09-02 18:04:21.295][000000010.668] I/user.excloud_demo 发送成功，流水号: 6
[2026-09-02 18:04:21.299][000000010.668] I/user.[excloud]数据发送成功 65 字节
[2026-09-02 18:04:21.305][000000010.671] I/user.[excloud]运维日志文件已清空 /hzmtn1.trc
[2026-09-02 18:04:21.309][000000010.672] I/user.excloud_demo [回调] mtn_log_upload_progress {"file_name":"hzmtn1.trc","current_file":1,"total_files":1,"file_size":309,"status":"success","error_msg":""}
[2026-09-02 18:04:21.315][000000010.673] I/user.excloud_demo 运维日志上传进度，当前: 1 / 1 文件名: hzmtn1.trc 状态: success
[2026-09-02 18:04:21.320][000000010.674] I/user.[excloud]运维日志上传完成 成功文件数: 1 失败文件数: 0
[2026-09-02 18:04:21.331][000000010.674] I/user.excloud_demo [回调] mtn_log_upload_complete {"success_count":1,"failed_count":0,"total_files":1}
[2026-09-02 18:04:21.350][000000010.675] I/user.excloud_demo 运维日志上传完成，成功: 1 失败: 0 总计: 1
[2026-09-02 18:04:21.370][000000010.739] I/user.[excloud]TCP socket cb userdata: 0C17EC88 33554450 0
[2026-09-02 18:04:21.392][000000010.740] I/user.[excloud]TCP socket 发送完成
[2026-09-02 18:04:21.404][000000010.785] I/user.httpplus 服务器已完成响应
[2026-09-02 18:04:21.410][000000010.789] I/user.[excloud]文件上传响应 HTTP Code: 200 Body: {"info":"iot./iot/air_up/image","code":0,"trace":"iot./iot/air_up/image trcace:","log":"^^^","value":{"uri":"/vsa/aircloud_image...
[2026-09-02 18:04:21.420][000000010.790] I/user.[excloud]文件上传成功 URL: /vsa/aircloud_image/F1NewGerZ2mf9NUVEyFvQw/2026-09/866597079394597/20260902180422_test.jpg
[2026-09-02 18:04:21.426][000000010.791] I/user.[excloud]构建发送数据 field: 24 type: 0 value: 0
[2026-09-02 18:04:21.434][000000010.793] I/user.[excloud]构建发送数据 field: 784 type: 0 value: 1
[2026-09-02 18:04:21.441][000000010.795] I/user.[excloud]构建发送数据 field: 785 type: 3 value: test.jpg
[2026-09-02 18:04:21.451][000000010.796] I/user.[excloud]构建发送数据 field: 787 type: 0 value: 0
[2026-09-02 18:04:21.459][000000010.798] I/user.[excloud]tlv发送数据长度4 36
[2026-09-02 18:04:21.473][000000010.799] I/user.[excloud]构建消息头 seq: 7 len: 36 flags: 2 dev: 0186659707939459
[2026-09-02 18:04:21.491][000000010.802] I/user.excloud_demo [回调] send_result {"sequence_num":7,"success":true,"error_msg":"Send successful"}
[2026-09-02 18:04:21.498][000000010.803] I/user.excloud_demo 发送成功，流水号: 7
[2026-09-02 18:04:21.507][000000010.803] I/user.[excloud]数据发送成功 52 字节
[2026-09-02 18:04:21.514][000000010.808] I/user.[excloud]文件上传完成
[2026-09-02 18:04:21.518][000000010.808] I/user.excloud_demo 真实图片上传已触发，结果将通过单文件上传回调反馈
[2026-09-02 18:04:21.529][000000010.853] I/user.[excloud]TCP socket cb userdata: 0C17EC88 33554450 0
[2026-09-02 18:04:21.537][000000010.854] I/user.[excloud]TCP socket 发送完成
[2026-09-02 18:04:21.991][000000011.379] I/user.httpplus 服务器已完成响应
[2026-09-02 18:04:21.995][000000011.382] I/user.[excloud]文件上传响应 HTTP Code: 200 Body: {"info":"iot./iot/air_up/audio","code":0,"trace":"iot./iot/air_up/audio trcace:","log":"^^^","value":{"uri":"/vsa/aircloud_audio...
[2026-09-02 18:04:21.999][000000011.383] I/user.[excloud]文件上传成功 URL: /vsa/aircloud_audio/F1NewGerZ2mf9NUVEyFvQw/2026-09/866597079394597/20260902180423_test.mp3
[2026-09-02 18:04:22.004][000000011.384] I/user.[excloud]构建发送数据 field: 24 type: 0 value: 0
[2026-09-02 18:04:22.010][000000011.385] I/user.[excloud]构建发送数据 field: 784 type: 0 value: 2
[2026-09-02 18:04:22.014][000000011.387] I/user.[excloud]构建发送数据 field: 785 type: 3 value: test.mp3
[2026-09-02 18:04:22.017][000000011.389] I/user.[excloud]构建发送数据 field: 787 type: 0 value: 0
[2026-09-02 18:04:22.021][000000011.390] I/user.[excloud]tlv发送数据长度4 36
[2026-09-02 18:04:22.027][000000011.391] I/user.[excloud]构建消息头 seq: 8 len: 36 flags: 2 dev: 0186659707939459
[2026-09-02 18:04:22.031][000000011.395] I/user.excloud_demo [回调] send_result {"sequence_num":8,"success":true,"error_msg":"Send successful"}
[2026-09-02 18:04:22.033][000000011.395] I/user.excloud_demo 发送成功，流水号: 8
[2026-09-02 18:04:22.037][000000011.396] I/user.[excloud]数据发送成功 52 字节
[2026-09-02 18:04:22.041][000000011.400] I/user.[excloud]文件上传完成
[2026-09-02 18:04:22.045][000000011.400] I/user.excloud_demo 真实音频上传已触发，结果将通过单文件上传回调反馈
[2026-09-02 18:04:22.048][000000011.439] I/user.[excloud]TCP socket cb userdata: 0C17EC88 33554450 0
[2026-09-02 18:04:22.053][000000011.440] I/user.[excloud]TCP socket 发送完成
[2026-09-02 18:05:17.158][000000066.555] I/user.demo 周期记录 sys_uptime=1788343517 tag=excloud_demo
[2026-09-02 18:05:19.079][000000068.476] I/user.[excloud]构建发送数据 field: 256 type: 1 value: 26.500000000000
[2026-09-02 18:05:19.082][000000068.478] I/user.[excloud]构建发送数据 field: 257 type: 1 value: 60.000000000000
[2026-09-02 18:05:19.085][000000068.479] I/user.[excloud]构建发送数据 field: 782 type: 0 value: 23
[2026-09-02 18:05:19.087][000000068.481] I/user.[excloud]构建发送数据 field: 771 type: 0 value: 3700
[2026-09-02 18:05:19.094][000000068.483] I/user.[excloud]构建发送数据 field: 776 type: 0 value: 1
[2026-09-02 18:05:19.097][000000068.485] I/user.[excloud]tlv发送数据长度4 40
[2026-09-02 18:05:19.100][000000068.485] I/user.[excloud]构建消息头 seq: 9 len: 40 flags: 2 dev: 0186659707939459
[2026-09-02 18:05:19.102][000000068.490] I/user.excloud_demo [回调] send_result {"sequence_num":9,"success":true,"error_msg":"Send successful"}
[2026-09-02 18:05:19.105][000000068.490] I/user.excloud_demo 发送成功，流水号: 9
[2026-09-02 18:05:19.106][000000068.491] I/user.[excloud]数据发送成功 56 字节
[2026-09-02 18:05:19.264][000000068.663] I/user.[excloud]TCP socket cb userdata: 0C17EC88 33554450 0
[2026-09-02 18:05:19.267][000000068.664] I/user.[excloud]TCP socket 发送完成
```

正常情况下可依次观察到：4G 网卡 IP_READY → excloud.setup 初始化成功 → getip 获取服务器信息 → TCP 连接成功 → 设备鉴权成功 → 自动心跳启动 → 周期业务上报 → 真实图片/音频自动上传 → 运维日志周期记录与上传等日志；

6、（可选）远程控制演示：登录合宙 AirCloud 平台，在设备详情页对该设备下发控制命令（如 GPIO 电平 775、设置电压 800、工作状态 265、休眠模式 778 等字段），开发板收到后逐条执行并回传执行结果，可在 Luatools 日志中观察"收到服务器控制命令"及"回传控制响应"相关打印；

```
[2026-09-02 18:06:17.165][000000126.563] I/user.demo 周期记录 sys_uptime=1788343577 tag=excloud_demo
[2026-09-02 18:06:19.098][000000128.492] I/user.[excloud]构建发送数据 field: 256 type: 1 value: 26.500000000000
[2026-09-02 18:06:19.101][000000128.494] I/user.[excloud]构建发送数据 field: 257 type: 1 value: 60.000000000000
[2026-09-02 18:06:19.103][000000128.495] I/user.[excloud]构建发送数据 field: 782 type: 0 value: 23
[2026-09-02 18:06:19.105][000000128.497] I/user.[excloud]构建发送数据 field: 771 type: 0 value: 3700
[2026-09-02 18:06:19.106][000000128.499] I/user.[excloud]构建发送数据 field: 776 type: 0 value: 1
[2026-09-02 18:06:19.108][000000128.500] I/user.[excloud]tlv发送数据长度4 40
[2026-09-02 18:06:19.109][000000128.501] I/user.[excloud]构建消息头 seq: 10 len: 40 flags: 2 dev: 0186659707939459
[2026-09-02 18:06:19.113][000000128.505] I/user.excloud_demo [回调] send_result {"sequence_num":10,"success":true,"error_msg":"Send successful"}
[2026-09-02 18:06:19.116][000000128.506] I/user.excloud_demo 发送成功，流水号: 10
[2026-09-02 18:06:19.117][000000128.506] I/user.[excloud]数据发送成功 56 字节
[2026-09-02 18:06:19.267][000000128.659] I/user.[excloud]TCP socket cb userdata: 0C17EC88 33554450 0
[2026-09-02 18:06:19.275][000000128.660] I/user.[excloud]TCP socket 发送完成
[2026-09-02 18:07:17.179][000000186.573] I/user.demo 周期记录 sys_uptime=1788343637 tag=excloud_demo
[2026-09-02 18:07:19.107][000000188.508] I/user.[excloud]构建发送数据 field: 256 type: 1 value: 26.500000000000
[2026-09-02 18:07:19.110][000000188.510] I/user.[excloud]构建发送数据 field: 257 type: 1 value: 60.000000000000
[2026-09-02 18:07:19.112][000000188.511] I/user.[excloud]构建发送数据 field: 782 type: 0 value: 23
[2026-09-02 18:07:19.122][000000188.513] I/user.[excloud]构建发送数据 field: 771 type: 0 value: 3700
[2026-09-02 18:07:19.125][000000188.515] I/user.[excloud]构建发送数据 field: 776 type: 0 value: 1
[2026-09-02 18:07:19.126][000000188.516] I/user.[excloud]tlv发送数据长度4 40
[2026-09-02 18:07:19.128][000000188.517] I/user.[excloud]构建消息头 seq: 11 len: 40 flags: 2 dev: 0186659707939459
[2026-09-02 18:07:19.131][000000188.522] I/user.excloud_demo [回调] send_result {"sequence_num":11,"success":true,"error_msg":"Send successful"}
[2026-09-02 18:07:19.132][000000188.522] I/user.excloud_demo 发送成功，流水号: 11
[2026-09-02 18:07:19.134][000000188.523] I/user.[excloud]数据发送成功 56 字节
[2026-09-02 18:07:19.292][000000188.689] I/user.[excloud]TCP socket cb userdata: 0C17EC88 33554450 0
[2026-09-02 18:07:19.294][000000188.690] I/user.[excloud]TCP socket 发送完成
[2026-09-02 18:07:45.598][000000214.995] I/user.[excloud]TCP socket cb userdata: 0C17EC88 33554452 0
[2026-09-02 18:07:45.602][000000214.997] I/user.[excloud]解析消息头 设备ID: 866597079394597 序列号: 11 消息长度: 51 协议版本: 0 需要回复: false UDP承载: false 包含auth_key: false
[2026-09-02 18:07:45.604][000000214.999] I/user.excloud_demo [回调] message {"header":{"protocol_version":0,"msg_length":51,"device_id":"866597079394597","need_reply":false,"sequence_num":11,"has_auth_key":false,"is_udp":false},"tlvs":[{"value":"[{\"field_meaning\":775,\"data_type\":0,\"value\":1}]","type":3,"raw_value":"[{\"field_meaning\":775,\"data_type\":0,\"value\":1}]","length":47,"field":19}]}
[2026-09-02 18:07:45.607][000000214.999] I/user.excloud_demo 收到消息，流水号: 11
[2026-09-02 18:07:45.610][000000215.000] I/user.excloud_demo 下行TLV字段 含义: 19 类型: 3 值: [{"field_meaning":775,"data_type":0,"value":1}]
[2026-09-02 18:07:45.611][000000215.000] I/user.excloud_demo 收到服务器控制命令，原始值: [{"field_meaning":775,"data_type":0,"value":1}]
[2026-09-02 18:07:45.616][000000215.001] I/user.excloud_demo 控制命令字段数: 1
[2026-09-02 18:07:45.619][000000215.003] I/user.excloud_demo [模拟] 控制 GPIO 电平 电平: 1
[2026-09-02 18:07:45.621][000000215.003] I/user.excloud_demo 字段执行成功: 775 GPIO电平控制成功 值: 1
[2026-09-02 18:07:45.623][000000215.004] I/user.excloud_demo 回传控制响应 [{"msg":"GPIO电平控制成功","result":0,"value":1,"field_meaning":775}]
[2026-09-02 18:07:45.626][000000215.005] I/user.[excloud]构建发送数据 field: 20 type: 5 value: [{"msg":"GPIO电平控制成功","result":0,"value":1,"field_meaning":775}]
[2026-09-02 18:07:45.629][000000215.006] I/user.[excloud]tlv发送数据长度4 79
[2026-09-02 18:07:45.633][000000215.007] I/user.[excloud]构建消息头 seq: 12 len: 79 flags: 2 dev: 0186659707939459
[2026-09-02 18:07:45.635][000000215.010] I/user.excloud_demo [回调] send_result {"sequence_num":12,"success":true,"error_msg":"Send successful"}
[2026-09-02 18:07:45.637][000000215.010] I/user.excloud_demo 发送成功，流水号: 12
[2026-09-02 18:07:45.639][000000215.011] I/user.[excloud]数据发送成功 95 字节
[2026-09-02 18:07:45.675][000000215.069] I/user.[excloud]TCP socket cb userdata: 0C17EC88 33554450 0
[2026-09-02 18:07:45.683][000000215.069] I/user.[excloud]TCP socket 发送完成
[2026-09-02 18:07:59.676][000000229.080] I/user.[excloud]TCP socket cb userdata: 0C17EC88 33554452 0
[2026-09-02 18:07:59.691][000000229.082] I/user.[excloud]解析消息头 设备ID: 866597079394597 序列号: 11 消息长度: 52 协议版本: 0 需要回复: false UDP承载: false 包含auth_key: false
[2026-09-02 18:07:59.697][000000229.083] I/user.excloud_demo [回调] message {"header":{"protocol_version":0,"msg_length":52,"device_id":"866597079394597","need_reply":false,"sequence_num":11,"has_auth_key":false,"is_udp":false},"tlvs":[{"value":"[{\"field_meaning\":800,\"data_type\":0,\"value\":12}]","type":3,"raw_value":"[{\"field_meaning\":800,\"data_type\":0,\"value\":12}]","length":48,"field":19}]}
[2026-09-02 18:07:59.701][000000229.084] I/user.excloud_demo 收到消息，流水号: 11
[2026-09-02 18:07:59.704][000000229.085] I/user.excloud_demo 下行TLV字段 含义: 19 类型: 3 值: [{"field_meaning":800,"data_type":0,"value":12}]
[2026-09-02 18:07:59.714][000000229.085] I/user.excloud_demo 收到服务器控制命令，原始值: [{"field_meaning":800,"data_type":0,"value":12}]
[2026-09-02 18:07:59.720][000000229.086] I/user.excloud_demo 控制命令字段数: 1
[2026-09-02 18:07:59.728][000000229.087] I/user.excloud_demo [模拟] 设置电压 电压: 12
[2026-09-02 18:07:59.734][000000229.088] I/user.excloud_demo 字段执行成功: 800 设置电压成功 值: 12
[2026-09-02 18:07:59.740][000000229.089] I/user.excloud_demo 回传控制响应 [{"msg":"设置电压成功","result":0,"value":12,"field_meaning":800}]
[2026-09-02 18:07:59.750][000000229.089] I/user.[excloud]构建发送数据 field: 20 type: 5 value: [{"msg":"设置电压成功","result":0,"value":12,"field_meaning":800}]
[2026-09-02 18:07:59.762][000000229.091] I/user.[excloud]tlv发送数据长度4 76
[2026-09-02 18:07:59.775][000000229.091] I/user.[excloud]构建消息头 seq: 13 len: 76 flags: 2 dev: 0186659707939459
[2026-09-02 18:07:59.787][000000229.094] I/user.excloud_demo [回调] send_result {"sequence_num":13,"success":true,"error_msg":"Send successful"}
[2026-09-02 18:07:59.800][000000229.095] I/user.excloud_demo 发送成功，流水号: 13
[2026-09-02 18:07:59.812][000000229.096] I/user.[excloud]数据发送成功 92 字节
[2026-09-02 18:07:59.826][000000229.138] I/user.[excloud]TCP socket cb userdata: 0C17EC88 33554450 0
[2026-09-02 18:07:59.837][000000229.139] I/user.[excloud]TCP socket 发送完成
[2026-09-02 18:08:14.392][000000243.796] I/user.[excloud]TCP socket cb userdata: 0C17EC88 33554452 0
[2026-09-02 18:08:14.408][000000243.798] I/user.[excloud]解析消息头 设备ID: 866597079394597 序列号: 11 消息长度: 100 协议版本: 0 需要回复: false UDP承载: false 包含auth_key: false
[2026-09-02 18:08:14.422][000000243.799] I/user.excloud_demo [回调] message {"header":{"protocol_version":0,"msg_length":100,"device_id":"866597079394597","need_reply":false,"sequence_num":11,"has_auth_key":false,"is_udp":false},"tlvs":[{"value":"[{\"field_meaning\":775,\"data_type\":0,\"value\":1},\n {\"field_meaning\":800,\"data_type\":0,\"value\":12}]","type":3,"raw_value":"[{\"field_meaning\":775,\"data_type\":0,\"value\":1},\n {\"field_meaning\":800,\"data_type\":0,\"value\":12}]","length":96,"field":19}]}
[2026-09-02 18:08:14.436][000000243.800] I/user.excloud_demo 收到消息，流水号: 11
[2026-09-02 18:08:14.451][000000243.801] I/user.excloud_demo 下行TLV字段 含义: 19 类型: 3 值: [{"field_meaning":775,"data_type":0,"value":1},
 {"field_meaning":800,"data_type":0,"value":12}]
[2026-09-02 18:08:14.465][000000243.801] I/user.excloud_demo 收到服务器控制命令，原始值: [{"field_meaning":775,"data_type":0,"value":1},
 {"field_meaning":800,"data_type":0,"value":12}]
[2026-09-02 18:08:14.480][000000243.802] I/user.excloud_demo 控制命令字段数: 2
[2026-09-02 18:08:14.493][000000243.804] I/user.excloud_demo [模拟] 控制 GPIO 电平 电平: 1
[2026-09-02 18:08:14.509][000000243.804] I/user.excloud_demo 字段执行成功: 775 GPIO电平控制成功 值: 1
[2026-09-02 18:08:14.522][000000243.805] I/user.excloud_demo [模拟] 设置电压 电压: 12
[2026-09-02 18:08:14.537][000000243.806] I/user.excloud_demo 字段执行成功: 800 设置电压成功 值: 12
[2026-09-02 18:08:14.551][000000243.807] I/user.excloud_demo 回传控制响应 [{"msg":"GPIO电平控制成功","result":0,"value":1,"field_meaning":775},{"msg":"设置电压成功","result":0,"value":12,"field_meaning":800}]
[2026-09-02 18:08:14.565][000000243.807] I/user.[excloud]构建发送数据 field: 20 type: 5 value: [{"msg":"GPIO电平控制成功","result":0,"value":1,"field_meaning":775},{"msg":"设置电压成功","result":0,"value":12,"field_meaning":800}]
[2026-09-02 18:08:14.576][000000243.809] I/user.[excloud]tlv发送数据长度4 150
[2026-09-02 18:08:14.590][000000243.810] I/user.[excloud]构建消息头 seq: 14 len: 150 flags: 2 dev: 0186659707939459
[2026-09-02 18:08:14.602][000000243.813] I/user.excloud_demo [回调] send_result {"sequence_num":14,"success":true,"error_msg":"Send successful"}
[2026-09-02 18:08:14.610][000000243.813] I/user.excloud_demo 发送成功，流水号: 14
[2026-09-02 18:08:14.624][000000243.814] I/user.[excloud]数据发送成功 166 字节
[2026-09-02 18:08:14.636][000000243.873] I/user.[excloud]TCP socket cb userdata: 0C17EC88 33554450 0
[2026-09-02 18:08:14.650][000000243.874] I/user.[excloud]TCP socket 发送完成
[2026-09-02 18:08:17.196][000000246.590] I/user.demo 周期记录 sys_uptime=1788343697 tag=excloud_demo
[2026-09-02 18:08:19.123][000000248.524] I/user.[excloud]构建发送数据 field: 256 type: 1 value: 26.500000000000
[2026-09-02 18:08:19.137][000000248.526] I/user.[excloud]构建发送数据 field: 257 type: 1 value: 60.000000000000
[2026-09-02 18:08:19.151][000000248.528] I/user.[excloud]构建发送数据 field: 782 type: 0 value: 23
[2026-09-02 18:08:19.164][000000248.530] I/user.[excloud]构建发送数据 field: 771 type: 0 value: 3700
[2026-09-02 18:08:19.176][000000248.531] I/user.[excloud]构建发送数据 field: 776 type: 0 value: 1
[2026-09-02 18:08:19.184][000000248.533] I/user.[excloud]tlv发送数据长度4 40
[2026-09-02 18:08:19.191][000000248.534] I/user.[excloud]构建消息头 seq: 15 len: 40 flags: 2 dev: 0186659707939459
[2026-09-02 18:08:19.200][000000248.537] I/user.excloud_demo [回调] send_result {"sequence_num":15,"success":true,"error_msg":"Send successful"}
[2026-09-02 18:08:19.210][000000248.537] I/user.excloud_demo 发送成功，流水号: 15
[2026-09-02 18:08:19.216][000000248.538] I/user.[excloud]数据发送成功 56 字节
[2026-09-02 18:08:19.230][000000248.623] I/user.[excloud]TCP socket cb userdata: 0C17EC88 33554450 0
[2026-09-02 18:08:19.234][000000248.624] I/user.[excloud]TCP socket 发送完成
```

7、（可选）PC 模拟器虚拟设备调试：将 config.lua 中 force_virtual_device 设为 true，并填写 virtual_phone_number / virtual_serial_num，可在 PC 模拟器上以虚拟设备身份体验上述流程。
