--[[
@module  main
@summary 远程文件管理系统入口（780EXX + Air6205 WiFi配件板）
@version 1.0
@date    2026.07.13
@usage
本demo演示的核心功能为：
基于780EXX核心板 + 外挂Air6205 WiFi配件板的远程文件管理系统。

1. 系统工作原理
   设备启动后，通过 boot 按键触发服务启动。exremotefile 扩展库自动检测
   到 780EXX 系列模组，先通过 airlink UART 协议初始化 Air6205，然后创建
   AP 热点并启动 HTTP 文件服务器。手机/电脑连接热点后通过浏览器访问
   文件管理系统，实现文件的浏览、下载、上传、删除功能。

2. 接线说明（780EXX核心板 → Air6205配件板）
   UART2_RXD(IO12) → U1_TX
   UART2_TXD(IO13) → U1_RX
   VBAT            → VBAT
   GND             → GND

3. 核心功能特性
   - 任务控制：通过 boot 按键（GPIO0）控制服务启停
   - 热点创建：Air6205 创建名为 LuatOS_FileHub 的 WiFi 热点
   - 文件浏览：通过浏览器查看设备中的文件列表
   - 文件下载：支持直接通过 URL 下载文件
   - 文件上传：支持通过网页上传文件
   - 文件删除：支持通过网页删除文件
   - 用户认证：提供用户名密码认证机制

注意事项：
1. 本demo依赖exremotefile扩展库，内部自动识别780EXX系列并初始化Air6205
2. 确保 script/libs/explorer.html 文件烧录到设备中
]]

PROJECT = "780EXX_WIFI_FILE_SERVER"
VERSION = "001.999.000"

log.info("main", PROJECT, VERSION)

-- 引入任务控制模块
require "task_control"

-- 用户代码已结束--------------------------------------------
sys.run()
-- sys.run()之后不要加任何语句!!!!!
