local exaudio = require "exaudio"

local audio_drv = {}

local audio_config = {
    model = "es8311",
    i2c_id = 0,
    pa_ctrl = 162,
    dac_ctrl = 164,
    dac_delay = 6,
    pa_delay = 100,
    dac_time_delay = 100,
    bits_per_sample = 16,
    pa_on_level = 1,
    audio_mode = "old"
}

function audio_drv.init()
    if not exaudio.setup(audio_config) then
        log.error("sip_record.audio", "ES8311 初始化失败")
        return false
    end
    if exaudio.vol then
        exaudio.vol(35)
    end
    if exaudio.mic_vol then
        exaudio.mic_vol(96)
    end
    log.info("sip_record.audio", "ES8311 初始化成功", "vol=35", "mic=96")
    return true
end

return audio_drv
