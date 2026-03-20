--[[
@module  main
@summary Air780EPM 主程序
@version 1.0
@date    2026.03.17
@author  LuatOS
@usage
本程序用于 Air780EPM 模组，通过 airlink 与 Air1601 通信，
并发送 mobile 信息给 Air1601。
]]

-- 项目名称和版本定义
PROJECT = "Air780EPM_AirLink"
VERSION = "001.000.001"

-- 日志输出
log.info("main", PROJECT, VERSION)

-- 加载 airlink 网络模块
require "network_airlink"

-- 加载云平台模块
require "aircloud_app"

-- 启动系统
log.info("main", "sys.run")
sys.run()