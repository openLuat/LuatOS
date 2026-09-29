--[[
@module  sip_app_main
@summary SIP 注册/呼出/接听/挂断状态机，媒体由 audio_drv 的 exaudio 适配层提供
@version 1.0
@date    2026.09.23
@author  王世豪
@usage
本文件为 SIP 协议栈业务封装模块，核心业务逻辑为：
1、封装 exsip 的注册、来电、接听、挂断、媒体事件，通过 sys.publish("SIP_APP_STATE") 广播状态供 AirCloud 上报；
2、以独立任务 sip_app_main_task + 消息队列驱动（DIAL/ACCEPT/HANGUP/PRIMARY/RESTART），
   由 app_main 经 SIP_APP_MAIN_*_REQ 订阅触发；
3、SOS(PRIMARY) 智能分流：来电中 → 接听、通话中 → 忽略(或抢占重呼)、空闲 → 向 config.dial_number 呼出；
4、音频未就绪/异常时在业务任务内 recover_audio 重初始化，避免在 SIP/串口回调里阻塞等待；
5、register/lifecycle/media/voip/error 异常统一 post("RESTART") 重建 SIP + 音频会话；
本文件对外提供状态广播与消息接口，业务编排在 app_main.lua；
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
            log.info("sip_app", "接通电话")
            post("RING")   -- 来电后持续振铃, 由按键/接听请求触发 ACCEPT
        elseif action == "connected" then
            set_state("CONNECTED")
        elseif action == "ended" then
            audio_drv.stop_ringback(true)   -- 先停循环振铃(不复位, 避免复位吞掉挂断提示音)
            -- skip_recover=true: 停桥接但先不恢复MIC(避免复位吞掉挂断提示音), 播完由提示音队列复位恢复
            audio_drv.stop(true)
            set_state(registered and (audio_drv.is_ready() and "READY" or "AUDIO_RECOVERING") or "OFFLINE")
            log.info("sip_app", "对方已挂断", "播放挂断提示音")
            audio_drv.play_hangup()
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
                    if command == "RING" then
                        log.info("sip_app", "呼入振铃", "未接通前持续振铃")
                        audio_drv.play_ringback_loop()
                    end
                    if command == "PRIMARY" then
                        value = cfg.dial_number
                        if state == "INCOMING" then
                            -- 来电中：接听。
                            -- 呼叫目标就是 IMEI+1，与来电方是同一人，所以"SOS 既能接听又能呼叫"
                            -- 对用户而言结果完全一致，不需要用户自己判断当前是来电还是空闲。
                            command = "ACCEPT"
                        elseif state == "CONNECTED" or state == "ANSWERING"
                            or state == "DIALING" or state == "HANGING_UP" then
                            -- 通话中：默认忽略。单号码下抢占重呼 = 挂掉当前通话再打给同一个人，
                            -- 只有副作用；等做多号码轮拨时把 config.keys.sos_preempt_in_call 改 true。
                            if cfg.keys and cfg.keys.sos_preempt_in_call then
                                log.warn("sip_app", "SOS 抢占：先挂断当前会话", state)
                                exsip.hangUp()
                                audio_drv.stop()
                                -- 等 callback 把状态推回 READY（call ended 分支），最多等 5 秒
                                local elapsed = 0
                                while state ~= "READY" and elapsed < 5000 do
                                    sys.wait(100)
                                    elapsed = elapsed + 100
                                end
                                log.info("sip_app", "SOS 抢占：挂断完成，状态", state)
                                command = "DIAL"
                            else
                                log.warn("sip_app", "通话中忽略 SOS（抢占未启用）", state)
                                command = nil
                            end
                        else
                            -- 空闲态（READY / OFFLINE 等）：呼出
                            command = "DIAL"
                        end
                        log.info("sip_app", "SOS 分流", "状态", state, "转为", tostring(command))
                    end
                    if command == "DIAL" then
                        if registered and (state == "READY" or state == "AUDIO_RECOVERING" or state == "AUDIO_ERROR") then
                            recover_audio()
                        end
                        if state == "READY" and registered and audio_drv.is_ready()
                            and not exsip.is_voip_running() then
                            if type(value) == "string" and value ~= "" then
                                if exsip.dial(value) then
                                    set_state("DIALING")
                                else
                                    log.warn("sip_app", "exsip.dial 返回 false", value)
                                end
                            else log.warn("sip_app", "请填写config.dial_number") end
                        else log.warn("sip_app", "暂不能呼出", state, "audio_ready", audio_drv.is_ready()) end
                    elseif command == "ACCEPT" then
                        if state == "INCOMING" then audio_drv.stop_ringback() end   -- 先停振铃再接听
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
