# MJPG视频播放器介绍

## 项目概述

本项目是基于 Air1601/Air1602 的视频播放演示demo，实现了两种视频播放场景（二选一）：播放本地烧录的视频、以及播放从服务器下载的视频。

## 文件结构

- main.lua: 主程序入口，支持二选一演示模式
- lcd_drv.lua: LCD驱动初始化模块
- mjpg_player.lua: 播放本地烧录的视频功能模块
- mjpg_player_server.lua: 播放从服务器下载的视频功能模块
- netdrv_device.lua: 网络驱动设备选择模块
- netdrv/: 网络驱动模块目录
  - netdrv_wifi.lua: WiFi STA网卡驱动
  - netdrv_eth_spi.lua: SPI外挂CH390H以太网卡驱动
  - netdrv_4g.lua: UART外挂4G模组(Air780EPM)驱动
  - netdrv_multiple.lua: 多网卡优先级配置驱动
- fly_man_80.mjpg: 示例视频文件（本地播放模式需要）

## 功能模块说明

### 场景一：本地烧录的视频（默认启用）

**使用方式**：
- 在 main.lua 中启用 `require "mjpg_player"`
- 将 `fly_man_80.mjpg` 和代码一起烧录到固件中
- 上电后自动开始播放

### 场景二：从服务器下载的视频

**使用方式**：

- 需要连接网络（WiFi/以太网/4G外挂三选一）
- 在 netdrv_device.lua 中选择并启用合适的网络驱动
- 在 main.lua 中启用 `require "mjpg_player_server"`
- 在 main.lua 中注释掉 `require "mjpg_player"`
- 上电后自动下载并播放

## 演示硬件环境

1、Air1601/Air1602开发板一块+LCD屏幕

或者Air1601/Air1602核心板+RGB LCD屏幕（1024x600分辨率）

Air1601/Air1602核心板和RGB LCD屏幕的硬件接线方式请参考Air1601/Air1602硬件手册

2、TYPE-C USB数据线一根

- Air1601/Air1602核心板通过 TYPE-C USB 口供电；

- TYPE-C USB 数据线直接插到核心板的 TYPE-C USB 座子，另外一端连接电脑 USB 口；

## 演示软件环境

1、[Luatools下载调试工具](https://docs.openluat.com/common/Luatools/)

2、[Air1601/Air1602 固件](https://docs.openluat.com/air1601/luatos/firmware/)，选择支持AirUI功能的固件。

3、 luatos需要的脚本和资源文件

- 脚本和资源文件[点我浏览所有文件](https://gitee.com/openLuat/LuatOS/tree/master/module/Air1601_Air1602/demo/play_mjpg)

- 准备好软件环境之后，接下来查看如何[使用 LuaTools 烧录软件](https://docs.openluat.com/air1601/luatos/common/download/)，将本篇文章中演示使用的项目文件烧录到 Air1601/Air1602 核心板中

4、 lib 脚本文件：使用 Luatools 烧录时，勾选 添加默认 lib 选项，使用默认 lib 脚本文件；

## 演示核心步骤

1、搭建好硬件环境

2、根据需求配置网络（如使用服务器下载模式）：
   - 编辑 `netdrv_device.lua`，选择需要的网络驱动（WiFi/以太网/4G三选一）
   - WiFi STA模式：`require "netdrv_wifi"`（默认）
   - SPI以太网模式（CH390H）：`require "netdrv_eth_spi"`
   - UART外挂4G模式（Air780EPM）：`require "netdrv_4g"`

3、根据需求配置演示功能：
   - 编辑main.lua文件，选择需要演示的功能
   - 功能一（本地烧录的视频）：取消注释 `require "mjpg_player"`，注释掉 `require "mjpg_player_server"`
   - 功能二（从服务器下载的视频）：注释掉 `require "mjpg_player"`，取消注释 `require "mjpg_player_server"`

4、功能一需要烧录视频文件：

   - 将 `fly_man_80.mjpg` 放入项目目录
   - 使用 Luatools 将视频文件打包到固件中
   - 烧录固件到设备

5、功能二需要配置网络连接（WiFi/以太网/4G外挂三选一）

6、Luatools烧录内核固件和修改后的demo脚本代码

7、烧录成功后，自动开机运行

8、运行程序，观察日志输出了解系统状态

### 功能一：本地烧录的视频

当设备启动并初始化完成后，自动加载并播放视频文件。

类似以下日志：

``` lua
I/user.main PLAY_MJPG 001.999.000
I/user.播放器 初始化LCD和AirUI...
I/user.lcd.init true
I/user.airui init success 1024 600
I/user.播放器 准备播放视频...
I/user.播放器 LCD尺寸: 1024 x 600
I/user.播放器 视频实际分辨率: 160 x 160
I/user.播放器 视频显示位置: 432 220
I/user.播放器 视频组件创建成功
I/user.播放器 视频开始播放
```

### 功能二：从服务器下载并播放视频

设备启动后连接网络，下载视频文件后自动播放。

类似以下日志：

``` lua
I/user.播放器 初始化LCD和AirUI...
I/user.lcd.init true
I/user.airui init success 1024 600
I/user.播放器 准备播放视频...
I/user.播放器 从服务器下载视频: https://appstoreoss.luatos.com/iot-apps/res/100197/video_160x160.mjpg
I/user.播放器 等待网络连接...
I/user.播放器 网络已就绪
I/user.播放器 开始下载...
I/user.播放器 下载完成, 大小: 420769 字节
I/user.播放器 LCD尺寸: 1024 x 600
I/user.播放器 视频实际分辨率: 160 x 160
I/user.播放器 视频显示位置: 432 220
I/user.播放器 视频组件创建成功
I/user.播放器 视频开始播放
```

## 视频格式要求

- **格式**：MJPG (Motion JPEG)
- **分辨率**：不超过 1024x600（LCD 分辨率）
- **帧率**：默认 15fps，可通过 `VIDEO_FPS` 变量调整
