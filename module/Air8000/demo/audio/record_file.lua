--[[
@module  record_file
@summary 录音到文件
@version 3.0
@date    2026.01.09
@author  陈媛媛
@usage

注意：
如果搭配AirAUDIO_1010 音频板测试，需将AirAUDIO_1010 音频板中PA开关拨到OFF，让软件控制PA，避免pop音

录音到文件演示程序，按键功能：
1. Power键：开始/停止录音，停止播放
   - 空闲时按Power键开始5秒录音
   - 录音中按Power键提前结束录音
   - 播放中按Power键停止播放
2. Boot键：开始/停止播放，停止录音
   - 空闲时按Boot键播放录音文件
   - 播放中按Boot键停止播放
   - 录音中按Boot键提前结束录音

音量设置：
  播放音量：60
  录音麦克风音量：60

录音逻辑：
  录音时长为5秒，并计时
  录音过程中可以按任意键提前结束
  录音完成后自动播放录音文件
]]

exaudio = require("exaudio")

-- 硬件配置参数
local audio_setup_param = {
    model = "es8311",          -- 音频编解码芯片类型
    i2c_id = 0,                -- I2C接口编号
    pa_ctrl = 162,             -- 音频放大器控制引脚
    dac_ctrl = 164,            -- 音频编解码芯片控制引脚
    bits_per_sample = 16       -- 录音位深
}

-- 录音文件路径
local recordPath = "/record.amr"

-- 全局状态
local is_recording = false     -- 是否正在录音
local is_playing = false       -- 是否正在播放
local record_timer = nil       -- 录音计时器
local record_seconds = 0       -- 录音计时秒数

-- 音量设置
local PLAY_VOLUME = 60         -- 播放音量
local RECORD_VOLUME = 60       -- 录音麦克风音量

-- ========== 播放相关函数 ==========

-- 播放完成回调函数
function play_end_callback(event)
    if event == exaudio.PLAY_DONE then
        log.info("播放完成")
        is_playing = false
    end
end

-- 开始播放录音文件
function start_playback()
    if io.exists(recordPath) then
        local file_size = io.fileSize(recordPath)
        if file_size > 0 then
            log.info("播放录音文件", "大小:", file_size, "字节")
            
            is_playing = true
            
            local audio_play_param = {
                type = 0,              -- 0=播放文件
                content = recordPath,  -- 播放录音文件
                cbfnc = play_end_callback,
                priority = 1
            }
            
            local play_result = exaudio.play_start(audio_play_param)
            if not play_result then
                log.error("播放启动失败")
                is_playing = false
            else
                log.info("播放已开始")
            end
        else
            log.warn("录音文件为空，无法播放")
        end
    else
        log.warn("录音文件不存在，无法播放")
    end
end

-- 停止播放
function stop_playback()
    if is_playing then
        log.info("停止播放")
        exaudio.play_stop()
        is_playing = false
    end
end

-- ========== 录音相关函数 ==========

-- 录音完成回调函数
function record_end_callback(event)
    if event == exaudio.RECORD_DONE then
        is_recording = false
        stop_record_timer()
        
        local file_size = io.fileSize(recordPath)
        log.info("录音完成", "时长:", record_seconds, "秒", "大小:", file_size, "字节")
        
        -- 使用定时器延迟500ms后播放录音文件
        sys.timerStart(start_playback, 500)
    end
end

-- 录音计时器回调
function record_timer_callback()
    if is_recording then
        record_seconds = record_seconds + 1
        log.info("录音中...", record_seconds, "秒")
        
        -- 如果达到5秒，自动停止录音
        if record_seconds >= 5 then
            stop_recording()
            log.info("录音时长已达5秒，自动停止录音")
        end
    end
end

-- 开始录音计时
function start_record_timer()
    record_seconds = 0
    record_timer = sys.timerLoopStart(record_timer_callback, 1000)
end

-- 停止录音计时
function stop_record_timer()
    if record_timer then
        sys.timerStop(record_timer)
        record_timer = nil
        record_seconds = 0
    end
end

-- 开始录音
function start_recording()
    if is_recording then
        log.info("已经在录音中")
        return false
    end
    
    if is_playing then
        log.info("正在播放中，停止播放")
        stop_playback()
    end
    
    log.info("开始录音", "时长:5秒")
    
    -- 设置录音麦克风音量
    exaudio.mic_vol(RECORD_VOLUME)
    
    local audio_record_param = {
        format = exaudio.AMR_NB,  -- 使用AMR_NB格式（窄带）
        time = 5,                -- 录制5秒
        path = recordPath,        -- 录音文件路径
        cbfnc = record_end_callback  -- 录音完成回调函数
    }
    
    local record_result = exaudio.record_start(audio_record_param)
    if record_result then
        is_recording = true
        start_record_timer()
        log.info("录音已开始，按任意键可提前结束")
        return true
    else
        log.error("录音启动失败")
        return false
    end
end

-- 停止录音
function stop_recording()
    if is_recording then
        log.info("提前停止录音", "已录制:", record_seconds, "秒")
        exaudio.record_stop()
        is_recording = false
        stop_record_timer()
    end
end

-- ========== 按键处理函数 ==========

-- POWERKEY键：开始/停止录音，停止播放
function powerkey_handler()
    log.info("按下POWERKEY键")
    
    if is_recording then
        -- 录音中：停止录音
        log.info("正在录音中，停止录音")
        stop_recording()
    elseif is_playing then
        -- 播放中：停止播放
        log.info("正在播放中，停止播放")
        stop_playback()
    else
        -- 空闲状态：开始录音
        log.info("空闲状态，开始录音")
        start_recording()
    end
end

-- BOOT键：开始/停止播放，停止录音
function boot_key_handler()
    log.info("按下BOOT键")
    
    if is_recording then
        -- 录音中：停止录音
        log.info("正在录音中，停止录音")
        stop_recording()
    elseif is_playing then
        -- 播放中：停止播放
        log.info("正在播放中，停止播放")
        stop_playback()
    else
        -- 空闲状态：播放录音
        log.info("空闲状态，播放录音")
        start_playback()
    end
end

-- ========== 音频主任务 ==========

function main_audio_task()

    log.info("音频系统初始化")
    
    if exaudio.setup(audio_setup_param) then
        -- 设置音量
        exaudio.vol(PLAY_VOLUME)              -- 播放音量
        exaudio.mic_vol(RECORD_VOLUME)        -- 录音麦克风音量
        
        log.info("音量设置", "播放:", PLAY_VOLUME, "录音:", RECORD_VOLUME)
        
        -- 检查是否有录音文件
        if io.exists(recordPath) then
            local file_size = io.fileSize(recordPath)
            log.info("找到录音文件", "大小:", file_size, "字节")
        else
            log.info("无录音文件")
        end
        
        log.info("按键功能说明：")
        log.info("1. Power键: 开始/停止录音，停止播放")
        log.info("2. Boot键: 开始/停止播放，停止录音")  
        log.info("3. 录音时长: 5秒，可提前结束")
        log.info("4. 录音完成后自动播放")
    else
        log.error("音频硬件初始化失败")
    end
end

-- ========== 初始化设置 ==========

-- 设置POWERKEY键（开始/停止录音）
gpio.setup(gpio.PWR_KEY, powerkey_handler, gpio.PULLUP, gpio.FALLING)
gpio.debounce(gpio.PWR_KEY, 200, 1)

-- 设置BOOT键（开始/停止播放，停止录音）
gpio.setup(0, boot_key_handler, gpio.PULLDOWN, gpio.RISING)
gpio.debounce(0, 200, 1)

-- 启动音频主任务
sys.taskInit(main_audio_task)