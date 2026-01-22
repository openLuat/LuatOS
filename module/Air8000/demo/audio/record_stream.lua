--[[
@module  record_stream
@summary 流式录音
@version 1.0
@date    2025.09.08
@author  陈媛媛
@usage

注意：
如果搭配AirAUDIO_1010 音频板测试，需将AirAUDIO_1010 音频板中PA开关拨到OFF，让软件控制PA，避免pop音

流式录音(仅支持PCM)，核心业务逻辑为：
1、主程序录音进行流式录音
2、录音过程中不断的进行recode_data_callback回调，回调内容为音频流的地址和长度
本文件没有对外接口，直接在main.lua中require "record_stream"就可以加载运行；
]]
exaudio = require("exaudio")

-- 音频初始化设置参数,exaudio.setup 传入参数
local audio_setup_param ={
    model= "es8311",          -- dac类型,可填入"es8311","es8211"
    i2c_id = 0,          -- i2c_id,可填入0，1 并使用pins 工具配置对应的管脚
    --Air8000开发板配置pa_ctrl 和dac_ctrl 
    pa_ctrl = 162,            -- 音频放大器电源控制管脚
    dac_ctrl = 164,           -- 音频编解码芯片电源控制管脚
    --Air8000核心板配置pa_ctrl 和dac_ctrl 
    -- pa_ctrl = 17,            -- 音频放大器电源控制管脚
    -- dac_ctrl = 16,           -- 音频编解码芯片电源控制管脚  
    bits_per_sample = 16  -- 录音的位深，可选8,16,24 位，但是当选择音频格式为AMR_NB,自动调节为8位,当音频格式为AMR_WB,自动调节为16位
}

-- 录音的数据流回调函数，注意不可以在回调函数中加入耗时和延迟的操作
local function  recode_data_callback(addr,data_len)
    log.info("收到音频流,地址为:",addr,"有效数据长度为:",data_len)
end
local function record_end(event)
    if event == exaudio.RECORD_DONE then
        log.info("录音完成")
    end
end 

-- 录音配置参数,exaudio.record_start 的入参
local audio_record_param ={
    format= exaudio.PCM_16000,    -- 录制格式，有exaudio.AMR_NB,exaudio.AMR_WB,exaudio.PCM_8000,exaudio.PCM_16000,exaudio.PCM_24000,exaudio.PCM_32000
    time = 5,               -- 录制时间,单位(秒)
    path = recode_data_callback,             -- 如果填入的是字符串，则表示是文件路径，录音会传输到这个路径里
                                        -- 如果填入的是函数，则表示是流式录音，录音的数据会传输到此函数内,返回的是zbuf地址，以及数据长度
                                        -- 如果是流式录音，则仅支持PCM 格式 
    cbfnc = record_end,            -- 录音完毕回调函数
}



local taskName = "task_audio"
local function audio_task()
    log.info("开始流式录制音频到文件")
    if exaudio.setup(audio_setup_param) then
        exaudio.record_start(audio_record_param)
    end
end

sys.taskInitEx(audio_task, taskName)
