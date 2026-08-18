--[[
@module  record_amr_file
@summary 录音到文件（AMR格式）
@version 1.0
@date    2026.02.24
@author  拓毅恒
@usage

注意：
如果搭配AirAUDIO_1010 音频板测试，需将AirAUDIO_1010 音频板中PA开关拨到OFF，让软件控制PA，避免pop音

录音到文件演示程序，单按键操作：
1. 短按PWRKEY (< 1s)：开始录音（空闲时）/ 停止录音（录音中）/ 停止播放（播放中）
2. 长按PWRKEY (≥ 1s)：停止录音 / 停止播放（强制停止）

音量设置：
  播放音量：60
  录音麦克风音量：60

录音逻辑：
  录音时长为5秒，并计时
  录音过程中可以短按PWRKEY提前结束
  录音完成后自动播放录音文件

工作流程：
1. 初始化：设置音频硬件参数
2. 录音：短按PWRKEY开始录音，实时写入文件
3. 播放：录音完成后自动播放录音文件
4. 状态管理：互斥控制录音/播放状态
]]

local exaudio = require "exaudio"
-- 硬件版本由 main.lua 中的 _G.HARDWARE_ENV 全局变量统一控制

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

-- 录音文件路径
local recordPath = "/record.amr"

-- 硬件配置参数
local audio_setup_param = {
    model = "es8311",          -- dac类型,可填入"es8311","tm8211"
    i2c_id = 0,                -- I2C接口编号
    pa_ctrl = (HARDWARE_ENV == "G") and 25 or 23,             -- 音频放大器控制引脚, G:25, H:23
    dac_ctrl = 2,            -- 音频编解码芯片控制引脚
    
    -- 【注意：固件版本＜V2026，这里单位为1ms，这里填600，否则可能第一个字播不出来】
    dac_delay = set_dac_delay,            -- DAC启动前冗余时间
    
    i2s_sample = 16000,         -- I2S采样率
    bits_per_sample = 16,       -- I2S录音位深
    i2s_framebit = 16,           -- I2S通道位宽

    audio_mode = "auto", -- 音频框架版本选择: "auto"用默认, "new"新框架, "old"旧框架
    codec_voltage = (HARDWARE_ENV == "G") and 1 or 0 -- ES8311电压: 0=1.8V, 1=3.3V
}

-- 全局状态
local is_recording = false     -- 是否正在录音
local is_playing = false       -- 是否正在播放
local record_timer = nil       -- 录音计时器
local record_seconds = 0       -- 录音计时秒数

-- 音量设置
local PLAY_VOLUME = 70         -- 播放音量
local RECORD_VOLUME = 70       -- 录音麦克风音量

-- 录音时长设置（秒）
local RECORD_DURATION = 5      -- 录音时长

-- ========== 播放相关函数 ==========

-- 播放完成回调函数
local function play_end_callback(event)
    if event == exaudio.PLAY_DONE then
        log.info("播放完成")
        is_playing = false
    end
end

-- 开始播放录音文件
local function start_playback()
    log.info("录音文件路径", recordPath)
    
    -- 如果录音文件存在，播放录音
    if io.exists(recordPath) then

        -- 播放设置
        local audio_play_param = {
            type = 0,              -- 0=播放文件
            content = recordPath,  -- 播放录音文件
            cbfnc = play_end_callback,
            priority = 1
        }

        local file_size = io.fileSize(recordPath)
        if file_size > 0 then
            log.info("播放录音文件", "大小:", file_size, "字节")
            
            is_playing = true
            
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
local function stop_playback()
    if is_playing then
        log.info("停止播放")
        exaudio.play_stop({type = 0})
        is_playing = false
    end
end

-- ========== 录音相关函数 ==========

-- 停止录音计时
local function stop_record_timer()
    if record_timer then
        sys.timerStop(record_timer)
        record_timer = nil
        record_seconds = 0
    end
end

-- 停止录音
local function stop_recording()
    if is_recording then
        log.info("停止录音", "已录制:", record_seconds, "秒")
        exaudio.record_stop()
        is_recording = false
        stop_record_timer()
    end
end

-- 录音完成回调函数
local function record_end_callback(event)
    if event == exaudio.RECORD_DONE then
        is_recording = false
        local file_size = io.fileSize(recordPath)
        log.info("录音完成", "大小:", file_size, "字节")
        stop_record_timer()
        
        -- 使用定时器延迟500ms后播放录音文件
        sys.timerStart(start_playback, 500)
    end
end

-- 录音计时器回调
local function record_timer_callback()
    if is_recording then
        record_seconds = record_seconds + 1
        log.info("录音中...", record_seconds, "秒")
        
        -- 如果达到设定时长，自动停止录音
        if record_seconds >= RECORD_DURATION then
            stop_recording()
            log.info("录音时长已达", RECORD_DURATION, "秒，自动停止录音")
        end
    end
end

-- 开始录音计时
local function start_record_timer()
    record_seconds = 0
    record_timer = sys.timerLoopStart(record_timer_callback, 1000)
end

-- 开始录音
local function start_recording()
    if is_recording then
        log.info("已经在录音中")
        return false
    end
    
    if is_playing then
        log.info("正在播放中，停止播放")
        stop_playback()
    end
    
    log.info("开始录音", "时长:", RECORD_DURATION, "秒")
    
    -- 设置录音麦克风音量
    exaudio.mic_vol(RECORD_VOLUME)
    
    local audio_record_param = {
        format = exaudio.AMR_NB,  -- 使用AMR_NB格式（窄带）
        time = RECORD_DURATION,      -- 录制时长
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

-- ========== 按键处理函数 ==========

local pwrkey_press_time = 0         -- 记录按下时刻（tick）
local KEY_LONG_PRESS_MS = 1000      -- 长按阈值：1秒

-- PWRKEY单按键：短按开始/停止，长按强制停止
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
                -- 长按：强制停止（录音或播放）
                log.info("长按PWRKEY，强制停止")
                stop_recording()
                stop_playback()
            else
                -- 短按：开始录音 / 停止录音 / 停止播放
                if is_recording then
                    log.info("短按PWRKEY，停止录音")
                    stop_recording()
                elseif is_playing then
                    log.info("短按PWRKEY，停止播放")
                    stop_playback()
                else
                    log.info("短按PWRKEY，开始录音")
                    start_recording()
                end
            end
            pwrkey_press_time = 0
        end
    end
end

-- ========== 音频主任务 ==========

local function main_audio_task()

    log.info("音频系统初始化")
    
    if exaudio.setup(audio_setup_param) then
        -- 设置音量
        exaudio.vol(PLAY_VOLUME)              -- 播放音量
        exaudio.mic_vol(RECORD_VOLUME)        -- 录音麦克风音量
        
        log.info("音量设置", "播放:", PLAY_VOLUME, "录音:", RECORD_VOLUME)
        
        -- 检查是否有录音文件
        if io.exists(recordPath) then
            local file_size = io.fileSize(recordPath)
            log.info("找到录音文件", "大小:", file_size, "字节", "路径:", recordPath)
        else
            log.info("无录音文件", "路径:", recordPath)
        end
        
        log.info("按键功能说明：")
        log.info("1. 短按PWRKEY: 开始录音 / 停止录音 / 停止播放")
        log.info("2. 长按PWRKEY: 强制停止（录音或播放）")  
        log.info("3. 录音时长: ", RECORD_DURATION, "秒，可提前结束")
        log.info("4. 录音完成后自动播放")
        log.info("5. 录音文件保存到:", recordPath)
    else
        log.error("音频硬件初始化失败")
    end
end

-- ========== 初始化设置 ==========

-- PWRKEY 同时检测上升沿和下降沿（单按键操作）
gpio.setup(gpio.PWR_KEY, pwrkey_handler, gpio.PULLUP, gpio.BOTH)
gpio.debounce(gpio.PWR_KEY, 200, 1)

-- 启动音频主任务
sys.taskInit(main_audio_task)