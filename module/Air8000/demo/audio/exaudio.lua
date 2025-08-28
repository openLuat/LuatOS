--[[
@module exaudio
@summary exaudio扩展库
@version 1.0
@date    2025.08.08
@author  梁健
@usage
]]
local exaudio = {}

local i2s_id = 0            -- i2s_id 0
local i2s_mode = 0          -- i2s模式 0 主机 1 从机
local i2s_sample_rate = 16000   -- 采样率
local i2s_channel_format = i2s.MONO_R   -- 声道, 0 左声道, 1 右声道, 2 立体声
local i2s_communication_format = i2s.MODE_LSB   -- 格式, 可选MODE_I2S, MODE_LSB, MODE_MSB
local i2s_channel_bits = 16     -- 声道的BCLK数量
local multimedia_id = 0         -- 音频通道 0
local voice_vol = 55
local mic_vol = 80
local power_on_level = 1
local MSG_PD = "playDone"   -- 播放完成所有数据
exaudio.PLAY_DONE = 1

local audio_setup_param ={
    model= "es8311",          -- dac类型,可填入"es8311","es8211"
    i2c_id = 0,          -- i2c_id,可填入0，1 并使用pins 工具配置对应的管脚
    pa_ctrl = 0,         -- 音频放大器电源控制管脚
    dac_ctrl = 0,        --  音频编解码芯片电源控制管脚
    dac_delay = 3,        -- 在DAC启动前插入的冗余时间，单位100ms
    pa_delay = 100,      -- 在DAC启动后，延迟多长时间打开PA，单位1ms
    dac_time_delay = 600,    -- 音频播放完毕时，PA与DAC关闭的时间间隔，单位1ms
    bits_per_sample = 16,  -- codec 采样位数
    pa_on_level = 1,           -- PA打开电平 1 高电平 0 低电平        
}

local audio_play_param ={
    type= 0,                -- 播放类型，有0，播放文件，1.播放tts 2. 流式播放
                            -- 如果是播放文件,支持mp3,amr,wav格式
                            -- 如果是tts,内容格式见:https://wiki.luatos.com/chips/air780e/tts.html?highlight=tts
                            -- 流式播放，仅支持PCM 格式音频,如果是流式播放，则Sampling_Rate, Sampling_Depth,Signed_or_Unsigned 必填写
    content = nil,          -- 如果播放类型为0时，则填入string 是播放单个音频文件,如果是表则是播放多段音频文件。
                            -- 如果播放tts 则填入要播放的内容。
                            -- 如果为2，流式播放，则填入音频回调函数
    cbFnc = nil,            -- 播放完毕回调函数
                            --  0-播放成功结束
                            --  1-播放出错
                            --  2-播放优先级不够，没有播放
                            --  3-传入的参数出错，没有播放
                            --  4-被新的播放请求中止
                            --  5-调用audio.stop接口主动停止
    priority = 0,           -- 音频优先级，数值越大，优先级越高
                            -- 优先级高的播放请求会终止优先级低的播放
                            -- 相同优先级的播放请求，播放策略参考：audio.setStrategy接口
    sampling_Rate = 16000,  -- 采样率,仅为流式播放起作用
    sampling_Depth =  16,   -- 采样位位深,仅流式播放的时候才有作用
    signed_or_Unsigned = true  -- PCM 的数据是否有符号，仅为流式播放起作用
}

local audio_record_param ={
    format= 0,              -- 录制格式，有AMR,AMR_WB,PCM_8000,PCM_16000,PCM_24000,PCM_32000
    time = 5,               -- 录制时间,单位(秒)
    path = nil,             -- 如果填入的是字符串，则表示是文件路径，录音会传输到这个路径里
                            -- 如果填入的是函数，则表示是流式录音，录音的数据会传输到此函数内
}

local function audio_callback(id, event)
    log.info("audio_callback,event:",event,audio.MORE_DATA,audio.DONE,audio.RECORD_DATA,audio.RECORD_DONE)
    if event  == audio.MORE_DATA then
        audio_play_param.content()
    elseif audio.DONE  then
        if audio_play_param.cbFnc ~= nil  then
            audio_play_param.cbFnc(exaudio.PLAY_DONE)
        end
        sys.publish(MSG_PD)
        log.error("audio_callback 1111")
    end
end

local function audio_setup()
    local result,data
    sys.wait(100)

    i2c.setup(audio_setup_param.i2c_id,i2c.FAST)
    
    result,data= i2s.setup(i2s_id, i2s_mode, i2s_sample_rate, audio_setup_param.bits_per_sample, i2s_channel_format, i2s_communication_format,i2s_channel_bits)
    if not result then     --  设置音频参数错误
        return result
    end

    audio.config(multimedia_id, audio_setup_param.pa_ctrl, audio_setup_param.pa_on_level, audio_setup_param.dac_delay, audio_setup_param.pa_delay, audio_setup_param.dac_ctrl, power_on_level, audio_setup_param.dac_time_delay)
    audio.setBus(multimedia_id, audio.BUS_I2S,{chip = audio_setup_param.model,i2cid = audio_setup_param.i2c_id , i2sid = i2s_id, voltage = audio.VOLTAGE_1800})	--通道0的硬件输出通道设置为I2S

    audio.vol(multimedia_id, voice_vol)
    audio.micVol(multimedia_id, mic_vol)
    audio.pm(multimedia_id,audio.RESUME)
    sys.wait(100)
    audio.on(multimedia_id, audio_callback)
    return result
end




function exaudio.setup(audioConfigs)
    if audioConfigs.model == nil  and (audioConfigs.model ~= "es8311"  or audioConfigs.model ~= "es8211") then   -- codec 名称必现写
        log.error("没有填写codec 名称,或者不是es8311,es8211")
        return false      
    else
        audio_setup_param.model = audioConfigs.model
    end

    if audioConfigs.model  == "es8311"  then
        if  ( audioConfigs.i2c_id == nil  or type(audioConfigs.i2c_id) ~= "number"  )then   
             -- 如果是8311 ，则必须写出i2c 地址
            log.error("当前使用8311 codec, 但没有填写i2c id")
            return false
        else
            audio_setup_param.i2c_id = audioConfigs.i2c_id
        end
    end

    if audioConfigs.pa_ctrl == nil then   -- pa_ctrl PA 的控制管脚必须填写
        log.error("pa 控制为空")
        return false
    else
        audio_setup_param.pa_ctrl = audioConfigs.pa_ctrl
    end


    if audioConfigs.dac_ctrl ~= nil  and type(audioConfigs.dac_ctrl) == "number" then   -- 编解码芯片控制管脚不需要必填
        audio_setup_param.dac_ctrl = audioConfigs.dac_ctrl
    end

    if audioConfigs.dac_delay ~= nil  and type(audioConfigs.dac_delay) == "number" then   -- 在DAC启动前插入的冗余时间 ，非必填
        audio_setup_param.dac_delay = audioConfigs.dac_delay
    end

    if audioConfigs.pa_delay ~= nil  and type(audioConfigs.pa_delay) == "number" then   -- 在DAC启动后，延迟多长时间打开PA ，非必填
        audio_setup_param.pa_delay = audioConfigs.padelay
    end


    if audioConfigs.dac_time_delay ~= nil  and type(audioConfigs.dac_time_delay) == "number" then   
        audio_setup_param.dac_time_delay = audioConfigs.dac_time_delay
    end

    if audioConfigs.bits_per_sample ~= nil  and type(audioConfigs.bits_per_sample) == "number" then   
        audio_setup_param.bits_per_sample = audioConfigs.bits_per_sample
    end
    
    if audioConfigs.pa_on_level ~= nil  and type(audioConfigs.pa_on_level) == "number" then  
        audio_setup_param.pa_on_level = audioConfigs.pa_on_level
    end

    return audio_setup()    -- 返回初始化结果
end

function exaudio.write_datablock(data)
    -- local block_lens = 256
    -- if #data % block_lens  ~= 0 then
    --     log.info("write_datablock0",#data,block_lens - #data % block_lens)
    --     data = data .. string.rep("\255", block_lens - #data % block_lens) 
    --     log.info("write_datablock1",#data)
    -- end
    audio.write(multimedia_id,data)    
end

function exaudio.play_start(playConfigs)
    if playConfigs.type == nil  and type(playConfigs.type)  ~= "number" then   
        log.error("type 必须填写,也必须为数值,0:播放文件,1: 播放TTS,2:流式播放")
        return false      
    else
        audio_play_param.type = playConfigs.type
    end

    if playConfigs.priority ~= nil and type(playConfigs.priority) == "number" then  -- 如果当前的播放优先级比历史优先级高，则停止之前的播放
        if playConfigs.priority >= audio_play_param.priority then   
            log.error("playConfigs.priority 插入高优先级音频")
            audio.play(multimedia_id)
            log.error("playConfigs.priority 插入高优先级音频 1111")
            sys.waitUntil(MSG_PD)
            log.error("playConfigs.priority 插入高优先级音频 after 1111")
            sys.wait(500)
        end
    end

    if audio_play_param.type == 0 then    --  播放文件处理
        if playConfigs.content == nil then
            log.error("当type 为0 时,playConfigs.content 只能为string(播放单文件),或者table(多文件)")
            return false      
        end
        
        if(type(playConfigs.content) == "table") then      -- 当播放多文件时候
            for _, path in ipairs(playConfigs.content) do  
                if type(path) ~= "string" then             -- 检查多文件是否都是string
                    log.error("当type 为0 时,playConfigs.content 为table 时,table 内元素必须为string 类型")
                    return false     
                end
            end
        elseif  (type(playConfigs.content) ~= "string") then
            log.error("当type 为0 时,playConfigs.content 类型必须为table(播放多文件),或者string(播放单文件)")
            return false    
        end
        audio_play_param.content = playConfigs.content
        audio.play(multimedia_id,audio_play_param.content)
    end

    if audio_play_param.type == 1 then        -- 播放tts 处理
        if playConfigs.content == nil or type(playConfigs.content) ~= "string"  then
            log.error("当type 为1 时,表示播放tts,playConfigs.content 必须为string 类型")
            return false    
        end
        audio_play_param.content = playConfigs.content
        audio.tts(multimedia_id,audio_play_param.content)
    end
    if audio_play_param.type == 2 then        -- 流式播放处理
        if playConfigs.content == nil or type(playConfigs.content) ~= "function"  then
            log.error("当type 为2 时,表示流式播放,playConfigs.content 必须为function 类型")
            return false    
        end
        if playConfigs.sampling_Rate == nil or type(playConfigs.sampling_Rate) ~= "number"  then
            log.error("当type 为2 时,表示流式播放,sampling_Rate(采样率)必须为int 类型")
            return false    
        end
        if playConfigs.sampling_Depth == nil or type(playConfigs.sampling_Depth) ~= "number"  then
            log.error("当type 为2 时,表示流式播放,sampling_Depth(采样位深)必须为int 类型")
            return false    
        end
        if playConfigs.signed_or_Unsigned == nil and type(playConfigs.signed_or_Unsigned) == "boolean"  then
            audio_play_param.signed_or_Unsigned = playConfigs.signed_or_Unsigned
        end
        audio_play_param.content = playConfigs.content
        audio.start(multimedia_id, audio.PCM, 1, playConfigs.sampling_Rate, playConfigs.sampling_Depth, audio_play_param.signed_or_Unsigned)
        audio.write(0, string.rep("\0", 512))  -- 流式播放前需要先发一下数据
    end


    if playConfigs.cbFnc ~= nil and type(playConfigs.cbFnc) == "function" then -- 如果填了回调函数，则保存回调韩函数，播放完毕调用回调函数
        audio_play_param.cbFnc = playConfigs.cbFnc
    end
    return true    
end

function exaudio.play_stop()
    return audio.stop(multimedia_id)
end

function exaudio.isEnd()
    return audio.isEnd()
end

function exaudio.getError()
    return audio.getError()
end

function exaudio.record()
    
end

function exaudio.record_stop()
    
end

function exaudio.vol()
    
end

function exaudio.micVol()
    
end

return exaudio