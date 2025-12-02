--[[
@module  audio_drv
@summary 音频设备管理模块，负责音频设备的初始化和控制
@version 2.0
@date    2025.11.26
@author  陈媛媛
@usage
本模块提供以下功能：
1、定义所有硬件引脚常量
2、使用exaudio扩展库初始化音频设备
]]


local audio_drv = {}
local exaudio = require "exaudio"
local _initialized = false

-- 音频初始化参数
local audio_setup_param = {
    model = "es8311",       -- 音频编解码类型,可填入"es8311","es8211"
    i2c_id = 0,             -- i2c_id,可填入0，1 并使用pins工具配置对应的管脚
    pa_ctrl = gpio.AUDIOPA_EN,          -- 音频放大器电源控制管脚
    dac_ctrl = 20,         -- 音频编解码芯片电源控制管脚    
}

-- 初始化音频设备
function audio_drv.init()
    if _initialized then
        log.info("audio_drv", "音频设备已经初始化")
        return true
    end
    
    log.info("audio_drv", "开始初始化音频设备")
    
    local audio_init_ok = exaudio.setup(audio_setup_param)
    
    if audio_init_ok then
        _initialized = true
        log.info("audio_drv", "音频设备初始化成功")
        return true
    else
        log.error("audio_drv", "音频设备初始化失败")
        return false
    end
end

return audio_drv