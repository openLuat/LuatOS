--[[
@module  sip_main
@summary SIP 协议栈模块
@version 1.0
@date    2026.07.17
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
local g_media_ready = false
local g_call_connected = false
local g_connected_published = false
local g_progress_confirmed = false
local g_progress_published = false

local function logi(...)
    log.info("sip_main", ...)
end

local function set_state(new_state)
    if g_state ~= new_state then
        logi("状态切换", g_state, "->", new_state)
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

local function publish_media_state()
    if g_state == STATE_IDLE or g_state == STATE_DISCONNECTING or not g_media_ready then return end
    if g_call_connected then
        if not g_connected_published then
            g_connected_published = true
            sys.publish("SIP_CONNECTED")
        end
    elseif g_state == STATE_PROGRESSING and g_progress_confirmed and not g_progress_published then
        g_progress_published = true
        sys.publish("SIP_PROGRESSING")
    end
end

local function finish_call(reason, failed)
    local was_active = g_state ~= STATE_IDLE
    reset_media_state()
    set_state(STATE_IDLE)
    if was_active then sys.publish(failed and "SIP_FAILED" or "SIP_DISCONNECTED", reason) end
end

local function fail_call(reason)
    if g_state == STATE_IDLE or g_state == STATE_DISCONNECTING then return end
    reset_media_state()
    set_state(STATE_DISCONNECTING)
    pcm_sip.hangUp()
    sys.publish("SIP_FAILED", reason)
end

-- ==================== 请求处理 ====================

local function on_sip_dial_req(uri)
    if g_state ~= STATE_IDLE then
        log.warn("sip_main", "SIP 忙，无法拨号", g_state)
        return
    end
    reset_media_state()
    set_state(STATE_DIALING)
    logi("执行拨号", uri)
    local ok = pcm_sip.dial(uri)
    if not ok then
        log.error("sip_main", "pcm_sip.dial 失败")
        set_state(STATE_IDLE)
        sys.publish("SIP_FAILED", "dial_failed")
    end
end

local function on_sip_accept_req()
    if g_state ~= STATE_INCOMING and g_state ~= STATE_PROGRESSING then
        log.warn("sip_main", "当前不是来电状态", g_state)
        return
    end
    logi("执行接听")
    local ok = pcm_sip.accept()
    if not ok then
        log.error("sip_main", "pcm_sip.accept 失败")
        fail_call("accept_failed")
    end
end

local function on_sip_progress_req()
    if g_state ~= STATE_INCOMING then
        log.warn("sip_main", "当前不能启动早期媒体", g_state)
        return
    end
    set_state(STATE_PROGRESSING)
    if not pcm_sip.progress or not pcm_sip.progress() then
        log.error("sip_main", "pcm_sip.progress 失败")
        fail_call("progress_failed")
    end
    -- progress() 仅投递请求；等待 183 已发送和 VoIP started 后才拨打 CC。
end

local function on_sip_hangup_req()
    if g_state == STATE_IDLE then
        log.warn("sip_main", "SIP 已空闲")
        return
    end
    if g_state == STATE_DISCONNECTING then
        logi("SIP 正在挂断")
        return
    end
    reset_media_state()
    set_state(STATE_DISCONNECTING)
    logi("执行挂断")
    local ok = pcm_sip.hangUp()
    if not ok then
        log.error("sip_main", "pcm_sip.hangUp 失败")
    end
end

sys.subscribe("SIP_DIAL_REQ", on_sip_dial_req)
sys.subscribe("SIP_ACCEPT_REQ", on_sip_accept_req)
sys.subscribe("SIP_PROGRESS_REQ", on_sip_progress_req)
sys.subscribe("SIP_HANGUP_REQ", on_sip_hangup_req)

-- ==================== SIP 事件处理 ====================

local function on_sip_event(event, action, data)
    logi("事件", event, action)

    if event == "register" then
        if action == "ok" then
            g_registered = true
            logi("SIP 注册成功")
        else
            g_registered = false
            logi("SIP 注册失败", action)
        end

    elseif event == "ready" then
        logi("SIP 服务已就绪")

    elseif event == "call" then
        if action == "incoming" then
            reset_media_state()
            set_state(STATE_INCOMING)
            logi("SIP 来电", data and data.from or "unknown")
            local headers = data and data.headers or {}
            sys.publish("SIP_INCOMING", data and data.from or "", data and data.uri or "", headers["to"] or "")

        elseif action == "ringing" then
            logi("SIP 响铃中")

        elseif action == "progress" then
            if g_state == STATE_PROGRESSING then
                g_progress_confirmed = true
                publish_media_state()
            end

        elseif action == "connected" or action == "established" then
            if g_state == STATE_IDLE or g_state == STATE_DISCONNECTING then return end
            g_call_connected = true
            set_state(STATE_CONNECTED)
            logi("SIP 已接通，等待媒体就绪")
            publish_media_state()

        elseif action == "ended" then
            finish_call(data and data.reason or "", false)

        elseif action == "failed" or action == "dial_rejected" then
            finish_call(data and data.reason or action, true)
        end

    elseif event == "media" then
        if action == "ready" then
            data = data or {}
            local ip = data.remote_ip or (data.session and data.session.remote_ip) or ""
            local port = data.remote_port or (data.session and data.session.remote_port) or 0
            logi("SIP 媒体就绪", ip, port, data.codec)
            if g_state ~= STATE_IDLE and g_state ~= STATE_DISCONNECTING then
                g_media_ready = true
                publish_media_state()
            end
        elseif action == "stop" then
            g_media_ready = false
            logi("SIP 媒体停止", data and data.reason or "")
        elseif action == "error" then
            fail_call(data and data.reason or "media_start_failed")
        end

    elseif event == "voip" then
        if action == "state" then
            logi("VoIP 状态", data)
            if data == "error" then fail_call("voip_error") end
        elseif action == "error" then
            log.error("sip_main", "VoIP 错误", data)
            fail_call("voip_error")
        end

    elseif event == "lifecycle" then
        if action == "online" then
            logi("SIP 在线", data and data.local_ip or "")
        elseif action == "stopped" or action == "offline" then
            g_registered = false
            logi("SIP 已离线", action)
            finish_call(action, true)
        end

    elseif event == "error" then
        log.error("sip_main", "SIP 错误", action, data)
        if action == "network_changed" then fail_call("network_changed") end

    elseif event == "message" then
        if action == "rx" then
            logi("收到 SIP MESSAGE", data and data.from or "", data and data.body or "")
        end
    end
end

-- ==================== 公共 API ====================

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

    -- pcm_sip.start 统一验证并设置 VoIP bridge 模式，失败直接中止。
    local start_ok = pcm_sip.start()
    if not start_ok then
        log.error("sip_main", "pcm_sip.start 失败")
        return false
    end
    logi("SIP 启动完成")
    return true
end

function sip_main.dial(uri)
    sys.publish("SIP_DIAL_REQ", uri)
end

function sip_main.accept()
    sys.publish("SIP_ACCEPT_REQ")
end

function sip_main.hangup()
    sys.publish("SIP_HANGUP_REQ")
end

function sip_main.get_state()
    return g_state
end

function sip_main.is_registered()
    return g_registered
end

return sip_main
