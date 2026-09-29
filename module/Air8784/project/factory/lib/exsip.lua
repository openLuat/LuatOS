--[[
@module exsip
@summary SIP/VoIP 电话扩展库，支持普通 SIP 通话与 CC<->SIP 双向语音流桥接
@version 1.0
@date    2026.04.10
@author  蒋骞
@usage
本库封装了 exsipclient 和 VoIP 引擎，提供更简洁的 API 接口，
让用户更容易上手 SIP/VoIP 电话功能，当前已支持蜂窝通话（CC/VoLTE）与 SIP 的双向语音流桥接。

CC<->SIP 桥接说明：
1、在 exsip.init() 中设置 cc_sip_bridge = true，库会选择 voip.AUDIO_MODE_BRIDGE；
   固件提供 cc.setBridge 时会同步选择 CC 桥接路由，应在 CC/SIP 音频启动前完成初始化。
2、CC -> SIP：蜂窝对端语音解码为 PCM 后送入 VoIP，由 VoIP 编码为 G.711 RTP 发往 SIP 对端。
   SIP -> CC：SIP RTP 经 VoIP 解码为 PCM 后送入 CC 上行，传给蜂窝对端。
   SIP 侧使用 PCMU/PCMA、8kHz 单声道，CC 侧 8kHz/16kHz 的采样率适配由底层桥接完成。
3、桥接依赖固件的 CC/VoIP PCM 桥接能力。CC 管理通话音频硬件，SIP 不再启动本地 Audio V2 speech；
   应用无需在 Lua 中调用 voip.pcmIn/pcmOut 搬运 CC 音频。
4、cc_sip_bridge 默认 false。audio_mode 选择 VoIP 音频模式，普通 SIP 下的 AUDIO_MODE_BRIDGE
   用于本地 Audio V2 等 PCM 适配；经本库启用 CC<->SIP 桥接需设置 cc_sip_bridge = true。
5、本库负责 SIP 信令和 VoIP 媒体启停；CC 的拨号、接听、挂断，以及两侧通话联动由应用控制。
   SIP 来电转蜂窝外呼时，可先调用 exsip.progress() 建立 183 早期媒体，待 CC 接通后再调用 exsip.accept()。
6、桥接模式下不启动 record.auto 自动录音。停止 SIP 或挂断不会清除桥接选择；切换路由前应停止
   SIP 服务并等待 CC/SIP 媒体释放，再通过 exsip.init() 显式设置 cc_sip_bridge = false。
完整的两侧通话联动示例见 module/Air8000/demo/sip_cc_bridge。

基本用法：
local exsip = require "exsip"

-- 配置 SIP 账号；下面的来电回调直接接听 SIP，适用于普通 SIP 通话。
-- CC<->SIP 桥接时在配置中添加 cc_sip_bridge = true，并由应用协调 CC 呼叫与 SIP 接听。
local config = {
    sip_server_addr = "192.168.1.100",
    sip_server_port = 5060,
    sip_domain = "192.168.1.100",
    sip_username = "1001",
    sip_password = "123456"
}

-- 设置统一事件回调
exsip.on(function(event_type, action, data)
    if event_type == "register" then
        log.info("sip", "注册状态:", action)
    elseif event_type == "call" then
        if action == "incoming" then
            log.info("sip", "来电:", data.from)
            exsip.accept()
        elseif action == "connected" then
            log.info("sip", "通话已建立")
        elseif action == "ended" then
            log.info("sip", "通话已结束")
        end
    end
end)

-- 启动前需要先通过exaudio.setup()或BSP等价接口初始化音频硬件。
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
-- 版本号：202609171331
-- 1、更新时间：2026-09-17 13:31
-- 2、更新内容
--    自动接听定时器绑定来电 Call-ID，忽略旧通话遗留的定时回调。
--    接听命令携带当前 Call-ID，避免排队中的旧命令误接新通话。
-- 版本号：202609161450
-- 1、更新时间：2026-09-16 14:50
-- 2、更新内容
--    初始化阶段校验并选择 CC-SIP 桥接路由，失败时保留原配置。
--    SIP 服务运行或媒体尚未释放时禁止更改路由，停止 SIP 后保留桥接选择。
--    兼容缺少 cc.setBridge 的旧版桥接固件，保留桥接配置并打印警告继续初始化。
-- 版本号：202608311130
-- 1、更新时间：2026-08-31 11:30
-- 2、更新内容
--    透传同步 AEC 后端、延迟、降噪和 AGC 配置，并默认使用 Speex/20ms 延迟。
-- 版本号：202608271848
-- 1、更新时间：2026-08-27 18:48
-- 2、更新内容
--    统一普通SIP与CC-SIP桥接模式选择，修复启动失败传播和Audio V2 bridge清理。
-- 版本号：202608271100
-- 1、更新时间：2026-08-27 11:00
-- 2、更新内容
--    Air8101/Air8101B 使用 Audio V2 DAC 直连 VoIP，禁止误入 PCM bridge。
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
-- 媒体准备任务可被 CANCEL / 挂断 / 断网取消；C start 已受理也属于占用。
local g_media_generation = 0
local g_media_pending = false
local g_media_requested = false
local g_media_stopping = false
local MEDIA_PREPARE_TIMEOUT_MS = 2000
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
    sip_server_port = exsip.DEFAULT_SIP_PORT,
    rtp_port = exsip.DEFAULT_RTP_PORT,
    expires = exsip.DEFAULT_EXPIRES,
    codecs = { exsip.CODEC_PCMU, exsip.CODEC_PCMA },
    ptime = 20,
    auto_answer = false,
    delay_auto_answer = 0,
    call_timeout = 30,
    debug_sip_response = false,
    early_media = true,
    aec = false,
    aec_mode = "speex",
    aec_denoise = true,
    aec_agc = false,
    aec_delay_samples = 160,
    aec_tail = 200,
    early_media_response = 183,
    adapter = nil,  -- nil = 使用系统默认网卡
    audio_mode = nil,  -- nil = 自动选择本地音频路径；CC 桥接启用时自动设为 AUDIO_MODE_BRIDGE。
    -- true: 选择 CC<->SIP 双向语音流桥接，由 CC 管理音频硬件，SIP 仅处理 RTP/PCM。
    -- false: 普通 SIP；AUDIO_MODE_BRIDGE 用于本地 PCM 适配，不选择 CC 桥接路由。
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

    local auto = config.auto
    if auto == nil then
        auto = false
    end

    local record = {
        auto = auto,
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

local function has_voip_pcm_bridge()
    return voip and type(voip.setAudioMode) == "function" and
        voip.AUDIO_MODE_BRIDGE ~= nil and type(voip.pcmIn) == "function" and
        type(voip.pcmOut) == "function"
end

local function set_voip_audio_mode(mode)
    if mode == nil then return true end
    if not voip then
        log_error("voip core not support")
        return false
    end
    if type(voip.setAudioMode) ~= "function" then
        -- 未编入bridge的固件只有直接硬件模式，AUDIO_MODE_I2S即默认模式。
        if voip.AUDIO_MODE_I2S ~= nil and mode == voip.AUDIO_MODE_I2S then
            return true
        end
        log_error("voip.setAudioMode not supported for mode", mode)
        return false
    end
    local call_ok, mode_ok = pcall(voip.setAudioMode, mode)
    if not call_ok or not mode_ok then
        log_error("set voip audio mode failed:", mode, mode_ok)
        return false
    end
    return true
end

local function stop_exaudio_voip_bridge()
    if not g_voip_uses_exaudio then return end
    g_voip_uses_exaudio = false
    if type(exaudio.sip_voip_stop) == "function" then
        local ok, err = pcall(exaudio.sip_voip_stop)
        if not ok then
            log_warn("stop audio_v2 SIP bridge failed", err)
        end
    end
end

local function start_voip_engine_now(session)
    if not voip then
        log_error("voip core not support")
        return
    end
    -- 唤醒音频硬件（audio_v2 框架下 ES8311 可能处于 shutdown，需先恢复）
    if exaudio.pm then
        pcall(exaudio.pm, exaudio.RESUME)
    end

    local codec_map = {
        [exsip.CODEC_PCMU] = voip.PCMU,
        [exsip.CODEC_PCMA] = voip.PCMA
    }
    local codec = codec_map[session.codec] or voip.PCMU

    -- 普通SIP可自动选择C层直接硬件或Lua Audio V2 PCM bridge；CC-SIP桥接
    -- 必须由CC C层独占音频硬件，不能再启动本地SIP speech。
    local is_cc_sip_bridge = g_config and g_config.cc_sip_bridge == true
    local bsp = rtos and rtos.bsp and rtos.bsp()
    local model = hmeta and hmeta.model and hmeta.model()
    local platform = type(bsp) == "string" and bsp or model
    local is_air8101 = type(platform) == "string" and
        platform:lower():find("air8101", 1, true) ~= nil
    local has_pcm_bridge = has_voip_pcm_bridge()
    local audio_v2_enabled = type(exaudio.is_audio_v2) == "function" and exaudio.is_audio_v2()
    local configured_mode = g_config and g_config.audio_mode
    local use_sip_audio_v2 = false

    stop_exaudio_voip_bridge()
    if is_cc_sip_bridge then
        if not has_pcm_bridge or configured_mode ~= voip.AUDIO_MODE_BRIDGE then
            log_error("CC-SIP bridge requires AUDIO_MODE_BRIDGE and PCM bridge APIs")
            return
        end
        log_info("CC-SIP bridge: skip local audio_v2 speech")
    elseif configured_mode ~= nil then
        if has_pcm_bridge and configured_mode == voip.AUDIO_MODE_BRIDGE then
            if is_air8101 then
                log_error("Air8101 does not support local PCM bridge mode")
                return
            end
            if not audio_v2_enabled then
                log_error("AUDIO_MODE_BRIDGE requires the active Audio V2 framework")
                return
            end
            use_sip_audio_v2 = true
            log_info("configured Audio V2 PCM bridge mode", platform)
        else
            log_info("configured direct hardware audio mode", configured_mode, platform)
        end
    else
        use_sip_audio_v2 = not is_air8101 and audio_v2_enabled and has_pcm_bridge
        local auto_mode = use_sip_audio_v2 and voip.AUDIO_MODE_BRIDGE or voip.AUDIO_MODE_I2S
        if not set_voip_audio_mode(auto_mode) then return end
        if is_air8101 and audio_v2_enabled then
            log_info("Air8101 Audio V2 DAC direct mode", platform)
        elseif use_sip_audio_v2 then
            log_info("automatic Audio V2 PCM bridge mode", platform)
        else
            log_info("automatic direct hardware audio mode", platform)
        end
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
        aec = g_config.aec == true,
        aec_mode = g_config.aec_mode,
        aec_denoise = g_config.aec_denoise == true,
        aec_agc = g_config.aec_agc == true,
        aec_delay_samples = tonumber(g_config.aec_delay_samples) or 160,
        aec_tail = tonumber(g_config.aec_tail) or 200
    })

    if ok then
        g_media_requested = true
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
        return true
    else
        log_error("voip engine start failed")
    end
    return false
end

local function start_voip_engine(session)
    if not voip then
        log_error("voip core not support")
        return
    end
    -- 同一会话的 183 / 200 媒体通知不能重复申请硬件。
    if g_media_pending or (g_media_requested and not g_media_stopping) then return end
    g_media_generation = g_media_generation + 1
    local generation = g_media_generation
    g_media_pending = true
    emit_callback("voip", "state", "starting")
    sys.taskInit(function()
        local remaining = MEDIA_PREPARE_TIMEOUT_MS
        local function current()
            return generation == g_media_generation and g_started
        end
        local function fail(reason)
            if not current() then return end
            g_media_pending = false
            emit_callback("voip", "error", reason)
            if not g_media_requested then emit_callback("voip", "state", "stopped") end
        end
        -- 上一个通话仍在释放 DMA 时，新的媒体请求等待 stopped。
        while current() and g_media_requested and remaining > 0 do
            sys.wait(20)
            remaining = remaining - 20
        end
        if not current() then return end
        if g_media_requested then fail("audio_stop_timeout") return end
        -- CC 桥接时保留 CC 正在使用的音频驱动和早期媒体，不执行普通 SIP 的本地播放清理。
        if not (g_config and g_config.cc_sip_bridge) then
            local stop_driver = audio_v2 and type(audio_v2.stop_driver) == "function" and
                type(exaudio.is_audio_v2) == "function" and exaudio.is_audio_v2()
            for play_type = 0, 2 do
                local ok, err = pcall(exaudio.play_stop, {type = play_type})
                if stop_driver and not ok then fail("audio_stop_failed: " .. tostring(err)) return end
            end
            -- 仅提供同步停驱动接口的 audio_v2 平台等待请求释放。
            -- 其他平台保留原有的三次 play_stop pcall 后直接启动行为。
            if stop_driver then
                if type(exaudio.is_end) == "function" then
                    while current() and remaining > 0 do
                        local ok, done = pcall(exaudio.is_end)
                        if not ok then fail("audio_state_failed") return end
                        if done then break end
                        sys.wait(20)
                        remaining = remaining - 20
                    end
                    if not current() then return end
                    if remaining <= 0 then fail("audio_stop_timeout") return end
                end
                -- request cancel 完成后停止空转的驱动，保留共享 I2C。
                local ok, stopped = pcall(audio_v2.stop_driver)
                if not ok or not stopped then fail("audio_driver_stop_failed") return end
            end
        end
        if not current() then return end
        g_media_pending = false
        local ok, started = pcall(start_voip_engine_now, session)
        if not ok or not started then
            fail(ok and "audio_start_failed" or tostring(started))
        end
    end)
end

local function stop_voip_engine()
    if not voip then
        return
    end
    stop_call_record()
    local was_pending = g_media_pending
    g_media_generation = g_media_generation + 1
    g_media_pending = false
    stop_exaudio_voip_bridge()
    if g_media_requested or voip.isRunning() then
        if not g_media_stopping then
            g_media_stopping = true
            emit_callback("voip", "state", "stopping")
            voip.stop() -- 包括 start 已入队、尚未 reported started 的情况。
            log_info("voip engine stopping")
        end
    elseif was_pending then
        emit_callback("voip", "state", "stopped")
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
                    local call_id = payload.call_id
                    sys.timerStart(function()
                        if g_started and g_current_call and g_current_call.call_id == call_id then
                            exsip.accept()
                        end
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
            stop_voip_engine()
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
            if state == "stopped" or state == "idle" then
                g_media_requested = false
                g_media_stopping = false
            end
            if state == "stopped" or state == "error" or state == "idle" then
                stop_exaudio_voip_bridge()
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
CC<->SIP 桥接应在 CC/SIP 音频启动前配置，cc_sip_bridge=true 会自动选择 AUDIO_MODE_BRIDGE。
固件提供 cc.setBridge 时由本接口同步选择 CC 路由；旧版桥接固件缺少该接口时保留配置并警告。
路由切换要求 SIP 服务停止且 CC/SIP 媒体已释放，校验或路由选择失败时保留原配置。
@api exsip.init(config)
@table config 配置参数表
@string config.sip_server_addr SIP 服务器地址
@number config.sip_server_port SIP 服务器端口，默认 5060
@string config.sip_domain SIP 域
@string config.sip_username SIP 用户名
@string config.sip_password SIP 密码
@string config.sip_transport SIP 传输协议，"UDP" 或 "TCP"，默认 "TCP"
@number config.rtp_port 本地 RTP 端口，默认 40000
@number config.expires 注册有效期（秒），默认 600
@table config.codecs 编解码器列表，默认 {"PCMU", "PCMA"}
@number config.ptime 打包时长（毫秒），默认 20
@boolean config.auto_answer 是否自动接听，默认 false
@number config.delay_auto_answer 自动接听延迟（秒），默认 0
@number config.call_timeout 拨号超时时间（秒），默认 30
@boolean config.debug_sip_response 是否打印完整 SIP 服务器响应，默认 false
@number config.adapter 网络适配器，nil=使用系统默认，socket.LWIP_GP=4G，socket.LWIP_STA=WiFi，socket.LWIP_ETH=以太网
@boolean config.cc_sip_bridge 是否启用 CC<->SIP 双向语音流桥接，默认 false；需固件支持 CC/VoIP PCM 桥接
@number config.audio_mode VoIP 音频模式，nil=自动选择；支持 voip.AUDIO_MODE_I2S、voip.AUDIO_MODE_BRIDGE；CC 桥接时仅允许 nil 或 AUDIO_MODE_BRIDGE
@boolean config.early_media 是否允许通过 progress() 发送来电早期媒体响应，默认 true
@number config.early_media_response 来电早期响应，默认 183（带 SDP，可启动媒体）；设为 180 时仅发送振铃响应
@table config.record 通话录音配置，默认关闭；支持 auto、dir、prefix、max_seconds；CC 桥接模式不启动自动录音
@boolean config.aec 是否启用回声消除，默认 false；需要时由应用显式开启
@string config.aec_mode AEC 后端，"speex" 或 "bk"，默认 "speex"
@boolean config.aec_denoise 是否启用后端降噪，默认 true
@boolean config.aec_agc 是否启用 Speex AGC，默认 false
@number config.aec_delay_samples 声学延迟采样点数，默认 160
@number config.aec_tail Speex 回声尾长（毫秒），默认 200
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

    if config.aec ~= nil and type(config.aec) ~= "boolean" then
        log_error("aec must be a boolean")
        return false
    end
    if config.aec_mode ~= nil and config.aec_mode ~= "speex" and config.aec_mode ~= "bk" then
        log_error("aec_mode must be 'speex' or 'bk'")
        return false
    end
    if config.aec_denoise ~= nil and type(config.aec_denoise) ~= "boolean" then
        log_error("aec_denoise must be a boolean")
        return false
    end
    if config.aec_agc ~= nil and type(config.aec_agc) ~= "boolean" then
        log_error("aec_agc must be a boolean")
        return false
    end

    local record_config, record_err = validate_record_config(config.record)
    if not record_config then
        log_error("invalid record config:", record_err)
        return false
    end
    if config.cc_sip_bridge ~= nil and type(config.cc_sip_bridge) ~= "boolean" then
        log_error("cc_sip_bridge must be a boolean")
        return false
    end

    local next_config = {}
    for k, v in pairs(default_config) do
        next_config[k] = v
    end
    for k, v in pairs(config) do
        next_config[k] = v
    end
    next_config.record = record_config
    if next_config.audio_mode ~= nil and (not voip or
        (next_config.audio_mode ~= voip.AUDIO_MODE_I2S and
         next_config.audio_mode ~= voip.AUDIO_MODE_BRIDGE)) then
        log_error("unsupported audio_mode")
        return false
    end
    if next_config.cc_sip_bridge then
        if not has_voip_pcm_bridge() then
            log_error("CC-SIP bridge requires PCM bridge APIs")
            return false
        end
        if next_config.audio_mode ~= nil and next_config.audio_mode ~= voip.AUDIO_MODE_BRIDGE then
            log_error("cc_sip_bridge conflicts with configured audio_mode")
            return false
        end
        next_config.audio_mode = voip.AUDIO_MODE_BRIDGE
    end
    if g_config and (g_started or g_media_pending or g_media_requested) and
        (next_config.cc_sip_bridge ~= g_config.cc_sip_bridge or
         next_config.audio_mode ~= g_config.audio_mode) then
        log_error("stop SIP and CC media before changing the audio route")
        return false
    end
    if not next_config.sip_domain then
        next_config.sip_domain = next_config.sip_server_addr
    end

    -- 在 CC 早期媒体启动前选择桥接路由；底层切换路由时检查两侧是否空闲，失败不改动状态。
    -- 启用时同时选择 VoIP PCM 模式，后续由 CC C 层完成双向语音流转发。
    if cc and type(cc.setBridge) == "function" then
        local call_ok, selected = pcall(cc.setBridge, next_config.cc_sip_bridge)
        if not call_ok or not selected then
            log_error("CC-SIP route is busy or unavailable", selected)
            return false
        end
    elseif next_config.cc_sip_bridge then
        -- 旧版桥接固件通过 audio_mode 选择 CC 路由，兼容保留桥接配置。
        log_warn("cc.setBridge unavailable; keeping legacy CC-SIP bridge mode")
    end
    g_config = next_config
    if g_config.cc_sip_bridge and g_config.record.auto then
        log_warn("automatic recording is disabled for CC-SIP bridge mode")
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

    -- init 已校验路由；旧版 CC 桥接固件在此通过 PCM 模式完成路由选择。
    if not set_voip_audio_mode(g_config.audio_mode) then
        return false
    end
    if g_config.audio_mode ~= nil then
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

    local start_call_ok, sip_started = pcall(sipclient.start, {
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
    if not start_call_ok or not sip_started then
        if g_ip_event_subscribed then
            sys.unsubscribe("IP_READY", ip_ready_handler)
            sys.unsubscribe("IP_LOSE", ip_lose_handler)
            g_ip_event_subscribed = false
        end
        g_current_adapter = nil
        log_error("sipclient.start failed:", sip_started)
        return false
    end

    g_started = true
    -- exnetif.lock_network()
    log_info("started", "adapter", g_config.adapter)
    return true
end

--[[
停止 SIP 服务。
停止 SIP 信令和 VoIP 媒体，保留 CC 桥接选择；CC 通话的挂断由应用单独处理。
@api exsip.stop()
@return nil 无返回值
@usage
exsip.stop()
]]
function exsip.stop()
    if not g_started then
        return
    end

    -- SIP 停止后 CC 可能仍在完成 PLAY_STOP，保留桥接选择直到后续 init 成功切换路由。
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

    -- 保留原有 SIP 异步收尾的 1 秒窗口；仅未释放的媒体需要继续等待。
    local elapsed = 0
    while elapsed < 1000 or (g_media_requested and elapsed < MEDIA_PREPARE_TIMEOUT_MS) do
        sys.wait(10)
        elapsed = elapsed + 10
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
拨打 SIP 电话；CC 来电转 SIP 外呼时，应用可通过 from_number 透传蜂窝主叫号码作为显示名。
@api exsip.dial(target, from_number)
@string target 目标号码或 SIP URI，例如 "1002" 或 "sip:1002@example.com"
@string from_number 可选，写入本次 SIP 外呼 From 头的显示名，不修改注册账号
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
桥接场景可由应用在 CC 接通后调用，只接听 SIP 侧，不代替 cc.accept()。
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

    sipclient.answer(g_current_call and g_current_call.call_id)
    log_info("answering call")
    return true
end

--[[
发送来电早期媒体响应。
默认发送 183 + SDP，协商完成后启动 VoIP，可用于向 SIP 对端转发 CC 侧早期语音。
此操作不接听 SIP，也不发起 CC 呼叫；early_media=false 时不发送，响应配置为 180 时不启动早期媒体。
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
挂断 SIP 通话并请求停止 VoIP 媒体；桥接场景下应用还需处理 CC 侧挂断。
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

    stop_voip_engine()
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
桥接模式沿用相同事件：media/ready 表示 SIP 媒体参数就绪，VoIP 启动结果由 voip 事件报告。
call/connected、call/ended 只表示 SIP 侧通话状态，CC 侧状态与两侧接听、挂断联动由应用处理。
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
log.info("当前用户:", config.sip_username)
]]
function exsip.get_config()
    if not g_config then
        return nil
    end
    local config_copy = {}
    for k, v in pairs(g_config) do
        if k ~= "password" and k ~= "sip_password" then
            config_copy[k] = v
        end
    end
    return config_copy
end

--[[
获取当前通话信息。
@api exsip.get_current_call()
@return string 来电号码，无通话或无法解析时返回 nil
@usage
local incoming_number = exsip.get_current_call()
if incoming_number then
    log.info("来电号码:", incoming_number)
end
]]
function exsip.get_current_call()
    if not g_current_call or type(g_current_call.from) ~= "string" then return nil end
    return string.match(g_current_call.from, ':([^:@]+)@')
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
查询媒体是否占用音频，包含启动准备、C start 已受理以及等待 stopped。
TTS / 本地播放应使用此接口，is_voip_running 仍保持原有通话运行语义。
@api exsip.is_voip_busy()
@return boolean 是否仍占用音频
]]
function exsip.is_voip_busy()
    return g_media_pending or g_media_requested or g_media_stopping or
        (voip and type(voip.isRunning) == "function" and voip.isRunning()) or false
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
    return "202609171331"
end

log.debug("exsip", "version -> " .. exsip.version())

return exsip
