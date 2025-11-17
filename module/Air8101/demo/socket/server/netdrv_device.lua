--[[
@module  netdrv_device
@summary 网络驱动设备功能模块 
@version 1.0
@date    2025.11.15
@author  王世豪
@usage
本文件为网络驱动设备功能模块，核心业务逻辑为：根据项目需求，选择并且配置合适的网卡(网络适配器)
1、netdrv_wifi_sta：socket.LWIP_STA，WIFI STA网卡；
2、netdrv_wifi_ap：socket.LWIP_AP，WIFI AP网卡；
2、netdrv_eth_rmii：socket.LWIP_ETH，通过MAC层的rmii接口外挂PHY芯片（LAN8720Ai）的以太网卡；
3、netdrv_eth_spi：socket.LWIP_USER1，通过SPI外挂CH390H芯片的以太网卡；

根据自己的项目需求，只需要require以上四种中的一种即可；


本文件没有对外接口，直接在main.lua中require "netdrv_device"就可以加载运行；
]]


-- 根据自己的项目需求，只需要require以下四种中的一种即可；

-- 加载“WIFI STA网卡”驱动模块
-- require "netdrv_wifi_sta"

-- 加载“WIFI AP网卡”驱动模块
require "netdrv_wifi_ap"

-- 加载“通过MAC层的rmii接口外挂PHY芯片（LAN8720Ai）的以太网卡”驱动模块
-- require "netdrv_eth_rmii"

-- 加载“通过SPI外挂CH390H芯片的以太网卡”驱动模块
-- require "netdrv_eth_spi"
