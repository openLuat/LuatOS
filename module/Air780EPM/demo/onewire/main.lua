--[[
@module  main
@summary OneWire综合演示项目主文件（单传感器 + 多传感器）
@version 001.000.000
@date    2025.11.25
@author  王棚嶙
@usage
本演示项目整合单DS18B20和多DS18B20传感器功能：
1. 单传感器模式：GPIO2默认OneWire功能、硬件通道0模式、CRC校验、3秒间隔连续监测
2. 多传感器模式：引脚54/23切换、PWR_KEY按键控制、电源管理、2秒间隔双路监测
3. 完整的OneWire API接口演示、错误处理、设备检测、温度报警
]]

-- 项目信息
PROJECT = "onewire_demo"
VERSION = "001.000.000"




-- 在日志中打印项目名和项目版本号
log.info("main", PROJECT, VERSION)



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

-- 在加载以下两个功能的时候建议分别打开，避免同时初始化OneWire总线，导致资源冲突
-- 单设备模式：使用GPIO2默认OneWire功能
-- 双设备模式：GPIO2默认 + 引脚54复用

-- 加载单传感器应用模块
-- require("onewire_single_app")

-- 加载多传感器应用模块
require("onewire_multi_app")


-- 启动系统主循环
sys.run()