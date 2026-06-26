--[[
@module  main
@summary 弹球大作战游戏应用入口（整合版）
@version 2.0.0
@date    2026.06.05
@author  LuatOS
@usage
弹球大作战游戏，提供单机对战和联网对战两种模式
整合所有功能到单个模块中
--]]

PROJECT = "PINBALL_WAR"
VERSION = "002.000.000"

log.info("main", PROJECT, VERSION)

-- 加载整合后的模块
require "pinball_combined"

-- 发布打开菜单窗口的事件
sys.publish("OPEN_PINBALL_WAR_MENU")

sys.run()
