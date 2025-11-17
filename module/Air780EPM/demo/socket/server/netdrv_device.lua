--[[
@module  netdrv_device
@summary 网络驱动设备功能模块 
@version 1.0
@date    2025.11.15
@author  王世豪
@usage
本文件为网络驱动设备功能模块，核心业务逻辑为：根据项目需求，选择并且配置合适的网卡(网络适配器)
1、netdrv_eth_spi：socket.LWIP_ETH，通过SPI外挂CH390H芯片的以太网卡；

本文件没有对外接口，直接在main.lua中require "netdrv_device"就可以加载运行；
]]

-- 加载“通过SPI外挂CH390H芯片的以太网卡”驱动模块
require "netdrv_eth_spi"
