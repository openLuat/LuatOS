audio_config={}

local exaudio = require "exaudio"

local success, errno = io.mkdir("/afile/")
--播放结果
local audio_result="a"

-- 音频初始化设置参数,exaudio.setup 传入参数
local audio_setup_param ={
    model= "es8311",          -- 音频编解码类型,可填入"es8311","es8211"
    i2c_id = 0,          -- i2c_id,可填入0，1 并使用pins 工具配置对应的管脚
    pa_ctrl = gpio.AUDIOPA_EN,         -- 音频放大器电源控制管脚
    dac_ctrl = 20,        --  音频编解码芯片电源控制管脚,780ehv 默认使用20
}

--播放完成回调
local function play_end(event)
    if event == exaudio.PLAY_DONE then
        log.info("播放完成",exaudio.is_end())
        local result,user_stop=audio.getError(0)
        log.info("最近一次的播放结果",audio.getError(0))
        sys.publish("audio_result","rrpc,playend,"..(result and "true" or "false")..","..(user_stop and "true" or "false"))
        exaudio.play_stop()
    end
end 

--tts初始化配置（audio_play_tts 已改为直调 audio.tts，此表不再使用，保留作参考）
-- local tts_data={
--     type= 1,                -- 播放类型，有0，播放文件，1.播放tts 2. 流式播放
--     content = "",          -- 如果播放类型为0时，则填入string 是播放单个音频文件,如果是表则是播放多段音频文件。
--     cbfnc = play_end,    
-- }

--播放文件初始化配置
local file_data={
    type= 0,                -- 播放类型，有0，播放文件，1.播放tts 2. 流式播放
                            -- 如果是播放文件,支持mp3,amr,wav格式
                            -- 如果是tts,内容格式见:https://wiki.luatos.com/chips/air780e/tts.html?highlight=tts
                            -- 流式播放，仅支持PCM 格式音频,如果是流式播放，则sampling_rate, sampling_depth,signed_or_unsigned 必填写
    content = "",          -- 如果播放类型为0时，则填入string 是播放单个音频文件,如果是表则是播放多段音频文件。
    cbfnc = play_end,            -- 播放完毕回调函数
}

--tts播放函数
--注意（8780V / ES8311）：
--  1. 播放完成后 audio 库会把 codec 置 POWEROFF 掉电，第二次访问 I2C0(0x18) 会超时
--  2. 因此每次播放前必须先 audio.pm(RESUME) 重新上电
--  3. 播放完【不要】手动置 STANDBY/POWEROFF，保持常开，便于10秒循环播报
--  4. 若 RESUME 后仍超时，则完整重新初始化 codec（exaudio.setup）再播
function audio_config.audio_play_tts(playdata)
    sys.taskInit(function()
        if not (audio and audio.tts) then
            log.error("audio_config", "本固件不支持TTS，请更换支持TTS的固件")
            return
        end
        -- 播放前：codec 重新上电（RESUME），避免 I2C0 访问超时
        if audio.pm then
            pcall(audio.pm, 0, audio.RESUME)
        end
        -- 保险：DAC电源脚(780EHV 默认GPIO20)强制上电
        pcall(gpio.setup, 20, 1, gpio.PULLUP)
        sys.wait(50)

        local ok = pcall(audio.tts, 0, playdata)
        if not ok then
            log.warn("audio_config", "audio.tts 首次调用失败，尝试重新初始化codec")
            -- 播放完成掉电后，RESUME可能不足以恢复，完整重新初始化
            local init_ok = pcall(exaudio.setup, audio_setup_param)
            if init_ok then
                pcall(audio.pm, 0, audio.RESUME)
                sys.wait(50)
                pcall(audio.tts, 0, playdata)
            else
                log.error("audio_config", "codec重新初始化失败，检查I2C0接线与DAC电源")
                return
            end
        end

        -- 等待播放结束（最长15秒）
        local timeout_ms = 0
        while timeout_ms < 15000 do
            sys.wait(100)
            timeout_ms = timeout_ms + 100
            if audio.isEnd(0) then break end
        end
        -- 播放完保持 RESUME 常开（不手动关电），下次10秒播报可立即发声
    end)
    return true
end

--音频文件播放函数
--目前使用的是http下载到文件区播放的方式，如果需要用完就删掉，可以选择保存到内存区
function audio_config.audio_play_file(url,file_name,isdelete)
    log.info("URL",url,type(url))
    log.info("file_name",file_name,type(file_name))
    log.info("isdelete",isdelete,type(isdelete))
    sys.taskInit(function()
        if not audio_result then
            audio_result=true
        end
        if url and url~="" then
            --存到本地文件区，适用于多次播放
            
            local code, headers, body = http.request("GET", url, nil, nil, {dst = "/afile/"..file_name}).wait()
            --保存到内存区可以这么操作
            -- local code, headers, body = http.request("GET", url, nil, nil, {dst = "/ram/"..file_name}).wait()
        
        log.info("下载完成", code, headers, body)
        end

        file_data.content="/afile/"..file_name
        audio_result=exaudio.play_start(file_data)
        log.info("播放结果",audio_result)
        if isdelete and tonumber(isdelete) == 1 then
            log.info("删除文件",file_data.content,io.exists(file_data.content))
            os.remove(file_data.content)
            log.info("result",io.exists(file_data.content))
        end
    end)
    return audio_result
end

--初始化音频功能，设置参数
--返回值：成功返回true，失败返回false
function audio_config.init()
    if exaudio.setup(audio_setup_param) then
        if fskv.get("vol") then
            exaudio.vol(fskv.get("vol"))
            log.info("音量设置成功",fskv.get("vol"))
        end
        -- sys.taskInit(audio_play_tts)
        -- sys.taskInit(audio_play_file)
        return true
    else
        log.error("音频初始化失败")
        return false
    end
end

return audio_config