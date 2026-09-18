-- 仅用于本 demo：SIP 信令 + VoIP PCM 桥接，无本地音频后端。
local pcm_sip = {}
local sipclient
local g_config
local g_started = false
local g_registered = false
local g_callbacks = {}
local g_cc_media_pending
local g_cc_media_starting = false
local g_cc_media_restarting = false
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

local function start_pending_cc_media()
    local session = g_cc_media_pending
    if not session then return end
    g_cc_media_starting = true
    if not start_voip_engine(session) then
        g_cc_media_pending = nil
        g_cc_media_starting = false
        emit_callback("media", "error", {reason = "voip_start_failed"})
    end
end

local function request_cc_media(session)
    g_cc_media_pending = session
    local state = voip and voip.getState and voip.getState() or "idle"
    if state ~= "idle" then
        g_cc_media_restarting = true
        g_cc_media_starting = false
        if voip and voip.stop then voip.stop() end
    else
        g_cc_media_restarting = false
        start_pending_cc_media()
    end
end

local function stop_voip_engine()
    g_cc_media_pending = nil
    g_cc_media_starting = false
    g_cc_media_restarting = false
    if not voip then
        return
    end
    if voip.stop then
        voip.stop()
        log_info("voip engine stopping")
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
    log_info("event:", event, "action:", action)

    if event == "register" then
        if action == "ok" then
            g_registered = true
            emit_callback("register", "ok", payload)
            emit_callback("ready")
        elseif action == "challenge" then
            -- challenge 是正常的认证流程，不标记为未注册
            emit_callback("register", "challenge", payload)
        else
            g_registered = false
            emit_callback("register", "failed", payload)
        end
    elseif event == "call" then
        if action == "incoming" then
            local incoming_call = {
                from = payload.from,
                call_id = payload.call_id,
                headers = payload.headers,
                remote_sdp = payload.remote_sdp,
                body = payload.body,
                uri = payload.uri
            }
            emit_callback("call", "incoming", incoming_call)
        elseif action == "ringing" or action == "progress" then
            emit_callback("call", action, payload)
        elseif action == "connected" or action == "established" then
            emit_callback("call", "connected", payload)
        elseif action == "dial_rejected" then
            -- 本次拨号未受理；busy 时不能重置已经存在的通话。
            emit_callback("call", "dial_rejected", payload)
        elseif action == "ended" or action == "failed" then
            stop_voip_engine()

            emit_callback("call", "ended", payload)

        end
    elseif event == "media" then
        if action == "ready" then
            local session = payload.session or payload
            log_info("media ready", session.remote_ip, session.remote_port, session.codec)
            request_cc_media(session)
        elseif action == "stop" then
            stop_voip_engine()
            emit_callback("media", "stop", payload)
        end
    elseif event == "message" then
        if action == "rx" then
            emit_callback("message", "rx", {
                from = payload.from,
                body = payload.body
            })
        elseif action == "sent" then
            emit_callback("message", "sent", {
                to = payload.to
            })
        end
    elseif event == "dtmf" then
        emit_callback("dtmf", action, payload)
    elseif event == "lifecycle" then
        log_info("lifecycle:", action)
        if action == "offline" then
            -- SIP 离线时，停止 voip 引擎，让下次重连时使用新网卡
            stop_voip_engine()

            g_registered = false
        elseif action == "stopped" then
            stop_voip_engine()

            g_registered = false
        end
        emit_callback("lifecycle", action, payload)
    elseif event == "error" then
        log_error("error:", action, payload.event, payload.param)
        emit_callback("error", action, payload)
    end
end

local function setup_voip_callbacks()
    voip.on("state", function(state)
        log_info("voip state", state)
        if state == "started" and g_cc_media_starting and not g_cc_media_restarting then
            local session = g_cc_media_pending
            g_cc_media_pending = nil
            g_cc_media_starting = false
            if session then emit_callback("media", "ready", session) end
        elseif state == "error" then
            g_cc_media_pending = nil
            g_cc_media_starting = false
            g_cc_media_restarting = false
        elseif state == "stopped" and g_cc_media_restarting then
            g_cc_media_restarting = false
            start_pending_cc_media()
        end
        emit_callback("voip", "state", state)
    end)
    voip.on("error", function(err) emit_callback("voip", "error", err) end)
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

function pcm_sip.dial(target,from_number)
    if not g_started then
        log_error("not started, call pcm_sip.start() first")
        return false
    end

    if not sipclient or not sipclient.call then
        log_error("sipclient.call not available")
        return false
    end

    if type(target) ~= "string" then
        log_error("target must be a string")
        return false
    end
    sipclient.call(target,from_number)
    log_info("calling:", target,from_number)
    return true
end

function pcm_sip.accept()
    if not g_started then
        log_error("not started")
        return false
    end

    if not sipclient or not sipclient.answer then
        log_error("sipclient.answer not available")
        return false
    end

    sipclient.answer()
    log_info("answering call")
    return true
end

function pcm_sip.progress()
    if not g_started then
        log_error("not started")
        return false
    end

    if not sipclient or not sipclient.progress then
        log_error("sipclient.progress not available")
        return false
    end

    sipclient.progress()
    log_info("progressing incoming call")
    return true
end

function pcm_sip.hangUp(force)
    if not g_started then
        log_error("not started")
        return false
    end

    if not sipclient or not sipclient.hangup then
        log_error("sipclient.hangup not available")
        return false
    end

    if force then stop_voip_engine() end
    sipclient.hangup(force == true)
    log_info("hanging up")
    return true
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
