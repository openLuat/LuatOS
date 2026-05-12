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

-- local audio_configs = {
--     model = "es8311",
--     i2c_id = 0,
--     pa_ctrl = 162,
--     dac_ctrl = 164,
--     dac_delay = 6,
--     pa_delay = 100,
--     dac_time_delay = 100,
--     bits_per_sample = 16,
--     pa_on_level = 1
-- }

local audio_configs ={
    model= "es8311",          -- 音频编解码类型,可填入"es8311","es8211"
    i2c_id = 0,          -- i2c_id,可填入0，1 并使用pins 工具配置对应的管脚
    
    -- 【注意：固件版本＜V2026，这里单位为1ms，这里填600，否则可能第一个字播不出来】
    dac_delay = set_dac_delay,            -- DAC启动前冗余时间
    
    pa_ctrl = gpio.AUDIOPA_EN,         -- 音频放大器电源控制管脚
    
    dac_ctrl = 20,        --  音频编解码芯片电源控制管脚,780ehv 默认使用20
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
        if exaudio.vol then
            exaudio.vol(65)  -- 设置通话音量为65
            log.info("audio_drv", "已设置通话音量为: 65")
        end
        -- 设置麦克风音量
        if exaudio.mic_vol then
            exaudio.mic_vol(96)  -- 设置麦克风音量为96
            log.info("audio_drv", "已设置麦克风音量为: 96")
        end
        return true
    else
        log.error("audio_drv", "exaudio.setup初始化失败")
        return false
    end
end

return audio_drv
