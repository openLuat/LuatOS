--[[
@module  airlbs_app
@summary 多 WiFi 定位（直接用官方 airlbs 扩展库，本文件只做配置 / 扫 WiFi / 定时）
@version 2.0
@date    2026.10.19
@usage
    local lbs = require "airlbs_app"
    lbs.init()
    lbs.get()            -- { lat =, lng =, ts = } 或 nil
    sys.subscribe("AIRLBS_LOCATION", function(lat, lng) ... end)

配置（config_*.lua 的 airlbs 表）
    enabled / project_id / project_key
    interval 默认 300 秒（代码下限 60）；scan_timeout 默认 10 秒

说明
1. 组包、鉴权（HMAC-SHA1）、UDP 收发全部交给官方 airlbs 扩展库
   （script/libs/airlbs.lua），本文件不再自己拼协议。
2. Air8101 没有蜂窝，airlbs 就是「多 WiFi 定位」：必须把扫描到的
   BSSID + RSSI 通过 wifi_info 传给库，库里走 Air8101 分支组包。
3. 官方库内部用 "airlbs" 作任务名和 socket owner，本文件的任务不能重名，
   否则消息会串（所以这里用 sys.taskInit，不注册同名任务）。
4. 烧录要带扩展库（airlbs 依赖 libnet），否则 require "airlbs" 会失败。
]]

local airlbs = require "airlbs"     -- 必须字面量 require，烧录合并器才会打包

local M = {}

local state
local task_started = false

local function cfg()
    return (_G.project_config or {}).airlbs or {}
end

local function valid_str(v)
    return type(v) == "string" and #v > 0
end

--- 扫描附近 WiFi，返回库要的格式：{ { bssid = 二进制6字节, rssi = number }, ... }
local function scan_wifi(timeout_s)
    if not wlan then return {} end

    pcall(wlan.init)
    pcall(wlan.scan)
    if not sys.waitUntil("WLAN_SCAN_DONE", (timeout_s or 10) * 1000) then
        log.warn("airlbs", "WiFi 扫描超时")
        return {}
    end

    local result = wlan.scanResult() or {}
    local list = {}
    for k, v in pairs(result) do
        local bssid, rssi
        if type(k) == "number" and type(v) == "table" then
            bssid, rssi = v.bssid, v.rssi
        elseif type(v) == "table" then
            bssid, rssi = v.bssid, v.rssi
        end
        if bssid and type(rssi) == "number" then
            list[#list + 1] = { bssid = bssid, rssi = rssi }
        end
        if #list >= 20 then break end     -- 20 个足够，包越小越快
    end
    log.info("airlbs", "扫描到", #list, "个 WiFi")
    return list
end

local function main_task()
    -- 等网络（官方示例同款写法）
    while not socket.adapter(socket.dft()) do
        sys.waitUntil("IP_READY", 1000)
    end

    -- 时间戳参与鉴权，先对时（失败也继续，用系统时间）
    if os.time() < 1600000000 then
        socket.sntp()
        sys.waitUntil("NTP_UPDATE", 10000)
    end

    local c = cfg()
    local interval = tonumber(c.interval) or 300
    if interval < 60 then interval = 60 end
    local scan_timeout = tonumber(c.scan_timeout) or 10

    -- 打一行实际出口：失败时先看这里是不是 4G/WiFi/以太网
    local dft = socket.dft()
    log.info("airlbs", "定位任务启动", "出口", tostring(dft), socket.localIP(dft) or "-",
        "间隔", interval, "秒", "扫描超时", scan_timeout, "秒")

    while true do
        local wifi = scan_wifi(scan_timeout)

        local ok, data = airlbs.request({
            project_id = c.project_id,
            project_key = c.project_key,
            wifi_info  = wifi,
            timeout    = 15000,
            adapter    = socket.dft(),     -- 跟随当前默认网卡（4G / WiFi / 以太网通用）
        })

        if ok and data then
            state = { lat = data.lat, lng = data.lng, ts = os.time() }
            log.info("airlbs", "定位成功", "lat", data.lat, "lng", data.lng)
            sys.publish("AIRLBS_LOCATION", data.lat, data.lng)
        else
            log.warn("airlbs", "定位失败:", tostring(data))
        end

        sys.wait(interval * 1000)
    end
end

-- ===== 对外接口 =====

--- 启动（幂等）：enabled=false 或没配项目时只打日志
function M.init()
    if task_started then return true end

    local c = cfg()
    if c.enabled ~= true then
        log.info("airlbs", "未启用（config.airlbs.enabled=false），不定位")
        return false
    end
    if not valid_str(c.project_id) or not valid_str(c.project_key) then
        log.warn("airlbs", "未配置 project_id / project_key（config.airlbs），不定位")
        return false
    end
    if #c.project_id ~= 6 then
        log.warn("airlbs", "project_id 应为 6 位，当前:", c.project_id)
    end

    task_started = true
    sys.taskInit(main_task)
    return true
end

--- 最近一次定位结果
function M.get()
    return state
end

--- 手动触发一轮：下一轮循环会自然执行，这里只返回当前缓存
function M.locate_now()
    return state ~= nil
end

log.info("airlbs", "模块已加载（官方 airlbs 库 + 本地 WiFi 扫描）")

return M
