--[[
@module exsip
@summary SIP/VoIP 电话扩展库，简化 SIP 客户端使用
@version 1.0
@date    2026.04.10
@author  蒋骞
@usage
本库封装了 exsipclient 和 VoIP 引擎，提供更简洁的 API 接口，
让用户更容易上手 SIP/VoIP 电话功能。

基本用法：
local exsip = require "exsip"

-- 配置 SIP 账号
local config = {
    server = "192.168.1.100",
    port = 5060,
    domain = "192.168.1.100",
    user = "1001",
    password = "123456"
}

-- 设置事件回调
exsip.on("register", function(status)
    log.info("sip", "注册状态:", status)
end)

exsip.on("call", function(event, data)
    if event == "incoming" then
        log.info("sip", "来电:", data.from)
        exsip.accept()
    elseif event == "connected" then
        log.info("sip", "通话已建立")
    elseif event == "ended" then
        log.info("sip", "通话已结束")
    end
end)

-- 启动 SIP 服务
exsip.init(config)
exsip.start()

-- 拨打电话
-- exsip.dial("1002")

-- 发送消息
-- exsip.message("1002", "你好")

-- 挂断通话
-- exsip.hangUp()

-- 版本更新说明
-- 版本号：202607021200
-- 1、更新时间：2026-07-02 12:00
-- 2、更新内容
--    新增exsip.version()接口
--    支持exsip库文件版本号管理功能，版本号的格式为：yyyymmddhhmm，表示yyyy年mm月dd日hh时mm分发布的版本
]]
exaudio = require "exaudio"

local exsip = {}

-- 常量定义 

-- 传输协议
exsip.TRANSPORT_UDP = "udp"
exsip.TRANSPORT_TCP = "tcp"

-- 编解码器
exsip.CODEC_PCMU = "PCMU"
exsip.CODEC_PCMA = "PCMA"

-- 默认端口
exsip.DEFAULT_SIP_PORT = 5060
exsip.DEFAULT_RTP_PORT = 40000

-- 默认注册有效期（秒）
exsip.DEFAULT_EXPIRES = 600

-- 网络适配器（需要 socket 库支持）
-- socket.LWIP_GP = 4G（默认）
-- socket.LWIP_STA = WiFi
-- socket.LWIP_ETH = 以太网
-- nil = 使用系统默认网卡


local sipclient = nil
local g_config = nil
local g_started = false
local g_registered = false
local g_callbacks = {}
local g_current_call = nil
-- 本次 VoIP 是否由 exaudio 建立本地 audio_v2 收发链路。
local g_voip_uses_exaudio = false
local g_netdrv_subscribed = false
-- 自动录音只在 call connected 后尝试一次；媒体晚于通话建立时允许延后重试。
local g_call_connected = false
local g_auto_record_attempted = false
local g_auto_record_pending = false
local g_record_sequence = 0

-- SIP 当前实际使用的网卡（由 exsipclient 启动时确定）
local g_current_adapter = nil
-- 记录当前可用的网卡（收到 IP_READY 添加，收到 IP_LOSE 移除）
local g_ready_adapters = {}
-- 是否已订阅 IP 状态事件
local g_ip_event_subscribed = false

-- 默认配置
local default_config = {
    sip_transport = exsip.TRANSPORT_TCP,
    port = exsip.DEFAULT_SIP_PORT,
    rtp_port = exsip.DEFAULT_RTP_PORT,
    expires = exsip.DEFAULT_EXPIRES,
    codecs = { exsip.CODEC_PCMU, exsip.CODEC_PCMA },
    ptime = 20,
    auto_answer = false,
    delay_auto_answer = 0,
    call_timeout = 30,
    debug_sip_response = false,
    early_media = true,
    early_media_response = 183,
    adapter = nil,  -- nil = 使用系统默认网卡
    audio_mode = nil,  -- nil = 使用系统默认音频模式；voip.AUDIO_MODE_BRIDGE, -- 使用桥接模式
    -- true: CC 独占音频硬件，SIP 仅提供 RTP/PCM 桥接，不启动本地 audio_v2 speech。
    cc_sip_bridge = false,
    record = {
        auto = false,
        dir = "/sd/record",
        prefix = "sip",
        max_seconds = 7200
    }
}


local function log_info(...)
    if _G.log and type(log.info) == "function" then
        log.info("exsip", ...)
    end
end

local function log_warn(...)
    if _G.log and type(log.warn) == "function" then
        log.warn("exsip", ...)
    end
end

local function log_error(...)
    if _G.log and type(log.error) == "function" then
        log.error("exsip", ...)
    end
end

local function emit_callback(event, ...)
    local cb = g_callbacks[event]
    if type(cb) == "function" then
        local ok, err = pcall(cb, ...)
        if not ok then
            log_error("callback error:", event, err)
        end
    end
end

local function validate_record_config(config)
    if config == nil then
        config = {}
    elseif type(config) ~= "table" then
        return nil, "record must be a table"
    end

    local record = {
        auto = config.auto == nil and false or config.auto,
        dir = config.dir == nil and "/sd/record" or config.dir,
        prefix = config.prefix == nil and "sip" or config.prefix,
        max_seconds = config.max_seconds == nil and 7200 or config.max_seconds
    }
    if type(record.auto) ~= "boolean" then
        return nil, "record.auto must be a boolean"
    end
    if type(record.dir) ~= "string" or #record.dir == 0 or record.dir:sub(1, 1) ~= "/" then
        return nil, "record.dir must be an absolute path"
    end
    if type(record.prefix) ~= "string" or #record.prefix == 0 or not record.prefix:match("^[%w_%-]+$") then
        return nil, "record.prefix may only contain letters, digits, '_' and '-'"
    end
    if type(record.max_seconds) ~= "number" or record.max_seconds < 1 or record.max_seconds % 1 ~= 0 then
        return nil, "record.max_seconds must be a positive integer"
    end
    return record
end

local function record_state()
    if not voip or type(voip.recordStatus) ~= "function" then
        return nil
    end
    local ok, status = pcall(voip.recordStatus)
    if ok and type(status) == "table" then
        return status.state
    end
    return nil
end

local function make_record_path()
    g_record_sequence = g_record_sequence + 1
    local suffix
    local ok, date = pcall(os.date, "*t")
    if ok and type(date) == "table" and tonumber(date.year) and date.year >= 2020 then
        suffix = string.format("%04d%02d%02d_%02d%02d%02d", date.year, date.month, date.day,
            date.hour, date.min, date.sec)
    else
        local ticks = 0
        if mcu and type(mcu.ticks) == "function" then
            local ticks_ok, value = pcall(mcu.ticks)
            if ticks_ok then
                ticks = tonumber(value) or 0
            end
        end
        suffix = tostring(ticks)
    end
    local dir = g_config.record.dir:gsub("/+$", "")
    return string.format("%s/%s_%s_%d.wav", dir, g_config.record.prefix, suffix, g_record_sequence)
end

local function start_auto_record()
    if not g_call_connected or g_auto_record_attempted or not g_config or
        not g_config.record.auto or g_config.cc_sip_bridge then
        return
    end
    if not voip or type(voip.recordStart) ~= "function" then
        g_auto_record_attempted = true
        log_warn("voip recording not supported")
        return
    end

    local state = record_state()
    if state and state ~= "idle" then
        -- 业务已手动启动录音，本次通话不再由 exsip 接管。
        g_auto_record_attempted = true
        g_auto_record_pending = false
        log_info("recording already active, skip automatic recording")
        return
    end

    local path = make_record_path()
    local ok, err = voip.recordStart(path, {max_seconds = g_config.record.max_seconds})
    if ok then
        g_auto_record_attempted = true
        g_auto_record_pending = false
        log_info("automatic recording requested", path)
    elseif err == "invalid_state" then
        -- connected 可能早于 media ready；只允许在 media ready 后重试。
        g_auto_record_pending = true
        log_info("automatic recording waiting for media")
    else
        g_auto_record_attempted = true
        g_auto_record_pending = false
        log_warn("automatic recording failed", err)
    end
end

local function stop_call_record()
    g_auto_record_pending = false
    if not voip or type(voip.recordStop) ~= "function" then
        return
    end
    local state = record_state()
    if state and state ~= "idle" and state ~= "stopping" then
        local ok, err = voip.recordStop()
        if not ok then
            log_warn("stop recording failed", err)
        end
    end
end

local function reset_call_record_state()
    g_call_connected = false
    g_auto_record_attempted = false
    g_auto_record_pending = false
end

local function start_voip_engine(session)
    if not voip then
        log_error("voip core not support")
        return
    end
    --关闭其他播报，避免和 VoIP 音频冲突
    pcall(exaudio.play_stop, {type = 0}) 
    pcall(exaudio.play_stop, {type = 1}) 
    pcall(exaudio.play_stop, {type = 2}) 

    -- 唤醒音频硬件（audio_v2 框架下 ES8311 可能处于 shutdown，需先恢复）
    if exaudio.pm then
        pcall(exaudio.pm, exaudio.RESUME)
    end

    local codec_map = {
        [exsip.CODEC_PCMU] = voip.PCMU,
        [exsip.CODEC_PCMA] = voip.PCMA
    }
    local codec = codec_map[session.codec] or voip.PCMU

    -- 普通 SIP/audio_v2 使用 Lua 管理的本地 PCM 收发；CC-SIP 桥接则由 CC C 层
    -- 直接交换 PCM，必须避免第二个 audio_v2 speech 请求占用 I2S 并重复上行。
    local is_cc_sip_bridge = g_config and g_config.cc_sip_bridge == true
    local use_sip_audio_v2 = not is_cc_sip_bridge and exaudio.is_audio_v2 and exaudio.is_audio_v2() and type(voip.setAudioMode) == "function" and voip.AUDIO_MODE_BRIDGE ~= nil
    g_voip_uses_exaudio = false
    if is_cc_sip_bridge then
        log_info("CC-SIP bridge: skip local audio_v2 speech")
    elseif voip.setAudioMode and use_sip_audio_v2 then
        if voip.AUDIO_MODE_BRIDGE then
            pcall(voip.setAudioMode, voip.AUDIO_MODE_BRIDGE)
        elseif voip.AUDIO_MODE_I2S then
            pcall(voip.setAudioMode, voip.AUDIO_MODE_I2S)
        end
    elseif voip.setAudioMode and voip.AUDIO_MODE_I2S then
        pcall(voip.setAudioMode, voip.AUDIO_MODE_I2S)
    end

    log_info("start voip engine with adapter:", g_current_adapter, "remote:", session.remote_ip .. ":" .. session.remote_port)
    local ok = voip.start({
        remote_ip = session.remote_ip,
        remote_port = tonumber(session.remote_port) or 10000,
        local_port = tonumber(session.local_rtp_port) or 0,
        codec = codec,
        ptime = tonumber(session.ptime) or 20,  -- 打包时长，单位毫秒
        sample_rate = tonumber(session.sample_rate) or 8000,    -- 采样率，单位Hz，默认8000
        jitter_depth = 3,   --抖动缓冲深度，单位为包，默认值为3，建议值为3-5，过大可能增加通话延迟，过小可能增加丢包率
        multimedia_id = 0,  --多媒体ID
        stats_interval = 5000,  --统计信息上报间隔
        -- 使用 SIP 层锁定的网卡适配器，确保媒体和 SIP 使用同一个网卡
        adapter = g_current_adapter,
        -- adapter = session.adapter or (g_config and g_config.adapter) or socket.dft(),
        aec = true,
        aec_denoise =true,
        aec_tail = 200
    })

    if ok then
        local adapter_ok, bridge_ok = true, true
        if use_sip_audio_v2 then
            adapter_ok, bridge_ok = pcall(exaudio.sip_voip_start)
        end
        if not adapter_ok or not bridge_ok then
            log_error("audio_v2 SIP bridge start failed")
            voip.stop()
            return
        end
        g_voip_uses_exaudio = use_sip_audio_v2
        log_info("voip engine started", session.remote_ip .. ":" .. session.remote_port,
            "codec=" .. tostring(session.codec), "adapter", g_config and g_config.adapter)
        if g_auto_record_pending or g_call_connected then
            start_auto_record()
        end
    else
        log_error("voip engine start failed")
    end
end

local function stop_voip_engine()
    if not voip then
        return
    end
    stop_call_record()
    if voip.isRunning() then
        if g_voip_uses_exaudio and exaudio.sip_voip_stop then exaudio.sip_voip_stop() end
        g_voip_uses_exaudio = false
        voip.stop()
        log_info("voip engine stopping")
    end
end

-- 网卡 IP 就绪/丢失事件处理
local function ip_ready_handler(ip, adapter)
    log_info("IP_READY", ip, adapter)
    g_ready_adapters[adapter] = true
end

local function ip_lose_handler(adapter)
    log_info("IP_LOSE", adapter)
    g_ready_adapters[adapter] = nil
    if not g_started then
        return
    end
    if adapter == g_current_adapter then
        local all_down = true
        for _ in pairs(g_ready_adapters) do
            all_down = false
            break
        end
        log_warn("current adapter lost, triggering error", adapter)
        emit_callback("error", "network_changed", {
            reason = "current_adapter_lost",
            adapter = adapter,
            all_down = all_down
        })
    end
end

local function sip_event_handler(event, action, payload)
    log_info("event:", event, "action:", action)

    if event == "register" then
        if action == "ok" then
            g_registered = true
            emit_callback("register", "ok", payload)
            emit_callback("ready")
        elseif action == "challenge" then
            -- challenge 是正常的认证流程，不标记为未注册
            emit_callback("register", "challenge", payload)
        else
            g_registered = false
            emit_callback("register", "failed", payload)
        end
    elseif event == "call" then
        if action == "incoming" then
            g_current_call = {
                from = payload.from,
                call_id = payload.call_id,
                headers = payload.headers,
                remote_sdp = payload.remote_sdp,
                body = payload.body,
                uri = payload.uri
            }
            emit_callback("call", "incoming", g_current_call)
            if g_config and g_config.auto_answer then
                if g_config.delay_auto_answer > 0 then
                    sys.timerStart(function()
                        exsip.accept()
                    end, g_config.delay_auto_answer * 1000)
                else
                    exsip.accept()
                end
            end
        elseif action == "ringing" then
            emit_callback("call", "ringing", payload)
        elseif action == "connected" or action == "established" then
            g_call_connected = true
            start_auto_record()
            emit_callback("call", "connected", payload)
        elseif action == "ended" or action == "failed" then
            stop_call_record()
            reset_call_record_state()
            emit_callback("call", "ended", payload)
            g_current_call = nil
        end
    elseif event == "media" then
        if action == "ready" then
            local session = payload.session or payload
            log_info("media ready", session.remote_ip, session.remote_port, session.codec)
            start_voip_engine(session)
            emit_callback("media", "ready", session)
        elseif action == "stop" then
            stop_call_record()
            stop_voip_engine()
            emit_callback("media", "stop", payload)
        end
    elseif event == "message" then
        if action == "rx" then
            emit_callback("message", "rx", {
                from = payload.from,
                body = payload.body
            })
        elseif action == "sent" then
            emit_callback("message", "sent", {
                to = payload.to
            })
        end
    elseif event == "dtmf" then
        emit_callback("dtmf", action, payload)
    elseif event == "lifecycle" then
        log_info("lifecycle:", action)
        if action == "offline" then
            -- SIP 离线时，停止 voip 引擎，让下次重连时使用新网卡
            stop_voip_engine()
            reset_call_record_state()
            g_registered = false
        elseif action == "stopped" then
            stop_voip_engine()
            reset_call_record_state()
            g_registered = false
        end
        emit_callback("lifecycle", action, payload)
    elseif event == "error" then
        log_error("error:", action, payload.event, payload.param)
        emit_callback("error", action, payload)
    end
end

--  VoIP 回调函数

local function setup_voip_callbacks()
    if voip then
        voip.on("state", function(state)
            log_info("voip state:", state)
            if state == "stopped" or state == "error" or state == "idle" then
                stop_call_record()
                reset_call_record_state()
            end
            emit_callback("voip", "state", state)
        end)

        voip.on("stats", function(stats)
            emit_callback("voip", "stats", stats)
        end)

        voip.on("error", function(err)
            log_error("voip error:", err)
            emit_callback("voip", "error", err)
        end)

        -- 未编入 LUAT_USE_VOIP_RECORD 的固件没有录音 API，也不注册未知事件。
        if type(voip.recordStatus) == "function" then
            voip.on("record", function(event, info)
                emit_callback("record", event, info)
                emit_callback("voip", "record", event, info)
            end)
        end
    end
end


--[[
配置 SIP 参数。
@api exsip.init(config)
@table config 配置参数表
@string config.sip_server_addr SIP 服务器地址
@number config.sip_server_port SIP 服务器端口，默认 5060
@string config.sip_domain SIP 域
@string config.sip_username SIP 用户名
@string config.sip_password SIP 密码
@string config.sip_transport RTP 传输协议，"UDP" 或 "TCP"，默认 "TCP"
@number config.rtp_port 本地 RTP 端口，默认 40000
@number config.expires 注册有效期（秒），默认 600
@table config.codecs 编解码器列表，默认 {"PCMU", "PCMA"}
@number config.ptime 打包时长（毫秒），默认 20
@boolean config.auto_answer 是否自动接听，默认 false
@number config.delay_auto_answer 自动接听延迟（秒），默认 0
@number config.call_timeout 拨号超时时间（秒），默认 30
@boolean config.debug_sip_response 是否打印完整 SIP 服务器响应，默认 false
@number config.adapter 网络适配器，nil=使用系统默认，socket.LWIP_GP=4G，socket.LWIP_STA=WiFi，socket.LWIP_ETH=以太网
@table config.record 通话录音配置，默认关闭；支持 auto、dir、prefix、max_seconds
@return boolean 成功返回 true，失败返回 false
@usage
exsip.init({
    sip_server_addr = "192.168.1.100",
    sip_server_port = 5060,
    sip_domain = "192.168.1.100",
    sip_username = "1001",
    sip_password = "123456",
    auto_answer = false,
    adapter = nil  -- 使用系统默认网卡
})
]]
function exsip.init(config)
    log_info("exsip.init called, config type:", type(config), "config:", config)
    if not config or type(config) ~= "table" then
        log_error("config must be a table")
        return false
    end

    if not config.sip_server_addr or not config.sip_username or not config.sip_password then
        log_error("server, user and password are required")
        return false
    end

    local record_config, record_err = validate_record_config(config.record)
    if not record_config then
        log_error("invalid record config:", record_err)
        return false
    end

    g_config = {}
    for k, v in pairs(default_config) do
        g_config[k] = v
    end
    for k, v in pairs(config) do
        g_config[k] = v
    end
    g_config.record = record_config

    if g_config.cc_sip_bridge and g_config.record.auto then
        log_warn("automatic recording is disabled for CC-SIP bridge mode")
    end

    if not g_config.sip_domain then
        g_config.sip_domain = g_config.sip_server_addr
    end

    log_info("init completed:", g_config.sip_username .. "@" .. g_config.sip_domain)
    return true
end

--[[
启动 SIP 服务。
@api exsip.start()
@return boolean 成功返回 true，失败返回 false
@usage
exsip.start()
]]
function exsip.start()
    if not g_config then
        log_error("please call exsip.init() first")
        return false
    end

    if g_started then
        log_info("already started")
        return true
    end

    local ok, err = pcall(function()
        sipclient = require "exsipclient"
    end)

    if not ok or not sipclient then
        log_error("failed to load exsipclient:", err)
        return false
    end

    -- 根据调用方配置设置 VoIP 音频模式
    if g_config.audio_mode ~= nil then
        if not voip or type(voip.setAudioMode) ~= "function" then
            log_error("voip.setAudioMode not supported")
            return false
        end

        local mode_ok = voip.setAudioMode(g_config.audio_mode)

        if not mode_ok and voip.stop then
            log_warn("set audio mode failed, stop voip and retry")
            voip.stop()

            -- 不建议在 exsip 库内部使用 sys.wait(500)
            -- voip.stop 如果是同步完成，可以直接重试
            mode_ok = voip.setAudioMode(g_config.audio_mode)
        end

        if not mode_ok then
            log_error("set voip audio mode failed:", g_config.audio_mode)
            return false
        end

        log_info("voip audio mode configured:", g_config.audio_mode)
    end

    setup_voip_callbacks()

    -- 订阅 IP 就绪/丢失事件
    if not g_ip_event_subscribed then
        sys.subscribe("IP_READY", ip_ready_handler)
        sys.subscribe("IP_LOSE", ip_lose_handler)
        g_ip_event_subscribed = true
        log_info("subscribed to IP_READY and IP_LOSE")
    end

    -- 确定并记录当前实际使用的网卡
    g_current_adapter = g_config.adapter or socket.dft()
    log_info("current adapter set:", g_current_adapter)

    sipclient.start({
        sip_server_addr = g_config.sip_server_addr,
        sip_server_port = g_config.sip_server_port,
        sip_domain = g_config.sip_domain,
        sip_username = g_config.sip_username,
        sip_password = g_config.sip_password,
        sip_transport = g_config.sip_transport,
        adapter = g_config.adapter,
        rtp_port = g_config.rtp_port,
        expires = g_config.expires,
        codecs = g_config.codecs,
        ptime = g_config.ptime,
        call_timeout = g_config.call_timeout,
        debug_sip_response = g_config.debug_sip_response,
        early_media = g_config.early_media,
        early_media_response = g_config.early_media_response,
        event_callback = sip_event_handler
    })

    g_started = true
    -- exnetif.lock_network()
    log_info("started", "adapter", g_config.adapter)
    return true
end

--[[
停止 SIP 服务。
@api exsip.stop()
@return nil 无返回值
@usage
exsip.stop()
]]
function exsip.stop()
    if not g_started then
        return
    end

    stop_voip_engine()

    if sipclient and sipclient.stop then
        sipclient.stop()
    end

    -- 取消订阅 IP 就绪/丢失事件
    if g_ip_event_subscribed then
        sys.unsubscribe("IP_READY", ip_ready_handler)
        sys.unsubscribe("IP_LOSE", ip_lose_handler)
        g_ip_event_subscribed = false
        log_info("unsubscribed from IP_READY and IP_LOSE")
    end

    local timeout = 1000
    while g_started and timeout > 0 do
        sys.wait(10)
        timeout = timeout - 10
    end
    g_started = false
    g_registered = false
    g_current_call = nil
    g_current_adapter = nil
    g_ready_adapters = {}
    reset_call_record_state()
    log_info("stopped")
end

--[[
拨打电话。
@api exsip.dial(target)
@string target 目标号码或 SIP URI，例如 "1002" 或 "sip:1002@example.com"
@return boolean 成功返回 true，失败返回 false
@usage
exsip.dial("1002")
]]
function exsip.dial(target,from_number)
    if not g_started then
        log_error("not started, call exsip.start() first")
        return false
    end

    if not sipclient or not sipclient.call then
        log_error("sipclient.call not available")
        return false
    end

    if type(target) ~= "string" then
        log_error("target must be a string")
        return false
    end
    sipclient.call(target,from_number)
    log_info("calling:", target,from_number)
    return true
end

--[[
接听来电。
@api exsip.accept()
@return boolean 成功返回 true，失败返回 false
@usage
exsip.accept()
]]
function exsip.accept()
    if not g_started then
        log_error("not started")
        return false
    end

    if not sipclient or not sipclient.answer then
        log_error("sipclient.answer not available")
        return false
    end

    sipclient.answer()
    log_info("answering call")
    return true
end

--[[
发送来电早期媒体响应。
@api exsip.progress()
@return boolean 成功返回 true，失败返回 false
@usage
exsip.progress()
]]
function exsip.progress()
    if not g_started then
        log_error("not started")
        return false
    end

    if not sipclient or not sipclient.progress then
        log_error("sipclient.progress not available")
        return false
    end

    sipclient.progress()
    log_info("progressing incoming call")
    return true
end

--[[
挂断通话。
@api exsip.hangUp()
@return boolean 成功返回 true，失败返回 false
@usage
exsip.hangUp()
]]
function exsip.hangUp()
    if not g_started then
        log_error("not started")
        return false
    end

    if not sipclient or not sipclient.hangup then
        log_error("sipclient.hangup not available")
        return false
    end

    sipclient.hangup()
    log_info("hanging up")
    return true
end

--[[
使用指定 SIP 失败码结束尚未接听的来电。
@api exsip.fail(code, reason)
@number code SIP 状态码，默认 486
@string reason 原因短语
@return boolean 成功返回 true，失败返回 false
@usage
exsip.fail(480, "Temporarily Unavailable")
]]
function exsip.fail(code, reason)
    if not g_started then
        log_error("not started")
        return false
    end

    if not sipclient or not sipclient.fail then
        log_error("sipclient.fail not available")
        return false
    end

    sipclient.fail(code, reason)
    log_info("failing incoming call", code, reason)
    return true
end

--[[
发送即时消息。
@api exsip.message(target, text)
@string target 目标号码或 SIP URI
@string text 消息内容
@return boolean 成功返回 true，失败返回 false
@usage
exsip.message("1002", "你好")
]]
function exsip.message(target, text)
    if not g_started then
        log_error("not started")
        return false
    end

    if not sipclient or not sipclient.message then
        log_error("sipclient.message not available")
        return false
    end

    sipclient.message(target, text)
    log_info("sending message to:", target)
    return true
end

--[[
注册事件回调。
@api exsip.on(callback)
@function callback 统一回调函数，参数为 (event_type, arg1, arg2, arg3)
@return nil 无返回值
@usage
exsip.on(function(event_type, arg1, arg2, arg3)
    if event_type == "register" then
        local status, data = arg1, arg2
        log.info("sip", "注册状态:", status)
    elseif event_type == "ready" then
        log.info("sip", "服务就绪")
    elseif event_type == "call" then
        local event, data = arg1, arg2
        log.info("sip", "通话事件:", event)
    elseif event_type == "media" then
        local event, session = arg1, arg2
        log.info("sip", "媒体事件:", event)
    elseif event_type == "message" then
        local event, data = arg1, arg2
        log.info("sip", "消息事件:", event)
    elseif event_type == "voip" then
        local event, data = arg1, arg2
        log.info("voip", "VoIP事件:", event)
    elseif event_type == "error" then
        local action, payload = arg1, arg2
        log.error("sip", "错误:", action)
    end
end)
]]
function exsip.on(callback)
    if type(callback) == "function" then
        local events = {"register", "ready", "call", "media", "message", "dtmf", "voip", "record", "lifecycle", "error"}
        for _, event in ipairs(events) do
            g_callbacks[event] = function(...)
                callback(event, ...)
            end
        end
        log_info("unified callback registered for all events")
    else
        log_error("callback must be a function")
    end
end

--[[
取消事件回调。
@api exsip.off(event)
@string event 事件名称
@return nil 无返回值
@usage
exsip.off("call")
]]
function exsip.off(event)
    g_callbacks[event] = nil
    log_info("callback unregistered for event:", event)
end

--[[
获取当前配置。
@api exsip.get_config()
@return table 当前配置表
@usage
local config = exsip.get_config()
log.info("当前用户:", config.user)
]]
function exsip.get_config()
    if not g_config then
        return nil
    end
    local config_copy = {}
    for k, v in pairs(g_config) do
        if k ~= "password" then
            config_copy[k] = v
        end
    end
    return config_copy
end

--[[
获取当前通话信息。
@api exsip.get_current_call()
@return table 通话信息表，无通话时返回 nil
@usage
local call = exsip.get_current_call()
if call then
    log.info("来电号码:", call.from)
end
]]
function exsip.get_current_call()
    local incoming_number
    if g_current_call.from then
        incoming_number = string.match(g_current_call.from, ':([^:@]+)@')
    end
    return incoming_number
end

--[[
检查 SIP 服务是否已启动。
@api exsip.is_started()
@return boolean 已启动返回 true，否则返回 false
@usage
if exsip.is_started() then
    log.info("SIP 服务已启动")
end
]]
function exsip.is_started()
    return g_started
end

--[[
检查 SIP 是否注册成功。
@api exsip.isRegistered()
@return boolean 已注册返回 true，否则返回 false
@usage
if exsip.isRegistered() then
    log.info("SIP 已注册")
end
]]
function exsip.isRegistered()
    return g_registered
end

--[[
检查 VoIP 引擎是否正在运行。
@api exsip.is_voip_running()
@return boolean 正在运行返回 true，否则返回 false
@usage
if exsip.is_voip_running() then
    log.info("VoIP 引擎正在运行")
end
]]
function exsip.is_voip_running()
    if voip and voip.isRunning then
        return voip.isRunning()
    end
    return false
end

--[[
在当前已建立的 SIP 通话中发送一串 SIP INFO DTMF。
@api exsip.dtmf(digits[, duration_ms[, interval_ms] ])
@string digits DTMF 字符串，仅支持 0-9、A-D、*、#，最长 32 位
@number duration_ms 单位毫秒，默认 160，范围 50-2000
@number interval_ms 两位 INFO 的发送间隔，默认 100，范围 0-5000
@return boolean 参数合法且已投递返回 true，否则返回 false
@usage
exsip.dtmf("13800138000")
exsip.dtmf("*123#", 160, 100)
]]
function exsip.dtmf(digits, duration_ms, interval_ms)
    if not g_started then
        log_error("not started")
        return false
    end
    if not sipclient or not sipclient.dtmf then
        log_error("sipclient.dtmf not available")
        return false
    end
    if type(digits) ~= "string" or #digits == 0 or #digits > 32 then
        log_error("digits must contain 1-32 DTMF characters")
        return false
    end
    digits = digits:upper()
    if not digits:match("^[0-9A-D%*#]+$") then
        log_error("invalid dtmf digits:", digits)
        return false
    end
    duration_ms = tonumber(duration_ms) or 160
    interval_ms = tonumber(interval_ms) or 100
    if duration_ms < 50 or duration_ms > 2000 or interval_ms < 0 or interval_ms > 5000 then
        log_error("invalid dtmf duration or interval")
        return false
    end
    sipclient.dtmf(digits, duration_ms, interval_ms)
    return true
end

--[[
获取库版本信息
@return string 年月日时分，例如： "202606300102"
@usage
exsip.version()
]]
function exsip.version()
    return "202607021200"
end

log.debug("exsip", "version -> " .. exsip.version())

return exsip
