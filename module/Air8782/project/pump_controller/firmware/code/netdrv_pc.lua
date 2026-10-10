--[[
@module  netdrv_pc
@summary “PC 模拟器网卡”驱动模块（模拟器调试自动适配用）
@version 1.0.0
@date    2026.09.11
@author  嵌入式软件设计开发代理
@usage
参考官方 demo module/Air780EPM/demo/aircloud/netdrv/netdrv_pc.lua：
1. 监听 "IP_READY" / "IP_LOSE"（PC 模拟器网卡为 socket.ETH0）；
2. 网络就绪时发布 NET_READY，断开时发布 NET_DISCONNECT，供业务模块使用；
3. 显式设置默认网卡为 socket.ETH0（exnetif 扩展库当前不支持模拟器，需手动设置）；
4. 本模块由 netdrv_device 在检测到 PC 模拟器环境时自动加载，其它模块无需直接 require。
本模块无对外接口，直接 require "netdrv_pc" 即加载运行。
]]

local msg_bus = require("msg_bus")

-- 是否已发布过 NET_READY（避免“启动补发”与 IP_READY 事件重复发布）
local net_ready_published = false

-- 发布网络就绪（去重）
local function publish_net_ready(ip)
    if not net_ready_published then
        net_ready_published = true
        log.info("netdrv_pc.ip_ready_func", "IP_READY", ip)
        sys.publish(msg_bus.NET_READY)
    end
end

-- 模拟器网卡获得 IP：设置可靠 DNS，并通知网络就绪
local function ip_ready_func(ip, adapter)
    if adapter == socket.ETH0 then
        -- 增加阿里云与 114 公共 DNS，提升 DNS 稳定性（专网卡/国外网络请按需删除）
        socket.setDNS(adapter, 1, "223.5.5.5")
        socket.setDNS(adapter, 2, "114.114.114.114")
        publish_net_ready(socket.localIP(socket.ETH0))
    end
end

-- 模拟器网卡丢失 IP：通知网络断开
local function ip_lose_func(adapter)
    if adapter == socket.ETH0 then
        log.warn("netdrv_pc.ip_lose_func", "IP_LOSE")
        net_ready_published = false
        sys.publish(msg_bus.NET_DISCONNECT)
    end
end

-- 订阅网络状态事件（PC 模拟器网卡为 socket.ETH0）
sys.subscribe("IP_READY", ip_ready_func)
sys.subscribe("IP_LOSE", ip_lose_func)

-- 设置默认网卡为 socket.ETH0
-- PC 模拟器上的默认网卡需显式设置，因为 exnetif 扩展库当前还不支持模拟器
socket.dft(socket.ETH0)

-- 启动补发：脚本加载时模拟器网卡可能已就绪（IP_READY 早于订阅）导致事件丢失，
-- 此处检查网卡状态并补发一次 NET_READY，确保业务模块能正常启动
if socket.adapter(socket.ETH0) then
    publish_net_ready(socket.localIP(socket.ETH0))
end
