exaudio = require("exaudio")

local audio_setup_param ={
    model= "es8311",          -- dac类型,可填入"es8311","es8211"
    i2c_id = 0,          -- i2c_id,可填入0，1 并使用pins 工具配置对应的管脚
    pa_ctrl = 162,         -- 音频放大器电源控制管脚
    dac_ctrl = 164,        --  音频编解码芯片电源控制管脚
    bits_per_sample = 16  -- 录音的位深，可选8,16,24 位，但是当选择音频格式为AMR_NB,自动调节为8位,当音频格式为AMR_WB,自动调节为16位
    -- dac_delay = 3,        -- 在DAC启动前插入的冗余时间，单位100ms,控制pop 音
    -- pa_delay = 100,      -- 在DAC启动后，延迟多长时间打开PA，单位1ms,控制pop 音
    -- dac_time_delay = 600,    -- 音频播放完毕时，PA与DAC关闭的时间间隔，单位1ms,控制pop 音
    -- pa_on_level = 1,           -- PA打开电平 1 高电平 0 低电平        
}

local function  recode_data_callback(addr,data_len)
    log.info("收到音频流,地址为:",addr,"有效数据长度为:",data_len)
end
local function record_end(event)
    if event == exaudio.RECODE_DONE then
        log.info("录音完成")
    end
end 

local audio_record_param ={
    format= exaudio.AMR_NB,    -- 录制格式，有exaudio.AMR_NB,exaudio.AMR_WB,exaudio.PCM_8000,exaudio.PCM_16000,exaudio.PCM_24000,exaudio.PCM_32000
    time = 5,               -- 录制时间,单位(秒)
    path = recode_data_callback,             -- 如果填入的是字符串，则表示是文件路径，录音会传输到这个路径里
                            -- 如果填入的是函数，则表示是流式录音，录音的数据会传输到此函数内,返回的是zbuf地址，以及数据长度
    cbFnc = record_end,            -- 录音完毕回调函数
}



local taskName = "task_audio"
local function audio_task()
    log.info("开始流式录制音频到文件")
    if exaudio.setup(audio_setup_param) then
        exaudio.record_start(audio_record_param)
    end
end

sysplus.taskInitEx(audio_task, taskName)
