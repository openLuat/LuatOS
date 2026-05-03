--[[
@module  main
@summary BLE从机应用入口
@version 1.0.0
@date    2026.04.09
@author  王世豪
@usage
BLE从机应用，支持BLE协议从机功能
--]]

PROJECT = "BLE_SLAVE"
VERSION = "001.999.000"

-- 在日志中打印项目名和项目版本号
log.info("main", PROJECT, VERSION)

-- 加载BLE从机窗口
require "ble_slave_win"

-- 发布打开窗口事件
sys.publish("OPEN_BLE_SLAVE_WIN")

-- 运行系统
sys.run()
