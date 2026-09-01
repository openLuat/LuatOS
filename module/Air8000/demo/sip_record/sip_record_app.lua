local exsip = require "exsip"
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

local function record_status()
    if not voip or type(voip.recordStatus) ~= "function" then
        return nil
    end
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
        if ticks_ok then
            ticks = tonumber(value) or 0
        end
    end
    return tostring(ticks)
end

local function make_record_path(prefix, sequence)
    local dir = cfg.record.dir:gsub("/+$", "")
    return string.format("%s/%s_%s_%d.wav", dir, prefix, record_suffix(), sequence)
end

local function start_auto_record()
    if not connected or not cfg.record.auto or auto_record_attempted then
        return
    end

    local status = record_status()
    if not status then
        auto_record_attempted = true
        log.error("sip_record", "无法查询录音状态，自动录音未启动")
        return
    end
    if status.state ~= "idle" then
        -- 新版 exsip 可能已经先一步启动自动录音，避免创建第二个文件。
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
        -- call connected 可能略早于 VoIP 任务进入 STARTING/RUNNING，等 started 后重试。
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

local function sip_callback(event, arg1, arg2)
    if event == "ready" then
        sip_ready = true
        log.info("sip_record.sip", "SIP 已注册，可以按 BOOT 键拨号")
    elseif event == "register" then
        log.info("sip_record.sip", "register", arg1)
    elseif event == "call" then
        local action, data = arg1, arg2 or {}
        if action == "incoming" then
            incoming = true
            calling = false
            auto_record_attempted = false
            auto_record_pending = false
            log.info("sip_record.sip", "来电，按 BOOT 键接听", data.from or "")
        elseif action == "ringing" then
            calling = true
            log.info("sip_record.sip", "对方响铃中")
        elseif action == "connected" or action == "established" then
            incoming = false
            calling = false
            connected = true
            log.info("sip_record.sip", "通话接通，自动录音将从此刻开始")
            start_auto_record()
        elseif action == "ended" then
            stop_record("call_ended")
            incoming = false
            calling = false
            connected = false
            auto_record_attempted = false
            auto_record_pending = false
            log.info("sip_record.sip", "通话结束", data.reason or "")
        else
            log.info("sip_record.sip", "call", action)
        end
    elseif event == "record" then
        local action, info = arg1, arg2 or {}
        log.info("sip_record.record", action,
            "path=" .. tostring(info.path),
            "reason=" .. tostring(info.reason),
            "bytes=" .. tostring(info.bytes),
            "duration_ms=" .. tostring(info.duration_ms),
            "dropped=" .. tostring(info.dropped_frames))
    elseif event == "media" and arg1 == "stop" then
        stop_record("media_stop")
    elseif event == "voip" then
        if arg1 == "state" then
            log.info("sip_record.voip", "state=" .. tostring(arg2))
            if arg2 == "started" and auto_record_pending then
                start_auto_record()
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

local function boot_key_handler()
    if incoming then
        log.info("sip_record.key", "接听")
        if exsip.accept() then
            incoming = false
            calling = true
        end
    elseif connected then
        toggle_record()
    elseif calling then
        log.warn("sip_record.key", "正在呼叫，请等待接通或按 POWERKEY 挂断")
    elseif sip_ready then
        log.info("sip_record.key", "拨号", cfg.dial_target)
        if exsip.dial(tostring(cfg.dial_target)) then
            calling = true
        end
    else
        log.warn("sip_record.key", "SIP 尚未就绪")
    end
end

local function power_key_handler()
    if incoming or calling or connected then
        log.info("sip_record.key", "挂断")
        exsip.hangUp()
    end
end

local function log_record_status()
    local status = record_status()
    if status and (connected or status.state ~= "idle") then
        log.info("sip_record.status", status.state,
            "ms=" .. tostring(status.duration_ms),
            "bytes=" .. tostring(status.bytes),
            "queued=" .. tostring(status.queued_frames),
            "dropped=" .. tostring(status.dropped_frames),
            "reason=" .. tostring(status.reason))
    end
end

local function validate_config(config)
    if type(config.sip_server_addr) ~= "string" or config.sip_server_addr == "sip.example.com" or
        type(config.sip_username) ~= "string" or type(config.sip_password) ~= "string" or
        config.sip_password == "replace-with-your-password" then
        return false, "请先在 config.lua 中填写真实 SIP 服务器、用户名和密码"
    end
    if config.dial_target == nil then
        return false, "缺少 dial_target"
    end
    config.record = config.record or {}
    config.record.auto = config.record.auto == nil and true or config.record.auto
    config.record.dir = config.record.dir or "/sd/record"
    config.record.prefix = config.record.prefix or "sip"
    config.record.max_seconds = config.record.max_seconds or 7200
    local mount_point = config.sd and config.sd.mount_point or "/sd"
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

    log.info("sip_record", "录音配置",
        "auto=" .. tostring(cfg.record.auto),
        "dir=" .. tostring(cfg.record.dir),
        "max_seconds=" .. tostring(cfg.record.max_seconds),
        "exsip=" .. tostring(type(exsip.version) == "function" and exsip.version() or "unknown"))

    if not voip or type(voip.recordStart) ~= "function" or type(voip.recordStatus) ~= "function" then
        log.error("sip_record", "固件不支持 SIP 本地录音，请使用启用 LUAT_USE_VOIP_RECORD 的 Air8000 1号或13号固件")
        return false
    end

    gpio.setup(gpio.PWR_KEY, power_key_handler, gpio.PULLUP, gpio.FALLING)
    gpio.debounce(gpio.PWR_KEY, 200, 1)
    gpio.setup(0, boot_key_handler, gpio.PULLDOWN, gpio.RISING)
    gpio.debounce(0, 200, 1)

    exsip.on(sip_callback)
    sys.timerLoopStart(log_record_status, 5000)

    sys.taskInit(function()
        local mount_call_ok, mounted, mount_err = pcall(storage.mount, cfg.sd, cfg.record.dir)
        if not mount_call_ok then
            mount_err = mounted
            mounted = false
        end
        if not mounted then
            log.error("sip_record.sd", "TF 卡不可用，SIP 仍会启动，但录音会失败", mount_err)
        end

        if not audio_drv.init() then
            return
        end

        while not socket.adapter(socket.dft()) do
            log.warn("sip_record.net", "等待 4G 网络")
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
        -- 录音事件直接绑定到底层，兼容尚未转发 record 事件的旧版 exsip.lua。
        voip.on("record", function(event, info)
            sip_callback("record", event, info)
        end)
        log.info("sip_record", "启动完成：BOOT=拨号/接听/切换录音，POWERKEY=挂断")
    end)
    return true
end

return app
