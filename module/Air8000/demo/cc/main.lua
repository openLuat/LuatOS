
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "ccdemo"
VERSION = "1.0.0"
log.style(1)

uart.setup(1, 115200)

local up1 = zbuff.create(6400,0)
local up2 = zbuff.create(6400,0)
local down1 = zbuff.create(6400,0)
local down2 = zbuff.create(6400,0)
local cnt = 0

local function record(is_dl, point)
    if is_dl then
        log.info("下行数据，位于缓存", point+1, "缓存1数据量", down1:used(), "缓存2数据量", down2:used())
    else
        log.info("上行数据，位于缓存", point+1, "缓存1数据量", up1:used(), "缓存2数据量", up2:used())
    end
	log.info("通话质量", cc.quality())
    -- 可以在初始化串口后，通过uart.tx来发送走对应的zbuff即可
end

sys.subscribe("CC_IND", function(state)
    log.info("cc_status", state)
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
if cc then
    log.info("支持cc库")
    cc.on("record", record)
    cc.record(true, up1, up2, down1, down2)
end
    local multimedia_id = 0
    local i2c_id = 0
    local i2s_id = 0
    local i2s_mode = 0
    local i2s_sample_rate = 16000
    local i2s_bits_per_sample = 16
    local i2s_channel_format = i2s.MONO_R
    local i2s_communication_format = i2s.MODE_LSB
    local i2s_channel_bits = 16

    local pa_pin = 0      --  PA 使能开关
    local pa_on_level = 1
    local pa_delay = 100
    local power_pin = 28      --  8311 使能开关
    local power_on_level = 1
    local power_delay = 3
    local power_time_delay = 100

    local voice_vol = 60
    local mic_vol = 80

    local find_es8311 = false
    gpio.setup(24, 1, gpio.PULLUP)          -- 默认打开内部的I2C0 相关器件，不然I2C 初始化会失败
    gpio.setup(power_pin, 1, gpio.PULLUP)            -- 打开es8311 的电源脚
    gpio.setup(pa_pin, 1, gpio.PULLUP)               -- 打开pa 的电源脚
    sys.wait(300)
    i2c.setup(i2c_id, i2c.FAST)
    if i2c.send(i2c_id, 0x18, 0xfd) == true then
        log.info("音频小板或内置ES8311", "codec on i2c0")
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
    if cc then
        sys.waitUntil("IP_READY")
        
        cc.init(multimedia_id)

        audio.pm(0,audio.STANDBY)
        sys.waitUntil("CC_READY")
        -- sys.wait(3000)   
        -- cc.dial(0,"10086") --拨打电话
    end

end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
