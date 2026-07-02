--[[
@module  play_stream
@summary 流式播放
@version 1.2
@date    2026.06.26
@author  拓毅恒
@usage

注意：
1. Air8101使用内置DAC输出音频，无需外部音频编解码芯片
2. 需要固件版本>=V1018才可播放音频

本文件为流式播放应用功能模块，核心业务逻辑为：
1、初始化后启动流式播放
2、读取test.pcm文件数据，通过exaudio.play_stream_write写入播放
3、播放task不断播放传入流式音频
本文件没有对外接口，直接在main.lua中require "play_stream"就可以加载运行；
]]

local exaudio = require("exaudio")

-- 音频初始化设置参数 (DAC模式)
local audio_setup_param ={
    model = "dac",            -- 音频编解码类型: "dac" 表示使用内置DAC
    
    pa_ctrl = 27,             -- 音频放大器电源控制管脚
    pa_on_level = 1,          -- PA打开电平
    pa_delay = 10            -- PA延时
}

-- 播放完成回调
local function play_end(event)
    if event == exaudio.PLAY_DONE then
        log.info("播放完成",exaudio.is_end())

    end
end 

-- 流式播放音频播放的配置
local audio_play_param ={
    codec_id = 0,                   -- 编解码器ID：0=RAW/PCM, 1=WAV, 2=AMR_NB, 3=AMR_WB, 4=TTS, 5=MP3
    type= 2,                -- 播放类型，如果是流式播放，则sampling_rate, sampling_depth,signed_or_unsigned 必填写
    cbfnc = play_end,            -- 播放完毕回调函数
    sampling_rate = 16000,  -- 采样率,仅为流式播放起作用
    sampling_depth =  16,   -- 采样位位深,仅流式播放的时候才有作用
    signed_or_unsigned = true  -- PCM 的数据是否有符号，仅为流式播放起作用
}

---------------------------------
---------模拟获取音频task---------
---------------------------------
local function audio_get_data()
    -- 等待播放初始化完成
    sys.waitUntil("AUDIO_READY")
    
    log.info("开始流式获取音频数据")
    local file = io.open("/luadb/test.pcm", "rb")   -- 模拟流式播放音源，实际的音频数据来源也可以来自网络或者本地存储

    -- 获取推荐的缓冲区大小
    local buffer_size = exaudio.get_stream_buffer_size() or 4096
    log.info("流式播放缓冲区大小", buffer_size)

    while true do
        local read_data = file:read(buffer_size)  --  读取文件，模拟流式音频源,需要1024 的倍数
        if read_data  == nil then
            file:close()                -- 模拟音频获取完毕，关闭音频文件
            -- 本API需要用V2024固件！！！ 
            -- 写入数据完毕后，通知多媒体通道已经没有更多数据需要播放了
            -- 开启后可以有效的降低pop音
            exaudio.finish()
            break
        end

        -- 如果读取的数据小于缓冲区大小，补充静音数据
        if #read_data < buffer_size then
            read_data = read_data .. string.rep("\0", buffer_size - #read_data)
        end

        exaudio.play_stream_write(read_data)  -- 流式写入音频数据
        sys.wait(20)                   -- 写数据需要留出时间给其他task 运行代码
    end
end

sys.taskInitEx(audio_get_data, "audio_get_data")


---------------------------------
------------通过主task------------
---------------------------------
local taskName = "task_audio"
local function audio_task()
    log.info("开始流式播报")
    if exaudio.setup(audio_setup_param) then
        if exaudio.play_start(audio_play_param) then
            log.info("播放状态",exaudio.is_end())
            sys.publish("AUDIO_READY")  -- 通知数据task可以开始读取数据
        else
            log.error("流式播放启动失败")
        end
    end
end

sys.taskInitEx(audio_task, taskName)
