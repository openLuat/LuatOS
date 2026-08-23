--[[
@module  main
@summary LuatOS用户应用脚本文件入口，总体调度应用逻辑
@version 1.0
@date    2026.08.19
@author  江访
@usage

本demo演示的核心功能为：
1、初始化墨水屏（epd库custom模式驱动2.13寸屏）
2、通过按键切换页面显示
3、显示epd核心库图形和文字
4、动态信息页演示电池/温度/时间局部刷新

更多说明参考本目录下的readme.md文件
]]

-- main.lua - 程序入口文件

-- 定义项目名称和版本号
PROJECT = "epd_demo" -- 项目名称
VERSION = "001.999.000"    -- 版本号

-- 在日志中打印项目名和项目版本号
log.info("epd_demo", PROJECT, VERSION)

-- 设置日志输出风格为样式2（建议调试时开启）
-- log.style(2)

-- 加载epd显示驱动管理功能模块
require "epd_drv"

-- 加载按键驱动管理功能模块
require "key_drv"

-- 加载epd核心库实现的用户界面功能模块
-- 实现多页面切换、按键事件分发和界面渲染功能
-- 包含主页、epd演示页、动态信息页和时间显示页
require "ui_main"

-- 用户代码已结束
-- 结尾总是这一句
sys.run()
-- sys.run()之后不要加任何语句!!!!!因为添加的任何语句都不会被执行
