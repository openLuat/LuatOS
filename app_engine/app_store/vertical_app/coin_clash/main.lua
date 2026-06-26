--[[
@module  main
@summary 双人接金币碰撞对决游戏应用入口
@version 1.0.0
@date    2026.06.09
@author  王世豪
@usage
双人接金币碰撞对决，支持本地双人对战和网络联机对战
--]]

PROJECT = "COIN_CLASH"
VERSION = "001.000.000"

log.info("main", PROJECT, VERSION)

require "coin_clash_win"

sys.publish("OPEN_COIN_CLASH_WIN")

sys.run()
