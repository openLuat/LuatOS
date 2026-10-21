--[[
@module  net_watchdog
@summary 网络看门狗（无 IP / 长时间无成功上报就重启）
@version 1.0
@date    2026.10.20

与硬件看门狗（wdt）互补：
- wdt 管"程序卡死"，由 main.lua 3 秒喂一次；
- 本模块管"程序活着但网络死了"：连续超时没有任何可用 IP，或业务长时间无法成功上报，
  主动重启恢复（现场设备无人值守，重启是最可靠的兜底）。

喂狗方式：业务模块成功后 sys.publish("FEED_NETWORK_WATCHDOG")。
]]

local app_config = require "app_config"
local storage = require "storage"

local M = {}

local last_feed = os.time()
local last_ok_ip = os.time()

sys.subscribe("FEED_NETWORK_WATCHDOG", function()
    last_feed = os.time()
    last_ok_ip = os.time()
end)

local function has_any_ip()
    local ok, v = pcall(function()
        return socket.adapter(socket.dft()) or socket.localIP(socket.LWIP_ETH) ~= "0.0.0.0"
    end)
    return ok and v == true
end

sys.taskInit(function()
    while true do
        sys.wait(30000)
        local c = app_config.load()
        if c.net_watchdog_enable ~= false then
            local timeout = tonumber(c.net_watchdog_timeout) or 900
            local now = os.time()
            if has_any_ip() then
                last_ok_ip = now
            end
            local idle = now - math.max(last_feed, last_ok_ip)
            if idle > timeout then
                log.error("net_watchdog", "网络异常超过", timeout, "秒，重启设备")
                storage.log("watchdog", "网络异常 " .. tostring(idle) .. " 秒，重启")
                sys.wait(500)
                rtos.reboot()
            end
        end
    end
end)

function M.feed()
    last_feed = os.time()
end

function M.get_idle()
    return os.time() - math.max(last_feed, last_ok_ip)
end

return M
