--[[
@module  net_mgr
@summary WiFi 连接与信号强度管理（wlan 核心库）
@version 1.1.0
@date    2026.10.21
@usage
  require "net_mgr" 后自动联网，状态通过消息通知 UI：
    sys.subscribe("NET_STATUS", function(n) ... end)
    n = { ready = bool, rssi = number|nil, ip = string|nil, ssid = string|nil }
  信号格数：net_mgr.level(rssi) -> 0~4

  连不上时，串口日志会打印周围扫描到的 AP 列表，便于定位：
    - 扫不到任何 AP  → 天线/射频问题
    - 扫到 AP 但没有目标 SSID → 热点是 5GHz / 隐藏 / 太远（Air8101 只支持 2.4GHz）
    - CONNECTED 后拿不到 IP → DHCP 超时(260)
    - 断开原因 258 = 密码错误
]]

local cfg = require "hw_config"

local net = {
    ready = false,
    rssi  = nil,
    ip    = nil,
    ssid  = "",
}

-- 断开原因（wlan 文档约定）
local REASON = {
    [256] = "信号丢失",
    [257] = "找不到该 SSID",
    [258] = "密码错误",
    [259] = "主动断开",
    [260] = "DHCP 超时（已连上但拿不到 IP）",
}

-- RSSI 转信号格（合宙建议：>-60 强，-60~-80 中，<-80 弱）
function net.level(rssi)
    if type(rssi) ~= "number" then return 0 end
    if rssi > -55 then return 4 end
    if rssi > -67 then return 3 end
    if rssi > -78 then return 2 end
    if rssi > -90 then return 1 end
    return 0
end

local function publish()
    sys.publish("NET_STATUS", net)
end

--- 全量扫描一次并打印结果，用于定位"扫不到 SSID"
-- @return number|nil 扫到的 AP 数量；nil 表示扫描失败
local function scan_once()
    if not (wlan and wlan.scan) then return nil end

    pcall(wlan.scan)
    if not sys.waitUntil("WLAN_SCAN_DONE", 10000) then
        log.warn("net_mgr", "扫描超时，未收到 WLAN_SCAN_DONE")
        return nil
    end

    local list = wlan.scanResult() or {}
    local target = cfg.wifi.ssid or ""
    local cnt, hit, hit_rssi = 0, false, nil

    for _, v in ipairs(list) do
        cnt = cnt + 1
        local ssid = v.ssid or ""
        if cnt <= 12 then
            log.info("net_mgr", string.format("AP[%d] %s  rssi=%s",
                cnt, #ssid > 0 and ssid or "<隐藏>", tostring(v.rssi)))
        end
        if #target > 0 and ssid == target then
            hit, hit_rssi = true, v.rssi
        end
    end

    log.info("net_mgr", "扫描到 AP 数量", cnt)

    if #target > 0 then
        if hit then
            log.info("net_mgr", "目标 SSID 在 2.4G 可见, rssi =", hit_rssi)
        elseif cnt == 0 then
            log.warn("net_mgr", "一个 AP 都扫不到：检查天线是否接好、模组射频是否正常")
        else
            log.warn("net_mgr", "未扫到目标 SSID：可能是 5GHz 热点 / 隐藏 SSID / 距离太远")
        end
    end

    return cnt
end

local function demo_worker()
    sys.waitUntil("UI_READY", 8000)    -- 等 UI 建好再广播，避免首帧丢失
    local seq = { -52, -58, -63, -55, -49, -60 }
    local i = 1
    while true do
        net.ready = true
        net.rssi  = seq[i]
        net.ip    = "192.168.1.86"
        net.ssid  = "SmartDoor-2.4G"
        i = i % #seq + 1
        publish()
        sys.wait(5000)
    end
end

local function real_worker()
    sys.waitUntil("UI_READY", 8000)    -- 等 UI 建好再广播，避免首帧丢失
    if not wlan then
        log.warn("net_mgr", "wlan 库不可用")
        while true do
            publish()
            sys.wait(10000)
        end
    end

    wlan.init()
    pcall(wlan.setMode, wlan.STATION)
    sys.wait(300)

    local target = cfg.wifi.ssid or ""

    -- 开机先扫一次：日志里能直接看到周围所有 2.4G AP
    scan_once()

    if #target > 0 then
        -- connect 返回 true 只代表"发起成功"，结果看 wlan.ready()
        wlan.connect(target, cfg.wifi.password or "", 1)
        net.ssid = target
        log.info("net_mgr", "connecting", target)
    else
        log.warn("net_mgr", "未配置 WiFi，请在 hw_config.lua 填写 ssid")
    end

    local synced = false
    local fails, scans = 0, 0

    while true do
        local ready = false
        pcall(function() ready = wlan.ready() end)
        net.ready = ready and true or false

        if net.ready then
            fails = 0
            local info
            pcall(function() info = wlan.getInfo() end)
            if type(info) == "table" then
                net.rssi = info.rssi
            end
            local ip
            pcall(function() ip = wlan.getIP() end)
            net.ip = ip

            -- 首次联网后校时一次（固件无 sntp 能力时自动跳过）
            if not synced then
                synced = true
                if socket and socket.sntp then
                    pcall(socket.sntp)
                    log.info("net_mgr", "sntp start")
                end
            end
        else
            net.rssi = nil
            net.ip   = nil

            -- 长时间连不上：每 60s 复扫一次（最多 3 次），避免日志刷屏
            fails = fails + 1
            if scans < 3 and fails % 12 == 0 then
                scans = scans + 1
                scan_once()
            end
        end

        publish()
        sys.wait(5000)
    end
end

sys.subscribe("WLAN_STA_INC", function(evt, data)
    if evt == "CONNECTED" then
        net.ssid = data
        log.info("net_mgr", "wifi connected", data)
    else
        log.warn("net_mgr", "wifi disconnected", data, REASON[data] or "")
    end
end)

if cfg.demo_mode then
    sys.taskInit(demo_worker)
else
    sys.taskInit(real_worker)
end

return net
