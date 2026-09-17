--[[
@module  bridge
@summary SIP 与 CC 的桥接协调器
@version 1.0
@date    2026.07.17
@author  蒋骞
@usage
由 sip_main.lua 自动 require 加载。
通过订阅 SIP/CC 事件，发送跨模块请求，完成自动接听、自动拨号和挂断同步。
bridge 不直接引用 sip_main 或 cc_main，避免循环依赖。
]]

local config = require "config"

local bridge = {}

local STATE_SIP_IDLE = "sip_idle"
local STATE_SIP_DISCONNECTING = "sip_disconnecting"
local STATE_CC_IDLE = "cc_idle"
local STATE_CC_DIALING = "cc_dialing"
local STATE_CC_DISCONNECTING = "cc_disconnecting"

local g_sip_state = STATE_SIP_IDLE
local g_cc_state = STATE_CC_IDLE
local g_call_direction = nil
local g_call_start_time = nil

local function logi(...)
    log.info("bridge", ...)
end

local function on_both_connected()
    if not g_call_start_time then
        g_call_start_time = os.time()
    end
end

local function reset_call()
    if cc and cc.bridgeTone then cc.bridgeTone(false) end
    g_call_direction = nil
    g_call_start_time = nil
end

local function hangup_cc_and_reset()
    if g_cc_state ~= STATE_CC_IDLE and g_cc_state ~= STATE_CC_DISCONNECTING then
        logi("同步挂断 CC")
        g_cc_state = STATE_CC_DISCONNECTING
        sys.publish("CC_HANGUP_REQ")
    end
    reset_call()
end

local function hangup_sip_and_reset()
    if g_sip_state ~= STATE_SIP_IDLE and g_sip_state ~= STATE_SIP_DISCONNECTING then
        logi("同步挂断 SIP")
        g_sip_state = STATE_SIP_DISCONNECTING
        sys.publish("SIP_HANGUP_REQ")
    end
    reset_call()
end

-- ==================== SIP 事件处理 ====================

local function on_sip_incoming(from, uri, to)
    logi("SIP 来电", from, uri, to)
    if g_sip_state ~= STATE_SIP_IDLE or g_cc_state ~= STATE_CC_IDLE then
        log.warn("bridge", "桥接忙，拒绝新的 SIP 来电", g_sip_state, g_cc_state)
        sys.publish("SIP_HANGUP_REQ")
        return
    end
    g_sip_state = "sip_incoming"
    g_call_direction = "outgoing"
    if config.auto_answer_sip then
        logi("启动 SIP 183 早期媒体")
        sys.publish("SIP_PROGRESS_REQ")
    end
end

local function on_sip_progressing()
    if g_call_direction ~= "outgoing" or g_sip_state ~= "sip_incoming" then return end
    g_sip_state = "sip_progressing"
    if g_cc_state == STATE_CC_IDLE then
        logi("早期媒体已建立，拨打手机", config.target_phone_number)
        g_cc_state = STATE_CC_DIALING
        sys.publish("CC_DIAL_REQ", config.target_phone_number)
    else
        log.warn("bridge", "CC 非空闲，终止当前 SIP 来电", g_cc_state)
        g_sip_state = STATE_SIP_DISCONNECTING
        sys.publish("SIP_HANGUP_REQ")
    end
end

local function on_sip_connected()
    logi("SIP 已连接")
    g_sip_state = "sip_connected"
    if g_call_direction == "incoming" and g_cc_state == "cc_ringing" then
        logi("呼入场景：接听手机")
        sys.publish("CC_ACCEPT_REQ")
    end
    if g_cc_state == "cc_connected" then
        on_both_connected()
    end
end

local function on_sip_disconnected(reason)
    logi("SIP 断开", reason or "")
    g_sip_state = STATE_SIP_IDLE
    hangup_cc_and_reset()
end

local function on_sip_failed(reason)
    log.warn("bridge", "SIP 失败", reason or "")
    g_sip_state = STATE_SIP_IDLE
    hangup_cc_and_reset()
end

sys.subscribe("SIP_INCOMING", on_sip_incoming)
sys.subscribe("SIP_PROGRESSING", on_sip_progressing)
sys.subscribe("SIP_CONNECTED", on_sip_connected)
sys.subscribe("SIP_DISCONNECTED", on_sip_disconnected)
sys.subscribe("SIP_FAILED", on_sip_failed)

-- ==================== CC 事件处理 ====================

local function on_cc_incoming(number)
    logi("CC 来电", number)
    g_cc_state = "cc_ringing"
    if g_sip_state ~= STATE_SIP_IDLE then
        log.warn("bridge", "SIP 非空闲，拒绝新的 CC 来电", g_sip_state)
        g_cc_state = STATE_CC_DISCONNECTING
        sys.publish("CC_HANGUP_REQ")
        return
    end
    if config.auto_handle_mobile_incoming then
        g_call_direction = "incoming"
        g_sip_state = "sip_dialing"
        logi("呼入场景：拨打 SIP", config.remote_sip_uri)
        sys.publish("SIP_DIAL_REQ", config.remote_sip_uri)
    end
end

local function on_cc_connected()
    logi("CC 已连接")
    g_cc_state = "cc_connected"
    if g_call_direction == "outgoing" and g_sip_state == "sip_progressing" then
        logi("CC 已接通，现在接听 SIP")
        sys.publish("SIP_ACCEPT_REQ")
    end
    if g_sip_state == "sip_connected" then
        on_both_connected()
    end
end

local function on_cc_disconnected(reason)
    logi("CC 断开", reason or "")
    g_cc_state = STATE_CC_IDLE
    hangup_sip_and_reset()
end

local function on_cc_failed(reason)
    log.warn("bridge", "CC 失败", reason or "")
    hangup_sip_and_reset()
end

local function on_cc_dial_rejected(reason)
    log.warn("bridge", "CC 拒绝拨号", reason or "")
    hangup_sip_and_reset()
end

local function on_cc_state_changed(new_state)
    g_cc_state = new_state
end

sys.subscribe("CC_INCOMING", on_cc_incoming)
sys.subscribe("CC_CONNECTED", on_cc_connected)
sys.subscribe("CC_DISCONNECTED", on_cc_disconnected)
sys.subscribe("CC_FAILED", on_cc_failed)
sys.subscribe("CC_DIAL_REJECTED", on_cc_dial_rejected)
sys.subscribe("CC_STATE_CHANGED", on_cc_state_changed)

-- ==================== 公共 API ====================

function bridge.get_state()
    return {
        sip_state = g_sip_state,
        cc_state = g_cc_state,
        in_call = (g_sip_state == "sip_connected" and g_cc_state == "cc_connected"),
        call_direction = g_call_direction,
        call_duration = g_call_start_time and (os.time() - g_call_start_time) or 0,
    }
end

logi("SIP/CC 桥接协调器已加载")

return bridge
