--[[
@module sip_audio_app
@summary 功能测试-SIP通话：Air8605 UART6 Air1103 PCM 桥接（严格移植 Air8605 实测出声工程）
@description
蓝本：E:\luatools\userprojs\8605_sip_app_flash\...\SIP_APP\flash_files\app\audio\audio_app.lua
该工程在 Air8605 上实测双向出声，本文件逐函数对齐，仅做工厂适配：
  * setup 走工厂统一收口 audio_hw.setup（model=air1103, uart_id=6, audio_mode="new"）
  * MIC 上行：覆盖 chip.feed，用自带 55AA 解析器 sipapp_pcm_rx（比 air1103 内置解析器
    在嘈杂 UART 上更稳健：校验失败只丢 1 字节重同步，不丢整缓冲）
  * 上行在 UART 回调里直接 voip.pcmIn（按返回的已消费样本数做背压），不再用定时器搬运
  * 下行在单一 5ms 任务里 voip.pcmOut -> 8k->16k 重采样 -> chip.play_stream_write
  * 单一 owner + generation：tone/call/diagnostic 同一播放归属，停播放一律
    chip.play_stream_stop(true)，从不发 STOP-MIC、从不复位芯片（复位约1.4s且停MIC，
    是"卡顿、对端听不到"的直接原因）
  * 提示音用 res/air1103_*.pcm 文件流式播放（打包后在 /luadb/），不是芯片内置命令
  * MIC 归属：蓝本是精简固件、只有 SIP，可常驻占用 chip.feed/on_audio_data；
    工厂里通用录音页、AI 会话、外设录音页都会抢这两个回调。因此本模块在
    初始化与每次起桥前用 take_mic() 收回、MIC 断流时用 ensure_mic() 自愈
    （必要时软复位 Air1103 重启上行），只在 teardown（退出 SIP 页）交还。

对外接口（供 sip_test_app / ui 调用）：
  init / start / stop / stop_bridge / is_ready / is_running / is_bridge_ok
  set_mute / set_volume / get_volume / diagnostics
  play_ringback_loop / play_ringback / stop_ringback / play_hangup
]]

local M = {}

local ex_ok, exaudio = pcall(require, "exaudio")
local chip_ok, chip = pcall(require, "air1103")
local cfg = ((_G.project_config or {}).hw or {}).audio or {}
local volume = math.max(0, math.min(100, tonumber(cfg.play_vol) or 70))

local initialized, initializing = false, false
local owner, generation = nil, 0
local frames, rx_bytes, bad_frames, last_mic, peak = 0, 0, 0, 0, 0
local mic_rate, fps = nil, 0
local fault = nil
local capture, capture_bytes = nil, 0
local queue, pending = {}, ""
local input_resampler, output_resampler
local stats = { uplink = 0, downlink = 0, drops = 0 }
local diag_busy = false
local muted = false
local mic_gap_max = 0
local last_submit, submit_gap_max, input_blocked, input_partial = nil, 0, 0, 0
local last_loop, loop_gap_max = nil, 0
local uplink_error
local prestart_frames, near_clip_frames = 0, 0

-- ==================== 工具 ====================

local function now()
    if mcu and mcu.ticks2 then
        local s, us = mcu.ticks2(0)
        return s * 1000 + (us or 0) / 1000
    end
    return os.time() * 1000
end

local function restore_touch()
    if _G.tp_drv and type(_G.tp_drv.i2c_restore) == "function" then
        pcall(_G.tp_drv.i2c_restore)
    end
end

local function signal_error(reason)
    fault = tostring(reason)
    log.error("sip_audio_app", fault)
    sys.publish("AUDIO_ERROR", fault)
    return false, fault
end

local function pcm_peak(data)
    local out = 0
    for i = 1, #data - 1, 16 do out = math.max(out, math.abs(string.unpack("<h", data, i))) end
    return out
end

-- ==================== 上行：MIC -> voip ====================
-- UART 回调本就运行在 Lua task 上下文，直接提交，不再加定时器唤醒；
-- 限制每次工作量，背压时保留所有未消费字节。
local function pump_uplink()
    if owner ~= "call" or uplink_error or not voip.isRunning() then return end
    for _ = 1, 4 do
        if #pending == 0 and #queue > 0 then
            pending = input_resampler:process(table.remove(queue, 1)) or ""
        end
        if #pending == 0 then break end
        local chunk = pending:sub(1, 640)
        local samples = tonumber(voip.pcmIn(muted and string.rep("\0", #chunk) or chunk)) or 0
        local used = math.max(0, math.min(#chunk // 2, math.floor(samples))) * 2
        if used == 0 then input_blocked = input_blocked + 1; break end
        local tick = now()
        if last_submit then submit_gap_max = math.max(submit_gap_max, tick - last_submit) end
        last_submit = tick
        pending = pending:sub(used + 1); stats.uplink = stats.uplink + used
        if used < #chunk then input_partial = input_partial + 1; break end
    end
end

local function on_pcm(data)
    if type(data) ~= "string" or #data ~= 512 then bad_frames = bad_frames + 1; return end
    local tick = now()
    if owner == "call" and last_mic > 0 then mic_gap_max = math.max(mic_gap_max, tick - last_mic) end
    frames, last_mic = frames + 1, tick
    -- 削顶诊断不需要逐帧精确：MIC 64 帧/秒、每帧 32 次 unpack，全算等于每秒
    -- 1500+ 次 C 调用白占调度时间。每 4 帧采一次足够反映电平和削顶。
    if frames % 4 == 0 then peak = pcm_peak(data) end
    if capture and capture_bytes + #data <= 112640 then
        capture[#capture + 1] = data; capture_bytes = capture_bytes + #data
    end
    if owner == "call" then
        if peak >= 32700 then near_clip_frames = near_clip_frames + 1 end
        -- 启动期 PCM 属于等待阶段，不属于已建立的通话
        if not voip.isRunning() then prestart_frames = prestart_frames + 1; return end
        if #queue >= 24 then table.remove(queue, 1); stats.drops = stats.drops + 1 end
        queue[#queue + 1] = data
        local ok, err = pcall(pump_uplink)
        if not ok then uplink_error = tostring(err) end
    end
end

-- 自带 55AA MIC 解析器（工厂适配：放在 app/sip 目录，与蓝本同名模块等价）
local pcm_rx = require "sipapp_pcm_rx"
local mic_parser = pcm_rx.new(on_pcm)
-- 工厂固件里通用录音页(factory_rec)/AI 会话也会把 chip.feed 与 chip.on_audio_data
-- 换成它们自己的回调，并且退出时还原。谁最后动过，MIC 就归谁。
-- 一旦 SIP 桥启动时 MIC 不在本模块手里：last_mic 不再更新 → is_ready() 为假 →
-- exsip 判定 sip_voip_start 失败并执行 voip.stop() → 整通电话完全没有声音。
-- 所以每次起桥/初始化都必须"收回" MIC，而通话结束不再交还（只有退出 SIP 页才交还），
-- 避免第 2 通电话起就再也拿不到上行。
local original_feed = chip_ok and chip.feed or nil
local sip_feed_fn
local function install_sip_feed()
    if not chip_ok or chip.feed == sip_feed_fn then return end
    original_feed = chip.feed
    chip.feed = sip_feed_fn
end
local function restore_original_feed()
    if not chip_ok then return end
    if original_feed then chip.feed = original_feed end
end
sip_feed_fn = function(data)
    if type(data) == "string" then
        rx_bytes = rx_bytes + #data
        return mic_parser.feed(data)
    end
end

-- 接管 MIC：解析器 + 上行回调 + 打开接收，三件套一起拿回来
local function take_mic()
    if not chip_ok then return false end
    install_sip_feed()
    if type(chip.on_audio_data) == "function" then chip.on_audio_data(on_pcm) end
    if type(chip.set_rx_enable) == "function" then pcall(chip.set_rx_enable, true) end
    return true
end

-- 上行是否真的在出帧（比 is_ready 的 3s 窗口更严，判定桥接能不能起来）
local function mic_alive(window)
    window = window or 500
    return last_mic > 0 and now() - last_mic <= window
end

-- 起桥前自愈：先收回 MIC；还不出帧就软复位一次（约1.4s）
-- @param wait_ms number|nil 收回后等待出帧的时间
-- @return boolean true=MIC 上行可用
local function ensure_mic(wait_ms)
    take_mic()
    local deadline = now() + (wait_ms or 300)
    while now() < deadline and not mic_alive(500) do sys.wait(20) end
    if mic_alive(500) then return true end
    if chip_ok and type(chip.reset) == "function" then
        log.warn("sip_audio_app", "MIC 无上行帧，软复位 Air1103 后重试")
        mic_parser.reset()
        pcall(chip.reset)
        local hard = now() + 2500
        while now() < hard and not mic_alive(500) do sys.wait(20) end
    end
    return mic_alive(500)
end

-- ==================== 能力检查 ====================

local function firmware()
    if _G.is_pc then return false, "PC 预览无 Air1103 硬件" end
    if not ex_ok then return false, "缺少 exaudio" end
    if not chip_ok then return false, "缺少 air1103" end
    for _, n in ipairs({ "init", "uninit", "on_audio_data", "set_rx_enable", "reset",
        "set_volume", "play_stream_start", "play_stream_write", "play_stream_stop",
        "get_pending", "is_running", "get_tx_error" }) do
        if type(chip[n]) ~= "function" then return false, "air1103 缺少 " .. n end
    end
    for _, n in ipairs({ "pcmIn", "pcmOut", "pcmResampler", "isRunning" }) do
        if not voip or type(voip[n]) ~= "function" then return false, "voip 缺少 " .. n end
    end
    -- 走 UART 语音芯片的桥接必须有 PCM 桥接口，否则 exsip 会退回 I2S 直出，
    -- 声音进了 DAC 而不是 Air1103，表现为整通电话没声音且没有任何报错。
    if type(voip.setAudioMode) ~= "function" or voip.AUDIO_MODE_BRIDGE == nil then
        return false, "固件未编入 VoIP PCM 桥接(voip.setAudioMode/AUDIO_MODE_BRIDGE)"
    end
    return true
end

function M.check_firmware() return firmware() end

-- ==================== 播放归属（tone/call/diagnostic 同一 owner）====================

local function set_chip_volume()
    local ok, result = pcall(chip.set_volume, math.floor(volume * 31 / 100))
    return ok and result ~= false
end

local function stop_stream()
    if chip_ok then pcall(chip.play_stream_stop, true) end
    restore_touch()
end

local function cancel_playback()
    generation = generation + 1
    owner = nil; queue = {}; pending = ""
    stop_stream()
end

local function start_stream(kind)
    if not initialized then return false, "audio_not_initialized" end
    if owner then return false, "audio_busy" end
    local ok, result, why = pcall(chip.play_stream_start, math.floor(volume * 31 / 100),
        { report_tx_error = true })
    restore_touch()
    if not ok or not result then return false, why or "speaker_start_failed" end
    generation = generation + 1; owner = kind
    return true, generation
end

local function stream_ok(token)
    return token == generation and owner ~= nil and chip.is_running() and not chip.get_tx_error()
end

local function finish_stream(token)
    if token == generation then cancel_playback() end
end

local function feed_pcm(token, data)
    -- 每次写入保持小块；驱动队列有界，不要整段提交录音
    for pos = 1, #data, 640 do
        while stream_ok(token) and chip.get_pending() > 1920 do sys.wait(10) end
        if not stream_ok(token) then return false, chip.get_tx_error() or "playback_cancelled" end
        chip.play_stream_write(data:sub(pos, pos + 639))
    end
    return true
end

local function drain(token)
    local deadline = now() + 3000
    while stream_ok(token) and chip.get_pending() > 0 and now() < deadline do sys.wait(10) end
    if not stream_ok(token) then return false, chip.get_tx_error() or "playback_cancelled" end
    if chip.get_pending() > 0 then return false, "speaker_drain_timeout" end
    sys.wait(40)
    return true
end

local function pcm_converter(source_rate, target_rate, channels)
    -- V1028 拒绝等率转换；等率时原样保留 PCM 字节
    if source_rate == target_rate then
        return { reset = function() end, process = function(_, data) return data end }
    end
    return voip.pcmResampler(source_rate, target_rate, channels)
end

-- ==================== MIC 等待/重开 ====================

local function wait_mic(stage)
    install_sip_feed()
    chip.on_audio_data(on_pcm); chip.set_rx_enable(true)
    mic_parser.reset()
    frames, last_mic = 0, 0
    local before = rx_bytes
    assert(chip.reset(), "Air1103 复位命令失败")
    local deadline = now() + 6000
    while frames == 0 and now() < deadline do sys.wait(50) end
    local p = mic_parser.stats()
    log.info("sip_audio_app", "MIC recovery", stage, "rx_bytes", rx_bytes - before,
        "frames", frames, "pending", p.pending, "checksum_errors", p.checksum_errors)
    return frames > 0
end

local function reopen_mic(power_cycle)
    -- 先停喇叭，避免 teardown 期间发 STOP-MIC
    stop_stream()
    assert(chip.uninit(), "Air1103 UART teardown 失败")
    if power_cycle then
        gpio.setup(cfg.power_gpio or 73, 0)
        sys.wait(300)
    end
    local ok, result = pcall(chip.init, cfg.uart_id or 6, cfg.baud or 2000000)
    if power_cycle then
        gpio.setup(cfg.power_gpio or 73, 1)
        sys.wait(800)
    end
    assert(ok and result, "Air1103 UART reopen 失败")
    install_sip_feed()
    chip.on_audio_data(on_pcm); chip.set_rx_enable(true)
end

-- ==================== 初始化（必须在 sys task 内）====================

function M.init()
    if initialized and M.is_ready() then return true end
    if initializing or owner then return false, "audio_busy" end
    local supported, reason = firmware()
    if not supported then return signal_error(reason) end
    initializing = true; initialized = false; fault = nil
    local ok, err = pcall(function()
        gpio.setup(cfg.power_gpio or 73, 1)
        -- Air1103 上电到就绪约 1.4s（见 config 注释 boot_ms=1500）
        sys.wait(tonumber(cfg.boot_ms) or 1500)
        -- 工厂统一收口 exaudio.setup；这里显式再给一遍蓝本原样的 air1103 入参：
        -- audio_hw.params 的 model/uart_id/audio_mode 来自板级配置，一旦哪个型号漏写，
        -- exaudio 会退回 I2S（默认 uart_id=1），SIP 就再也出不了声且不报错。
        -- extra 同名字段覆盖，等价于蓝本的 exaudio.setup{model="air1103",uart_id=6,...}。
        local audio_hw = require "audio_hw"
        local setup, result = pcall(audio_hw.setup, {
            model = "air1103", uart_id = 6, audio_mode = "new",
            bits_per_sample = 16, channels = 1,
        })
        restore_touch()
        assert(setup and result, "exaudio.setup 失败: " .. tostring(result))
        local received = wait_mic("soft_reset")
        if not received then
            log.warn("sip_audio_app", "MIC stalled; reopening UART")
            reopen_mic(false)
            received = wait_mic("uart_reopen")
        end
        if not received then
            log.warn("sip_audio_app", "MIC stalled; power cycling")
            reopen_mic(true)
            received = wait_mic("power_cycle")
        end
        if not received then
            local p = mic_parser.stats()
            log.error("sip_audio_app", "MIC init stalled", "raw_rx_total", rx_bytes,
                "parser_pending", p.pending, "discarded", p.discarded, "checksum_errors", p.checksum_errors)
            error("UART 重开和 Air1103 上电后仍无 MIC 帧")
        end
        local t, n = now(), frames
        sys.wait(2000)
        fps = (frames - n) * 1000 / math.max(1, now() - t)
        if fps >= 48 and fps <= 76 then mic_rate = 16000
        elseif fps >= 24 and fps <= 39 then mic_rate = 8000
        else error("MIC 帧率不稳定: " .. string.format("%.1f", fps)) end
        input_resampler = assert(pcm_converter(mic_rate, 8000, 1), "MIC 重采样器不可用")
        output_resampler = assert(voip.pcmResampler(8000, 16000), "喇叭重采样器不可用")
        assert(set_chip_volume(), "音量命令失败")
        initialized = true
        exaudio.sip_voip_start = M.start
        exaudio.sip_voip_stop = M.stop_bridge
        log.info("sip_audio_app", "初始化完成", "MIC rate", mic_rate, "fps", fps)
    end)
    restore_touch(); initializing = false
    if not ok then return signal_error(err) end
    sys.publish("AUDIO_READY", M.diagnostics())
    return true
end

function M.request_init()
    if M.is_ready() then return true end
    if not initializing and not owner and not diag_busy then sys.taskInit(M.init) end
    return false
end

function M.is_ready()
    return initialized and last_mic > 0 and now() - last_mic < 3000
end

function M.is_running() return owner == "call" end
function M.is_busy() return owner ~= nil or initializing or diag_busy end
function M.is_bridge_ok() return owner == "call" and M.is_ready() and chip.is_running() end

function M.set_mute(on)
    if type(on) ~= "boolean" then return false, "invalid_mute" end
    muted = on
    return true
end

function M.set_volume(value)
    if value == nil then return volume end
    if type(value) ~= "number" then return false, "invalid_volume" end
    volume = math.max(0, math.min(100, math.floor(value)))
    cfg.play_vol = volume
    if initialized then return set_chip_volume() end
    return true
end

function M.get_volume() return volume end

function M.diagnostics()
    return {
        ready = M.is_ready(), busy = M.is_busy(), initializing = initializing, owner = owner,
        frames = frames, rx_bytes = rx_bytes, bad_frames = bad_frames, fps = fps, mic_rate = mic_rate,
        peak = peak, volume = volume, error = fault, uart = cfg.uart_id or 6,
        baud = cfg.baud or 2000000, power_pin = cfg.power_gpio or 73,
        uplink = stats.uplink, downlink = stats.downlink, drops = stats.drops,
    }
end

-- ==================== 通话桥启停 ====================

function M.start(session)
    if diag_busy or initializing then return false, "audio_busy" end
    if owner == "call" then return true end
    -- 没初始化就别硬起桥：初始化要 3~4 秒等 MIC 帧率标定，会顶穿 exsip 的媒体准备超时。
    -- 这里立刻失败让 exsip 走正常失败分支（log + voip.stop），同时后台补一次初始化，
    -- 下一通电话就能正常，而不是每通都"接通了却没声音"。
    if not initialized then
        if not initializing and not diag_busy then sys.taskInit(M.init) end
        log.error("sip_audio_app", "音频桥启动失败: 音频尚未初始化完成")
        return false, "audio_not_initialized"
    end
    -- 起桥是决定"这一通电话有没有声音"的唯一入口：
    -- 先收回 MIC（别的页面可能把它抢走了），拿不到上行就自愈一次，
    -- 仍然没有才失败。绝不能在 MIC 不明的情况下静默返回 false —— exsip 会直接 voip.stop()。
    if not M.is_ready() then
        local ok, why = firmware()
        if not ok then
            log.error("sip_audio_app", "音频桥无法启动:", tostring(why))
            return signal_error(why)
        end
        if not ensure_mic(300) then
            log.error("sip_audio_app", "音频桥启动失败: Air1103 无 MIC 上行帧",
                "frames", frames, "raw_rx_total", rx_bytes)
            return false, "audio_not_ready"
        end
    else
        take_mic()
    end
    local rate = session and tonumber(session.sample_rate or 8000) or 8000
    if rate ~= 8000 then return false, "unsupported_sample_rate" end
    -- 音频自检的人工确认只作"听音记录"，不再作为起桥硬门槛：
    -- 做成硬门槛时，没点过确认的设备会整通电话静默无声（exsip 直接 voip.stop），
    -- 现场只会看到"又不行了"。这里保留提示，桥照常起。
    local store = require "sip_test_store"
    if not store.is_audio_verified() then
        log.warn("sip_audio_app", "音频自检尚未人工确认，仍按当前硬件状态起桥（建议在自检页确认一次）")
    end
    if owner == "tone" then cancel_playback() end
    local ok, token = start_stream("call")
    if not ok then return signal_error(token) end
    queue = {}; pending = ""; stats = { uplink = 0, downlink = 0, drops = 0 }
    mic_gap_max = 0; last_submit = nil; submit_gap_max = 0; input_blocked = 0; input_partial = 0
    last_loop = nil; loop_gap_max = 0
    uplink_error = nil; prestart_frames = 0; near_clip_frames = 0
    input_resampler:reset(); output_resampler:reset()
    log.info("sip_audio_app", "bridge: MIC 回调上行，pcmIn 返回样本数")
    sys.taskInit(function()
        local report_at, previous_up, previous_down = now() + 5000, 0, 0
        local read_attempts, read_empty, read_blocked = 0, 0, 0
        local mic_recoveries = 0
        local good, why = pcall(function()
            while owner == "call" and generation == token do
                local loop_tick = now()
                if last_loop then loop_gap_max = math.max(loop_gap_max, loop_tick - last_loop) end
                last_loop = loop_tick
                if not stream_ok(token) then error(chip.get_tx_error() or "speaker_stopped") end
                if not M.is_ready() then
                    -- 通话中 MIC 被别的页面抢走时先救回来；救不回来才结束通话，
                    -- 否则对端会一直"听不到"而本端还显示在通话中。
                    if mic_recoveries < 2 and ensure_mic(200) then
                        mic_recoveries = mic_recoveries + 1
                        log.warn("sip_audio_app", "通话中 MIC 掉线，已自动恢复", mic_recoveries)
                    else
                        local p = mic_parser.stats()
                        log.error("sip_audio_app", "MIC lost detail", "raw_rx_total", rx_bytes, "frames", frames,
                            "parser_pending", p.pending, "discarded", p.discarded, "checksum_errors", p.checksum_errors)
                        error("MIC stream lost")
                    end
                end
                if uplink_error then error(uplink_error) end
                if voip.isRunning() then
                    pump_uplink()
                    if chip.get_pending() < 1920 then
                        read_attempts = read_attempts + 1
                        local pcm = voip.pcmOut(160)
                        if pcm and #pcm > 0 then
                            local output = output_resampler:process(pcm)
                            if output and #output > 0 then chip.play_stream_write(output) end
                            stats.downlink = stats.downlink + #pcm
                        else
                            read_empty = read_empty + 1
                        end
                    else
                        read_blocked = read_blocked + 1
                    end
                end
                if now() >= report_at then
                    log.info("sip_audio_app", "bridge", "mic_peak", peak,
                        "mic_age_ms", math.floor(now() - last_mic), "muted", muted,
                        "up_bytes", stats.uplink - previous_up, "down_bytes", stats.downlink - previous_down,
                        "mic_queue", #queue, "drops", stats.drops)
                    log.info("sip_audio_app", "downlink", "session", token, "pcm_reads", read_attempts,
                        "empty", read_empty, "blocked", read_blocked, "speaker_pending", chip.get_pending(),
                        "loop_gap_max_ms", math.floor(loop_gap_max),
                        "speaker_running", chip.is_running(), "tx_error", chip.get_tx_error() or "none")
                    log.info("sip_audio_app", "uplink timing", "mic_gap_max_ms", math.floor(mic_gap_max),
                        "submit_gap_max_ms", math.floor(submit_gap_max), "input_blocked", input_blocked,
                        "input_partial", input_partial, "pending_bytes", #pending,
                        "prestart_frames", prestart_frames, "near_clip_frames", near_clip_frames)
                    mic_gap_max, submit_gap_max, input_blocked, input_partial = 0, 0, 0, 0
                    loop_gap_max = 0
                    local p = mic_parser.stats()
                    log.info("sip_audio_app", "MIC RX", "raw_bytes", rx_bytes, "valid_frames", frames,
                        "discarded", p.discarded, "checksum_errors", p.checksum_errors, "pending", p.pending)
                    if type(voip.stats) == "function" then
                        local okv, v = pcall(voip.stats)
                        if okv and type(v) == "table" then
                            log.info("sip_audio_app", "rtp", "session", token, "tx", v.tx_packets,
                                "rx", v.rx_packets, "rx_bytes", v.rx_bytes, "tx_errors", v.tx_errors)
                        end
                    end
                    -- 内存/GC 观测：卡顿到底是"Lua 侧 GC 停顿"还是"网络侧丢包"，
                    -- 看这行就能定性。gc_kb 每次都在涨落是正常的；
                    -- 若 lua_used 一路爬高、gc_kb 峰值越来越大，就是还有对象没及时回收。
                    local gok, gkb = pcall(collectgarbage, "count")
                    local mok, mem = pcall(rtos.meminfo, "lua")
                    log.info("sip_audio_app", "mem/gc", "gc_kb", gok and math.floor(gkb) or -1,
                        "lua_used_kb", (mok and type(mem) == "table" and mem.lua) and math.floor(mem.lua / 1024) or -1,
                        "lua_max_kb", (mok and type(mem) == "table" and mem.lua_max) and math.floor(mem.lua_max / 1024) or -1)
                    read_attempts, read_empty, read_blocked = 0, 0, 0
                    previous_up, previous_down = stats.uplink, stats.downlink
                    report_at = now() + 5000
                end
                sys.wait(5)
            end
        end)
        if token == generation and owner == "call" then
            finish_stream(token)
            if not good then signal_error(why); sys.publish("AUDIO_BRIDGE_FAILED", tostring(why)) end
        end
    end)
    return true
end

function M.stop()
    if owner == "call" then
        cancel_playback()
        -- 这里不再还原 air1103 原生 feed：通用录音页只在它自己进入/退出时接管，
        -- 若通话结束就交还，第 2 通电话起 SIP 拿不到 MIC 回调 → 桥接起不来 → 全程无声。
        -- MIC 解析权统一在 teardown（退出 SIP 页）时交还。
        take_mic()
    end
    muted = false
    return true
end

M.stop_bridge = M.stop

-- 退出 SIP 页时彻底释放：停播放 -> 还原原生 feed -> 关 UART6 -> 复位状态。
-- 保证返回通用录音页时，Air1103/UART6 完全回到未占用状态。
function M.teardown()
    if owner then
        pcall(cancel_playback)
    end
    pcall(restore_original_feed)
    if initialized or initializing then
        pcall(stop_stream)
        pcall(chip.uninit)
    end
    owner = nil
    initialized = false
    initializing = false
    mic_rate = nil
    input_resampler, output_resampler = nil, nil
    queue, pending = {}, ""
    muted = false
    return true
end

-- ==================== 提示音（res/air1103_*.pcm 文件流式）====================
-- 应用同样拥有 tone：停播放从不发 STOP-MIC、从不复位芯片。

local function play_tone(names, loop, callback)
    if diag_busy or initializing or owner == "call" then return false, "audio_busy" end
    if not initialized then return false, "audio_not_ready" end
    if owner == "tone" then cancel_playback() end
    local buffers = {}
    for _, name in ipairs(names) do
        local f = io.open("/luadb/air1103_" .. name .. ".pcm", "rb")
        if not f then return signal_error("缺少提示音: " .. name) end
        local data = f:read("*a"); f:close()
        if not data or #data == 0 or #data > 64000 then return signal_error("无效提示音: " .. name) end
        buffers[#buffers + 1] = data
    end
    local ok, token = start_stream("tone")
    if not ok then return false, token end
    sys.taskInit(function()
        local good, why = pcall(function()
            repeat
                for _, data in ipairs(buffers) do
                    local accepted, reason = feed_pcm(token, data)
                    if not accepted then
                        if token == generation then error(reason) end
                        return
                    end
                end
            until not loop or token ~= generation
            if token == generation then local drained, reason = drain(token); assert(drained, reason) end
        end)
        if token == generation then
            finish_stream(token)
            if not good then signal_error(why) end
        end
        if type(callback) == "function" then pcall(callback) end
    end)
    return true
end

function M.play_ringback_loop() return play_tone({ "busy", "gap" }, true) end
function M.play_ringback(callback) return play_tone({ "busy", "gap" }, false, callback) end
function M.play_hangup(callback) return play_tone({ "hangup" }, false, callback) end

-- 蓝本语义：停铃从不复位/停 MIC。忽略传入标志，只在 tone 归属时取消播放。
function M.stop_ringback()
    if owner == "tone" then cancel_playback() end
    return true
end

-- Called only by sip_audio_diag's background task. The lock covers initialization,
-- recording and playback; there is no window in which a call may steal the stream.
-- 严格照蓝本 audio_app.diagnostic_run 逐行移植。
function M.diagnostic_run(kind, progress)
    if diag_busy or owner or initializing then return false, "audio_busy" end
    if kind ~= "tone" and kind ~= "record" then return false, "invalid_test" end
    diag_busy = true
    local token
    local submitted, started = 0, now()
    local function report(stage, detail)
        log.info("sip_audio_diag", kind, stage, detail)
        if progress then progress(stage, detail, M.diagnostics()) end
    end
    local function submit(data)
        local ok, why = feed_pcm(token, data)
        assert(ok, why)
        submitted = submitted + #data
    end
    local success, reason = pcall(function()
        if not M.is_ready() then
            report("initializing", "等待 Air1103 和麦克风数据")
            local ok, why = M.init(); assert(ok, why)
        end
        if kind == "tone" then
            report("probing", "Checking reset response before the 3-second tone")
            local baseline = frames
            sys.wait(200)
            assert(frames > baseline, "MIC stopped before command probe")
            local before, probe_start, max_gap = frames, now(), 0
            assert(chip.reset(), "Air1103 reset command submission failed")
            while now() - probe_start < 3000 do
                sys.wait(20)
                max_gap = math.max(max_gap, now() - last_mic)
            end
            local recovered = frames > before and now() - last_mic < 200
            log.info("sip_audio_diag", "reset observation", "mic_gap_ms", math.floor(max_gap),
                "frames", frames - before, "recovered", recovered)
            if max_gap < 200 then
                log.warn("sip_audio_diag", "No clear MIC pause: reset execution unconfirmed; check UART6 TX to Air1103 RX")
            end
            assert(recovered, "MIC did not recover after reset probe")
            report("playing", "Playing 3-second 800Hz tone; check SPK and amplifier input")
            log.info("sip_audio_diag", "PCM format", 16000, 16, 1, "volume", volume, "chip_volume", math.floor(volume * 31 / 100))
            local ok, id = start_stream("diagnostic"); assert(ok, id); token = id
            local chunks = {}
            for i = 0, 1599 do
                chunks[#chunks + 1] = string.pack("<h", math.floor(6000 * math.sin(2 * math.pi * 800 * i / 16000)))
            end
            local pcm = table.concat(chunks)
            for i = 1, 30 do submit(pcm) end
        else
            report("recording", "请说话：录制 3 秒，随后自动回放")
            local t, n = now(), frames
            capture = {}; capture_bytes = 0
            sys.wait(3000)
            local recorded = capture; capture = nil
            local bytes = capture_bytes
            local measured = (frames - n) * 1000 / math.max(1, now() - t)
            local rate
            if measured >= 48 and measured <= 76 then rate = 16000
            elseif measured >= 24 and measured <= 39 then rate = 8000
            else error("MIC frame rate unstable during recording") end
            assert(bytes > 0, "no_recorded_pcm")
            report("replaying", "正在回放录音，请确认声音内容、速度和清晰度")
            log.info("sip_audio_diag", "record captured", "bytes", bytes, "rate", rate, "frames", #recorded)
            local resampler = assert(pcm_converter(rate, 16000), "record resampler unavailable")
            local ok, id = start_stream("diagnostic"); assert(ok, id); token = id
            for _, pcm in ipairs(recorded) do
                local output = resampler:process(pcm)
                if output and #output > 0 then submit(output) end
            end
        end
        -- Air1103 only consumes complete 320-byte frames. Pad the final fragment.
        local remainder = submitted % 320
        if remainder ~= 0 then submit(string.rep("\0", 320 - remainder)) end
        local drained, why = drain(token); assert(drained, why)
        log.info("sip_audio_diag", "host playback drained", "pcm_bytes", submitted,
            "pending", chip.get_pending(), "tx_error", chip.get_tx_error() or "none",
            "elapsed_ms", math.floor(now() - started))
        log.info("sip_audio_diag", "UART submission is not a chip acknowledgement or proof of audible sound")
    end)
    capture = nil; capture_bytes = 0
    if token then finish_stream(token) end
    diag_busy = false; restore_touch()
    if not success then return signal_error(reason) end
    fault = nil
    return true, M.diagnostics()
end

function M.selftest()
    -- Keep require separate for Luatools' static dependency scanner.
    local diag = require "sip_audio_diag"
    return diag.start("tone")
end

-- 模块加载即挂上桥接钩子：音频还没初始化时也必须由这里应答，
-- 否则 exaudio 自带的 air1103 分支会直接返回 true，exsip 认为桥接成功却没有任何搬运，
-- 结果是"通话建立、两端都没声音"，且日志里查不到任何失败。
if ex_ok and type(exaudio) == "table" then
    exaudio.sip_voip_start = M.start
    exaudio.sip_voip_stop = M.stop_bridge
end

return M
