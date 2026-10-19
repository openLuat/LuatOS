--[[
@module  netdrv_pc
@summary PC 模拟器网卡驱动
@version 1.0
@date    2026.10.16
@usage
监听 "IP_READY"/"IP_LOSE"，设置默认网卡为 ETH0，并构造 mobile.imei 桩。
直接 require "netdrv_pc" 即可加载运行。
]]

local function ip_ready_func(ip, adapter)
    if adapter == socket.ETH0 then
        socket.setDNS(adapter, 1, "223.5.5.5")
        socket.setDNS(adapter, 2, "114.114.114.114")
        log.info("netdrv_pc.ip_ready_func", "IP_READY", socket.localIP(socket.ETH0))
    end
end

local function ip_lose_func(adapter)
    if adapter == socket.ETH0 then
        log.warn("netdrv_pc.ip_lose_func", "IP_LOSE")
    end
end

sys.subscribe("IP_READY", ip_ready_func)
sys.subscribe("IP_LOSE", ip_lose_func)

-- 设置默认网卡为 ETH0
socket.dft(socket.ETH0)

-- PC 模拟器上构造唯一的设备 ID
_G.mobile = {}
function mobile.imei()
    return "pc_simulator"
end
