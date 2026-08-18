--[[
@module  sip_main
@summary SIP 协议栈模块
@version 1.0
@date    2026.07.17
@author  蒋骞
@usage
封装 exsip 的注册、事件处理、拨号/接听/挂断。
通过发布/订阅消息与 bridge.lua 和 cc_main.lua 交互。
]]

local exsip = require "exsip"
local config = require "config"
-- 自动加载桥接协调器
local bridge = require "bridge"

local sip_main = {}

local STATE_IDLE = "sip_idle"
local STATE_INCOMING = "sip_incoming"
local STATE_DIALING = "sip_dialing"
local STATE_CONNECTED = "sip_connected"
local STATE_DISCONNECTING = "sip_disconnecting"

local g_state = STATE_IDLE
local g_registered = false

local function logi(...)
    log.info("sip_main", ...)
end

local function set_state(new_state)
    if g_state ~= new_state then
        logi("状态切换", g_state, "->", new_state)
        g_state = new_state
    end
end

-- ==================== 请求处理 ====================

local function on_sip_dial_req(uri)
    if g_state ~= STATE_IDLE then
        log.warn("sip_main", "SIP 忙，无法拨号", g_state)
        return
    end
    set_state(STATE_DIALING)
    logi("执行拨号", uri)
    local ok = exsip.dial(uri)
    if not ok then
        log.error("sip_main", "exsip.dial 失败")
        set_state(STATE_IDLE)
        sys.publish("SIP_FAILED", "dial_failed")
    end
end

local function on_sip_accept_req()
    if g_state ~= STATE_INCOMING then
        log.warn("sip_main", "当前不是来电状态", g_state)
        return
    end
    logi("执行接听")
    local ok = exsip.accept()
    if not ok then
        log.error("sip_main", "exsip.accept 失败")
        set_state(STATE_IDLE)
        sys.publish("SIP_FAILED", "accept_failed")
    end
end

local function on_sip_hangup_req()
    if g_state == STATE_IDLE then
        log.warn("sip_main", "SIP 已空闲")
        return
    end
    set_state(STATE_DISCONNECTING)
    logi("执行挂断")
    local ok = exsip.hangUp()
    if not ok then
        log.error("sip_main", "exsip.hangUp 失败")
    end
end

sys.subscribe("SIP_DIAL_REQ", on_sip_dial_req)
sys.subscribe("SIP_ACCEPT_REQ", on_sip_accept_req)
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
            set_state(STATE_INCOMING)
            logi("SIP 来电", data and data.from or "unknown")
            sys.publish("SIP_INCOMING", data and data.from or "", data and data.uri or "", data and data.headers["to"] or "")

        elseif action == "ringing" then
            logi("SIP 响铃中")

        elseif action == "connected" or action == "established" then
            set_state(STATE_CONNECTED)
            logi("SIP 通话已建立")
            sys.publish("SIP_CONNECTED")

        elseif action == "ended" then
            set_state(STATE_IDLE)
            logi("SIP 通话已结束", data and data.reason or "unknown")
            sys.publish("SIP_DISCONNECTED", data and data.reason or "")

        elseif action == "failed" then
            set_state(STATE_IDLE)
            logi("SIP 通话失败", data and data.reason or "unknown")
            sys.publish("SIP_FAILED", data and data.reason or "")
        end

    elseif event == "media" then
        if action == "ready" then
            local ip = data.remote_ip or (data.session and data.session.remote_ip) or ""
            local port = data.remote_port or (data.session and data.session.remote_port) or 0
            logi("SIP 媒体就绪", ip, port, data.codec)
        elseif action == "stop" then
            logi("SIP 媒体停止", data.reason)
        end

    elseif event == "voip" then
        if action == "state" then
            logi("VoIP 状态", data)
        elseif action == "stats" then
            logi("VoIP 统计", data.tx_packets, data.rx_packets, data.rx_lost)
        elseif action == "error" then
            log.error("sip_main", "VoIP 错误", data)
        end

    elseif event == "lifecycle" then
        if action == "online" then
            logi("SIP 在线", data.local_ip)
        elseif action == "stopped" then
            g_registered = false
            logi("SIP 已停止")
        end

    elseif event == "error" then
        log.error("sip_main", "SIP 错误", action, data)

    elseif event == "message" then
        if action == "rx" then
            logi("收到 SIP MESSAGE", data.from, data.body)
        end
    end
end

-- ==================== 公共 API ====================

function sip_main.init()
    logi("SIP 初始化开始")
    exsip.on(on_sip_event)

    local sip_ok = exsip.init({
        sip_server_addr = config.sip_server_addr,
        sip_server_port = config.sip_server_port,
        sip_domain = config.sip_domain,
        sip_username = config.sip_username,
        sip_password = config.sip_password,
        sip_transport = config.sip_transport,
        rtp_port = config.rtp_port,
        codecs = {config.codec},
        ptime = config.ptime,
        auto_answer = false,  -- 由 bridge 控制
        adapter = config.adapter,
    })
    if not sip_ok then
        log.error("sip_main", "exsip.init 失败")
        return false
    end

    -- 设置为桥接模式：voip 不控制 I2S，PCM 与 cc 交换
    if voip and voip.setAudioMode then
        local ok = voip.setAudioMode(voip.AUDIO_MODE_BRIDGE)
        if ok then
            logi("voip 已设置为桥接模式")
        else
            log.warn("sip_main", "voip 设置桥接模式失败，尝试先停止后重试")
            if voip.stop then voip.stop() end
            sys.wait(500)
            ok = voip.setAudioMode(voip.AUDIO_MODE_BRIDGE)
            if ok then
                logi("voip 桥接模式设置成功")
            else
                log.error("sip_main", "voip 桥接模式设置失败")
            end
        end
    else
        log.warn("sip_main", "voip 模块不可用，跳过桥接模式设置")
    end

    local start_ok = exsip.start()
    if not start_ok then
        log.error("sip_main", "exsip.start 失败")
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
