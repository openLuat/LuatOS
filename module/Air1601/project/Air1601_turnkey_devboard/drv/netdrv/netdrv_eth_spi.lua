--[[
@module  netdrv_eth_spi
@summary "通过SPI外挂CH390H芯片的以太网卡"驱动模块(Air1601版本)
@version 1.0
@date    2026.03.16
@author  朱天华
@usage
本文件为"通过SPI外挂CH390H芯片的以太网卡"驱动模块，核心业务逻辑为：
1、打开CH390H芯片供电开关；
2、初始化spi1，初始化以太网卡，并且在以太网卡上开启DHCP(动态主机配置协议)；
3、以太网卡的连接状态发生变化时，在日志中进行打印；

直接使用Air1601开发板硬件测试即可；

本文件没有对外接口，直接在其他功能模块中require "netdrv_eth_spi"就可以加载运行；
]]

local exnetif = require "exnetif"

local function ip_ready_func(ip, adapter)
    if adapter == socket.LWIP_ETH then
        socket.setDNS(adapter, 1, "223.5.5.5")
        socket.setDNS(adapter, 2, "114.114.114.114")

        log.info("netdrv_eth_spi.ip_ready_func", "IP_READY", socket.localIP(socket.LWIP_ETH))
    end
end

local function ip_lose_func(adapter)
    if adapter == socket.LWIP_ETH then
        log.warn("netdrv_eth_spi.ip_lose_func", "IP_LOSE")
    end
end


sys.subscribe("IP_READY", ip_ready_func)
sys.subscribe("IP_LOSE", ip_lose_func)


-- 配置SPI外接以太网芯片CH390H的单网卡，exnetif.set_priority_order使用的网卡编号为socket.LWIP_ETH
-- 本demo使用Air1601开发板测试，开发板上的硬件配置为：
-- GPIO140为CH390H以太网芯片的供电使能控制引脚
-- 使用spi1，片选引脚使用GPIO8
-- 如果使用的硬件不是Air1601开发板，根据自己的硬件配置修改以下参数
exnetif.set_priority_order({
    {
        ETHERNET = {
            pwrpin = 140,
            tp = netdrv.CH390,
            opts = {spi = 1, cs = 8}
        }
    }
})
