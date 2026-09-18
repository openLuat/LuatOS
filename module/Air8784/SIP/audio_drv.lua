--[[
@module audio_drv
@summary Air8784 + Air1103：官方扩展库适配及 SIP PCM 桥接
@date 2026.09.18
依赖 v2026.09.17.15 的 exaudio.lua / air1103.lua，原样随工程附带。
硬件保持 config.audio：UART1/2Mbps、GPIO22 高电平供电。
参考 SIP_8101B_1103 的默认库适配，但不采用其 UART2/VBAT 接线。
业务接口：init/start/stop/is_ready/is_running/check_firmware。
init 在 sys 任务中调用；收到真实 MIC PCM 后才报告就绪。
播放通过 exaudio；回调、复位和队列查询使用 air1103 公开接口。
不要同时启动 exaudio.record_start，它会替换本模块的 MIC 回调。
]]

local exaudio = require "exaudio"
local air1103 = require "air1103"
local driver = {}
local opened = false
function driver.uninit()
    if opened then pcall(exaudio.play_stop, {type=2}) end
    opened = false
    return air1103.uninit()
end
function driver.init(id, baud)
    assert(baud == 2000000, "Air1103 PCM firmware requires 2Mbps")
    driver.uninit()
    local ok, result = pcall(exaudio.setup, {model="air1103", uart_id=id,
        audio_mode="new", bits_per_sample=16, channels=1})
    if not ok or not result then
        pcall(air1103.uninit)
        log.error("audio_drv", "DEFAULT_AUDIO_SETUP_FAILED", result)
        return false
    end
    opened = true
    log.info("audio_drv", "DEFAULT_AUDIO_LIBS", "exaudio", exaudio.version(), "air1103", "UART", id)
    -- 默认setup未检查UART返回值，媒体层必须等待真实MIC_READY。
    return true
end
function driver.on_audio_data(cb) air1103.on_audio_data(cb) end
function driver.set_rx_enable(enabled) air1103.set_rx_enable(enabled) end
function driver.reset()
    air1103.set_rx_enable(false) -- 通过公开接口清除旧半帧
    local result = air1103.reset()
    air1103.set_rx_enable(true)
    return result
end
-- 配置沿用Air1103的0..31档位；默认exaudio.vol参数为0..100。
-- 向上取整，确保其floor(percent*31/100)准确还原原始档位。
function driver.set_volume(value)
    if type(value) ~= "number" or value ~= value then return false end
    local level = math.max(0, math.min(31, math.floor(value)))
    local percent = math.ceil(level * 100 / 31)
    return exaudio.vol(percent)
end
function driver.play_stream_start(value)
    if not opened or not driver.set_volume(value) then return false end
    return exaudio.play_start({type=2}) and air1103.is_running()
end
function driver.play_stream_write(data) return exaudio.play_stream_write(data) end
function driver.play_stream_stop() return exaudio.play_stop({type=2}) end
function driver.get_pending() return air1103.get_pending() end


-- ==================== 模块与配置 ====================

local M = {}
local cfg = require("config").audio
local test_mode = cfg.test_mode or "NORMAL"
assert(test_mode == "NORMAL" or test_mode == "SKIP_UPLINK_RESAMPLE"
    or test_mode == "STOP_DOWNLINK_UART", "Unknown audio test mode")
local skip_uplink_resample = test_mode == "SKIP_UPLINK_RESAMPLE"
local stop_downlink_uart = test_mode == "STOP_DOWNLINK_UART"
local silent_uplink = string.rep("\0", 256) -- 128 samples / 16ms at 8kHz
-- driver 为上方官方扩展库适配器。

-- ==================== 运行状态与统计 ====================

-- PCM转换在C层逐样本处理；Lua只传递整帧字符串和保留未消费尾部。
local str_sub = string.sub
local int_max, int_min = math.max, math.min
local clock_ticks = mcu.ticks2
local initialized, ready, running = false, false, false
local playback = false
local play_target = math.max(40, math.min(120, tonumber(cfg.play_buffer_ms) or 60)) // 10 * 320
local mic_gain = math.max(1, math.min(8, math.floor(tonumber(cfg.mic_gain) or 1)))
local mic_clipped = 0
local play_timer, stats_timer, capture_timer
local capture_queue, capture_head, capture_count = {}, 1, 0
local first_input, first_output = true, true
local mic_frames, tx_samples, rx_samples, dropped = 0, 0, 0, 0
local silent_ms = 0
local uplink = ""
local down_converter, up_converter
local last_accept_s, last_accept_us, stall_reported = 0, 0, false
-- 7 tap 二项式低通 [1,6,15,20,15,6,1]/64。
-- 调试通话用：高频衰减较明显，换取低 CPU 开销；不等同于原 3.4kHz FIR。
local last_mic_s, last_mic_us = 0, 0
local max_capture_us, max_input_us, max_output_us, max_play_us = 0, 0, 0, 0

-- ==================== 时间与重采样辅助函数 ====================

local function elapsed_us(seconds, micros)
    local now_s, now_us = clock_ticks(0)
    -- 先求差再相乘，避免拼接长时间运行的绝对微秒数。
    return (now_s - seconds) * 1000000 + now_us - micros
end

local function reset_resampler()
    if down_converter then
        down_converter:reset()
    end
    if up_converter then
        up_converter:reset()
    end
    uplink = ""
    capture_queue, capture_head, capture_count = {}, 1, 0
end

local function downsample(pcm)
    local converted, clipped = down_converter:process(pcm)
    mic_clipped = mic_clipped + clipped
    return converted
end

local function upsample(pcm)
    local count = #pcm // 2
    if count < 1 or count > 160 or #pcm % 2 ~= 0 then
        return ""
    end
    return up_converter:process(pcm)
end

-- ==================== 上行音频采集 ====================

local function receive_pcm(data)
    if type(data) ~= "string" or #data ~= 512 then
        return
    end
    last_mic_s, last_mic_us = clock_ticks(0)
    mic_frames = mic_frames + 1
    if not ready then
        ready = true
        log.info("audio_1103", "MIC_READY", "收到合法 16kHz PCM 帧")
        sys.publish("AUDIO_1103_READY")
    end
    if not running then -- 空闲时不把麦克风数据送入 RTP
        return
    end
    -- UART 回调只入队；重采样和原生 PCM 接口在独立定时器执行。
    if capture_count == 8 then
        capture_queue[capture_head] = nil
        capture_head = capture_head % 8 + 1
        capture_count = capture_count - 1
        dropped = dropped + 128
    end
    local tail = (capture_head + capture_count - 1) % 8 + 1
    capture_queue[tail] = data
    capture_count = capture_count + 1
end

local function capture_tick()
    if not running or not voip.isRunning() then
        return
    end
    -- 每 10ms 最多处理一帧（16ms 音频），必须返回调度器。
    if capture_count > 0 and #uplink == 0 then
        local data = capture_queue[capture_head]
        capture_queue[capture_head] = nil
        capture_head = capture_head % 8 + 1
        capture_count = capture_count - 1
        local begin_s, begin_us = clock_ticks(0)
        if skip_uplink_resample then
            uplink = silent_uplink
        else
            uplink = downsample(data)
        end
        max_capture_us = int_max(max_capture_us, elapsed_us(begin_s, begin_us))
    end
    if #uplink == 0 then
        return
    end
    if first_input then
        log.info("audio_1103", "PCM_IN_ENTER", #uplink)
    end
    local begin_s, begin_us = clock_ticks(0)
    local consumed = tonumber(voip.pcmIn(uplink)) or 0 -- 单位：样本，不是字节
    max_input_us = int_max(max_input_us, elapsed_us(begin_s, begin_us))
    if first_input then
        log.info("audio_1103", "PCM_IN_RETURN", consumed)
        first_input = false
    end
    consumed = int_max(0, int_min(#uplink // 2, consumed))
    if consumed > 0 then
        last_accept_s, last_accept_us = clock_ticks(0)
        stall_reported = false
    end
    tx_samples = tx_samples + consumed
    uplink = str_sub(uplink, consumed * 2 + 1)
end

local function capture_poll()
    if not running then
        return
    end
    capture_tick()
    -- 单次定时器在工作结束后重启，避免周期事件积压后集中补执行。
    -- 积压时短延时追赶；原生PCM尚未消费时退让。
    local delay = #uplink > 0 and 10 or (capture_count > 0 and 2 or 5)
    if running then
        capture_timer = sys.timerStart(capture_poll, delay)
    end
end

-- ==================== 固件能力检查 ====================

function M.check_firmware()
    for _, name in ipairs({"setAudioMode", "pcmIn", "pcmOut", "pcmResampler", "start", "stop", "isRunning", "on"}) do
        if not voip or type(voip[name]) ~= "function" then
            return false, "底层固件缺少 voip." .. name
        end
    end
    if not audio_v2 then
        return false, "当前 exsip PCM bridge 路径需要 audio_v2 固件"
    end
    if voip.AUDIO_MODE_BRIDGE == nil then
        return false, "底层固件缺少 PCM bridge 模式"
    end
    return true
end

-- ==================== 音频初始化 ====================

-- 在 sys.task 中调用；有界等待真实上行，不能把 UART setup 成功当成芯片就绪。
function M.init()
    if initialized and M.is_ready() then
        return true
    end
    if running then
        return false
    end
    local ok, err = M.check_firmware()
    if not ok then
        log.error("audio_1103", err)
        return false
    end
    if not down_converter then
        local ok_down, mic_converter = pcall(voip.pcmResampler, 16000, 8000, mic_gain)
        local ok_up, speaker_converter = pcall(voip.pcmResampler, 8000, 16000)
        if not ok_down or not ok_up or not mic_converter or not speaker_converter then
            log.error("audio_1103", "原生PCM重采样器创建失败")
            return false
        end
        down_converter, up_converter = mic_converter, speaker_converter
    end
    -- 已初始化但复位后无PCM，必须重开UART并清除解析状态，不能永久返回false。
    if initialized then
        log.warn("audio_1103", "RECOVER_BEGIN", "重新初始化UART和1103")
        driver.uninit()
    end
    initialized, ready = false, false
    reset_resampler()
    if type(cfg.power_gpio) == "number" then
        gpio.setup(cfg.power_gpio, cfg.power_on_level or 1)
    end
    sys.wait(cfg.boot_ms)
    if not driver.init(cfg.uart_id, 2000000) then
        driver.uninit()
        return false
    end
    -- 指定版 exaudio 的 Air1103 SIP 钩子为空操作，由本层接入实际 PCM。
    exaudio.sip_voip_start = M.start
    exaudio.sip_voip_stop = M.stop
    driver.on_audio_data(receive_pcm)
    driver.set_rx_enable(true)
    if not driver.reset() then
        driver.uninit()
        return false
    end
    local elapsed = 0
    while not ready and elapsed < cfg.ready_timeout_ms do
        sys.waitUntil("AUDIO_1103_READY", 100)
        elapsed = elapsed + 100
    end
    if not ready then
        log.error("audio_1103", "未收到1103音频帧，检查固件/供电/UART1/电平", "UART", cfg.uart_id)
        driver.uninit()
        return false
    end
    driver.set_volume(cfg.volume)
    initialized = true
    log.info("audio_1103", "初始化完成", "UART", cfg.uart_id, "baud", 2000000, "power GPIO", cfg.power_gpio)
    return true
end

-- ==================== 启动双向音频桥接 ====================

function M.start(session)
    if not M.is_ready() then
        return false
    end
    if session and tonumber(session.sample_rate or 8000) ~= 8000 then
        log.error("audio_1103", "仅支持8kHz G711会话")
        return false
    end
    if running then
        return true
    end
    reset_resampler()
    tx_samples, rx_samples, dropped, silent_ms = 0, 0, 0, 0
    mic_clipped = 0
    if not stop_downlink_uart then
        if not driver.play_stream_start(cfg.volume) then
            return false
        end
        playback = true
    end
    running = true
    log.warn("audio_1103", "TEST_MODE", test_mode)
    log.info("audio_1103", "PCM_CONVERTER", "native", "16k<->8k")
    first_input, first_output = true, true
    last_mic_s, last_mic_us = clock_ticks(0)
    max_capture_us, max_input_us, max_output_us, max_play_us = 0, 0, 0, 0
    last_accept_s, last_accept_us = clock_ticks(0)
    stall_reported = false
    capture_timer = sys.timerStart(capture_poll, 10)
    local function playback_work()
        if not running or not voip.isRunning() then
            return
        end
        if not stop_downlink_uart and driver.get_pending() >= play_target + 640 then
            return
        end
        -- 单次最多取20ms；按队列水位补数据，播放时钟由UART驱动保持。
        -- driver 内部按320字节/10ms送出，缺数据时补静音。
        if first_output then
            log.info("audio_1103", "PCM_OUT_ENTER")
        end
        local begin_s, begin_us = clock_ticks(0)
        local pcm = voip.pcmOut(160)
        max_output_us = int_max(max_output_us, elapsed_us(begin_s, begin_us))
        if first_output then
            log.info("audio_1103", "PCM_OUT_RETURN", pcm and #pcm or 0)
            first_output = false
        end
        if pcm and #pcm > 0 then
            rx_samples = rx_samples + #pcm // 2
            local output = upsample(pcm)
            -- Test B keeps resampling cost, isolating UART packetization/playback work.
            if not stop_downlink_uart then
                driver.play_stream_write(output)
            end
        end
    end
    local function playback_tick()
        if not running then
            return
        end
        local begin_s, begin_us = clock_ticks(0)
        playback_work()
        local work_us = elapsed_us(begin_s, begin_us)
        max_play_us = int_max(max_play_us, work_us)
        -- 5ms检查队列水位，水位充足时不转换，防止定时回调迟到累积速率误差。
        if running then
            play_timer = sys.timerStart(playback_tick, 5)
        end
    end
    play_timer = sys.timerStart(playback_tick, 20)
    local function microphone_stats_tick()
        if not running then
            return
        end
        silent_ms = elapsed_us(last_mic_s, last_mic_us) // 1000
        log.info("audio_1103", "PCM", "mic_frames", mic_frames, "tx", tx_samples,
            "rx", rx_samples, "dropped", dropped, "queued16k", capture_count, "pending16k", driver.get_pending(), "mic_age_ms", silent_ms,
            "max_us resample/in/out", max_capture_us, max_input_us, max_output_us, "play_us", max_play_us,
            "mic_gain", mic_gain, "mic_clipped", mic_clipped, "test_mode", test_mode)
        if #uplink > 0 and elapsed_us(last_accept_s, last_accept_us) >= 2000000 and not stall_reported then
            stall_reported = true
            sys.publish("AUDIO_1103_ERROR", "PCM发送持续阻塞")
            M.stop()
            log.error("audio_1103", "PCM_TX_STALLED", "底层持续未消费PCM", "pending8k", #uplink)
        end
        if silent_ms >= cfg.mic_timeout_ms then
            ready = false
            sys.publish("AUDIO_1103_ERROR", "通话中1103上行中断")
            M.stop()
        end
        if running then
            stats_timer = sys.timerStart(microphone_stats_tick, 1000)
        end
    end
    stats_timer = sys.timerStart(microphone_stats_tick, 1000)
    log.info("audio_1103", "BRIDGE_STARTED", "UART16k <-> RTP8k")
    return true
end

-- ==================== 停止双向音频桥接 ====================

function M.stop()
    running = false
    if capture_timer then
        sys.timerStop(capture_timer)
        capture_timer = nil
    end
    if play_timer then
        sys.timerStop(play_timer)
        play_timer = nil
    end
    if stats_timer then
        sys.timerStop(stats_timer)
        stats_timer = nil
    end
    reset_resampler()
    if playback then
        playback = false
        driver.play_stream_stop() -- 原协议同时停止上行；必须复位才能恢复MIC
        ready = false
        driver.reset()
        driver.set_rx_enable(true)
    end
    -- 保持 GPIO22 供电，不在每次挂断时切换 Q4；协议复位恢复 MIC。
end

-- ==================== 状态查询 ====================

function M.is_ready()
    if ready and elapsed_us(last_mic_s, last_mic_us) >= cfg.mic_timeout_ms * 1000 then
        ready = false
    end
    return initialized and ready
end
function M.is_running()
    return running
end

return M
