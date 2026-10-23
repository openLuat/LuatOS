socket.dft(socket.LWIP_GP)
local function on_ip_ready(ip, adapter)
    if adapter == socket.LWIP_GP then log.info("netdrv_4g", "IP_READY", ip) end
end
sys.subscribe("IP_READY", on_ip_ready)
local function on_ip_lose(adapter)
    if adapter == socket.LWIP_GP then log.warn("netdrv_4g", "IP_LOSE") end
end
sys.subscribe("IP_LOSE", on_ip_lose)
-- 使用 SIM/APN 自动联网及运营商 DNS；专网 APN 请按所用 SIM 配置。
