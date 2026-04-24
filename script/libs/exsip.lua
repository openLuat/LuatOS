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
]]
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
local g_callbacks = {}
local g_current_call = nil

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
    adapter = nil  -- nil = 使用系统默认网卡
}


local function log_info(...)
    if _G.log and type(log.info) == "function" then
        log.info("exsip", ...)
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

local function start_voip_engine(session)
    if not voip then
        log_error("voip core not support")
        return
    end

    local codec_map = {
        [exsip.CODEC_PCMU] = voip.PCMU,
        [exsip.CODEC_PCMA] = voip.PCMA
    }
    local codec = codec_map[session.codec] or voip.PCMU

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
        adapter = g_config.adapter
    })

    if ok then
        log_info("voip engine started", session.remote_ip .. ":" .. session.remote_port,
            "codec=" .. tostring(session.codec))
    else
        log_error("voip engine start failed")
    end
end

local function stop_voip_engine()
    if not voip then
        return
    end
    if voip.isRunning() then
        voip.stop()
        log_info("voip engine stopping")
    end
end

local function sip_event_handler(event, action, payload)
    log_info("event:", event, "action:", action)

    if event == "register" then
        if action == "ok" then
            emit_callback("register", true, payload)
            emit_callback("ready")
        else
            emit_callback("register", false, payload)
        end
    elseif event == "call" then
        if action == "incoming" then
            g_current_call = {
                from = payload.from,
                call_id = payload.call_id
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
        elseif action == "connected" then
            emit_callback("call", "connected", payload)
        elseif action == "ended" or action == "failed" then
            stop_voip_engine()
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
            emit_callback("voip", "state", state)
        end)

        voip.on("stats", function(stats)
            emit_callback("voip", "stats", stats)
        end)

        voip.on("error", function(err)
            log_error("voip error:", err)
            emit_callback("voip", "error", err)
        end)
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
@number config.adapter 网络适配器，nil=使用系统默认，socket.LWIP_GP=4G，socket.LWIP_STA=WiFi，socket.LWIP_ETH=以太网
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
    if not config or type(config) ~= "table" then
        log_error("config must be a table")
        return false
    end

    if not config.sip_server_addr or not config.sip_username or not config.sip_password then
        log_error("server, user and password are required")
        return false
    end

    g_config = {}
    for k, v in pairs(default_config) do
        g_config[k] = v
    end
    for k, v in pairs(config) do
        g_config[k] = v
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

    setup_voip_callbacks()

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
        event_callback = sip_event_handler
    })

    g_started = true
    log_info("started")
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

    local timeout = 1000
    while g_started and timeout > 0 do
        sys.wait(10)
        timeout = timeout - 10
    end
    g_started = false
    g_current_call = nil
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
function exsip.dial(target)
    if not g_started then
        log_error("not started, call exsip.start() first")
        return false
    end

    if not sipclient or not sipclient.call then
        log_error("sipclient.call not available")
        return false
    end

    sipclient.call(target)
    log_info("calling:", target)
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
        local events = {"register", "ready", "call", "media", "message", "voip", "error"}
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
    return g_current_call
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

return exsip
