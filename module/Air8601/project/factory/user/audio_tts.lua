--[[
@module  audio_tts
@summary 语音播报模块（TTS，Air8601：内置 DAC + LM4871 功放，PA=GPIO74 低电平打开）
@version 1.0
@date    2026.09.05
@usage
    local audio_tts = require "audio_tts"
    audio_tts.play("欢迎使用合宙智能寄存柜")
    或
    audio_tts.play("刷脸取件")

注意：
1. Air8601 只有 DAC，无 ES8311，只能播放（TTS），不能录音。
2. 音频功放 PA 使能脚为 GPIO74，低电平打开（AUDIOPA_EN 低有效）。
3. 需要固件版本 >= V1024 才可播放音频（本项目 LuatOS-SoC V1027，满足）。
4. 本模块用 exaudio(扩展库)，model="dac" 走 Air1601 内置 DAC。
5. 播放是异步的，play() 不阻塞；同一时间只播一句，新请求会打断旧的。
]]

local exaudio = require "exaudio"

local M = {}

-- 音频初始化参数（Air8601）
local setup_param = {
    model = "dac",        -- 音频编解码类型：Air1601 用内置 DAC
    pa_ctrl = 74,         -- 音频功放电源控制管脚（AUDIOPA_EN = GPIO74）
    pa_on_level = 0,      -- PA 打开电平：低电平打开（低有效）
    pa_delay = 10,        -- PA 延时(ms)
}

local inited = false

-- 播放完成回调
local function play_end()
    log.info("audio_tts", "播放完成")
end

-- 初始化音频（首次调用自动 setup）
local function ensure_init()
    if inited then return true end
    if exaudio.setup(setup_param) then
        exaudio.vol(80)     -- 音量 0-100
        inited = true
    else
        log.error("audio_tts", "exaudio.setup 失败，TTS 不可用")
    end
    return inited
end

-- 播放一段 TTS 文本
-- @param text 要播报的文字（如"欢迎使用合宙人脸识别智能寄存柜"）
function M.play(text)
    if not text or text == "" then return false end
    if not ensure_init() then return false end
    log.info("audio_tts", "播放:", text)
    return exaudio.play_start({
        type = 1,           -- 1 = 播放 TTS
        content = text,
        cbfnc = play_end,
    })
end

-- 停止播放
function M.stop()
    if inited then
        exaudio.play_stop({type = 1})
    end
end

return M
