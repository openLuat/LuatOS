--[[
@module  audio_drv
@summary 音频驱动模块
@version 1.0
@date    2026.04.15
@usage
本模块负责音频设备的初始化和配置
]]

local exaudio = require "exaudio"

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
    pa_on_level = 1
}

function audio_drv.init()
    if rtos and rtos.bsp and rtos.bsp() and rtos.bsp():find("PC") then
        log.info("audio_drv", "PC 模拟器，跳过音频初始化")
        return true
    end

    -- gpio.setup(147, 1)     -- 8000开发板，打开I2C总线，扫描音频芯片
    
    --初始化音频设备
    if exaudio.setup(audio_configs) then
        log.info("audio_drv", "exaudio.setup初始化成功")
        return true
    else
        log.error("audio_drv", "exaudio.setup初始化失败")
        return false
    end
end

return audio_drv
