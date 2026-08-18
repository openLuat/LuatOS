--[[
@module  bridge
@summary SIP 与 CC 的桥接协调器
@version 1.0
@date    2026.07.17
@author  蒋骞
@usage
由 sip_main.lua 自动 require 加载。
通过订阅 SIP/CC 事件，发送跨模块请求，完成自动接听、自动拨号、挂断同步和本地音频控制。
bridge 不直接引用 sip_main 或 cc_main，避免循环依赖。
]]

local config = require "config"

local exaudio
local ok, result = pcall(require, "exaudio")
if ok then exaudio = result end

local bridge = {}

local STATE_SIP_IDLE = "sip_idle"
local STATE_CC_IDLE = "cc_idle"

local g_sip_state = STATE_SIP_IDLE
local g_cc_state = STATE_CC_IDLE
local g_call_direction = nil
local g_call_start_time = nil
local g_local_audio = config.local_audio_default

local function logi(...)
    log.info("bridge", ...)
end

local function apply_audio()
    if not exaudio then return end
    if g_local_audio then
        if exaudio.vol then
            exaudio.vol(35)
            logi("本地音频已打开: 扬声器 35")
        end
        if exaudio.mic_vol then
            exaudio.mic_vol(96)
            logi("本地音频已打开: 麦克风 96")
        end
    else
        if exaudio.vol then
            exaudio.vol(0)
            logi("本地音频已关闭: 扬声器静音")
        end
        if exaudio.mic_vol then
            exaudio.mic_vol(0)
            logi("本地音频已关闭: 麦克风静音")
        end
    end
end

local function on_both_connected()
    if not g_call_start_time then
        g_call_start_time = os.time()
    end
    apply_audio()
end

local function reset_call()
    g_call_direction = nil
    g_call_start_time = nil
end

-- ==================== SIP 事件处理 ====================

local function on_sip_incoming(from, uri, to)
    logi("SIP 来电", from, uri, to)
    g_sip_state = "sip_incoming"
    g_call_direction = "outgoing"
    if config.auto_answer_sip then
        logi("自动接听 SIP")
        sys.publish("SIP_ACCEPT_REQ")
    end
end

local function on_sip_connected()
    logi("SIP 已连接")
    g_sip_state = "sip_connected"
    if g_call_direction == "outgoing" and g_cc_state == STATE_CC_IDLE then
        logi("呼出场景：拨打手机", config.target_phone_number)
        sys.publish("CC_DIAL_REQ", config.target_phone_number)
    elseif g_call_direction == "incoming" and g_cc_state == "cc_ringing" then
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
    if g_cc_state ~= STATE_CC_IDLE then
        logi("同步挂断 CC")
        sys.publish("CC_HANGUP_REQ")
    end
    reset_call()
end

local function on_sip_failed(reason)
    log.warn("bridge", "SIP 失败", reason or "")
    g_sip_state = STATE_SIP_IDLE
    if g_cc_state ~= STATE_CC_IDLE then
        logi("同步挂断 CC")
        sys.publish("CC_HANGUP_REQ")
    end
    reset_call()
end

sys.subscribe("SIP_INCOMING", on_sip_incoming)
sys.subscribe("SIP_CONNECTED", on_sip_connected)
sys.subscribe("SIP_DISCONNECTED", on_sip_disconnected)
sys.subscribe("SIP_FAILED", on_sip_failed)

-- ==================== CC 事件处理 ====================

local function on_cc_incoming(number)
    logi("CC 来电", number)
    g_cc_state = "cc_ringing"
    if config.auto_handle_mobile_incoming then
        g_call_direction = "incoming"
        logi("呼入场景：拨打 SIP", config.remote_sip_uri)
        sys.publish("SIP_DIAL_REQ", config.remote_sip_uri)
    end
end

local function on_cc_connected()
    logi("CC 已连接")
    g_cc_state = "cc_connected"
    if g_sip_state == "sip_connected" then
        on_both_connected()
    end
end

local function on_cc_disconnected(reason)
    logi("CC 断开", reason or "")
    g_cc_state = STATE_CC_IDLE
    if g_sip_state ~= STATE_SIP_IDLE then
        logi("同步挂断 SIP")
        sys.publish("SIP_HANGUP_REQ")
    end
    reset_call()
end

local function on_cc_failed(reason)
    log.warn("bridge", "CC 失败", reason or "")
    g_cc_state = STATE_CC_IDLE
    if g_sip_state ~= STATE_SIP_IDLE then
        logi("同步挂断 SIP")
        sys.publish("SIP_HANGUP_REQ")
    end
    reset_call()
end

sys.subscribe("CC_INCOMING", on_cc_incoming)
sys.subscribe("CC_CONNECTED", on_cc_connected)
sys.subscribe("CC_DISCONNECTED", on_cc_disconnected)
sys.subscribe("CC_FAILED", on_cc_failed)

-- ==================== 公共 API ====================

function bridge.set_local_audio(enabled)
    g_local_audio = enabled
    logi("设置本地音频", enabled)
    apply_audio()
end

function bridge.get_state()
    return {
        sip_state = g_sip_state,
        cc_state = g_cc_state,
        in_call = (g_sip_state == "sip_connected" and g_cc_state == "cc_connected"),
        call_direction = g_call_direction,
        call_duration = g_call_start_time and (os.time() - g_call_start_time) or 0,
        local_audio = g_local_audio,
    }
end

logi("SIP/CC 桥接协调器已加载")

return bridge
