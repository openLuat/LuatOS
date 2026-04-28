--[[
@module  main
@summary 打砖块游戏应用入口
@version 1.0.0
@date    2026.04.13
@author  王世豪
@usage
打砖块游戏应用，经典街机游戏玩法
--]]

PROJECT = "BREAKOUT"
VERSION = "001.999.000"

-- 在日志中打印项目名和项目版本号
log.info("main", PROJECT, VERSION)

-- 加载游戏窗口模块
require "breakout_win"

-- 发布打开窗口事件
sys.publish("OPEN_BREAKOUT_WIN")

-- 运行系统
sys.run()
