--[[
@module  main
@summary MQTT 多客户端管理器 应用主入口
@version 1.0.0
@date    2026.05.19
]]

PROJECT = "MQTT_CLIENT"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- 加载窗口模块
require "mqtt_client_win"

-- 发布消息触发窗口创建（必须在 require 之后，确保订阅已注册）
sys.publish("OPEN_MQTT_CLIENT_WIN")

-- 进入事件循环（必需）
sys.run()
