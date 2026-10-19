--[[
@module  netdrv_4g
@summary 4G 网卡驱动
@version 1.0
@date    2026.10.16
@usage
监听 "IP_READY" 和 "IP_LOSE" 事件，配置 DNS 并打印网络状态。
直接 require "netdrv_4g" 即可加载运行。
]]

local function ip_ready_func(ip, adapter)
    if adapter == socket.LWIP_GP then
        socket.setDNS(adapter, 1, "223.5.5.5")
        socket.setDNS(adapter, 2, "114.114.114.114")
        log.info("netdrv_4g.ip_ready_func", "IP_READY", socket.localIP(socket.LWIP_GP))
    end
end

local function ip_lose_func(adapter)
    if adapter == socket.LWIP_GP then
        log.warn("netdrv_4g.ip_lose_func", "IP_LOSE")
    end
end

sys.subscribe("IP_READY", ip_ready_func)
sys.subscribe("IP_LOSE", ip_lose_func)
