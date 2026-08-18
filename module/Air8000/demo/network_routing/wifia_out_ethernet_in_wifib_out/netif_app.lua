--[[
@module  netif_app
@summary 多网融合：WiFi 提供外网，以太网 LAN 口分流上网，演示 WiFi A -> WiFi B 动态切换
@version 1.0
@date    2026.07.21
@author  王城钧
@usage
本文件为网络管理模块，核心业务逻辑为：
1. 调用 exnetif.setproxy 建立 WiFi A -> 以太网 LAN 多网融合代理（首次自动启用掉线重连）
2. 再次调用 exnetif.setproxy 传入 WiFi B 凭证，库自动检测变化并完成 NAPT/WiFi 切换
3. 全程仅使用 exnetif.setproxy 一个接口，无需额外参数、无需关闭/重开代理
本文件没有对外接口，直接在main.lua中require "netif_app"就可以加载运行；
]]

local exnetif = require "exnetif"

local switch_interval = 30000

-- 以太网公共配置
local eth_opts = {
    ethpower_en = 140,
    tp = netdrv.CH390,
    opts = { spi = 1, cs = 12, irq = 21 },
}

function netif_app_task_func()
    -- 第一阶段：WiFi A -> 以太网
    local res = exnetif.setproxy(socket.LWIP_ETH, socket.LWIP_STA, {
        ethpower_en = eth_opts.ethpower_en,
        tp = eth_opts.tp,
        opts = eth_opts.opts,
        main_adapter = {
            ssid = "116",
            password = "wangshuai123"
        }
    })
    if not res then
        log.error("第一阶段失败：WiFi A -> 以太网 代理建立失败")
        return
    end
    log.info("第一阶段成功：WiFi A -> 以太网 代理已建立，自动重连已启用")

    log.info("WiFi A 将工作", switch_interval / 1000, "秒后切换到 WiFi B")
    sys.wait(switch_interval)

    -- 第二阶段：WiFi B -> 以太网（库内部检测 SSID 变化，自动完成切换）
    res = exnetif.setproxy(socket.LWIP_ETH, socket.LWIP_STA, {
        ethpower_en = eth_opts.ethpower_en,
        tp = eth_opts.tp,
        opts = eth_opts.opts,
        main_adapter = {
            ssid = "xiaoshuai",
            password = "2894551470"
        }
    })
    if not res then
        log.error("第二阶段失败：无法切换到 WiFi B")
        return
    end
    log.info("第二阶段成功：WiFi B -> 以太网 代理已建立，自动重连已启用")

    log.info("WiFi 切换演示完成，当前使用 WiFi B 提供网络")
end

sys.taskInit(netif_app_task_func)
