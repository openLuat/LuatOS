--[[
@module  voice
@summary 导航 TTS 语音播报（内置 DAC + HT6873，走 exaudio；无音频固件静默降级）
@version 1.0
@date    2026.10.29
@usage
参考 factory/app/common/tts_app.lua 与 jq_ev_charge_monitor/code/ev_voice.lua：
旧 audio 库在 DAC 模式 PA/DAC 通路配不好会不出声，统一走固件扩展库 exaudio。

  voice.init()              -- 在协程里初始化（幂等），失败也不影响地图
  voice.say("前方右转")      -- 入队串行播报，任意上下文可调，不阻塞
  voice.stop()               -- 清空并打断
  voice.available() -> bool

同一句在 cooldown 时间内去重，避免 500ms 定时帧重复播报。
PC 模拟器 / 无 exaudio 固件下降级为日志打印，业务照常。
]]

local M = {}

-- Air8607 10 寸板：内置 DAC，HT6873 功放，GPIO73 高电平使能
local HW = {
    model = "dac",
    pa_ctrl = 73,
    pa_on_level = 1,
    dac_delay = 6,
    pa_delay = 10,
}

local exaudio = nil
local ready = false
local busy = false
local pa_pin = HW.pa_ctrl
local pa_on = false  -- 当前功放使能状态

-- 打开 / 关闭 HT6873 功放使能脚。
-- 不播报时必须关 PA：否则功放一直放大 DAC 空闲底噪，喇叭会"格叽格叽"响。
local function pa_enable(en)
    if pa_on == en then return end
    pcall(gpio.setup, pa_pin, en and 1 or 0)
    pcall(gpio.set, pa_pin, en and 1 or 0)
    pa_on = en
end

local volume = 30
local queue = {}
local MAX_QUEUE = 6
local last_text = nil
local last_tick = 0
local COOLDOWN = 4000   -- 同一句最小播报间隔（毫秒）

local function has_fn(t, key)
    if t == nil then return false end
    local ok, f = pcall(function() return t[key] end)
    return ok and type(f) == "function"
end

--[[初始化音频通路（须在协程中调用，内部会 sys.wait）
@param cfg table 可选硬件/音量配置
@return boolean 是否具备真实发声能力
]]
function M.init(cfg)
    cfg = cfg or {}
    volume = cfg.volume or volume
    if ready then
        return true
    end
    local ok, lib = pcall(require, "exaudio")
    if not ok or lib == nil then
        log.warn("voice", "exaudio 不可用，播报降级为日志", lib)
        return false
    end
    if not has_fn(lib, "setup") or not has_fn(lib, "play_start") then
        log.warn("voice", "exaudio 缺少 setup/play_start，降级为日志")
        return false
    end
    local sp = {
        model = cfg.model or HW.model,
        pa_ctrl = cfg.pa_ctrl or HW.pa_ctrl,
        pa_on_level = HW.pa_on_level,
        dac_delay = HW.dac_delay,
        pa_delay = HW.pa_delay,
    }
    local ok2, ret = pcall(lib.setup, sp)
    if not ok2 or not ret then
        log.warn("voice", "exaudio.setup 失败，降级为日志", ok2, ret)
        return false
    end
    pcall(lib.vol, volume)
    sys.wait(120) -- DAC / PA 上电稳定
    exaudio = lib
    ready = true
    pa_enable(false) -- 初始化后先关功放，避免空闲底噪
    log.info("voice", "TTS 通路就绪，音量", volume)
    return true
end

function M.available()
    return ready
end

function M.set_volume(v)
    volume = math.max(0, math.min(100, v or volume))
    if ready then pcall(exaudio.vol, volume) end
end

local function play_blocking(text)
    if not ready then
        log.info("voice", "[模拟播报]", text)
        sys.wait(600)
        return true
    end
    pa_enable(true) -- 起播前打开功放
    sys.wait(40)
    local done = false
    local ok = exaudio.play_start({
        type = 1, -- 1 = TTS 文本
        content = text,
        cbfnc = function(event)
            if event == exaudio.PLAY_DONE then done = true end
        end,
    })
    if not ok then
        log.warn("voice", "play_start 失败:", text)
        return false
    end
    -- 超时兜底：约 0.2s/字，限制 3~15 秒
    local limit = #text * 200
    if limit < 3000 then limit = 3000 end
    if limit > 15000 then limit = 15000 end
    local t = 0
    while not done and t < limit do
        sys.wait(100)
        t = t + 100
    end
    if not done then
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
        pcall(play_blocking, item)
        busy = false
        if #queue > 0 then
            -- 还有下一句：功放保持开启，继续播（避免反复通断的爆音）
            pump()
        else
            -- 队列播空：等 250ms 确认没有新句子进来，再关功放消底噪
            sys.wait(250)
            if #queue == 0 then
                pcall(exaudio.play_stop, { type = 1 })
                pa_enable(false)
            else
                pump()
            end
        end
    end)
end

--[[加入播报队列（不阻塞，带去重防抖）
@param text string
@param force boolean 强制播报（跳过去重）
]]
function M.say(text, force)
    if type(text) ~= "string" or text == "" then return end
    local now = mcu and mcu.ticks and mcu.ticks() or 0
    if not force and text == last_text and (now - last_tick) < COOLDOWN then
        return
    end
    last_text, last_tick = text, now
    if #queue >= MAX_QUEUE then
        return
    end
    queue[#queue + 1] = text
    log.info("voice", "播报", text)
    pump()
end

function M.stop()
    queue = {}
    if ready then pcall(exaudio.play_stop, { type = 1 }) end
    pa_enable(false) -- 停止播报立即关功放
end

return M
