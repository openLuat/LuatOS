--[[
@module  play_stream
@summary 流式播放
@version 1.0
@date    2025.09.08
@author  梁健
@usage

本文件为流式播放应用功能模块，核心业务逻辑为：
1、创建一个播放流式音频task（task_audio）
2、创建一个模拟获取流式音频的task（audio_get_data）
3、此task通过流式传输不断向audio_buff(zbuff)填入播放的音频
4、播放task 不断播放audio_buff(zbuff)的音频内容
5、使用powerkey 按键进行音量减小，点击boot 按键进行音量增加
本文件没有对外接口，直接在main.lua中require "play_stream"就可以加载运行；
]]

exaudio = require("exaudio")

local audio_buff       -- 存储音频数据的zbuff,使用方法见https://docs.openluat.com/osapi/core/zbuff/
local write_seek = 0   -- 写入zbuff 的指针位置
local read_seek = 0    -- 驱动zbuff 的指针位置

local zbuff_size = 61440      -- 申请内存的最大值，需要1024的倍数
local read_size = 4096        -- 除了最后一包数据，读写zbuff  都要按照1024倍数进行 
local file = nil              -- 文件句柄，打开文件后，将会被赋值

-- 音频初始化设置参数,exaudio.setup 传入参数
local audio_setup_param ={
    model= "es8311",          -- dac类型,可填入"es8311","es8211"
    i2c_id = 0,          -- i2c_id,可填入0，1 并使用pins 工具配置对应的管脚
    pa_ctrl = 162,         -- 音频放大器电源控制管脚
    dac_ctrl = 164,        --  音频编解码芯片电源控制管脚 
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
    file = io.open("/luadb/test.pcm", "rb")   -- 模拟流式播放音源，实际的音频数据来源也可以来自网络或者本地存储
    while true do
        local read_data = file:read(read_size)  --  读取文件，模拟流式音频源
        if read_data  == nil then
            file:close()                -- 模拟音频获取完毕，关闭音频文件
            break
        end
        exaudio.stream_play_write(read_data)  -- 流式写入音频数据
        sys.wait(100)                   -- 写数据需要留出事件给其他task 运行代码
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
    end
end

sys.taskInitEx(audio_task, taskName)
