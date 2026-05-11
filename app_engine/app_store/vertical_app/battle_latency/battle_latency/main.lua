--[[
@module  main
@summary  对战测速应用入口
@version  1.0.0
@date    2026.05.09
@author  王世豪
@usage
对战测速应用，双设备MQTT通信，实时位置同步和延迟测试
--]]

PROJECT = "SIMPLE_BATTLE"
VERSION = "001.000.000"

log.info("main", PROJECT, VERSION)

require "battle_latency_win"

sys.publish("OPEN_BATTLE_WIN")

sys.run()
