--[[
@module  netdrv_device
@summary 网络驱动设备选择
@version 1.0
@date    2026.10.16
@usage
根据 rtos.bsp() 选择并加载对应的网卡驱动。
]]

if rtos.bsp() == "PC" then
    -- PC 模拟器网卡
    require "netdrv_pc"
else
    -- 4G 网卡（Air780EGP 原生 4G）
    require "netdrv_4g"
end
