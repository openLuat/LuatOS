--[[
@module  main
@summary LIS2DH12 三轴加速度传感器 Demo 入口
@version 1.0
@date    2026.07.16
@author  江访
]]

--[[
=== 演示内容 ===

本 demo 演示 exs_lis2dh12 扩展库的完整功能，顺序为：
HELLO→[1/4]→[2/4]→[3/4]→[4/4]→End
1、初始化和数据读取（[1/4]）
2、量程切换演示（[2/4]）
3、输出速率切换（[3/4]）
4、温度读取演示（[4/4]）

]]

-- main.lua - 程序入口文件

PROJECT = "LIS2DH12_Demo"    -- 项目命名
VERSION = "001.999.000"      -- 项目版本号

-- 在日志中打印项目名和项目版本号
log.info("main", PROJECT, VERSION)

-- 加载 lis2dh12_demo.lua 演示模块
require "lis2dh12_demo"

-- 用户代码已结束
-- 结尾总是这一句
sys.run()
-- sys.run()之后不要加任何语句!!!!!因为添加的任何语句都不会被执行
