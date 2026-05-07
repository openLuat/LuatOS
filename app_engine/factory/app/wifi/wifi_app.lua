--[[
@module  wifi_app
@summary WiFi应用模块分发器，根据平台加载对应实现
@version 1.0
@date    2026.05.07
@author  江访
]]--
if _G.model_str:find("Air1601") or _G.model_str:find("Air1602") then
    return require "wifi_app_air1601"
else
    return require "wifi_app_air8000w"
end
