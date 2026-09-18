--[[
@module  sip_main
@summary SIP 协议栈模块
@version 1.1
@date    2026.09.18
@author  蒋骞
@usage
封装 pcm_sip 的注册、事件处理、拨号/接听/挂断。
通过发布/订阅消息与 bridge.lua 和 cc_main.lua 交互。
]]

local pcm_sip = require "pcm_sip"
local config = require "config"
-- 自动加载桥接协调器
local bridge = require "bridge"

local sip_main = {}

local STATE_IDLE = "sip_idle"
local STATE_INCOMING = "sip_incoming"
local STATE_PROGRESSING = "sip_progressing"
local STATE_DIALING = "sip_dialing"
local STATE_CONNECTED = "sip_connected"
local STATE_DISCONNECTING = "sip_disconnecting"

local g_state = STATE_IDLE
local g_registered = false
local g_call
local g_pending_owner
local g_media_ready = false
local g_call_connected = false
local g_connected_published = false
local g_progress_confirmed = false
local g_progress_published = false

local function logi(...) log.info("sip_main", ...) end

local function set_state(new_state)
    if g_state ~= new_state then
        logi("state", g_state, "->", new_state)
        g_state = new_state
    end
end

local function reset_media_state()
    g_media_ready = false
    g_call_connected = false
    g_connected_published = false
    g_progress_confirmed = false
    g_progress_published = false
end

local function matches(call_id, generation, owner_token)
    return g_call and (call_id == nil or call_id == g_call.call_id) and
        (generation == nil or generation == g_call.sip_generation) and
        (owner_token == nil or owner_token == g_call.owner_token)
end

local function publish_call(topic, reason, call)
    if reason ~= nil then
        sys.publish(topic, reason, call.call_id, call.sip_generation, call.owner_token)
    else
        sys.publish(topic, call.call_id, call.sip_generation, call.owner_token)
    end
end

local function match_event(data)
    if not g_call or not matches(nil, data.sip_generation, data.owner_token) then return false end
    if data.call_id and not g_call.call_id and g_call.direction == "out" then
        g_call.call_id = data.call_id
        publish_call("SIP_CALL_BOUND", nil, g_call)
    end
    return matches(data.call_id, data.sip_generation, data.owner_token)
end

local function publish_media_state()
    if not g_call or g_state == STATE_IDLE or g_state == STATE_DISCONNECTING or not g_media_ready then return end
    if g_call_connected then
        if not g_connected_published then
            g_connected_published = true
            publish_call("SIP_CONNECTED", nil, g_call)
        end
    elseif g_state == STATE_PROGRESSING and g_progress_confirmed and not g_progress_published then
        g_progress_published = true
        publish_call("SIP_PROGRESSING", nil, g_call)
    end
end

local function finish_call(reason, failed)
    local call = g_call
    if not call then return end
    reason = call.failure_reason or reason
    failed = failed or call.failure_reason ~= nil
    g_call = nil
    g_pending_owner = nil
    reset_media_state()
    set_state(STATE_IDLE)
    publish_call(failed and "SIP_FAILED" or "SIP_DISCONNECTED", reason or "", call)
end

local function fail_call(reason)
    if not g_call or g_state == STATE_IDLE or g_state == STATE_DISCONNECTING then return end
    g_call.failure_reason = reason
    reset_media_state()
    set_state(STATE_DISCONNECTING)
    -- 协议终结前保留通话归属，包括尚未获得 Call-ID 的外呼。
    pcm_sip.hangUp(false, g_call.call_id, g_call.sip_generation, g_call.owner_token)
end

local function on_sip_dial_req(uri, owner_token)
    if g_state ~= STATE_IDLE then
        if owner_token ~= nil and (not g_call or owner_token ~= g_call.owner_token) then
            sys.publish("SIP_FAILED", "busy", nil, nil, owner_token)
        end
        return
    end
    g_pending_owner = owner_token
    reset_media_state()
    set_state(STATE_DIALING)
    local ok, call = pcm_sip.dial(uri, nil, owner_token)
    if not ok then
        set_state(STATE_IDLE)
        g_pending_owner = nil
        sys.publish("SIP_FAILED", "dial_failed", nil, nil, owner_token)
    elseif not g_call and g_state == STATE_DIALING then
        g_call = call
        g_call.direction = "out"
    end
end

local function on_sip_accept_req(call_id, generation, owner_token)
    if not matches(call_id, generation, owner_token) or
        (g_state ~= STATE_INCOMING and g_state ~= STATE_PROGRESSING) then return end
    if not pcm_sip.accept(g_call.call_id, g_call.sip_generation, g_call.owner_token) then fail_call("accept_failed") end
end

local function on_sip_progress_req(call_id, generation, owner_token)
    if not matches(call_id, generation, owner_token) or g_state ~= STATE_INCOMING then return end
    set_state(STATE_PROGRESSING)
    if not pcm_sip.progress(g_call.call_id, g_call.sip_generation, g_call.owner_token) then fail_call("progress_failed") end
    -- 必须同时确认 183 已发送，并收到原生媒体实际启动的回调。
end

local function on_sip_hangup_req(call_id, generation, owner_token)
    if not matches(call_id, generation, owner_token) or g_state == STATE_IDLE or g_state == STATE_DISCONNECTING then return end
    reset_media_state()
    set_state(STATE_DISCONNECTING)
    pcm_sip.hangUp(false, g_call.call_id, g_call.sip_generation, g_call.owner_token)
end

local function on_sip_fail_req(code, reason, call_id, generation, owner_token)
    if not matches(call_id, generation, owner_token) or
        (g_state ~= STATE_INCOMING and g_state ~= STATE_PROGRESSING) then return end
    reset_media_state()
    set_state(STATE_DISCONNECTING)
    if not pcm_sip.fail(code, reason, g_call.call_id, g_call.sip_generation, g_call.owner_token) then
        pcm_sip.hangUp(false, g_call.call_id, g_call.sip_generation, g_call.owner_token)
    end
end

sys.subscribe("SIP_DIAL_REQ", on_sip_dial_req)
sys.subscribe("SIP_ACCEPT_REQ", on_sip_accept_req)
sys.subscribe("SIP_PROGRESS_REQ", on_sip_progress_req)
sys.subscribe("SIP_HANGUP_REQ", on_sip_hangup_req)
sys.subscribe("SIP_FAIL_REQ", on_sip_fail_req)

local function on_sip_event(event, action, data)
    logi("event", event, action)
    if event == "register" then
        if action == "ok" then g_registered = true
        elseif action ~= "challenge" then g_registered = false end
    elseif event == "call" then
        data = data or {}
        if action == "dialing" then
            if g_state ~= STATE_DIALING or g_call or
                (g_pending_owner ~= nil and g_pending_owner ~= data.owner_token) then return end
            g_call = {call_id = data.call_id, sip_generation = data.sip_generation,
                owner_token = data.owner_token, direction = "out"}
            return
        elseif action == "incoming" then
            if g_state ~= STATE_IDLE then return end
            reset_media_state()
            g_call = {call_id = data.call_id, sip_generation = data.sip_generation, direction = "in"}
            set_state(STATE_INCOMING)
            local headers = data.headers or {}
            sys.publish("SIP_INCOMING", data.from or "", data.uri or "", headers["to"] or "",
                g_call.call_id, g_call.sip_generation)
            return
        end
        if not match_event(data) then return end
        if action == "progress" then
            if g_state == STATE_PROGRESSING then
                g_progress_confirmed = true
                publish_media_state()
            end
        elseif action == "connected" or action == "established" then
            if g_state == STATE_IDLE or g_state == STATE_DISCONNECTING then return end
            g_call_connected = true
            set_state(STATE_CONNECTED)
            publish_media_state()
        elseif action == "ended" then
            finish_call(data.reason, false)
        elseif action == "failed" or action == "dial_rejected" then
            finish_call(data.reason or action, true)
        end
    elseif event == "media" then
        data = data or {}
        if action == "state" then
            -- 旧媒体停止事件只唤醒清理检查，不更新新通话的状态。
            sys.publish("SIP_MEDIA_STATE", data.state, data.call_id, data.sip_generation, data.owner_token)
            if match_event(data) and data.state ~= "started" then g_media_ready = false end
        elseif match_event(data) then
            if action == "ready" and g_state ~= STATE_IDLE and g_state ~= STATE_DISCONNECTING then
                g_media_ready = true
                publish_media_state()
            elseif action == "stop" then
                g_media_ready = false
            elseif action == "error" or action == "failed" then
                fail_call(data.reason or "media_start_failed")
            end
        end
    elseif event == "lifecycle" then
        if action == "stopped" or action == "offline" then
            g_registered = false
            if match_event(data or {}) then finish_call(action, true) end
        end
    elseif event == "error" and action == "network_changed" then
        fail_call("network_changed")
    end
end

function sip_main.init()
    logi("SIP 初始化开始")
    local sip_ok = pcm_sip.init({
        sip_server_addr = config.sip_server_addr,
        sip_server_port = config.sip_server_port,
        sip_domain = config.sip_domain,
        sip_username = config.sip_username,
        sip_password = config.sip_password,
        sip_transport = config.sip_transport,
        rtp_port = config.rtp_port,
        codecs = {config.codec},
        ptime = config.ptime,
        adapter = config.adapter,
    })
    if not sip_ok then
        log.error("sip_main", "pcm_sip.init 失败")
        return false
    end

    pcm_sip.on(on_sip_event)

    -- pcm_sip.start 统一验证并设置 VoIP 桥接模式，失败直接中止。
    local start_ok = pcm_sip.start()
    if not start_ok then
        log.error("sip_main", "pcm_sip.start 失败")
        return false
    end
    logi("SIP 启动完成")
    return true
end

function sip_main.dial(uri, owner_token)
    sys.publish("SIP_DIAL_REQ", uri, owner_token)
end

function sip_main.accept()
    if g_call then sys.publish("SIP_ACCEPT_REQ", g_call.call_id, g_call.sip_generation, g_call.owner_token) end
end

function sip_main.hangup()
    if g_call then sys.publish("SIP_HANGUP_REQ", g_call.call_id, g_call.sip_generation, g_call.owner_token) end
end

function sip_main.is_media_idle()
    return pcm_sip.is_media_idle()
end

function sip_main.get_state()
    return g_state
end

function sip_main.is_registered()
    return g_registered
end

return sip_main
