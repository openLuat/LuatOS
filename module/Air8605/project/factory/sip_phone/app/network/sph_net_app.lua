-- UART3 Airlink 4G. Read cached state in UI; never perform RPC from a UI timer.
local M = {}
local state = {ready=false,link=false,ip="",modem=true,wifi=false,scanning=false,ssid=""}
local signal = {kind="4g",level=0}
local initialized, channel = false, false
local adapter
-- 工厂里 4G 是 airlink 桥接，mobile.* / socket.adapter 全是 UART3 上的同步 RPC。
-- 本模块【不再起自己的轮询】：
--   1) 原实现每 5 秒做两次同步 RPC（detect_default_adapter + mobile.csq）；
--   2) 工厂 status_provider_app 本来就有 2 秒一次的 mobile.csq；
--   3) 两条叠加把 airlink RPC 通道打满 → "rpc yield timeout after 712ms" + 总线错误死机，
--      平时则表现为 Air1103 下行(10ms 一拍)被抢调度导致的"卡"。
-- 而这条轮询维护的东西：signal 在 UI 里根本没人用，state.ready 已由 IP_READY/IP_LOSE 维护。
-- 所以这里只保留事件驱动，信号等级直接订阅工厂的状态发布。
local signal_level = 0
sys.subscribe("STATUS_SIGNAL_UPDATED", function(level) signal_level = tonumber(level) or 0 end)
local function publish()
    sys.publish("NET_STATE",M.status())
    if state.ready then sys.publish("NET_READY",state.ip) end
end
function M.status()
    local copy={}; for k,v in pairs(state) do copy[k]=v end; return copy
end
function M.signal()
    local copy={}; for k,v in pairs(signal) do copy[k]=v end
    copy.level=signal_level   -- 由工厂 status_provider_app 的 csq 结果驱动
    return copy
end
function M.is_up() return state.ready end
function M.has_wifi() return false end
function M.has_modem() return not is_pc end
local function set_ready(up, ad)
    if state.ready~=up then log.info("net_app","network ready",up,"adapter",ad) end
    state.ready,state.link=up,up
    state.ip=""
    if up then
        local ok,ip=pcall(socket.localIP,ad)
        if ok then state.ip=ip or "" end
    end
    publish()
end
sys.subscribe("EXLIB_NETDRV_NETWORK_STATUS",function(kind,ad)
    if is_pc or not initialized then return end
    -- 工厂默认网卡可能在切换：任一网卡变为 4G 在线即认为可用
    set_ready(kind=="airlink_4G",ad)
end)
sys.subscribe("IP_LOSE",function(ad)
    -- 只有掉线的正是当前默认网卡时才置为离线
    if ad==adapter then set_ready(false,ad) end
end)
sys.subscribe("IP_READY",function(ip,ad)
    if initialized then
        adapter = ad or adapter
        set_ready(true,ad)
    end
end)
local syncing=false
sys.subscribe("NET_READY",function()
    if syncing or os.time()>1735689600 then return end
    syncing=true
    sys.taskInit(function()
        local ok=pcall(socket.sntp)
        local synced=ok and sys.waitUntil("NTP_UPDATE",15000)
        log.info("net_app",synced and "NTP synchronized" or "NTP pending")
        syncing=false
    end)
end)
-- 【工厂集成】网络已由 net_manager 接管（开机时已 apply 一次优先级）。
-- 这里绝不能再调 exnetif.set_priority_order，否则两套组网逻辑会互相打架。
-- 只做两件事：1) 检测当前默认网卡是否已联网；2) 周期刷新信号（通话中自动跳过）。
-- IP_READY / IP_LOSE 订阅保留，但不再按"同事方案写死的 adapter"过滤，
-- 工厂默认网卡是谁就跟谁。
local function detect_default_adapter()
    local candidates = {}
    if socket.LWIP_GP_GW then candidates[#candidates+1] = socket.LWIP_GP_GW end
    if socket.ETH0 then candidates[#candidates+1] = socket.ETH0 end
    -- socket.adapter(nil) 在部分固件上返回当前默认 adapter
    local dft = nil
    pcall(function() dft = socket.adapter() end)
    if type(dft) == "number" then table.insert(candidates, 1, dft) end
    for _, ad in ipairs(candidates) do
        local up = false
        pcall(function() up = socket.adapter(ad) == true end)
        if up then return ad, true end
    end
    -- 没探测到在线网卡：仍返回第一个候选，等待 IP_READY 事件置位
    return candidates[1], false
end

function M.init()
    if initialized then return true end
    initialized=true
    if is_pc then
        state.modem=false; signal.kind="eth"
        adapter=socket.ETH0
        socket.dft(adapter)
        set_ready(socket.adapter(adapter)==true,adapter)
        return true
    end
    adapter = detect_default_adapter()
    set_ready(adapter ~= nil and socket.adapter(adapter)==true, adapter)
    -- 只做这一次探测；之后完全靠 IP_READY / IP_LOSE /
    -- EXLIB_NETDRV_NETWORK_STATUS 事件驱动，不再周期性发起 airlink 同步 RPC。
    return true
end
return M
