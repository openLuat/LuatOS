--[[
@module  netdrv_device
@summary 网络驱动设备功能模块
@version 1.0
@date    2025.11.4
@author  拓毅恒
@usage
本文件为网络驱动设备功能模块，核心业务逻辑为：根据项目需求，选择并且配置合适的网卡(网络适配器)
1、netdrv_ap：socket.LWIP_AP，WIFI AP网卡；
2、netdrv_wifi：socket.LWIP_STA，WIFI STA网卡；
3、netdrv_eth_spi：socket.LWIP_ETH，通过SPI外挂CH390H芯片的以太网卡；

无论选择哪种网卡模式，在成功联网后都会发布"CREATE_OK"事件，用于通知httpsrv_start.lua启动HTTP服务器。

使用说明：取消注释下面对应网卡的require语句即可使用该网卡模式。
本文件没有对外接口，直接在main.lua中require "netdrv_device"就可以加载运行；
]]

-- 配置选择的网卡模式，取消注释对应行以启用

-- 加载"WIFI AP网卡"驱动模块（默认启用）
require "netdrv_ap"

-- 加载"WIFI STA网卡"驱动模块
-- require "netdrv_wifi"

-- 加载“通过MAC层的rmii接口外挂PHY芯片（LAN8720Ai）的以太网卡”驱动模块
-- require "netdrv_eth_rmii"

-- 加载“通过SPI外挂CH390H芯片的以太网卡”驱动模块
-- require "netdrv_eth_spi"
