-- 仅用于本 demo：SIP 信令 + VoIP PCM 桥接，无本地音频后端。
local pcm_sip = {}
local sipclient
local g_config
local g_started = false
local g_registered = false
local g_callbacks = {}
local g_call
local g_call_generation = 0
local g_media
local g_media_pending
local g_current_adapter
local g_ready_adapters = {}
local g_ip_event_subscribed = false
local default_config = {
    sip_transport = "tcp", sip_server_port = 5060, rtp_port = 40000,
    expires = 600, codecs = {"PCMU", "PCMA"}, ptime = 20,
    call_timeout = 30, debug_sip_response = false,
}
local function log_info(...) log.info("pcm_sip", ...) end
local function log_warn(...) log.warn("pcm_sip", ...) end
local function log_error(...) log.error("pcm_sip", ...) end

local function emit_callback(event, ...)
    local cb = g_callbacks[event]
    if type(cb) == "function" then
        local ok, err = pcall(cb, ...)
        if not ok then
            log_error("callback error:", event, err)
        end
    end
end

-- 前台业务结束后，仍保留正在停止原生媒体的通话记录。
local function new_call(call_id, direction, owner_token, target)
    g_call_generation = g_call_generation + 1
    return {call_id = call_id, sip_generation = g_call_generation,
        owner_token = owner_token, direction = direction, target = target}
end

local function matches(call, call_id, generation, owner_token)
    return call and (call_id == nil or call_id == call.call_id) and
        (generation == nil or generation == call.sip_generation) and
        (owner_token == nil or owner_token == call.owner_token)
end

local function with_identity(payload, call)
    local out = {}
    for key, value in pairs(payload or {}) do out[key] = value end
    if call then
        out.call_id = call.call_id
        out.sip_generation = call.sip_generation
        out.owner_token = call.owner_token
    end
    return out
end

local function payload_call_id(payload)
    return payload and (payload.call_id or (payload.dialog and payload.dialog.call_id) or
        (payload.session and payload.session.call_id))
end

local function event_call(payload)
    local call = g_call
    if not call or not matches(call, nil, payload.sip_generation, payload.owner_token) then return end
    local call_id = payload_call_id(payload)
    if call_id and call.call_id and call_id ~= call.call_id then return end
    if call_id and not call.call_id then
        if call.direction ~= "out" then return end
        call.call_id = call_id
        emit_callback("call", "bound", with_identity({}, call))
    end
    return call
end

local function native_state()
    return voip and voip.getState and voip.getState() or "idle"
end

local function media_state(state, call)
    emit_callback("media", "state", with_identity({state = state}, call))
end

local function has_voip_pcm_bridge()
    return voip and type(voip.setAudioMode) == "function" and
        voip.AUDIO_MODE_BRIDGE ~= nil and type(voip.pcmIn) == "function" and
        type(voip.pcmOut) == "function"
end

local function set_bridge_mode()
    if not has_voip_pcm_bridge() then
        log_error("firmware_missing_voip_bridge")
        return false
    end
    local ok, result = pcall(voip.setAudioMode, voip.AUDIO_MODE_BRIDGE)
    if not ok or not result then log_error("set bridge mode failed", result); return false end
    return true
end

local function start_voip_engine(session)
    local codec_map = {PCMU = voip.PCMU, PCMA = voip.PCMA}
    local codec = codec_map[session.codec]
    if codec == nil or (tonumber(session.ptime) or 20) ~= 20 or
        (tonumber(session.sample_rate) or 8000) ~= 8000 then
        log_error("bridge requires PCMA/PCMU, 8000 Hz, 20 ms")
        return false
    end
    g_current_adapter = session.adapter or g_current_adapter
    local ok = voip.start({
        remote_ip = session.remote_ip,
        remote_port = tonumber(session.remote_port) or 10000,
        local_port = tonumber(session.local_rtp_port) or 0,
        codec = codec, ptime = 20, sample_rate = 8000,
        jitter_depth = 3, multimedia_id = 0,
        adapter = g_current_adapter, aec = false,
    })
    if ok then
        log_info("PCM media start queued", session.remote_ip, session.remote_port, session.codec)
        return true
    end
    log_error("voip engine start failed")
    return false
end

local start_pending_media

local function request_media_stop()
    if g_media and g_media.state == "stopping" then return end
    if not g_media and native_state() == "idle" then return end
    g_media = g_media or {call = g_call}
    g_media.state = "stopping"
    media_state("stopping", g_media.call)
    -- 原生层已受理启动请求时，即使尚未进入运行状态，也必须请求停止。
    voip.stop()
end

local function stop_voip_engine(call)
    if g_media_pending and (not call or g_media_pending.call == call) then
        local pending_call = g_media_pending.call
        g_media_pending = nil
        media_state("cancelled", pending_call)
    end
    if not call or (g_media and g_media.call == call) then request_media_stop() end
end

local function same_session(a, b)
    return a and b and a.call_id == b.call_id and a.remote_ip == b.remote_ip and
        a.remote_port == b.remote_port and a.local_rtp_port == b.local_rtp_port and
        a.codec == b.codec and a.ptime == b.ptime and a.remote_direction == b.remote_direction
end

start_pending_media = function()
    local pending = g_media_pending
    if not pending or g_media or native_state() ~= "idle" then return end
    g_media_pending = nil
    if pending.call ~= g_call or pending.call.terminating then
        media_state("cancelled", pending.call)
        return
    end
    pending.state = "starting"
    g_media = pending
    media_state("starting", pending.call)
    if not start_voip_engine(pending.session) then
        if g_media == pending then
            if native_state() == "idle" then g_media = nil
            else request_media_stop() end
        end
        media_state("error", pending.call)
        emit_callback("media", "error", with_identity({reason = "voip_start_failed"}, pending.call))
    end
end

local function request_cc_media(session, call)
    if call.terminating then return end
    if g_media_pending and g_media_pending.call == call and same_session(g_media_pending.session, session) then return end
    if g_media and g_media.call == call and g_media.state ~= "stopping" and
        same_session(g_media.session, session) then return end
    g_media_pending = {call = call, session = with_identity(session, call)}
    media_state("pending", call)
    if g_media or native_state() ~= "idle" then
        -- re-INVITE 更换媒体时，先等待旧原生媒体停止确认。
        request_media_stop()
    else
        start_pending_media()
    end
end

local function ip_ready_handler(ip, adapter)
    log_info("IP_READY", ip, adapter)
    g_ready_adapters[adapter] = true
end

local function ip_lose_handler(adapter)
    log_info("IP_LOSE", adapter)
    g_ready_adapters[adapter] = nil
    if not g_started then
        return
    end
    if adapter == g_current_adapter then
        local all_down = true
        for _ in pairs(g_ready_adapters) do
            all_down = false
            break
        end
        log_warn("current adapter lost, triggering error", adapter)
        emit_callback("error", "network_changed", {
            reason = "current_adapter_lost",
            adapter = adapter,
            all_down = all_down
        })
    end
end

local function sip_event_handler(event, action, payload)
    payload = payload or {}
    log_info("event:", event, "action:", action)
    if event == "register" then
        if action == "ok" then
            g_registered = true
            emit_callback("register", "ok", payload)
            emit_callback("ready")
        elseif action == "challenge" then
            emit_callback("register", "challenge", payload)
        else
            g_registered = false
            emit_callback("register", "failed", payload)
        end
    elseif event == "call" then
        if action == "incoming" then
            if g_call then return end
            g_call = new_call(payload.call_id, "in")
            emit_callback("call", "incoming", with_identity(payload, g_call))
            return
        end
        if action == "dial_rejected" then
            -- payload.dialog 可能指向另一通已建立的通话，不能据此认定本次外呼归属。
            local call = g_call
            if not call or call.direction ~= "out" or call.call_id or
                payload.target ~= call.target or not matches(call, nil, payload.sip_generation, payload.owner_token) then return end
            g_call = nil
            emit_callback("call", "dial_rejected", with_identity(payload, call))
            return
        end
        local call = event_call(payload)
        if not call then return end
        if action == "ended" or action == "failed" then
            call.terminating = true
            g_call = nil
            stop_voip_engine(call)
            emit_callback("call", action, with_identity(payload, call))
        elseif not call.terminating then
            if action == "established" then action = "connected" end
            emit_callback("call", action, with_identity(payload, call))
        end
    elseif event == "media" then
        local call = event_call(payload)
        if not call then return end
        if action == "ready" then
            local session = payload.session or payload
            request_cc_media(session, call)
        elseif action == "stop" then
            stop_voip_engine(call)
            emit_callback("media", "stop", with_identity(payload, call))
        end
    elseif event == "lifecycle" then
        local call = g_call
        if action == "offline" or action == "stopped" then
            g_registered = false
            if call then call.terminating = true end
            g_call = nil
            stop_voip_engine()
        end
        emit_callback("lifecycle", action, with_identity(payload, call))
    else
        emit_callback(event, action, payload)
    end
end

local function native_media_error(reason, detail)
    local media = g_media
    local actual = native_state()
    if not media or media.state == "stopping" or actual == "running" or actual == "starting" then return end
    -- C 层先投递错误事件，再清理资源并投递停止事件；getState 此时可能已返回空闲。
    -- 收到停止回调前，继续保留该媒体的通话归属。
    media.state = "stopping"
    media_state("error", media.call)
    media_state("stopping", media.call)
    if media.call == g_call and not media.call.terminating then
        emit_callback("media", "error", with_identity({reason = reason, detail = detail}, media.call))
    end
end

local function setup_voip_callbacks()
    voip.on("state", function(state)
        local media = g_media
        local actual = native_state()
        log_info("voip state", state, actual)
        if state == "started" then
            if media and media.state == "starting" and media.call == g_call and
                not media.call.terminating and actual == "running" then
                media.state = "running"
                media_state("started", media.call)
                emit_callback("media", "ready", with_identity(media.session, media.call))
            end
        elseif state == "stopped" or state == "idle" then
            if actual == "idle" and media and media.state == "stopping" then
                g_media = nil
                media_state("stopped", media.call)
                start_pending_media()
            end
        elseif state == "error" then
            native_media_error("voip_start_error")
        end
        -- 保留原生状态通知接口；业务层使用带通话身份的媒体事件。
        emit_callback("voip", "state", state)
    end)
    voip.on("error", function(err)
        native_media_error("voip_error", err)
        emit_callback("voip", "error", err)
    end)
end

function pcm_sip.init(config)
    if type(config) ~= "table" or not config.sip_server_addr or
        not config.sip_username or not config.sip_password then
        log_error("server, user and password are required")
        return false
    end
    if config.ptime ~= nil and config.ptime ~= 20 then return false end
    local codecs = config.codecs or default_config.codecs
    if type(codecs) ~= "table" or #codecs == 0 then return false end
    for _, codec in ipairs(codecs) do
        if codec ~= "PCMU" and codec ~= "PCMA" then return false end
    end
    g_config = {}
    for k, v in pairs(default_config) do g_config[k] = v end
    for k, v in pairs(config) do g_config[k] = v end
    g_config.sip_domain = g_config.sip_domain or g_config.sip_server_addr
    return true
end

function pcm_sip.start()
    if not g_config then
        log_error("please call pcm_sip.init() first")
        return false
    end

    if g_started then
        log_info("already started")
        return true
    end

    local ok, err = pcall(function()
        sipclient = require "exsipclient"
    end)

    if not ok or not sipclient then
        log_error("failed to load exsipclient:", err)
        return false
    end

    if not set_bridge_mode() then return false end

    setup_voip_callbacks()

    -- 订阅 IP 就绪/丢失事件
    if not g_ip_event_subscribed then
        sys.subscribe("IP_READY", ip_ready_handler)
        sys.subscribe("IP_LOSE", ip_lose_handler)
        g_ip_event_subscribed = true
        log_info("subscribed to IP_READY and IP_LOSE")
    end

    -- 确定并记录当前实际使用的网卡
    g_current_adapter = g_config.adapter or socket.dft()
    log_info("current adapter set:", g_current_adapter)

    local start_call_ok, sip_started = pcall(sipclient.start, {
        sip_server_addr = g_config.sip_server_addr,
        sip_server_port = g_config.sip_server_port,
        sip_domain = g_config.sip_domain,
        sip_username = g_config.sip_username,
        sip_password = g_config.sip_password,
        sip_transport = g_config.sip_transport,
        adapter = g_config.adapter,
        rtp_port = g_config.rtp_port,
        expires = g_config.expires,
        codecs = g_config.codecs,
        ptime = g_config.ptime,
        call_timeout = g_config.call_timeout,
        debug_sip_response = g_config.debug_sip_response,
        early_media = true,
        early_media_response = 183,
        event_callback = sip_event_handler
    })
    if not start_call_ok or not sip_started then
        if g_ip_event_subscribed then
            sys.unsubscribe("IP_READY", ip_ready_handler)
            sys.unsubscribe("IP_LOSE", ip_lose_handler)
            g_ip_event_subscribed = false
        end
        g_current_adapter = nil
        log_error("sipclient.start failed:", sip_started)
        return false
    end

    g_started = true
    log_info("started", "adapter", g_config.adapter)
    return true
end

function pcm_sip.dial(target, from_number, owner_token)
    if not g_started or not sipclient or not sipclient.call or type(target) ~= "string" or g_call then return false end
    local call = new_call(nil, "out", owner_token, target)
    if call.owner_token == nil then call.owner_token = "sip:" .. call.sip_generation end
    g_call = call
    -- 投递到异步协议任务前，先绑定本地外呼身份，以便识别拨号拒绝事件。
    emit_callback("call", "dialing", with_identity({}, call))
    sipclient.call(target, from_number)
    return true, with_identity({}, call)
end

function pcm_sip.accept(call_id, generation, owner_token)
    if not g_started or not sipclient or not sipclient.answer or
        not matches(g_call, call_id, generation, owner_token) or g_call.terminating or g_call.direction ~= "in" then return false end
    if g_call.answer_requested then return true end
    g_call.answer_requested = true
    sipclient.answer(g_call.call_id)
    return true
end

function pcm_sip.progress(call_id, generation, owner_token)
    if not g_started or not sipclient or not sipclient.progress or
        not matches(g_call, call_id, generation, owner_token) or g_call.terminating or g_call.direction ~= "in" then return false end
    if g_call.progress_requested then return true end
    g_call.progress_requested = true
    sipclient.progress(g_call.call_id)
    return true
end

function pcm_sip.hangUp(force, call_id, generation, owner_token)
    if type(force) == "string" then
        owner_token, generation, call_id, force = generation, call_id, force, false
    end
    if not g_started or not sipclient or not sipclient.hangup or
        not matches(g_call, call_id, generation, owner_token) then return false end
    if g_call.terminating and force ~= true then return true end
    if force == true then
        if g_call.force_requested then return true end
        g_call.force_requested = true
    end
    g_call.terminating = true
    stop_voip_engine(g_call)
    -- 外呼只有收到首个对话事件后，才能获得协议层的 Call-ID。
    -- 收到匹配的协议终结事件前，保留前台通话及其挂断中状态。
    sipclient.hangup(force == true, g_call.call_id)
    return true
end

function pcm_sip.fail(code, reason, call_id, generation, owner_token)
    if not g_started or not sipclient or not sipclient.fail or
        not matches(g_call, call_id, generation, owner_token) or g_call.terminating or
        g_call.direction ~= "in" or g_call.answer_requested then return false end
    g_call.terminating = true
    stop_voip_engine(g_call)
    sipclient.fail(code, reason, g_call.call_id)
    return true
end

function pcm_sip.is_media_idle()
    return g_media == nil and g_media_pending == nil and native_state() == "idle"
end

function pcm_sip.on(callback)
    if type(callback) == "function" then
        local events = {"register", "ready", "call", "media", "message", "dtmf", "voip", "lifecycle", "error"}
        for _, event in ipairs(events) do
            g_callbacks[event] = function(...)
                callback(event, ...)
            end
        end
        log_info("unified callback registered for all events")
    else
        log_error("callback must be a function")
    end
end

function pcm_sip.isRegistered()
    return g_registered
end

return pcm_sip
