--[[
@module  netdrv_4g
@summary “4G网卡”驱动模块
@version 1.0
@date    2025.07.01
@author  朱天华
@usage
本文件为4G网卡驱动模块，核心业务逻辑为：
1、监听"IP_READY"和"IP_LOSE"，在日志中进行打印；

在 Air780EHM/EHV/EGH 上，内核固件启动后默认网卡就是 socket.LWIP_GP，
所以这里不需要像以太网那样调用 exnetif 配置网卡，只要订阅联网事件即可。

本文件没有对外接口，直接在其他功能模块中require "netdrv_4g"就可以加载运行；
]]

local function ip_ready_func(ip, adapter)
    if adapter == socket.LWIP_GP then
        -- 这里默认加入两个自定义 DNS（阿里云 / 国内通用），提高 DNS 稳定性；
        -- **如果使用专网卡，请把下面两行注释掉**（专网 DNS 由网络侧下发）
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

-- 4G 附着成功、拿到 IP 后，内核固件会产生"IP_READY"消息
-- 4G 断网（掉网/欠费/信号丢失）后，会产生"IP_LOSE"消息
-- 也可以在任何时刻调用 socket.adapter(socket.LWIP_GP) 判断当前状态
sys.subscribe("IP_READY", ip_ready_func)
sys.subscribe("IP_LOSE", ip_lose_func)
