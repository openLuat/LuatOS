--[[
@module  app_status
@summary 用户模式状态服务：时间/日期/星期 + 网络摘要
@version 1.1
@date    2026.10.19
@usage
    local status = require "app_status"       -- require 即启动（每秒刷新时间）
    status.time_str()                         -- "08:05"
    status.date_str()                         -- "2026-10-16"
    status.weekday_str()                      -- "星期五"
    status.net_summary()                      -- "以太网 192.168.1.20" / "未联网"

说明
1. 时间由 app_net.sntp() 同步，synced 前显示的是 1970 起的假时间，UI 上会给灰；
2. 本模块只做"取数与发布事件"，不碰 UI，避免业务与界面耦合；
3. 时间、网络任一变化都会发布 STATUS_UPDATED，页面订阅一次即可。
]]

local M = {}

local app_net = require "app_net"

-- ===== 时间 =====

local weekday_map = {
    ["Sunday"] = "星期日", ["Monday"] = "星期一", ["Tuesday"] = "星期二",
    ["Wednesday"] = "星期三", ["Thursday"] = "星期四",
    ["Friday"] = "星期五", ["Saturday"] = "星期六",
}

function M.time_str()
    local t = os.date("*t")
    return string.format("%02d:%02d", t.hour or 0, t.min or 0)
end

function M.date_str()
    local t = os.date("*t")
    return string.format("%04d-%02d-%02d", t.year or 1970, t.month or 1, t.day or 1)
end

function M.weekday_str()
    local en = os.date("%A")
    return weekday_map[en] or en
end

-- ===== 网络摘要 =====

function M.net_summary()
    local adapter, name = app_net.get_active()
    if not adapter or not socket.adapter(adapter) then
        return "未联网"
    end
    local ip = socket.localIP(adapter)
    if ip and ip ~= "" and ip ~= "0.0.0.0" then
        return name .. " " .. ip
    end
    return name
end

-- ===== 周期刷新 =====

local last_minute
sys.timerLoopStart(function()
    local t = os.date("*t")
    local key = string.format("%04d%02d%02d%02d%02d",
        t.year or 1970, t.month or 1, t.day or 1, t.hour or 0, t.min or 0)
    if key ~= last_minute then
        last_minute = key
        sys.publish("STATUS_UPDATED")
    end
end, 1000)

sys.subscribe("APP_NET_CHANGED", function()
    sys.publish("STATUS_UPDATED")
end)

return M
