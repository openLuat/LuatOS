--[[
@module  audio_drv
@summary 音频设备管理模块，负责音频设备的初始化和控制（仅使用exaudio扩展库）
@version 2.1
@date    2026.11.06
@author  陈媛媛
@usage
1、定义板级引脚常量
2、使用exaudio扩展库初始化音频设备
]]

local exaudio = require "exaudio"

-- 8780V 板级引脚（原理图 p1：模组 19 脚 GPIO22 = PA_EN → U260 AW8733 SHDN；
-- 102 脚 GPIO20 = 模组内部 Codec 电源使能）
local I2C_ID        = 0    -- ES8311 挂 I2C0，地址 0x18
local PA_CTRL       = 22   -- 功放使能
local DAC_CTRL      = 20   -- Codec 电源使能
local CODEC_VOLTAGE = 1    -- ES8311 IO 电平：1=3.3V，0=1.8V

-- 喇叭/麦克风音量（0-100）。通话瞬间射频发射+功放推喇叭峰值可达 2A，
-- 电源带不动会表现为通话刚开始就重启，可先降到 45~55 排除电源问题。
local SPEAKER_VOL = 70
local MIC_VOL     = 65

-- dac_delay 单位随固件变化：V2026 起为 100ms，之前为 1ms（填 600 否则首字丢）
local set_dac_delay = 600
local version = rtos.version()
local num_str = version and version:match("V(%d+)")
if num_str and tonumber(num_str) >= 2026 then
    set_dac_delay = 6
end

-- 音频框架由 main.lua 按固件能力选定
local AUDIO_MODE = _G.AUDIO_MODE or "old"

local audio_configs = {
    model = "es8311",
    i2c_id = I2C_ID,
    pa_ctrl = PA_CTRL,
    dac_ctrl = DAC_CTRL,
    codec_voltage = CODEC_VOLTAGE,

    dac_delay = set_dac_delay,   -- DAC启动前冗余时间
    pa_delay = 100,              -- DAC启动后延迟打开PA(ms)
    dac_time_delay = 100,        -- 播放完毕后PA与DAC关闭间隔(ms)
    bits_per_sample = 16,
    pa_on_level = 1,             -- PA打开电平 1:高 0:低

    audio_mode = AUDIO_MODE,     -- "new" 新框架 / "old" 旧框架
}

-- 初始化音频设备
local function initAudioDevice()
    log.info("audio_drv", "初始化音频 i2c", I2C_ID, "pa_ctrl", PA_CTRL,
        "dac_ctrl", DAC_CTRL, "框架", AUDIO_MODE)

    if exaudio.setup(audio_configs) then
        exaudio.vol(SPEAKER_VOL)
        exaudio.mic_vol(MIC_VOL)
        log.info("audio_drv", "exaudio.setup初始化成功")
        return true
    end

    -- 新框架初始化失败时退回旧框架再试一次，避免整机没声音
    if AUDIO_MODE == "new" then
        log.warn("audio_drv", "新框架初始化失败，回退旧框架重试")
        audio_configs.audio_mode = "old"
        AUDIO_MODE = "old"
        if exaudio.setup(audio_configs) then
            exaudio.vol(SPEAKER_VOL)
            exaudio.mic_vol(MIC_VOL)
            log.info("audio_drv", "exaudio.setup初始化成功（旧框架）")
            return true
        end
    end

    log.error("audio_drv", "exaudio.setup初始化失败")
    return false
end

-- 获取音频通道ID（保留用于兼容性）
local function getMultimediaId()
    return 0
end

-- 导出接口
return {
    initAudioDevice = initAudioDevice,
    getMultimediaId = getMultimediaId
}
