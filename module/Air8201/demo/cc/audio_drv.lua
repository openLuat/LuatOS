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

支持 Air8201G 和 Air8201H 两种硬件版本，通过 main.lua 中的 _G.HARDWARE_ENV 宏切换：
- Air8201G: pa_ctrl=25, ES8311=3.3V
- Air8201H: pa_ctrl=23, ES8311=1.8V
]]

-- 引入exaudio库
local exaudio = require "exaudio"

-- 根据硬件版本选择 pa_ctrl 和 codec_voltage
local hw = _G.HARDWARE_ENV or "H"
local pa_ctrl_pin = (hw == "G") and 25 or 23
local codec_voltage = (hw == "G") and 1 or 0   -- G=3.3V, H=1.8V
local hw_name = (hw == "G") and "Air8201G" or "Air8201H"

log.info("audio_drv", "硬件版本:", hw_name, "pa_ctrl:", pa_ctrl_pin, "codec_voltage:", codec_voltage == 0 and "1.8V" or "3.3V")

-- 根据版本号自适应设置dac_delay
local set_dac_delay = 0
local version = rtos.version()
local version_num = 0
if version then
    -- 从版本号字符串中提取数字部分
    local num_str = version:match("V(%d+)")
    if num_str then
        version_num = tonumber(num_str)
    end
end

if version_num and version_num >= 2026 then
    -- 固件版本≥V2026，dac_delay单位为100ms
    set_dac_delay = 6
else
    -- 固件版本＜V2026，dac_delay单位为1ms
    set_dac_delay = 600
end

-- exaudio配置参数
local audio_configs = {
    model = "es8311",         -- dac类型,"es8311"
    i2c_id = 0,               -- ES8311挂在I2C0上
    pa_ctrl = pa_ctrl_pin,    -- 音频放大器(PA)电源控制管脚（G=25, H=23）
    dac_ctrl = 2,             -- 音频编解码芯片(ES8311)电源控制管脚
    codec_voltage = codec_voltage,  -- ES8311 IO电压: G=3.3V(1), H=1.8V(0)
        
    -- 【注意：固件版本＜V2026，这里单位为1ms，这里填600，否则可能第一个字播不出来】
    dac_delay = set_dac_delay,            -- DAC启动前冗余时间
    
    pa_delay = 100,           -- DAC启动后延迟打开PA的时间(单位1ms)
    dac_time_delay = 100,     -- 播放完毕后PA与DAC关闭间隔(单位1ms)
    bits_per_sample = 16,     -- 采样位深
    pa_on_level = 1,           -- PA打开电平 1:高 0:低
    audio_mode = "new", --  音频框架版本选择: "auto"用默认, "new"新框架, "old"旧框架
}

-- 初始化音频设备
local function initAudioDevice()

    -- 使用exaudio.setup统一配置音频设备
    log.info("audio_drv", "使用exaudio.setup初始化音频设备")
    if exaudio.setup(audio_configs) then
        exaudio.vol(50)            -- 喇叭音量
        exaudio.mic_vol(65)        -- 麦克风音量
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
