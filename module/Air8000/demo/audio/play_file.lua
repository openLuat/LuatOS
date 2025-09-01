exaudio = require("exaudio")

local audio_setup_param ={
    model= "es8311",          -- 音频编解码类型,可填入"es8311","es8211"
    i2c_id = 0,          -- i2c_id,可填入0，1 并使用pins 工具配置对应的管脚
    pa_ctrl = 162,         -- 音频放大器电源控制管脚
    dac_ctrl = 164,        --  音频编解码芯片电源控制管脚
    -- dac_delay = 3,        -- 在DAC启动前插入的冗余时间，单位100ms,控制pop 音
    -- pa_delay = 100,      -- 在DAC启动后，延迟多长时间打开PA，单位1ms,控制pop 音
    -- dac_time_delay = 600,    -- 音频播放完毕时，PA与DAC关闭的时间间隔，单位1ms,控制pop 音
    -- pa_on_level = 1,           -- PA打开电平 1 高电平 0 低电平        
}
local function play_end(event)
    if event == exaudio.PLAY_DONE then
        log.info("播放完成")
        
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



local taskName = "task_audio"
local function audio_task()
    log.info("开始播放音频文件")
    if exaudio.setup(audio_setup_param) then
        exaudio.play_start(audio_play_param)
        sys.wait(2000)
        --exaudio.play_start({type= 0,content = "/luadb/1.mp3",priority = 1})     -- 可对之前的播放进行打断
    end
    
end

sysplus.taskInitEx(audio_task, taskName)
