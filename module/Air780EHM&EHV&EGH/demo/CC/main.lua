
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "ccdemo"
VERSION = "1.0.0"
log.style(1)
--[[]
运行环境：Air780EHV核心板+AirAUDIO_1000配件板
最后修改时间：2025-6-17
使用了如下IO口：
[3, "MIC+", " PIN3脚, 用于麦克风正极"],
[4, "MIC-", " PIN4脚, 用于麦克风负极"],
[5, "spk+", " PIN5脚, 用于喇叭正极"],
[6, "spk-", " PIN6脚, 用于喇叭负极"],
[20, "AudioPA_EN", " PIN20脚, 用于PA使能脚"],
3.3V
GND
执行逻辑为：
设置i2s和音频参数，读取文件qianzw.txt里面的内容，然后播放出来
]]

-- sys库是标配
sys = require("sys")

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
    log.info("cc状态", state)
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
    cc.on("record", record)
    cc.record(true, up1, up2, down1, down2)
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

    cc.init(multimedia_id)
	audio.pm(0,audio.STANDBY)
    sys.waitUntil("CC_READY")
    log.info("一切就绪，5S后准备打电话")
    sys.wait(5000)   
    -- cc.dial(0,"12345678910) --拨打电话



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
