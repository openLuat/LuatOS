exaudio = require("exaudio")

local audio_setup_param ={
    model= "es8311",          -- dac类型,可填入"es8311","es8211"
    i2c_id = 0,          -- i2c_id,可填入0，1 并使用pins 工具配置对应的管脚
    pa_ctrl = 162,         -- 音频放大器电源控制管脚
    dac_ctrl = 164,        --  音频编解码芯片电源控制管脚
    bits_per_sample = 16  -- 录音的位深，可选8,16,24 位，但是当选择音频格式为AMR_NB,自动调节为8位,当音频格式为AMR_WB,自动调节为16位
}
local recordPath = "/record.amr"

local function record_end(event)
    if event == exaudio.RECORD_DONE then
        log.info("录音完成")
        log.info("录音后文件大小",io.fileSize(recordPath))
    end
end 


local audio_record_param ={
    format= exaudio.AMR_WB,    -- 录制格式，有exaudio.AMR_NB,exaudio.AMR_WB,exaudio.PCM_8000,exaudio.PCM_16000,exaudio.PCM_24000,exaudio.PCM_32000
    time = 5,               -- 录制时间,单位(秒)
    path = recordPath,             -- 如果填入的是字符串，则表示是文件路径，录音会传输到这个路径里
                                      -- 如果填入的是函数，则表示是流式录音，录音的数据会传输到此函数内,返回的是zbuf地址，以及数据长度
    cbFnc = record_end,            -- 录音完毕回调函数
}



local taskName = "task_audio"
local function audio_task()
    sys.wait(100)
    log.info("开始录制音频到文件")
    if exaudio.setup(audio_setup_param) then
        exaudio.record_start(audio_record_param)
    end
end

sysplus.taskInitEx(audio_task, taskName)
