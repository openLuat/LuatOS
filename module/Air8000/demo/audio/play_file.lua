--[[
@module  play_file
@summary 播放文件
@version 1.0
@date    2025.09.08
@author  梁健
@usage

本文件为播放文件的应用功能模块，核心业务逻辑为：
1、自动播放一个1.mp3音乐,
2、点powerkey 按键进行音频切换，点击boot 按键停止音频播放
3、点击boot 按键停止音频播放
本文件没有对外接口，直接在main.lua中require "play_file"就可以加载运行；
]]

exaudio = require("exaudio")
local taskName = "task_audio"

local audio_setup_param ={
    model= "es8311",          -- 音频编解码类型,可填入"es8311","es8211"
    i2c_id = 0,          -- i2c_id,可填入0，1 并使用pins 工具配置对应的管脚
    pa_ctrl = 162,         -- 音频放大器电源控制管脚
    dac_ctrl = 164,        --  音频编解码芯片电源控制管脚    
}

local function play_end(event)
    if event == exaudio.PLAY_DONE then
        log.info("播放完成",exaudio.is_end())
    end
end


local audio_play_param ={
    type= 0,                -- 播放类型，有0，播放文件，1.播放tts 2. 流式播放
                            -- 如果是播放文件,支持mp3,amr,wav格式
                            -- 如果是tts,内容格式见:https://wiki.luatos.com/chips/air780e/tts.html?highlight=tts
                            -- 流式播放，仅支持PCM 格式音频,如果是流式播放，则sampling_rate, sampling_depth,signed_or_unsigned 必填写
    content = "/luadb/1.mp3",          -- 如果播放类型为0时，则填入string 是播放单个音频文件,如果是表则是播放多段音频文件。
    cbfnc = play_end,            -- 播放完毕回调函数
}


---------------------------------
---通过BOOT 按键进行播放停止操作---
---------------------------------
local function stop_audio()
    log.info("停止播放")
    sys.sendMsg(taskName, MSG_KEY_PRESS, "STOP_AUDIO")
end
--按下boot 停止播放
gpio.setup(0, stop_audio, gpio.PULLDOWN, gpio.RISING)
gpio.debounce(0, 200, 1) -- 防抖，防止频繁触发

---------------------------------
---通过POWERKEY按键进行音频切换---
---------------------------------

local function next_audio()
    log.info("切换播放")
    sys.sendMsg(taskName, MSG_KEY_PRESS, "NEXT_AUDIO")
end

--按下powerkey 打断播放，播放优先级更高的音频
gpio.setup(gpio.PWR_KEY, next_audio, gpio.PULLUP, gpio.FALLING)
gpio.debounce(gpio.PWR_KEY, 200, 1) -- 防抖，防止频繁触发


---------------------------------
---------------主task------------
---------------------------------


local index_number = 1
local audio_path = nil
local function audio_task()
    log.info("开始播放音频文件")
    if exaudio.setup(audio_setup_param) then
        exaudio.play_start(audio_play_param) -- 仅仅支持task 中运行
        while true do
            local msg = sys.waitMsg(taskName, MSG_KEY_PRESS)   -- 等待按键触发
            if msg[2] ==  "NEXT_AUDIO" then  
                
                if index_number %2 == 0 then     --  切换音频路径
                    audio_path = "/luadb/1.mp3"
                else
                    audio_path = "/luadb/10.amr"
                end

                exaudio.play_start({type= 0, content = audio_path,cbfnc = play_end,priority = index_number})
                index_number= index_number +1 
            elseif msg[2] ==  "STOP_AUDIO" then
                exaudio.play_stop()
            end 
        end
    end
    
end
sys.taskInitEx(audio_task, taskName)
