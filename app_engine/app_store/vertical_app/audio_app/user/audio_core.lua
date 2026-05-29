--[[
@module  audio_core
@summary 音频核心功能模块
@version 1.0
@date    2026.03.26
@author  拓毅恒
@usage
支持MP3/AMR/PCM格式音频播放
]]

local audio_core = {}

-- exaudio扩展库引用
local exaudio = nil

-- 音频系统状态
local initialized = false
local current_volume = 75
local mic_volume = 60
local is_playing = false
local is_recording = false
local play_callback = nil
local record_callback = nil
local progress_callback = nil
local stream_task = nil

-- SD卡配置参数 (Air1601/Air1602)
local sd_spi_id = 1
local sd_cs_pin = 8
local sd_mount_path = "/sd"

-- 录音文件路径
local record_amr_path = sd_mount_path .. "/record.amr"
local record_pcm_path = sd_mount_path .. "/record.pcm"

-- 当前播放的文件路径和格式
local current_play_path = nil
local current_play_format = nil

-- TTS音色映射表
local tts_voice_map = {
    ["default"] = "[m50]",  -- 默认
    ["xujiu"] = "[m51]",    -- 许久
    ["tang"] = "[m54]",     -- 唐老鸭
}

--[[
根据版本号自适应设置dac_delay
参考: play_file.lua, record_amr_file.lua, record_pcm_file.lua
]]
local function get_dac_delay()
    local version = rtos.version()
    local version_num = 0
    if version then
        local num_str = version:match("V(%d+)")
        if num_str then
            version_num = tonumber(num_str)
        end
    end
    
    if version_num and version_num >= 2026 then
        return 6  -- 固件版本≥V2026，单位为100ms
    else
        return 600  -- 固件版本＜V2026，单位为1ms
    end
end

--[[
获取模组型号
@return string 模组型号: "air1601", "air1602", "air8000" 或其他
]]
local function get_module_type()
    local model = hmeta and hmeta.model and hmeta.model()
    log.info("audio_core", "读取到的模组型号:", model)
    if model then
        local model_lower = model:lower()
        if model_lower:find("air1602") then
            return "air1602"
        elseif model_lower:find("air1601") then
            return "air1601"
        elseif model_lower:find("air8000") then
            return "air8000"
        end
    end
    return "other"
end

--[[
报告进度
]]
local function report_progress(percent, message)
    if progress_callback then
        progress_callback(percent, message)
    end
end

--[[
挂载SD卡
]]
local function mount_sd_card()
    log.info("audio_core", "开始挂载SD卡")
    report_progress(15, "挂载SD卡...")
    
    -- 初始化SPI接口 (8位数据位, 400kHz时钟)
    spi.setup(sd_spi_id, nil, 0, 0, 8, 400000)
    -- 设置片选引脚为高电平 (同一spi总线上的所有从设备在初始化时必须要先拉高CS脚，防止从设备之间互相干扰)
    gpio.setup(sd_cs_pin, 1)
    
    -- 挂载SD卡 (24MHz时钟)
    report_progress(25, "挂载中...")
    local mount_ok, mount_err = fatfs.mount(fatfs.SPI, sd_mount_path, sd_spi_id, sd_cs_pin, 24000000)
    report_progress(40, "挂载中...")
    
    if mount_ok then
        report_progress(50, "挂载成功")
        log.info("audio_core", "SD卡挂载成功")
        local data, err = fatfs.getfree(sd_mount_path)
        if data then
            log.info("audio_core", "SD卡空间:", json.encode(data))
        end
        return true
    else
        log.warn("audio_core", "SD卡挂载失败:", mount_err)
        return false
    end
end

--[[
获取文件扩展名
]]
local function get_file_ext(filename)
    return filename:lower():match("%.([^%.]+)$") or ""
end

--[[
播放完成回调（通用）
参考: play_file.lua, record_amr_file.lua
]]
local function play_end_callback(event)
    if not exaudio then return end
    if event == exaudio.PLAY_DONE then
        log.info("audio_core", "播放完成")
        is_playing = false
        current_play_path = nil
        current_play_format = nil
        if play_callback then
            play_callback()
            play_callback = nil
        end
    end
end

--[[
流式播放数据读取任务
参考: record_pcm_file.lua
]]
local function stream_playback_task(file_path)
    log.info("audio_core", "开始流式读取音频数据:", file_path)
    if not exaudio then
        is_playing = false
        return
    end

    local file = io.open(file_path, "rb")
    
    if not file then
        log.error("audio_core", "无法打开音频文件:", file_path)
        is_playing = false
        return
    end
    
    -- 获取推荐的缓冲区大小
    local buffer_size = exaudio.get_stream_buffer_size() or 4096
    log.info("audio_core", "流式播放缓冲区大小:", buffer_size)
    
    while is_playing do
        local read_data = file:read(buffer_size)
        if read_data == nil then
            -- 文件读取完毕
            file:close()
            file = nil
            -- 通知多媒体通道没有更多数据
            exaudio.finish()
            log.info("audio_core", "流式数据读取完成")
            break
        end
        
        -- 如果读取的数据小于缓冲区大小，补充静音数据
        if #read_data < buffer_size then
            read_data = read_data .. string.rep("\0", buffer_size - #read_data)
        end
        
        exaudio.play_stream_write(read_data)
        sys.wait(20)  -- 留出时间给其他task运行
    end
    
    -- 如果播放被提前停止，确保文件被关闭
    if file then
        file:close()
        log.info("audio_core", "播放被停止，文件已关闭")
    end
end

--[[
初始化音频系统

@api audio_core.init(callback)
@param callback function 进度回调函数，参数为(percent, message)
@return boolean 初始化成功返回true，失败返回false
参考: play_file.lua, record_amr_file.lua
]]
function audio_core.init(callback)
    if initialized then
        log.info("audio_core", "音频系统已初始化")
        return true
    end

    progress_callback = callback
    report_progress(5, "初始化...")

    -- 获取模组型号
    local module_type = get_module_type()
    
    -- Air1602 畅玩版没有SD卡槽，跳过挂载
    if module_type ~= "air1602" then
        -- 尝试挂载SD卡
        mount_sd_card()
    else
        log.info("audio_core", "Air1602 跳过SD卡挂载")
        report_progress(50, "无SD卡")
    end

    report_progress(60, "配置音频...")
    
    -- 加载exaudio模块
    if not exaudio then
        exaudio = require "exaudio"
        if not exaudio or type(exaudio) ~= "table" then
            log.error("audio_core", "加载exaudio库失败")
            report_progress(0, "音频库加载失败")
            return false
        end
    end
    
    -- 根据模组型号设置音频初始化参数
    local module_type = get_module_type()
    local audio_setup_param = {}
    
    if module_type == "air1601" then
        -- Air1601使用内置DAC
        log.info("audio_core", "检测到Air1601模组，使用DAC模式")
        audio_setup_param = {
            model = "dac",            -- 音频编解码类型: "dac" 表示使用内置DAC
            pa_ctrl = 12,             -- 音频放大器电源控制管脚
            pa_on_level = 1,          -- PA打开电平，0=低电平使能，1=高电平使能
            pa_delay = 10,            -- PA延时(ms)，DAC启动后延迟打开PA的时间
        }
    elseif module_type == "air1602" then
        -- Air1602使用内置DAC
        log.info("audio_core", "检测到Air1602模组，使用DAC模式")
        audio_setup_param = {
            model = "dac",            -- 音频编解码类型: "dac" 表示使用内置DAC
            pa_ctrl = 45,             -- 音频放大器电源控制管脚
            pa_on_level = 1,          -- PA打开电平，0=低电平使能，1=高电平使能
            pa_delay = 10,            -- PA延时(ms)，DAC启动后延迟打开PA的时间
        }
    elseif module_type == "air8000" then
        -- Air8000系列使用ES8311
        log.info("audio_core", "检测到Air8000模组，使用ES8311模式")
        audio_setup_param = {
            model = "es8311",         -- 音频编解码类型
            i2c_id = 0,               -- i2c_id
            dac_delay = get_dac_delay(), -- 根据版本自适应设置
            pa_ctrl = 162,            -- 音频放大器电源控制管脚
            dac_ctrl = 164,           -- 音频编解码芯片电源控制管脚
        }
    else
        -- 其他模组，使用默认配置（ES8311）
        log.info("audio_core", "未识别模组型号，或当前型号还不支持，请使用8000W/1601/1602畅玩版进行测试")
        return false
    end

    report_progress(75, "启动中...")
    if exaudio.setup(audio_setup_param) then
        report_progress(90, "设置音量...")
        -- 设置音量
        exaudio.vol(current_volume)
        exaudio.mic_vol(mic_volume)

        initialized = true
        report_progress(100, "完成")
        log.info("audio_core", "音频系统初始化成功")
        return true
    else
        log.error("audio_core", "音频系统初始化失败")
        return false
    end
end

--[[
播放音频文件（支持MP3/AMR/PCM自动切换）

@api audio_core.play_file(file_path, callback)
@param file_path string 音频文件路径
@param callback function 播放完成回调函数（可选）
@return boolean 播放启动成功返回true，失败返回false
]]
function audio_core.play_file(file_path, callback)
    if is_playing then
        log.warn("audio_core", "正在播放中，先停止当前播放")
        audio_core.stop_play()
        -- 等待一小段时间确保播放完全停止
        sys.wait(100)
    end
    
    if not io.exists(file_path) then
        log.error("audio_core", "文件不存在:", file_path)
        return false
    end
    
    -- 获取文件格式
    local ext = get_file_ext(file_path)
    log.info("audio_core", "播放文件:", file_path, "格式:", ext)
    
    play_callback = callback
    current_play_path = file_path
    current_play_format = ext
    
    local play_result = false
    
    if ext == "mp3" or ext == "amr" then
        -- MP3/AMR格式：使用文件播放模式 (type=0)
        local audio_play_param = {
            type = 0,
            content = file_path,
            cbfnc = play_end_callback,
            priority = 1
        }
        
        is_playing = true
        play_result = exaudio.play_start(audio_play_param)
        
    elseif ext == "pcm" then
        -- PCM格式：使用流式播放模式 (type=2)
        local audio_play_param = {
            type = 2,
            cbfnc = play_end_callback,
            priority = 1,
            sampling_rate = 16000,  -- 采样率
            sampling_depth = 16,    -- 采样位深
            signed_or_unsigned = true,  -- PCM数据是否有符号
            codec_id = 0            -- 编解码器ID：0表示RAW/PCM直通模式
        }
        
        is_playing = true
        play_result = exaudio.play_start(audio_play_param)
        
        if play_result then
            -- 启动流式数据读取任务
            stream_task = sys.taskInit(stream_playback_task, file_path)
        end
        
    else
        log.error("audio_core", "不支持的音频格式:", ext)
        return false
    end
    
    if not play_result then
        log.error("audio_core", "播放启动失败")
        is_playing = false
        current_play_path = nil
        current_play_format = nil
        return false
    else
        log.info("audio_core", "开始播放:", file_path)
        return true
    end
end

--[[
停止播放

@api audio_core.stop_play()
@return nil
]]
function audio_core.stop_play()
    if not is_playing then return end
    if not exaudio then return end
    
    log.info("audio_core", "停止播放")
    
    -- 标记停止状态，让流式任务退出
    is_playing = false
    
    -- 停止播放
    if current_play_format == "pcm" then
        -- PCM流式播放需要特殊处理
        exaudio.play_stop({type = 2})
    elseif current_play_format == "tts" then
        -- TTS播放
        exaudio.play_stop({type = 1})
    else
        -- MP3/AMR文件播放
        exaudio.play_stop({type = 0})
    end
    
    -- 等待流式任务结束
    if stream_task then
        -- 不阻塞，让任务自然结束
        stream_task = nil
    end
    
    current_play_path = nil
    current_play_format = nil
    play_callback = nil
end

--[[
暂停播放

@api audio_core.pause_play()
@return nil
]]
function audio_core.pause_play()
    if not exaudio then return end
    if is_playing then
        log.info("audio_core", "暂停播放")
        exaudio.play_pause()
    end
end

--[[
恢复播放

@api audio_core.resume_play()
@return nil
]]
function audio_core.resume_play()
    if not exaudio then return end
    if is_playing then
        log.info("audio_core", "恢复播放")
        exaudio.play_resume()
    end
end

--[[
设置播放音量

@api audio_core.set_volume(vol)
@param vol number 音量值，范围0-100
@return nil
]]
function audio_core.set_volume(vol)
    current_volume = math.max(0, math.min(100, vol))
    if initialized and exaudio then
        exaudio.vol(current_volume)
    end
    log.info("audio_core", "音量设置为:", current_volume)
end

--[[
设置麦克风音量

@api audio_core.set_mic_volume(vol)
@param vol number 麦克风音量，范围0-100
@return nil
]]
function audio_core.set_mic_volume(vol)
    mic_volume = math.max(0, math.min(100, vol))
    if initialized and exaudio then
        exaudio.mic_vol(mic_volume)
    end
    log.info("audio_core", "麦克风音量设置为:", mic_volume)
end

--[[
获取当前播放状态

@api audio_core.is_playing()
@return boolean 是否正在播放
]]
function audio_core.is_playing()
    return is_playing
end

--[[
获取当前播放文件路径

@api audio_core.get_current_file()
@return string 当前播放的文件路径，未播放返回nil
]]
function audio_core.get_current_file()
    return current_play_path
end

-- ==================== 录音功能（保留） ====================

--[[
录音完成回调
]]
local function record_end_callback(event)
    if not exaudio then return end
    if event == exaudio.RECORD_DONE then
        log.info("audio_core", "录音完成")
        is_recording = false
        if record_callback then
            record_callback()
            record_callback = nil
        end
    end
end

--[[
开始录音

@api audio_core.start_record(format, duration, callback)
@param format string 录音格式："amr"或"pcm"
@param duration number 录音时长（秒），范围3-180
@param callback function 录音完成回调函数（可选）
@return boolean 录音启动成功返回true，失败返回false
参考: record_amr_file.lua, record_pcm_file.lua
]]
function audio_core.start_record(format, duration, callback)
    if not initialized or not exaudio then
        log.error("audio_core", "音频系统未初始化")
        return false
    end
    
    if is_recording then
        log.warn("audio_core", "已经在录音中")
        return false
    end
    
    if is_playing then
        log.info("audio_core", "正在播放中，先停止播放")
        audio_core.stop_play()
    end
    
    -- 检查SD卡状态并更新路径
    local data = fatfs.getfree("/sd")
    local use_sd = (data ~= nil)
    
    local record_path
    if format == "amr" then
        record_path = use_sd and record_amr_path or "/record.amr"
    else
        record_path = use_sd and record_pcm_path or "/record.pcm"
    end
    
    -- 限制录音时长
    duration = math.max(3, math.min(180, duration))
    
    record_callback = callback
    
    log.info("audio_core", "开始录音", "格式:", format, "时长:", duration, "路径:", record_path)
    
    local audio_record_param
    if format == "amr" then
        -- AMR格式录音（参考record_amr_file.lua）
        audio_record_param = {
            format = exaudio.AMR_NB,
            time = duration,
            path = record_path,
            cbfnc = record_end_callback
        }
    else
        -- PCM格式录音（参考record_pcm_file.lua）
        -- 删除旧文件
        if io.exists(record_path) then
            os.remove(record_path)
        end
        
        audio_record_param = {
            format = exaudio.PCM_16000,
            time = duration,
            path = function(buff, size)
                if buff and size > 0 then
                    local file = io.open(record_path, "ab")
                    if file then
                        file:write(buff:query())
                        file:close()
                    end
                end
            end,
            cbfnc = record_end_callback
        }
    end
    
    local record_result = exaudio.record_start(audio_record_param)
    
    if record_result then
        is_recording = true
        return true
    else
        log.error("audio_core", "录音启动失败")
        return false
    end
end

--[[
停止录音

@api audio_core.stop_record()
@return nil
]]
function audio_core.stop_record()
    if not is_recording then return end
    if not exaudio then return end
    
    log.info("audio_core", "停止录音")
    exaudio.record_stop()
    is_recording = false
    record_callback = nil
end

--[[
获取录音文件路径

@api audio_core.get_record_path(format)
@param format string 录音格式："amr"或"pcm"
@return string 录音文件路径
]]
function audio_core.get_record_path(format)
    local data = fatfs.getfree("/sd")
    local use_sd = (data ~= nil)
    
    if format == "amr" then
        return use_sd and record_amr_path or "/record.amr"
    else
        return use_sd and record_pcm_path or "/record.pcm"
    end
end

--[[
播放TTS语音

@api audio_core.play_tts(text, voice, callback)
@param text string 要播放的文本内容
@param voice string 音色："default"(默认), "xujiu"(许久), "tang"(唐老鸭)
@param callback function 播放完成回调函数（可选）
@return boolean 播放启动成功返回true，失败返回false
]]
function audio_core.play_tts(text, voice, callback)
    if not initialized then
        log.info("audio_core", "音频系统未初始化，自动初始化...")
        local ok = audio_core.init()
        if not ok then
            log.error("audio_core", "音频系统初始化失败")
            return false
        end
    end
    
    if is_playing then
        log.warn("audio_core", "正在播放中，先停止当前播放")
        audio_core.stop_play()
        sys.wait(100)
    end
    
    if not text or text == "" then
        log.error("audio_core", "TTS文本为空")
        return false
    end
    
    -- 获取音色前缀
    local voice_prefix = tts_voice_map[voice] or tts_voice_map["default"]
    local tts_content = voice_prefix .. text
    
    log.info("audio_core", "播放TTS:", text, "音色:", voice)
    
    play_callback = callback
    current_play_path = "tts://" .. text
    current_play_format = "tts"
    
    -- TTS播放参数
    local audio_play_param = {
        type = 1,  -- TTS播放类型
        content = tts_content,
        cbfnc = play_end_callback,
        priority = 1
    }
    
    is_playing = true
    local play_result = exaudio.play_start(audio_play_param)
    
    if not play_result then
        log.error("audio_core", "TTS播放启动失败")
        is_playing = false
        current_play_path = nil
        current_play_format = nil
        return false
    else
        log.info("audio_core", "TTS播放开始")
        return true
    end
end

--[[
反初始化音频系统

@api audio_core.deinit()
@return nil
]]
function audio_core.deinit()
    if not initialized then return end
    
    -- 停止所有播放和录音
    audio_core.stop_play()
    audio_core.stop_record()
    
    initialized = false
    exaudio = nil  
    log.info("audio_core", "音频系统已关闭")
end

return audio_core
