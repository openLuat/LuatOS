--[[
@module  main
@summary LuatOS用户应用脚本文件入口，总体调度应用逻辑
@version 1.0
@date    2025.10.29
@author  拓毅恒
@usage
演示功能概述
本demo演示如何通过HTTPDNS功能，在LuatOS环境下实现域名解析，从而绕过运营商DNS污染或劫持，提高网络访问稳定性。
HTTPDNS通过直接向指定DNS服务器发起HTTP/HTTPS请求获取域名解析结果，不依赖本地UDP 53端口，适用于4G蜂窝、WiFi、以太网等网络场景。
功能使用说明
本demo以解析“air32.cn” 与 “openluat.com”为例，展示完整流程：初始化、发起查询、获取结果。

更多说明参考本目录下的readme.md文件
]]
PROJECT = "HTTPDNS"
VERSION = "001.000.000"


-- 在日志中打印项目名和项目版本号
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

-- 加载“WIFI STA网卡”驱动模块
require "netdrv_wifi"

-- 加载 httpdns 功能模块
require "httpdns_task"

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
