-- nconv: var2-4 fn2-5 tag-short
--[[
@module  netdrv_device
@summary 网络驱动设备分发器，根据平台加载对应网卡驱动
@version 1.0
@date    2026.03.26
@author  江访
]]

if _G.model_str:find("PC") then
    require "netdrv_pc"
else
    require "netdrv_4g"
end
