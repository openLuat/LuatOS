--[[
@module  settings_app
@summary 设置模块主入口
@version 1.0
@date    2026.04.02
@author  江访
@usage
本模块为设置功能的主入口，负责：
1. 通知 settings_config_app 进行初始化
2. 协调各个设置子模块的加载
]]

require "settings_config_app"
require "settings_buzz_app"
require "settings_about_app"
require "settings_display_app"
require "settings_storage_app"
require "settings_memory_app"

sys.publish("SETTINGS_APP_INIT")