--[[
@module  audio_1103
@summary 1103 电源、串口驱动、16k/8k PCM 转换及 SIP 双向桥接
@version 1.0
@date    2026.09.16
@description
本模块是设备适配层，内部复用 Air1103；业务层通过 audio_drv 调用。
通过 AP 库初始化 audio_v2，实际音频传输走 UART。
1103 须使用兼容 Air1103 协议的固件，主控固件须支持 voip.pcmResampler。
]]

-- ==================== 模块与配置 ====================

local M = {}
local cfg = require("config").audio
local test_mode = cfg.test_mode or "NORMAL"
assert(test_mode == "NORMAL" or test_mode == "SKIP_UPLINK_RESAMPLE"
    or test_mode == "STOP_DOWNLINK_UART", "Unknown audio test mode")
local skip_uplink_resample = test_mode == "SKIP_UPLINK_RESAMPLE"
local stop_downlink_uart = test_mode == "STOP_DOWNLINK_UART"
local silent_uplink = string.rep("\0", 256) -- 128 samples / 16ms at 8kHz
local driver = require "air1103"
local exaudio = require "exaudio"

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
    if voip.AUDIO_MODE_BRIDGE == nil then
        return false, "底层固件缺少 PCM bridge 模式"
    end
    return true
end

-- ==================== 音频初始化 ====================

-- 在 sys.task 中调用；有界等待真实上行，不能把 UART setup 成功当成芯片就绪。
function M.init()
    if initialized and ready then
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
        local mic_converter = voip.pcmResampler(16000, 8000, mic_gain)
        local speaker_converter = voip.pcmResampler(8000, 16000)
        down_converter, up_converter = mic_converter, speaker_converter
    end
    -- 已初始化但复位后无PCM，必须重开UART并清除解析状态，不能永久返回false。
    if initialized then
        log.warn("audio_1103", "RECOVER_BEGIN", "重新初始化UART和1103")
        driver.uninit()
    end
    initialized, ready = false, false
    reset_resampler()
    gpio.setup(cfg.power_gpio, 1)
    sys.wait(cfg.boot_ms)
    if not audio_v2 then
        log.error("audio_1103", "需要支持 audio_v2 的固件")
        return false
    end
    if not exaudio.setup({model = "Air1103", audio_mode = "new", uart_id = cfg.uart_id}) then
        driver.uninit()
        return false
    end
    -- AP exaudio 的 SIP 钩子默认只返回成功；在设备适配层接入实际 PCM。
    exaudio.sip_voip_start = M.start
    exaudio.sip_voip_stop = M.stop
    driver.on_audio_data(receive_pcm)
    driver.set_rx_enable(true)
    driver.reset()
    local elapsed = 0
    while not ready and elapsed < cfg.ready_timeout_ms do
        sys.waitUntil("AUDIO_1103_READY", 100)
        elapsed = elapsed + 100
    end
    if not ready then
        log.error("audio_1103", "未收到1103音频帧，检查固件/供电/UART1/电平")
        driver.uninit()
        return false
    end
    driver.set_volume(cfg.volume)
    initialized = true
    log.info("audio_1103", "初始化完成", "UART1=2M", "power GPIO", cfg.power_gpio)
    return true
end

-- ==================== 启动双向音频桥接 ====================

function M.start(session)
    if not initialized or not ready then
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
    -- 保持1103供电，避免原理图UART/MUTE回灌；不在每次挂断时切Q4。
end

-- ==================== 状态查询 ====================

function M.is_ready()
    return initialized and ready
end
function M.is_running()
    return running
end

return M
