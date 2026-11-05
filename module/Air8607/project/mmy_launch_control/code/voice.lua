--[[
@module  voice
@summary 指挥中心语音播报（TTS 三后端自动降级，PC 模拟器静音）
@version 1.0
@date    2026.11.04
@board   Air8607 + 板载 DAC + HT6873 功放（AUDIOPA_EN = GPIO73，高有效）

=== 为什么这块屏要说话 ===
倒计时是背对屏幕也能感知的信息。这里只在"任务节点"开口：
  自检开始 / 终端倒计时 / 主发动机点火 / 起飞 / 最大动压 / 一级分离 / 入轨 / 中止。
其它状态一律靠屏幕，避免展厅里没完没了地念。

=== 后端探测（不同 Air8607 固件带的东西不一样）===
  1. ex_tts   exaudio + 音频库 -> exaudio.play_start{type = 1, content = 文本}
  2. av2_tts  没有 exaudio，但固件有 audio_v2.tts -> 自己配 DAC + PA，直接调
  3. aud_tts  旧框架 audio.tts -> audio.config + setBus(DAC) + audio.tts
  4. silent   都没有（PC 模拟器就是这种）：界面照常，按钮上显示"语音 关"

两个必然踩到的坑（与 mmy_home_energy 一致）：
1、起播前必须重建通路：play_stop -> setup -> 音量 -> 唤醒；否则第二句起
   可能返回 true 却不出声，也等不到结束回调。
2、结束回调会丢，所以每句挂按字数估算的看门狗，并用播报代次 gen 拦截过期回调。
]]
local T = require "theme"

local M = {}
local A = T.audio

local st = {
    ready = false,
    mode = nil,
    enabled = true,
    busy = false,
    pending = nil,
    req_gen = 0,
    last = "",
    diag = "",
}
M.st = st

local function has_fn(t, k)
    if t == nil then return false end
    local ok, f = pcall(function() return t[k] end)
    return ok and type(f) == "function"
end

local function get_lib(name)
    local g = rawget(_G, name)
    if g then return g end
    local ok, lib = pcall(require, name)
    if not ok then return nil end
    return lib
end

local ex, av2, aud
local AUDIO_ID = 0

local function pa_set(on)
    if not (gpio and gpio.setup) then return end
    pcall(gpio.setup, A.pa_ctrl, on and A.pa_on_level or (1 - A.pa_on_level))
end

local gen = 0
local function bump_gen()
    gen = gen + 1
    return gen
end

local function finish(my_gen, why)
    if my_gen and my_gen ~= gen then return end
    if not st.busy then return end
    st.busy = false
    if why then log.warn("voice", why, st.last) end
    local p = st.pending
    st.pending = nil
    if p and st.enabled and st.ready then
        sys.taskInit(function()
            if not st.busy and st.enabled then M.say(p) end
        end)
    end
end

local function say_ms(text)
    local chars = #text / 3
    local ms = 1500 + chars * 260
    if ms < 2400 then ms = 2400 elseif ms > 12000 then ms = 12000 end
    return math.floor(ms)
end

local function arm_watchdog(my_gen, ms)
    sys.taskInit(function()
        sys.wait(ms)
        if my_gen == gen then finish(my_gen, "播报超时没收到结束回调，强制收尾") end
    end)
end

local function ex_open()
    return (pcall(function()
        local cfg = {
            model = A.model,
            pa_ctrl = A.pa_ctrl,
            pa_on_level = A.pa_on_level,
            dac_delay = A.dac_delay,
        }
        if ex.setup(cfg) == false then error("setup 返回失败") end
        if has_fn(ex, "vol") then ex.vol(A.vol) end
        if has_fn(ex, "pm") and ex.RESUME then ex.pm(ex.RESUME) end
    end))
end

local function tts_prep()
    if st.mode == "ex_tts" then
        if has_fn(ex, "play_stop") then pcall(ex.play_stop, { type = 1 }) end
        ex_open()
        sys.wait(60)
    elseif st.mode == "av2_tts" then
        if has_fn(av2, "stop") then pcall(av2.stop) end
        pa_set(true)
        if has_fn(av2, "shutdown") then pcall(av2.shutdown, false, false, false) end
    elseif st.mode == "aud_tts" then
        if has_fn(aud, "stop") then pcall(aud.stop, AUDIO_ID) end
        pa_set(true)
    end
end

local function ex_tts_start(text)
    pcall(tts_prep)
    local my = bump_gen()
    st.req_gen = my
    st.busy = true
    local ok, ret = pcall(ex.play_start, {
        type = 1,
        content = text,
        priority = A.priority,
        cbfnc = function() M.done(my) end,
    })
    if not ok or ret == false then
        st.busy = false
        return false
    end
    arm_watchdog(my, say_ms(text))
    return true
end

function M.done(my_gen)
    finish(my_gen)
end

local function av2_setup()
    if not has_fn(av2, "tts") then return false end
    local ok = pcall(function()
        if has_fn(av2, "on") then
            av2.on(function(_, event)
                if event == av2.REQUEST_END then M.done(st.req_gen) end
            end)
        end
        if has_fn(av2, "config_pa_power_ctrl") then
            av2.config_pa_power_ctrl(true, A.pa_ctrl, A.pa_on_level, 10)
        end
        if has_fn(av2, "soft_volume") then av2.soft_volume(A.vol) end
        if has_fn(av2, "shutdown") then av2.shutdown(false, false, false) end
    end)
    if ok then pa_set(true) end
    return ok
end

local function av2_tts_start(text)
    pcall(tts_prep)
    local my = bump_gen()
    st.req_gen = my
    st.busy = true
    local ok, ret = pcall(av2.tts, text, A.priority)
    if not ok or ret == false then
        st.busy = false
        return false
    end
    arm_watchdog(my, say_ms(text))
    return true
end

local function aud_setup()
    if not has_fn(aud, "tts") then return false end
    local ok = pcall(function()
        if has_fn(aud, "config") then
            aud.config(AUDIO_ID, A.pa_ctrl, A.pa_on_level, 0, 10)
        end
        if has_fn(aud, "setBus") and aud.BUS_DAC then
            aud.setBus(AUDIO_ID, aud.BUS_DAC, { dacid = 0 })
        end
        if has_fn(aud, "on") then
            local d1, d2 = aud.PLAY_DONE, aud.SPEAK_DONE
            aud.on(function(_, event)
                if (d1 and event == d1) or (d2 and event == d2) then M.done(st.req_gen) end
            end)
        end
        if has_fn(aud, "vol") then aud.vol(AUDIO_ID, A.vol) end
    end)
    if ok then pa_set(true) end
    return ok
end

local function aud_tts_start(text)
    pcall(tts_prep)
    local my = bump_gen()
    st.req_gen = my
    st.busy = true
    local ok, ret = pcall(aud.tts, AUDIO_ID, text)
    if not ok or ret == false then
        st.busy = false
        return false
    end
    arm_watchdog(my, say_ms(text))
    return true
end

local function pick_backend()
    ex = get_lib("exaudio")
    av2 = get_lib("audio_v2")
    aud = get_lib("audio")
    st.diag = string.format("ex:%d a2:%d au:%d", ex and 1 or 0, av2 and 1 or 0, aud and 1 or 0)

    if ex and has_fn(ex, "setup") and has_fn(ex, "play_start") then
        if has_fn(av2, "tts") or has_fn(aud, "tts") then
            if ex_open() then return "ex_tts" end
            log.warn("voice", "exaudio 初始化失败，尝试直连 audio_v2")
        end
    end
    if av2_setup() then return "av2_tts" end
    if aud_setup() then return "aud_tts" end
    return nil
end

--- 初始化：探测后端、配置通路，可选播一句开机语
function M.init()
    if st.ready then return true end
    st.mode = pick_backend()
    if not st.mode then
        st.ready = false
        log.warn("voice", "无可用音频后端，进入静音模式", st.diag)
        return false
    end
    st.ready = true
    log.info("voice", "语音就绪", st.mode, "音量", A.vol, st.diag)
    if A.boot then
        sys.taskInit(function()
            sys.wait(600)
            M.say(A.boot_text)
        end)
    end
    return true
end

--- 立即播报；正在播就把这句挂起（只留最后一句）
function M.say(text)
    if not st.ready or not st.enabled then return 0 end
    if type(text) ~= "string" or text == "" then return 0 end
    if st.busy then
        st.pending = text
        return 0
    end
    st.last = text
    local ok
    if st.mode == "ex_tts" then
        ok = ex_tts_start(text)
    elseif st.mode == "av2_tts" then
        ok = av2_tts_start(text)
    else
        ok = aud_tts_start(text)
    end
    if not ok then
        log.warn("voice", "起播失败", st.mode, text)
        return 0
    end
    log.info("voice", "播报", text)
    return 1
end

function M.stop()
    st.pending = nil
    st.busy = false
    bump_gen()
    local mode = st.mode
    if mode == "ex_tts" and has_fn(ex, "play_stop") then
        pcall(ex.play_stop, { type = 1 })
    elseif mode == "av2_tts" and has_fn(av2, "stop") then
        pcall(av2.stop)
    elseif mode == "aud_tts" and has_fn(aud, "stop") then
        pcall(aud.stop, AUDIO_ID)
    end
end

function M.set_enabled(on)
    st.enabled = on and true or false
    if not st.enabled then
        M.stop()
        pa_set(false)
    elseif st.ready then
        if st.mode == "ex_tts" then
            ex_open()
        elseif st.mode == "av2_tts" and has_fn(av2, "shutdown") then
            pcall(av2.shutdown, false, false, false)
        end
        pa_set(true)
    end
    log.info("voice", st.enabled and "语音开" or "语音关")
    return st.enabled
end

function M.toggle()
    return M.set_enabled(not st.enabled)
end

function M.enabled() return st.enabled end
function M.ready() return st.ready end

return M
