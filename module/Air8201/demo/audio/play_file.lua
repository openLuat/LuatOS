--[[
@module  play_file
@summary 播放文件
@version 1.0
@date    2025.09.08
@author  陈媛媛
@usage


本文件为播放文件的应用功能模块，核心业务逻辑为：
1、自动播放一个sample-6s.mp3音乐
2、短按PWRKEY (< 1s)：切换音频
3、长按PWRKEY (≥ 1s)：停止音频播放

本文件没有对外接口，直接在main.lua中require "play_file"就可以加载运行；

硬件版本由 main.lua 中的 _G.HARDWARE_ENV 全局变量统一控制
- Air8201G: PWRKEY单按键, pa_ctrl=25
- Air8201H: PWRKEY单按键, pa_ctrl=23, ES8311需1.8V电压
]]

local exaudio = require "exaudio"
local taskName = "task_audio"

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
    model= "es8311",          -- 音频编解码类型,可填入"es8311","tm8211"
    i2c_id = 0,          -- i2c_id,可填入0，1 并使用pins 工具配置对应的管脚
    
    -- 【注意：固件版本＜V2026，这里单位为1ms，这里填600，否则可能第一个字播不出来】
    dac_delay = set_dac_delay,            -- DAC启动前冗余时间
    
    pa_ctrl = (HARDWARE_ENV == "G") and 25 or 23,         -- 音频放大器电源控制管脚, G:25, H:23
    dac_ctrl = 2,        --  音频编解码芯片电源控制管脚
    
    audio_mode = "new", -- 音频框架版本选择: "auto"用默认, "new"新框架, "old"旧框架
    codec_voltage = (HARDWARE_ENV == "G") and 1 or 0 -- ES8311电压: 0=1.8V, 1=3.3V
}

--  播放结束回调
local function play_end(event)
    if event == exaudio.PLAY_DONE then
        log.info("播放完成",exaudio.is_end())
    end
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

-------------------------------------------
---PWRKEY单按键：短按切换 / 长按停止---
-------------------------------------------
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
                log.info("长按PWRKEY，停止播放")
                sys.sendMsg(taskName, MSG_KEY_PRESS, "STOP_AUDIO")
            else
                log.info("短按PWRKEY，切换播放")
                sys.sendMsg(taskName, MSG_KEY_PRESS, "NEXT_AUDIO")
            end
            pwrkey_press_time = 0
        end
    end
end

-- PWRKEY 同时检测上升沿和下降沿
gpio.setup(gpio.PWR_KEY, pwrkey_handler, gpio.PULLUP, gpio.BOTH)
gpio.debounce(gpio.PWR_KEY, 200, 1) -- 防抖，防止频繁触发


---------------------------------
-----主task,处理播放音频---------
---------------------------------


local index_number = 1
local audio_path = nil
local function audio_task()
    log.info("开始播放音频文件")
    if exaudio.setup(audio_setup_param) then
        exaudio.vol(70)            -- 喇叭音量
        exaudio.play_start(audio_play_param) -- 仅仅支持task 中运行
        while true do
            local msg = sys.waitMsg(taskName, MSG_KEY_PRESS)   -- 等待按键触发
            if msg[2] ==  "NEXT_AUDIO" then  
                
                if index_number %2 == 0 then     --  切换音频路径
                    audio_path = "/luadb/sample-6s.mp3"
                else
                    audio_path = "/luadb/10.amr"
                end

                exaudio.play_start({type= 0, content = audio_path,cbfnc = play_end,priority = index_number})
                index_number= index_number +1 
            elseif msg[2] ==  "STOP_AUDIO" then
                exaudio.play_stop(audio_play_param)
            end 
        end
    end
    
end
sys.taskInitEx(audio_task, taskName)
