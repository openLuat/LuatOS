--[[
@module  play_stream
@summary 流式播放
@version 1.2
@date    2026.04.21
@author  拓毅恒
@usage

本文件为流式播放应用功能模块，核心业务逻辑为：
1、创建一个播放流式音频task（task_audio）
2、创建一个模拟获取流式音频的task（audio_get_data）
3、此task通过流式传输不断向exaudio.play_stream_write填入播放的音频
4、播放task 不断播放传入流式音频
5、短按PWRKEY (< 1s) 减小音量，长按PWRKEY (≥ 1s) 增大音量

本文件没有对外接口，直接在main.lua中require "play_stream"就可以加载运行；

硬件版本由 main.lua 中的 _G.HARDWARE_ENV 全局变量统一控制
- Air8201G: PWRKEY单按键, pa_ctrl=25
- Air8201H: PWRKEY单按键, pa_ctrl=23, ES8311需1.8V电压
]]

exaudio = require("exaudio")

-- 根据版本号自适应设置dac_delay
local set_dac_delay = 0
local version = rtos.version()
local version_num = 0
if version then
    -- 从版本号字符串中提取数字部分
    local num_str = version:match("V(%d+)")
    if num_str then
        version_num = tonumber(num_str)
    end
end

if version_num and version_num >= 2026 then
    -- 固件版本≥V2026，dac_delay单位为100ms
    set_dac_delay = 6
else
    -- 固件版本＜V2026，dac_delay单位为1ms
    set_dac_delay = 600
end

-- 音频初始化设置参数,exaudio.setup 传入参数
local audio_setup_param ={
    model= "es8311",          -- dac类型,可填入"es8311","tm8211"
    i2c_id = 0,          -- i2c_id,可填入0，1 并使用pins 工具配置对应的管脚
    
    -- 【注意：固件版本＜V2026，这里单位为1ms，这里填600，否则可能第一个字播不出来】
    dac_delay = set_dac_delay,            -- DAC启动前冗余时间
    
    pa_ctrl = (HARDWARE_ENV == "G") and 25 or 23,         -- 音频放大器电源控制管脚, G:25, H:23
    dac_ctrl = 2,        --  音频编解码芯片电源控制管脚

    audio_mode = "new", -- 音频框架版本选择: "auto"用默认, "new"新框架, "old"旧框架
    codec_voltage = (HARDWARE_ENV == "G") and 1 or 0 -- ES8311电压: 0=1.8V, 1=3.3V
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
                            -- 如果是tts,内容格式见:https://docs.openluat.com/osapi/ext/exaudio/#tts_2
                            -- 流式播放，仅支持PCM 格式音频,如果是流式播放，则sampling_rate, sampling_depth,signed_or_unsigned 必填写
    cbfnc = play_end,            -- 播放完毕回调函数
    sampling_rate = 16000,  -- 采样率,仅为流式播放起作用
    sampling_depth =  16,   -- 采样位位深,仅流式播放的时候才有作用
    signed_or_unsigned = true  -- PCM 的数据是否有符号，仅为流式播放起作用
}

-------------------------------------------
---PWRKEY单按键：短按音量- / 长按音量+---
-------------------------------------------
local volume_number = 50
local pwrkey_press_time = 0         -- 记录按下时刻（tick）
local KEY_LONG_PRESS_MS = 1000      -- 长按阈值：1秒

local function pwrkey_handler()
    local key_level = gpio.get(gpio.PWR_KEY)
    if key_level == 0 then
        -- 下降沿：按键按下
        pwrkey_press_time = mcu.ticks()
    else
        -- 上升沿：按键松开
        if pwrkey_press_time > 0 then
            local duration = mcu.ticks() - pwrkey_press_time
            if duration >= KEY_LONG_PRESS_MS then
                -- 长按：增大音量
                volume_number = volume_number + 20
                if volume_number > 100 then volume_number = 100 end
                log.info("长按PWRKEY，增大音量", volume_number)
            else
                -- 短按：减小音量
                volume_number = volume_number - 15
                if volume_number < 0 then volume_number = 0 end
                log.info("短按PWRKEY，减小音量", volume_number)
            end
            exaudio.vol(volume_number)
            pwrkey_press_time = 0
        end
    end
end

-- PWRKEY 同时检测上升沿和下降沿
gpio.setup(gpio.PWR_KEY, pwrkey_handler, gpio.PULLUP, gpio.BOTH)
gpio.debounce(gpio.PWR_KEY, 200, 1)   -- 防抖，防止频繁触发

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
        exaudio.play_start(audio_play_param)
        log.info("播放状态",exaudio.is_end())
        sys.publish("AUDIO_READY")  -- 通知数据task可以开始读取数据
    else
        log.error("流式播放启动失败")
    end
end

sys.taskInitEx(audio_task, taskName)
