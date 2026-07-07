--[[
@module  record_pcm_file
@summary 流式录音到文件功能（PCM格式）
@version 1.0
@date    2026.07.06
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
  播放音量：70
  录音麦克风音量：70

录音逻辑：
  录音时长为5秒，并计时
  录音过程中可以按任意键提前结束
  录音完成后录音文件保存在TF卡或内部存储中

播放逻辑：
  使用流式播放方式播放PCM格式录音文件
  演示使用16kHz采样率、16位采样深度、有符号PCM数据
  注意：播放采样位深仅支持到24位，如果录制32位录音则无法播放，需要用电脑进行播放！！！

工作流程：
1. 初始化：挂载TF卡，设置音频硬件参数
2. 录音：流式录音，实时写入TF卡，显示写入速度统计
3. 播放：流式播放，按下BOOT按键读取文件并播放
4. 状态管理：互斥控制录音/播放状态
]]

local exaudio = require("exaudio")

-- TF卡配置参数（Air8101）
local sd_spi_id = 0            -- SPI接口编号
local sd_cs_pin = 32           -- TF卡片选引脚
local sd_power_pin = 50        -- TF卡电源/LDO控制引脚
local sd_mount_path = "/sd"    -- TF卡挂载路径

-- 录音文件路径（保存到TF卡）
local recordPath = sd_mount_path .. "/record.pcm"

-- 硬件配置参数 (DAC模式)
local audio_setup_param = {
    model = "dac",            -- 音频编解码类型: "dac" 表示使用内置DAC

    pa_ctrl = 27,             -- 音频放大器电源控制管脚
    pa_on_level = 1,          -- PA打开电平
    pa_delay = 10             -- PA延时
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

-- 停止播放
local function stop_playback()
    if is_playing then
        log.info("停止流式播放")
        exaudio.play_stop({type = 2})  -- 停止流式播放
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
    if is_recording then
        log.info("已经在录音中")
        return false
    end

    if is_playing then
        log.info("正在播放中，停止播放")
        stop_playback()
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

-- ========== 按键处理函数 ==========

-- POWERKEY键：开始/停止录音，停止播放
local function powerkey_handler()
    log.info("按下POWERKEY键")

    if is_recording then
        log.info("正在录音中，停止录音")
        stop_recording()
    elseif is_playing then
        log.info("正在播放中，停止播放")
        stop_playback()
    else
        log.info("空闲状态，开始录音")
        start_recording()
    end
end

-- BOOT键：开始/停止播放，停止录音
local function boot_key_handler()
    log.info("按下BOOT键")

    if is_recording then
        log.info("正在录音中，停止录音")
        stop_recording()
    elseif is_playing then
        log.info("正在播放中，停止播放")
        stop_playback()
    else
        log.info("空闲状态，播放录音")
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

    -- CH390 电源走的VBAT拨码开关，还有个LDO开关，对应GPIO53，CS脚GPIO34
    gpio.setup(53, 1, gpio.PULLUP)
    gpio.setup(34, 1, gpio.PULLUP)

    -- little flash 电源走的VBAT拨码开关，还有个LDO开关，对应GPIO48，CS脚GPIO49
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
        recordPath = "/record.pcm"
    else
        log.info("TF卡挂载成功！！！")
    end

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

        log.info("按键功能说明：")
        log.info("1. Power键: 开始/停止录音，停止播放")
        log.info("2. Boot键: 开始/停止播放，停止录音")
        log.info("3. 录音时长: ", RECORD_DURATION, "秒，可提前结束")
        log.info("4. 录音完成后按Boot键播放")
        log.info("5. 录音文件保存到:", recordPath)
    else
        log.error("音频硬件初始化失败")
    end
end

sys.taskInit(main_audio_task)
