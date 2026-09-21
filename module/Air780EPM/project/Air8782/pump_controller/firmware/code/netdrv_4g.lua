--[[
@module  netdrv_4g
@summary “4G网卡”驱动模块（本项目单 4G 上网）
@version 1.0.0
@date    2026.09.11
@author  嵌入式软件设计开发代理
@usage
参考官方 demo module/Air780EPM/demo/aircloud/netdrv/netdrv_4g.lua：
1. 监听 "IP_READY" / "IP_LOSE"；
2. 网络就绪时发布 NET_READY，断开时发布 NET_DISCONNECT，供业务模块使用。
本模块无对外接口，直接 require "netdrv_4g" 即加载运行。
]]

local msg_bus = require("msg_bus")

-- 4G 网卡获得 IP：设置可靠 DNS，并通知网络就绪
local function ip_ready_func(ip, adapter)
    if adapter == socket.LWIP_GP then
        -- 增加阿里云与 114 公共 DNS，提升 DNS 稳定性（专网卡/国外网络请按需删除）
        socket.setDNS(adapter, 1, "223.5.5.5")
        socket.setDNS(adapter, 2, "114.114.114.114")

        log.info("netdrv_4g.ip_ready_func", "IP_READY", socket.localIP(socket.LWIP_GP))
        sys.publish(msg_bus.NET_READY)
    end
end

-- 4G 网卡丢失 IP：通知网络断开
local function ip_lose_func(adapter)
    if adapter == socket.LWIP_GP then
        log.warn("netdrv_4g.ip_lose_func", "IP_LOSE")
        sys.publish(msg_bus.NET_DISCONNECT)
    end
end

-- 订阅网络状态事件（Air780EPM 内核启动后默认网卡即 socket.LWIP_GP）
sys.subscribe("IP_READY", ip_ready_func)
sys.subscribe("IP_LOSE", ip_lose_func)
