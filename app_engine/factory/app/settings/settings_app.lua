
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
local fe = (_G.project_config and _G.project_config.features) or {}

require "settings_config_app"   -- fskv配置管理（设备名称、IOT账号、存储优先级读写）
if fe.buzzer then
    require "settings_buzz_app"     -- 触摸音效管理（仅当有蜂鸣器）
end
require "settings_about_app"    -- 关于页面信息
require "settings_display_app"  -- 显示亮度管理
require "settings_storage_app"  -- 存储空间信息查询（内置Flash）
if fe.sd_card or fe.nand_flash then
    require "storage_pri_app"       -- 外部存储初始化（仅当有SD卡/NAND Flash）
end
require "settings_memory_app"   -- 系统内存/Vm/PSRAM 信息查询
sys.publish("SETTINGS_APP_INIT")  -- 等待fskv就绪后再发布 SETTINGS_APP_INIT 事件，确保配置模块先行初始化
