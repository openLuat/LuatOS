local cnt = 0
sys.subscribe("CC_IND", function(state)
    log.info("CC_IND", state)
    if state == "READY" then
        sys.publish("CC_READY")
    elseif state == "INCOMINGCALL" then
        cnt = cnt + 1
        if cnt > 1 then
            cc.accept(0)
        end
    elseif state == "HANGUP_CALL_DONE" or state == "MAKE_CALL_FAILED" or state == "DISCONNECTED" then
        audio.pm(0, audio.STANDBY)
        -- audio.pm(0,audio.SHUTDOWN)	--低功耗可以选择SHUTDOWN或者POWEROFF，如果codec无法断电用SHUTDOWN
    end
end)

local ccReady = false
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
    local pa_pin = 23
    local pa_on_level = 1
    local pa_delay = 100
    local power_pin = 255
    local power_on_level = 1
    local power_delay = 3
    local power_time_delay = 100
    local voice_vol = 100
    local mic_vol = 80
    local find_es8311 = false
    mcu.altfun(mcu.I2C, i2c_id, 13, 2, 0)
    mcu.altfun(mcu.I2C, i2c_id, 14, 2, 0)
    i2c.setup(i2c_id, i2c.FAST)
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
    i2s.setup(i2s_id, i2s_mode, i2s_sample_rate, i2s_bits_per_sample, i2s_channel_format, i2s_communication_format, i2s_channel_bits)
    audio.config(multimedia_id, pa_pin, pa_on_level, power_delay, pa_delay, power_pin, power_on_level, power_time_delay)
    audio.setBus(multimedia_id, audio.BUS_I2S, {
        chip = "es8311",
        i2cid = i2c_id,
        i2sid = i2s_id,
        voltage = audio.VOLTAGE_1800
    }) -- 通道0的硬件输出通道设置为I2S
    audio.vol(multimedia_id, voice_vol)
    audio.micVol(multimedia_id, mic_vol)
    cc.init(multimedia_id)
    audio.pm(0, audio.STANDBY)
    sys.publish("AUDIO_SETUP_DONE")--音频初始化完毕了
    sys.waitUntil("CC_READY")
    ccReady = true
    sys.wait(100)
end)

sys.taskInit(function()
    sys.waitUntil("AUDIO_SETUP_DONE")
    log.info("audio", "ready")
    while true do
        local _,cmd,param = sys.waitUntil("AUDIO_CMD_RECEIVED")
        log.info("audio", cmd, param)
        if cmd == "call" then
            if ccReady then
                cc.dial(0,param) --拨打电话
            else
                log.info("audio", "cc not ready")
            end
        elseif cmd == "music" then
            local result = audio.play(0, "/luadb/yuan.amr")
            log.info("audio", "play music",result)
            sys.wait(1000)
            if not audio.isEnd(0) then
                log.info("手动关闭")
                audio.playStop(0)
            end
            audio.pm(0, audio.STANDBY)
        end
    end
end)
