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

-- Air1602 V1.2：ES8311 / I2S2 麦克风 + 内置 DAC。
local AUDIO_PROFILE = "air1602_v12"

-- local audio_configs ={
--     model = "dac",            -- 音频编解码类型: "dac" 表示使用内置DAC
    
--     pa_ctrl = 27,             -- 音频放大器电源控制管脚
--     pa_on_level = 1,          -- PA打开电平
--     pa_delay = 10,            -- PA延时
--     audio_mode = "new"      -- 音频模式: "new" 表示使用新的audio_v2音频模式
-- }

-- local audio_configs ={
--     model = "dac",            -- 音频编解码类型: "dac" 表示使用内置DAC
    
--     pa_ctrl = 45,             -- 音频放大器电源控制管脚
--     pa_on_level = 1,          -- PA打开电平，0=低电平使能，1=高电平使能
--     dac_delay = 6,            -- DAC启动前冗余时间，单位为100ms
--     audio_mode = "new"      -- 音频模式: "new" 表示使用新的audio_v2音频模式
-- }

local audio_configs = {
    audio_mode = "new",
    model = "es8311",         -- 音频编解码类型: "es8311" 使用ES8311编解码芯片

    -- I2C配置（ES8311通过I2C1通信）
    i2c_id = 1,               -- I2C总线编号

    -- 默认驱动切换（Air1602_V1.2开发板必须：DAC0输出 + I2S2录音）
    tx_bus_type = audio_v2.DRIVER_TYPE_DAC,   -- 发送(播放)总线类型: 内置DAC
    tx_bus_id = 0,            -- 发送总线ID
    rx_bus_type = audio_v2.DRIVER_TYPE_I2S,   -- 接收(录音)总线类型: I2S
    rx_bus_id = 2,            -- 接收总线ID: 2=I2S2

    -- 音频编解码芯片电源控制脚（Air1602_V1.2开发板ES8311_EN=GPIO43）
    -- exaudio内部在切换默认驱动成功后，会对该引脚自动执行"拉低→等待→拉高"复位脉冲重启ES8311
    dac_ctrl = 43,

    -- I2S配置
    i2s_sample = 16000,        -- I2S采样率
    bits_per_sample = 16,     -- I2S采样位深
    i2s_framebit = 16,        -- I2S通道位宽
    channels = 1,             -- 声道数: 1=单声道

    -- PA功放配置
    pa_ctrl = 73,             -- PA功放控制管脚，Air1602_V1.2开发板PA_EN=GPIO73
    pa_on_level = 0,          -- PA打开电平，0=低电平使能（Air1602_V1.2开发板低电平使能）
    pa_delay = 100,           -- PA打开延迟(ms)
}

function audio_drv.init()
    if rtos and rtos.bsp and rtos.bsp() and rtos.bsp():find("PC") then
        log.info("audio_drv", "PC 模拟器，跳过音频初始化")
        return true
    end

    if AUDIO_PROFILE ~= "air1602_v12" then
        log.error("audio_drv", "不支持的音频配置", AUDIO_PROFILE)
        return false
    end
    -- LCD 触摸芯片与 ES8311 共用 I2C1；先使能 LCD，避免未上电器件干扰总线。
    gpio.setup(57, 1, gpio.PULLUP)
    log.info("audio_drv", "音频配置", AUDIO_PROFILE)

    -- gpio.setup(147, 1)     -- 8000开发板，打开I2C总线，扫描音频芯片
    
    --初始化音频设备
    if exaudio.setup(audio_configs) then
        log.info("audio_drv", "exaudio.setup初始化成功")
        if exaudio.vol then
            exaudio.vol(20)
            log.info("audio_drv", "已设置通话音量为: 20")
        end
        -- 设置麦克风音量
        if exaudio.mic_vol then
            exaudio.mic_vol(100)
            log.info("audio_drv", "已设置麦克风音量为: 100")
        end
        return true
    else
        log.error("audio_drv", "exaudio.setup初始化失败")
        return false
    end
end

return audio_drv
