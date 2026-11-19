local cfg = require "cc_local_config"
local audio = require "cc_local_audio"
local settings = require "aircloud_settings"
local voice = require "call_voice"
local task_voice = require "task_voice"
local exaudio = require "exaudio"
local M = {}
local initialized, state = false, "INIT"
local deadline, media_timer, release_timer
local action_seq = 0
local function set_state(value)
    state = value
    log.info("cc_local", "STATE", state)
    sys.publish("CC_LOCAL_STATE", state)
end
local function cancel_timers()
    if deadline then sys.timerStop(deadline); deadline = nil end
    if media_timer then sys.timerStop(media_timer); media_timer = nil end
    if release_timer then sys.timerStop(release_timer); release_timer = nil end
end
local function finish()
    action_seq = action_seq + 1
    voice.cancel()
    cancel_timers()
    audio.stop()
    set_state(initialized and "IDLE" or "INIT")
end
function M.hangup()
    if not initialized or state == "IDLE" or state == "RELEASING" then return end
    if state == "PREPARING" then
        finish() -- 尚未提交拨号，只取消播报；失效的拨号协程不能继续呼叫。
        return
    end
    cancel_timers()
    audio.stop()
    set_state("RELEASING")
    release_timer = sys.timerStart(function()
        release_timer = nil
        set_state("RELEASE_ERROR") -- 不假装已释放，允许再次请求挂断。
        log.error("cc_local", "挂断确认超时，请再次长按 UP")
    end, 10000)
    cc.hangUp(0)
end
local function call_timeout()
    deadline = nil
    log.warn("cc_local", "呼叫等待超时")
    M.hangup()
end
function M.dial(number)
    if settings.pending then return false, "模式切换等待重启" end
    if not initialized or state ~= "IDLE" then return false, "CC 忙或初始化未完成" end
    if type(number) ~= "string" or #number < 1 or #number > 32 or not number:match("^%+?%d+$") then
        log.warn("cc_local", "请在 cc_local_config.number 填写手机号码")
        return false, "号码无效"
    end
    action_seq = action_seq + 1
    local token = action_seq
    set_state("PREPARING")
    local function valid()
        return token == action_seq and state == "PREPARING" and not settings.pending
    end
    exaudio.vol(math.ceil(cfg.volume * 100 / 31))
    voice.speak("正在拨号", valid)
    -- 超时/取消仍须等原生 TTS 释放，不能用 CC PCM 覆盖播放流。
    local released = voice.prepare()
    if not valid() then
        if token == action_seq and state == "PREPARING" then finish() end
        return false, "拨号已取消"
    end
    if not released then finish(); return false, "播报音频未释放" end
    set_state("DIALING")
    deadline = sys.timerStart(call_timeout, cfg.dial_timeout_ms)
    if not cc.dial(0, number) then finish(); return false, "拨号失败" end
    return true
end
function M.accept()
    if settings.pending or not initialized or state ~= "INCOMING" then return false end
    set_state("ANSWERING")
    action_seq = action_seq + 1
    local token = action_seq
    if not voice.prepare() then M.hangup(); return false end
    if token ~= action_seq or state ~= "ANSWERING" then return false end
    if deadline then sys.timerStop(deadline) end
    deadline = sys.timerStart(call_timeout, 15000)
    if not cc.accept(0) then M.hangup(); return false end
    return true
end
function M.get_state() return state end
function M.safe_idle()
    return (state=="IDLE" or state=="ERROR") and not media_timer and not release_timer
        and not voice.is_busy() and not task_voice.is_playing()
end
function M.voice_ready()
    -- task_voice 会在播放期间调用 can_play，不能把它自身的占用视为抢占。
    return initialized and state=="IDLE" and not media_timer and not release_timer and not voice.is_busy()
end
function M.restore_volume() exaudio.vol(math.ceil(cfg.volume * 100 / 31)) end
function M.target_number()
    if settings.saved then return (settings.saved.sos_cc_numbers or {})[1] end
    return cfg.number -- 仅供手动 BOOT_MODE=cc 调试。
end

local function start_media()
    if state ~= "CONNECTED" and state ~= "DIALING" and state ~= "ANSWERING" then return end
    if media_timer or not initialized or state == "IDLE" or state == "RELEASING" or state == "RELEASE_ERROR" then return end
    local attempts = 0
    local function attempt()
        media_timer = nil
        if state == "IDLE" or state == "RELEASING" or state == "RELEASE_ERROR" then return end
        local ok, err
        if voice.is_busy() or task_voice.is_playing() then
            err = "等待播报音频释放"
        else
            ok, err = audio.start()
        end
        if ok then return end
        attempts = attempts + 1
        if attempts >= 30 then
            log.error("cc_local", "音频启动失败", err)
            M.hangup()
        else media_timer = sys.timerStart(attempt, 100) end
    end
    media_timer = sys.timerStart(attempt, 100)
end
sys.subscribe("CC_IND", function(event)
    log.info("cc_local", "CC_IND", event)
    if not initialized then return end
    if event == "INCOMINGCALL" then
        if state == "IDLE" or state == "PREPARING" then
            action_seq = action_seq + 1
            voice.cancel()
            task_voice.cancel("incoming call")
            set_state("INCOMING")
            log.info("cc_local", "来电：按 SOS 接听，长按 UP 拒接", cc.lastNum())
            deadline = sys.timerStart(call_timeout, cfg.dial_timeout_ms)
        end
    elseif event == "CONNECTED" or event == "SPEECH_START" then
        if state == "DIALING" or state == "ANSWERING" or state == "INCOMING" then
            if deadline then sys.timerStop(deadline); deadline = nil end
            set_state("CONNECTED")
            start_media()
        end
    elseif event == "AUDIO_START" then
        -- 音频事件可能先于 CONNECTED；不据此宣称电话已接通。
        start_media()
    elseif event == "DISCONNECTED" or event == "HANGUP_CALL_DONE" or event == "MAKE_CALL_FAILED" then
        finish()
    end
end)
sys.subscribe("CC_LOCAL_AUDIO_ERROR", function(reason)
    log.error("cc_local", reason)
    M.hangup()
end)
-- 所有外部请求在 sys 任务中执行，GPIO 回调只发布消息。
sys.subscribe("CC_LOCAL_DIAL_REQ", function(number) sys.taskInit(M.dial, number) end)
sys.subscribe("CC_LOCAL_ACCEPT_REQ", function() sys.taskInit(M.accept) end)
sys.subscribe("CC_LOCAL_HANGUP_REQ", function() sys.taskInit(M.hangup) end)
sys.subscribe("CC_LOCAL_PRIMARY", function()
    sys.taskInit(function()
        if state == "INCOMING" then M.accept() else M.dial(M.target_number()) end
    end)
end)
sys.taskInit(function()
    local called, ok, err = pcall(audio.init)
    if not called or not ok then
        set_state("ERROR")
        log.error("cc_local", "初始化失败", called and err or ok)
        return
    end
    initialized = true
    set_state("IDLE")
    gpio.setup(20, function() sys.publish("CC_LOCAL_PRIMARY") end, gpio.PULLUP, gpio.FALLING)
    gpio.debounce(20, 150, 1)
    local long_timer
    gpio.setup(21, function()
        if long_timer then sys.timerStop(long_timer); long_timer = nil end
        if gpio.get(21) == 0 then
            long_timer = sys.timerStart(function()
                long_timer = nil
                if gpio.get(21) == 0 then sys.publish("CC_LOCAL_HANGUP_REQ") end
            end, 1000)
        end
    end, gpio.PULLUP, gpio.BOTH)
    gpio.debounce(21, 150, 1)
    log.info("cc_local", "独立蜂窝电话就绪：SOS 拨号/接听，长按 UP 挂断/拒接")
    while true do
        sys.wait(5000)
        if state == "CONNECTED" then
            local tx, rx = audio.stats()
            log.info("cc_local", "PCM bytes TX/RX", tx, rx)
        end
    end
end)
return M
