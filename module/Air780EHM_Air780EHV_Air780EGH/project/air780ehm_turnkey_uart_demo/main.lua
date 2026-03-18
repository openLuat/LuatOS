--[[
@module  main
@summary UI+UART 独立项目主程序入口
@version 1.0.0
@date    2026.03.17
@usage
独立UI+UART功能演示项目
]]

-- 项目名称和版本定义
PROJECT = "UI_UART_Project"
VERSION = "001.999.001"

-- 在日志中打印项目名和项目版本号
log.info("main", "【项目启动】项目名称:" .. PROJECT .. " 版本号:" .. VERSION)

-- 设置日志输出风格为样式2（建议调试时开启）
-- log.style(2)

-- 如果内核固件支持errDump功能，此处进行配置，【强烈建议打开此处的注释】
if errDump then
    errDump.config(true, 600)
end

-- 启动一个循环定时器，每隔3秒钟打印一次内存情况
sys.timerLoopStart(function()
    log.info("mem.lua", rtos.meminfo())
    log.info("mem.sys", rtos.meminfo("sys"))
end, 3000)

-- 加载显示驱动
lcd_drv = require "lcd_drv"
-- 加载触摸驱动
tp_drv = require "tp_drv"

-- 加载串口功能模块
require "uart_app"

-- 引入UI主模块
require "ui_main"

-- 用户代码已结束
-- 结尾总是这一句
sys.run()
-- sys.run()之后不要加任何语句!!!!!因为添加的任何语句都不会被执行
