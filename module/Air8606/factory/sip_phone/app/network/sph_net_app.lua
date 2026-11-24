-- SIP 使用工厂网络管理器选出的默认出口。UI 读缓存，不重新配置 SPI2 或 J24。
local M = {}
local features = (_G.project_config or {}).features or {}
local state = {
    ready=false, link=false, ip="", modem=features.net_4g==true,
    wifi=features.wifi==true, scanning=false, ssid="",
}
local levels = {wifi=0, ["4g"]=0}
local active_adapter
local initialized = false

function M.status()
    local result = {}
    for key, value in pairs(state) do result[key] = value end
    return result
end

function M.is_up() return state.ready end
function M.has_wifi() return state.wifi end
function M.has_modem() return state.modem end
function M.signal()
    local kind = "eth"
    if active_adapter ~= nil and active_adapter == socket.LWIP_STA then kind = "wifi"
    elseif active_adapter ~= nil and active_adapter == socket.LWIP_GP_GW then kind = "4g" end
    return {kind=kind, level=levels[kind] or 0}
end

sys.subscribe("STATUS_SIGNAL_UPDATED", function(level) levels["4g"] = tonumber(level) or 0 end)
sys.subscribe("STATUS_WIFI_SIGNAL_UPDATED", function(level) levels.wifi = tonumber(level) or 0 end)

local function set_route(adapter, ip)
    local ready = type(adapter) == "number" and adapter >= 0
    if ready and not ip then
        local ok, addr = pcall(socket.localIP, adapter)
        if ok then ip = addr end
    end
    ip = ip or ""
    if not ready then adapter = nil end
    if active_adapter == adapter and state.ready == ready and state.ip == ip then return end
    active_adapter = adapter
    state.ready, state.link, state.ip = ready, ready, ip
    sys.publish("NET_STATE", M.status())
    if ready then sys.publish("NET_READY", ip) end
end

local function refresh_route()
    local adapter = socket.dft()
    if type(adapter) == "number" and adapter >= 0 and socket.adapter(adapter) then
        set_route(adapter)
    else
        set_route(nil)
    end
end

sys.subscribe("EXLIB_NETDRV_NETWORK_STATUS", function(kind, adapter)
    if initialized then set_route(kind and adapter or nil) end
end)
sys.subscribe("IP_READY", function(ip, adapter)
    if initialized and adapter == socket.dft() then set_route(adapter, ip) end
end)
sys.subscribe("IP_LOSE", function(adapter)
    if not initialized or adapter ~= active_adapter then return end
    if adapter == socket.dft() then set_route(nil) else refresh_route() end
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

function M.init()
    if not initialized then
        initialized = true
        refresh_route()
    end
    return true
end

return M
