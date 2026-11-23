-- Air8606 host-side EX2 diagnostics. The SPI2 assembly determines the peer.
local tick_time = require "tick_time"
local M = {}
local PROTOCOL, MAX_PACKET = "air8606", 1000
local REQUEST_TIMEOUT, LINK_TIMEOUT, NMEA_TIMEOUT = 5000, 15000, 5000
-- J15 can spend 12 s waiting for PHY/DHCP followed by 10 s on HTTP.
M.ETH_DIAG_TIMEOUT = 25000
local COMMANDS = { status = true, gnss_start = true, gnss_stop = true, eth_diag = true }
local initialized, enabled = false, false
local next_id = 0
local pending = {}
local last_peer_tick, last_nmea_tick, last_gnss_notice_tick
local state = { online = false, eth = { link = false, ready = false, ip = "" },
    mobile = {}, gnss = { enabled = false, fix = false, rmc = {}, gga = {}, last_rx = 0 } }

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end

local function elapsed(since)
    return tick_time.to_ms(tick_time.elapsed(tick_time.now(), since))
end

local function publish()
    sys.publish("AIR8606_PEER_STATUS", copy(state))
end

local function publish_gnss()
    last_gnss_notice_tick = tick_time.now()
    sys.publish("AIR8606_GNSS", copy(state.gnss))
end

local function clear_location()
    state.gnss.fix, state.gnss.rmc, state.gnss.gga = false, {}, {}
    state.gnss.last_rx = 0
    last_nmea_tick = nil
    if libgnss and libgnss.clear then libgnss.clear() end
end

local function update_status(data)
    if type(data) ~= "table" then return end
    if type(data.eth) == "table" then state.eth = copy(data.eth) end
    if type(data.mobile) == "table" then state.mobile = copy(data.mobile) end
    if type(data.gnss) == "table" then
        local remote_enabled = data.gnss.enabled == true
        if state.gnss.enabled ~= remote_enabled then
            clear_location()
            state.gnss.enabled = remote_enabled
        end
        state.gnss.rx_bytes = data.gnss.rx_bytes
        state.gnss.lines = data.gnss.lines
        state.gnss.dropped = data.gnss.dropped
        publish_gnss()
    end
end

local function finish(id, ok, data, err)
    local request = pending[id]
    if not request then return end
    pending[id] = nil
    if request.timer then sys.timerStop(request.timer) end
    if request.cb then
        local called, reason = pcall(request.cb, ok, data, err)
        if not called then log.warn("air8606_peer", "callback", reason) end
    end
end

local function receive_nmea(line)
    -- The native libgnss streaming buffer is 120 bytes, including its terminator.
    if not state.gnss.enabled or type(line) ~= "string" or #line == 0 or #line > 118
        or line:sub(1, 1) ~= "$" or line:find("[%z\r\n]") then return end
    if not libgnss or type(libgnss.parse) ~= "function" then return end
    libgnss.parse(line .. "\r\n")
    last_nmea_tick = tick_time.now()
    state.gnss.last_rx = tick_time.to_ms(last_nmea_tick)
    local old_fix = state.gnss.fix
    state.gnss.fix = libgnss.isFix() == true
    state.gnss.rmc = libgnss.getRmc(2) or {}
    state.gnss.gga = libgnss.getGga(2) or {}
    if old_fix ~= state.gnss.fix or not last_gnss_notice_tick
        or elapsed(last_gnss_notice_tick) >= 1000 then publish_gnss() end
end

local function receive(data)
    if type(data) ~= "string" or #data > MAX_PACKET then return end
    local decoded, message = pcall(json.decode, data)
    if not decoded or type(message) ~= "table" or message.protocol ~= PROTOCOL
        or message.version ~= 1 then return end
    if message.kind == "response" then
        local request = pending[message.id]
        if not request or message.cmd ~= request.cmd then return end
        last_peer_tick, state.online = tick_time.now(), true
        update_status(message.data)
        finish(message.id, message.ok == true, copy(message.data), message.error)
        publish()
    elseif message.kind == "event" then
        if message.event ~= "status" and message.event ~= "nmea" then return end
        last_peer_tick, state.online = tick_time.now(), true
        if message.event == "status" then
            update_status(message.data)
            publish()
        else
            receive_nmea(message.line)
        end
    end
end

-- Returns true, request_id after enqueueing, or false, reason without a callback.
-- An accepted request invokes cb(ok, data, error) exactly once.
function M.request(cmd, args, cb)
    if not enabled then return false, "peer_not_enabled" end
    if not COMMANDS[cmd] then return false, "unknown_command" end
    if args ~= nil and type(args) ~= "table" then return false, "invalid_arguments" end
    if cb ~= nil and type(cb) ~= "function" then return false, "invalid_callback" end
    if not airlink.ready() then return false, "airlink_not_ready" end
    next_id = next_id % 0x7FFFFFFF + 1
    local id = next_id
    local encoded = json.encode({ protocol = PROTOCOL, version = 1, kind = "request",
        id = id, cmd = cmd, args = args or {} })
    if type(encoded) ~= "string" or #encoded > MAX_PACKET then return false, "packet_too_large" end
    local request = { cmd = cmd, cb = cb }
    pending[id] = request
    local called, result = pcall(airlink.sdata, encoded)
    if not called or result == false then
        pending[id] = nil
        return false, "airlink_send_failed"
    end
    request.timer = sys.timerStart(function()
        finish(id, false, nil, "timeout")
    end, cmd == "eth_diag" and M.ETH_DIAG_TIMEOUT or REQUEST_TIMEOUT)
    return true, id
end

function M.status()
    local snapshot = copy(state)
    snapshot.airlink_ready = enabled and airlink.ready() == true
    snapshot.online = snapshot.airlink_ready and state.online
    return snapshot
end

function M.offline_hint(snapshot)
    return snapshot.airlink_ready and "SPI2 已就绪，等待 Air8606 EX2 厂测脚本应答"
        or "SPI2 未就绪，检查 EX2 从机固件及 R176～R180"
end

local errors = {
    gnss_uart_setup_failed = "EX2 无法打开 Air510W UART1",
    ethernet_spi_setup_failed = "J15 的 SPI0 初始化失败",
    ethernet_driver_setup_failed = "J15 的 CH390H 驱动初始化失败",
    ethernet_dhcp_setup_failed = "J15 的 DHCP 客户端启动失败",
    ethernet_link_down = "J15 无物理链路，请检查网线和交换机",
    ethernet_dhcp_timeout = "J15 有链路，等待 DHCP 地址超时",
    http_body_length = "J15 收到 HTTP 200，应答长度不等于 2048 字节",
}

function M.error_text(reason)
    if reason == "airlink_not_ready" or reason == "timeout" then
        local snapshot = M.status()
        if not snapshot.online then return M.offline_hint(snapshot) end
        return "等待 EX2 命令应答超时"
    end
    if type(reason) == "string" then
        local code = reason:match("^http_status_(.+)$")
        if code then return "J15 HTTP 返回 " .. code end
    end
    return errors[reason] or reason
end

function M.gnss(enable, cb)
    return M.request(enable and "gnss_start" or "gnss_stop", nil, cb)
end

function M.eth_diag(cb)
    return M.request("eth_diag", nil, cb)
end

function M.init(cfg)
    if initialized then return enabled end
    if not cfg or cfg.radio ~= "4g" then return false, "peer_not_enabled" end
    if not airlink or type(airlink.sdata) ~= "function" then return false, "airlink_unavailable" end
    initialized, enabled = true, true
    sys.subscribe("AIRLINK_SDATA", receive)
    sys.taskInit(function()
        while true do
            local status_pending = false
            for _, request in pairs(pending) do
                if request.cmd == "status" then status_pending = true end
            end
            if not status_pending then M.request("status") end
            sys.wait(5000)
        end
    end)
    sys.taskInit(function()
        while true do
            sys.wait(1000)
            local changed = false
            if state.online and last_peer_tick and elapsed(last_peer_tick) >= LINK_TIMEOUT then
                state.online, changed = false, true
                clear_location()
                publish_gnss()
            elseif last_nmea_tick and elapsed(last_nmea_tick) >= NMEA_TIMEOUT then
                clear_location()
                publish_gnss()
                changed = true
            end
            if changed then publish() end
        end
    end)
    return true
end

return M
