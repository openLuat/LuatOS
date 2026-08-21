--[[
@module  record_pcm_file
@summary 流式录音到文件功能（PCM格式）
@version 1.0
@date    2026.07.06
@author  拓毅恒
@usage

注意：
1. Air1602_V1.2开发板使用ES8311编解码芯片，录音走I2S2，播放走内置DAC
2. 需要固件版本>=V1026才可播放音频
3. LCD触摸芯片占用I2C1总线，若板载LCD需先拉高LCD_EN(GPIO57)，否则会干扰ES8311通信
4. 挂载SD卡前需先拉高SD_EN(GPIO56)使能SD供电（Air160X_V1.2开发板特性）
5. 录制PCM格式音频（16kHz/16bit/有符号/单声道），需要支持新音频框架的固件

录音到文件演示程序（开机自动运行，无需按键）：
1. 自动挂载SD卡，挂载失败自动回退内部存储
2. 自动开始5秒录音（PCM格式）
3. 录音完成后自动播放录音文件

音量设置：
  播放音量：70
  录音麦克风音量：70

录音逻辑：
  录音时长为5秒，并计时
  录音时长到自动停止
  录音完成后录音文件保存在TF卡或内部存储中

播放逻辑：
  使用流式播放方式播放PCM格式录音文件
  演示使用16kHz采样率、16位采样深度、有符号、单声道PCM数据
  注意：播放采样位深仅支持到24位，如果录制32位录音则无法播放，需要用电脑进行播放！！！

工作流程：
1. 初始化：挂载TF卡（失败自动回退内部存储），设置音频硬件参数
2. 录音：流式录音（PCM格式），实时写入TF卡，显示写入速度统计
3. 播放：录音完成后自动流式播放录音文件
4. 状态管理：互斥控制录音/播放状态
]]

local exaudio = require("exaudio")

-- TF卡配置参数
local sd_spi_id = 1            -- SPI接口编号
local sd_cs_pin = 8            -- 片选引脚
local sd_mount_path = "/sd"    -- SD卡挂载路径

-- 录音文件路径（保存到TF卡）
local recordPath = sd_mount_path .. "/record.pcm"

-- 硬件配置参数 (DAC模式)
local audio_setup_param = {
    model = "es8311",         -- 音频编解码类型: "es8311" 使用ES8311编解码芯片

    -- I2C配置（ES8311通过I2C1通信）
    i2c_id = 1,               -- I2C总线编号

    -- 默认驱动切换（Air1602_V1.2开发板必须：DAC0输出 + I2S2录音）
    tx_bus_type = audio_v2.DRIVER_TYPE_DAC,   -- 发送(播放)总线类型: 内置DAC
    tx_bus_id = 0,            -- 发送总线ID
    rx_bus_type = audio_v2.DRIVER_TYPE_I2S,   -- 接收(录音)总线类型: I2S
    rx_bus_id = 2,            -- 接收总线ID: 2=I2S2

    -- 音频编解码芯片电源控制脚（Air1602_V1.2开发板ES8311_EN=GPIO43）
    -- exaudio内部在切换默认驱动成功后，会对该引脚自动执行"拉低→等待→拉高"复位脉冲重启ES8311
    dac_ctrl = 43,

    -- I2S配置
    i2s_sample = 16000,        -- I2S采样率
    bits_per_sample = 16,     -- I2S采样位深
    i2s_framebit = 16,        -- I2S通道位宽
    channels = 1,             -- 声道数: 1=单声道

    -- PA功放配置
    pa_ctrl = 73,             -- PA功放控制管脚，Air1602_V1.2开发板PA_EN=GPIO73
    pa_on_level = 0,          -- PA打开电平，0=低电平使能（Air1602_V1.2开发板低电平使能）
    pa_delay = 100,           -- PA打开延迟(ms)
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
            file = nil
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
        sys.wait(20)                            -- 写数据需要留出时间给其他task运行代码
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

        log.info("录音完成后，启动播放任务")
        sys.timerStart(start_playback, 500)
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
    time = RECORD_DURATION,        -- 录制时长
    path = function(buff, size)
        -- 流式回调方式将录音数据写入文件
        if buff and size > 0 then
            -- 获取当前时间
            local start_time = mcu.ticks()  -- 记录开始时间
            local file = io.open(recordPath, "ab")  -- 追加模式打开文件
            if file then
                file:write(buff:query()) -- 将缓冲区数据写入文件
                file:close()             -- 写入完成后关闭文件

                -- 计算写入速度
                local end_time = mcu.ticks()  -- 记录结束时间
                local write_time_ms = calc_time_diff_ms(start_time, end_time)

                if write_time_ms and write_time_ms > 0 then
                    local write_speed = size / (write_time_ms / 1000)  -- 字节/秒
                    log.info("TF卡写入统计",
                        "数据大小:", size, "字节,",
                        "写入耗时:", string.format("%.2f", write_time_ms), "ms,",
                        "写入速度:", string.format("%.2f", write_speed / 1024), "KB/s")
                else
                    log.info("TF卡写入统计",
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
        log.info("录音已开始")
        return true
    else
        log.error("录音启动失败")
        return false
    end
end

-- ========== TF卡挂载函数 ==========

-- 挂载SD卡
local function mount_sd_card()
    log.info("开始挂载SD卡")

    -- ##########  SD_EN引脚控制(仅Air160X_V1.2开发板需要) ##########
    -- Air160X_V1.2开发板: SD_EN引脚为GPIO56，挂载TF卡前必须拉高以使能供电
    -- Air1601_V1.1开发板: 无SD_EN引脚，无需此操作
    local SD_EN_PIN = 56
    gpio.setup(SD_EN_PIN, 1)

    -- ##########  SPI初始化 ##########
    spi.setup(sd_spi_id, nil, 0, 0, 8, 400000)
    -- 设置片选引脚同一spi总线上的所有从设备在初始化时必须要先拉高CS脚，防止从设备之间互相干扰。
    gpio.setup(sd_cs_pin, 1)

    -- ########## 开始进行tf卡挂载 ##########
    -- 挂载失败默认格式化，
    -- 如无需格式化应改为fatfs.mount(fatfs.SPI, "/sd", spi_id, pin_cs, 24000000, nil, 1, false),
    -- 一般是在测试硬件是否有问题的时候把格式化取消掉
    local mount_ok, mount_err = fatfs.mount(fatfs.SPI, sd_mount_path, sd_spi_id, sd_cs_pin, 24000000)

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

    -- 先挂载TF卡
    if not mount_sd_card() then
        log.error("TF卡挂载失败，录音文件将无法保存到TF卡")
        -- 如果TF卡挂载失败，使用内部存储路径
        recordPath = "/record.pcm"
    else
        log.info("TF卡挂载成功！！！")
    end

    -- LCD触摸也使用I2C1（1602_V1.2开发板特性），必须先拉高LCD_EN=GPIO57，
    -- 否则触摸芯片会干扰I2C1总线导致ES8311通信失败
    gpio.set(57, 1)
    
    if exaudio.setup(audio_setup_param) then
        -- 设置音量
        exaudio.vol(PLAY_VOLUME)
        exaudio.mic_vol(RECORD_VOLUME)

        log.info("音量设置", "播放:", PLAY_VOLUME, "录音:", RECORD_VOLUME)

        -- 检查是否有录音文件
        if io.exists(recordPath) then
            local file_size = io.fileSize(recordPath)
            log.info("找到录音文件", "大小:", file_size, "字节", "路径:", recordPath)
        else
            log.info("无录音文件", "路径:", recordPath)
        end

        log.info("音频系统初始化完成，准备开始录音")
        log.info("录音时长: ", RECORD_DURATION, "秒")
        log.info("录音完成后自动播放")
        log.info("录音文件保存到:", recordPath)
        sys.wait(1000)
        start_recording()
    else
        log.error("音频硬件初始化失败")
    end
end

sys.taskInit(main_audio_task)
