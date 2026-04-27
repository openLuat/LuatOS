-- netdrv_pc.lua - PC模拟器网卡驱动

local function ip_ready_func(ip, adapter)
    if adapter == socket.LWIP_GP then
        socket.setDNS(adapter, 1, "223.5.5.5")
        socket.setDNS(adapter, 2, "114.114.114.114")
        log.info("netdrv_pc.ip_ready_func", "IP_READY", socket.localIP(socket.LWIP_GP))
    end
end

local function ip_lose_func(adapter)
    if adapter == socket.LWIP_GP then
        log.warn("netdrv_pc.ip_lose_func", "IP_LOSE")
    end
end

sys.subscribe("IP_READY", ip_ready_func)
sys.subscribe("IP_LOSE", ip_lose_func)
