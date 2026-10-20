--[[
@module  netdrv_device
@summary Air8000 出厂固件网卡驱动选择模块
@version 1.0
@date    2026.10.16
@usage
本模块无对外接口，正常模式链路中 require "netdrv_device" 即完成网卡加载。
网卡类型由 factory_config.get_netdev() 决定（多版本一套固件）：
- 4g       → netdrv_4g       ：socket.LWIP_GP，4G 网卡（Air8000/Air8000T/Air8000G）
- wifi     → netdrv_wifi     ：socket.LWIP_STA，WiFi STA（Air8000W，2.4G）
- eth      → netdrv_eth_spi  ：SPI 外挂 CH390H 以太网（Air8000D）
- multiple → netdrv_multiple ：4G+WiFi+ETH 多网卡优先级（Air8000M）
平台兼容：
- PC 模拟器强制 netdrv_pc
- Air8101(WiFi 模组 bsp 名)强制 netdrv_wifi
]]

local factory_config = require "factory_config"

local bsp = rtos.bsp()

if bsp == "PC" then
    -- PC 模拟器网卡
    require "netdrv.netdrv_pc"
elseif bsp == "Air8101" then
    -- Air8101 WiFi 模组
    require "netdrv.netdrv_wifi"
else
    -- Air8000：按版本配置分发
    local netdev = factory_config.get_netdev()
    if netdev == "wifi" then
        require "netdrv.netdrv_wifi"
    elseif netdev == "eth" then
        require "netdrv.netdrv_eth_spi"
    elseif netdev == "multiple" then
        require "netdrv.netdrv_multiple"
    else
        -- 默认 4G
        require "netdrv.netdrv_4g"
    end
end
