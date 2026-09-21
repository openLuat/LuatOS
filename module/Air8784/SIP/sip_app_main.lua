--[[ @module sip_app_main
@summary SIP注册/呼出/接听/挂断，媒体由audio_drv 的 exaudio 适配层提供
]]
local cfg = require "config"
local audio_drv = require "audio_drv"
local exsip = require "exsip"
local TASK = "sip_app_main_task"
local state, registered, closing = "INIT", false, false

local function set_state(value)
    state = value
    log.info("sip_app", "STATE", state)
    sys.publish("SIP_APP_STATE", state)
end

local function post(command, value)
    sys.sendMsg(TASK, command, value)
end

local function callback(event, action, payload)
    payload = payload or {}
    if event == "ready" then
        registered = true
        if state == "INIT" or state == "OFFLINE" then set_state("READY") end
    elseif event == "register" then
        log.info("sip_app", "REGISTER", action, payload.sip_code, payload.reason)
        if action == "failed" then registered = false post("RESTART") end
    elseif event == "call" then
        log.info("sip_app", "CALL", action)
        if action == "incoming" then
            set_state("INCOMING")
            if cfg.sip.auto_answer then post("ACCEPT") end
        elseif action == "connected" then
            set_state("CONNECTED")
        elseif action == "ended" then
            audio_drv.stop()
            set_state(registered and (audio_drv.is_ready() and "READY" or "AUDIO_RECOVERING") or "OFFLINE")
        end
    elseif event == "media" then
        log.info("sip_app", "MEDIA", action, payload.codec, payload.sample_rate)
        -- 官方 media/ready 不保证桥接成功，以实际设备适配层状态为准。
        if action == "ready" and not audio_drv.is_running() then
            log.error("sip_app", "PCM桥接启动失败")
            post("RESTART")
        end
    elseif event == "voip" then
        if action == "stats" then
            log.info("sip_app", "RTP", "tx", payload.tx_packets,
                "rx", payload.rx_packets, "lost", payload.rx_lost)
        elseif action == "error" then
            log.error("sip_app", "VOIP_ERROR", payload)
            post("RESTART")
        else log.info("sip_app", "VOIP", action, payload) end
    elseif event == "lifecycle" then
        log.info("sip_app", "LIFECYCLE", action)
        if not closing and (action == "offline" or action == "stopped") then
            registered = false
            set_state("OFFLINE")
            post("RESTART")
        end
    elseif event == "error" then
        log.error("sip_app", "ERROR", action, payload.reason or payload.event)
        post("RESTART")
    end
end

local function on_dial_request(_, number) post("DIAL", number) end
sys.subscribe("SIP_APP_MAIN_DIAL_REQ", on_dial_request)
local function on_accept_request() post("ACCEPT") end
sys.subscribe("SIP_APP_MAIN_ACCEPT_REQ", on_accept_request)
local function on_hangup_request() post("HANGUP") end
sys.subscribe("SIP_APP_MAIN_HANGUP_REQ", on_hangup_request)
local function on_primary_request() post("PRIMARY") end
sys.subscribe("SIP_APP_MAIN_PRIMARY_REQ", on_primary_request)
local function on_audio_error(reason)
    log.error("sip_app", reason)
    post("RESTART")
end
sys.subscribe("AUDIO_DRV_ERROR", on_audio_error)

-- 只在业务任务中恢复，避免在SIP/串口回调里阻塞等待；保留正在到来的来电状态。
local function recover_audio()
    if audio_drv.is_ready() then return true end
    if exsip.is_voip_running() then return false end
    if state == "READY" or state == "AUDIO_ERROR" then set_state("AUDIO_RECOVERING") end
    local ok = audio_drv.init()
    if state == "AUDIO_RECOVERING" then
        set_state(ok and (registered and "READY" or "OFFLINE") or "AUDIO_ERROR")
    end
    return ok
end

local function sip_main_task()
    for _, name in ipairs({"sip_server_addr", "sip_username", "sip_password"}) do
        if type(cfg.sip[name]) ~= "string" or cfg.sip[name] == "" then
            log.error("sip_app", "请填写config.lua字段", name)
            set_state("CONFIG_REQUIRED")
            return
        end
    end
    if cfg.sip.sip_transport ~= "udp" and cfg.sip.sip_transport ~= "tcp" then
        log.error("sip_app", "sip_transport仅支持udp/tcp") return
    end
    local sip_config = {}
    for key, value in pairs(cfg.sip) do sip_config[key] = value end
    if sip_config.sip_domain == "" then sip_config.sip_domain = sip_config.sip_server_addr end
    sip_config.adapter = socket.LWIP_GP
    sip_config.auto_answer = false -- 本业务层检查1103就绪后再接听
    if not voip then log.error("sip_app", "固件缺少 voip 库") return end
    sip_config.audio_mode = voip.AUDIO_MODE_BRIDGE
    exsip.on(callback)
    while true do
        registered = false
        while not audio_drv.init() do
            set_state("AUDIO_ERROR")
            log.warn("sip_app", "音频初始化未成功，5秒后重试")
            sys.wait(5000)
        end
        set_state("INIT")
        while not socket.adapter(socket.LWIP_GP) do sys.waitUntil("IP_READY", 1000) end
        sys.cleanMsg(TASK)
        if exsip.init(sip_config) and exsip.start() then
            while true do
                if registered and audio_drv.is_ready() and (state == "AUDIO_RECOVERING" or state == "AUDIO_ERROR") then
                    set_state("READY")
                end
                if (state == "READY" or state == "AUDIO_RECOVERING" or state == "AUDIO_ERROR")
                    and not audio_drv.is_ready() and not exsip.is_voip_running() then
                    if not recover_audio() then sys.wait(5000) end
                end
                local msg = sys.waitMsg(TASK, nil, 1000)
                if not socket.adapter(socket.LWIP_GP) then break end
                if type(msg) == "table" then
                    local command, value = msg[1], msg[2]
                    if command == "RESTART" then break end
                    if command == "PRIMARY" then
                        command = state == "INCOMING" and "ACCEPT" or "DIAL"
                        value = cfg.dial_number
                    end
                    if command == "DIAL" then
                        if registered and (state == "READY" or state == "AUDIO_RECOVERING" or state == "AUDIO_ERROR") then
                            recover_audio()
                        end
                        if state == "READY" and registered and audio_drv.is_ready()
                            and not exsip.is_voip_running() then
                            if type(value) == "string" and value ~= "" then
                                if exsip.dial(value) then set_state("DIALING") end
                            else log.warn("sip_app", "请填写config.dial_number") end
                        else log.warn("sip_app", "暂不能呼出", state, "audio_ready", audio_drv.is_ready()) end
                    elseif command == "ACCEPT" then
                        if state == "INCOMING" and not audio_drv.is_ready() then recover_audio() end
                        local elapsed = 0
                        while state == "INCOMING" and not audio_drv.is_ready()
                            and elapsed < cfg.audio.ready_timeout_ms do
                            sys.waitUntil("AUDIO_DRV_READY", 100)
                            elapsed = elapsed + 100
                        end
                        if state == "INCOMING" and audio_drv.is_ready() then
                            if exsip.accept() then set_state("ANSWERING") end
                        else log.warn("sip_app", "暂不能接听", state, "audio_ready", audio_drv.is_ready()) end
                    elseif command == "HANGUP" then
                        if state == "DIALING" or state == "INCOMING" or state == "ANSWERING" or state == "CONNECTED" then
                            if exsip.hangUp() then set_state("HANGING_UP") end
                        end
                    end
                end
            end
        end
        closing = true
        -- 包括重协商不支持/音频中断在内的异常：先结束SIP对话，再关闭服务。
        if state == "DIALING" or state == "INCOMING" or state == "ANSWERING"
            or state == "CONNECTED" or state == "HANGING_UP" then exsip.hangUp() end
        exsip.stop()
        audio_drv.stop()
        closing = false
        registered = false
        set_state("OFFLINE")
        -- 等待异步媒体销毁，防止下一次通话重用旧音频回调。
        local elapsed = 0
        while exsip.is_voip_running() and elapsed < 10000 do
            sys.wait(100)
            elapsed = elapsed + 100
        end
        if exsip.is_voip_running() then
            log.error("sip_app", "媒体销毁超时，请保存日志后重启设备")
            return
        end
        sys.wait(5000)
    end
end
sys.taskInitEx(sip_main_task, TASK)
