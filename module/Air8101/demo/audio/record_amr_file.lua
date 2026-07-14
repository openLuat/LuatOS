--[[
@module  record_amr_file
@summary 录音到文件（AMR格式）
@version 1.0
@date    2026.06.26
@author  拓毅恒
@usage

注意：
1. Air8101使用内置DAC输出音频，无需外部音频编解码芯片
2. 需要固件版本>=V1018才可播放音频
3. 此功能需要用Air8101B来测试，Air8101不支持

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

工作流程：
1. 初始化：挂载TF卡，设置音频硬件参数
2. 录音：流式录音（AMR_NB格式），实时写入TF卡
3. 播放：流式播放录音文件
4. 状态管理：互斥控制录音/播放状态
]]

local exaudio = require("exaudio")

-- TF卡配置参数（Air8101）
local sd_spi_id = 0            -- SPI接口编号
local sd_cs_pin = 32           -- TF卡片选引脚
local sd_power_pin = 50        -- TF卡电源/LDO控制引脚
local sd_mount_path = "/sd"    -- TF卡挂载路径

-- 录音文件路径（保存到TF卡）
local recordPath = sd_mount_path .. "/record.amr"

-- 硬件配置参数 (DAC模式)
local audio_setup_param ={
    model = "dac",            -- 音频编解码类型: "dac" 表示使用内置DAC
    
    pa_ctrl = 27,             -- 音频放大器电源控制管脚
    pa_on_level = 1,          -- PA打开电平
    pa_delay = 10            -- PA延时
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
        stop_recording()
    elseif is_playing then
        stop_playback()
    else
        start_recording()
    end
end

-- BOOT键：开始/停止播放，停止录音
local function boot_key_handler()
    log.info("按下BOOT键")
    
    if is_recording then
        stop_recording()
    elseif is_playing then
        stop_playback()
    else
        start_playback()
    end
end

-- ========== 初始化设置 ==========

-- 设置POWERKEY键（开始/停止录音）
gpio.setup(29, powerkey_handler, gpio.PULLUP, gpio.FALLING)
gpio.debounce(29, 200, 1)

-- 设置BOOT键（开始/停止播放，停止录音）
gpio.setup(37, boot_key_handler, gpio.PULLUP, gpio.FALLING)
gpio.debounce(37, 200, 1)

-- ========== TF卡挂载函数 ==========

-- 挂载TF卡
local function mount_tf_card()
    log.info("开始挂载TF卡")
    
    -- 打开TF卡电源
    gpio.setup(sd_power_pin, 1, gpio.PULLUP)
    -- 拉高CS脚避免干扰
    gpio.setup(sd_cs_pin, 1, gpio.PULLUP)
    
    -- CH390 电源走的VBAT拨码开关，还有个LDO开关，对应GPIO53 ，CS脚GPIO34
    gpio.setup(53, 1, gpio.PULLUP) 
    gpio.setup(34, 1, gpio.PULLUP)

    -- little flash 电源走的VBAT拨码开关 还有个LDO开关 对应 GPIO48   CS脚GPIO49
    gpio.setup(48, 1, gpio.PULLUP)
    gpio.setup(49, 1, gpio.PULLUP)
    
    -- 配置SPI0引脚功能
    pins.setup(6, "SPI0_MISO")
    pins.setup(71, "SPI0_MOSI")
    pins.setup(72, "SPI0_CLK")
    
    -- 初始化SPI接口
    spi.setup(sd_spi_id, nil, 0, 0, 8, 400 * 1000)
    gpio.setup(sd_cs_pin, 1)
    
    -- 挂载TF卡，挂载失败时不自动格式化
    local mount_ok, mount_err = fatfs.mount(fatfs.SPI, sd_mount_path, sd_spi_id, sd_cs_pin, 16 * 1000 * 1000, sd_power_pin, 100, false)
    
    if mount_ok then
        log.info("TF卡挂载成功", "挂载路径:", sd_mount_path)
        
        -- 获取TF卡空间信息
        local data, err = fatfs.getfree(sd_mount_path)
        if data then
            log.info("TF卡空间信息", json.encode(data))
        else
            log.warn("获取TF卡空间信息失败", err)
        end
        
        return true
    else
        log.error("TF卡挂载失败", mount_err)
        return false
    end
end

-- ========== 音频主任务 ==========

local function main_audio_task()
    log.info("音频系统初始化")
    
    -- 先挂载TF卡
    if not mount_tf_card() then
        log.error("TF卡挂载失败，录音文件将无法保存到TF卡")
        -- 如果TF卡挂载失败，使用内部存储路径
        recordPath = "/record.amr"
    else
        log.info("TF卡挂载成功！！！")
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
        
        log.info("按键功能说明：")
        log.info("1. Power键: 开始/停止录音，停止播放")
        log.info("2. Boot键: 开始/停止播放，停止录音")  
        log.info("3. 录音时长: ", RECORD_DURATION, "秒，可提前结束")
        log.info("4. 录音完成后自动播放")
        log.info("5. 录音文件保存到:", recordPath)
    else
        log.error("音频硬件初始化失败")
    end
end

sys.taskInit(main_audio_task)
