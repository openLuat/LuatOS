--[[
@module  ectts
@summary TTS 文字转语音播报模块
@version 1.0
@date    2026.09.18
@author  CodeBuddy
@usage
本模块封装合宙 exaudio 库的 TTS 播报功能，供整个项目共享使用。

## 硬件配置（Air8602 智能寄存柜）
- 音频 PA 使能脚：AUDIOPA_EN = GPIO73，低电平使能
- 音频输出：使用 Air8602 内置 DAC

## 对外接口
- ectts.init()                  -- 初始化音频硬件（幂等，多次调用安全）
- ectts.say(text)               -- 异步排队播报一段 TTS，立即返回，不阻塞调用方
- ectts.stop()                  -- 停止当前播放并清空队列
- ectts.set_volume(0~100)       -- 设置播放音量
- sys.publish("TTS_PLAY", text) -- 也可通过发布消息的方式播报

## 使用示例
    local ectts = require "ectts"
    ectts.init()
    ectts.say("欢迎使用合宙智能寄存柜")
    ectts.say("取件")
]]

local M = {}

local exaudio = require("exaudio")

-- 音频初始化参数（参照 demo/audio/Air1602/play_tts.lua）
-- Air8602 项目音频 PA: AUDIOPA_EN = GPIO73，低电平打开
local audio_setup_param = {
    model       = "dac",   -- Air8602 使用内置 DAC 输出
    pa_ctrl     = 73,      -- PA 使能脚 GPIO73
    pa_on_level = 0,       -- 低电平使能
    dac_delay   = 6,       -- DAC 启动冗余时间，单位 100ms
}

-- 是否已完成 exaudio.setup
local audio_inited = false
-- 队列：等待播放的 TTS 文本
local play_queue = {}
-- 是否正在播放（任务内使用）
local playing = false
-- 当前音量
local volume = 60

-- 初始化音频硬件（幂等）
function M.init()
    if audio_inited then
        return true
    end
    local ok = exaudio.setup(audio_setup_param)
    if ok then
        exaudio.vol(volume)
        audio_inited = true
        log.info("ectts", "TTS 音频初始化成功，PA=GPIO73 低电平使能")
    else
        log.warn("ectts", "TTS 音频初始化失败")
    end
    return ok
end

-- 设置音量 0~100
function M.set_volume(v)
    if type(v) ~= "number" then return end
    if v < 0 then v = 0 end
    if v > 100 then v = 100 end
    volume = v
    if audio_inited then
        exaudio.vol(volume)
    end
end

-- 异步排队播报一段 TTS，立即返回，不会阻塞调用方
-- 如果传入 nil 或空串则忽略
function M.say(text)
    if not text or text == "" then return end
    if type(text) ~= "string" then
        text = tostring(text)
    end
    table.insert(play_queue, text)
end

-- 停止播放并清空队列
function M.stop()
    play_queue = {}
    if audio_inited then
        exaudio.play_stop({type = 1})
    end
end

-- TTS 播放任务：循环从队列取数据播放
local function tts_task()
    -- 等系统其它初始化完成再初始化音频
    sys.wait(500)
    M.init()

    while true do
        if #play_queue > 0 then
            -- 如果正在播放则等待
            if playing then
                sys.wait(100)
            else
                local text = table.remove(play_queue, 1)
                playing = true

                -- 启动播放，失败时自动重试（最多 3 次，TTS 引擎需要网络/预热）
                local ok = false
                local retry = 0
                while not ok and retry < 3 do
                    ok = exaudio.play_start({
                        type    = 1,
                        content = text,
                        cbfnc   = function(event)
                            if event == exaudio.PLAY_DONE then
                                log.info("ectts", "TTS 播放完成", text)
                            end
                        end,
                    })
                    if not ok then
                        retry = retry + 1
                        log.warn("ectts", "TTS 启动播放失败", text, "重试", retry)
                        -- 递增等待时间，给 audio_v2 框架恢复时间
                        sys.wait(500 * retry)
                        -- 播放失败时主动恢复音频硬件（应对网络刚连上或硬件低功耗场景）
                        if audio_inited then
                            pcall(function() exaudio.pm(exaudio.RESUME) end)
                        end
                    end
                end

                if not ok then
                    log.error("ectts", "TTS 多次重试仍失败，丢弃本段", text)
                    playing = false
                else
                    -- 等待本段播放完毕
                    while not exaudio.is_end() do
                        sys.wait(100)
                    end
                    playing = false
                end
            end
        else
            sys.wait(100)
        end
    end
end

-- 启动 TTS 后台播放任务（幂等）
local task_started = false
local function ensure_task()
    if task_started then return end
    task_started = true
    sys.taskInitEx(tts_task, "task_tts")
end

-- 模块被 require 时立即启动后台任务
ensure_task()

-- 订阅消息方式触发播放：sys.publish("TTS_PLAY", "取件")
sys.subscribe("TTS_PLAY", function(text)
    M.say(text)
end)

return M