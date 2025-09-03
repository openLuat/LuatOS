exaudio = require("exaudio")

local audio_setup_param ={
    model= "es8311",          -- dac类型,可填入"es8311","es8211"
    i2c_id = 0,          -- i2c_id,可填入0，1 并使用pins 工具配置对应的管脚
    pa_ctrl = 162,         -- 音频放大器电源控制管脚
    dac_ctrl = 164,        --  音频编解码芯片电源控制管脚 
}
local  index = 4096         --  每次播放的数据长度不能小于1024,并且除去最后一包数据，数据长度都要为1024 的倍数
local f = io.open("/luadb/test.pcm", "rb")   -- 模拟流式播放音源，实际的音频数据来源也可以来自网络或者本地存储
local function audio_need_more_data()
    if f then 
        return   f:read(index)
    end
end 

local function play_end(event)
    if event == exaudio.PLAY_DONE then
        log.info("播放完成",exaudio.is_end())
        if f then 
            return   f:close()
        end
    end
end 

local audio_play_param ={
    type= 2,                -- 播放类型，有0，播放文件，1.播放tts 2. 流式播放
                            -- 如果是播放文件,支持mp3,amr,wav格式
                            -- 如果是tts,内容格式见:https://wiki.luatos.com/chips/air780e/tts.html?highlight=tts
                            -- 流式播放，仅支持PCM 格式音频,如果是流式播放，则Sampling_Rate, Sampling_Depth,Signed_or_Unsigned 必填写
    content = audio_need_more_data,          -- 如果播放类型为0时，则填入string 是播放单个音频文件,如果是表则是播放多段音频文件。
                            -- 如果播放tts 则填入要播放的内容。
                            -- 如果为2，流式播放，则填入音频回调函数
    cbFnc = play_end,            -- 播放完毕回调函数
    sampling_Rate = 16000,  -- 采样率,仅为流式播放起作用
    sampling_Depth =  16,   -- 采样位位深,仅流式播放的时候才有作用
    signed_or_Unsigned = true  -- PCM 的数据是否有符号，仅为流式播放起作用
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
--按下boot 停止播放
gpio.setup(0, add_volume, gpio.PULLDOWN, gpio.RISING)
gpio.debounce(0, 200, 1)

---------------------------------
---通过POWERKEY按键减小音量---
---------------------------------

local function down_volume()
    volume_number = volume_number - 15
    log.info("减小音量",volume_number)
    exaudio.vol(volume_number)
end

gpio.setup(gpio.PWR_KEY, down_volume, gpio.PULLUP, gpio.FALLING)
gpio.debounce(gpio.PWR_KEY, 200, 1)   -- 防抖，防止频繁触发


---------------------------------
---通过主task---
---------------------------------
local taskName = "task_audio"
local function audio_task()
    log.info("开始流式播报")
    if exaudio.setup(audio_setup_param) then
        exaudio.play_start(audio_play_param)
    end
end

sys.taskInitEx(audio_task, taskName)
