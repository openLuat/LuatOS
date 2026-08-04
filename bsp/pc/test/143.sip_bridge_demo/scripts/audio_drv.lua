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

-- audio_v2 负责 I2S DMA；外置 ES8311 的寄存器及 DAC/PA 状态仍需由 Lua 恢复。
-- 使用 pcall 保持 PC 模拟器也可加载本脚本。
local es8311
local es8311_ok, es8311_mod = pcall(function() return require("es8311") end)
if es8311_ok then
    es8311 = es8311_mod
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
    -- SIP↔CC 桥接仅支持 audio_v2；普通 CC 仍可使用 old 音频框架。
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

-- 在 audio_v2 的 CC 语音真正开始时恢复外置编解码器输出通路。
-- 这是硬件适配：不创建音频请求，也不参与桥接 PCM 数据流。
function audio_drv.enable_cc_codec(sample_rate)
    if audio_configs.audio_mode ~= "new" then
        return true
    end
    if rtos and rtos.bsp and rtos.bsp() and rtos.bsp():find("PC") then
        return true
    end
    if not es8311 then
        log.error("audio_drv", "未找到es8311驱动，无法恢复CC音频输出")
        return false
    end

    sample_rate = sample_rate or 16000
    gpio.setup(audio_configs.dac_ctrl, 1)
    gpio.setup(audio_configs.pa_ctrl, audio_configs.pa_on_level)
    es8311.init(audio_configs.i2c_id)
    es8311.set_sample_rate(audio_configs.i2c_id, sample_rate, 256)
    es8311.set_data_bits(audio_configs.i2c_id, audio_configs.bits_per_sample)
    es8311.set_format(audio_configs.i2c_id)
    es8311.resume(audio_configs.i2c_id)
    es8311.set_mute(audio_configs.i2c_id, true)  -- 先静音，避免启动时的噪音
    es8311.set_voice_vol(audio_configs.i2c_id, 70)
    es8311.set_mic_vol(audio_configs.i2c_id, 96)
    log.info("audio_drv", "audio_v2 CC codec DAC/PA resumed", sample_rate)
    return true
end

return audio_drv
