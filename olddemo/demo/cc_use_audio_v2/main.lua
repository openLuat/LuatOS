
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "ccdemo"
VERSION = "1.0.0"
local es8311 = require "es8311"
log.style(1)
mcu.hardfault(0)
audio_v2.debug(true)    --测试阶段打开调试模式
--[[
    本demo暂时只在air780ep测试过
    本demo需要外挂ES8311 codec芯片
]]

-- sys库是标配
sys = require("sys")

if wdt then
    --添加硬狗防止程序卡死，在支持的设备上启用这个功能
    --wdt.init(9000)--初始化watchdog设置为9s
    --sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end
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
    if state == "READY" then
        sys.publish("CC_READY")
    elseif state == "INCOMINGCALL" then
		cnt = cnt + 1
		if cnt > 1 then
			cc.accept(0)
		end
    elseif state == "AUDIO_START" then
		-- 可以往对端发送额外的音频数据
        -- cc.extern_source({"/luadb/test_16k.mp3"})
        cc.extern_source("你好，测试一下，测试一下，测试一下")
    elseif state == "HANGUP_CALL_DONE" or state == "MAKE_CALL_FAILED" or state == "DISCONNECTED" then
		-- audio.pm(0,audio.SHUTDOWN)	--低功耗可以选择SHUTDOWN或者POWEROFF，如果codec无法断电用SHUTDOWN
	end
end)

function audio_setup_air780ehm_evb()
    local i2c_id = 1
    local all_nums, default_driver_index = audio_v2.get_driver_info()
    for i = 0, all_nums - 1 do
        log.info("驱动序号", i, "id", audio_v2.print_probe_id(audio_v2.get_driver_id(i), true))
    end
    log.info("默认驱动序号", default_driver_index, "id", audio_v2.print_probe_id(audio_v2.get_driver_id(default_driver_index), true))
    audio_v2.config_pa_power_ctrl(true, 1, 1, 100)  --PA能控制
    audio_v2.config_codec_power_ctrl(false, nil, nil, 600, 0) --codec电源不控制，只控制播放前的空白音时长

    audio_v2.config(audio_v2.CFG_PARAM_I2S_MODE, audio_v2.CFG_VALUE_I2S_MODE_LSB)
    audio_v2.config(audio_v2.CFG_PARAM_I2S_FRAME_BITS, 16, 16)
    audio_v2.config(audio_v2.CFG_PARAM_I2S_CHANNEL_TYPE, audio_v2.CFG_VALUE_I2S_CHANNEL_TYPE_RIGHT)

    i2c.setup(i2c_id)
    gpio.setup(2, 1) --全程都打开codec电源
    es8311.init(i2c_id)
    es8311.set_sample_rate(i2c_id,16000,256)
    es8311.set_data_bits(i2c_id,16)
    es8311.set_format(i2c_id)
    es8311.resume(i2c_id)
    es8311.set_voice_vol(i2c_id,57)
    es8311.set_mic_vol(i2c_id,85)
    --es8311.standby(i2c_id)
end

sys.taskInit(function()
    audio_setup_air780ehm_evb()
    cc.init()
    cc.on("record", record)
    cc.record(true, up1, up2, down1, down2)
    sys.waitUntil("CC_READY")
    sys.wait(100)   
    --cc.dial(0,"114") --拨打电话
end)

-- sys.taskInit(function()
--     while 1 do
--         -- 打印内存状态, 调试用
--         sys.wait(1000)
--         log.info("lua", rtos.meminfo())
--         log.info("sys", rtos.meminfo("sys"))
--     end
-- end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
