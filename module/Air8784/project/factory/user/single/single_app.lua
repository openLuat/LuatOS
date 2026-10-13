--[[
@module  single_app
@summary 单SIP注册和通话业务
@version 2.0
@date    2026.09.29
@author  王世豪
@usage
协同配置版本：运行模式独立于主动任务保存，删除任务不改变模式。
由统一入口在pair/round模式加载，使用single_audio及single_config。
显式关闭CC桥接；接收SIP_APP_MAIN_*事件，不加载CC通话模块。
]]
local task_voice = require "task_voice"
local cfg = require "single_config"
local single_audio = require "single_audio"
local exsip = require "exsip"
local TASK = "single_app_main_task"
local state, registered, closing = "INIT", false, false

local function set_state(value)
    if value~="READY" then task_voice.cancel("single call state") end
    state = value
    log.info("single_app", "STATE", state)
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
        log.info("single_app", "REGISTER", action, payload.sip_code, payload.reason)
        if action == "failed" then registered = false post("RESTART") end
    elseif event == "call" then
        log.info("single_app", "CALL", action)
        if action == "incoming" then
            set_state("INCOMING")
            log.info("single_app", "接通电话")
            post("RING")   -- 来电后持续振铃, 由按键/接听请求触发 ACCEPT
        elseif action == "connected" then
            set_state("CONNECTED")
        elseif action == "ended" then
            single_audio.stop_ringback(true)   -- 先停循环振铃(不复位, 避免复位吞掉挂断提示音)
            -- skip_recover=true: 停桥接但先不恢复MIC(避免复位吞掉挂断提示音), 播完由提示音队列复位恢复
            single_audio.stop(true)
            set_state(registered and (single_audio.is_ready() and "READY" or "AUDIO_RECOVERING") or "OFFLINE")
            log.info("single_app", "对方已挂断", "播放挂断提示音")
            single_audio.play_hangup()
        end
    elseif event == "media" then
        log.info("single_app", "MEDIA", action, payload.codec, payload.sample_rate)
        -- 官方 media/ready 不保证桥接成功，以实际设备适配层状态为准。
        if action == "ready" and not single_audio.is_running() then
            log.error("single_app", "PCM桥接启动失败")
            post("RESTART")
        end
    elseif event == "voip" then
        if action == "stats" then
            log.info("single_app", "RTP", "tx", payload.tx_packets,
                "rx", payload.rx_packets, "lost", payload.rx_lost)
        elseif action == "error" then
            log.error("single_app", "VOIP_ERROR", payload)
            post("RESTART")
        else log.info("single_app", "VOIP", action, payload) end
    elseif event == "lifecycle" then
        log.info("single_app", "LIFECYCLE", action)
        if not closing and (action == "offline" or action == "stopped") then
            registered = false
            set_state("OFFLINE")
            post("RESTART")
        end
    elseif event == "error" then
        log.error("single_app", "ERROR", action, payload.reason or payload.event)
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
    log.error("single_app", reason)
    post("RESTART")
end
sys.subscribe("AUDIO_DRV_ERROR", on_audio_error)

-- 只在业务任务中恢复，避免在SIP/串口回调里阻塞等待；保留正在到来的来电状态。
local function recover_audio()
    if single_audio.is_ready() then return true end
    if exsip.is_voip_running() then return false end
    if state == "READY" or state == "AUDIO_ERROR" then set_state("AUDIO_RECOVERING") end
    local ok = single_audio.init()
    if state == "AUDIO_RECOVERING" then
        set_state(ok and (registered and "READY" or "OFFLINE") or "AUDIO_ERROR")
    end
    return ok
end

local function single_app_task()
    for _, name in ipairs({"sip_server_addr", "sip_username", "sip_password"}) do
        if type(cfg.sip[name]) ~= "string" or cfg.sip[name] == "" then
            log.error("single_app", "请填写config.lua字段", name)
            set_state("CONFIG_REQUIRED")
            return
        end
    end
    if cfg.sip.sip_transport ~= "udp" and cfg.sip.sip_transport ~= "tcp" then
        log.error("single_app", "sip_transport仅支持udp/tcp") return
    end
    local sip_config = {}
    for key, value in pairs(cfg.sip) do sip_config[key] = value end
    if sip_config.sip_domain == "" then sip_config.sip_domain = sip_config.sip_server_addr end
    sip_config.adapter = socket.LWIP_GP
    sip_config.auto_answer = false -- 本业务层检查1103就绪后再接听
    if not voip then log.error("single_app", "固件缺少 voip 库") return end
    sip_config.cc_sip_bridge = false
    sip_config.audio_mode = voip.AUDIO_MODE_BRIDGE
    exsip.on(callback)
    while true do
        registered = false
        while not single_audio.init() do
            set_state("AUDIO_ERROR")
            log.warn("single_app", "音频初始化未成功，5秒后重试")
            sys.wait(5000)
        end
        set_state("INIT")
        while not socket.adapter(socket.LWIP_GP) do sys.waitUntil("IP_READY", 1000) end
        sys.cleanMsg(TASK)
        if exsip.init(sip_config) and exsip.start() then
            while true do
                if registered and single_audio.is_ready() and (state == "AUDIO_RECOVERING" or state == "AUDIO_ERROR") then
                    set_state("READY")
                end
                if (state == "READY" or state == "AUDIO_RECOVERING" or state == "AUDIO_ERROR")
                    and not single_audio.is_ready() and not exsip.is_voip_running() then
                    if not recover_audio() then sys.wait(5000) end
                end
                local msg = sys.waitMsg(TASK, nil, 1000)
                if not socket.adapter(socket.LWIP_GP) then break end
                if type(msg) == "table" then
                    local command, value = msg[1], msg[2]
                    if command == "RESTART" then break end
                    if command == "RING" then
                        log.info("single_app", "呼入振铃", "未接通前持续振铃")
                        single_audio.play_ringback_loop()
                    end
                    if command == "PRIMARY" then
                        command = state == "INCOMING" and "ACCEPT" or "DIAL"
                        value = cfg.dial_number
                    end
                    if command == "DIAL" then
                        if registered and (state == "READY" or state == "AUDIO_RECOVERING" or state == "AUDIO_ERROR") then
                            recover_audio()
                        end
                        if state == "READY" and registered and single_audio.is_ready()
                            and not exsip.is_voip_running() then
                            if type(value) == "string" and value ~= "" then
                                if exsip.dial(value) then set_state("DIALING") end
                            else log.warn("single_app", "请填写config.dial_number") end
                        else log.warn("single_app", "暂不能呼出", state, "audio_ready", single_audio.is_ready()) end
                    elseif command == "ACCEPT" then
                        if state == "INCOMING" then single_audio.stop_ringback() end   -- 先停振铃再接听
                        if state == "INCOMING" and not single_audio.is_ready() then recover_audio() end
                        local elapsed = 0
                        while state == "INCOMING" and not single_audio.is_ready()
                            and elapsed < cfg.audio.ready_timeout_ms do
                            sys.waitUntil("AUDIO_DRV_READY", 100)
                            elapsed = elapsed + 100
                        end
                        if state == "INCOMING" and single_audio.is_ready() then
                            if exsip.accept() then set_state("ANSWERING") end
                        else log.warn("single_app", "暂不能接听", state, "audio_ready", single_audio.is_ready()) end
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
        single_audio.stop()
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
            log.error("single_app", "媒体销毁超时，请保存日志后重启设备")
            return
        end
        sys.wait(5000)
    end
end
sys.taskInitEx(single_app_task, TASK)

-- 只读就绪状态供AirCloud协同配置使用。
local function status()
    return registered, single_audio.is_ready()
end
return {status=status}
