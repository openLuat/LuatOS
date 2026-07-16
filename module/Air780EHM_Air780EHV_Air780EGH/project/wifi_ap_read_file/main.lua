--[[
@module  main
@summary 远程文件管理系统入口（780EXX + Air6205 WiFi核心板）
@version 1.0
@date    2026.07.13
@usage
演示功能概述
1.1 HTTPSVR 文件管理系统概述
HTTPSVR 文件管理系统是一种基于Air780EXX + Air6205 WiFi核心板的轻量级文件服务器解决方案，
通过AP创建WiFi热点并提供HTTP服务，使用户可以通过浏览器方便地浏览、管理和下载设备内部存储及SD卡中的文件。
1.2 系统工作原理
设备启动后，自动创建AP热点，并初始化SD卡挂载。同时启动HTTP服务器，提供文件列表浏览、文件下载等功能。
用户只需连接到设备的WiFi热点，通过浏览器访问指定IP地址，即可查看和管理设备中的文件。
1.3 核心功能特性
- 任务控制：通过默认配置和boot按键控制是否启停文件管理任务
- 热点创建：设备自动创建名为`LuatOS_FileHub`的WiFi热点，供用户连接
- SD卡管理：自动挂载SD卡，支持浏览和下载SD卡中的文件
- 文件浏览：通过浏览器查看设备内部存储和SD卡中的文件列表
- 文件下载：支持直接通过URL下载文件，支持大文件下载
- 用户认证：提供简单的用户名密码认证机制，保护文件安全
1.4 接线说明（Air780EXX核心板 → Air6205核心板）
   28/U2RXD        → U1_TX
   29/U2TXD        → U1_RX
   VBAT            → VBAT
   GND             → GND

本示例基于合宙 Air780EXX + Air6205 模组，演示 AP + 文件服务器 的完整实现流程。用户连接到设备WiFi热点后，通过浏览器即可访问文件管理系统，实现文件的浏览和下载功能。
更多说明参考本目录下的readme.md文件

注意事项：
1. 本demo依赖exremotefile扩展库，内部自动识别Air780EXX系列并初始化Air6205
2. 确保 script/libs/explorer.html 文件烧录到设备中
]]

PROJECT = "780EXX_WIFI_FILE_SERVER"
VERSION = "001.999.000"

log.info("main", PROJECT, VERSION)


-- 如果内核固件支持wdt看门狗功能，此处对看门狗进行初始化和定时喂狗处理
-- 如果脚本程序死循环卡死，就会无法及时喂狗，最终会自动重启
if wdt then
    --配置喂狗超时时间为9秒钟
    wdt.init(9000)
    --启动一个循环定时器，每隔3秒钟喂一次狗
    sys.timerLoopStart(wdt.feed, 3000)
end


-- 如果内核固件支持errDump功能，此处进行配置，【强烈建议打开此处的注释】
-- 因为此功能模块可以记录并且上传脚本在运行过程中出现的语法错误或者其他自定义的错误信息，可以初步分析一些设备运行异常的问题
-- 以下代码是最基本的用法，更复杂的用法可以详细阅读API说明文档
-- 启动errDump日志存储并且上传功能，600秒上传一次
-- if errDump then
--     errDump.config(true, 600)
-- end


-- 使用LuatOS开发的任何一个项目，都强烈建议使用远程升级FOTA功能
-- 可以使用合宙的iot.openluat.com平台进行远程升级
-- 也可以使用客户自己搭建的平台进行远程升级
-- 远程升级的详细用法，可以参考fota的demo进行使用


-- 启动一个循环定时器
-- 每隔3秒钟打印一次总内存，实时的已使用内存，历史最高的已使用内存情况
-- 方便分析内存使用是否有异常
-- sys.timerLoopStart(function()
--     log.info("mem.lua", rtos.meminfo())
--     log.info("mem.sys", rtos.meminfo("sys"))
-- end, 3000)



-- 引入任务控制模块
require "task_control"

-- 用户代码已结束--------------------------------------------
sys.run()
-- sys.run()之后不要加任何语句!!!!!
