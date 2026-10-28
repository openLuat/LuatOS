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
local call_voice = require "call_voice"
local cfg = require "single_config"
local single_audio = require "single_audio"
local exsip = require "exsip"
local settings = require "aircloud_settings"
local answer_policy = require "incoming_answer"
local answer = answer_policy.new()
local TASK = "single_app_main_task"
local state, registered, closing = "INIT", false, false
local registration_epoch=0
local call_generation, preparing_dial = 0, false
local end_pending=false
local function media_busy()
    return exsip.is_voip_busy()
end

local function set_state(value)
    if value~="READY" then task_voice.cancel("single call state") end
    if value~="INCOMING" then answer.cancel() end
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
        if not registered then registration_epoch=registration_epoch+1 end
        registered = true
        if state == "INIT" or state == "OFFLINE" then set_state("READY") end
    elseif event == "register" then
        log.info("single_app", "REGISTER", action, payload.sip_code, payload.reason)
        if action == "failed" then registered = false post("RESTART") end
    elseif event == "call" then
        log.info("single_app", "CALL", action)
        if action == "incoming" then
            end_pending=false
            call_generation=call_generation+1
            call_voice.cancel()
            set_state("INCOMING")
            log.info("single_app", "接通电话")
            post("RING",call_generation)   -- 旧来电的排队消息不得作用于新来电
            answer.start(settings.answer_settings(), function(token)
                post("AUTO_ACCEPT", token)
            end)
        elseif action == "ringing" then
            if state=="DIALING" then post("RINGBACK",call_generation) end
        elseif action == "connected" then
            call_voice.cancel()
            single_audio.stop_ringback(true,true)
            set_state("CONNECTED")
        elseif action == "ended" then
            call_generation=call_generation+1
            call_voice.cancel()
            single_audio.stop_ringback(true,true) -- 停铃但保持 MIC，不让复位吞掉后续播报
            -- skip_recover=true: 停桥接但先不恢复MIC(避免复位吞掉挂断提示音), 播完由提示音队列复位恢复
            single_audio.stop(true)
            set_state(registered and (single_audio.is_ready() and "READY" or "AUDIO_RECOVERING") or "OFFLINE")
            log.info("single_app", "对方已挂断", "播放挂断提示音")
            end_pending=true
            post("ANNOUNCE_END", {generation=call_generation,reason=payload.reason})
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
local function on_accept_request() call_voice.cancel();post("ACCEPT") end
sys.subscribe("SIP_APP_MAIN_ACCEPT_REQ", on_accept_request)
local function on_hangup_request()
    -- The task engine calls hangup again when it observes a completed call.
    -- This cleanup must not cancel the end announcement already in progress.
    if state~="DIALING" and state~="INCOMING" and state~="ANSWERING" and state~="CONNECTED" then return end
    if preparing_dial then call_generation=call_generation+1 end
    call_voice.cancel();post("HANGUP",call_generation)
end
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
    if call_voice.is_busy() then return false end
    if single_audio.is_ready() then return true end
    if media_busy() then return false end
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
    if cfg.sip.sip_transport ~= "udp" and cfg.sip.sip_transport ~= "tcp" and cfg.sip.sip_transport ~= "tls" then
        log.error("single_app", "sip_transport仅支持udp/tcp/tls") return
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
        -- TLS 证书按需读取：缺失则告警并等待重试（证书可经 OTA 补烧，无需重启即可自愈）
        local cert_ok = true
        if sip_config.sip_transport == "tls" then
            local ca = io.readFile(sip_config.sip_tls_ca_path or "/luadb/sip-ca.pem")
            if not ca then
                log.error("single_app", "TLS 开启但 CA 证书缺失:", sip_config.sip_tls_ca_path)
                set_state("CONFIG_REQUIRED")
                cert_ok = false
            else
                sip_config.sip_tls = { ca_cert = ca }
                log.info("single_app", "TLS 已启用，CA 证书长度", #ca)
            end
        end
        if cert_ok and exsip.init(sip_config) and exsip.start() then
            while true do
                if registered and single_audio.is_ready() and (state == "AUDIO_RECOVERING" or state == "AUDIO_ERROR") then
                    set_state("READY")
                end
                if (state == "READY" or state == "AUDIO_RECOVERING" or state == "AUDIO_ERROR")
                    and not end_pending and not call_voice.is_busy() and not single_audio.is_ready() and not media_busy() then
                    if not recover_audio() then sys.wait(5000) end
                end
                local msg = sys.waitMsg(TASK, nil, 1000)
                if not socket.adapter(socket.LWIP_GP) then break end
                if type(msg) == "table" then
                    local command, value = msg[1], msg[2]
                    if command == "RESTART" then break end
                    if command == "AUTO_ACCEPT" then
                        command = answer.valid(value) and state=="INCOMING" and "ACCEPT" or "STALE"
                    end
                    if command == "RING" and state == "INCOMING" and value==call_generation then
                        log.info("single_app", "呼入振铃", "未接通前持续振铃")
                        local generation=call_generation
                        call_voice.speak("收到来电",function()return state=="INCOMING" and generation==call_generation end)
                        if state=="INCOMING" and generation==call_generation and not call_voice.is_busy() then
                            single_audio.play_ringback_loop()
                        end
                    end
                    if command=="RINGBACK" and value==call_generation and state=="DIALING"
                        and not single_audio.is_running() and not call_voice.is_busy() then
                        log.info("single_app","OUTGOING_RINGBACK","180 Ringing")
                        single_audio.play_ringback_loop()
                    end
                    if command == "ANNOUNCE_END" and value.generation==call_generation then
                        local generation=call_generation
                        for _=1,500 do
                            if generation~=call_generation or not media_busy() then break end
                            sys.wait(20)
                        end
                        if generation==call_generation then
                            if media_busy() then log.error("single_app","END_SPEECH_MEDIA_TIMEOUT",value.reason)
                            else
                                call_voice.speak(call_voice.hangup_text(value.reason),function()
                                    return generation==call_generation and not media_busy()
                                end)
                            end
                            end_pending=false
                        end
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
                                call_generation=call_generation+1
                                local generation=call_generation
                                preparing_dial=true;set_state("DIALING")
                                call_voice.speak("正在拨号",function()
                                    return generation==call_generation and state=="DIALING"
                                end)
                                preparing_dial=false
                                if generation==call_generation and state=="DIALING" and call_voice.prepare() then
                                    if not exsip.dial(value) then
                                        set_state("READY")
                                        call_voice.speak("呼叫失败")
                                    end
                                elseif state=="DIALING" then set_state("READY") end
                            else log.warn("single_app", "请填写config.dial_number") end
                        else log.warn("single_app", "暂不能呼出", state, "audio_ready", single_audio.is_ready()) end
                    elseif command == "ACCEPT" then
                        answer.cancel()
                        local generation=call_generation
                        local released=call_voice.prepare()
                        if released and state == "INCOMING" then single_audio.stop_ringback(true,true) end
                        if state == "INCOMING" and not single_audio.is_ready() then recover_audio() end
                        local elapsed = 0
                        while state == "INCOMING" and not single_audio.is_ready()
                            and elapsed < cfg.audio.ready_timeout_ms do
                            sys.waitUntil("AUDIO_DRV_READY", 100)
                            elapsed = elapsed + 100
                        end
                        if released and generation==call_generation and state == "INCOMING" and single_audio.is_ready() then
                            if exsip.accept() then set_state("ANSWERING") end
                        else log.warn("single_app", "暂不能接听", state, "audio_ready", single_audio.is_ready()) end
                    elseif command == "HANGUP" and value==call_generation then
                        if state == "DIALING" or state == "INCOMING" or state == "ANSWERING" or state == "CONNECTED" then
                            if exsip.hangUp() then set_state("HANGING_UP") end
                        end
                    end
                end
            end
        end
        answer.cancel()
        call_voice.prepare()
        single_audio.stop_ringback(true,true)
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
    return registered, single_audio.is_ready(), registration_epoch
end
return {status=status}
