--[[
@module  main
@summary BLE主机应用入口
@version 1.0.0
@date    2026.04.10
@author  王世豪
@usage
BLE主机应用，支持BLE协议主机功能，包括扫描、连接和数据传输
--]]

PROJECT = "BLE_MASTER"
VERSION = "001.999.000"

-- 在日志中打印项目名和项目版本号
log.info("main", PROJECT, VERSION)

-- 加载BLE主机窗口
require "ble_master_win"

-- 发布打开窗口事件
sys.publish("OPEN_BLE_MASTER_WIN")

-- 运行系统
sys.run()
