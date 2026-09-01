local exaudio = require "exaudio"

local audio_drv = {}

local CFG_PARAM_ADC_DIG_GAIN = 0x424b0101
local CFG_PARAM_ADC_ANA_GAIN = 0x424b0102
local MIC_ADC_DIG_GAIN = 0x3f
local MIC_ADC_ANA_GAIN = 0x03
local DAC_PLAY_VOL = 40

local audio_config = {
    model = "dac",
    pa_ctrl = 27,
    pa_on_level = 1,
    pa_delay = 10,
    audio_mode = "new"
}

local function config_dac_vol()
    if audio and type(audio.vol) == "function" then
        local value = audio.vol(0, DAC_PLAY_VOL)
        log.info("sip_record.audio", "通话DAC音量", DAC_PLAY_VOL, value)
    end
end

function audio_drv.init()
    -- 保留原 Air8101 SIP demo 的板级使能状态；GPIO13同时是TF卡供电控制。
    gpio.setup(13, 1, gpio.PULLUP)
    gpio.setup(7, 1, gpio.PULLUP)

    if not exaudio.setup(audio_config) then
        log.error("sip_record.audio", "内置DAC初始化失败")
        return false
    end
    if exaudio.vol then
        exaudio.vol(DAC_PLAY_VOL)
    end

    local dig_ok = audio_v2.config(CFG_PARAM_ADC_DIG_GAIN, MIC_ADC_DIG_GAIN)
    local ana_ok = audio_v2.config(CFG_PARAM_ADC_ANA_GAIN, MIC_ADC_ANA_GAIN)
    log.info("sip_record.audio", "初始化成功",
        "mic_dig=" .. tostring(dig_ok), "mic_ana=" .. tostring(ana_ok))

    sys.subscribe("SIP_RECORD_VOIP_STARTED", config_dac_vol)
    return true
end

return audio_drv
