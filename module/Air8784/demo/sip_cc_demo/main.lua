--[[
@module  main
@summary LuatOS用户应用脚本文件入口
@version 1.0
@date    2026.09.23
@author  蒋骞
@usage
本文件为项目入口文件，核心业务逻辑为：
1、定义 PROJECT、VERSION 并打印项目信息；
2、加载网络驱动模块 netdrv_device 和启动流程模块 app_main；
3、调用 sys.run() 启动 LuatOS 系统调度；

本文件没有对外接口，烧录后自动运行；
main.lua 中除 require 外不要添加功能代码，sys.run() 之后不要添加任何语句；
]]

-- 必须定义PROJECT和VERSION变量
PROJECT = "AIR8784_1103_SIP_CC"
VERSION = "001.000.000"

-- 打印项目信息
log.info("main", PROJECT, VERSION)

-- [可选] 看门狗初始化（根据产品型号选择）
-- ⚠️️ 注意：此代码块根据产品型号动态处理
-- Air1601/1602/6201/8101系列：取消注释，启用看门狗
-- Air700/780/8000系列：删除整个代码块（包括注释）

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

-- require其他功能模块
require "netdrv_device"
require "app_main"

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后不要加任何语句!!!!!因为添加的任何语句都不会被执行
