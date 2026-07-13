--[[
@module  audio_drv
@summary 音频驱动模块
@version 1.0
@date    2026.04.15
@usage
本模块负责音频设备的初始化和配置
]]

local exaudio
local ok, result = pcall(function() return require("exaudio") end)
if ok then
    exaudio = result
end

local audio_drv = {}

local audio_configs = {
    model = "es8311",
    i2c_id = 0,
    pa_ctrl = 162,
    dac_ctrl = 164,
    dac_delay = 6,
    pa_delay = 100,
    dac_time_delay = 100,
    bits_per_sample = 16,
    pa_on_level = 1,
    -- Air8000 默认旧框架，但 CC 通话需要 audio_v2
    audio_mode = "new",
}

function audio_drv.init()
    if rtos and rtos.bsp and rtos.bsp() and rtos.bsp():find("PC") then
        log.info("audio_drv", "PC 模拟器，跳过音频初始化")
        return true
    end

    -- 某些Air8000开发板需要打开GPIO147使能I2C总线电源
    -- 如果初始化成功但无声音，尝试取消下面注释
    -- gpio.setup(147, 1)
    
    --初始化音频设备
    local setup_ok, setup_ret = pcall(exaudio.setup, audio_configs)
    if setup_ok and setup_ret then
        log.info("audio_drv", "exaudio.setup初始化成功, 音频框架:", exaudio.get_audio_mode and exaudio.get_audio_mode() or "unknown")
        
        -- 检查TTS是否可用
        if audio and audio.tts then
            log.info("audio_drv", "旧框架TTS可用 (audio.tts存在)")
        end
        if audio_v2 and audio_v2.tts then
            log.info("audio_drv", "新框架TTS可用 (audio_v2.tts存在)")
        end
        
        if exaudio.vol then
            exaudio.vol(70)  -- 音量调到70
            log.info("audio_drv", "已设置播放音量为: 70")
        end
        -- 设置麦克风音量
        if exaudio.mic_vol then
            exaudio.mic_vol(96)
            log.info("audio_drv", "已设置麦克风音量为: 96")
        end
        return true
    else
        log.error("audio_drv", "exaudio.setup初始化失败:", setup_ret)
        return false
    end
end

return audio_drv
