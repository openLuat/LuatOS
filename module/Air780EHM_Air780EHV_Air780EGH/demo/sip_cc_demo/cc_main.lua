--[[
@module  cc_main
@summary VoLTE 通话模块
@version 1.0.1
@date    2026.07.17
@author  蒋骞
@usage
封装 cc 库的初始化、事件处理、拨号/接听/挂断。
通过发布/订阅消息与 bridge.lua 和 sip_main.lua 交互。
]]

local cc_main = {}

-- 音频驱动（可选）：用于 SPEECH_START 时恢复外置编解码器输出通路
local audio_drv
do
    local aok, aresult = pcall(require, "audio_drv")
    if aok then
        audio_drv = aresult
    end
end

local STATE_IDLE = "cc_idle"
local STATE_DIALING = "cc_dialing"
local STATE_RINGING = "cc_ringing"
local STATE_CONNECTED = "cc_connected"
local STATE_DISCONNECTING = "cc_disconnecting"

local g_state = STATE_IDLE
local g_ready = false

local function logi(...)
    log.info("cc_main", ...)
end

local function set_state(new_state)
    if g_state ~= new_state then
        logi("状态切换", g_state, "->", new_state)
        g_state = new_state
    end
end

-- ==================== 请求处理 ====================

local function on_cc_dial_req(number)
    if g_state ~= STATE_IDLE then
        log.warn("cc_main", "CC 忙，无法拨号", g_state)
        sys.publish("CC_FAILED", "cc_busy")
        return
    end
    set_state(STATE_DIALING)
    logi("执行拨号", number)
    if not cc or not cc.dial then
        log.error("cc_main", "cc.dial 不可用")
        set_state(STATE_IDLE)
        sys.publish("CC_FAILED", "cc_not_ready")
        return
    end
    local ok = cc.dial(0, number)
    if not ok then
        log.error("cc_main", "cc.dial 失败")
        set_state(STATE_IDLE)
        sys.publish("CC_FAILED", "dial_failed")
    end
end

local function on_cc_accept_req()
    if g_state ~= STATE_RINGING then
        log.warn("cc_main", "当前没有来电", g_state)
        return
    end
    logi("执行接听")
    if not cc or not cc.accept then
        log.error("cc_main", "cc.accept 不可用")
        return
    end
    local ok = cc.accept(0)
    if not ok then
        log.error("cc_main", "cc.accept 失败")
        set_state(STATE_IDLE)
        sys.publish("CC_FAILED", "accept_failed")
    end
end

local function on_cc_hangup_req()
    if g_state == STATE_IDLE then
        log.warn("cc_main", "CC 已空闲")
        return
    end
    set_state(STATE_DISCONNECTING)
    logi("执行挂断")
    if cc and cc.hangUp then
        cc.hangUp(0)
    end
end

sys.subscribe("CC_DIAL_REQ", on_cc_dial_req)
sys.subscribe("CC_ACCEPT_REQ", on_cc_accept_req)
sys.subscribe("CC_HANGUP_REQ", on_cc_hangup_req)

-- ==================== CC 事件处理 ====================

local function on_cc_event(status, value, extra)
    logi("事件", status, value, extra)

    if status == "READY" then
        g_ready = true
        logi("CC 系统已就绪")
        sys.publish("CC_READY")

    elseif status == "INCOMINGCALL" then
        local number = cc and cc.lastNum and cc.lastNum() or ""
        if g_state == STATE_RINGING then
            logi("重复来电，忽略", number)
            return
        end
        if g_state ~= STATE_IDLE then
            log.warn("cc_main", "CC 忙，拒绝来电", g_state)
            if cc and cc.hangUp then cc.hangUp(0) end
            return
        end
        set_state(STATE_RINGING)
        logi("手机来电", number)
        sys.publish("CC_INCOMING", number)

    elseif status == "CONNECTED" or status == "AUDIO_START" then
        if g_state ~= STATE_CONNECTED then
            set_state(STATE_CONNECTED)
            logi("CC 通话已建立")
            sys.publish("CC_CONNECTED")
        end

    elseif status == "DISCONNECTED" then
        set_state(STATE_IDLE)
        logi("CC 通话已断开")
        sys.publish("CC_DISCONNECTED")

    elseif status == "MAKE_CALL_OK" then
        logi("CC 拨号请求已发送")
        sys.publish("CC_MAKE_CALL_OK")

    elseif status == "MAKE_CALL_FAILED" then
        log.error("cc_main", "CC 拨号失败")
        set_state(STATE_IDLE)
        sys.publish("CC_FAILED", "make_call_failed")

    elseif status == "ANSWER_CALL_DONE" then
        logi("CC 接听完成")

    elseif status == "HANGUP_CALL_DONE" then
        logi("CC 挂断完成")
        set_state(STATE_IDLE)
        -- 通知 bridge：CC 已回到空闲。若不发布，bridge 的 g_cc_state
        -- 会停留在 cc_connected，导致后续 SIP 来电被误判为“CC 忙”而回 486。
        sys.publish("CC_DISCONNECTED", "hangup_done")

    elseif status == "SPEECH_START" then
        logi("CC 语音开始")
        -- audio_v2 接管 I2S 后，需恢复外置 ES8311 的 DAC/PA；
        -- 仅是硬件输出通路恢复，不会启用本地音频或改变桥接开关。
        if audio_drv and audio_drv.enable_cc_codec then
            audio_drv.enable_cc_codec(16000)
        end

    elseif status == "PLAY" then
        logi("CC 音频输出开始（早期媒体/彩铃）", value)
        -- PLAY=通话音频通道开始出声(含未接听阶段回铃/彩铃/提示音)。
        -- 通知 bridge 及时停掉本地占位回铃音，避免与 CC 真实下行在 TX FIFO 叠加。
        sys.publish("CC_MEDIA_START", value)
    end
end

-- ==================== 公共 API ====================

function cc_main.init()
    logi("CC 初始化开始")
    if cc then
        g_ready = true
        logi("CC 库已可用")
    else
        g_ready = false
        log.warn("cc_main", "CC 库未就绪，等待 READY 事件")
    end

    if g_ready and cc and cc.init then
        local ok = cc.init(0)
        if ok then
            logi("CC 初始化成功")
            sys.publish("CC_READY")
        else
            log.error("cc_main", "CC 初始化失败")
        end
    end

    sys.subscribe("CC_IND", on_cc_event)
    logi("CC 初始化完成")
    return true
end

function cc_main.dial(number)
    sys.publish("CC_DIAL_REQ", number)
end

function cc_main.accept()
    sys.publish("CC_ACCEPT_REQ")
end

function cc_main.hangup()
    sys.publish("CC_HANGUP_REQ")
end

function cc_main.get_state()
    return g_state
end

function cc_main.is_ready()
    return g_ready
end

return cc_main
