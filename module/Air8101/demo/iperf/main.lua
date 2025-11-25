--[[
@module  main
@summary LuatOS用户应用脚本文件入口，总体调度应用逻辑
@version 1.0
@date    2025.10.28
@author  拓毅恒
@usage
演示功能概述
本demo演示如何使用LuatOS的iperf模块进行网络吞吐量测试。
iperf是一种网络性能测试工具，支持服务器模式和客户端模式，可以测试网络的带宽和稳定性。
本demo提供了两个独立的测试用例：
1、iperf服务器模式 - 设备作为服务器等待客户端连接
2、iperf客户端模式 - 设备作为客户端主动连接服务器
3、netdrv_device：配置连接外网使用的网卡，目前支持以下两种选择（二选一）
   (1) netdrv_eth_rmii：通过MAC层的rmii接口外挂PHY芯片（LAN8720Ai）的以太网卡
   (2) netdrv_eth_spi：通过SPI外挂CH390H芯片的以太网卡

更多说明参考本目录下的readme.md文件
]]
PROJECT = "IPERF_DEMO"
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

-- 加载网络驱动设备功能模块
require "netdrv_device"

-- 加载 iperf 服务器测试模块
require "iperf_server"

-- 加载 iperf 客户端测试模块
-- require "iperf_client"

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!