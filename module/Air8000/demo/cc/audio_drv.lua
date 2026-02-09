--[[
@module  audio_drv
@summary 音频设备管理模块，负责音频设备的初始化和控制（仅使用exaudio扩展库）
@version 2.0
@date    2025.10.23
@author  陈媛媛
@usage
本模块提供以下功能：
1、定义所有硬件引脚常量
2、使用exaudio扩展库初始化音频设备
]]

-- 引入exaudio库
local exaudio = require("exaudio")

-- exaudio配置参数
local audio_configs = {
    model = "es8311",         -- dac类型: "es8311"
    i2c_id = 0,               -- i2c_id: 可填入0，1 并使用pins 工具配置对应的管脚
    pa_ctrl = 162,            -- 音频放大器电源控制管脚
    dac_ctrl = 164,           -- 音频编解码芯片电源控制管脚
        
    -- 【注意：固件版本＜V2026，这里单位为1ms，这里填600，否则可能第一个字播不出来】
    dac_delay = 6,            -- DAC启动前冗余时间(单位100ms)
    
    pa_delay = 100,           -- DAC启动后延迟打开PA的时间(单位1ms)
    dac_time_delay = 100,     -- 播放完毕后PA与DAC关闭间隔(单位1ms)
    bits_per_sample = 16,     -- 采样位深
    pa_on_level = 1           -- PA打开电平 1:高 0:低
}


exaudio.vol(70)            -- 喇叭音量
exaudio.mic_vol(65)        -- 麦克风音量

-- 初始化音频设备
local function initAudioDevice()

    -- 使用exaudio.setup统一配置音频设备
    log.info("audio_drv", "使用exaudio.setup初始化音频设备")
    if exaudio.setup(audio_configs) then
        log.info("audio_drv", "exaudio.setup初始化成功")
    else
        log.error("audio_drv", "exaudio.setup初始化失败")
        return false
    end
    
    -- log.info("audio_drv", "Audio device initialized using exaudio only")
    return true
end

-- 获取音频通道ID（保留用于兼容性）
local function getMultimediaId()
    return 0  -- 返回默认值0
end

-- 导出接口
return {
    initAudioDevice = initAudioDevice,
    getMultimediaId = getMultimediaId
}