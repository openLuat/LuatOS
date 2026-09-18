--[[
@module  cc_main
@summary VoLTE 纯 PCM 通话与生命周期保护
@version 1.1
@date    2026.09.18
@usage
封装 CC 初始化、呼叫身份、媒体状态和逐通真实 PCM 统计。
通过发布/订阅消息与 bridge.lua 和 sip_main.lua 交互。
]]

local cc_main = {}
local config = require "config"

local STATE_IDLE = "cc_idle"
local STATE_DIALING = "cc_dialing"
local STATE_RINGING = "cc_ringing"
local STATE_CONNECTED = "cc_connected"
local STATE_DISCONNECTING = "cc_disconnecting"

local g_state = STATE_IDLE
local g_ready = false
local g_initialized = false
local g_call_connected = false
local g_media_ready = false
local g_audio_start_timer
local g_call_generation = 0
local g_owner_token
local g_session
local g_monitor
local g_monitor_timer
local g_monitor_min
local g_monitor_limit
local g_missing_calls = 0
local g_anomaly_reported = false

local REQUIRED_STATS = {
    "session", "active", "media_ready", "fault", "dl_pushed", "dl_queued", "ul_queued",
    "sdk_active", "sdk_pending", "sdk_stop_waiting", "sdk_fault", "sdk_stop_timeout",
}

local function logi(...)
    log.info("cc_main", ...)
end

local function integer(value)
    return type(value) == "number" and value >= 0 and value < math.huge and value == math.floor(value)
end

local function read_stats()
    if not cc or type(cc.bridgePcmStats) ~= "function" then return nil end
    local ok, stats = pcall(cc.bridgePcmStats)
    if ok and type(stats) == "table" then return stats end
end

local function valid_stats(stats)
    if type(stats) ~= "table" or type(stats.selected) ~= "boolean" then return false, "selected" end
    for _, name in ipairs(REQUIRED_STATS) do
        if not integer(stats[name]) then return false, name end
    end
    return true
end

local function now_ms()
    if not mcu or type(mcu.ticks2) ~= "function" then return nil end
    local high, low = mcu.ticks2(1)
    if not integer(high) or not integer(low) then return nil end
    -- ticks2 的高位单位是 1000000 ms，不是 2^32 ms。
    return high * 1000000.0 + low
end

local function matches_request(generation, owner_token)
    return (generation == nil or generation == g_call_generation) and
        (owner_token == nil or owner_token == g_owner_token)
end

local function set_state(new_state)
    if g_state ~= new_state then
        local old_state = g_state
        logi("状态切换", old_state, "->", new_state)
        g_state = new_state
        sys.publish("CC_STATE_CHANGED", new_state, old_state,
            g_call_generation, g_owner_token, g_session)
    end
end

local function stop_audio_start_timeout()
    if g_audio_start_timer then
        sys.timerStop(g_audio_start_timer)
        g_audio_start_timer = nil
    end
end

local function stop_monitor_timer()
    if g_monitor_timer then
        sys.timerStop(g_monitor_timer)
        g_monitor_timer = nil
    end
end

local function clear_missing_calls()
    g_missing_calls = 0
    g_anomaly_reported = false
end

local function monitor_settings()
    local minimum = tonumber(config.cc_media_min_connected_ms) or 2000
    local limit = tonumber(config.cc_media_missing_call_limit) or 3
    minimum = math.floor(minimum)
    limit = math.floor(limit)
    if minimum ~= g_monitor_min or limit ~= g_monitor_limit then
        g_monitor_min, g_monitor_limit = minimum, limit
        clear_missing_calls()
        if g_monitor then g_monitor.unknown = true end
    end
    return minimum > 0 and limit > 0
end

local function sample_pcm(stats)
    local call = g_monitor
    if not call or call.finished then return end
    if not monitor_settings() then
        call.disabled = true
        call.unknown = true
        clear_missing_calls()
        stop_monitor_timer()
        return
    end
    stats = stats or read_stats()
    if not stats or stats.selected ~= true or not integer(call.session) or call.session == 0 or
        stats.session ~= call.session or not integer(stats.dl_pushed) then
        call.unknown = true
        clear_missing_calls()
        stop_monitor_timer()
        return
    end
    -- 该计数只来自有效 HAL 下行 PCM；上传静音、FIFO 长度、RTP 和 AUDIO_START 均不能替代。
    if stats.dl_pushed > 0 then
        call.raw_seen = true
        clear_missing_calls()
        stop_monitor_timer()
    end
end

local function schedule_pcm_sample()
    local call = g_monitor
    if not call or call.finished or call.raw_seen or call.unknown or g_monitor_timer then return end
    local generation = g_call_generation
    g_monitor_timer = sys.timerStart(function()
        if generation ~= g_call_generation or call ~= g_monitor then return end
        g_monitor_timer = nil
        sample_pcm()
        schedule_pcm_sample()
    end, 100)
end

local function bind_session()
    local stats = read_stats()
    if stats and stats.selected == true and integer(stats.session) and stats.session > 0 then
        g_session = stats.session
    end
    monitor_settings()
    g_monitor = {session = g_session, generation = g_call_generation}
    sample_pcm(stats)
    schedule_pcm_sample()
end

local function begin_call(owner_token)
    stop_audio_start_timeout()
    stop_monitor_timer()
    g_call_generation = g_call_generation + 1
    g_owner_token = owner_token
    g_session = nil
    g_monitor = nil
    g_call_connected = false
    g_media_ready = false
end

local function note_real_connected()
    local call = g_monitor
    if not call or call.connected_at or call.finished then return end
    call.connected_at = now_ms()
    if not call.connected_at then
        call.unknown = true
        clear_missing_calls()
    end
    sample_pcm()
end

local function note_hangup_requested()
    local call = g_monitor
    if not call or call.hangup_requested then return end
    call.hangup_requested = true
    call.hangup_at = now_ms()
    if not call.hangup_at then
        call.unknown = true
        clear_missing_calls()
    end
    sample_pcm()
end

local function finish_monitor()
    local call = g_monitor
    if not call or call.finished then return end
    sample_pcm()
    stop_monitor_timer()
    call.finished = true
    if call.raw_seen or call.disabled then return end
    if call.unknown then
        clear_missing_calls()
        log.warn("cc_main", "PCM 统计未知，不计入连续异常", call.generation, call.session)
        return
    end
    if not call.connected_at then return end
    local ended_at = call.hangup_requested and call.hangup_at or now_ms()
    if not ended_at or ended_at < call.connected_at then
        clear_missing_calls()
        return
    end
    local duration = ended_at - call.connected_at
    if duration < g_monitor_min then return end
    g_missing_calls = g_missing_calls + 1
    log.warn("cc_main", "已接通通话无真实 PCM", duration, "连续", g_missing_calls)
    if g_missing_calls >= g_monitor_limit and not g_anomaly_reported then
        g_anomaly_reported = true
        return {
            source = "bridgePcmStats.dl_pushed",
            generation = call.generation, owner_token = g_owner_token, session = call.session,
            connected_ms = duration, missing_calls = g_missing_calls,
            min_connected_ms = g_monitor_min, missing_call_limit = g_monitor_limit,
        }
    end
end

local function stop_bridge_audio()
    -- stats 已进入下一 session 时，不停止不属于本通的 native 媒体。
    local stats = read_stats()
    if g_session and stats and stats.session == g_session and cc and cc.bridgeAudioStop then
        cc.bridgeAudioStop()
    end
end

local function request_hangup()
    note_hangup_requested()
    stop_audio_start_timeout()
    g_media_ready = false
    stop_bridge_audio()
    set_state(STATE_DISCONNECTING)
    local stats = read_stats()
    local another_session = g_session and stats and integer(stats.session) and stats.session ~= g_session
    if not another_session and cc and cc.hangUp then cc.hangUp(0) end
end

local function publish_failure(reason, terminal)
    sys.publish("CC_FAILED", reason, g_call_generation, g_owner_token, g_session, terminal)
end

local function start_audio_start_timeout()
    if g_audio_start_timer then return end
    local timeout = tonumber(config.cc_audio_start_timeout_ms) or 0
    if timeout <= 0 then return end
    local generation = g_call_generation
    g_audio_start_timer = sys.timerStart(function()
        if generation ~= g_call_generation then return end
        g_audio_start_timer = nil
        if g_state ~= STATE_DIALING and g_state ~= STATE_RINGING and g_state ~= STATE_CONNECTED then return end
        if not g_call_connected or g_media_ready then return end
        log.error("cc_main", "CC 音频通道启动超时", timeout)
        request_hangup()
        publish_failure("audio_start_timeout", false)
    end, timeout)
end

local function finish_media_start()
    if not g_call_connected or not g_media_ready or
        (g_state ~= STATE_DIALING and g_state ~= STATE_RINGING) then return end
    stop_audio_start_timeout()
    set_state(STATE_CONNECTED)
    logi("CC 已接通且 PCM 通道就绪")
    sys.publish("CC_CONNECTED", g_call_generation, g_owner_token, g_session)
end

local function on_media_error(reason, session)
    if g_state == STATE_IDLE or g_state == STATE_DISCONNECTING then return end
    if session ~= nil and session ~= g_session then return end
    local stats = read_stats()
    if session ~= nil and stats and stats.session ~= session then return end
    log.error("cc_main", "PCM 媒体故障", reason, "session", session)
    request_hangup()
    publish_failure(reason or "pcm_media_error", false)
end

local function finish_call(reason, failed)
    if g_state == STATE_IDLE then return end
    local anomaly = finish_monitor()
    stop_audio_start_timeout()
    stop_bridge_audio()
    g_call_connected = false
    g_media_ready = false
    set_state(STATE_IDLE)
    if failed then
        publish_failure(reason, true)
    else
        sys.publish("CC_DISCONNECTED", reason, g_call_generation, g_owner_token, g_session)
    end
    if anomaly then sys.publish("CC_BRIDGE_MEDIA_ANOMALY", "NO_MODEM_PCM", anomaly) end
end

-- ==================== 请求处理 ====================

local function on_cc_dial_req(number, owner_token)
    if g_state ~= STATE_IDLE then
        sys.publish("CC_DIAL_REJECTED", "busy", owner_token)
        return
    end
    if not g_initialized then
        sys.publish("CC_DIAL_REJECTED", "cc_not_ready", owner_token)
        return
    end
    begin_call(owner_token)
    set_state(STATE_DIALING)
    logi("执行拨号", number)
    if not cc or not cc.dial then
        finish_call("cc_not_ready", true)
        return
    end
    local ok = cc.dial(0, number)
    if not ok then
        log.error("cc_main", "cc.dial 失败")
        finish_call("dial_failed", true)
        return
    end
    bind_session()
    if cc.bridgeTone then
        -- 仅请求网络侧彩铃；真实蜂窝下行和接通由 C 后端仲裁。
        cc.bridgeTone(true)
    end
end

local function on_cc_accept_req(generation, owner_token)
    if not matches_request(generation, owner_token) or g_state ~= STATE_RINGING then return end
    logi("执行接听")
    if not cc or not cc.accept then
        on_media_error("accept_unavailable")
        return
    end
    if not cc.accept(0) then on_media_error("accept_failed") end
end

local function on_cc_hangup_req(generation, owner_token)
    if not matches_request(generation, owner_token) or
        g_state == STATE_IDLE or g_state == STATE_DISCONNECTING then return end
    logi("执行挂断")
    request_hangup()
end

sys.subscribe("CC_DIAL_REQ", on_cc_dial_req)
sys.subscribe("CC_ACCEPT_REQ", on_cc_accept_req)
sys.subscribe("CC_HANGUP_REQ", on_cc_hangup_req)

-- ==================== CC 事件处理 ====================

local function on_cc_event(status, value, extra)
    logi("事件", status, value, extra)
    if status == "READY" then
        g_ready = true
    elseif status == "INCOMINGCALL" then
        local number = cc and cc.lastNum and cc.lastNum() or ""
        if g_state == STATE_RINGING then return end
        if g_state ~= STATE_IDLE then
            if g_state ~= STATE_DISCONNECTING then request_hangup() end
            return
        end
        if not g_initialized then
            if cc and cc.hangUp then cc.hangUp(0) end
            return
        end
        begin_call(nil)
        bind_session()
        set_state(STATE_RINGING)
        sys.publish("CC_INCOMING", number, g_call_generation, g_session)
    elseif status == "CONNECTED" or status == "CONNECTED_NUMBER" or status == "ANSWER_CALL_DONE" then
        if g_state ~= STATE_DIALING and g_state ~= STATE_RINGING and g_state ~= STATE_CONNECTED then return end
        -- 保留业务接通兼容性；缺 PCM 监测仅认真正接通通知。
        if status ~= "ANSWER_CALL_DONE" then note_real_connected() end
        if not g_call_connected then
            g_call_connected = true
            if cc.bridgeTone then cc.bridgeTone(false) end
            if not g_media_ready then start_audio_start_timeout() end
        end
        finish_media_start()
    elseif status == "AUDIO_START" then
        if g_state == STATE_IDLE or g_state == STATE_DISCONNECTING or
            value == nil or value ~= g_session then return end
        local stats = read_stats()
        if not stats or stats.session ~= value or stats.active ~= 1 or stats.media_ready ~= 1 then return end
        sample_pcm(stats)
        g_media_ready = true
        stop_audio_start_timeout()
        finish_media_start()
    elseif (status == "PLAY" and value == 0) or status == "PLAY_STOP" then
        if g_state == STATE_IDLE or g_state == STATE_DISCONNECTING then return end
        -- 媒体阶段结束不代表整通结束，也不清除本通的真实 PCM 证据。
        sample_pcm()
        g_media_ready = false
        if g_call_connected then start_audio_start_timeout() end
    elseif status == "DISCONNECTED" then
        finish_call("remote_hangup", false)
    elseif status == "MAKE_CALL_FAILED" then
        finish_call("make_call_failed", true)
    elseif status == "HANGUP_CALL_DONE" then
        finish_call("local_hangup", false)
    elseif status == "SPEECH_START" then
        -- C 后端负责 PCM；不从此通知推断接通或启用旧音频通路。
    elseif status == "MAKE_CALL_OK" then
        logi("CC 拨号请求已发送")
    end
end

-- ==================== 公共 API ====================

sys.subscribe("CC_IND", on_cc_event)
sys.subscribe("CC_BRIDGE_MEDIA_ERROR", on_media_error)

function cc_main.init()
    if g_initialized then return true end
    if not cc or not cc.init then return false, "cc_unavailable" end
    if cc.AUDIO_MODE_BRIDGE_PCM == nil then return false, "firmware_missing_bridge_pcm" end
    if now_ms() == nil then return false, "firmware_missing_monotonic_clock" end
    local valid, field = valid_stats(read_stats())
    if not valid then return false, "firmware_missing_pcm_stats:" .. field end
    if type(cc.bridgeAudioStop) ~= "function" then return false, "firmware_missing_bridge_audio_stop" end
    local ok, reason = cc.init(0, cc.AUDIO_MODE_BRIDGE_PCM)
    if not ok then
        g_ready = false
        log.error("cc_main", "CC 初始化失败", reason)
        return false, reason or "cc_init_failed"
    end
    local stats = read_stats()
    valid, field = valid_stats(stats)
    if not valid or stats.selected ~= true then
        g_ready = false
        return false, "firmware_invalid_pcm_stats:" .. (field or "selected")
    end
    monitor_settings()
    g_initialized = true
    g_ready = true
    logi("CC 初始化完成 bridge_pcm")
    return true
end

function cc_main.dial(number, owner_token)
    sys.publish("CC_DIAL_REQ", number, owner_token)
end

function cc_main.accept()
    sys.publish("CC_ACCEPT_REQ", g_call_generation, g_owner_token)
end

function cc_main.hangup()
    sys.publish("CC_HANGUP_REQ", g_call_generation, g_owner_token)
end

function cc_main.claim_owner(generation, owner_token)
    if generation ~= g_call_generation or g_state == STATE_IDLE or owner_token == nil or
        (g_owner_token ~= nil and g_owner_token ~= owner_token) then return false end
    g_owner_token = owner_token
    return true
end

function cc_main.get_state() return g_state end
function cc_main.get_generation() return g_call_generation end
function cc_main.get_session() return g_session end
function cc_main.get_stats() return read_stats() end
function cc_main.is_ready() return g_ready end

function cc_main.is_media_idle()
    local stats = read_stats()
    if not valid_stats(stats) or stats.selected ~= true then return false end
    return stats.active == 0 and stats.media_ready == 0 and
        stats.dl_queued == 0 and stats.ul_queued == 0 and stats.sdk_active == 0 and
        stats.sdk_pending == 0 and stats.sdk_stop_waiting == 0
end

return cc_main
