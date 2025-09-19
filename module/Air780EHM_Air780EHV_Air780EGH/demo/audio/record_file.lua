--[[
@module  record_file
@summary 录音到文件
@version 1.0
@date    2025.09.08
@author  梁健
@usage

录音到文件，核心业务逻辑为：
1、主程序录音到/record.amr 文件
2、使用powerkey 按键进行录音音量减小
3、点击boot 按键进行录音音量增加
本文件没有对外接口，直接在main.lua中require "record_file"就可以加载运行；
]]
exaudio = require("exaudio")

-- 音频初始化设置参数,exaudio.setup 传入参数
local audio_setup_param ={
    model= "es8311",          -- dac类型,可填入"es8311","es8211"
    i2c_id = 0,          -- i2c_id,可填入0，1 并使用pins 工具配置对应的管脚
    pa_ctrl = 162,         -- 音频放大器电源控制管脚
    dac_ctrl = 164,        --  音频编解码芯片电源控制管脚
    bits_per_sample = 16  -- 录音的位深，可选8,16,24 位，但是当选择音频格式为AMR_NB,自动调节为8位,当音频格式为AMR_WB,自动调节为16位
}
local recordPath = "/record.amr"

-- 录音完成回调
local function record_end(event)
    if event == exaudio.RECORD_DONE then
        log.info("录音后文件大小",io.fileSize(recordPath))
    end
end 

-- 录音配置参数,exaudio.record_start 的入参
local audio_record_param ={
    format= exaudio.PCM_32000,    -- 录制格式，有exaudio.AMR_NB,exaudio.AMR_WB,exaudio.PCM_8000,exaudio.PCM_16000,exaudio.PCM_24000,exaudio.PCM_32000
                                  -- 如果选择exaudio.AMR_WB,则需要固件支持volte 功能
    time = 5,               -- 录制时间,单位(秒)
    path = recordPath,             -- 如果填入的是字符串，则表示是文件路径，录音会传输到这个路径里
                                   -- 如果填入的是函数，则表示是流式录音，录音的数据会传输到此函数内,返回的是zbuf地址，以及数据长度
                                   -- 如果是流式录音，则仅支持PCM 格式 
    cbfnc = record_end,            -- 录音完毕回调函数
}


---------------------------------
---通过BOOT 按键增大录音---
---------------------------------
local volume_number = 50 
local function add_volume()
    volume_number = volume_number + 20
    log.info("增大录音音量",volume_number)
    exaudio.mic_vol(volume_number)
end
--按下boot 停止播放
gpio.setup(0, add_volume, gpio.PULLDOWN, gpio.RISING)
gpio.debounce(0, 200, 1)

---------------------------------
---通过POWERKEY按键减小录音-------
---------------------------------

local function down_volume()
    volume_number = volume_number - 15
    log.info("减小录音音量",volume_number)
    exaudio.mic_vol(volume_number)
end

gpio.setup(gpio.PWR_KEY, down_volume, gpio.PULLUP, gpio.FALLING)
gpio.debounce(gpio.PWR_KEY, 200, 1)   -- 防抖，防止频繁触发

---------------------------------
---音频 task 初始化函数-----------
---------------------------------
local taskName = "task_audio"
local function audio_task()
    sys.wait(100)
    log.info("开始录制音频到文件")
    if exaudio.setup(audio_setup_param) then
        exaudio.record_start(audio_record_param)
    end
end

sys.taskInitEx(audio_task, taskName)
