--[[
@module  bridge
@summary SIP 与 CC 的桥接协调器
@version 1.0.2
@date    2026.07.20
@author  蒋骞
@usage
由 sip_main.lua 自动 require 加载。
通过订阅 SIP/CC 事件，发送跨模块请求，完成自动接听、自动拨号、挂断同步和本地音频控制。
bridge 不直接引用 sip_main 或 cc_main，避免循环依赖。

健壮性（对齐参考 sip_bridge_agent.lua）：
- CC 忙/未就绪时发布 SIP_FAIL_REQ(486/480) 结束 SIP 早期媒体，避免 SIP 分支悬挂。
- SIP->CC 呼出早期媒体拨号超时保护(outgoing_early_timeout)。
- CC 未接通失败时延迟 SIP 失败，保留运营商失败播报(outgoing_failure_prompt_grace)。
- 早期媒体占位回铃音(cc.bridgeTone -> voip.bridgeTone -> Lua pcmIn 兜底)。
- 手机来电且不转 SIP 时，依据 auto_answer_mobile_incoming 自动接听或保持振铃。
- SIP MESSAGE 备用控制通道。
- VOIP_STARTED/VOIP_STOPPED：voip 就绪后重启早期媒体回铃音，避免 CC_MAKE_CALL_OK 先到时遗漏。
- CC_MEDIA_START(PLAY)：CC 真实下行媒体开始时及时停净占位回铃音，避免与 16k 下行在 TX FIFO 叠加造成音质变差。
]]

local config = require "config"

local exaudio
local ok, result = pcall(require, "exaudio")
if ok then exaudio = result end

local bridge = {}

-- 状态常量
local STATE_SIP_IDLE = "sip_idle"
local STATE_SIP_INCOMING = "sip_incoming"
local STATE_SIP_PROGRESSING = "sip_progressing"
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
local g_cc_ready = false
local g_outgoing_early_timeout_timer = nil
local g_pending_early_fail_timer = nil
local g_cc_media_started = false

local function logi(...)
    log.info("bridge", ...)
end
local function logw(...)
    log.warn("bridge", ...)
end
local function loge(...)
    log.error("bridge", ...)
end

-- 早期媒体阶段判断
local function sip_is_early_stage()
    return g_sip_state == STATE_SIP_INCOMING or g_sip_state == STATE_SIP_PROGRESSING
end

-- ==================== 音频 ====================

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
    g_cc_media_started = false
end

-- ==================== 早期媒体回铃音（前向声明） ====================

local set_cc_bridge_tone

-- ==================== 定时器 / 失败宽限 ====================

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

local function fail_sip_early(code, reason)
    stop_pending_early_fail()
    if sip_is_early_stage() then
        logi("结束 SIP 早期媒体阶段:", code, reason)
        -- 由 sip_main 执行 exsip.fail(code, reason)
        sys.publish("SIP_FAIL_REQ", code or 480, reason or "Temporarily Unavailable")
        g_sip_state = STATE_SIP_IDLE
    else
        -- 非早期：直接挂断 SIP
        logi("同步挂断 SIP 通话")
        sys.publish("SIP_HANGUP_REQ")
        g_sip_state = STATE_SIP_IDLE
    end
end

local function schedule_sip_early_fail(code, reason)
    local delay = tonumber(config.outgoing_failure_prompt_grace) or 0
    if g_call_direction ~= "outgoing" or not sip_is_early_stage() then
        fail_sip_early(code, reason)
        return
    end
    if delay <= 0 then
        fail_sip_early(code, reason)
        return
    end
    stop_pending_early_fail()
    logi("延迟结束 SIP 早期媒体，保留 CC 失败播报:", delay, "秒", code, reason)
    g_pending_early_fail_timer = sys.timerStart(function()
        g_pending_early_fail_timer = nil
        if sip_is_early_stage() then
            fail_sip_early(code, reason)
        end
    end, delay * 1000)
end

-- ==================== CC 就绪 / 可拨手机 ====================

local function can_start_mobile_leg_from_sip()
    if not g_cc_ready then
        loge("CC 未就绪，无法拨打手机")
        return false, 480, "Temporarily Unavailable"
    end
    if g_cc_state ~= STATE_CC_IDLE then
        logw("CC 忙，无法拨打手机:", g_cc_state)
        return false, 486, "Busy Here"
    end
    return true
end

-- ==================== 早期拨号超时 ====================

local function outgoing_early_timeout_cb()
    g_outgoing_early_timeout_timer = nil
    if g_call_direction ~= "outgoing" or not sip_is_early_stage() or g_cc_state ~= STATE_CC_DIALING then
        return
    end
    logw("SIP->CC 早期拨号超时，未收到 CC 接通/失败/断开事件，主动释放")
    set_cc_bridge_tone(false)
    sys.publish("CC_HANGUP_REQ")
    g_cc_state = STATE_CC_IDLE
    fail_sip_early(480, "Temporarily Unavailable")
    reset_call()
end

local function start_outgoing_early_timeout()
    stop_outgoing_early_timeout()
    local timeout = tonumber(config.outgoing_early_timeout) or 0
    if timeout <= 0 then return end
    g_outgoing_early_timeout_timer = sys.timerStart(outgoing_early_timeout_cb, timeout * 1000)
    logi("启动 SIP->CC 早期拨号超时保护:", timeout, "秒")
end

-- ==================== 早期媒体占位回铃音（Lua 兜底） ====================

local g_lua_bridge_tone_timer = nil
local g_lua_bridge_tone_frame_index = 0
local g_lua_bridge_tone_frames = nil
local g_lua_bridge_tone_silence = nil

local function pcm16le(sample)
    sample = math.floor(sample)
    if sample < -32768 then sample = -32768
    elseif sample > 32767 then sample = 32767
    end
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
            local sample = 2600 * math.sin(two_pi * 440 * n / 8000) + 2600 * math.sin(two_pi * 480 * n / 8000)
            chunks[#chunks + 1] = pcm16le(sample)
        end
        frames[frame] = table.concat(chunks)
    end
    g_lua_bridge_tone_frames = frames
    g_lua_bridge_tone_silence = string.rep("\0", 320)
end

local function lua_bridge_tone_tick()
    if not voip or not voip.pcmIn or not voip.isRunning or not voip.isRunning() or not sip_is_early_stage() then
        set_cc_bridge_tone(false)
        return
    end
    build_lua_bridge_tone_frames()
    local cycle = g_lua_bridge_tone_frame_index % 150
    local frame = cycle < 50 and g_lua_bridge_tone_frames[cycle + 1] or g_lua_bridge_tone_silence
    local consumed = voip.pcmIn(frame)
    g_lua_bridge_tone_frame_index = g_lua_bridge_tone_frame_index + 1
    if g_lua_bridge_tone_frame_index % 50 == 1 then
        logi("Lua bridge tone pcmIn", consumed)
    end
end

local function start_lua_bridge_tone()
    if not voip or not voip.pcmIn then
        logw("voip.pcmIn 不可用，无法启动 Lua bridge tone")
        return false
    end
    if g_lua_bridge_tone_timer then return true end
    build_lua_bridge_tone_frames()
    g_lua_bridge_tone_frame_index = 0
    g_lua_bridge_tone_timer = sys.timerLoopStart(lua_bridge_tone_tick, 20)
    logi("Lua bridge tone start", g_lua_bridge_tone_timer)
    return g_lua_bridge_tone_timer ~= nil
end

local function stop_lua_bridge_tone()
    if g_lua_bridge_tone_timer then
        sys.timerStop(g_lua_bridge_tone_timer)
        g_lua_bridge_tone_timer = nil
        logi("Lua bridge tone stop")
    end
    g_lua_bridge_tone_frame_index = 0
end

set_cc_bridge_tone = function(enabled)
    if not enabled then
        stop_lua_bridge_tone()
        if voip and voip.bridgeTone then
            local ok = voip.bridgeTone(false)
            logi("VoIP bridge tone", "stop", ok)
        end
        if cc and cc.bridgeTone then
            local ok = cc.bridgeTone(false)
            logi("CC bridge tone", "stop", ok)
        end
        return
    end

    if cc and cc.bridgeTone then
        if voip and voip.bridgeTone then
            local stopped = voip.bridgeTone(false)
            logi("VoIP bridge tone", "stop before CC tone", stopped)
        end
        local ok = cc.bridgeTone(true)
        logi("CC bridge tone", "start", ok)
        if ok then
            stop_lua_bridge_tone()
            return
        end
    end

    if voip and voip.bridgeTone then
        local ok = voip.bridgeTone(true)
        logi("VoIP bridge tone", "start fallback", ok)
        if ok then
            stop_lua_bridge_tone()
            return
        end
        if voip.isRunning and not voip.isRunning() then
            return
        end
    end

    start_lua_bridge_tone()
end

-- ==================== VoIP 状态与早期媒体回铃音同步 ====================

local function on_voip_started()
    if g_call_direction == "outgoing" and sip_is_early_stage() and g_cc_state == STATE_CC_DIALING and not g_cc_media_started then
        logi("VoIP 已启动，重新启动早期媒体回铃音")
        set_cc_bridge_tone(true)
    end
end

local function on_voip_stopped()
    logi("VoIP 已停止，关闭早期媒体回铃音")
    set_cc_bridge_tone(false)
end

-- CC 真实下行媒体已开始(PLAY)：及时停净本地占位回铃音，避免与 CC 16k 下行在 TX FIFO 叠加。
local function on_cc_media_start(audio_type)
    if g_call_direction == "outgoing" and sip_is_early_stage() then
        logi("CC 下行媒体已开始，及时停掉本地占位回铃音", audio_type or "")
        g_cc_media_started = true
        set_cc_bridge_tone(false)
    end
end

sys.subscribe("VOIP_STARTED", on_voip_started)
sys.subscribe("VOIP_STOPPED", on_voip_stopped)
sys.subscribe("CC_MEDIA_START", on_cc_media_start)

-- ==================== SIP 事件处理 ====================

local function on_sip_incoming(from, uri, to)
    logi("SIP 来电", from, uri, to)
    if g_sip_state ~= STATE_SIP_IDLE then
        logw("SIP 忙，拒绝来电", g_sip_state)
        sys.publish("SIP_HANGUP_REQ")
        return
    end
    g_sip_state = STATE_SIP_INCOMING
    g_call_direction = "outgoing"
    if config.auto_answer_sip then
        local ready, code, reason = can_start_mobile_leg_from_sip()
        if not ready then
            logw("CC 不可用，结束 SIP 来电", code, reason)
            fail_sip_early(code, reason)
            g_call_direction = nil
            return
        end
        logi("启动 SIP 183 早期媒体")
        sys.publish("SIP_PROGRESS_REQ")
    end
end

local function on_sip_progressing()
    g_sip_state = STATE_SIP_PROGRESSING
    if g_call_direction == "outgoing" then
        local ready, code, reason = can_start_mobile_leg_from_sip()
        if not ready then
            logw("早期媒体阶段无法拨打手机，结束 SIP", code, reason)
            fail_sip_early(code, reason)
            g_call_direction = nil
            return
        end
        logi("早期媒体已建立，拨打手机", config.target_phone_number)
        g_cc_state = STATE_CC_DIALING
        sys.publish("CC_DIAL_REQ", config.target_phone_number)
    end
end

local function on_sip_connected()
    logi("SIP 已连接")
    g_sip_state = STATE_SIP_CONNECTED
    if g_call_direction == "incoming" and g_cc_state == STATE_CC_RINGING then
        logi("呼入场景：接听手机")
        sys.publish("CC_ACCEPT_REQ")
    end
    if g_cc_state == STATE_CC_CONNECTED then
        on_both_connected()
    end
end

local function on_sip_disconnected(reason)
    logi("SIP 断开", reason or "")
    stop_outgoing_early_timeout()
    stop_pending_early_fail()
    set_cc_bridge_tone(false)
    g_sip_state = STATE_SIP_IDLE
    if g_cc_state ~= STATE_CC_IDLE then
        if g_cc_state ~= STATE_CC_DISCONNECTING then
            logi("同步挂断 CC")
            sys.publish("CC_HANGUP_REQ")
            g_cc_state = STATE_CC_DISCONNECTING
        end
    end
    reset_call()
end

local function on_sip_failed(reason)
    log.warn("bridge", "SIP 失败", reason or "")
    stop_outgoing_early_timeout()
    stop_pending_early_fail()
    set_cc_bridge_tone(false)
    g_sip_state = STATE_SIP_IDLE
    if g_cc_state ~= STATE_CC_IDLE then
        if g_cc_state ~= STATE_CC_DISCONNECTING then
            logi("同步挂断 CC")
            sys.publish("CC_HANGUP_REQ")
            g_cc_state = STATE_CC_DISCONNECTING
        end
    end
    reset_call()
end

sys.subscribe("SIP_INCOMING", on_sip_incoming)
sys.subscribe("SIP_PROGRESSING", on_sip_progressing)
sys.subscribe("SIP_CONNECTED", on_sip_connected)
sys.subscribe("SIP_DISCONNECTED", on_sip_disconnected)
sys.subscribe("SIP_FAILED", on_sip_failed)

-- ==================== CC 事件处理 ====================

local function on_cc_ready()
    g_cc_ready = true
    logi("CC 系统已就绪")
end

local function on_cc_make_call_ok()
    logi("CC 拨号请求已发送")
    if g_call_direction == "outgoing" and sip_is_early_stage() then
        start_outgoing_early_timeout()
        set_cc_bridge_tone(true)
    end
end

local function on_cc_incoming(number)
    logi("CC 来电", number)
    if g_cc_state ~= STATE_CC_IDLE and g_cc_state ~= STATE_CC_RINGING then
        logw("CC 忙，拒绝来电", g_cc_state)
        sys.publish("CC_HANGUP_REQ")
        return
    end
    if g_cc_state == STATE_CC_RINGING then
        logi("忽略重复来电", number)
        return
    end
    g_cc_state = STATE_CC_RINGING
    if config.auto_handle_mobile_incoming then
        g_call_direction = "incoming"
        if g_sip_state == STATE_SIP_CONNECTED then
            logi("SIP 已连接，直接接听手机来电")
            g_cc_state = STATE_CC_CONNECTED
            sys.publish("CC_ACCEPT_REQ")
            on_both_connected()
        elseif g_sip_state == STATE_SIP_IDLE or g_sip_state == STATE_SIP_DISCONNECTING then
            logi("呼入场景：拨打 SIP", config.remote_sip_uri)
            sys.publish("SIP_DIAL_REQ", config.remote_sip_uri)
        else
            logw("SIP 状态不空闲，拒绝手机来电", g_sip_state)
            g_cc_state = STATE_CC_IDLE
            g_call_direction = nil
            sys.publish("CC_HANGUP_REQ")
        end
    else
        g_call_direction = nil
        if config.auto_answer_mobile_incoming then
            logi("手机来电自动 SIP 桥接已关闭，自动接听 CC 来电")
            g_cc_state = STATE_CC_CONNECTED
            sys.publish("CC_ACCEPT_REQ")
            on_both_connected()
        else
            logi("手机来电自动 SIP 桥接已关闭，保持 CC 振铃")
        end
    end
end

local function on_cc_connected(reason)
    logi("CC 已连接", reason or "")
    stop_outgoing_early_timeout()
    stop_pending_early_fail()
    set_cc_bridge_tone(false)
    g_cc_state = STATE_CC_CONNECTED
    if g_call_direction == "outgoing" and sip_is_early_stage() then
        logi("CC 已接通，现在接听 SIP")
        sys.publish("SIP_ACCEPT_REQ")
    end
    if g_sip_state == STATE_SIP_CONNECTED then
        on_both_connected()
    end
end

local function on_cc_disconnected(reason)
    logi("CC 断开", reason or "")
    stop_outgoing_early_timeout()
    g_cc_state = STATE_CC_IDLE
    set_cc_bridge_tone(false)
    if g_call_direction == "outgoing" and sip_is_early_stage() then
        schedule_sip_early_fail(480, "Temporarily Unavailable")
    elseif g_sip_state == STATE_SIP_CONNECTED or g_sip_state == STATE_SIP_DIALING or g_sip_state == STATE_SIP_DISCONNECTING then
        fail_sip_early(480, "Temporarily Unavailable")
    end
    reset_call()
end

local function on_cc_failed(reason)
    log.warn("bridge", "CC 失败", reason or "")
    stop_outgoing_early_timeout()
    g_cc_state = STATE_CC_IDLE
    set_cc_bridge_tone(false)
    if g_call_direction == "outgoing" and sip_is_early_stage() then
        schedule_sip_early_fail(480, "Temporarily Unavailable")
    elseif g_sip_state == STATE_SIP_CONNECTED or g_sip_state == STATE_SIP_DIALING or g_sip_state == STATE_SIP_DISCONNECTING then
        fail_sip_early(480, "Temporarily Unavailable")
    end
    reset_call()
end

sys.subscribe("CC_READY", on_cc_ready)
sys.subscribe("CC_MAKE_CALL_OK", on_cc_make_call_ok)
sys.subscribe("CC_INCOMING", on_cc_incoming)
sys.subscribe("CC_CONNECTED", on_cc_connected)
sys.subscribe("CC_DISCONNECTED", on_cc_disconnected)
sys.subscribe("CC_FAILED", on_cc_failed)

-- ==================== SIP MESSAGE 备用控制通道 ====================

local function handle_sip_message(body)
    body = body or ""
    logi("SIP MESSAGE 命令:", body)
    local cmd = nil
    local ok, result = pcall(function()
        local t = {}
        for k, v in body:gmatch('"([^"]+)":%s*"([^"]*)"') do t[k] = v end
        for k, v in body:gmatch('"([^"]+)":%s*(true|false)') do t[k] = (v == "true") end
        for k, v in body:gmatch('"([^"]+)":%s*(%d+)') do t[k] = tonumber(v) end
        return t
    end)
    if ok and result then cmd = result end
    if not cmd or not cmd.cmd then
        logw("无法解析 SIP MESSAGE:", body)
        return
    end
    local command = cmd.cmd
    logi("执行 SIP MESSAGE 命令:", command)
    if command == "dial" then
        local number = cmd.number or config.target_phone_number
        logi("MESSAGE 拨号:", number)
        sys.publish("SIP_DIAL_REQ", config.remote_sip_uri)
        g_call_direction = "outgoing"
        sys.publish("CC_DIAL_REQ", number)
    elseif command == "hangup" then
        logi("MESSAGE 挂断")
        fail_sip_early(486, "Busy Here")
        sys.publish("CC_HANGUP_REQ")
        reset_call()
    elseif command == "answer" then
        logi("MESSAGE 接听")
        sys.publish("SIP_ACCEPT_REQ")
        sys.publish("CC_ACCEPT_REQ")
    elseif command == "set_audio" then
        if cmd.enabled ~= nil then
            bridge.set_local_audio(cmd.enabled)
        end
    elseif command == "status" then
        logi("状态查询请求")
    else
        logw("未知命令:", command)
    end
end

local function on_sip_message(body)
    handle_sip_message(body)
end

sys.subscribe("SIP_MESSAGE", on_sip_message)

-- ==================== 公共 API ====================

function bridge.set_local_audio(enabled)
    g_local_audio = enabled
    logi("设置本地音频", enabled)
    apply_audio()
end

function bridge.set_auto_mobile_incoming(enabled)
    config.auto_handle_mobile_incoming = enabled and true or false
    logi("设置手机来电自动 SIP 桥接:", config.auto_handle_mobile_incoming)
    return true
end

function bridge.set_auto_answer_mobile_incoming(enabled)
    config.auto_answer_mobile_incoming = enabled and true or false
    logi("设置手机来电自动接听:", config.auto_answer_mobile_incoming)
    return true
end

function bridge.get_state()
    return {
        sip_state = g_sip_state,
        cc_state = g_cc_state,
        in_call = (g_sip_state == STATE_SIP_CONNECTED and g_cc_state == STATE_CC_CONNECTED),
        call_direction = g_call_direction,
        call_duration = g_call_start_time and (os.time() - g_call_start_time) or 0,
        local_audio = g_local_audio,
        auto_mobile_incoming = config.auto_handle_mobile_incoming,
        auto_answer_mobile_incoming = config.auto_answer_mobile_incoming,
    }
end

logi("SIP/CC 桥接协调器已加载")

return bridge
