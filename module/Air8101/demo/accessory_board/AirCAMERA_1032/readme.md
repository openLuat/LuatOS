# AirCAMERA_1032 DEMO

## 演示功能概述

本示例在 Air8101B 上使用 AirCAMERA_1032 采集 USB MJPEG 图像。脚本逐帧抓取 JPEG，在 LCD 上解码显示，并通过触摸按钮切换分辨率、停止和恢复预览。

1、[main.lua](main.lua) 主程序入口

2、[usb_preview.lua](usb_preview.lua) USB 预览与触摸控制模块

3、[board.lua](board.lua) 开发板硬件配置模块

4、[camera_app.lua](camera_app.lua) USB 摄像头采集模块

5、[ui.lua](ui.lua) LCD 预览绘制模块

## 演示功能概述

### 1、主程序入口模块（main.lua）

- 设置项目名 `Air8101_AirCAMERA_1032_Demo` 和版本号 `001.999.000`，并在启动时打印。
- 通过 `require "usb_preview"` 加载预览模块，然后调用 `sys.run()` 启动调度。

### 2、USB 预览与触摸控制模块（usb_preview.lua）

- 初始化 LCD 和触摸屏，开机自动从 640×360 档开始预览。
- 在同一个协程中处理分辨率切换、START/STOP 和逐帧显示。
- 首次打开失败后，延长摄像头断电时间并重试一次。

## 演示硬件环境

1、Air8101B V3.0 开发板一块。

2、AirCAMERA_1032 USB 摄像头一个，接到开发板的 USB-A 口。脚本使用 GPIO29 控制摄像头供电。

3、AirLCD_1100 10.1 寸 1024×600 RGB 屏和 GT911 触摸屏。接好显示与触摸接口。示例的 LCD 时序配置名为 `hx8282`，屏幕与触摸参数见 `board.lua`。

4、USB 数据线一根，用于连接电脑和开发板，烧录并查看串口日志。

## 演示软件环境

1、Luatools 下载调试工具：[https://docs.openluat.com/air780epm/common/Luatools/](https://docs.openluat.com/air780epm/common/Luatools/)

2、包含 AirCAMERA_1032 UVC 修复并启用 JPEG 软件解码的 Air8101B 固件。[Air8101 固件下载](https://docs.openluat.com/air8101/luatos/firmware/)

> 当前最新的 V2022 106 号固件还不支持。预计在 V2023 临时固件、V2024 正式固件中支持。
>
> 若使用 2024 固件仍无法显示预览画面，请联系技术人员咨询。

## 演示核心步骤

### 1、接线并烧录

1. 接好摄像头、LCD 和触摸屏，再连接开发板和电脑。
2. 使用 Luatools 将固件和本目录下的所有 Lua 文件烧录到开发板。
3. 上电后等待 640×360 预览自动启动。界面显示 `Opening` 时，摄像头正在上电、枚举或等待首帧。单次首帧等待上限为 15 秒，打开失败后自动重试一次。

### 2、切换分辨率和停止预览

1. 点屏幕底部的 **640x360**、**720p** 或 **1080p**，切换 USB MJPEG 采集分辨率。
2. 点 **STOP** 关闭摄像头并断开供电。按钮显示 **START** 后，再点一次即可按当前档位恢复预览。

| 按钮 | USB MJPEG 协商分辨率 | LCD 显示方式 |
| --- | --- | --- |
| 640x360 | 640×360 | 整帧居中显示，默认档位 |
| 720p | 1280×720 | 按原像素从中间裁出 1024×480 的区域 |
| 1080p | 1920×1080 | 按原像素从中间裁出 1024×480 的区域 |

### 3、查看演示结果

状态栏显示 `Live` 后，LCD 开始刷新画面，并显示当前协商分辨率。三档均已在 Air8101B 上验证出画面。串口的 `first_display` 日志依次记录协商分辨率、实际 JPEG 帧尺寸和屏幕可见尺寸。

```text
I/user.air1032 first_display 640 360 jpeg 640 368 visible 640 368
I/user.air1032 first_display 1280 720 jpeg 1280 720 visible 1024 480
I/user.air1032 first_display 1920 1080 jpeg 1920 1088 visible 1024 480
```

实测 640×360 档的 JPEG 帧头为 640×368，1080p 档的帧头为 1920×1088。绘制时按实际 JPEG 尺寸计算居中位置和裁剪范围。

## 常见问题

- **界面提示 USB camera open failed**。检查摄像头是否插在开发板的 USB-A 口，并按「演示软件环境」中的固件要求确认所用固件已包含 AirCAMERA_1032 UVC 修复。
- **界面提示 JPEG display failed**。检查固件是否启用了 JPEG 软件解码。串口日志可查看解码或内存相关的错误。
- **高分辨率切换时画面暂时空白**。切换会重新打开摄像头。等状态栏更新到 `Live` 后，画面开始刷新。
- **720p 或 1080p 预览时画面卡顿**。脚本先用软件解码整帧 JPEG，再裁剪上屏。两档分辨率的单帧解码耗时较长。想让画面更流畅，可以切换到原生 640×360。
