--[[
@module  sip_main
@summary SIP 协议栈模块
@version 1.0.1
@date    2026.07.20
@author  蒋骞
@usage
封装 exsip 的注册、事件处理、拨号/接听/挂断。
通过发布/订阅消息与 bridge.lua 和 cc_main.lua 交互。

新增：
- SIP_FAIL_REQ：由 bridge 请求结束 SIP 早期媒体(486/480)，避免 CC 忙时 SIP 分支悬挂。
- voip 误启动保护：无有效 SIP 通话时 voip 意外启动则立即停止。
- SIP MESSAGE 转发为备用控制通道(SIP_MESSAGE)。
- VOIP_STARTED/VOIP_STOPPED：broadcast voip 状态，bridge 据此在 voip 就绪后重启早期媒体回铃音。
]]

local exsip = require "exsip"
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

local function on_sip_dial_req(uri,from_number)
    if g_state ~= STATE_IDLE then
        log.warn("sip_main", "SIP 忙，无法拨号", g_state)
        return
    end
    set_state(STATE_DIALING)
    logi("执行拨号", uri)
    local ok = exsip.dial(uri,from_number)
    if not ok then
        log.error("sip_main", "exsip.dial 失败")
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
    local ok = exsip.accept()
    if not ok then
        log.error("sip_main", "exsip.accept 失败")
        set_state(STATE_IDLE)
        sys.publish("SIP_FAILED", "accept_failed")
    end
end

local function on_sip_progress_req()
    if g_state ~= STATE_INCOMING then
        log.warn("sip_main", "当前不能启动早期媒体", g_state)
        return
    end
    if not exsip.progress or not exsip.progress() then
        log.error("sip_main", "exsip.progress 失败")
        set_state(STATE_IDLE)
        sys.publish("SIP_FAILED", "progress_failed")
        return
    end
    set_state(STATE_PROGRESSING)
    sys.publish("SIP_PROGRESSING")
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

-- bridge 请求结束 SIP 早期媒体：CC 忙/未就绪时避免 SIP 分支悬挂。
local function on_sip_fail_req(code, reason)
    if g_state == STATE_IDLE then
        log.warn("sip_main", "SIP 已空闲，忽略失败请求")
        return
    end
    if g_state == STATE_INCOMING or g_state == STATE_PROGRESSING then
        logi("结束 SIP 早期媒体", code, reason)
        if exsip.fail then
            exsip.fail(code or 480, reason or "Temporarily Unavailable")
        else
            exsip.hangUp()
        end
        set_state(STATE_IDLE)
    else
        set_state(STATE_DISCONNECTING)
        logi("执行挂断（失败请求）")
        exsip.hangUp()
    end
end

sys.subscribe("SIP_DIAL_REQ", on_sip_dial_req)
sys.subscribe("SIP_ACCEPT_REQ", on_sip_accept_req)
sys.subscribe("SIP_PROGRESS_REQ", on_sip_progress_req)
sys.subscribe("SIP_HANGUP_REQ", on_sip_hangup_req)
sys.subscribe("SIP_FAIL_REQ", on_sip_fail_req)

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
            local headers = data and data.headers or {}
            sys.publish("SIP_INCOMING", data and data.from or "", data and data.uri or "", headers["to"] or "")

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
            data = data or {}
            local ip = data.remote_ip or (data.session and data.session.remote_ip) or ""
            local port = data.remote_port or (data.session and data.session.remote_port) or 0
            logi("SIP 媒体就绪", ip, port, data.codec)
        elseif action == "stop" then
            logi("SIP 媒体停止", data and data.reason or "")
        end

    elseif event == "voip" then
        if action == "state" then
            logi("VoIP 状态", data)
            -- 参考版：voip 在无有效 SIP 通话时意外启动(抢占 I2S/音频硬件)则立即停止。
            if data == "started" and (g_state == STATE_IDLE or g_state == STATE_DISCONNECTING) then
                log.warn("sip_main", "VoIP 在无有效 SIP 通话时启动，立即停止")
                if voip and voip.stop then
                    voip.stop()
                end
            elseif data == "started" then
                -- 参考版：voip 就绪后在呼出早期媒体阶段重新启动铃声，避免 CC_MAKE_CALL_OK 先到时遗漏。
                sys.publish("VOIP_STARTED")
            elseif data == "stopped" then
                sys.publish("VOIP_STOPPED")
            end
        elseif action == "stats" then
            data = data or {}
            logi("VoIP 统计", data.tx_packets, data.rx_packets, data.rx_lost)
        elseif action == "error" then
            log.error("sip_main", "VoIP 错误", data)
        end

    elseif event == "lifecycle" then
        if action == "online" then
            logi("SIP 在线", data and data.local_ip or "")
        elseif action == "stopped" then
            g_registered = false
            logi("SIP 已停止")
        end

    elseif event == "error" then
        log.error("sip_main", "SIP 错误", action, data)

    elseif event == "message" then
        if action == "rx" then
            logi("收到 SIP MESSAGE", data and data.from or "", data and data.body or "")
            -- 备用控制通道：转发给 bridge 解析 JSON 命令
            sys.publish("SIP_MESSAGE", data and data.body or "")
        end
    end
end

-- ==================== 公共 API ====================

function sip_main.init()
    logi("SIP 初始化开始")
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
        cc_sip_bridge = true,
        auto_answer = false,  -- 由 bridge 控制
        early_media = true,
        early_media_response = 183,
        adapter = config.adapter,
    })
    if not sip_ok then
        log.error("sip_main", "exsip.init 失败")
        return false
    end

    exsip.on(on_sip_event)

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
