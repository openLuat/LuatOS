--[[
@module  netif_app
@summary netif_app 网络管理模块,开启多网融合功能，演示动态切换WiFi上游网络
@version 1.0
@date    2026.07.14
@author  王城钧
@usage
本文件为网络管理模块，核心业务逻辑为：
1. 通过 exnetif.setproxy 建立 ETH -> STA(WiFi A) 多网融合，启用自动重连
2. 通过 exnetif.switch_upstream_wifi 切换上游 WiFi 到 WiFi B，保持自动重连
本文件没有对外接口，直接在main.lua中require "netif_app"就可以加载运行；
]]

local exnetif = require "exnetif"

-- WiFi A 和 WiFi B 的配置（请替换为实际SSID和密码）
local wifi_a_config = {
    ssid = "116",
    password = "wangshuai123"
}
local wifi_b_config = {
    ssid = "xiaoshuai",
    password = "2894551470"
}

-- 切换到WiFi A后等待多长时间再切到WiFi B（单位：毫秒）
local switch_interval = 30000

-- 以太网公共配置
local eth_config = {
    ethpower_en = 140,
    tp = netdrv.CH390,
    opts = { spi = 1, cs = 12, irq = 21 },
}

--[[
主任务：WiFi A -> ETH 代理 -> 切换为 WiFi B -> ETH 代理
]]
function netif_app_task_func()
    -- 第一阶段：WiFi A → 以太网
    local eth_params = {}
    for k, v in pairs(eth_config) do
        eth_params[k] = v
    end
    eth_params.main_adapter = wifi_a_config
    eth_params.auto_reconnect = true

    local res = exnetif.setproxy(socket.LWIP_ETH, socket.LWIP_STA, eth_params)
    if not res then
        log.error("第一阶段失败：WiFi A → 以太网 代理建立失败")
        return
    end
    log.info("第一阶段成功", "WiFi A → 以太网 代理已建立，自动重连已启用")

    -- WiFi A 工作一段时间
    log.info("WiFi A 将工作", switch_interval / 1000, "秒后切换到 WiFi B")
    sys.wait(switch_interval)

    -- 第二阶段：切换到 WiFi B → 以太网
    wifi_b_config.auto_reconnect = true
    res = exnetif.switch_upstream_wifi(wifi_b_config)
    if not res then
        log.error("第二阶段失败：无法切换到 WiFi B")
        return
    end
    log.info("第二阶段成功", "WiFi B → 以太网 代理已建立，自动重连已启用")

    -- WiFi B 持续工作中
    -- 如需切回 WiFi A，调用 exnetif.switch_upstream_wifi(wifi_a_config) 即可
    log.info("WiFi 切换演示完成，当前使用 WiFi B 提供网络")

    -- 每5秒进行HTTP连接测试，实时监测WIFI网络连接状态，仅供测试需要，量产不需要
    -- while 1 do
    --     local code, headers, body = http.request("GET", "https://httpbin.air32.cn/bytes/2048", nil, nil, {adapter = socket.LWIP_STA, timeout = 5000, debug = false}).wait()
    --     log.info("http执行结果", code, headers, body and #body)
    --     sys.wait(5000)
    -- end
end

sys.taskInit(netif_app_task_func)
