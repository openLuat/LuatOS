--[[
@module  main
@summary Air8101B 上的 AirCAMERA_1032 USB 摄像头 LCD 预览示例
@version 001.999.000
@date    2026.11.21
@usage
1. 将 AirCAMERA_1032 接到 Air8101B V3.0 开发板的 USB-A 口，接好 AirLCD_1100 和触摸屏。
2. 使用包含 AirCAMERA_1032 UVC 修复并启用 JPEG 软件解码的 Air8101B 固件，将本目录的 Lua 文件一起烧录。
3. 开机自动从 640×360 档开始预览。触摸底部的 640x360、720p 或 1080p 按钮切换分辨率。
4. 720p、1080p 画面居中裁剪到屏幕预览区。点 STOP 关闭预览并断开摄像头供电，
   再点 START 按当前选中的分辨率重新打开。
]]

-- Luatools 读取 PROJECT 和 VERSION 用于标识应用。项目名使用 ASCII，版本号按 XXX.YYY.ZZZ 填写。
PROJECT = "Air8101_AirCAMERA_1032_Demo"
VERSION = "001.999.000"

-- 启动时打印项目名和版本号，便于核对当前烧录的脚本。
log.info("main", PROJECT, VERSION)

-- 加载 USB 预览模块，由模块注册触摸事件并启动预览协程。
require "usb_preview"

-- 启动 LuatOS 调度，入口文件以 sys.run() 结束。
sys.run()
