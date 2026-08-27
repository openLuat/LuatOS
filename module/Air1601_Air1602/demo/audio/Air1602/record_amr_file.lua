--[[
@module  record_amr_file
@summary 录音到文件（AMR格式）
@version 1.0
@date    2026.06.26
@author  拓毅恒
@usage

注意：
1. Air1602_V1.2开发板使用ES8311编解码芯片，录音走I2S2，播放走内置DAC
2. 需要固件版本>=V1026才可播放音频
3. LCD触摸芯片占用I2C1总线，必须先拉高LCD_EN(GPIO57)，否则会干扰ES8311通信
4. 挂载SD卡前需先拉高SD_EN(GPIO56)使能SD供电（Air160X_V1.2开发板特性）
5. 录制AMR_NB格式音频，需要使用支持新音频框架的固件

录音到文件演示程序（开机自动运行，无需按键）：
1. 自动挂载SD卡，挂载失败自动回退内部存储
2. 自动开始5秒录音（AMR_NB格式）
3. 录音完成后自动播放录音文件

音量设置：
  播放音量：75
  录音麦克风音量：80

录音逻辑：
  录音时长为5秒，并计时
  录音时长到自动停止
  录音完成后自动播放录音文件

工作流程：
1. 初始化：挂载SD卡（失败自动回退内部存储），设置音频硬件参数
2. 录音：流式录音（AMR_NB格式），保存到SD卡
3. 播放：录音完成后自动播放录音文件
]]

local exaudio = require("exaudio")

-- SD卡配置参数
local sd_spi_id = 1            -- SPI接口编号
local sd_cs_pin = 8            -- 片选引脚
local sd_mount_path = "/sd"    -- SD卡挂载路径

-- 录音文件路径（SD卡挂载成功后保存到SD卡，失败则保存到内部存储）
local recordPath = "/record.amr"

-- 硬件配置参数（ES8311 + I2S2模式）
-- Air1602_V1.2开发板使用I2S2接ES8311编解码芯片，输出走内置DAC
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
    i2s_sample = 8000,        -- I2S采样率
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
local record_timer = nil       -- 录音计时器
local record_seconds = 0       -- 录音计时秒数

-- 音量设置
local PLAY_VOLUME = 75         -- 播放音量
local RECORD_VOLUME = 80       -- 录音麦克风音量

-- 录音时长设置（秒）
local RECORD_DURATION = 5      -- 录音时长

-- ========== 播放相关函数 ==========

-- 播放完成回调函数
local function play_end_callback(event)
    if event == exaudio.PLAY_DONE then
        log.info("播放完成")
    end
end

-- 开始播放录音文件
local function start_playback()
    log.info("录音文件路径", recordPath)
    
    if io.exists(recordPath) then
        local audio_play_param = {
            type = 0,
            content = recordPath,
            cbfnc = play_end_callback,
            priority = 1
        }

        local file_size = io.fileSize(recordPath)
        if file_size > 0 then
            log.info("播放录音文件", "大小:", file_size, "字节")
            local play_result = exaudio.play_start(audio_play_param)
            if not play_result then
                log.error("播放启动失败")
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
    
    -- 删除旧录音文件
    if io.exists(recordPath) then
        os.remove(recordPath)
        log.info("删除旧录音文件")
    end
    
    -- 设置录音麦克风音量
    exaudio.mic_vol(RECORD_VOLUME)
    
    local audio_record_param = {
        format = exaudio.AMR_NB,
        time = RECORD_DURATION,
        path = recordPath,
        cbfnc = record_end_callback
    }
    
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

-- ========== SD卡挂载函数 ==========

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
    -- LCD_EN 高电平有效，不同板子选用对应引脚，多余配置注释屏蔽
    -- Air1601_V1.1开发板/Air8601/Air8602：注释下方这一行
    -- Air160X_V1.2开发板：LCD_EN = GPIO57
    gpio.setup(57, 1, gpio.PULLUP)

    log.info("音频系统初始化")
    
    -- 先挂载SD卡
    if mount_sd_card() then
        -- SD卡挂载成功，录音文件保存到SD卡
        recordPath = sd_mount_path .. "/record.amr"
        log.info("录音文件将保存到SD卡:", recordPath)
    else
        -- SD卡挂载失败，回退到内部存储
        recordPath = "/record.amr"
        log.warn("SD卡挂载失败，录音文件将保存到内部存储:", recordPath)
    end

    if exaudio.setup(audio_setup_param) then
        -- 设置音量
        exaudio.vol(PLAY_VOLUME)
        exaudio.mic_vol(RECORD_VOLUME)
        
        log.info("音量设置", "播放:", PLAY_VOLUME, "录音:", RECORD_VOLUME)
        
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
