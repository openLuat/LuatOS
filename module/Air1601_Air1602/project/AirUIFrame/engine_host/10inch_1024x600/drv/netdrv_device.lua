--[[
@module  netdrv_device
@summary 网络驱动设备功能模块
@version 1.0
@date    2025.07.24
@author  朱天华
@usage
本文件为网络驱动设备功能模块，核心业务逻辑为：根据项目需求，选择并且配置合适的网卡(网络适配器)
1、netdrv_4g：socket.LWIP_GP，4G网卡；
2、netdrv_wifi：socket.LWIP_STA，WIFI STA网卡；
3、netdrv_eth_spi：socket.LWIP_ETH，通过SPI外挂CH390H芯片的以太网卡；
4、netdrv_multiple：可以配置多种网卡的优先级，按照优先级配置，使用其中一种网卡连接外网；
5、netdrv_pc：pc模拟器上的网卡

根据自己的项目需求，只需要require以上五种中的一种即可；


本文件没有对外接口，直接在main.lua中require "netdrv_device"就可以加载运行；
]]


-- 根据自己的项目需求，只需要require以下五种中的一种即可；

-- 加载“airlink-4G网卡”驱动模块
-- require "netdrv_4g"

-- 加载“airlink-STA网卡”驱动模块
require "netdrv_wifi"



-- 加载“pc模拟器网卡”驱动模块
-- require "netdrv_pc"


-- 网络选择配置：修改此变量来选择使用以太网还是WiFi
-- NETWORK_MODE = "ETHERNET"  -- 使用以太网
-- NETWORK_MODE = "WIFI"      -- 使用WiFi
-- NETWORK_MODE = "WIFI"  -- 默认使用WiFi

if rtos.bsp() == "PC" then
    -- 加载“pc模拟器网卡”驱动模块
    require "netdrv_pc"
elseif string.find(rtos.bsp(), "Air1601") or string.find(rtos.bsp(), "Air1602") then
    -- Air1601/Air1602 的WiFi联网逻辑由 wifi_app 按需初始化, 不在开机时自动加载
    -- 如有线网需要, 取消下面注释
    -- if NETWORK_MODE == "ETHERNET" then
    --     log.info("netdrv_device", "使用以太网网络模式")
    --     require "netdrv_eth_spi"
end
