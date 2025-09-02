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
        log.info("播放完成")
        exaudio.play_stop()
    end
end 
local audio_play_param ={
    type= 0,                -- 播放类型，有0，播放文件，1.播放tts 2. 流式播放
                            -- 如果是播放文件,支持mp3,amr,wav格式
                            -- 如果是tts,内容格式见:https://wiki.luatos.com/chips/air780e/tts.html?highlight=tts
                            -- 流式播放，仅支持PCM 格式音频,如果是流式播放，则Sampling_Rate, Sampling_Depth,Signed_or_Unsigned 必填写
    content = "/luadb/1.mp3",          -- 如果播放类型为0时，则填入string 是播放单个音频文件,如果是表则是播放多段音频文件。
    cbFnc = play_end,            -- 播放完毕回调函数
}

local function boot_key_cb()
    log.info("停止播放")
    sys.sendMsg(taskName, MSG_KEY_PRESS, "STOP_AUDIO")
end
--按下boot 停止播放
gpio.setup(0, boot_key_cb, gpio.PULLDOWN, gpio.RISING)
gpio.debounce(0, 200, 1)

local function power_key_cb()
    log.info("切换播放")
    sys.sendMsg(taskName, MSG_KEY_PRESS, "NEXT_AUDIO")
end

--按下powerkey 打断播放，播放优先级更高的音频
gpio.setup(gpio.PWR_KEY, power_key_cb, gpio.PULLUP, gpio.FALLING)
gpio.debounce(gpio.PWR_KEY, 200, 1)



local index_number = 1
local audio_path = nil
local function audio_task()
    log.info("开始播放音频文件")
    if exaudio.setup(audio_setup_param) then
        exaudio.play_start(audio_play_param) -- 仅仅支持task 中运行
        while true do
            local msg = sys.waitMsg(taskName, MSG_KEY_PRESS)
            if msg[2] ==  "NEXT_AUDIO" then  -- true powerkey false boot key
                if index_number %2 == 0 then
                    audio_path = "/luadb/1.mp3"
                else
                    audio_path = "/luadb/10.amr"
                end
                exaudio.play_start({type= 0, content = audio_path,cbFnc = play_end,priority = index_number})
                index_number= index_number +1 
            elseif msg[2] ==  "STOP_AUDIO" then
                exaudio.play_stop()
            end 
        end
    end
    
end
sys.taskInitEx(audio_task, taskName)
