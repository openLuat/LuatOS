--[[
@module  record_pcm_file
@summary 流式录音到文件功能（PCM格式）
@version 1.0
@date    2026.02.24
@author  拓毅恒
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
  录音完成后录音文件保存在sd卡目录或内存中

播放逻辑：
  使用流式播放方式播放PCM格式录音文件
  演示使用16kHz采样率、16位采样深度、有符号PCM数据
  注意：播放采样位深仅支持到24位，如果录制32位录音则无法播放，需要用电脑进行播放！！！

工作流程：
1. 初始化：挂载SD卡，设置音频硬件参数
2. 录音：流式录音，实时写入SD卡，显示写入速度统计
3. 播放：流式播放，按下BOOT按键读取文件并播放
4. 状态管理：互斥控制录音/播放状态
]]

local exaudio = require "exaudio"

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

-- SD卡配置参数
local sd_spi_id = 0            -- SPI接口编号
local sd_cs_pin = 16           -- 片选引脚 核心板cs为8 开发板cs为16 按照自己的硬件选择
local sd_mount_path = "/sd"    -- SD卡挂载路径

-- 录音文件路径（保存到SD卡）
local recordPath = sd_mount_path .. "/record.pcm"

-- 全局状态
local is_recording = false     -- 是否正在录音
local is_playing = false       -- 是否正在播放
local record_timer = nil       -- 录音计时器
local record_seconds = 0       -- 录音计时秒数

-- 音量设置
local PLAY_VOLUME = 60         -- 播放音量
local RECORD_VOLUME = 60       -- 录音麦克风音量

-- 硬件配置参数
local audio_setup_param = {
    model = "es8311",          -- 音频编解码芯片类型
    i2c_id = 0,                -- I2C接口编号
    pa_ctrl = gpio.AUDIOPA_EN,             -- 音频放大器控制引脚
    dac_ctrl = 20,            -- 音频编解码芯片控制引脚

    -- 【注意：固件版本＜V2026，这里单位为1ms，这里填600，否则可能第一个字播不出来】
    dac_delay = set_dac_delay,            -- DAC启动前冗余时间

    i2s_sample = 16000,         -- I2S采样率
    bits_per_sample = 16,       -- I2S录音位深
    i2s_framebit = 16           -- I2S通道位宽
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
    if io.exists(recordPath) then
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

-- 停止播放
local function stop_playback()
    if is_playing then
        log.info("停止流式播放")
        exaudio.play_stop(audio_play_param)  -- 停止流式播放
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
        log.info("按下BOOT键开始播放录音文件")
        stop_record_timer()
    end
end

-- 录音设置
local audio_record_param = {
    format = exaudio.PCM_16000,  -- 使用16kHz PCM格式
    time = 5,                -- 录制5秒
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
                local write_time = end_time - start_time  -- 毫秒
                local write_speed = size / (write_time / 1000)  -- 字节/秒
                
                log.info("SD卡写入统计", 
                    "数据大小:", size, "字节,", 
                    "写入耗时:", string.format("%.2f", write_time), "ms,",
                    "写入速度:", string.format("%.2f", write_speed / 1024), "KB/s")
                
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
        
        -- 如果达到5秒，自动停止录音
        if record_seconds >= 5 then
            stop_recording()
            log.info("录音时长已达5秒，自动停止录音")
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
    
    log.info("开始录音", "时长:5秒")
    
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

-- ========== 按键处理函数 ==========

-- POWERKEY键：开始/停止录音，停止播放
local function powerkey_handler()
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
local function boot_key_handler()
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

-- ========== SD卡挂载函数 ==========

-- 挂载SD卡
local function mount_sd_card()
    log.info("开始挂载SD卡")
    -- 打开ch390供电脚（使用开发板需要打开此注释）
    gpio.setup(20, 1, gpio.PULLUP) 
    --上拉ch390使用spi的cs引脚避免干扰（使用开发板需要打开此注释）
    gpio.setup(8,1)
    
    -- 初始化SPI接口
    spi.setup(sd_spi_id, nil, 0, 0, 400 * 1000)
    -- 设置片选引脚为高电平
    gpio.setup(sd_cs_pin, 1)
    
    -- 挂载SD卡，挂载失败时自动格式化
    local mount_ok, mount_err = fatfs.mount(fatfs.SPI, sd_mount_path, sd_spi_id, sd_cs_pin, 24 * 1000 * 1000)
    
    if mount_ok then
        log.info("SD卡挂载成功", "挂载路径:", sd_mount_path)
        
        -- 获取SD卡空间信息
        local data, err = fatfs.getfree(sd_mount_path)
        if data then
            log.info("SD卡空间信息", json.encode(data))
        else
            log.warn("获取SD卡空间信息失败", err)
        end
        
        return true
    else
        log.error("SD卡挂载失败", mount_err)
        return false
    end
end

-- ========== 音频主任务 ==========

local function main_audio_task()

    log.info("音频系统初始化")
    
    -- 先挂载SD卡
    if not mount_sd_card() then
        log.error("SD卡挂载失败，录音文件将无法保存到SD卡")
        -- 如果SD卡挂载失败，使用默认路径
        recordPath = "/record.pcm"
    else
        log.error("SD卡挂载成功！！！")
    end
    
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
        log.info("1. Power键: 开始/停止录音，停止播放")
        log.info("2. Boot键: 开始/停止播放，停止录音")  
        log.info("3. 录音时长: 5秒，可提前结束")
        log.info("4. 录音完成后自动播放")
        log.info("5. 录音文件保存到:", recordPath)
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