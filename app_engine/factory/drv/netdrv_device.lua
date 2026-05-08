--[[
@module  netdrv_device
@summary 网络驱动设备分发器，根据平台加载对应网卡驱动
@version 1.0
@date    2026.03.26
@author  江访
]]
if _G.model_str:find("Air1601") or _G.model_str:find("Air1602") then
    require "netdrv_wifi_air1601"
elseif _G.model_str:find("Air8000") then
    require "netdrv_4g_air8000w"
elseif _G.model_str:find("Air8101") then
    require "netdrv_wifi_air8101"
elseif _G.model_str:find("PC") then
    require "netdrv_pc"
end