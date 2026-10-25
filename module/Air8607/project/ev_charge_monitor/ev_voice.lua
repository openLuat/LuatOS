--[[
@module  ev_voice
@summary 语音播报服务（离线 TTS，串行队列，缺硬件时静默降级）
@version 1.0
@date    2026.10.23

=== 为什么不用旧框架 audio.tts ===
Air8607 是「芯片内置 DAC + HT6873 功放」，factory 工程的 tts_app 已踩过坑：
旧 audio 库在 DAC 模式下 PA/DAC 通路未配置好会不出声，统一走 exaudio 才稳。
参考 module/Air8607/project/factory/app/common/tts_app.lua。

=== 队列而不是抢占 ===
10 个桩可能在同一个 tick 里陆续充满，各播各的会互相打断成碎片。
这里用单消费者队列串行播报，保证每条都完整念完；stop() 可清空并立即打断。

=== 无音频能力的板子 ===
PC 模拟器 / 无喇叭固件上 exaudio 或 audio_v2 不可用，
此时降级为日志打印，UI 与业务逻辑照常运行。
]]
local M = {}

local exaudio = nil        -- exaudio 扩展库（固件内置）
local ready = false        -- 是否具备真实发声能力
local busy = false         -- 队列消费者是否在跑
local volume = 70
local queue = {}
local MAX_QUEUE = 8
local speaking_cb = nil    -- 播报状态回调

local function notify(speaking, text)
    if speaking_cb then
        local ok, err = pcall(speaking_cb, speaking, text)
        if not ok then log.warn("ev_voice", "状态回调异常", err) end
    end
end

--[[安全取函数：exaudio 在部分固件里是 userdata，不能先 type()=="table" 判断]]
local function has_fn(t, key)
    if t == nil then return false end
    local ok, f = pcall(function() return t[key] end)
    return ok and type(f) == "function"
end

--[[初始化音频通路
@param table cfg ev_config.HW.audio
@return boolean 是否具备真实发声能力
]]
function M.init(cfg)
    cfg = cfg or {}
    volume = cfg.volume or 70
    local ok, lib = pcall(require, "exaudio")
    if not ok or lib == nil then
        log.warn("ev_voice", "exaudio 扩展库不可用，播报降级为日志输出", lib)
        return false
    end
    if not has_fn(lib, "setup") or not has_fn(lib, "play_start") then
        log.warn("ev_voice", "exaudio 缺少 setup/play_start，播报降级为日志输出")
        return false
    end
    exaudio = lib

    local sp = {
        model = cfg.model or "dac",
        pa_ctrl = cfg.pa_ctrl,
        pa_on_level = cfg.pa_on_level or 1,
        dac_delay = cfg.dac_delay,
        pa_delay = cfg.pa_delay,
    }
    local ok2, ret = pcall(exaudio.setup, sp)
    if not ok2 or not ret then
        log.warn("ev_voice", "exaudio.setup 失败，播报降级为日志输出", ok2, ret)
        exaudio = nil
        return false
    end
    pcall(exaudio.vol, volume)
    sys.wait(100)          -- DAC / PA 上电需要一点时间
    ready = true
    log.info("ev_voice", "音频通路就绪, 音量", volume)
    return true
end

function M.available()
    return ready and exaudio ~= nil
end

function M.set_volume(v)
    volume = math.max(0, math.min(100, v or 70))
    if ready then pcall(exaudio.vol, volume) end
end

--[[播报状态回调
@function cb function(speaking:boolean, text:string)
]]
function M.on_state(cb)
    speaking_cb = cb
end

-- 单条播放（阻塞当前协程直到播完或超时）
local function play_blocking(text)
    if not ready then
        log.info("ev_voice", "[模拟播报]", text)
        sys.wait(800)      -- 模拟播报耗时，方便在 PC 上观察队列
        return true
    end

    local done = false
    local ok = exaudio.play_start({
        type = 1,          -- 1 = TTS 文本
        content = text,
        cbfnc = function(event)
            if event == exaudio.PLAY_DONE then done = true end
        end,
    })
    if not ok then
        log.warn("ev_voice", "play_start 失败:", text)
        return false
    end
    notify(true, text)

    -- 超时兜底：中文字符约 0.2s/字，限制在 3~20 秒
    local limit = #text * 200
    if limit < 3000 then limit = 3000 end
    if limit > 20000 then limit = 20000 end

    local t = 0
    while not done and t < limit do
        sys.wait(100)
        t = t + 100
    end
    if not done then
        log.warn("ev_voice", "播报超时，主动停止:", text)
        pcall(exaudio.play_stop, { type = 1 })
    end
    return done
end

local function pump()
    if busy then return end
    local item = table.remove(queue, 1)
    if not item then return end
    busy = true
    sys.taskInit(function()
        local ok, err = pcall(play_blocking, item.text)
        if not ok then log.error("ev_voice", "播报异常", err) end
        busy = false
        notify(false, item.text)
        pump()
    end)
end

--[[加入播报队列（任意上下文可调，不阻塞）
@param string text 播报文本
@param string tag  来源标记（仅日志）
]]
function M.say(text, tag)
    if type(text) ~= "string" or text == "" then return end
    if #queue >= MAX_QUEUE then
        log.warn("ev_voice", "播报队列已满，丢弃:", tag, text)
        return
    end
    queue[#queue + 1] = { text = text, tag = tag }
    log.info("ev_voice", "排队播报", tag or "", text)
    pump()
end

--[[立即停止并清空队列]]
function M.stop()
    queue = {}
    if ready then pcall(exaudio.play_stop, { type = 1 }) end
    notify(false, nil)
end

--[[是否有播报在进行或排队]]
function M.busy()
    return busy or #queue > 0
end

return M
