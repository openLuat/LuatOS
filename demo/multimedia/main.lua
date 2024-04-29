
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "audiotest"
VERSION = "2.0.1"

-- sys库是标配
_G.sys = require("sys")
_G.sysplus = require("sysplus")


-- Air780E的AT固件默认会为开机键防抖, 导致部分用户刷机很麻烦
if rtos.bsp() == "EC618" and pm and pm.PWK_MODE then
    pm.power(pm.PWK_MODE, false)
end

log.style(1)
local taskName = "task_audio"

local MSG_MD = "moreData"   -- 播放缓存有空余
local MSG_PD = "playDone"   -- 播放完成所有数据

-- amr数据存放buffer，尽可能地给大一些
amr_buff = zbuff.create(20 * 1024)
--创建一个amr的encoder
encoder = nil

audio.on(0, function(id, event,buff)
    --使用play来播放文件时只有播放完成回调
    if event == audio.RECORD_DATA then -- 录音数据
        codec.encode(encoder, buff, amr_buff)
    elseif event == audio.RECORD_DONE then -- 录音完成
        sys.publish("AUDIO_RECORD_DONE")
    else
        local succ,stop,file_cnt = audio.getError(0)
        if not succ then
            if stop then
                log.info("用户停止播放")
            else
                log.info("第", file_cnt, "个文件解码失败")
            end
        end
        -- log.info("播放完成一个音频")
        sysplus.sendMsg(taskName, MSG_PD)
    end
end)

function audio_setup()
    local bsp = rtos.bsp()
    if bsp == "EC618" then
        --Air780E开发板配套+音频扩展板. ES7149
        --由于音频扩展板的PA是长供电的,有塔塔声音是正常的,做产品的话有额外的参考设计
        i2s.setup(0, 0, 0, 0, 0, i2s.MODE_I2S)

        --如果用TM8211，打开下面的注释
        -- i2s.setup(0, 0, 0, 0, 0, i2s.MODE_MSB)

        --如果用软件DAC，打开下面的注释
        -- if audio.setBus then
        --     audio.setBus(0, audio.BUS_SOFT_DAC)
        -- end
        audio.config(0, 25, 1, 3, 100)
    elseif bsp == "EC718P" then
		-- CORE+音频小板是这个配置

        pm.power(pm.LDO_CTL, false)  --开发板上ES8311由LDO_CTL控制上下电
        sys.wait(100)
        pm.power(pm.LDO_CTL, true)  --开发板上ES8311由LDO_CTL控制上下电

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
        local power_pin = 16
        local power_on_level = 1
        local power_delay = 3
        local power_time_delay = 100

        local voice_vol = 70
        local mic_vol = 80
    
        i2c.setup(i2c_id,i2c.FAST)
        i2s.setup(i2s_id, i2s_mode, i2s_sample_rate, i2s_bits_per_sample, i2s_channel_format, i2s_communication_format,i2s_channel_bits)
    
        audio.config(multimedia_id, pa_pin, pa_on_level, power_delay, pa_delay, power_pin, power_on_level, power_time_delay)
        audio.setBus(multimedia_id, audio.BUS_I2S,{chip = "es8311",i2cid = i2c_id , i2sid = i2s_id})	--通道0的硬件输出通道设置为I2S

        audio.vol(multimedia_id, voice_vol)
        audio.micVol(multimedia_id, mic_vol)
        -- audio.debug(true)

	--带TM8211的云喇叭开发板参考下面的配置
		--[[
		local multimedia_id = 0
        local i2s_id = 0
        local i2s_mode = 0
        local i2s_sample_rate = 0
        local i2s_bits_per_sample = 16
        local i2s_channel_format = i2s.STEREO
        local i2s_communication_format = i2s.MODE_MSB
        local i2s_channel_bits = 16
    
        local pa_pin = 25
        local pa_on_level = 1
        local pa_delay = 100
        local power_pin = nil
        local power_on_level = 1
        local power_delay = 3
        local power_time_delay = 0

        -- local voice_vol = 200	--默认就不放大了
        i2s.setup(i2s_id, i2s_mode, i2s_sample_rate, i2s_bits_per_sample, i2s_channel_format, i2s_communication_format,i2s_channel_bits)
        audio.config(multimedia_id, pa_pin, pa_on_level, power_delay, pa_delay, power_pin, power_on_level, power_time_delay)
        audio.setBus(multimedia_id, audio.BUS_I2S,{chip = "tm8211", i2sid = i2s_id})	--通道0的硬件输出通道设置为I2S
        -- audio.vol(multimedia_id, voice_vol)
		]]
    elseif bsp == "AIR105" then
        -- Air105开发板支持DAC直接输出
        audio.config(0, 25, 1, 3, 100)
    else
        -- 其他板子未支持
        while 1 do
            log.info("audio", "尚未支持的BSP")
            sys.wait(1000)
        end
    end
    sys.publish("AUDIO_READY")
end

-- 配置好audio外设
sys.taskInit(audio_setup)

local function audio_task()
    sys.waitUntil("AUDIO_READY")
    local result

    --下面为录音demo，根据适配情况选择性开启
    -- local recordPath = "/record.amr"
    
    -- -- 直接录音到文件
    -- err = audio.record(0, audio.AMR, 5, 7, recordPath)
    -- sys.waitUntil("AUDIO_RECORD_DONE")
    -- log.info("record","录音结束")
    -- result = audio.play(0, {recordPath})
    -- while true do
    --     msg = sysplus.waitMsg(taskName, nil)
    --     if type(msg) == 'table' then
    --         if msg[1] == MSG_PD then
    --             log.info("播放结束")
    --             break
    --         end
    --     else
    --         log.error(type(msg), msg)
    --     end
    -- end

    -- -- 录音到内存自行编码
    -- encoder = codec.create(codec.AMR, false, 7)
    -- print("encoder",encoder)
    -- err = audio.record(0, audio.AMR, 5, 7)
    -- sys.waitUntil("AUDIO_RECORD_DONE")
    -- log.info("record","录音结束")
    -- os.remove(recordPath)
    -- io.writeFile(recordPath, "#!AMR\n")
	-- io.writeFile(recordPath, amr_buff:query(), "a+b")

	-- result = audio.play(0, {recordPath})
    -- while true do
    --     msg = sysplus.waitMsg(taskName, nil)
    --     if type(msg) == 'table' then
    --         if msg[1] == MSG_PD then
    --             log.info("播放结束")
    --             break
    --         end
    --     else
    --         log.error(type(msg), msg)
    --     end
    -- end

    -- amr 可播放采样率 8k/16k
    local amrs = {"/luadb/alipay.amr", "/luadb/2.amr", "/luadb/10.amr", "/luadb/yuan.amr"}
    -- 如需在同一个table内混播, 需要使用相同的采样率
    -- 此mp3为自由文件,无版权问题,合宙自录音频,若测试音质请使用其他高清mp3
    -- local mp3s = {"/luadb/test_32k.mp3"}
	-- ec618的固件需要用非full版本才能放下44k的MP3
    local mp3s = {"/luadb/test_44k.mp3"}	
    local counter = 0
    while true do
        log.info("开始播放")
        -- 两个列表前后播放
        if rtos.bsp() == "AIR105" then
            result = audio.play(0, "/luadb/test_32k.mp3")
        else
            result = audio.play(0, counter % 2 == 1 and amrs or mp3s)
        end
        counter = counter + 1
        if result then
        --等待音频通道的回调消息，或者切换歌曲的消息
            while true do
                msg = sysplus.waitMsg(taskName, nil)
                if type(msg) == 'table' then
                    if msg[1] == MSG_PD then
                        log.info("播放结束")
                        break
                    end
                else
                    log.error(type(msg), msg)
                end
            end
        else
            log.debug("解码失败!")
            sys.wait(1000)
        end
        if not audio.isEnd(0) then
            log.info("手动关闭")
            audio.playStop(0)
        end
		audio.pm(0,audio.STANDBY)
		-- audio.pm(0,audio.SHUTDOWN)	--低功耗可以选择SHUTDOWN或者POWEROFF，如果codec无法断电用SHUTDOWN
        -- log.info(rtos.meminfo("sys"))
        -- log.info(rtos.meminfo("lua"))
        sys.wait(1000)
    end
    sysplus.taskDel(taskName)
end

sysplus.taskInitEx(audio_task, taskName, task_cb)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
