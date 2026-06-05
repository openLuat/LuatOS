--[[
@module  main
@summary 卡牌对战游戏应用入口
@version 1.0.0
@date    2026.06.02
@author  LuatOS
@usage
卡牌对战游戏，支持本地对战和联网对战
]]

PROJECT = "TURN_CARD"
VERSION = "001.000.000"

log.info("main", PROJECT, VERSION)

require "turn_card_win"

sys.publish("OPEN_TURN_CARD_WIN")

sys.run()
