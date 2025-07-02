function audio_init()
    pm.ioVol(pm.IOVOL_ALL_GPIO, 3300)
    local multimedia_id = 0

    local i2s_id = 0
    local i2s_mode = 0
    local i2s_sample_rate = 16000
    local i2s_bits_per_sample = 16
    local i2s_channel_format = i2s.MONO_R
    local i2s_communication_format = i2s.MODE_LSB
    local i2s_channel_bits = 16
    --air8000 core开发版+音频小板配置
    local voice_vol = 60 --音频小板喇叭太容易失真了，不能太大
    local i2c_id = 0
    local pa_pin = 26
    local pa_on_level = 1
    local pa_delay = 200
    local dac_power_pin = 28
    local dac_power_on_level = 1
    local dac_power_off_delay = 600
    gpio.setup(24, 1)   --air8000的I2C0需要拉高gpio24才能用
    gpio.setup(26, 0)
    i2c.setup(0, i2c.FAST)

    i2s.setup(i2s_id, i2s_mode, i2s_sample_rate, i2s_bits_per_sample, i2s_channel_format, i2s_communication_format,i2s_channel_bits)

    audio.config(multimedia_id, pa_pin, pa_on_level, 0, pa_delay, dac_power_pin, dac_power_on_level, dac_power_off_delay)
    audio.setBus(multimedia_id, audio.BUS_I2S,{chip = "es8311",i2cid = i2c_id , i2sid = i2s_id})	--通道0的硬件输出通道设置为I2S

    audio.vol(multimedia_id, voice_vol)
    audio.micVol(multimedia_id, 75)
end