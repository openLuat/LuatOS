--[[
@module  settings_app
@summary 设置模块主入口
@version 1.0
@date    2026.04.02
@author  LuatOS
@usage
本模块为设置功能的主入口，负责：
1. 通知 settings_config_app 进行初始化
2. 协调各个设置子模块的加载
]]

require "settings_config_app"
require "settings_buzz_app"

-- 发布消息通知 settings_config_app 进行初始化
sys.publish("SETTINGS_APP_INIT")

log.info("settings_app", "设置模块初始化完成")
