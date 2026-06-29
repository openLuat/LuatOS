--[[
@module  play_file
@summary 播放文件
@version 1.0
@date    2026.06.26
@author  拓毅恒
@usage

注意：
1. Air8101使用内置DAC输出音频，无需外部音频编解码芯片
2. 需要固件版本>=V1018才可播放音频
3. 此功能需要用Air8101B来测试，Air8101不支持

本文件为播放文件的应用功能模块，核心业务逻辑为：
1、初始化后播放sample-6s.mp3
2、然后循环交替播放10.amr和sample-6s.mp3，播放间隔3秒
本文件没有对外接口，直接在main.lua中require "play_file"就可以加载运行；
]]

local exaudio = require("exaudio")

-- 音频初始化设置参数 (DAC模式)
local audio_setup_param ={
    model = "dac",            -- 音频编解码类型: "dac" 表示使用内置DAC
    
    pa_ctrl = 27,             -- 音频放大器电源控制管脚
    pa_on_level = 1,          -- PA打开电平
    pa_delay = 10            -- PA延时
}

-- 播放结束回调
local function play_end(event)
    if event == exaudio.PLAY_DONE then
        log.info("播放完成",exaudio.is_end())
    end
end

-- 音频播放的配置
local audio_play_param ={
    type= 0,                -- 播放类型，有0，播放文件，1.播放tts 2. 流式播放
                            -- 如果是播放文件,支持mp3,amr,wav格式
                            -- 如果是tts,内容格式见:https://docs.openluat.com/osapi/ext/exaudio/#tts_2
                            -- 流式播放，仅支持PCM 格式音频,如果是流式播放，则sampling_rate, sampling_depth,signed_or_unsigned 必填写
    content = "/luadb/sample-6s.mp3",          -- 如果播放类型为0时，则填入string 是播放单个音频文件,如果是表则是播放多段音频文件。
    cbfnc = play_end,            -- 播放完毕回调函数
}

---------------------------------
---通过BOOT 按键进行播放停止操作---
---------------------------------

-- 停止按键（Air8101 boot键为GPIO0）
local function stop_audio()
    log.info("停止播放")
    exaudio.play_stop(audio_play_param)
    log.info("播放停止成功")
end
-- 按下boot 停止播放
-- gpio.setup(0, stop_audio, gpio.PULLDOWN, gpio.RISING)
-- gpio.debounce(0, 200, 1)

---------------------------------
-----主task,处理播放音频---------
---------------------------------

local index_number = 1
local function audio_task()
    log.info("开始播放音频文件")
    if exaudio.setup(audio_setup_param) then
        exaudio.vol(70)            -- 喇叭音量
        exaudio.play_start(audio_play_param) -- 仅仅支持task 中运行
        while true do
            sys.wait(3000)
            if index_number % 2 == 0 then
                exaudio.play_start({type = 0, content = "/luadb/sample-6s.mp3", cbfnc = play_end})
            else
                exaudio.play_start({type = 0, content = "/luadb/10.amr", cbfnc = play_end})
            end
            index_number = index_number + 1
        end
    end
end
sys.taskInitEx(audio_task, "task_audio")
