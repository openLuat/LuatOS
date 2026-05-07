--[[
@module  main
@summary BLE iBeacon应用主入口
@version 1.0.0
@date    2026.04.07
@author  王世豪
@usage
BLE iBeacon应用，支持iBeacon协议广播功能
]]

PROJECT = "BLE_IBEACON"
VERSION = "001.999.000"

-- 在日志中打印项目名和项目版本号
log.info("main", PROJECT, VERSION)

require "ibeacon_win"

sys.publish("OPEN_IBEACON_WIN")

sys.run()
