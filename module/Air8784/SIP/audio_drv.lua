--[[
@module audio_drv
@summary Air1103 音频初始化及 SIP PCM 适配，仅通过 exaudio 操作设备
参考 SIP demo 的 exaudio 初始化方式。当前扩展库的 UART 模式尚未实现
SIP PCM 桥接，因此保留 16kHz MIC/扬声器与 8kHz VoIP 的转换。
]]
local exaudio = require "exaudio"
local cfg = require("config").audio
local M = {}
local initialized, ready, running = false, false, false
local recording, generation = false, 0
local down, up
local queue, uplink = {}, ""
local capture_timer, play_timer, health_timer
local mic_s, mic_us, accept_s, accept_us = 0, 0, 0, 0

local function elapsed_ms(s, us)
    local now_s, now_us = mcu.ticks2(0)
    return (now_s - s) * 1000 + (now_us - us) / 1000
end

local function clear_pcm()
    queue, uplink = {}, ""
    if down then down:reset() end
    if up then up:reset() end
end

local function set_volume()
    local level = math.max(0, math.min(31, math.floor(tonumber(cfg.volume) or 31)))
    return exaudio.vol(math.ceil(level * 100 / 31))
end

local function stop_record()
    recording, ready = false, false
    generation = generation + 1
    exaudio.record_stop()
end

local function start_record()
    generation = generation + 1
    local current, tail = generation, ""
    ready, recording = false, true
    local ok = exaudio.record_start({format=exaudio.PCM_16000, time=0,
        path=function(buff, len)
            if not recording or current ~= generation then return end
            -- exaudio 的临时 zbuff 可包含多帧；立即复制并按512字节拆帧。
            local data = tail .. buff:query(0, len)
            local complete = #data // 512 * 512
            if complete > 0 then
                mic_s, mic_us = mcu.ticks2(0)
                if not ready then
                    ready = true
                    sys.publish("AUDIO_DRV_READY")
                end
            end
            if running then
                for offset = 1, complete, 512 do
                    if #queue == 8 then table.remove(queue, 1) end
                    queue[#queue + 1] = data:sub(offset, offset + 511)
                end
            end
            tail = data:sub(complete + 1)
        end})
    if not ok then stop_record() end
    return ok
end

function M.check_firmware()
    for _, name in ipairs({"setAudioMode", "pcmIn", "pcmOut", "pcmResampler", "start", "stop", "isRunning", "on"}) do
        if not voip or type(voip[name]) ~= "function" then
            return false, "固件缺少 voip." .. name
        end
    end
    if not audio_v2 or voip.AUDIO_MODE_BRIDGE == nil then
        return false, "固件缺少 Audio V2 PCM bridge 支持"
    end
    return true
end

-- 与参考 demo 一样使用 exaudio.setup；在任务内等待真实 MIC 数据就绪。
function M.init()
    if M.is_ready() then return true end
    if running then return false end
    local ok, err = M.check_firmware()
    if not ok then log.error("audio_drv", err); return false end
    if not down then
        local gain = math.max(1, math.min(8, math.floor(tonumber(cfg.mic_gain) or 1)))
        local ok_down, new_down = pcall(voip.pcmResampler, 16000, 8000, gain)
        local ok_up, new_up = pcall(voip.pcmResampler, 8000, 16000)
        if not ok_down or not ok_up or not new_down or not new_up then
            log.error("audio_drv", "PCM重采样器创建失败")
            return false
        end
        down, up = new_down, new_up
    end
    if recording then stop_record() end
    initialized, ready = false, false
    clear_pcm()
    if type(cfg.power_gpio) == "number" then
        gpio.setup(cfg.power_gpio, cfg.power_on_level or 1)
    end
    sys.wait(cfg.boot_ms)
    local setup_ok, result = pcall(exaudio.setup, {
        model="air1103", uart_id=cfg.uart_id, audio_mode="new",
        bits_per_sample=16, channels=1,
    })
    if not setup_ok or not result then
        log.error("audio_drv", "exaudio.setup失败", result)
        return false
    end
    exaudio.sip_voip_start, exaudio.sip_voip_stop = M.start, M.stop_bridge
    if not set_volume() or not start_record() then return false end
    local waited = 0
    while not ready and waited < cfg.ready_timeout_ms do
        sys.waitUntil("AUDIO_DRV_READY", 100)
        waited = waited + 100
    end
    if not ready then
        stop_record()
        log.error("audio_drv", "未收到MIC数据，请检查供电、UART和固件")
        return false
    end
    initialized = true
    return true
end

local function capture_tick()
    if not running then return end
    if voip.isRunning() then
        if #uplink == 0 and #queue > 0 then
            uplink = down:process(table.remove(queue, 1))
        end
        if #uplink > 0 then
            -- pcmIn 返回已消费的样本数，保留未消费尾部供下次发送。
            local used = math.max(0, math.min(#uplink // 2, tonumber(voip.pcmIn(uplink)) or 0))
            if used > 0 then accept_s, accept_us = mcu.ticks2(0) end
            uplink = uplink:sub(used * 2 + 1)
        end
    end
    local delay = #uplink > 0 and 10 or (#queue > 0 and 2 or 5)
    capture_timer = sys.timerStart(capture_tick, delay)
end

function M.start(session)
    if not M.is_ready() then return false end
    if session and tonumber(session.sample_rate or 8000) ~= 8000 then return false end
    if running then return true end
    clear_pcm()
    if not set_volume() or not exaudio.play_start({type=2}) then return false end
    running = true
    accept_s, accept_us = mcu.ticks2(0)
    capture_timer = sys.timerStart(capture_tick, 10)
    local play_s, play_us = mcu.ticks2(0)
    local function playback_tick()
        if not running then return end
        -- 库未公开播放队列长度；每20ms最多发送一帧，延迟后不突发补帧。
        if voip.isRunning() and elapsed_ms(play_s, play_us) >= 20 then
            play_s, play_us = mcu.ticks2(0)
            local pcm = voip.pcmOut(160)
            if pcm and #pcm > 0 and #pcm <= 320 and #pcm % 2 == 0 then
                local output = up:process(pcm)
                exaudio.play_stream_write(output)
            end
        end
        play_timer = sys.timerStart(playback_tick, 5)
    end
    play_timer = sys.timerStart(playback_tick, 20)
    local function health_tick()
        if not running then return end
        local reason
        if elapsed_ms(mic_s, mic_us) >= cfg.mic_timeout_ms then
            reason = "通话中MIC数据中断"
        elseif #uplink > 0 and elapsed_ms(accept_s, accept_us) >= 2000 then
            reason = "PCM发送持续阻塞"
        end
        if reason then
            M.stop()
            sys.publish("AUDIO_DRV_ERROR", reason)
            return
        end
        health_timer = sys.timerStart(health_tick, 1000)
    end
    health_timer = sys.timerStart(health_tick, 1000)
    return true
end

function M.stop(skip_recover)
    if not running then return end
    running = false
    sys.timerStop(capture_timer)
    sys.timerStop(play_timer)
    sys.timerStop(health_timer)
    capture_timer, play_timer, health_timer = nil, nil, nil
    clear_pcm()
    exaudio.play_stop({type=2})
    -- 停止播放同时会停止芯片MIC；MIC恢复依赖 exaudio.record_start 内部的 Air1103 复位(重启约1.4s)。
    -- skip_recover=true: 挂断提示音需趁芯片就绪时播放，复位重启会吞掉紧跟的提示音，
    --                    故把MIC恢复延后到提示音队列收尾自行复位；保持GPIO供电。
    if not skip_recover then
        if not start_record() then log.error("audio_drv", "MIC恢复失败") end
    end
end

-- 供 exsip 在停止媒体时调用：只停桥接，不复位芯片(复位延后到挂断提示音队列收尾)。
function M.stop_bridge()
    return M.stop(true)
end

-- 本机提示音(按模型分发，透传 exaudio；air1103 模式复用芯片内嵌提示音与播放队列)
function M.play_ringback(callback) return exaudio.play_ringback(callback) end
function M.play_hangup(callback) return exaudio.play_hangup(callback) end
-- 循环振铃(未接通前一直响)与停止
function M.play_ringback_loop() return exaudio.play_ringback_loop() end
function M.stop_ringback(skip_reset) return exaudio.stop_ringback(skip_reset) end

function M.is_ready()
    if ready and elapsed_ms(mic_s, mic_us) >= cfg.mic_timeout_ms then ready = false end
    return initialized and ready
end

function M.is_running()
    return running
end

return M
