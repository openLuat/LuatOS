--[[
@module audio_drv
@summary Air1103 音频初始化及 SIP PCM 适配，exaudio 播放、air1103 直接采集 MIC
参考 SIP demo 的 exaudio 初始化方式。当前扩展库的 UART 模式尚未实现
SIP PCM 桥接，因此保留 16kHz MIC/扬声器与 8kHz VoIP 的转换。
]]
local exaudio = require "exaudio"
local air1103 = require "air1103"
local cfg = require("config").audio
-- 16kHz/16bit/单声道：每10ms为320字节，与正常参考工程保持一致。
local play_target = math.max(40, math.min(120, tonumber(cfg.play_buffer_ms) or 60)) // 10 * 320
local M = {}
local initialized, ready, running = false, false, false
local recording, generation = false, 0
local mic_recovering, mic_recovery_attempted = false, false
local recover_s, recover_us = 0, 0
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
    air1103.set_rx_enable(false)
    air1103.on_audio_data(nil)
end

local function start_record()
    generation = generation + 1
    local current = generation
    ready, recording = false, true
    -- 与正常参考工程一致：串口回调只入队，重采样仍在独立定时器执行。
    -- 不启动 exaudio.record_start，避免录音任务搬运、缓冲清零及回调覆盖。
    air1103.set_rx_enable(false)
    air1103.on_audio_data(function(data)
        if not recording or current ~= generation then return end
        if type(data) ~= "string" or #data ~= 512 then return end
        mic_s, mic_us = mcu.ticks2(0)
        if not ready then
            ready = true
            sys.publish("AUDIO_DRV_READY")
        end
        if running and not mic_recovering then
            if #queue == 8 then table.remove(queue, 1) end
            queue[#queue + 1] = data
        end
    end)
    local ok = air1103.reset()
    air1103.set_rx_enable(true)
    if not ok then stop_record() end
    return ok
end

function M.check_firmware()
    for _, name in ipairs({"get_pending", "on_audio_data", "set_rx_enable", "reset"}) do
        if type(air1103[name]) ~= "function" then
            return false, "air1103扩展库缺少" .. name .. "，请更新扩展库"
        end
    end
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
    if not mic_recovering and voip.isRunning() then
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
    mic_recovering, mic_recovery_attempted = false, false
    accept_s, accept_us = mcu.ticks2(0)
    capture_timer = sys.timerStart(capture_tick, 10)
    local function playback_tick()
        if not running then return end
        -- UART驱动负责10ms播放节拍；本层按水位补充，避免回调迟到造成持续欠载。
        -- 每次最多取20ms，水位达到目标+20ms时暂停取数，防止积压增加通话延迟。
        if not mic_recovering and voip.isRunning() and air1103.get_pending() < play_target + 640 then
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
        if mic_recovering then
            if ready then
                if set_volume() and exaudio.play_start({type=2}) then
                    mic_recovering = false
                    accept_s, accept_us = mcu.ticks2(0)
                    log.info("audio_drv", "MIC_RECOVER_OK", "SIP会话保持")
                else
                    reason = "MIC恢复后播放启动失败"
                end
            elseif elapsed_ms(recover_s, recover_us) >= cfg.ready_timeout_ms then
                reason = "通话中MIC恢复超时"
            end
        elseif elapsed_ms(mic_s, mic_us) >= cfg.mic_timeout_ms then
            if mic_recovery_attempted then
                reason = "通话中MIC再次中断"
            else
                -- 每次通话仅尝试一次；先停播放再复位，避免复位期间继续向芯片灌PCM。
                -- 不停止voip/SIP，等待真实MIC帧后恢复播放；超时仍上报业务层。
                mic_recovering, mic_recovery_attempted = true, true
                recover_s, recover_us = mcu.ticks2(0)
                log.warn("audio_drv", "MIC_RECOVER_BEGIN", "age_ms", math.floor(elapsed_ms(mic_s, mic_us)))
                exaudio.play_stop({type=2})
                clear_pcm()
                if not start_record() then reason = "通话中MIC复位失败" end
            end
        elseif #uplink > 0 and elapsed_ms(accept_s, accept_us) >= 2000 then
            reason = "PCM发送持续阻塞"
        end
        if reason then
            -- 已决定退出，不在这里再复位；后续由业务任务重新初始化。
            M.stop(true)
            sys.publish("AUDIO_DRV_ERROR", reason)
            return
        end
        health_timer = sys.timerStart(health_tick, mic_recovering and 100 or 1000)
    end
    health_timer = sys.timerStart(health_tick, 1000)
    return true
end

function M.stop(skip_recover)
    if not running then return end
    running = false
    mic_recovering = false
    sys.timerStop(capture_timer)
    sys.timerStop(play_timer)
    sys.timerStop(health_timer)
    capture_timer, play_timer, health_timer = nil, nil, nil
    clear_pcm()
    exaudio.play_stop({type=2})
    ready = false
    -- 停止播放同时会停止芯片MIC；通过 Air1103 复位恢复(重启约1.4s)。
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
