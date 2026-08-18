--[[
@module  bridge
@summary SIP 与 CC 的桥接协调器
@version 1.1
@date    2026.07.23
@usage
通过发布/订阅消息协调 SIP 和 CC。SIP 呼入时先发送 183 + SDP，
在早期媒体阶段拨打手机，手机音频就绪后再发送 200 OK。
]]

local config = require "config"

local exaudio
local ok, result = pcall(require, "exaudio")
if ok then exaudio = result end

local bridge = {}

local STATE_SIP_IDLE = "sip_idle"
local STATE_SIP_INCOMING = "sip_incoming"
local STATE_SIP_PROGRESSING = "sip_progressing"
local STATE_SIP_ANSWERING = "sip_answering"
local STATE_SIP_DIALING = "sip_dialing"
local STATE_SIP_CONNECTED = "sip_connected"
local STATE_SIP_DISCONNECTING = "sip_disconnecting"

local STATE_CC_IDLE = "cc_idle"
local STATE_CC_DIALING = "cc_dialing"
local STATE_CC_RINGING = "cc_ringing"
local STATE_CC_CONNECTED = "cc_connected"
local STATE_CC_DISCONNECTING = "cc_disconnecting"

local g_sip_state = STATE_SIP_IDLE
local g_cc_state = STATE_CC_IDLE
local g_call_direction = nil
local g_call_start_time = nil
local g_local_audio = config.local_audio_default
local g_outgoing_early_timeout_timer = nil
local g_pending_early_fail_timer = nil

local set_cc_bridge_tone
local g_lua_bridge_tone_timer = nil
local g_lua_bridge_tone_frame_index = 0
local g_lua_bridge_tone_frames = nil
local g_lua_bridge_tone_silence = nil

local function logi(...)
    log.info("bridge", ...)
end

local function logw(...)
    log.warn("bridge", ...)
end

local function sip_is_early_stage()
    return g_sip_state == STATE_SIP_INCOMING or
        g_sip_state == STATE_SIP_PROGRESSING
end

local function stop_outgoing_early_timeout()
    if g_outgoing_early_timeout_timer then
        sys.timerStop(g_outgoing_early_timeout_timer)
        g_outgoing_early_timeout_timer = nil
        logi("停止 SIP->CC 早期拨号超时保护")
    end
end

local function stop_pending_early_fail()
    if g_pending_early_fail_timer then
        sys.timerStop(g_pending_early_fail_timer)
        g_pending_early_fail_timer = nil
        logi("停止 SIP->CC 失败播报保护")
    end
end

local function apply_audio()
    if not exaudio then return end
    if g_local_audio then
        if exaudio.vol then exaudio.vol(35) end
        if exaudio.mic_vol then exaudio.mic_vol(96) end
        logi("本地音频已打开")
    else
        if exaudio.vol then exaudio.vol(0) end
        if exaudio.mic_vol then exaudio.mic_vol(0) end
        logi("本地音频已关闭")
    end
end

local function on_both_connected()
    if not g_call_start_time then
        g_call_start_time = os.time()
    end
    apply_audio()
end

local function reset_call()
    stop_outgoing_early_timeout()
    stop_pending_early_fail()
    if set_cc_bridge_tone then set_cc_bridge_tone(false) end
    g_call_direction = nil
    g_call_start_time = nil
end

local function fail_sip_early(code, reason)
    stop_pending_early_fail()
    if sip_is_early_stage() then
        logi("结束 SIP 早期媒体", code, reason)
        g_sip_state = STATE_SIP_DISCONNECTING
        sys.publish("SIP_FAIL_REQ", code or 480, reason or "Temporarily Unavailable")
    elseif g_sip_state ~= STATE_SIP_IDLE then
        g_sip_state = STATE_SIP_DISCONNECTING
        sys.publish("SIP_HANGUP_REQ")
    end
end

local function schedule_sip_early_fail(code, reason)
    local delay = tonumber(config.outgoing_failure_prompt_grace) or 0
    if g_call_direction ~= "outgoing" or not sip_is_early_stage() or delay <= 0 then
        fail_sip_early(code, reason)
        return
    end
    -- 同一次失败可能连续上报 MAKE_CALL_FAILED、DISCONNECTED 等事件。
    -- 已经进入播报保护窗口时不重启定时器，也不能提前挂断 SIP。
    if g_pending_early_fail_timer then
        logi("SIP->CC 失败播报窗口已启动，忽略重复失败事件")
        return
    end
    logi("延迟结束 SIP 早期媒体，保留 CC 失败播报", delay, "秒")
    g_pending_early_fail_timer = sys.timerStart(function()
        g_pending_early_fail_timer = nil
        if sip_is_early_stage() then
            fail_sip_early(code, reason)
        end
    end, delay * 1000)
end

local function pcm16le(sample)
    sample = math.max(-32768, math.min(32767, math.floor(sample)))
    if sample < 0 then sample = sample + 65536 end
    return string.char(sample % 256, math.floor(sample / 256) % 256)
end

local function build_lua_bridge_tone_frames()
    if g_lua_bridge_tone_frames then return end
    local frames = {}
    local two_pi = 2 * math.pi
    for frame = 1, 50 do
        local chunks = {}
        for i = 0, 159 do
            local n = (frame - 1) * 160 + i
            local sample = 2600 * math.sin(two_pi * 440 * n / 8000) +
                2600 * math.sin(two_pi * 480 * n / 8000)
            chunks[#chunks + 1] = pcm16le(sample)
        end
        frames[frame] = table.concat(chunks)
    end
    g_lua_bridge_tone_frames = frames
    g_lua_bridge_tone_silence = string.rep("\0", 320)
end

local function stop_lua_bridge_tone()
    if g_lua_bridge_tone_timer then
        sys.timerStop(g_lua_bridge_tone_timer)
        g_lua_bridge_tone_timer = nil
        logi("Lua bridge tone stop")
    end
    g_lua_bridge_tone_frame_index = 0
end

local function lua_bridge_tone_tick()
    if not voip or not voip.pcmIn or not voip.isRunning or
        not voip.isRunning() or not sip_is_early_stage() then
        stop_lua_bridge_tone()
        return
    end
    local cycle = g_lua_bridge_tone_frame_index % 150
    local frame = cycle < 50 and
        g_lua_bridge_tone_frames[cycle + 1] or g_lua_bridge_tone_silence
    voip.pcmIn(frame)
    g_lua_bridge_tone_frame_index = g_lua_bridge_tone_frame_index + 1
end

local function start_lua_bridge_tone()
    if not voip or not voip.pcmIn then return false end
    if g_lua_bridge_tone_timer then return true end
    build_lua_bridge_tone_frames()
    g_lua_bridge_tone_frame_index = 0
    g_lua_bridge_tone_timer = sys.timerLoopStart(lua_bridge_tone_tick, 20)
    logi("Lua bridge tone start", g_lua_bridge_tone_timer)
    return g_lua_bridge_tone_timer ~= nil
end

set_cc_bridge_tone = function(enabled)
    if not enabled then
        stop_lua_bridge_tone()
        if voip and voip.bridgeTone then voip.bridgeTone(false) end
        if cc and cc.bridgeTone then cc.bridgeTone(false) end
        return
    end

    if voip and voip.bridgeTone and voip.bridgeTone(true) then
        stop_lua_bridge_tone()
        return
    end
    if voip and voip.isRunning and not voip.isRunning() then
        return
    end
    if cc and cc.bridgeTone and cc.bridgeTone(true) then return end
    start_lua_bridge_tone()
end

local function outgoing_early_timeout_cb()
    g_outgoing_early_timeout_timer = nil
    if g_call_direction ~= "outgoing" or not sip_is_early_stage() or
        g_cc_state ~= STATE_CC_DIALING then
        return
    end
    logw("SIP->CC 早期拨号超时，主动释放")
    set_cc_bridge_tone(false)
    g_cc_state = STATE_CC_DISCONNECTING
    sys.publish("CC_HANGUP_REQ")
    fail_sip_early(480, "Temporarily Unavailable")
    g_call_start_time = nil
    g_call_direction = nil
end

local function start_outgoing_early_timeout()
    stop_outgoing_early_timeout()
    local timeout = tonumber(config.outgoing_early_timeout) or 0
    if timeout <= 0 then return end
    g_outgoing_early_timeout_timer =
        sys.timerStart(outgoing_early_timeout_cb, timeout * 1000)
    logi("启动 SIP->CC 早期拨号超时保护", timeout, "秒")
end

local function answer_sip_after_mobile_ready()
    if g_call_direction == "outgoing" and sip_is_early_stage() then
        logi("手机侧音频已就绪，发送 SIP 200 OK")
        stop_outgoing_early_timeout()
        stop_pending_early_fail()
        set_cc_bridge_tone(false)
        g_sip_state = STATE_SIP_ANSWERING
        sys.publish("SIP_ACCEPT_REQ")
    end
end

-- ==================== SIP 事件处理 ====================

local function on_sip_incoming(from, uri, to)
    logi("SIP 来电", from, uri, to)
    if g_sip_state ~= STATE_SIP_IDLE or g_cc_state ~= STATE_CC_IDLE then
        logw("桥接忙，拒绝 SIP 来电", g_sip_state, g_cc_state)
        sys.publish("SIP_FAIL_REQ", 486, "Busy Here")
        return
    end

    g_sip_state = STATE_SIP_INCOMING
    g_call_direction = "outgoing"
    if config.auto_answer_sip then
        if config.early_media then
            logi("发送 183 早期媒体响应")
            sys.publish("SIP_PROGRESS_REQ")
        else
            g_sip_state = STATE_SIP_ANSWERING
            sys.publish("SIP_ACCEPT_REQ")
        end
    end
end

local function on_sip_progressing()
    if g_call_direction ~= "outgoing" or
        g_sip_state ~= STATE_SIP_INCOMING then return end
    g_sip_state = STATE_SIP_PROGRESSING
    g_cc_state = STATE_CC_DIALING
    logi("早期媒体已建立，拨打手机", config.target_phone_number)
    sys.publish("CC_DIAL_REQ", config.target_phone_number)
    start_outgoing_early_timeout()
end

local function on_sip_connected()
    logi("SIP 已连接")
    g_sip_state = STATE_SIP_CONNECTED
    if g_call_direction == "outgoing" and g_cc_state == STATE_CC_IDLE then
        -- 未启用早期媒体时保持旧流程。
        g_cc_state = STATE_CC_DIALING
        sys.publish("CC_DIAL_REQ", config.target_phone_number)
    elseif g_call_direction == "incoming" and g_cc_state == STATE_CC_RINGING then
        sys.publish("CC_ACCEPT_REQ")
    end
    if g_cc_state == STATE_CC_CONNECTED then on_both_connected() end
end

local function on_sip_disconnected(reason)
    logi("SIP 断开", reason or "")
    g_sip_state = STATE_SIP_IDLE
    if g_cc_state ~= STATE_CC_IDLE then
        g_cc_state = STATE_CC_DISCONNECTING
        sys.publish("CC_HANGUP_REQ")
    end
    reset_call()
end

local function on_sip_failed(reason)
    logw("SIP 失败", reason or "")
    g_sip_state = STATE_SIP_IDLE
    if g_cc_state ~= STATE_CC_IDLE then
        g_cc_state = STATE_CC_DISCONNECTING
        sys.publish("CC_HANGUP_REQ")
    end
    reset_call()
end

local function on_sip_voip_started()
    if g_call_direction == "outgoing" and sip_is_early_stage() and
        g_cc_state == STATE_CC_DIALING then
        set_cc_bridge_tone(true)
    elseif g_sip_state == STATE_SIP_IDLE or
        g_sip_state == STATE_SIP_DISCONNECTING then
        if voip and voip.stop then voip.stop() end
    end
end

local function on_sip_media_stop(reason)
    stop_outgoing_early_timeout()
    if reason == "peer_cancel" or reason == "peer_hangup" or
        reason == "local_hangup" then
        stop_pending_early_fail()
    end
end

sys.subscribe("SIP_INCOMING", on_sip_incoming)
sys.subscribe("SIP_PROGRESSING", on_sip_progressing)
sys.subscribe("SIP_CONNECTED", on_sip_connected)
sys.subscribe("SIP_DISCONNECTED", on_sip_disconnected)
sys.subscribe("SIP_FAILED", on_sip_failed)
sys.subscribe("SIP_MEDIA_STOP", on_sip_media_stop)
sys.subscribe("SIP_VOIP_STARTED", on_sip_voip_started)
sys.subscribe("SIP_VOIP_STOPPED", function() set_cc_bridge_tone(false) end)

-- ==================== CC 事件处理 ====================

local function on_cc_incoming(number)
    logi("CC 来电", number)
    if g_cc_state ~= STATE_CC_IDLE then return end
    g_cc_state = STATE_CC_RINGING
    if config.auto_handle_mobile_incoming then
        g_call_direction = "incoming"
        g_sip_state = STATE_SIP_DIALING
        sys.publish("SIP_DIAL_REQ", config.remote_sip_uri,number)
    elseif config.auto_answer_mobile_incoming then
        g_call_direction = nil
        sys.publish("CC_ACCEPT_REQ")
    end
end

local function on_cc_connected()
    logi("CC 已连接")
    stop_outgoing_early_timeout()
    stop_pending_early_fail()
    g_cc_state = STATE_CC_CONNECTED
    answer_sip_after_mobile_ready()
    if g_sip_state == STATE_SIP_CONNECTED then on_both_connected() end
end

local function on_cc_disconnected(reason)
    logi("CC 断开", reason or "")
    stop_outgoing_early_timeout()
    g_cc_state = STATE_CC_IDLE
    set_cc_bridge_tone(false)
    if g_pending_early_fail_timer then
        logi("CC 重复断开事件，继续保留失败播报窗口")
        return
    end
    if g_call_direction == "outgoing" and sip_is_early_stage() then
        schedule_sip_early_fail(480, "Temporarily Unavailable")
        g_call_start_time = nil
    elseif g_sip_state ~= STATE_SIP_IDLE then
        g_sip_state = STATE_SIP_DISCONNECTING
        sys.publish("SIP_HANGUP_REQ")
        reset_call()
    else
        reset_call()
    end
end

local function on_cc_failed(reason)
    logw("CC 失败", reason or "")
    stop_outgoing_early_timeout()
    g_cc_state = STATE_CC_IDLE
    set_cc_bridge_tone(false)
    if g_pending_early_fail_timer then
        logi("CC 重复失败事件，继续保留失败播报窗口")
        return
    end
    if g_call_direction == "outgoing" and sip_is_early_stage() then
        schedule_sip_early_fail(480, "Temporarily Unavailable")
        g_call_start_time = nil
    elseif g_sip_state ~= STATE_SIP_IDLE then
        g_sip_state = STATE_SIP_DISCONNECTING
        sys.publish("SIP_HANGUP_REQ")
        reset_call()
    else
        reset_call()
    end
end

local function on_cc_make_call_ok()
    if g_call_direction == "outgoing" and sip_is_early_stage() then
        start_outgoing_early_timeout()
        set_cc_bridge_tone(true)
    end
end

local function on_cc_hangup_call_done()
    g_cc_state = STATE_CC_IDLE
    set_cc_bridge_tone(false)
    if g_pending_early_fail_timer then
        logi("CC 挂断完成，继续等待失败播报窗口结束")
        return
    end
    stop_outgoing_early_timeout()
end

local function on_cc_play(value)
    logi("CC 播放事件", value)
    -- 与参考实现一致：PLAY 0 不代表真实 early media 已结束。
end

sys.subscribe("CC_INCOMING", on_cc_incoming)
sys.subscribe("CC_CONNECTED", on_cc_connected)
sys.subscribe("CC_AUDIO_START", on_cc_connected)
sys.subscribe("CC_DISCONNECTED", on_cc_disconnected)
sys.subscribe("CC_FAILED", on_cc_failed)
sys.subscribe("CC_MAKE_CALL_OK", on_cc_make_call_ok)
sys.subscribe("CC_HANGUP_CALL_DONE", on_cc_hangup_call_done)
sys.subscribe("CC_SPEECH_START", function() logi("CC 语音开始") end)
sys.subscribe("CC_PLAY", on_cc_play)
sys.subscribe("CC_DIAL_TONE", function() logi("CC 拨号音") end)

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
        in_call = (g_sip_state == STATE_SIP_CONNECTED and
            g_cc_state == STATE_CC_CONNECTED),
        call_direction = g_call_direction,
        call_duration = g_call_start_time and
            (os.time() - g_call_start_time) or 0,
        local_audio = g_local_audio,
        early_media = sip_is_early_stage(),
    }
end

logi("SIP/CC 桥接协调器已加载（支持早期媒体）")

return bridge
