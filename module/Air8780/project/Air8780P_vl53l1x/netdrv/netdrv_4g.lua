--[[
@module  netdrv_4g
@summary "4G网卡"驱动模块
@version 1.0
@date    2026.07.21
@author  江访
@usage
本文件为4G网卡驱动模块，核心业务逻辑为：
1、监听"IP_READY"和"IP_LOSE"，在日志中进行打印；

本文件没有对外接口，直接在其他功能模块中require "netdrv_4g"就可以加载运行；
]]

local function ip_ready_func(ip, adapter)
    if adapter == socket.LWIP_GP then
        -- 设置DNS服务器IP地址
        socket.setDNS(adapter, 1, "223.5.5.5")
        socket.setDNS(adapter, 2, "114.114.114.114")

        log.info("netdrv_4g", "IP_READY", socket.localIP(socket.LWIP_GP))
    end
end

local function ip_lose_func(adapter)
    if adapter == socket.LWIP_GP then
        log.warn("netdrv_4g", "IP_LOSE")
    end
end

-- 订阅"IP_READY"和"IP_LOSE"两种消息
sys.subscribe("IP_READY", ip_ready_func)
sys.subscribe("IP_LOSE", ip_lose_func)

-- 在Air780EPM/Air8780P上，内核固件运行起来之后，默认网卡就是socket.LWIP_GP
