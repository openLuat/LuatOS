--[[
@module  netdrv_device
@summary 网络驱动设备功能模块
@version 1.0
@date    2025.07.24
@author  马梦阳
@usage
本文件为网络驱动设备功能模块，核心业务逻辑为：根据项目需求，选择并且配置合适的网卡(网络适配器)
1、netdrv_eth_spi：socket.LWIP_ETH，通过SPI外挂CH390H芯片的以太网卡；
2、netdrv_4g：socket.LWIP_GP，4G网卡；
（本 demo 只带这两种；需要多网卡优先级时自行引入 netdrv_multiple）

**用哪张网卡由 gb28181_config.lua 的 M.NETDRV 决定**（"4g" / "eth"），
这里不再手工开关 require：
  · 4g  —— 板载 4G。设备在运营商 NAT 后面，平台的 INVITE 只能顺着设备
           主动建立的 TCP 信令连接进来，所以 TRANSPORT 用 tcp（config 默认）；
  · eth —— SPI 外挂 CH390H。局域网/专网用，IP 固定，平台可以直接连设备。

本文件没有对外接口，直接在main.lua中require "netdrv_device"就可以加载运行；
]]

local cfg = require "gb28181_config"

-- 未配置时按以太网处理；gb28181_config.lua 已显式给出默认值 "4g"
if (cfg.NETDRV or "eth") == "eth" then
    -- 通过SPI外挂CH390H芯片的以太网卡
    require "netdrv_eth_spi"
else
    -- 4G网卡
    require "netdrv_4g"
end
