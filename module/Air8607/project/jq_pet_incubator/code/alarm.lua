--[[
@module  alarm
@summary 报警蜂鸣（内置 DAC + HT6873 功放，GPIO73 使能）
@version 1.1
@date    2026.10.28

【重要】exaudio 是 Lua 扩展库，必须 require "exaudio"，不是固件全局变量。
        且部分固件里它是一个 userdata，不能用 type(lib)=="table" 判断，
        只能逐个方法探测（见 has_fn）。

用法：
  alarm.init()            启动时配一次音频通路
  alarm.tick(有报警)      主刷新循环每秒调用一次，内部按 repeat_ms 限频播放
  alarm.play()            立即试听一次
  alarm.set_muted(true)   静音
]]
local conf = require "conf"

local M = {}
local A = conf.audio

local lib = nil            -- exaudio 扩展库
local av2 = nil            -- 固件内置 audio_v2（C 库，回退用）
local backend = "none"     -- exaudio / audio_v2 / none
local ready = false
local muted = false
local tickn = 0
local last_play = -100
local last_req = nil

-- exaudio 可能是 userdata，只能这样安全取函数
local function has_fn(t, key)
    if t == nil then return false end
    local ok, f = pcall(function() return t[key] end)
    return ok and type(f) == "function"
end

local function load_lib()
    local ok, mod = pcall(require, "exaudio")
    if ok and mod ~= nil and has_fn(mod, "setup") then return mod end
    local g = rawget(_G, "exaudio")
    if has_fn(g, "setup") then return g end
    return nil
end

function M.init()
    av2 = rawget(_G, "audio_v2")

    -- 报警音必须随脚本一起下发，否则只能空响
    if io and io.exists and not io.exists(A.file) then
        log.error("alarm", "找不到报警音文件", A.file, "请把 alarm.wav 与脚本一起拷到 sd/luadb/")
    else
        log.info("alarm", "报警音文件就绪", A.file)
    end

    -- 1) 首选 exaudio 扩展库
    lib = load_lib()
    if lib then
        local ok, ret = pcall(lib.setup, {
            model       = A.model,          -- "dac"
            pa_ctrl     = A.pa_ctrl,        -- GPIO73 HT6873 使能
            pa_on_level = A.pa_on_level,
            dac_delay   = 6,
            pa_delay    = 10,
        })
        if ok and ret then
            pcall(lib.vol, A.vol)
            sys.wait(100)                   -- DAC / PA 上电需要一点时间
            backend, ready = "exaudio", true
            log.info("alarm", "音频通路就绪(exaudio)", "音量", A.vol)
            return
        end
        log.warn("alarm", "exaudio.setup 失败", ok, tostring(ret))
    else
        log.warn("alarm", "未找到 exaudio 扩展库，尝试直连 audio_v2")
    end

    -- 2) 回退：固件内置 audio_v2（只要板子有 DAC 通路就能出声）
    if has_fn(av2, "play") then
        if has_fn(av2, "config_pa_power_ctrl") then
            pcall(av2.config_pa_power_ctrl, true, A.pa_ctrl, A.pa_on_level, 200)
        end
        if has_fn(av2, "soft_volume") then pcall(av2.soft_volume, A.vol) end
        backend, ready = "audio_v2", true
        log.info("alarm", "音频通路就绪(audio_v2 直连)", "音量", A.vol)
        return
    end

    log.error("alarm", "无可用音频后端，报警只做界面提示")
end

function M.set_muted(b)
    muted = b and true or false
    if muted then M.stop() end
end

function M.muted() return muted end
function M.ready() return ready end
function M.backend() return backend end

function M.stop()
    if not ready then return end
    if backend == "exaudio" then
        pcall(lib.play_stop, { type = 0 })
    elseif last_req and has_fn(av2, "stop") then
        pcall(av2.stop, last_req)
        last_req = nil
    end
end

function M.play()
    if not ready then
        log.info("alarm", "音频未就绪，仅界面报警")
        return false
    end

    if backend == "exaudio" then
        pcall(lib.play_stop, { type = 0 })
        if has_fn(lib, "vol") then pcall(lib.vol, A.vol) end
        -- setup 后默认处于 SHUTDOWN，起播前唤醒一次，否则第二次起播会静默
        if has_fn(lib, "pm") and lib.RESUME ~= nil then pcall(lib.pm, lib.RESUME) end
        local ok, ret = pcall(lib.play_start, { type = 0, content = A.file, priority = 0 })
        if not ok or ret == false then
            log.warn("alarm", "play_start 失败", tostring(ok), tostring(ret))
            return false
        end
        return true
    end

    if backend == "audio_v2" then
        if last_req and has_fn(av2, "stop") then pcall(av2.stop, last_req) end
        local ok, req = pcall(av2.play, A.file)
        if not ok then
            log.warn("alarm", "audio_v2.play 失败", tostring(req))
            return false
        end
        last_req = req
        return true
    end

    return false
end

-- 每个刷新周期调用一次；内部限频，避免把下行通路打满
function M.tick(any_alarm)
    tickn = tickn + 1
    if not any_alarm or muted or not ready then return end
    local gap = math.floor(A.repeat_ms / conf.sim.interval_ms)
    if gap < 1 then gap = 1 end
    if tickn - last_play < gap then return end
    last_play = tickn
    M.play()
end

return M
