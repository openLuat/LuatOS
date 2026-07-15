--[[
@module  record_pcm_file
@summary 流式录音到文件并自动播放（PCM格式）
@version 1.1
@date    2026.02.24
@author  拓毅恒
@usage

注意：
如果搭配AirAUDIO_1010 音频板测试，需将AirAUDIO_1010 音频板中PA开关拨到OFF，让软件控制PA，避免pop音

录音到文件演示程序，自动化流程：
1. 上电自动开始5秒录音
2. 录音完成后自动播放录音文件
3. 播放完成后流程结束

音量设置：
  播放音量：70
  录音麦克风音量：70

录音逻辑：
  录音时长为5秒，实时计时显示
  录音完成后录音文件保存在 /record.pcm

播放逻辑：
  使用流式播放方式播放PCM格式录音文件
  演示使用16kHz采样率、16位采样深度、有符号PCM数据
  注意：播放采样位深仅支持到24位，如果录制32位录音则无法播放，需要用电脑进行播放！！！

工作流程：
1. 初始化：设置音频硬件参数
2. 录音：自动开始流式录音，实时写入文件，显示写入速度统计
3. 播放：录音完成后自动播放录音文件
4. 结束：播放完成后流程结束
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
local recordPath = "/record.pcm"

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

-- ========== 播放相关函数 ==========

-- 播放完成回调函数
local function play_end_callback(event)
    if event == exaudio.PLAY_DONE then
        log.info("播放完成")
        is_playing = false
        -- 流式播放完成后，通知多媒体通道已经没有更多数据需要播放了
        exaudio.finish()
    end
end

-- 流式数据读取和写入任务
local function stream_audio_data()
    log.info("开始流式读取录音数据")
    local file = io.open(recordPath, "rb")   -- 打开录音文件进行流式播放
    
    if not file then
        log.error("无法打开录音文件:", recordPath)
        return
    end
    
    -- 获取推荐的缓冲区大小
    local buffer_size = exaudio.get_stream_buffer_size() or 4096
    log.info("流式播放缓冲区大小", buffer_size)
    
    while is_playing do
        local read_data = file:read(buffer_size)  -- 读取文件数据
        if read_data == nil then
            -- 文件读取完毕，关闭文件
            file:close()
            file = nil  -- 标记文件已关闭
            -- 写入数据完毕后，通知多媒体通道已经没有更多数据需要播放了
            exaudio.finish()
            log.info("流式数据读取完成")
            break
        end
        
        -- 如果读取的数据小于缓冲区大小，补充静音数据
        if #read_data < buffer_size then
            read_data = read_data .. string.rep("\0", buffer_size - #read_data)
        end
        
        exaudio.play_stream_write(read_data)  -- 流式写入音频数据
        sys.wait(20)                   -- 写数据需要留出时间给其他task运行代码
    end
    
    -- 如果播放被提前停止，确保文件被关闭
    if file then
        file:close()
        log.info("播放被停止，文件已关闭")
    end
end

-- 开始播放录音文件
local function start_playback()
    log.info("录音文件路径", recordPath)
    
    -- 如果录音文件存在，播放录音
    if io.exists(recordPath) then

        -- 播放设置
        -- 需要注意：播放采样位深仅支持到24位，如果录制32位录音则无法播放，需要用电脑进行播放！！！
        local audio_play_param = {
            type = 2,              -- 2=流式播放
            cbfnc = play_end_callback,
            priority = 1,
            sampling_rate = 16000,  -- 采样率
            sampling_depth = 16,    -- 采样位深
            signed_or_unsigned = true  -- PCM数据是否有符号
        }

        local file_size = io.fileSize(recordPath)
        if file_size > 0 then
            log.info("流式播放录音文件", "大小:", file_size, "字节")
            
            is_playing = true
            
            local play_result = exaudio.play_start(audio_play_param)
            if not play_result then
                log.error("流式播放启动失败")
                is_playing = false
            else
                log.info("流式播放已开始")
                -- 启动流式数据读取任务
                sys.taskInit(stream_audio_data)
            end
        else
            log.warn("录音文件为空，无法播放")
        end
    else
        log.warn("录音文件不存在，无法播放")
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
        
        -- 自动开始播放
        sys.taskInit(function()
            sys.wait(500)
            start_playback()
        end)
    end
end

-- 计算时间差（毫秒）
local function calc_time_diff_ms(start_tick, end_tick)
    -- 检查溢出：Lua中超过0x7fffffff会变成负数
    if (start_tick > 0 and end_tick < 0) or (start_tick < 0 and end_tick > 0) then
        log.warn("时间计算", "mcu.ticks()溢出，无法准确计算时长")
        return nil
    end
    
    local diff_ticks = end_tick - start_tick
    local hz = mcu.hz()
    if hz == 0 then
        hz = 1000  -- 默认1ms一个tick
    end
    
    return (diff_ticks * 1000) / hz
end

-- 录音设置
local audio_record_param = {
    format = exaudio.PCM_16000,  -- 使用16kHz PCM格式
    time = RECORD_DURATION,      -- 录制时长
    path = function(buff, size)
        -- 流式回调方式将录音数据写入文件
        if buff and size > 0 then
            -- 获取当前时间
            local start_time = mcu.ticks()  -- 记录开始时间
            local file = io.open(recordPath, "ab")  -- 追加模式打开文件
            if file then
                file:write(buff:query()) -- 将缓冲区数据写入文件
                file:close() -- 写入完成后关闭文件

                -- 计算写入速度
                local end_time = mcu.ticks()  -- 记录结束时间
                local write_time_ms = calc_time_diff_ms(start_time, end_time)
                
                if write_time_ms and write_time_ms > 0 then
                    local write_speed = size / (write_time_ms / 1000)  -- 字节/秒
                    log.info("文件写入统计", 
                        "数据大小:", size, "字节,", 
                        "写入耗时:", string.format("%.2f", write_time_ms), "ms,",
                        "写入速度:", string.format("%.2f", write_speed / 1024), "KB/s")
                else
                    log.info("文件写入统计", 
                        "数据大小:", size, "字节,", 
                        "写入耗时: 溢出无法计算")
                end
            else
                log.error("无法打开录音文件")
            end
        end
    end,
    cbfnc = record_end_callback  -- 录音完成回调函数
}

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
    
    log.info("开始录音", "时长:", RECORD_DURATION, "秒")
    
    -- 清空旧录音文件（流式模式需要手动管理文件）
    if io.exists(recordPath) then
        os.remove(recordPath)
        log.info("删除旧录音文件")
    end
    
    -- 设置录音麦克风音量
    exaudio.mic_vol(RECORD_VOLUME)
    
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
        
        log.info("录音时长:", RECORD_DURATION, "秒，录音完成后自动播放")
        log.info("录音文件保存到:", recordPath)
        
        -- 自动开始录音
        sys.taskInit(function()
            sys.wait(1000)
            start_recording()
        end)
    else
        log.error("音频硬件初始化失败")
    end
end

-- 启动音频主任务
sys.taskInit(main_audio_task)