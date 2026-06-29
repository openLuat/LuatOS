--[[
@module  play_tts
@summary 文字转语音
@version 1.0
@date    2026.06.26
@author  拓毅恒
@usage

注意：
1. Air8101使用内置DAC输出音频，无需外部音频编解码芯片
2. 需要固件版本>=V1018才可播放音频
3. 此功能需要用Air8101B来测试，Air8101不支持

本文件为TTS播放应用功能模块，核心业务逻辑为：
1、初始化后播默认TTS
2、然后循环播5种音色的TTS，间隔3秒
本文件没有对外接口，直接在main.lua中require "play_tts"就可以加载运行；
]]

local exaudio = require("exaudio")

-- 音频初始化设置参数 (DAC模式)
local audio_setup_param ={
    model = "dac",            -- 音频编解码类型: "dac" 表示使用内置DAC
    
    pa_ctrl = 27,             -- 音频放大器电源控制管脚
    pa_on_level = 1,          -- PA打开电平
    pa_delay = 10            -- PA延时
}

-- TTS音色列表（关于TTS音色设置请见: https://docs.openluat.com/osapi/ext/exaudio/#tts_2）
local tts_voices = {
    "[m51]支付宝到账,1千万元",   -- 许久
    "[m52]支付宝到账,1千万元",   -- 许多
    "[m53]支付宝到账,1千万元",   -- 晓萍
    "[m54]支付宝到账,1千万元",   -- 唐老鸭
    "[m55]支付宝到账,1千万元",   -- 许宝宝
}

local function play_end(event)
    if event == exaudio.PLAY_DONE then
        log.info("播放完成",exaudio.is_end())
        exaudio.play_stop({type = 1})
    end
end

local audio_play_param ={
    type = 1,                -- 播放类型: 1=播放TTS
    content = "支付宝到账,1千万元", -- 需要播放的内容
    cbfnc = play_end, -- 播放完毕回调函数
}

---------------------------------
-----主task,处理播放TTS----------
---------------------------------

local function audio_task()
    log.info("开始播放TTS")
    if exaudio.setup(audio_setup_param) then
        exaudio.vol(50)
        exaudio.play_start(audio_play_param)
        while not exaudio.is_end() do sys.wait(100) end
        
        -- 循环演示播放5种音色，间隔3秒
        local idx = 1
        while true do
            sys.wait(3000)
            exaudio.play_start({type = 1, content = tts_voices[idx], cbfnc = play_end})
            while not exaudio.is_end() do sys.wait(100) end
            idx = (idx % #tts_voices) + 1
        end
    end
end
sys.taskInitEx(audio_task, "task_audio")
