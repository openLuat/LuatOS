--[[
@module  netdrv_device
@summary 网络驱动设备分发器
]]
local ok, model = pcall(hmeta.model)
if not ok or not model then model = rtos.bsp() end

if type(model) == "string" and (model:find("Air1601") or model:find("Air1602")) then
    require "netdrv_dev_air1601"
else
    require "netdrv_dev_air8000w"
end
