--[[
@module  netdrv_device
@summary 网络驱动设备功能模块（原样保留）
@version 1.0
@date    2025.07.24
@author  朱天华
@usage
根据项目需求选择并且配置合适的网卡(网络适配器)
]]

if rtos.bsp() == "PC" then
    -- 加载"pc模拟器网卡"驱动模块
    require "netdrv_pc"
elseif rtos.bsp() ~= "Air8101" then
    -- 加载"4G网卡"驱动模块
    require "netdrv_4g"
end
