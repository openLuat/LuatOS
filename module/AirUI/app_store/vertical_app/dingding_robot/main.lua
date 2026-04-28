--[[
@module  main
@summary 钉钉机器人应用主入口
@version 1.0.0
@date    2026.04.03
@author  马亚丹
]]

-- 项目名称
PROJECT = "DINGDING_ROBOT"
-- 项目版本号
VERSION = "001.000.000"

-- 在日志中打印项目名和项目版本号
log.info("main", PROJECT, VERSION)

-- 引入扩展窗口库
--local exwin = require "exwin"

-- 引入主窗口模块
require "dingding_robot_win"

-- 发布消息，打开主窗口
sys.publish("OPEN_DINGDING_ROBOT_WIN")

-- 启动系统主循环
sys.run()
