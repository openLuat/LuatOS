audio_config={}

local exaudio = require "exaudio"

-- local success, errno = io.mkdir("/afile/")
--播放结果
local audio_result="a"

function audio_config.result()
    return audio_result
end

-- 音频初始化设置参数,exaudio.setup 传入参数
local audio_setup_param ={
    model= "es8311",          -- 音频编解码类型,可填入"es8311","es8211"
    i2c_id = 0,          -- i2c_id,可填入0，1 并使用pins 工具配置对应的管脚
    pa_ctrl = gpio.AUDIOPA_EN,         -- 音频放大器电源控制管脚
    dac_ctrl = 20,        --  音频编解码芯片电源控制管脚,780ehv 默认使用20
}

local function play_end(event)
    if event == exaudio.PLAY_DONE then
        log.info("播放完成",exaudio.is_end())
        exaudio.play_stop()
    end
end 

local tts_data={
    type= 1,                -- 播放类型，有0，播放文件，1.播放tts 2. 流式播放
    -- 如果是播放文件,支持mp3,amr,wav格式
    -- 如果是tts,内容格式见:https://docs.openluat.com/air780epm/common/tts/
    -- 流式播放，仅支持PCM 格式音频,如果是流式播放，则sampling_rate, sampling_depth,signed_or_unsigned 必填写
    content = "",          -- 如果播放类型为0时，则填入string 是播放单个音频文件,如果是表则是播放多段音频文件。
    cbfnc = play_end,    
}

local file_data={
    type= 0,                -- 播放类型，有0，播放文件，1.播放tts 2. 流式播放
                            -- 如果是播放文件,支持mp3,amr,wav格式
                            -- 如果是tts,内容格式见:https://wiki.luatos.com/chips/air780e/tts.html?highlight=tts
                            -- 流式播放，仅支持PCM 格式音频,如果是流式播放，则sampling_rate, sampling_depth,signed_or_unsigned 必填写
    content = "",          -- 如果播放类型为0时，则填入string 是播放单个音频文件,如果是表则是播放多段音频文件。
    cbfnc = play_end,            -- 播放完毕回调函数
}

-- local function audio_play_tts()
--     while true do
--         local result,playdata=sys.waitUntil("AUDIO_PLAY_TTS")
--         tts_data.content=playdata
--         audio_result=exaudio.play_start(tts_data)
--     end
-- end

function audio_config.audio_play_tts(playdata)
    sys.taskInit(function()
        log.info("先处理任务")
        tts_data.content=playdata
        audio_result=exaudio.play_start(tts_data)
        log.info("处理任务结束")
    end)
    log.info("AUDIO",audio_result)
    return audio_result
end

function audio_config.audio_play_file(url,file_name,isdelete)
    log.info("URL",url,type(url))
    log.info("file_name",file_name,type(file_name))
    log.info("isdelete",isdelete,type(isdelete))
    sys.taskInit(function()
        if url then
            local code, headers, body =
            http.request("GET", url, nil, nil, {dst = "/1.mp3"}).wait()
        --存到本地文件区，适用于多次播放
        log.info("下载完成", code, headers, body)
        end

        local r=io.exists("/"..file_name)
        log.info("文件是否存在",r)
        file_data.content="/1.mp3"
        audio_result=exaudio.play_start(file_data)
        if isdelete and tonumber(isdelete) == 1 then
            log.info("删除文件",file_data.content,io.exists(file_data.content))
            os.remove(file_data.content)
            log.info("result",io.exists(file_data.content))
        end
    end)
    return audio_result
end

function audio_config.init()
    if exaudio.setup(audio_setup_param) then
        if fskv.get("vol") then
            exaudio.vol(fskv.get("vol"))
            log.info("音量设置成功",fskv.get("vol"))
        end
        -- sys.taskInit(audio_play_tts)
        -- sys.taskInit(audio_play_file)
    else
        log.error("音频初始化失败")
    end
end

return audio_config