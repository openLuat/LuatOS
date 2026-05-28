--[[
@module  main
@summary 双人联网坦克大战游戏应用入口
@version 1.0.0
@date    2026.05.20
@author  王世豪
@usage
双人联网坦克大战游戏，支持本地双人对战和网络联机对战
--]]

PROJECT = "TANK_BATTLE"
VERSION = "001.000.000"

log.info("main", PROJECT, VERSION)

require "tank_battle_win"

sys.publish("OPEN_TANK_BATTLE_WIN")

sys.run()
