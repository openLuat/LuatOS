# AirCAMERA_1034 DEMO

## 演示功能概述

本示例主要展示 Air8101  + AirCAMERA_1034 人脸识别模组的综合应用，提供以下两个业务场景：

1、face_demo：人脸录入/验证（使用 AirCAMERA_1034 人脸识别模组）

2、photo_to_aircloud：循环拍照上传合宙云平台

注意：face_demo、photo_to_aircloud 两个个业务模块一次只能打开一个，不能同时打开。

## 功能模块介绍

1、main.lua：主程序入口。通过打开/注释 require 语句切换业务模块；

2、face_demo.lua：人脸录入/验证应用模块;

3、photo_to_aircloud.lua：循环拍照上传云平台应用模块;

4、netdrv_wifi.lua：打开wifi网络，仅 photo_to_aircloud 需要加载；

## 演示硬件环境

1、Air8101核心板 一块 + TYPE-C USB 数据线一根

2、AirCAMERA_1034 摄像头一个，摄像头对应USB 接口线束2根

3、公对母杜邦线三根

| 8101核心板 | AirCAMERA_1034摄像头 |
| ---------- | -------------------- |
| uart1_tx   | uart_rx              |
| uart1_rx   | uart_tx              |
| gnd        | gnd                  |

![ ](https://docs.openluat.com/cdn/image/Air8101/8101_1034.jpg)

## 演示软件环境

1、Luatools 下载调试工具：https://docs.openluat.com/air8101/luatos/common/download/

2、Air8101 内核固件： V2020-101 及以上版本（2026-08 之后的固件）

4、合宙aircloud云平台：https://iot.luatos.com/

## 演示核心步骤

### 1、face_demo：人脸录入/验证

1、搭建硬件环境：开发板 + AirCAMERA_1034 摄像头

2、打开 main.lua 中 require "face_demo"，注释掉其他业务模块

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

1、搭建硬件环境：8101核心板 + AirCAMERA_1034 摄像头（USB）

2、打开 main.lua 中 require "photo_to_aircloud" 和 require "netdrv_wifi"（注意修改wifi ssid和password）

3、烧录内核固件 + 对应 Lua 脚本

4、登录合宙云平台查看上传的照片（需要将设备归属到你的iot账号下）

![](https://docs.openluat.com/air8000/luatos/app/image/1601_1034_2.jpg)

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



