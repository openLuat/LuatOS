--[[
@module  netif_app
@summary 多网融合：WiFi 提供外网，以太网 LAN 口分流上网，演示 WiFi A → WiFi B 动态切换
@version 1.0
@date    2026.07.16
@author  王城钧
@usage
本文件为网络管理模块，核心业务逻辑为：
1. 调用 exnetif.set_priority_order 建立 WiFi A → 以太网 LAN 多网融合代理，启用掉线自动重连
2. 再次调用 exnetif.set_priority_order 将上游 WiFi 切换为 WiFi B，库内部自动处理 NAPT/WiFi 切换
3. 通过HTTP GET连接测试STA网卡网络情况
本文件没有对外接口，直接在main.lua中require "netif_app"就可以加载运行；
]]

local exnetif = require "exnetif"

-- WiFi A 和 WiFi B 的配置（请替换为实际SSID和密码）
local wifi_a_config = {
    WIFI = {
        ssid = "116",
        password = "wangshuai123",
        auto_reconnect = true,
        proxy_adapters = { socket.LWIP_ETH },
    }
}
local wifi_b_config = {
    WIFI = {
        ssid = "xiaoshuai",
        password = "2894551470",
        auto_reconnect = true,
        proxy_adapters = { socket.LWIP_ETH },
    }
}

-- 以太网硬件配置（与 WiFi 独立，WiFi 通过 proxy_adapters 引用）
local eth_config = {
    ETHERNET = {
        pwrpin = 140,
        tp = netdrv.CH390,
        opts = { spi = 1, cs = 12, irq = 21 },
    }
}

-- 切换到WiFi A后等待多长时间再切到WiFi B（单位：毫秒）
local switch_interval = 30000

--[[
主任务：WiFi A -> ETH 代理 -> 切换为 WiFi B -> ETH 代理
全程仅使用 exnetif.set_priority_order 一个接口
]]
function netif_app_task_func()
    -- 第一阶段：WiFi A -> 以太网
    local res = exnetif.set_priority_order({ wifi_a_config, eth_config })
    if not res then
        log.error("第一阶段失败", "WiFi A -> 以太网 代理建立失败")
        return
    end
    log.info("第一阶段成功", "WiFi A -> 以太网 代理已建立，自动重连已启用")

    -- WiFi A 工作一段时间
    log.info("WiFi A 将工作", switch_interval / 1000, "秒后切换到 WiFi B")
    sys.wait(switch_interval)

    -- 第二阶段：切换到 WiFi B -> 以太网（库内部检测凭证变化自动完成 NAPT/WiFi 切换）
    res = exnetif.set_priority_order({ wifi_b_config, eth_config })
    if not res then
        log.error("第二阶段失败", "无法切换到 WiFi B")
        return
    end
    log.info("第二阶段成功", "WiFi B -> 以太网 代理已建立，自动重连已启用")

    log.info("WiFi 切换演示完成，当前使用 WiFi B 提供网络")

    -- 每5秒进行HTTP连接测试，实时监测WIFI网络连接状态，仅供测试需要，量产不需要
    while 1 do
        local code, headers, body = http.request("GET", "https://httpbin.air32.cn/bytes/2048", nil, nil, {adapter = socket.LWIP_STA, timeout = 5000, debug = false}).wait()
        log.info("http执行结果", code, headers, body and #body)
        sys.wait(5000)
    end
end

sys.taskInit(netif_app_task_func)
