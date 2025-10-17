function audio_init()
    pm.ioVol(pm.IOVOL_ALL_GPIO, 3300)
    -- local multimedia_id = 0

    -- local i2s_id = 0
    -- local i2s_mode = 0
    -- local i2s_sample_rate = 16000
    -- local i2s_bits_per_sample = 16
    -- local i2s_channel_format = i2s.MONO_R
    -- local i2s_communication_format = i2s.MODE_LSB
    -- local i2s_channel_bits = 16
    -- --air8000 core开发版+音频小板配置
    -- local voice_vol = 60 --音频小板喇叭太容易失真了，不能太大
    -- local i2c_id = 0
    -- local pa_pin = 162           -- 喇叭pa功放脚
    -- local pa_on_level = 1
    -- local pa_delay = 200
    -- local dac_power_pin = 164
    -- local dac_power_on_level = 1
    -- local dac_power_off_delay = 600
    -- gpio.setup(24, 1)   --air8000的I2C0需要拉高gpio24才能用
    -- gpio.setup(26, 0)
    -- i2c.setup(0, i2c.FAST)
    -- gpio.setup(24, 1, gpio.PULLUP)          -- i2c工作的电压域
    -- sys.wait(100)
    -- gpio.setup(dac_power_pin, 1, gpio.PULLUP)   -- 打开音频编解码供电
    -- gpio.setup(pa_pin, 1, gpio.PULLUP)      -- 打开音频放大器
    -- audio.on(0, audio_callback)

    -- i2s.setup(i2s_id, i2s_mode, i2s_sample_rate, i2s_bits_per_sample, i2s_channel_format, i2s_communication_format,i2s_channel_bits)

    -- audio.config(multimedia_id, pa_pin, pa_on_level, 0, pa_delay, dac_power_pin, dac_power_on_level, dac_power_off_delay)
    -- audio.setBus(multimedia_id, audio.BUS_I2S,{chip = "es8311",i2cid = i2c_id , i2sid = i2s_id})	--通道0的硬件输出通道设置为I2S

    -- audio.vol(multimedia_id, voice_vol)
    -- audio.micVol(multimedia_id, 75)
     local multimedia_id = 0
 local i2c_id = 0 -- i2c_id 0

    local pa_pin = gpio.AUDIOPA_EN -- 喇叭pa功放脚
    local power_pin = 20 -- es8311电源脚

    local i2s_id = 0 -- i2s_id 0
    local i2s_mode = 0 -- i2s模式 0 主机 1 从机
    local i2s_sample_rate = 16000 -- 采样率
    local i2s_bits_per_sample = 16 -- 数据位数
    local i2s_channel_format = i2s.MONO_R -- 声道, 0 左声道, 1 右声道, 2 立体声
    local i2s_communication_format = i2s.MODE_LSB -- 格式, 可选MODE_I2S, MODE_LSB, MODE_MSB
    local i2s_channel_bits = 16 -- 声道的BCLK数量

    local multimedia_id = 0 -- 音频通道 0
    local pa_on_level = 1 -- PA打开电平 1 高电平 0 低电平
    local power_delay = 3 -- 在DAC启动前插入的冗余时间，单位100ms
    local pa_delay = 100 -- 在DAC启动后，延迟多长时间打开PA，单位1ms
    local power_on_level = 1 -- 电源控制IO的电平，默认拉高
    local power_time_delay = 100 -- 音频播放完毕时，PA与DAC关闭的时间间隔，单位1ms

    local voice_vol = 70 -- 喇叭音量
    local mic_vol = 80 -- 麦克风音量
    gpio.setup(power_pin, 1, gpio.PULLUP)
    gpio.setup(pa_pin, 1, gpio.PULLUP)

    sys.wait(200)

    i2c.setup(i2c_id, i2c.FAST) -- 设置i2c
    i2s.setup(i2s_id, i2s_mode, i2s_sample_rate, i2s_bits_per_sample, i2s_channel_format, i2s_communication_format,
        i2s_channel_bits) -- 设置i2s

    audio.config(multimedia_id, pa_pin, pa_on_level, power_delay, pa_delay, power_pin, power_on_level, power_time_delay)
    audio.setBus(multimedia_id, audio.BUS_I2S, {
        chip = "es8311",
        i2cid = i2c_id,
        i2sid = i2s_id,
    }) -- 通道0的硬件输出通道设置为I2S

    audio.vol(multimedia_id, voice_vol)
    audio.micVol(multimedia_id, mic_vol)

end