-- nconv: var2-4 fn2-5 tag-short
--[[
@module  netdrv_wifi
@summary "WIFI STA网卡"驱动模块
@version 1.0
@date    2025.07.01
@author  马梦阳
@usage
本文件为WIFI STA网卡驱动模块，核心业务逻辑为：
1、设置默认网卡为STA；
2、监听WIFI连接状态并打印日志；

airlink/wlan 硬件初始化统一由 wifi_app_air1601 负责，避免重复初始化。

本文件没有对外接口，直接在其他功能模块中require "netdrv_wifi"就可以加载运行；
]]
sys.subscribe("IP_READY", function(ip, ad)
    if ad and ad == socket.LWIP_STA then
        log.info("nwf.ip", "IP_READY", socket.localIP(socket.LWIP_STA))
    end
end)

sys.subscribe("IP_LOSE", function(ad)
    if ad and ad == socket.LWIP_STA then
        log.warn("nwf.los", "IP_LOSE")
    end
end)

sys.subscribe("WLAN_STA_INC", function(evt, data)
    log.info("sta", evt, data)
end)

-- 仅设置默认网卡，不初始化硬件
socket.dft(socket.LWIP_STA)
