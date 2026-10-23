--[[
@module  netdrv_4g
@summary “4G网卡”驱动模块 
@version 1.0
@date    2025.07.01
@usage
本文件为4G网卡驱动模块，核心业务逻辑为：
1、监听"IP_READY"和"IP_LOSE"，在日志中进行打印；

本文件没有对外接口，直接在其他功能模块中require "netdrv_4g"就可以加载运行；
]]

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
