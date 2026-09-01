local exsip = require "exsip"
local exaudio = require "exaudio"
local audio_drv = require "audio_drv"
local storage = require "storage"

local app = {}
local cfg
local sip_ready = false
local incoming = false
local calling = false
local connected = false
local manual_sequence = 0
local auto_sequence = 0
local auto_record_attempted = false
local auto_record_pending = false
local playback_sequence = 0

local function record_status()
    if not voip or type(voip.recordStatus) ~= "function" then return nil end
    local ok, status = pcall(voip.recordStatus)
    return ok and status or nil
end

local function record_suffix()
    local ok, date = pcall(os.date, "*t")
    if ok and type(date) == "table" and tonumber(date.year) and date.year >= 2020 then
        return string.format("%04d%02d%02d_%02d%02d%02d",
            date.year, date.month, date.day, date.hour, date.min, date.sec)
    end
    local ticks = 0
    if mcu and type(mcu.ticks) == "function" then
        local ticks_ok, value = pcall(mcu.ticks)
        if ticks_ok then ticks = tonumber(value) or 0 end
    end
    return tostring(ticks)
end

local function make_record_path(prefix, sequence)
    local dir = cfg.record.dir:gsub("/+$", "")
    return string.format("%s/%s_%s_%d.wav", dir, prefix, record_suffix(), sequence)
end

local function start_auto_record()
    if not connected or not cfg.record.auto or auto_record_attempted then return end

    local status = record_status()
    if not status then
        auto_record_attempted = true
        log.error("sip_record", "无法查询录音状态，自动录音未启动")
        return
    end
    if status.state ~= "idle" then
        auto_record_attempted = true
        auto_record_pending = false
        log.info("sip_record", "录音已由 exsip 启动", status.state, status.path or "")
        return
    end

    auto_sequence = auto_sequence + 1
    local path = make_record_path(cfg.record.prefix, auto_sequence)
    local ok, err = voip.recordStart(path, {max_seconds = cfg.record.max_seconds})
    if ok then
        auto_record_attempted = true
        auto_record_pending = false
        log.info("sip_record", "自动录音启动请求成功", path)
    elseif err == "invalid_state" then
        auto_record_pending = true
        log.info("sip_record", "等待 VoIP 启动后重试自动录音")
    else
        auto_record_attempted = true
        auto_record_pending = false
        log.error("sip_record", "自动录音启动失败", err or "unknown", path)
    end
end

local function stop_record(reason)
    auto_record_pending = false
    local status = record_status()
    if status and status.state ~= "idle" and status.state ~= "stopping" then
        local ok, err = voip.recordStop()
        log.info("sip_record", "停止录音", reason, ok, err or "")
    end
end

local function toggle_record()
    local status = record_status()
    if not status then
        log.error("sip_record", "当前固件未提供 voip 录音 API")
        return
    end
    if status.state == "recording" or status.state == "armed" then
        local ok, err = voip.recordStop()
        log.info("sip_record", "手动停止录音", ok, err or "")
    elseif status.state == "idle" then
        manual_sequence = manual_sequence + 1
        local path = make_record_path("manual", manual_sequence)
        local ok, err = voip.recordStart(path, {max_seconds = cfg.record.max_seconds})
        log.info("sip_record", "手动开始录音", ok, err or "", path)
    else
        log.warn("sip_record", "当前录音状态不能切换", status.state)
    end
end

local function play_recording_after_stop(info)
    if not cfg.record.play_after_stop then return end

    local path = info and info.path
    local bytes = tonumber(info and info.bytes) or 0
    if type(path) ~= "string" or path == "" or bytes <= 0 then
        log.warn("sip_record.playback", "录音文件无效，跳过测试回放", tostring(path), bytes)
        return
    end

    playback_sequence = playback_sequence + 1
    local sequence = playback_sequence
    sys.taskInit(function()
        sys.wait(cfg.record.playback_delay_ms)
        if sequence ~= playback_sequence then return end

        if incoming or calling or connected or
            (voip and type(voip.isRunning) == "function" and voip.isRunning()) then
            log.warn("sip_record.playback", "已有SIP通话，跳过测试回放", path)
            return
        end

        local status = record_status()
        if status and status.state ~= "idle" then
            log.warn("sip_record.playback", "录音设备尚未空闲，跳过测试回放", status.state)
            return
        end
        if not io.exists(path) then
            log.error("sip_record.playback", "录音文件不存在", path)
            return
        end

        local file_size = tonumber(io.fileSize(path)) or 0
        if file_size <= 44 then
            log.error("sip_record.playback", "录音文件为空或WAV未完成", path, file_size)
            return
        end

        log.info("sip_record.playback", "开始测试回放", path, "bytes=" .. tostring(file_size))
        local call_ok, play_ok = pcall(exaudio.play_start, {
            type = 0,
            content = path,
            priority = 1,
            cbfnc = function(event)
                if event == exaudio.PLAY_DONE then
                    log.info("sip_record.playback", "测试回放完成", path)
                end
            end
        })
        if not call_ok or not play_ok then
            log.error("sip_record.playback", "测试回放启动失败", path, tostring(play_ok))
        end
    end)
end

local function sip_callback(event, arg1, arg2)
    if event == "ready" then
        sip_ready = true
        log.info("sip_record.sip", "SIP 已注册")
    elseif event == "register" then
        log.info("sip_record.sip", "register", arg1)
    elseif event == "call" then
        local action, data = arg1, arg2 or {}
        if action == "incoming" then
            incoming = true
            calling = false
            auto_record_attempted = false
            auto_record_pending = false
            log.info("sip_record.sip", "来电", data.from or "")
        elseif action == "ringing" then
            calling = not incoming
            log.info("sip_record.sip", "响铃中")
        elseif action == "connected" or action == "established" then
            incoming = false
            calling = false
            connected = true
            log.info("sip_record.sip", "通话接通，开始自动录音")
            start_auto_record()
        elseif action == "ended" then
            stop_record("call_ended")
            incoming = false
            calling = false
            connected = false
            auto_record_attempted = false
            auto_record_pending = false
            log.info("sip_record.sip", "通话结束", data.reason or "")
        end
    elseif event == "record" then
        local action, info = arg1, arg2 or {}
        log.info("sip_record.record", action,
            "path=" .. tostring(info.path), "reason=" .. tostring(info.reason),
            "bytes=" .. tostring(info.bytes), "duration_ms=" .. tostring(info.duration_ms),
            "dropped=" .. tostring(info.dropped_frames))
        if action == "stopped" then
            play_recording_after_stop(info)
        end
    elseif event == "media" and arg1 == "stop" then
        stop_record("media_stop")
    elseif event == "voip" then
        if arg1 == "state" then
            log.info("sip_record.voip", "state=" .. tostring(arg2))
            if arg2 == "started" then
                sys.publish("SIP_RECORD_VOIP_STARTED")
                if auto_record_pending then start_auto_record() end
            elseif arg2 == "stopped" then
                auto_record_pending = false
            end
        elseif arg1 == "stats" then
            local stats = arg2 or {}
            log.info("sip_record.voip", "tx=" .. tostring(stats.tx_packets),
                "rx=" .. tostring(stats.rx_packets), "lost=" .. tostring(stats.rx_lost))
        end
    elseif event == "error" then
        log.error("sip_record.sip", "error", arg1)
    elseif event == "lifecycle" and arg1 == "stopped" then
        sip_ready = false
    end
end

local function action_key_handler()
    if incoming then
        log.info("sip_record.key", "接听")
        if exsip.accept() then
            incoming = false
            calling = true
        end
    elseif connected then
        toggle_record()
    elseif calling then
        log.warn("sip_record.key", "正在呼叫")
    elseif sip_ready then
        log.info("sip_record.key", "拨号", cfg.dial_target)
        if exsip.dial(tostring(cfg.dial_target)) then calling = true end
    else
        log.warn("sip_record.key", "SIP 尚未就绪")
    end
end

local function hangup_key_handler()
    if incoming or calling or connected then
        log.info("sip_record.key", "挂断")
        exsip.hangUp()
    end
end

local function log_record_status()
    local status = record_status()
    if status and (connected or status.state ~= "idle") then
        log.info("sip_record.status", status.state,
            "ms=" .. tostring(status.duration_ms), "bytes=" .. tostring(status.bytes),
            "queued=" .. tostring(status.queued_frames), "dropped=" .. tostring(status.dropped_frames),
            "reason=" .. tostring(status.reason))
    end
end

local function validate_config(config)
    if type(config.sip_server_addr) ~= "string" or config.sip_server_addr == "sip.example.com" or
        type(config.sip_username) ~= "string" or type(config.sip_password) ~= "string" or
        config.sip_password == "replace-with-your-sip-password" then
        return false, "请先在 config.lua 中填写真实 SIP 参数"
    end
    if config.dial_target == nil then return false, "缺少 dial_target" end
    config.adapter = config.adapter or socket.LWIP_STA
    config.record = config.record or {}
    config.record.auto = config.record.auto == nil and true or config.record.auto
    config.record.dir = config.record.dir or "/sd/record"
    config.record.prefix = config.record.prefix or "sip"
    config.record.max_seconds = config.record.max_seconds or 7200
    config.record.play_after_stop = config.record.play_after_stop == nil and true or config.record.play_after_stop
    config.record.playback_delay_ms = tonumber(config.record.playback_delay_ms) or 2000
    if config.record.playback_delay_ms < 0 then config.record.playback_delay_ms = 2000 end
    config.sd = config.sd or {}
    config.keys = config.keys or {}
    local mount_point = config.sd.mount_point or "/sd"
    if type(config.record.dir) ~= "string" or type(mount_point) ~= "string" then
        return false, "record.dir 和 sd.mount_point 必须是字符串"
    end
    mount_point = mount_point:gsub("/+$", "")
    if config.record.dir ~= mount_point and config.record.dir:sub(1, #mount_point + 1) ~= mount_point .. "/" then
        return false, "record.dir 必须位于 TF 卡挂载点 " .. mount_point .. " 下"
    end
    return true
end

function app.start(config)
    local ok, err = validate_config(config)
    if not ok then
        log.error("sip_record", err)
        return false
    end
    cfg = config

    if not voip or type(voip.recordStart) ~= "function" or type(voip.recordStatus) ~= "function" then
        log.error("sip_record", "当前 Air8101 固件未提供 voip 本地录音 API")
        return false
    end

    local action_gpio = cfg.keys.action_gpio or 37
    gpio.setup(action_gpio, action_key_handler, gpio.PULLUP, gpio.FALLING)
    gpio.debounce(action_gpio, 200, 1)
    if cfg.keys.hangup_gpio then
        gpio.setup(cfg.keys.hangup_gpio, hangup_key_handler, gpio.PULLUP, gpio.FALLING)
        gpio.debounce(cfg.keys.hangup_gpio, 200, 1)
    end

    exsip.on(sip_callback)
    sys.timerLoopStart(log_record_status, 5000)

    sys.taskInit(function()
        local mount_call_ok, mounted, mount_err = pcall(storage.mount, cfg.sd, cfg.record.dir)
        if not mount_call_ok then
            mount_err = mounted
            mounted = false
        end
        if not mounted then
            local fallback_dir = cfg.sd.fallback_dir or "/record"
            local fallback_ok, fallback_err = storage.ensure_dir(fallback_dir, "/")
            if fallback_ok then
                local fallback_max = tonumber(cfg.sd.fallback_max_seconds) or 60
                if fallback_max < 1 then fallback_max = 60 end
                cfg.record.dir = fallback_dir
                if cfg.record.max_seconds > fallback_max then
                    cfg.record.max_seconds = fallback_max
                end
                log.warn("sip_record.storage", "TF卡不可用，已回退到内部文件系统",
                    "mount_error=" .. tostring(mount_err),
                    "dir=" .. cfg.record.dir,
                    "max_seconds=" .. tostring(cfg.record.max_seconds))
            else
                log.error("sip_record.storage", "TF卡和内部文件系统均不可用，录音将失败",
                    "mount_error=" .. tostring(mount_err),
                    "fallback_error=" .. tostring(fallback_err))
            end
        else
            log.info("sip_record.storage", "使用TF卡录音", cfg.record.dir,
                "max_seconds=" .. tostring(cfg.record.max_seconds))
        end

        if not audio_drv.init() then return end

        while not socket.adapter(socket.LWIP_STA) do
            log.warn("sip_record.net", "等待 Wi-Fi 网络")
            sys.waitUntil("IP_READY", 1000)
        end

        if not exsip.init(cfg) then
            log.error("sip_record.sip", "exsip.init 失败")
            return
        end
        if not exsip.start() then
            log.error("sip_record.sip", "exsip.start 失败")
            return
        end
        voip.on("record", function(event, info)
            sip_callback("record", event, info)
        end)
        log.info("sip_record", "启动完成", "Wi-Fi", "SDIO TF", "GPIO" .. tostring(action_gpio))
    end)
    return true
end

return app
