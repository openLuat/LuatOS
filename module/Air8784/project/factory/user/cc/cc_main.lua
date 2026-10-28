--[[
@module  cc_main
@summary VoLTE 通话模块
@version 2.1
@date    2026.09.29
@author  蒋骞
@usage
本文件为 VoLTE 通话模块，核心业务逻辑为：
1、封装 cc 库的初始化、事件处理、拨号、接听和挂断，通过发布/订阅消息与 cc_bridge.lua 交互；
2、cc.init(0) 使用多媒体设备 id 0(Air1103 走 UART，不占用多媒体设备)；
3、订阅 CC_IND 事件，把 READY/INCOMINGCALL/CONNECTED/SPEECH_START/PLAY/DISCONNECTED/
   HANGUP_CALL_DONE 等底层状态转成 CC_READY/CC_INCOMING/CC_CONNECTED/CC_DISCONNECTED/
   CC_FAILED/CC_MAKE_CALL_OK/CC_MEDIA_START 消息，交给 bridge 协调两侧通话；
4、SPEECH_START 时若存在 cc_audio.enable_cc_codec 则调用它恢复外置 Codec 输出通路
   (Air780EHV+ES8311 场景；本工程 Air1103 无该接口，自动跳过)；
5、挂断完成回到空闲时补发 CC_DISCONNECTED，避免 bridge 误判 CC 忙而拒绝后续 SIP 来电；

本文件对外提供 cc_main.init()/dial()/accept()/hangup()/get_state()/is_ready() 接口，
直接在其他功能模块中require "cc_main"就可以加载运行；
]]
local task_voice = require "task_voice"

local cc_main = {}

-- 音频驱动（可选）：用于 SPEECH_START 时恢复外置编解码器输出通路
local cc_audio
do
    local aok, aresult = pcall(require, "cc_audio")
    if aok then
        cc_audio = aresult
    end
end

local STATE_IDLE = "cc_idle"
local STATE_DIALING = "cc_dialing"
local STATE_RINGING = "cc_ringing"
local STATE_CONNECTED = "cc_connected"
local STATE_DISCONNECTING = "cc_disconnecting"

local g_state = STATE_IDLE
local g_ready = false
local generation, release_timer, release_started = 0, nil, nil
local last_error
local was_connected=false

local function logi(...)
    log.info("cc_main", ...)
end

local function set_state(new_state)
    if new_state~=STATE_IDLE then task_voice.cancel("bridge call state") end
    if g_state ~= new_state then
        logi("状态切换", g_state, "->", new_state)
        g_state = new_state
        sys.publish("CC_STATE_CHANGED",new_state)
        local voice = require "call_voice"
        voice.bridge_state("cc",new_state)
    end
end

-- ==================== 请求处理 ====================
local function finish_release(reason)
    if g_state==STATE_IDLE then return end
    if release_timer then sys.timerStop(release_timer);release_timer=nil end
    if cc and cc.bridgeTone then pcall(cc.bridgeTone,false) end
    logi("CC_RELEASED",generation,reason,"elapsed_ms",release_started and (os.time()-release_started)*1000 or 0)
    release_started=nil;last_error=nil
    set_state(STATE_IDLE)
    sys.publish("CC_DISCONNECTED",reason)
end
local function request_release()
    if g_state==STATE_IDLE or g_state==STATE_DISCONNECTING or g_state=="cc_release_error" then return end
    set_state(STATE_DISCONNECTING)
    release_started=os.time()
    local token=generation
    release_timer=sys.timerStart(function()
        if token~=generation or g_state~=STATE_DISCONNECTING then return end
        release_timer=nil;last_error="release_timeout"
        set_state("cc_release_error")
        log.error("cc_main","CC_RELEASE_TIMEOUT",generation)
        sys.publish("CC_RELEASE_FAILED",last_error)
    end,10000)
    local ok,result,detail=false,nil,"hangup_unavailable"
    if cc and cc.hangUp then ok,result,detail=pcall(cc.hangUp,0) end
    logi("CC_RELEASE_REQUEST",generation,ok,result,detail)
    -- nil is a valid return from hangUp; it is not a completion signal.
end
local function dial_failed(reason,terminal)
    last_error=reason
    sys.publish("CC_FAILED",reason)
    if terminal then
        request_release()
        finish_release(reason)
    else request_release() end
end

local function on_cc_dial_req(number)
    if g_state ~= STATE_IDLE then
        log.warn("cc_main", "CC 忙，无法拨号", g_state)
        sys.publish("CC_FAILED", "cc_busy")
        return
    end
    generation=generation+1;last_error=nil;was_connected=false
    set_state(STATE_DIALING)
    logi("执行拨号", number)
    if not cc or not cc.dial then
        log.error("cc_main", "cc.dial 不可用")
        sys.publish("CC_FAILED", "cc_not_ready")
        finish_release("not_submitted")
        return
    end
    local called,ok,reason = pcall(cc.dial,0,number)
    if not called or not ok then
        log.error("cc_main", "CC_DIAL_FAILED",generation,called,ok,reason)
        if called then
            sys.publish("CC_FAILED", "dial_failed")
            finish_release("not_submitted")
        else dial_failed("dial_exception",false) end
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
        sys.publish("CC_FAILED", "accept_failed")
        request_release()
    end
end

-- Idle/duplicate release requests are idempotent, including old force callers.
local function on_cc_hangup_req(force)
    request_release()
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
        generation=generation+1;last_error=nil;was_connected=false
        set_state(STATE_RINGING)
        logi("手机来电", number)
        sys.publish("CC_INCOMING", number)

    elseif status == "CONNECTED" or status == "AUDIO_START" then
        if g_state==STATE_IDLE or g_state==STATE_DISCONNECTING or g_state=="cc_release_error" then
            log.warn("cc_main","late connected event",g_state);return
        end
        was_connected=true
        if g_state ~= STATE_CONNECTED then
            set_state(STATE_CONNECTED)
            logi("CC 通话已建立")
            sys.publish("CC_CONNECTED")
        end

    elseif status == "DISCONNECTED" then
        finish_release("disconnected")

    elseif status == "MAKE_CALL_OK" then
        logi("CC 拨号请求已发送")
        sys.publish("CC_MAKE_CALL_OK")

    elseif status == "MAKE_CALL_FAILED" then
        log.error("cc_main", "CC 拨号失败")
        if not was_connected and (g_state==STATE_DIALING or g_state==STATE_DISCONNECTING) then dial_failed("make_call_failed",true) end

    elseif status == "ANSWER_CALL_DONE" then
        logi("CC 接听完成")

    elseif status == "HANGUP_CALL_DONE" then
        logi("CC 挂断完成")
        -- 通知 bridge：CC 已回到空闲。若不发布，bridge 的 g_cc_state
        -- 会停留在 cc_connected，导致后续 SIP 来电被误判为“CC 忙”而回 486。
        finish_release("hangup_done")

    elseif status == "SPEECH_START" then
        logi("CC 语音开始")
        -- audio_v2 接管 I2S 后，需恢复外置 ES8311 的 DAC/PA；
        -- 仅是硬件输出通路恢复，不会启用本地音频或改变桥接开关。
        if cc_audio and cc_audio.enable_cc_codec then
            cc_audio.enable_cc_codec(16000)
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
function cc_main.release_error() return last_error end

return cc_main
