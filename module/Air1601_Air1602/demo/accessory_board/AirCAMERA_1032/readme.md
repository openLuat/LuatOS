# AirCAMERA_1032 DEMO

## 演示功能概述

本示例主要是展示 Air1601 + AirCAMERA_1032 USB摄像头的使用，支持实时预览到LCD屏幕、拍照后上传到电脑(UART)、拍照后上传到合宙IOT云平台、H.264编码与上传。

1、main.lua：主程序入口

2、preview.lua：摄像头实时预览到LCD屏幕，支持四种fit模式实时切换（center / contain / cover / stretch）

3、photo_uart_post.lua：执行拍照后，LCD显示图片，同时通过UART上传照片到电脑

4、photo_to_aircloud.lua：执行拍照后，LCD显示图片，同时上传到合宙IOT云平台

5、h264_power_test.lua：H.264编码与上传（支持仅编码、编码+本地保存、编码+串口上传、编码+AirCloud上传四种模式）

6、lcd_drv.lua：LCD屏幕驱动（1024x600分辨率）

7、netdrv/：网络驱动目录（支持WIFI、以太网、4G、多网卡等）

8、netdrv_device.lua：网络驱动选择器

注意：preview.lua、photo_uart_post.lua、photo_to_aircloud.lua、h264_power_test.lua 只能打开一个不能同时打开

## 演示功能概述

### 1、主程序入口模块（main.lua）
- 初始化项目信息和版本号
- 初始化看门狗，并定时喂狗
- 加载 netdrv_device.lua（可选，云平台业务需要）
- 默认已启用 photo_uart_post.lua（拍照+LCD显示+UART上传），如需其他业务模块请注释/取消注释切换

### 2、网络驱动模块（netdrv/netdrv_device.lua）
- netdrv_wifi.lua：WIFI连接
- netdrv_eth_spi.lua：SPI以太网连接（W5500）
- netdrv_4g.lua：4G模组连接
- netdrv_multiple.lua：多网卡优先级配置
- netdrv_pc.lua：PC模拟
- netdrv_device.lua：网络驱动选择器，在这里选择需要加载的网络驱动

### 3、摄像头实时预览模块（preview.lua）
- 初始化LCD屏幕，创建 AIRUI camera 组件
- 监听 USB 摄像头连接事件，枚举并选择 MJPEG 格式、1280×720 分辨
- 点击“开始预览”/“停止预览”控制画面显示
- 状态栏实时显示当前源分辨率、视口大小和 fit 模式
- 右侧面板提供“开始/停止预览”按钮和四种 fit 画面适配模式（center / contain / cover / stretch）实时切换按钮

### 4、拍照+LCD显示+UART上传模块（photo_uart_post.lua）
- 初始化LCD屏幕
- 初始化UART串口（用于上传照片）
- 监听USB摄像头连接事件
- 枚举摄像头支持的格式和分辨率，选择MJPEG格式、1024x576分辨率
- 配置摄像头帧回调，收到一帧后停止数据流
- 将MJPEG图片保存到/ram/photo.jpg
- LCD显示图片
- 通过UART将图片数据发送到电脑

### 5、拍照+LCD显示+云平台上传模块（photo_to_aircloud.lua）
- 初始化LCD屏幕
- 订阅IP_READY事件，网络连接后初始化excloud
- 监听USB摄像头连接事件
- 枚举摄像头支持的格式和分辨率，选择MJPEG格式、1024x576分辨率
- 配置摄像头帧回调，收到一帧后停止数据流
- 将MJPEG图片保存到/ram/photo.jpg
- LCD显示图片
- 调用excloud.upload_image上传图片到合宙IOT云平台
- 支持多种网络（WIFI/4G/以太网），自动通过socket.dft()判断当前默认网卡

### 6、H.264编码与上传模块（h264_power_test.lua）
- 初始化USB主机模式连接UVC摄像头
- 枚举摄像头支持的格式和分辨率，选择H.264格式、1280x720分辨率
- 配置双缓冲帧数据区，缓冲区大小按分辨率自适应
- 支持四种工作模式：
  - 模式1：仅编码（不保存、不上传）
  - 模式2：编码+本地保存（保存到SD卡，文件保留）
  - 模式3：编码+保存+串口上传（文件保留）
  - 模式4：编码+保存+AirCloud上传（使用excloud上传到合宙云平台）
- 支持SPI SD卡挂载（片选GPIO8），挂载失败自动回退到/ram路径
- 模式3使用UART3（2Mbps波特率）上传文件
- 模式4自动初始化excloud，支持网络自动检测和重连

## 演示硬件环境

1、Air1601开发板一块

2、LCD屏幕一块（RGB接口）

3、AirCAMERA_1032 USB摄像头模块一个

![](https://docs.openLuat.com/cdn/image/Air1601/1601+aieuvc_1000.jpg)


4、TYPE-C USB数据线一根

Air1601开发板通过TYPE-C USB口连接TYPE-C USB 数据线，数据线的另外一端连接电脑的USB口；
在 Air1601 开发板上丝印标注 USB1，为芯片烧录下载接口；


## 演示软件环境

1、 Luatools下载调试工具：https://docs.openluat.com/air1601/luatos/common/download/

2、Air1601 V1021及以上版本固件（理论上，2026年6月5日之后发布的固件都可以）

3、合宙IOT设备管理平台：https://iot.luatos.com/（云平台业务需要）

## 演示核心步骤

### **使用camera_preview实时预览的核心步骤**

1、搭建硬件环境

2、打开main.lua文件中 require "camera_preview"，注释掉其他业务模块

3、修改camera_preview.lua中的sensor_w和sensor_h为实际的LCD分辨率（默认1024x576）

4、烧录DEMO代码

5、等待USB摄像头连接，LCD屏幕会实时显示摄像头画面，LUATOOLS会有如下打印;
```lua
[2026-07-15 20:19:03.412][LTOS/N][000000001.411]:I/user.excamera.preview usb摄像头已连接，app_id 0
[2026-07-15 20:19:03.414][LTOS/N][000000001.411]:I/user.preview USB摄像头已连接, app_id: 0
[2026-07-15 20:19:03.417][LTOS/N][000000001.411]:I/user.preview UVC格式数量: 1
[2026-07-15 20:19:03.418][LTOS/N][000000001.411]:I/user.preview   格式索引 1, 类型: 1, 帧数: 4
[2026-07-15 20:19:03.420][LTOS/N][000000001.411]:I/user.preview     分辨率 1280x720, 帧率: 20 fps
[2026-07-15 20:19:03.421][LTOS/N][000000001.412]:I/user.preview     分辨率 864x480, 帧率: 20 fps
[2026-07-15 20:19:03.422][LTOS/N][000000001.412]:I/user.preview     分辨率 800x480, 帧率: 20 fps
[2026-07-15 20:19:03.424][LTOS/N][000000001.412]:I/user.preview     分辨率 640x480, 帧率: 20 fps
[2026-07-15 20:19:03.430][LTOS/N][000000001.427]:I/user.preview 摄像头已连接，点击“开始预览”显示画面
[2026-07-15 20:19:03.431][LTOS/N][000000001.427]:I/zbuff create large size: 900 kbyte, trigger force GC
[2026-07-15 20:19:03.432][LTOS/N][000000001.438]:I/zbuff create large size: 900 kbyte, trigger force GC
[2026-07-15 20:19:03.460][LTOS/N][000000001.448]:I/user.excamera.preview UVC格式数量 1
[2026-07-15 20:19:03.461][LTOS/N][000000001.448]:I/user.excamera.preview 匹配分辨率 1280 x 720 MJPEG
[2026-07-15 20:19:03.462][LTOS/N][000000001.448]:I/user.excamera.preview 推流已启动 1280 x 720
[2026-07-15 20:19:03.463][CAPP/N][000000001.456]:_usb_host_enumerate 632:find UVC Class:0x0e, Subclass:0x02, Protocl:0x00 on interface 1
[2026-07-15 20:19:03.464][CAPP/N][000000001.456]:_usb_host_enumerate 641:Loading driver on interface 1
[2026-07-15 20:19:03.466][CAPP/N][000000001.456]:_usb_host_enumerate 625:Do not support Class:0x01, Subclass:0x01, Protocl:0x00 on interface 2
[2026-07-15 20:19:03.467][CAPP/N][000000001.456]:_usb_host_enumerate 625:Do not support Class:0x01, Subclass:0x02, Protocl:0x00 on interface 3
[2026-07-15 20:19:03.468][CAPP/N][000000001.456]:_usb_host_enumerate 625:Do not support Class:0x01, Subclass:0x02, Protocl:0x00 on interface 4
[2026-07-15 20:19:03.469][CAPP/N][000000001.456]:_usb_host_enumerate 648:final availd interface 2
[2026-07-15 20:19:03.470][CAPP/N][000000001.456]:soc_usb_host_video_config_fast 493:format 1 frame 1, mjpeg w 1280 h 720 interval 500000
[2026-07-15 20:19:03.472][CAPP/N][000000001.472]:soc_usb_host_video_config_fast 576:Open video and select formatidx:1, frameidx:1, altsetting:1, format_type:1
[2026-07-15 20:19:03.473][CAPP/N][000000001.472]:luat_camera_task 291:camera image 1280 X 720
[2026-07-15 20:19:03.474][CAPP/N][000000001.472]:_usb_uvc_callback 177:0,0,0,0,921600,1,1024
[2026-07-15 20:19:03.753][CAPP/N][000000001.751]:_camera_decode_jpg_and_show 185:image 1280 X 720
[2026-07-15 20:19:03.755][CAPP/N][000000001.751]:_camera_decode_jpg_and_show 186:in buffer 1caf33f0 len 230400 out buffer 1cb2b800 len 1843200
[2026-07-15 20:19:03.756][CAPP/N][000000001.751]:_camera_decode_jpg_and_show 220:preview 1024 X 600, start 0, 0, cut 128, 60
[2026-07-15 20:19:40.306][CAPP/N][000000038.292]:i2c_master_xfer 395:i2c1 wait free CR 1, SR 68
[2026-07-15 20:19:40.506][LTOS/N][000000038.501]:I/user.preview 预览中 源1280×720→视口680×600 fit=cover
[2026-07-15 20:19:40.674][LTOS/N][000000038.661]:W/airui.camera camera: viewport 680x600, frame 1280x720, fit=2 (software)
[2026-07-15 20:19:48.668][LTOS/N][000000046.663]:I/user.preview 预览中 源1280×720→视口680×600 fit=center
[2026-07-15 20:19:51.701][LTOS/N][000000049.699]:I/user.preview 预览中 源1280×720→视口680×600 fit=contain
[2026-07-15 20:19:54.268][LTOS/N][000000052.272]:I/user.preview 预览中 源1280×720→视口680×600 fit=cover
[2026-07-15 20:19:56.124][LTOS/N][000000054.115]:I/user.preview 预览中 源1280×720→视口680×600 fit=stretch
[2026-07-15 20:19:57.910][LTOS/N][000000055.904]:I/user.preview 预览已停止 fit=stretch
[2026-07-15 20:20:00.707][LTOS/N][000000058.707]:I/user.preview 预览中 源1280×720→视口680×600 fit=stretch
……
```

### **使用photo_uart_post拍照+LCD显示+UART上传的核心步骤**

1、搭建硬件环境，USB转TTL模块连接到UART2（或根据硬件修改）

2、打开main.lua文件中 require "photo_uart_post"，注释掉其他业务模块

3、修改photo_uart_post.lua中的sensor_w和sensor_h为实际的LCD分辨率（默认1024x576）

4、电脑端打开串口工具（如SSCOM串口助手），选择对应串口，配置好波特率（2000000），勾选"接收数据到文件"

![](https://docs.openLuat.com/cdn/image/Air1601/SSCOM设置.png)

5、烧录DEMO代码

6、等待USB摄像头连接，自动会拍照一张，LCD显示图片，同时通过UART发送图片数据到电脑

7、电脑端保存UART收到的数据为.jpg文件，即可查看图片

8、LUATOOLS会有如下打印;
```lua
[2026-06-08 16:55:09.670][LTOS/N][000000001.849]:I/user.photo_uart_post usb摄像头已连接，app id 0 hub地址 1 端口 1 地址 2
[2026-06-08 16:55:09.671][LTOS/N][000000001.849]:I/user.photo_uart_post usb摄像头已连接，app id 0
[2026-06-08 16:55:09.673][LTOS/N][000000001.849]:I/user.photo_uart_post 总共有 2 种数据流格式
[2026-06-08 16:55:09.674][LTOS/N][000000001.850]:I/user.photo_uart_post 数据流序号 1 格式 2 图像数 4
[2026-06-08 16:55:09.675][LTOS/N][000000001.850]:I/user.photo_uart_post 跳过非MJPEG格式
[2026-06-08 16:55:09.677][LTOS/N][000000001.850]:I/user.photo_uart_post 数据流序号 2 格式 1 图像数 4
[2026-06-08 16:55:09.678][LTOS/N][000000001.850]:I/user.photo_uart_post   分辨率 1280 x 720 fps 15
[2026-06-08 16:55:09.680][LTOS/N][000000001.850]:I/user.photo_uart_post   分辨率 1024 x 576 fps 15
[2026-06-08 16:55:09.682][LTOS/N][000000001.850]:I/user.photo_uart_post 找到匹配分辨率 1024 x 576 (MJPEG)
[2026-06-08 16:55:09.684][CAPP/N][000000001.851]:_usb_host_enumerate 632:Loading driver on interface 1
[2026-06-08 16:55:09.685][CAPP/N][000000001.851]:_usb_host_enumerate 639:final availd interface 2
[2026-06-08 16:55:09.686][CAPP/N][000000001.851]:soc_usb_host_video_config_fast 493:format 2 frame 2, mjpeg w 1024 h 576 interval 666666
[2026-06-08 16:55:09.687][CAPP/N][000000001.866]:soc_usb_host_video_config_fast 576:Open video and select formatidx:2, frameidx:2, altsetting:4, format_type:1
[2026-06-08 16:55:18.612][LTOS/N][000000010.796]:I/user.photo_uart_post 接收到图像数据，位于 buffer0 长度 47350
[2026-06-08 16:55:18.622][LTOS/N][000000010.805]:I/user.photo_uart_post 照片已保存到 /ram/photo.jpg 大小 47350
[2026-06-08 16:55:18.625][LTOS/N][000000010.805]:I/user.photo_uart_post 开始通过UART上传照片...
[2026-06-08 16:55:18.628][LTOS/N][000000010.811]:I/user.photo_uart_post 照片已通过UART发送，大小 47350
[2026-06-08 16:55:18.689][LTOS/N][000000010.870]:I/user.photo_uart_post lcd.showImage返回值 true
[2026-06-08 16:55:18.694][LTOS/N][000000010.871]:I/user.photo_uart_post 照片显示完成
[2026-06-08 16:55:18.698][LTOS/N][000000010.871]:I/user.photo_uart_post 关闭摄像头流
```

### **使用photo_to_aircloud拍照+LCD显示+云平台上传的核心步骤**

1、搭建硬件环境，根据选择的网络模块连接WIFI/4G/以太网

2、在netdrv_device.lua中选择并加载对应的网络驱动

3、打开main.lua文件中 require "photo_to_aircloud" 和 require "netdrv_device"，注释掉其他业务模块

4、修改photo_to_aircloud.lua中的：

   - sensor_w和sensor_h：为实际的LCD分辨率（默认1024x576）
   - project_auth_key：在合宙IOT平台中创建项目后对应的项目Key

5、烧录DEMO代码

6、等待网络连接成功（打印IP_READY日志）

7、等待USB摄像头连接，自动会拍照一张，LCD显示图片，同时上传图片到合宙IOT云平台

8、登录合宙IOT设备管理平台 https://iot.luatos.com/#/page6/aircloud_photos 查看拍摄的照片

9、LUATOOLS会有如下打印;
```lua
[2026-06-08 16:59:12.507][LTOS/N][000000000.119]:I/user.初始化以太网
[2026-06-08 16:59:12.510][LTOS/N][000000000.120]:I/user.config.opts.spi 1 ,config.type 1
[2026-06-08 16:59:12.511][CAPP/N][000000000.120]:spi_set_new_config 386:spi1 目标速度25600000 实际速度30000000 BR 10
[2026-06-08 16:59:12.512][LTOS/N][000000000.120]:I/user.main open spi 0
[2026-06-08 16:59:12.513][LTOS/N][000000000.120]:D/ch390h 注册CH390H设备(4) SPI id 1 cs 14 irq 51
[2026-06-08 16:59:12.514][LTOS/N][000000000.120]:D/ch390h adapter 4 netif init ok
[2026-06-08 16:59:12.515][CAPP/N][000000000.121]:soc_create_event_task 188:task ch390h have 0 isr_event, total 64 static event
[2026-06-08 16:59:12.517][LTOS/N][000000000.121]:D/netdrv.ch390x task started
[2026-06-08 16:59:12.518][LTOS/N][000000000.121]:D/ch390h 注册完成 adapter 4 spi 1 cs 14 irq 51
[2026-06-08 16:59:12.519][LTOS/N][000000000.121]:I/user.以太网初始化完成
[2026-06-08 16:59:12.520][LTOS/N][000000000.121]:I/user.netdrv 订阅socket连接状态变化事件 Ethernet
[2026-06-08 16:59:12.570][LTOS/N][000000000.195]:W/user.photo_to_aircloud 等待IP_READY
[2026-06-08 16:59:12.632][LTOS/N][000000000.243]:I/netdrv.ch390x enable irq mode in pin 51
[2026-06-08 16:59:12.634][LTOS/N][000000000.254]:D/netdrv.ch390x 初始化MAC DC045A555F5E
[2026-06-08 16:59:13.572][LTOS/N][000000001.195]:W/user.photo_to_aircloud 等待IP_READY
[2026-06-08 16:59:14.554][LTOS/N][000000002.195]:I/user.photo_to_aircloud USB模式设置结果 true
[2026-06-08 16:59:14.556][LTOS/N][000000002.195]:I/user.photo_to_aircloud USB上电完成
[2026-06-08 16:59:14.557][LTOS/N][000000002.195]:I/user.photo_to_aircloud 初始化完成，摄像头连接后将每 10000 ms循环拍照并上传
[2026-06-08 16:59:14.558][LTOS/N][000000002.196]:W/user.photo_to_aircloud 等待IP_READY
[2026-06-08 16:59:14.662][LTOS/N][000000002.283]:I/netdrv.ch390x link is up 1 14 100M
[2026-06-08 16:59:14.664][LTOS/N][000000002.284]:D/netdrv 网卡(4)设置为UP
[2026-06-08 16:59:14.711][LTOS/N][000000002.334]:D/ulwip adapter 4 dhcp start netif 1c7bbf2c
[2026-06-08 16:59:14.713][LTOS/N][000000002.334]:D/DHCP dhcp discover DC045A555F5E
[2026-06-08 16:59:14.715][LTOS/N][000000002.334]:I/ulwip adapter 4 dhcp payload len 282
[2026-06-08 16:59:14.741][CAPP/N][000000002.367]:soc_usb_host_hub_int_handler 362:Port 1 change
[2026-06-08 16:59:14.745][CAPP/N][000000002.368]:soc_usb_host_hub_int_handler 373:port 1, status:0x103, change:0x03
[2026-06-08 16:59:14.746][CAPP/N][000000002.368]:soc_usb_host_hub_int_handler 406:Port 1, status:0x103, change:0x00
[2026-06-08 16:59:14.774][LTOS/N][000000002.388]:D/ulwip 收到DHCP数据包(len=300)
[2026-06-08 16:59:14.776][LTOS/N][000000002.388]:D/DHCP find ip 6401a8c0 192.168.1.100
[2026-06-08 16:59:14.777][LTOS/N][000000002.388]:D/DHCP result 2
[2026-06-08 16:59:14.778][LTOS/N][000000002.388]:D/DHCP got offer, send request
[2026-06-08 16:59:14.779][LTOS/N][000000002.388]:I/ulwip adapter 4 dhcp payload len 328
[2026-06-08 16:59:14.780][LTOS/N][000000002.391]:D/ulwip 收到DHCP数据包(len=300)
[2026-06-08 16:59:14.781][LTOS/N][000000002.391]:D/DHCP find ip 6401a8c0 192.168.1.100
[2026-06-08 16:59:14.782][LTOS/N][000000002.391]:D/DHCP result 5
[2026-06-08 16:59:14.784][LTOS/N][000000002.391]:D/DHCP DHCP acquired IP 192.168.1.100
[2026-06-08 16:59:14.785][LTOS/N][000000002.391]:D/ulwip adapter 4 ip 192.168.1.100
[2026-06-08 16:59:14.786][LTOS/N][000000002.391]:D/ulwip adapter 4 mask 255.255.255.0
[2026-06-08 16:59:14.787][LTOS/N][000000002.391]:D/ulwip adapter 4 gateway 192.168.1.1
[2026-06-08 16:59:14.788][LTOS/N][000000002.391]:D/ulwip adapter 4 lease_time 7200s
[2026-06-08 16:59:14.789][LTOS/N][000000002.391]:D/ulwip adapter 4 DNS1:192.168.1.1
[2026-06-08 16:59:14.792][LTOS/N][000000002.391]:D/net network ready 4, setup dns server
[2026-06-08 16:59:14.793][LTOS/N][000000002.391]:D/netdrv IP_READY 4 192.168.1.100
[2026-06-08 16:59:14.794][LTOS/N][000000002.392]:I/user.photo_to_aircloud 网络已连接，开始初始化excloud
[2026-06-08 16:59:14.795][LTOS/N][000000002.392]:I/user.photo_to_aircloud 根据当前网卡自动选择 device_type 4
[2026-06-08 16:59:14.796][LTOS/N][000000002.393]:I/user.[excloud]设备类型错误: 4G设备应为1, WIFI设备应为2
[2026-06-08 16:59:14.798][LTOS/N][000000002.393]:I/user.[excloud]未知设备类型
[2026-06-08 16:59:14.799][LTOS/N][000000002.395]:I/user.exmtn 读取索引 1
[2026-06-08 16:59:14.800][LTOS/N][000000002.395]:I/user.exmtn 读取块数配置 1
[2026-06-08 16:59:14.801][LTOS/N][000000002.395]:I/user.exmtn 读取写入方式配置 0
[2026-06-08 16:59:14.802][LTOS/N][000000002.396]:I/user.exmtn 配置变化 false
[2026-06-08 16:59:14.803][LTOS/N][000000002.396]:I/user.exmtn 配置未变化，文件存在，继续写入
[2026-06-08 16:59:14.805][LTOS/N][000000002.397]:I/user.exmtn 初始化成功: 每个文件 4.00 KB (1 块 × 4096 字节), 总空间 16.00 KB (4 个文件)
[2026-06-08 16:59:14.807][LTOS/N][000000002.397]:I/user.[excloud]运维日志初始化成功
[2026-06-08 16:59:14.809][LTOS/N][000000002.398]:I/user.[excloud]excloud.setup 初始化成功 设备ID: DC045A555F5E
[2026-06-08 16:59:14.810][LTOS/N][000000002.398]:I/user.photo_to_aircloud excloud初始化成功
[2026-06-08 16:59:14.811][LTOS/N][000000002.398]:I/user.[excloud]首次连接，获取服务器信息...
[2026-06-08 16:59:14.812][LTOS/N][000000002.398]:I/user.[excloud]excloud.getip 类型: 3 key: hegiSG73FHMzvFToaugk4CZXIla92Dnj-DC045A555F5E
[2026-06-08 16:59:14.813][LTOS/N][000000002.400]:D/socket connect to gps.openluat.com,443
[2026-06-08 16:59:14.815][LTOS/N][000000002.400]:D/DNS gps.openluat.com state 0 id 1 ipv6 0 use dns server0, try 0
[2026-06-08 16:59:14.816][LTOS/N][000000002.400]:D/net adatper 4 dns server 192.168.1.1
[2026-06-08 16:59:14.817][LTOS/N][000000002.400]:D/net dns udp sendto 192.168.1.1:53 from 192.168.1.100
[2026-06-08 16:59:14.818][LTOS/N][000000002.401]:D/net 设置DNS服务器 id 4 index 0 ip 223.5.5.5
[2026-06-08 16:59:14.819][LTOS/N][000000002.401]:D/net 设置DNS服务器 id 4 index 1 ip 114.114.114.114
[2026-06-08 16:59:14.820][LTOS/N][000000002.401]:I/user.netdrv_eth_spi.ip_ready_func IP_READY 192.168.1.100 255.255.255.0 192.168.1.1 nil
[2026-06-08 16:59:14.822][LTOS/N][000000002.401]:I/user.dnsproxy 开始监听
[2026-06-08 16:59:14.823][CAPP/N][000000002.402]:soc_usb_host_hub_int_handler 406:Port 1, status:0x103, change:0x00
[2026-06-08 16:59:14.824][LTOS/N][000000002.405]:I/DNS dns all done ,now stop
[2026-06-08 16:59:14.826][LTOS/N][000000002.405]:D/net adapter 4 connect 123.60.5.123:443 TCP
[2026-06-08 16:59:14.827][CAPP/N][000000002.427]:soc_usb_host_hub_int_handler 406:Port 1, status:0x103, change:0x00
[2026-06-08 16:59:14.962][CAPP/N][000000002.579]:soc_usb_host_hub_int_handler 406:Port 1, status:0x103, change:0x00
[2026-06-08 16:59:14.993][CAPP/N][000000002.604]:soc_usb_host_hub_int_handler 406:Port 1, status:0x103, change:0x00
[2026-06-08 16:59:14.995][CAPP/N][000000002.604]:soc_usb_host_enumerate 664:port 1 try enumerate 1 cnt
[2026-06-08 16:59:14.996][CAPP/N][000000002.605]:soc_usb_ll_reset 2006:host reset device!
[2026-06-08 16:59:15.103][LTOS/N][000000002.719]:I/user.httpplus 服务器已完成响应
[2026-06-08 16:59:15.105][LTOS/N][000000002.720]:I/user.[excloud]excloud.getip响应 HTTP Code: 200 Body: {"msg":"ok","conninfo":{"ipv4":"124.71.128.165","port":9108},"imginfo":{"url":"https://gps.openluat.com/iot/air_up/image","data_...
[2026-06-08 16:59:15.106][LTOS/N][000000002.721]:I/user.[excloud]获取到TCP/UDP连接信息 host: 124.71.128.165 port: 9108 key: nil
[2026-06-08 16:59:15.107][LTOS/N][000000002.721]:I/user.[excloud]获取到图片上传信息
[2026-06-08 16:59:15.126][LTOS/N][000000002.721]:I/user.[excloud]获取到音频上传信息
[2026-06-08 16:59:15.128][LTOS/N][000000002.721]:I/user.[excloud]获取到运维日志上传信息
[2026-06-08 16:59:15.129][LTOS/N][000000002.721]:I/user.[excloud]获取到二维码信息
[2026-06-08 16:59:15.130][LTOS/N][000000002.721]:I/user.[excloud]excloud.getip 更新配置: 124.71.128.165 9108
[2026-06-08 16:59:15.131][LTOS/N][000000002.721]:I/user.[excloud]excloud.getip 成功: true
[2026-06-08 16:59:15.132][LTOS/N][000000002.722]:I/user.[excloud]服务器信息获取成功 host: 124.71.128.165 port: 9108 transport: tcp
[2026-06-08 16:59:15.133][LTOS/N][000000002.722]:I/user.[excloud]获取到二维码信息
[2026-06-08 16:59:15.136][LTOS/N][000000002.722]:I/user.[excloud]创建TCP连接
[2026-06-08 16:59:15.137][LTOS/N][000000002.722]:D/socket connect to 124.71.128.165,9108
[2026-06-08 16:59:15.138][LTOS/N][000000002.723]:D/net adapter 4 connect 124.71.128.165:9108 TCP
[2026-06-08 16:59:15.139][LTOS/N][000000002.723]:I/user.[excloud]TCP连接结果 true false
[2026-06-08 16:59:15.140][LTOS/N][000000002.723]:I/user.[excloud]excloud service started
[2026-06-08 16:59:15.142][LTOS/N][000000002.723]:I/user.photo_to_aircloud excloud服务已开启
[2026-06-08 16:59:15.144][LTOS/N][000000002.724]:I/user.[excloud]excloud 自动心跳已启动，间隔 300 秒
[2026-06-08 16:59:15.145][LTOS/N][000000002.724]:I/user.photo_to_aircloud 自动心跳已启动
[2026-06-08 16:59:15.146][LTOS/N][000000002.734]:I/user.[excloud]socket cb userdata: 1C383768 33554449 0
[2026-06-08 16:59:15.147][LTOS/N][000000002.734]:I/user.[excloud]socket TCP连接成功
[2026-06-08 16:59:15.148][LTOS/N][000000002.734]:I/user.photo_to_aircloud excloud回调 connect_result
[2026-06-08 16:59:15.149][LTOS/N][000000002.734]:I/user.photo_to_aircloud excloud回调数据 {"success":true}
[2026-06-08 16:59:15.152][LTOS/N][000000002.734]:I/user.photo_to_aircloud excloud连接成功
[2026-06-08 16:59:15.153][LTOS/N][000000002.735]:I/user.[excloud]构建发送数据 16 3 hegiSG73FHMzvFToaugk4CZXIla92Dnj- 
[2026-06-08 16:59:15.154][LTOS/N][000000002.735]:I/user.[excloud]tlv发送数据长度4 40
[2026-06-08 16:59:15.155][LTOS/N][000000002.736]:I/user.[excloud]构建消息头 DC045A555F5E 
[2026-06-08 16:59:15.156][LTOS/N][000000002.737]:I/user.photo_to_aircloud excloud回调 send_result
[2026-06-08 16:59:15.157][LTOS/N][000000002.737]:I/user.photo_to_aircloud excloud回调数据 {"sequence_num":1,"success":true,"error_msg":"Send successful"}
[2026-06-08 16:59:15.158][LTOS/N][000000002.737]:I/user.photo_to_aircloud excloud发送成功，流水号: 1
[2026-06-08 16:59:15.159][LTOS/N][000000002.737]:I/user.[excloud]数据发送成功 60 字节
[2026-06-08 16:59:15.161][LTOS/N][000000002.746]:I/user.[excloud]socket cb userdata: 1C383768 33554450 0
[2026-06-08 16:59:15.162][LTOS/N][000000002.746]:I/user.[excloud]socket 发送完成
……
[2026-06-08 16:59:15.237][LTOS/N][000000002.847]:I/user.photo_to_aircloud usb摄像头已连接，app id 0 hub地址 1 端口 1 地址 2
[2026-06-08 16:59:15.238][LTOS/N][000000002.847]:I/user.photo_to_aircloud usb摄像头已连接，app id 0
[2026-06-08 16:59:15.239][LTOS/N][000000002.847]:I/user.photo_to_aircloud 创建frame_buff，当前内存状态 2097144 260072 260072
[2026-06-08 16:59:15.243][LTOS/N][000000002.859]:I/user.photo_to_aircloud 按分辨率自适应缓冲区大小 589824 字节
[2026-06-08 16:59:15.245][LTOS/N][000000002.859]:I/zbuff create large size: 576 kbyte, trigger force GC
[2026-06-08 16:59:15.246][LTOS/N][000000002.873]:I/user.photo_to_aircloud frame_buff就绪，当前内存状态 2097144 232200 260880
[2026-06-08 16:59:15.248][LTOS/N][000000002.873]:I/user.photo_to_aircloud 总共有 2 种数据流格式
[2026-06-08 16:59:15.249][LTOS/N][000000002.873]:I/user.photo_to_aircloud 格式索引 1 类型 2 帧数 4
[2026-06-08 16:59:15.250][LTOS/N][000000002.873]:I/user.photo_to_aircloud 跳过非MJPEG格式
[2026-06-08 16:59:15.251][LTOS/N][000000002.873]:I/user.photo_to_aircloud 格式索引 2 类型 1 帧数 4
[2026-06-08 16:59:15.252][LTOS/N][000000002.873]:I/user.photo_to_aircloud   分辨率 1280 x 720 fps 15
[2026-06-08 16:59:15.253][LTOS/N][000000002.874]:I/user.photo_to_aircloud   分辨率 1024 x 576 fps 15
[2026-06-08 16:59:15.254][LTOS/N][000000002.874]:I/user.photo_to_aircloud 找到匹配分辨率 1024 x 576 (MJPEG)
[2026-06-08 16:59:15.255][LTOS/N][000000002.874]:I/user.photo_to_aircloud 摄像头已就绪，开始循环拍照，间隔 10000 ms
[2026-06-08 16:59:15.257][LTOS/N][000000002.874]:I/user.photo_to_aircloud 触发新一轮拍照

```
10、登录合宙Iot设备管理平台查看拍摄的照片;

![](https://docs.openLuat.com/cdn/image/Air1601/aiecloud.png)


### **使用h264_power_test H.264编码与上传的核心步骤**

1、搭建硬件环境：
   - 模式1/2：仅需Air1601开发板+AirCAMERA_1032摄像头
   - 模式3：需额外连接USB转TTL模块到UART3
   - 模式4：需根据选择的网络模块连接WIFI/4G/以太网

2、打开main.lua文件中 require "h264_power_test"，注释掉其他业务模块

3、修改h264_power_test.lua中的配置：
   - TEST_MODE：选择工作模式（1/2/3/4）
   - RECORD_SECONDS：录制时长（秒），仅模式2/3/4
   - LOOP_INTERVAL：循环间隔（秒），仅模式2/3/4
   - PROJECT_AUTH_KEY：合宙IOT平台项目密钥，仅模式4

4、模式2/3/4确保SD卡已插入（格式为FAT32），否则自动回退到/ram路径

5、电脑端打开串口工具（如SSCOM串口助手），选择对应串口，配置好波特率（3000000），勾选"接收数据到文件"（仅模式3）

6、烧录DEMO代码

7、等待USB摄像头连接，根据TEST_MODE执行对应操作：
   - 模式1：持续编码，不上传不保存
   - 模式2：循环录制并保存到SD卡/ram，文件保留（video_时间戳.h264）
   - 模式3：录制+保存+UART上传文件
   - 模式4：录制+保存+AirCloud上传文件

8、操作完成后断电或复位即可，录制文件需定期手动清理

9、LUATOOLS会有如下打印;
```lua
[2026-07-09 10:00:00.000][LTOS/N][000000001.000]:I/user.h264_test 启动，工作模式 1
[2026-07-09 10:00:00.200][LTOS/N][000000001.200]:I/user.h264_test USB 摄像头已连接，app id 0
[2026-07-09 10:00:00.500][LTOS/N][000000001.500]:I/user.h264_test 摄像头已就绪
[2026-07-09 10:00:00.501][LTOS/N][000000001.501]:I/user.h264_test 模式1：仅编码（不保存不上传），持续运行...
[2026-07-09 10:00:02.501][LTOS/N][000000003.501]:I/user.h264_test 模式1 运行中... 帧数 100
```

## 注意事项

1、netdrv_device.lua中只能打开一个网络驱动，不能同时打开多个

2、preview.lua、photo_uart_post.lua、photo_to_aircloud.lua、h264_power_test.lua只能打开一个，不能同时打开

3、本示例不使用excamera库，而是直接使用camera库的原始API，Air1601当前版本不支持camera.capture()接口

4、h264_power_test.lua的模式2/3/4会保留录制文件（video_时间戳.h264），需定期手动清理SD卡/ram空间

5、h264_power_test.lua的模式4会自动初始化excloud，无需额外加载netdrv_device
