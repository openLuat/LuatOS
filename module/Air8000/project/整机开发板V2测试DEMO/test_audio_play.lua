--[[
1.本demo可直接在Air8000整机开发板上运行，如有需要请luat.taobao.com 购买
2.演示如何播放音频，注意此demo 不可以和audio_record,audio_tts  demo同时使用
3.使用了如下的IO口
[18, "I2S_CLK", " PIN18脚, 用于音频时钟信号"],
[19, "I2S_LRCK", " PIN19脚, 用于音频的左右声道时钟"],
[20, "I2S_DIN", " PIN20脚, 用于音频数据传输"],
[21, "I2S_DOUT", " PIN21脚, 用于音频数据传输"],
[22, "I2S_MCLK", " PIN22脚, 音频主时钟"],
[73, "GPIO162", " PIN73脚, 用于打开音频PA 开关，用来输出音频"],
[74, "GPIO164", " PIN74脚, 用于使能ES8311 编解码芯片"],
[80, "I2C0_SCL", " PIN80脚, I2C0_SCL 触摸屏通信,摄像头复用"],
[81, "I2C0_SDA", " PIN81脚, I2C0_SDA 触摸屏通信,摄像头复用"],
4.程序运行逻辑为，输入1.mp3文件路径，经过音频编码解码后，使用整机的扬声器输出
]]



local taskName = "task_audio_play"
local i2c_id = 0            -- i2c_id 0
local pa_pin = 162           -- 喇叭pa功放脚
local power_pin = 164         -- es8311电源脚
local i2s_id = 0            -- i2s_id 0
local i2s_mode = 0          -- i2s模式 0 主机 1 从机
local i2s_sample_rate = 16000   -- 采样率
local i2s_bits_per_sample = 16  -- 数据位数
local i2s_channel_format = i2s.MONO_R   -- 声道, 0 左声道, 1 右声道, 2 立体声
local i2s_communication_format = i2s.MODE_LSB   -- 格式, 可选MODE_I2S, MODE_LSB, MODE_MSB
local i2s_channel_bits = 16     -- 声道的BCLK数量

local multimedia_id = 0         -- 音频通道 0
local pa_on_level = 1           -- PA打开电平 1 高电平 0 低电平
local power_delay = 3           -- 在DAC启动前插入的冗余时间，单位100ms
local pa_delay = 100            -- 在DAC启动后，延迟多长时间打开PA，单位1ms
local power_on_level = 1        -- 电源控制IO的电平，默认拉高
local power_time_delay = 100    -- 音频播放完毕时，PA与DAC关闭的时间间隔，单位1ms

local voice_vol = 50        -- 喇叭音量
local mic_vol = 80          -- 麦克风音量

local MSG_MD = "moreData"   -- 播放缓存有空余
local MSG_PD = "playDone"   -- 播放完成所有数据

function audio_setup()
    pm.power(pm.LDO_CTL, false)  --开发板上ES8311由LDO_CTL控制上下电
    sys.wait(100)
    pm.power(pm.LDO_CTL, true)  --开发板上ES8311由LDO_CTL控制上下电

    i2c.setup(i2c_id,i2c.FAST)      --设置i2c
    i2s.setup(i2s_id, i2s_mode, i2s_sample_rate, i2s_bits_per_sample, i2s_channel_format, i2s_communication_format,i2s_channel_bits)    --设置i2s

    audio.config(multimedia_id, pa_pin, pa_on_level, power_delay, pa_delay, power_pin, power_on_level, power_time_delay)
    audio.setBus(multimedia_id, audio.BUS_I2S,{chip = "es8311",i2cid = i2c_id , i2sid = i2s_id, voltage = audio.VOLTAGE_1800})	--通道0的硬件输出通道设置为I2S

    audio.vol(multimedia_id, voice_vol)
    audio.micVol(multimedia_id, mic_vol)
    sys.publish("AUDIO_READY")
end



local function audio_play(id, event)
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
end


local function audio_task()
    local result    
    sys.taskInit(audio_setup)  -- 初始化音频，因为涉及到延迟，所以用task 的方式启动
    audio.on(0,audio_play)   --注册audio播放事件回调
    sys.waitUntil("AUDIO_READY")
    while true do
        log.info("开始播放")
        result = audio.play(0,"/luadb/1.mp3")
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
		    audio.pm(0,audio.STANDBY)       --PM模式 待机模式，PA断电，codec待机状态，系统不能进低功耗状态，如果PA不可控，codec进入静音模式
        end
		-- audio.pm(0,audio.SHUTDOWN)	--低功耗可以选择SHUTDOWN或者POWEROFF，如果codec无法断电用SHUTDOWN
        log.info("mem", "sys", rtos.meminfo("sys"))
        log.info("mem", "lua", rtos.meminfo("lua"))
        sys.wait(1000)
    end
end


sysplus.taskInitEx(audio_task, taskName)   
