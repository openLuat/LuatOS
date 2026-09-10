--[[
@module  netdrv_pc
@summary "pc模拟器网卡"驱动模块（原样保留）
@version 1.0
@date    2025.07.01
@author  朱天华
@usage
本文件为pc模拟器网卡驱动模块，核心业务逻辑为：
1、监听"IP_READY"和"IP_LOSE"，在日志中进行打印；

本文件没有对外接口，直接在其他功能模块中require "netdrv_pc"就可以加载运行；
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

-- 设置默认网卡为socket.ETH0
socket.dft(socket.ETH0)

-- PC模拟器上构造一个唯一的ID
_G.mobile = {}
function mobile.imei()
    return "zhutianhua1"
end
