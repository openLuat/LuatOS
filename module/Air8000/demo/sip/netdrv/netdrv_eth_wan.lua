--[[
@module  netdrv_eth_wan
@summary “通过SPI外挂CH390H芯片的以太网卡”驱动模块（WAN模式）
@version 1.0
@date    2026.04.15
@usage
本文件为“通过SPI外挂CH390H芯片的以太网卡”驱动模块，核心业务逻辑为：
1、开启以太网wan；

直接使用Air8000开发板硬件测试即可；

本文件没有对外接口，直接在其他功能模块中require "netdrv_eth_wan"就可以加载运行；
]]

local static_ip = false

local function ip_ready_func(ip, adapter)
    if adapter == socket.LWIP_ETH then
        socket.setDNS(adapter, 1, "223.5.5.5")
        socket.setDNS(adapter, 2, "114.114.114.114")
        log.info("netdrv_eth_wan.ip_ready_func", "IP_READY", socket.localIP(socket.LWIP_ETH))
    end
end

local function ip_lose_func(adapter)
    if adapter == socket.LWIP_ETH then
        log.warn("netdrv_eth_wan.ip_lose_func", "IP_LOSE")
    end
end

sys.subscribe("IP_READY", ip_ready_func)
sys.subscribe("IP_LOSE", ip_lose_func)

local function eth_wan_setup()
    log.info("ch390", "打开LDO供电")
    gpio.setup(140, 1, gpio.PULLUP)
    local result = spi.setup(1, nil, 0, 0, 8, 25600000)
    log.info("main", "open", result)
    if result ~= 0 then
        log.info("main", "spi open error", result)
        return
    end
    netdrv.setup(socket.LWIP_ETH, netdrv.CH390, {
        spi = 1,
        cs = 12
    })
    sys.wait(1000)
    if static_ip then
        log.info("静态ip", netdrv.ipv4(socket.LWIP_ETH, "192.168.4.100", "255.255.255.0", "192.168.4.1"))
    else
        netdrv.dhcp(socket.LWIP_ETH, true)
    end
    log.info("LWIP_ETH", "mac addr", netdrv.mac(socket.LWIP_ETH))
end

sys.taskInit(eth_wan_setup)
