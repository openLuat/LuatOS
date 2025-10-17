
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "tts_tm8211"
VERSION = "1.0.0"

-- sys库是标配
_G.sys = require("sys")
_G.sysplus = require("sysplus")

local pa_pin = 16 -- 喇叭pa功放脚
local power_pin = 17 -- tm8211电源脚 -----> 也是AirAudio_1020扩展板上的I2S_EN脚

local i2s_id = 0            -- i2s_id 0
local i2s_mode = 0          -- i2s模式 0 主机 1 从机
local i2s_sample_rate = 16000   -- 采样率
local i2s_bits_per_sample = 16  -- 数据位数
local i2s_channel_format = i2s.STEREO   -- 声道, 0 左声道, 1 右声道, 2 立体声
local i2s_communication_format = i2s.MODE_MSB   -- 格式, 可选MODE_I2S, MODE_LSB, MODE_MSB
local i2s_channel_bits = 16     -- 声道的BCLK数量

local multimedia_id = 0         -- 音频通道 0
local pa_on_level = 1           -- PA打开电平 1 高电平 0 低电平
local power_delay = 3           -- 在DAC启动前插入的冗余时间，单位100ms
local pa_delay = 10            -- 在DAC启动后，延迟多长时间打开PA，单位1ms
local power_on_level = 1        -- 电源控制IO的电平，默认拉高
local power_time_delay = 0    -- 音频播放完毕时，PA与DAC关闭的时间间隔，单位1ms

local voice_vol = 60        -- 喇叭音量
local mic_vol = 80          -- 麦克风音量
function audio_setup()
    sys.wait(100)
    gpio.setup(power_pin, 1, gpio.PULLUP)
    i2s.setup(i2s_id, i2s_mode, i2s_sample_rate, i2s_bits_per_sample, i2s_channel_format, i2s_communication_format,i2s_channel_bits)

    audio.config(multimedia_id, pa_pin, pa_on_level, power_delay, pa_delay, power_pin, power_on_level, power_time_delay)
    audio.setBus(multimedia_id, audio.BUS_I2S,{chip = "tm8211", i2sid = i2s_id})	--通道0的硬件输出通道设置为I2S

    audio.vol(multimedia_id, voice_vol)
    -- audio.micVol(multimedia_id, mic_vol)
    sys.publish("AUDIO_READY")
end

-- 配置好audio外设
sys.taskInit(audio_setup)

local taskName = "task_audio"

local MSG_MD = "moreData"   -- 播放缓存有空余
local MSG_PD = "playDone"   -- 播放完成所有数据

audio.on(0, function(id, event)
    --使用play来播放文件时只有播放完成回调
    local succ,stop,file_cnt = audio.getError(0)
    if not succ then
        if stop then
            log.info("用户停止播放")
        else
            log.info("第", file_cnt, "个文件解码失败")
        end
    end
    sysplus.sendMsg(taskName, MSG_PD)
end)


local function audio_task()
    local result    
    sys.waitUntil("AUDIO_READY")

    -- 本例子是按行播放 "千字文", 文本来源自wiki百科
    local fd = nil
    local line = nil
    while true do
        log.info("开始播放")
        line = nil
        if not fd then
            fd = io.open("/luadb/qianzw.txt")
        end
        if fd then
            line = fd:read("*l")
            if line == nil then
                fd:close()
                fd = nil
            end
        end
        if line == nil then
            line = "一二三四五六七八九十一二三四五六七八九十一二三四五六七八九十一二三四五六七八九十一二三四五六七八九十"
        end
        line = line:trim()
        log.info("播放内容", line)
        result = audio.tts(0, line)
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
        if audio.pm then
		    audio.pm(0,audio.STANDBY)
        end
		-- audio.pm(0,audio.SHUTDOWN)	--低功耗可以选择SHUTDOWN或者POWEROFF，如果codec无法断电用SHUTDOWN
        log.info("mem", "sys", rtos.meminfo("sys"))
        log.info("mem", "lua", rtos.meminfo("lua"))
        sys.wait(1000)
    end
    sysplus.taskDel(taskName)
end

sysplus.taskInitEx(audio_task, taskName)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
