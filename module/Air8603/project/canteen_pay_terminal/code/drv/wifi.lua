--[[
@module  wifi
@summary Air8603 W 系列 WiFi 联网（Air1603 ↔ Airlink UART3 ↔ Air6205A ↔ wlan）
@note    按官方 script/libs/exnetif.lua 的 setup_airlink_wifi 顺序精简而来，
         不引入整套 exnetif，保持工程最简、Luatools 可直接打包下载
]]

local CFG = require "config"
local M = { ready = false }

local function wifi_task()
    local w = CFG.wifi

    -- 1) 6205 模组进入 UART 模式：RX/TX 先下拉 1 秒再释放（官方硬件初始化时序）
    gpio.setup(22, nil, gpio.PULLDOWN)
    gpio.setup(23, nil, gpio.PULLDOWN)
    sys.wait(1000)
    gpio.close(22)
    gpio.close(23)

    -- 2) Airlink 链路 + WHALE 网卡桥接
    uart.setup(w.uart_id, w.baud, 8, 1)
    airlink.config(airlink.CONF_UART_ID, w.uart_id)
    airlink.init()
    netdrv.setup(socket.LWIP_STA, netdrv.WHALE)
    airlink.start(airlink.MODE_UART)

    -- 3) 连路由器；IP_READY 由底层在拿到 IP 后发布
    wlan.init()
    sys.wait(1000)
    log.info("wifi", "connect", w.ssid)
    local ok = wlan.connect(w.ssid, w.password, 1)
    log.info("wifi", "wlan.connect", ok)
end

function M.start()
    sys.taskInit(wifi_task)
end

-- 在协程里等网络就绪（IP_READY）
function M.wait_ready(timeout)
    if M.ready then return true end
    local _, ip, adapter = sys.waitUntil("IP_READY", timeout or CFG.limit.wifi_wait_ms)
    if ip then
        M.ready = true
        -- 拿到 IP 之后再设 DNS（与官方 exnetif 的 IP_READY 订阅一致）
        socket.setDNS(socket.LWIP_STA, 1, "114.114.114.114")
        socket.setDNS(socket.LWIP_STA, 2, "223.5.5.5")
        log.info("wifi", "IP_READY", ip, adapter)
    end
    return M.ready
end

return M
