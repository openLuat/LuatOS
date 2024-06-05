local cnt = 0
sys.subscribe("CC_IND", function(state)
    if state == "READY" then
        sys.publish("CC_READY")
    elseif state == "INCOMINGCALL" then
		cnt = cnt + 1
		if cnt > 1 then
			cc.accept(0)
		end
    elseif state == "HANGUP_CALL_DONE" or state == "MAKE_CALL_FAILED" or state == "DISCONNECTED" then
		audio.pm(0,audio.STANDBY)
		-- audio.pm(0,audio.SHUTDOWN)	--低功耗可以选择SHUTDOWN或者POWEROFF，如果codec无法断电用SHUTDOWN
	end
end)

sys.taskInit(function()
    local multimedia_id = 0
    local i2c_id = 0
    local i2s_id = 0
    local i2s_mode = 0
    local i2s_sample_rate = 16000
    local i2s_bits_per_sample = 16
    local i2s_channel_format = i2s.MONO_R
    local i2s_communication_format = i2s.MODE_LSB
    local i2s_channel_bits = 16

    local pa_pin = 25
    local pa_on_level = 1
    local pa_delay = 100
    local power_pin = 255
    local power_on_level = 1
    local power_delay = 3
    local power_time_delay = 100

    local voice_vol = 70
    local mic_vol = 65

    local find_es8311 = false
	--自适应开发板，如果明确是I2C几就不用了
    i2c.setup(i2c_id, i2c.FAST)
	pm.power(pm.LDO_CTL, false)  --开发板上ES8311由LDO_CTL控制上下电
    sys.wait(10)
    pm.power(pm.LDO_CTL, true)  --开发板上ES8311由LDO_CTL控制上下电
	sys.wait(10)
    if i2c.send(i2c_id, 0x18, 0xfd) == true then
        find_es8311 = true
    end

    if not find_es8311 then
        while true do
            log.info("not find es8311")
            sys.wait(1000)
        end
    end
    i2s.setup(i2s_id, i2s_mode, i2s_sample_rate, i2s_bits_per_sample, i2s_channel_format, i2s_communication_format,i2s_channel_bits)
    audio.config(multimedia_id, pa_pin, pa_on_level, power_delay, pa_delay, power_pin, power_on_level, power_time_delay)
    audio.setBus(multimedia_id, audio.BUS_I2S,{chip = "es8311", i2cid = i2c_id, i2sid = i2s_id})	--通道0的硬件输出通道设置为I2S
    audio.vol(multimedia_id, voice_vol)
    audio.micVol(multimedia_id, mic_vol)
    cc.init(multimedia_id)
	audio.pm(0,audio.STANDBY)
    sys.waitUntil("CC_READY")
    sys.wait(100)   
    --cc.dial(0,"114") --拨打电话
end)
