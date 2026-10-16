--[[
@module  play_file
@summary 播放文件
@version 1.0
@date    2026.07.02
@author  拓毅恒
@usage

注意：
1. Air1601使用内置DAC输出音频，无需外部音频编解码芯片
2. 需要固件版本>=V1024才可播放音频

本文件为播放文件的应用功能模块，核心业务逻辑为：
1、初始化后播放sample-6s.mp3
2、然后循环交替播放10.amr和sample-6s.mp3，播放间隔3秒
本文件没有对外接口，直接在main.lua中require "play_file"就可以加载运行；
]]

local exaudio = require "exaudio"

-- 硬件环境配置说明
-- 本Demo支持以下硬件环境，请根据实际使用情况修改HARDWARE_ENV变量：
--   "AIR1601_V1_1"  - Air1601 V1.1开发板：PA_EN = IO12
--   "AIR1601_V1_2"  - Air1601 V1.2开发板：PA_EN = IO73
--   "AIR1603_8607"  - Air1603 / 8607开发板：PA_EN = IO73
-- 详细说明请参考本目录下的readme.md文件
HARDWARE_ENV = "AIR1603_8607"  -- Air1601 V1.2开发板(PA_EN=IO73)。使用8607开发板请改为"AIR1603_8607"

-- PA脚映射：不同板型/版本的功放使能脚不同
local pa_pin_map = {
    AIR1601_V1_1 = 12,
    AIR1601_V1_2 = 73,
    AIR1603_8607 = 73,
}
local pa_pin = pa_pin_map[HARDWARE_ENV] or 73

-- 音频初始化设置参数 (DAC模式)
local audio_setup_param ={
    model = "dac",            -- 音频编解码类型: "dac" 表示使用内置DAC
    
    pa_ctrl = pa_pin,         -- 音频放大器电源控制管脚，Air1601_V1.1开发板-IO12，Air1601_V1.2/8607开发板-IO73
    pa_on_level = 1,          -- PA打开电平，0=低电平使能，1=高电平使能
    dac_delay = 6,            -- DAC启动前冗余时间，单位为100ms
}

--  播放结束回调
local function play_end(event)
    if event == exaudio.PLAY_DONE then
        log.info("播放完成",exaudio.is_end())
    end
    sys.publish("AUDIO_PLAY_DONE", event)  -- 通知播放任务：本首已结束，可切下一首
end

--  音频播放的配置
local audio_play_param ={
    type= 0,                -- 播放类型，有0，播放文件，1.播放tts 2. 流式播放
                            -- 如果是播放文件,支持mp3,amr,wav格式
                            -- 如果是tts,内容格式见:https://docs.openluat.com/osapi/ext/exaudio/#tts_2
                            -- 流式播放，支持PCM/MP3/AMR/WAV格式,如果是流式播放，则sampling_rate, sampling_depth,signed_or_unsigned 必填写
    content = "/luadb/sample-6s.mp3",          -- 如果播放类型为0时，则填入string 是播放单个音频文件,如果是表则是播放多段音频文件。
    cbfnc = play_end,            -- 播放完毕回调函数
}

---------------------------------
-----主task,处理播放音频---------
---------------------------------

local index_number = 0
local function audio_task()
    log.info("开始播放音频文件")
    if exaudio.setup(audio_setup_param) then
        exaudio.vol(70)            -- 喇叭音量
        while true do
            -- 交替播放 mp3 / amr
            local content = (index_number % 2 == 0) and "/luadb/sample-6s.mp3" or "/luadb/10.amr"
            log.info("audio_task", "开始播放", content)
            exaudio.play_start({type = 0, content = content, cbfnc = play_end})
            -- 严格等待本次播放结束回调，避免固定 sleep 打断 6s 的 mp3
            sys.waitUntil("AUDIO_PLAY_DONE", 30000)  -- 30s 超时兜底，防止异常死等
            index_number = index_number + 1
            sys.wait(300)          -- 两首间留间隔，防连播爆音
        end
    end
end
sys.taskInitEx(audio_task, "task_audio")
