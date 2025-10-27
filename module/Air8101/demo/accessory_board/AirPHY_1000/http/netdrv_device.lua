--[[
@module  netdrv_device
@summary 网络驱动设备功能模块
@version 1.0
@date    2025.09.24
@author  王城钧
@usage
本文件为网络驱动设备功能模块，核心业务逻辑为：根据项目需求，选择并且配置合适的网卡(网络适配器)
1、netdrv_ethernet_spi：socket.LWIP_ETH，通过SPI外挂CH390H芯片的以太网卡；
2、netdrv_multiple：可以配置多种网卡的优先级，按照优先级配置，使用其中一种网卡连接外网；

根据自己的项目需求，只需要require以上其中的一种即可；


本文件没有对外接口，直接在main.lua中require "netdrv_device"就可以加载运行；
]]


-- 根据自己的项目需求，只需要require以下其中的一种即可；

-- 加载“通过MAC层的rmii接口外挂PHY芯片（LAN8720Ai）的以太网卡”驱动模块
require "netdrv_eth_rmii"

-- 加载“可以配置优先级的多种网卡”驱动模块
-- require "netdrv_multiple"

-- 加载“WIFI STA网卡”驱动模块
-- require "netdrv_wifi"
