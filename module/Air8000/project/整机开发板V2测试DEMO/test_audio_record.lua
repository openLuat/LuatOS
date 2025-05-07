--[[
1. 本demo可直接在Air8000整机开发板上运行，如有需要请luat.taobao.com 购买
2. 注意：演示如何录制音频，注意此demo 不可同时和audio_play,audio_tts  同时使用
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
4. 本demo 处理逻辑是，开始录音，录制7秒左右，停止录音，并保存录音文件，然后播放录音文件
]]


taskName = "audio_record"
local MSG_MD = "moreData"   -- 播放缓存有空余
local MSG_PD = "playDone"   -- 播放完成所有数据
local i2c_id = 0            -- i2c_id 0

local pa_pin = 16           -- 喇叭pa功放脚
local power_pin = 8         -- es8311电源脚

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
-- amr数据存放buffer，尽可能地给大一些
local amr_buff = zbuff.create(20 * 1024)
--创建一个amr的encoder
local encoder = nil
local voice_vol = 70        -- 喇叭音量
local mic_vol = 80          -- 麦克风音量
local pcm_buff0 = zbuff.create(16000)
local pcm_buff1 = zbuff.create(16000)

local function audio_record(id, event, point)

    --使用play来播放文件时只有播放完成回调
    if event == audio.RECORD_DATA then -- 录音数据
        if point == 0 then
            log.info("buff", point, pcm_buff0:used())
            codec.encode(encoder, pcm_buff0, amr_buff)
        else
            log.info("buff", point, pcm_buff1:used())
            codec.encode(encoder, pcm_buff1, amr_buff)
        end
        
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
end



function audio_setup()
    pm.power(pm.LDO_CTL, false)  --开发板上ES8311由LDO_CTL控制上下电
    sys.wait(100)
    pm.power(pm.LDO_CTL, true)  --开发板上ES8311由LDO_CTL控制上下电
    gpio.setup(8, 1)

    i2c.setup(i2c_id,i2c.FAST)      --设置i2c
    i2s.setup(i2s_id, i2s_mode, i2s_sample_rate, i2s_bits_per_sample, i2s_channel_format, i2s_communication_format,i2s_channel_bits)    --设置i2s

    audio.config(multimedia_id, pa_pin, pa_on_level, power_delay, pa_delay, power_pin, power_on_level, power_time_delay)
    audio.setBus(multimedia_id, audio.BUS_I2S,{chip = "es8311",i2cid = i2c_id , i2sid = i2s_id, voltage = audio.VOLTAGE_1800})	--通道0的硬件输出通道设置为I2S

    audio.vol(multimedia_id, voice_vol)
    audio.micVol(multimedia_id, mic_vol)
    sys.publish("AUDIO_READY")
end


local function audio_record_task()
    audio_setup()
    audio.on(0,audio_record)   --注册audio播放事件回调
    sys.waitUntil("AUDIO_READY")
    sys.wait(5000)
    local result

    --下面为录音demo，根据适配情况选择性开启
    local recordPath = "/record.amr"
    
    
    encoder = codec.create(codec.AMR, false, 7)
    log.info("encoder",encoder)
    log.info("开始录音")
    err = audio.record(0, audio.AMR, 5, 7, nil,nil, pcm_buff0, pcm_buff1)
    sys.waitUntil("AUDIO_RECORD_DONE")
    log.info("record","录音结束")
    os.remove(recordPath)
    io.writeFile(recordPath, "#!AMR\n")
	io.writeFile(recordPath, amr_buff:query(), "a+b")

	result = audio.play(0, {recordPath})
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

end


sysplus.taskInitEx(audio_record_task, taskName)   