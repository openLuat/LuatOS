--[[
@module  main
@summary 蓝牙文件传输应用入口
@version 1.0.0
@date    2026.04.23
@usage
蓝牙文件传输应用，支持主从模式切换，文件发送和接收
--]]

PROJECT = "BLE_TRANSFER"
VERSION = "001.999.000"

-- 在日志中打印项目名和项目版本号
log.info("main", PROJECT, VERSION)

-- 加载蓝牙模拟器（PC环境）
require "bluetooth_sim"

-- 加载蓝牙文件传输窗口
require "ble_transfer_win"

-- 发布打开窗口事件
sys.publish("OPEN_BLE_TRANSFER_WIN")

-- 运行系统
sys.run()
