# AirCAMERA_1034 DEMO

## 演示功能概述

本示例演示 Air8101 系列搭配 AirCAMERA_1034 的三种用法。三种用法共用摄像头，请在 [main.lua](main.lua) 中选择其中一种。

1、[face_preview.lua](face_preview.lua) LCD 软件预览。支持触摸切换分辨率、拍照、照片保存到 TF 卡，以及在预览期间录入和验证人脸。

2、[face_demo.lua](face_demo.lua) 独立的人脸录入和验证示例。运行时会清空人脸模组内已有的用户。

3、[photo_to_aircloud.lua](photo_to_aircloud.lua) 循环拍照并上传合宙云平台（默认），需同时加载 [netdrv_wifi.lua](netdrv_wifi.lua)。

## 演示功能概述

### 1、主程序入口模块（main.lua）

- 设置项目名 `Air8101_AirCAMERA_1034_Demo` 和版本号 `001.999.000`。
- 通过 `require` 选择业务模块，默认加载 `netdrv_wifi` 和 `photo_to_aircloud`，然后调用 `sys.run()` 启动调度。

### 2、LCD 预览模块（face_preview.lua）

- 开机自动尝试预览。优先尝试 960×480，取不到首帧时按配置继续尝试其他分辨率。
- [board.lua](board.lua) 配置 LCD、触摸、摄像头供电和 UART1。[camera_app.lua](camera_app.lua) 负责 UVC 抓帧、拍照和存卡。[ui.lua](ui.lua) 负责 JPEG 解码上屏和触摸界面。
- 通过 UART1 在预览期间录入普通用户或验证已有用户。验证成功时，界面显示用户 ID。

### 3、独立人脸录入和验证模块（face_demo.lua）

- 通过 UART1 连接人脸模组，查询固件和用户列表，清空旧用户后演示录入和验证，并将结果打印到串口。

### 4、拍照上传和联网模块（photo_to_aircloud.lua、netdrv_wifi.lua）

- `netdrv_wifi` 建立 Wi-Fi 连接。`photo_to_aircloud` 等待联网，循环拍照并上传至合宙云平台。

## 演示硬件环境

### 1、LCD 预览

- Air8101B V3.0 开发板、AirCAMERA_1034 摄像头和 USB 数据线各一件。
- AirLCD_1100 屏幕，10.1 寸、1024×600、RGB 接口，显示驱动 IC 为 JD9165BA，触摸 IC 为 GT911。示例在 `board.lua` 中使用 `hx8282` LCD 时序配置。
- 摄像头接开发板的 USB-A 口，打开 `VBAT_Air8101` 和 `VBAT_UVC`。脚本通过 GPIO29 控制摄像头供电。
- 使用人脸功能时，将摄像头的 UART 线束接到 UART1，串口使用 115200、8N1。在 V3.0 开发板上将 `VBAT_4G` 拨到 OFF，并按摄像头的接线要求为 USB 和 UART 侧供电。
- 需要保存照片时，插入 FAT32 格式的 TF 卡并打开 `VBAT_SD`。

| 开发板 UART1 | AirCAMERA_1034 UART |
| --- | --- |
| TX | RX |
| RX | TX |
| GND | GND |

### 2、独立人脸示例和拍照上传

使用 Air8101 核心板、AirCAMERA_1034 和 USB 数据线。独立人脸示例也按上表交叉连接 UART1，并将两端共地。拍照上传通过 USB 采集图像。

![Air8101 核心板与 AirCAMERA_1034 接线](https://docs.openluat.com/cdn/image/Air8101/8101_1034.jpg)

## 演示软件环境

1、[Luatools 下载调试工具](https://docs.openluat.com/air8101/luatos/common/download/)。

2、LCD 预览使用支持 UVC 采集和 LCD JPEG 解码的 Air8101B 固件。需要稳定预览原生 320×240 时，使用已移除 MJPEG 固定 5 KiB 帧长门槛的固件。[Air8101 固件下载](https://docs.openluat.com/air8101/luatos/firmware/)。

3、使用人脸功能时，将扩展库 [exfacecam.lua](../../../../../script/libs/exfacecam.lua) 与示例脚本一起烧录。若需要中文界面，可附加 [MiSans_gb2312.ttf](../../ui/hzfont/MiSans_gb2312.ttf) 到脚本区根目录。

4、独立人脸示例和拍照上传使用 Air8101 V2020-101 及以上固件。拍照上传还需要 Wi-Fi 和 [合宙云平台](https://iot.luatos.com/)。

## 演示核心步骤

### 1、face_preview：LCD 软件预览、人脸录入和验证

1. 接好摄像头、显示屏和触摸屏。测试人脸功能时接好 UART1 线束。
2. 在 `main.lua` 中注释 `require "netdrv_wifi"` 和 `require "photo_to_aircloud"`，再启用 `require "face_preview"`。烧录本目录下的 Lua 文件，并添加 `exfacecam.lua`。
3. 上电等待预览画面。可通过底部按钮切换分辨率、开始或停止预览、拍照并保存到 TF 卡。
4. 画面出来后，点 **人脸录入（ENROLL）** 并正对摄像头，等待录入结果。若界面提示此人已录入，可直接验证。
5. 点 **人脸验证（VERIFY）** 并正对摄像头。验证通过后，界面显示用户 ID。录入和验证期间预览继续刷新，串口会记录期间绘制的帧数。

Luatools 串口日志示例。分辨率、用户 ID 和绘制帧数以实际输出为准。

```text
I/user.camera_app 摄像头就绪 960x480
I/user.main 预览泵启动
I/user.exfacecam uart1 @115200 8N1
I/user.exfacecam probe ok
I/user.main 人脸录入 true 1 期间绘制帧数 8
I/user.main 人脸验证 true 1 期间绘制帧数 5
```

### 2、face_demo：独立人脸录入和验证

1. 接好摄像头的 USB 和 UART1 线束。
2. 在 `main.lua` 中启用 `require "face_demo"`，注释其他业务模块，并随示例烧录 `exfacecam.lua`。
3. 上电后查看 Luatools 日志。脚本会清空模组已有用户，再执行录入和验证。测试时请正对摄像头。

```lua
I/user.face_demo 人脸识别demo启动
I/user.face_demo =========================================
I/user.face_demo   开始初始化...
I/user.face_demo =========================================
I/user.exfacecam uart1 @115200 8N1
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

### 3、photo_to_aircloud：拍照上传云平台

1、搭建硬件环境，使用 Air8101 核心板和 AirCAMERA_1034 摄像头。

2、在 `main.lua` 中同时启用 `require "photo_to_aircloud"` 和 `require "netdrv_wifi"`，注释其他业务模块，并在 `netdrv_wifi.lua` 中填写 Wi-Fi 配置。

3、烧录内核固件、示例 Lua 脚本和所需扩展库。

4、登录合宙云平台查看上传的照片（需要将设备归属到你的iot账号下）

![](https://docs.openluat.com/air8000/luatos/app/image/1601_1034_2.jpg)

5、Luatools 关键日志如下：

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

## 常见问题

- **预览界面没有人脸按钮**。确认 `exfacecam.lua` 已随脚本烧录，且 `board.FACE` 配置已启用。
- **点录入或验证后提示人脸模组无响应**。检查 UART1 的 TX/RX 是否交叉、两端是否共地，以及摄像头 UART 侧是否供电。
- **能显示界面，但没有摄像头画面**。检查摄像头是否接在 USB-A 口、`VBAT_UVC` 是否打开。查看串口日志中的摄像头初始化和首帧结果。
- **320×240 偶发黑屏或退回其他档位**。保留 5 KiB 门槛的旧固件会丢弃长度不超过 5120 字节的 MJPEG 帧，低细节画面更容易触发。换用包含短帧修复的固件，或切换到 480×320 等其他档位。
