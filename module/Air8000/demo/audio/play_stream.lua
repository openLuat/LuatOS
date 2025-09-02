exaudio = require("exaudio")

local audio_setup_param ={
    model= "es8311",          -- dac类型,可填入"es8311","es8211"
    i2c_id = 0,          -- i2c_id,可填入0，1 并使用pins 工具配置对应的管脚
    pa_ctrl = 162,         -- 音频放大器电源控制管脚
    dac_ctrl = 164,        --  音频编解码芯片电源控制管脚
    -- dac_delay = 3,        -- 在DAC启动前插入的冗余时间，单位100ms
    -- pa_delay = 100,      -- 在DAC启动后，延迟多长时间打开PA，单位1ms
    -- dac_time_delay = 600,    -- 音频播放完毕时，PA与DAC关闭的时间间隔，单位1ms
    -- bits_per_sample = 16,  -- codec 采样位数
    -- pa_on_level = 1,           -- PA打开电平 1 高电平 0 低电平        
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
        log.info("播放完成")
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
    --                         --  0-播放成功结束
    --                         --  1-播放出错
    --                         --  2-播放优先级不够，没有播放
    --                         --  3-传入的参数出错，没有播放
    --                         --  4-被新的播放请求中止
    --                         --  5-调用audio.stop接口主动停止
    -- priority = 0,           -- 音频优先级，数值越大，优先级越高
    --                         -- 优先级高的播放请求会终止优先级低的播放
    --                         -- 相同优先级的播放请求，播放策略参考：audio.setStrategy接口
    sampling_Rate = 16000,  -- 采样率,仅为流式播放起作用
    sampling_Depth =  16,   -- 采样位位深,仅流式播放的时候才有作用
    signed_or_Unsigned = true  -- PCM 的数据是否有符号，仅为流式播放起作用
}


local taskName = "task_audio"
local function audio_task()
    log.info("开始流式播报")
    if exaudio.setup(audio_setup_param) then
        exaudio.play_start(audio_play_param)
    end
end

sys.taskInitEx(audio_task, taskName)
