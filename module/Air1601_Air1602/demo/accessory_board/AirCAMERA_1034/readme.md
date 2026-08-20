# AirCAMERA_1034 DEMO

## 演示功能概述

本示例主要展示 Air1601  + AirCAMERA_1034 人脸识别模组的综合应用，提供以下三个**互斥**的业务场景：

1、face_demo：人脸录入/验证（使用 AirCAMERA_1034 人脸识别模组）

2、photo_to_aircloud：循环拍照上传合宙云平台

3、audio_record：USB摄像头麦克风录音 + TF卡存储 + 板载 DAC 播放

注意：face_demo、photo_to_aircloud、audio_record 三个业务模块一次只能打开一个，不能同时打开。

## 功能模块介绍

1、main.lua：主程序入口。通过打开/注释 require 语句切换业务模块；

2、face_demo.lua：人脸录入/验证应用模块;

3、photo_to_aircloud.lua：循环拍照上传云平台应用模块;

4、audio_record.lua：录音+播放应用模块。通过 AirCAMERA_1034 摄像头自带麦克风（标准 UAC 声卡，8000Hz/16bit/单声道）录音，保存到 TF 卡，录音结束后通过板载 DAC0 播放；

5、netdrv_device.lua：网络驱动选择器，仅 photo_to_aircloud 需要加载；

## 演示硬件环境

1、Air1601 或 Air1602 开发板一块 + TYPE-C USB 数据线两根

2、AirCAMERA_1034 摄像头一个，摄像头对应USB 接口线束2根，摄像头mic一个

3、TF 卡一张（仅 audio_record 需要）

4、喇叭一个（仅 audio_record 播放需要，接板载 DAC0 输出口）

5、SIM 卡一张

6、公对母杜邦线三根

| 1601开发板 | AirCAMERA_1034串口 |
| ---------- | ------------------ |
| uart2_tx   | uart_rx            |
| uart2_rx   | uart_tx            |
| gnd        | gnd                |

![](https://docs.openluat.com/air8000/luatos/app/image/1601_1034_1.jpg)

## 演示软件环境

1、Luatools 下载调试工具：https://docs.openluat.com/air1601/luatos/common/download/

2、Air1601/Air1602 内核固件： V1026 及以上版本（2026-08 之后的固件）

4、合宙aircloud云平台：https://iot.luatos.com/

## 演示核心步骤

### 1、face_demo：人脸录入/验证

1、搭建硬件环境：开发板 + AirCAMERA_1034 摄像头

2、打开 main.lua 中 require "face_demo"，注释掉其他业务模块和 netdrv_device

3、烧录内核固件 + 对应 Lua 脚本

4、Luatools 关键日志如下：

```lua
I/user.face_demo 人脸识别demo启动
I/user.face_demo =========================================
I/user.face_demo   开始初始化...
I/user.face_demo =========================================
I/user.exfacecam uart2 @115200 8N1
I/user.exfacecam probing...
I/user.exfacecam probe ok
I/user.exfacecam face module online
I/user.exfacecam camera init ok
I/user.face_demo 初始化完成
I/user.face_demo 模组固件: #BFP3E2V1.2.8
I/user.face_demo 共1个用户:
I/user.face_demo   [1] id=1 name=user_1577837340 admin=0
I/user.face_demo 清空已有用户...
```

### 2、photo_to_aircloud：拍照上传云平台

1、搭建硬件环境：开发板 + AirCAMERA_1034 摄像头（USB）+ 网络（WIFI/以太网/4G 任选其一）

2、打开 main.lua 中 require "photo_to_aircloud" 和 require "netdrv_device"（注释掉其他业务模块）

3、在 netdrv_device.lua 中选择实际使用的网络驱动

4、烧录内核固件 + 对应 Lua 脚本

5、登录合宙云平台查看上传的照片（需要将设备归属到你的iot账号下）

![](https://docs.openluat.com/air8000/luatos/app/image/1601_1034_2.png)

6、Luatools 关键日志如下：

```lua
I/user.photo_to_aircloud USB模式设置结果 true
I/user.photo_to_aircloud USB上电完成
I/user.photo_to_aircloud 网络已连接，开始初始化excloud
I/user.photo_to_aircloud excloud初始化成功
I/user.photo_to_aircloud excloud服务已开启
I/user.photo_to_aircloud usb摄像头已连接，app id 0
I/user.photo_to_aircloud 摄像头已就绪，开始循环拍照，间隔 10000 ms
I/user.photo_to_aircloud 照片已保存到 /ram/photo.jpg 大小 47350
I/user.photo_to_aircloud 照片上传成功
```

### 3、audio_record：录音 + 播放

1、搭建硬件环境：开发板 + AirCAMERA_1032 摄像头（USB，自带麦克风）+ TF 卡 + 喇叭/功放接 DAC0

2、打开 main.lua 中 require "audio_record"，注释掉其他业务模块和 netdrv_device

3、按需修改 audio_record.lua 顶部配置区（录音时长、保存路径、PA 功放引脚等）

4、烧录内核固件 + 对应 Lua 脚本

5、Luatools 关键日志如下：

```lua
I/user.audio_record 初始化USB摄像头（标准UVC接口）...
I/user.audio_record USB摄像头已连接, app id 0
I/user.audio_record TF卡挂载成功，录音保存到 /sd/record.wav
I/user.audio_record 默认音频驱动设置成功: 录音USB声卡0/播放DAC0
I/user.audio_record 录音已开始, req_id 0
I/user.audio_record 本次录音完成, 文件 /sd/record.wav
I/user.audio_record 3秒后开始播放录音...
I/user.audio_record 播放完成
```

