--[[
@module  main
@summary 双人联机火柴人格斗游戏应用入口
@version 1.0.0
@date    2026.05.09
@author  王世豪
@usage
双人联机火柴人格斗游戏，通过MQTT连接对战
--]]

PROJECT = "STICK_FIGHTER_ONLINE"
VERSION = "001.000.000"

log.info("main", PROJECT, VERSION)

require "stick_fighter_online_win"

sys.publish("OPEN_STICK_FIGHTER_ONLINE_WIN")

sys.run()
