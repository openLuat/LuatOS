--[[
@module  netdrv_device
@summary 网络驱动设备选择
@version 1.0
@date    2026.10.20
@usage
根据 rtos.bsp() 选择并加载对应的网卡驱动。
Air1780P 无 4G，开发板通过板载以太网口（CH390H，SPI0）联网。
]]

if rtos.bsp() == "PC" then
    -- PC 模拟器网卡
    require "netdrv_pc"
else
    -- 板载以太网（SPI 外挂 CH390H）
    require "netdrv_eth_spi"
end
