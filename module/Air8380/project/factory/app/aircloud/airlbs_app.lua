--[[
@module  airlbs_app
@summary airlbs 多基站 / 多基站+WiFi 定位
@version 1.0
@date    2026.10.20

说明：
1. airlbs 是**收费服务**，需要在 https://iot.openluat.com/lbs/bs 创建项目，拿到 6 位 project_id 与 project_key；
2. 未配置 id/key 时本模块直接跳过，不会产生无效请求；
3. 依赖 libnet.lua + airlbs.lua（已随工程携带）；
4. 定位结果通过 sys.publish("Airlbs_LOCATION_UPDATE", lat, lng) 广播，
   由 aircloud_app 订阅并上报（字段 512 经度 / 513 纬度）；
5. 定位前必须时间同步（服务端校验时间戳），所以流程是：等 IP → SNTP → 循环定位。

注意：WiFi 扫描会短暂影响 WiFi STA 连接，`lbs_wifi_scan = false` 时只用基站定位。
]]

local airlbs = require "airlbs"
local app_config = require "app_config"
local storage = require "storage"

local M = {}

local lat, lng = nil, nil

function M.get_location()
    return lat, lng
end

-- 兼容不同返回结构：优先取 table 字段，取不到再从 JSON 文本里抠
local function extract(data)
    if type(data) == "table" then
        if data.lat and data.lng then
            return tostring(data.lat), tostring(data.lng)
        end
    end
    local s = json.encode(data or {})
    local la = s:match('"lat"%s*:%s*([0-9%.%-]+)')
    local ln = s:match('"lng"%s*:%s*([0-9%.%-]+)')
    return la, ln
end

local function scan_wifi()
    if not wlan then return nil end
    local ok = pcall(function()
        wlan.init()
        wlan.scan()
    end)
    if not ok then return nil end
    sys.waitUntil("WLAN_SCAN_DONE", 10000)
    local info = wlan.scanResult()
    if type(info) == "table" and #info > 0 then
        return info
    end
    return nil
end

local function lbs_task()
    local c = app_config.load()
    if c.lbs_enabled == false then
        log.info("lbs", "定位未启用，跳过")
        return
    end
    if not c.lbs_project_id or #tostring(c.lbs_project_id) == 0
        or not c.lbs_project_key or #tostring(c.lbs_project_key) == 0 then
        log.warn("lbs", "未配置 lbs_project_id / lbs_project_key，跳过定位")
        return
    end

    -- 等任意链路拿到 IP
    while not socket.adapter(socket.dft()) do
        sys.waitUntil("IP_READY", 1000)
    end

    -- 服务端校验时间戳，先授时
    socket.sntp()
    if not sys.waitUntil("NTP_UPDATE", 10000) then
        log.warn("lbs", "NTP 超时，仍尝试定位")
    end

    local fail_count = 0
    while true do
        local cfg = app_config.load()
        local wifi_info = nil
        if cfg.lbs_wifi_scan ~= false then
            wifi_info = scan_wifi()
            log.info("lbs", "WiFi 扫描数量:", wifi_info and #wifi_info or 0)
        end

        local ok, data = airlbs.request({
            project_id = cfg.lbs_project_id,
            project_key = cfg.lbs_project_key,
            wifi_info = wifi_info,
            timeout = 10000,
        })

        if ok and data then
            local la, ln = extract(data)
            if la and ln then
                lat, lng = la, ln
                log.info("lbs", "定位成功", lat, lng)
                storage.log("lbs", "定位 " .. lat .. "," .. ln)
                sys.publish("Airlbs_LOCATION_UPDATE", lat, lng)
                fail_count = 0
            else
                log.warn("lbs", "返回数据无经纬度:", json.encode(data))
            end
        else
            fail_count = fail_count + 1
            -- 常见原因：id/key 错误、套餐次数用尽、无网络
            log.warn("lbs", "定位失败，已连续失败 " .. fail_count .. " 次，检查 project_id/key 与套餐余量")
            if fail_count == 3 then
                storage.log("lbs", "连续 3 次定位失败，检查 ID/Key 与套餐")
            end
        end

        local interval = tonumber(app_config.load().lbs_interval) or 600
        if interval < 60 then interval = 60 end   -- 频率过高会被服务端限流
        sys.wait(interval * 1000)
    end
end

sys.taskInit(lbs_task)

return M
