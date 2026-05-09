
--[[
@module  tpms_dashboard_win
@summary  智能胎压监测系统 - 实时显示四轮胎压和温度
@version 1.0
@date    2026-05-09
@author  马亚丹
]]
PROJECT = "TPMS_Dashboard"
VERSION = "001.001.000"

log.info("main", PROJECT, VERSION)

require "tpms_dashboard_win"

sys.publish("OPEN_TPMS_DASHBOARD_WIN")
sys.run()
