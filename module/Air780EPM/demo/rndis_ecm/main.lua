--[[
@module  main
@summary LuatOS用户应用脚本文件入口，总体调度应用逻辑
@version 1.0
@date    2025.08.25
@author  拓毅恒
@usage
演示功能概述
RNDIS是指Remote NDIS，基于USB实现RNDIS实际上就是TCP/IP over USB，就是在USB设备上跑TCP/IP，让USB设备看上去像一块网卡。从而使Windows /Linux可以通过 USB 设备连接网络。
ECM（Ethernet Control Model）是一种基于 USB 的通信设备类（CDC）子类协议，它将 “TCP/IP over USB” 抽象成一条虚拟以太网链路：USB 设备端实现 ECM 功能后，会在主机侧呈现为一块标准的以太网卡（如 usb0）。主机操作系统（Linux、macOS 等）无需额外专用驱动，即可通过该虚拟网卡发送/接收以太网帧，从而经 USB 设备连接到网络。
1、功能使用说明
由于 Air780EPM 只支持 LUATOS 模式，且 RNDIS 网卡应用默认关闭，所以在使用 RNIDS 之前，需要使用接口打开，本demo将为大家讲解如何使用 RNIDS 功能。
本demo仅演示在 Windows系统上运行 RNDIS 功能，如果需要在 Linux系统上使用功能，请查看文档：xxxxxxxxx
2、ECM 功能说明
由于Windows系统没有测试环境无法测试 ECM 功能，所以 open_ecm.lua 没有完整测试。

注：在v2013以下固件使用mobile.config()的返回值有bug，无论是否开启成功，返回值均为false，需要烧录V2013及以上固件才能完整验证此功能。

更多说明参考本目录下的readme.md文件
]]
PROJECT = "RNDIS_ECM"
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

-- 加载 open_rndis 主应用功能模块
require "open_rndis"

-- 加载 open_ecm 主应用功能模块
-- require "open_ecm"

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
