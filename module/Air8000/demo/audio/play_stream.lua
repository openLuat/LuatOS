--[[
@module  play_stream
@summary 流式播放
@version 1.1
@date    2026.01.11
@author  王世豪
@usage

本文件为流式播放应用功能模块，核心业务逻辑为：
1、创建一个播放流式音频task（task_audio）
2、创建一个模拟获取流式音频的task（audio_get_data）
3、此task通过流式传输不断向exaudio.play_stream_write填入播放的音频
4、播放task 不断播放传入流式音频
5、使用powerkey 按键进行音量减小，点击boot 按键进行音量增加
本文件没有对外接口，直接在main.lua中require "play_stream"就可以加载运行；
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
}

-- 播放完成回调
local function play_end(event)
    if event == exaudio.PLAY_DONE then
        log.info("播放完成",exaudio.is_end())

    end
end 

-- 流式播放音频播放的配置
local audio_play_param ={
    type= 2,                -- 播放类型，有0，播放文件，1.播放tts 2. 流式播放
                            -- 如果是播放文件,支持mp3,amr,wav格式
                            -- 如果是tts,内容格式见:https://wiki.luatos.com/chips/air780e/tts.html?highlight=tts
                            -- 流式播放，仅支持PCM 格式音频,如果是流式播放，则sampling_rate, sampling_depth,signed_or_unsigned 必填写
    cbfnc = play_end,            -- 播放完毕回调函数
    sampling_rate = 16000,  -- 采样率,仅为流式播放起作用
    sampling_depth =  16,   -- 采样位位深,仅流式播放的时候才有作用
    signed_or_unsigned = true  -- PCM 的数据是否有符号，仅为流式播放起作用
}

---------------------------------
---通过BOOT 按键增大音量---
---------------------------------
local volume_number = 50 
local function add_volume()
    volume_number = volume_number + 20
    log.info("增大音量",volume_number)
    exaudio.vol(volume_number)
end

gpio.setup(0, add_volume, gpio.PULLDOWN, gpio.RISING)
gpio.debounce(0, 200, 1)

---------------------------------
---通过POWERKEY按键减小音量-------
---------------------------------

local function down_volume()
    volume_number = volume_number - 15
    log.info("减小音量",volume_number)
    exaudio.vol(volume_number)
end

gpio.setup(gpio.PWR_KEY, down_volume, gpio.PULLUP, gpio.FALLING)
gpio.debounce(gpio.PWR_KEY, 200, 1)   -- 防抖，防止频繁触发


---------------------------------
---------模拟获取音频task---------
---------------------------------
local function audio_get_data()
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
        sys.wait(20)                   -- 写数据需要留出事件给其他task 运行代码
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
        exaudio.play_start(audio_play_param)
        log.info("播放状态",exaudio.is_end())
    end
end

sys.taskInitEx(audio_task, taskName)
