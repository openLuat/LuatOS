-- Air8000 内核启动后默认使用 4G 网卡。这里只记录网络状态；
-- 专网卡或海外网络不要在这里强制设置公共 DNS。
local function ip_ready(ip, adapter)
    if adapter == socket.LWIP_GP then
        log.info("sip_record.net", "IP_READY", ip or socket.localIP(adapter))
    end
end

local function ip_lose(adapter)
    if adapter == socket.LWIP_GP then
        log.warn("sip_record.net", "IP_LOSE")
    end
end

sys.subscribe("IP_READY", ip_ready)
sys.subscribe("IP_LOSE", ip_lose)
