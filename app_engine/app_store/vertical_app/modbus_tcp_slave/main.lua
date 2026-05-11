--[[
@module  main
@summary Modbus TCP 从站应用 - 主程序入口
@version 1.0.0
@date    2026.05.11
@author  马梦阳
@usage

]]

PROJECT = "MODBUS_TCP_SLAVE"
VERSION = "001.000.001"

log.info("main", PROJECT, VERSION)

require "modbus_win"

sys.publish("OPEN_MODBUS_WIN")

sys.run()
