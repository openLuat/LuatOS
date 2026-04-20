--[[
@module  netdrv_wifi
@summary “WIFI STA网卡”驱动模块
@version 1.0
@date    2026.04.15
@usage
本文件为WIFI STA网卡驱动模块，核心业务逻辑为：
1、初始化WIFI网络；
2、连接WIFI路由器；
3、和WIFI路由器之间的连接状态发生变化时，在日志中进行打印；

本文件没有对外接口，直接在其他功能模块中require "netdrv_wifi"就可以加载运行；
]]

local exnetif = require "exnetif"

local function ip_ready_func(ip, adapter)
    if adapter == socket.LWIP_STA then
        socket.setDNS(adapter, 1, "223.5.5.5")
        socket.setDNS(adapter, 2, "114.114.114.114")
        log.info("netdrv_wifi.ip_ready_func", "IP_READY", socket.localIP(socket.LWIP_STA))
    end
end

local function ip_lose_func(adapter)
    if adapter == socket.LWIP_STA then
        log.warn("netdrv_wifi.ip_lose_func", "IP_LOSE")
    end
end

sys.subscribe("IP_READY", ip_ready_func)
sys.subscribe("IP_LOSE", ip_lose_func)

local function wifi_sta_func(evt, data)
    log.info("收到STA事件", evt, data)
end

sys.subscribe("WLAN_STA_INC", wifi_sta_func)

local function netdrv_wifi_task_func()
    exnetif.set_priority_order({
        {
            WIFI = {
                ssid = "admin-降功耗，找合宙！",
                password = "Air123456"
            }
        }
    })
end

sys.taskInit(netdrv_wifi_task_func)
