--[[
@module  sip_talk
@summary SIP/VoIP 对讲模块（基于 exsip 替换 extalk）
@version 1.0
@date    2026.05.21
@usage
替换原有 AirTalk(extalk) 对讲，使用标准 SIP/VoIP 协议。
状态机: IDLE → INITING → READY → DIALING/INCOMING → CONNECTED → READY
]]

local sip_talk = {}
local exsip = require("exsip")
local exaudio = require("exaudio")
local config = require("config")
local audio_player = require("player")

local TASK_NAME = "sip_talk_task"

-- 状态机
local S = {
    IDLE = "STATE_IDLE",
    INITING = "STATE_INITING",
    READY = "STATE_READY",
    DIALING = "STATE_DIALING",
    INCOMING = "STATE_INCOMING",
    CONNECTED = "STATE_CONNECTED",
}
local g_state = S.IDLE
local g_audio_inited = false
local g_initialized = false   -- 防重入：sip_talk.init() 只需调用一次

-- SIP 回调
local function sip_callback(event, arg1, arg2)
    log.info("sip_talk", "SIP事件:", event, arg1)

    if event == "register" then
        if arg1 == "ok" then
            log.info("sip_talk", "SIP注册成功")
        elseif arg1 == "challenge" then
            log.info("sip_talk", "SIP认证挑战")
        else
            log.error("sip_talk", "SIP注册失败:", arg1)
            sys.sendMsg(TASK_NAME, "sip", "MSG_ERROR")
        end
    elseif event == "ready" then
        sys.sendMsg(TASK_NAME, "sip", "MSG_READY")
    elseif event == "call" then
        local sub = arg1
        local data = arg2
        if sub == "incoming" then
            log.info("sip_talk", "来电:", data and data.from)
            sys.sendMsg(TASK_NAME, "sip", "MSG_INCOMING", data)
        elseif sub == "ringing" then
            log.info("sip_talk", "对方响铃中")
        elseif sub == "connected" or sub == "established" then
            sys.sendMsg(TASK_NAME, "sip", "MSG_CONNECTED")
        elseif sub == "ended" then
            log.info("sip_talk", "通话结束, 原因:", data and data.reason)
            sys.sendMsg(TASK_NAME, "sip", "MSG_DISCONNECTED")
        end
    elseif event == "voip" then
        if arg1 == "state" then
            log.info("sip_talk", "VoIP状态:", arg2)
        end
    elseif event == "error" then
        log.error("sip_talk", "SIP错误:", arg1)
        sys.sendMsg(TASK_NAME, "sip", "MSG_ERROR")
    elseif event == "lifecycle" then
        if arg1 == "online" then
            log.info("sip_talk", "SIP在线, IP:", arg2 and arg2.local_ip)
        else
            sys.sendMsg(TASK_NAME, "sip", "MSG_ERROR")
        end
    end
end

-- 初始化 SIP 服务
local function start_sip()
    if not exsip then return false end
    log.info("sip_talk", "初始化SIP服务")

    if not g_audio_inited then
        if not audio_player.open() then
            log.error("sip_talk", "音频驱动初始化失败")
            return false
        end
        g_audio_inited = true
    end

    local sip_cfg = {
        sip_server_addr = config.SIP_CONFIG.SIP_SERVER_ADDR,
        sip_server_port = config.SIP_CONFIG.SIP_SERVER_PORT,
        sip_domain = config.SIP_CONFIG.SIP_DOMAIN,
        sip_username = mobile.imei(),
        sip_password = config.SIP_CONFIG.SIP_PASSWORD,
        sip_transport = exsip.TRANSPORT_UDP,
        auto_answer = config.SIP_CONFIG.AUTO_ANSWER,
    }

    if not exsip.init(sip_cfg) then
        log.error("sip_talk", "exsip.init 失败")
        return false
    end
    if not exsip.start() then
        log.error("sip_talk", "exsip.start 失败")
        return false
    end
    return true
end

local function stop_sip()
    if exsip then exsip.stop() end
    if exaudio then exaudio.pm(audio.SHUTDOWN) end
    g_audio_inited = false
end

-- 仅关闭 VoIP 音频引擎（通话结束时调用，不关闭 SIP 服务）
local function stop_voip_audio()
    if exaudio then
        exaudio.pm(audio.SHUTDOWN)
    end
    g_audio_inited = false
end

-- SIP 主任务
local function sip_main_task()
    local msg, tag, event, para

    while true do
        g_state = S.INITING

        -- 等待网络就绪
        while not socket.adapter(socket.dft()) do
            log.warn("sip_talk", "wait IP_READY")
            sys.waitUntil("IP_READY", 1000)
        end
        log.info("sip_talk", "网络就绪")

        sys.cleanMsg(TASK_NAME)

        if not start_sip() then
            log.error("sip_talk", "start_sip 失败")
            goto EXCEPTION_PROC
        end

        while true do
            msg = sys.waitMsg(TASK_NAME)
            tag, event, para = msg[1], msg[2], msg[3]

            log.info("sip_talk", g_state, event)

            if event == "MSG_STOP" then
                g_state = S.IDLE
                stop_sip()
                g_initialized = false
                return

            elseif event == "MSG_DIAL" then
                if g_state == S.READY then
                    audio_player.set_keep_open(true)
                    if exsip.dial(para) then
                        g_state = S.DIALING
                    else
                        audio_player.set_keep_open(false)
                        sys.publish("SIP_CALL_RESULT", false, "dial_failed")
                    end
                end

            elseif event == "MSG_READY" then
                if g_state == S.INITING then
                    g_state = S.READY
                    sys.publish("SIP_READY")
                end

            elseif event == "MSG_INCOMING" then
                if g_state == S.READY then
                    audio_player.set_keep_open(true)
                    g_state = S.INCOMING
                    sys.publish("SIP_INCOMING", para)
                end

            elseif event == "MSG_ACCEPT" then
                if g_state == S.INCOMING then
                    exsip.accept()
                end

            elseif event == "MSG_HANGUP" then
                if g_state == S.DIALING or g_state == S.INCOMING or g_state == S.CONNECTED then
                    audio_player.set_keep_open(false)
                    exsip.hangUp()
                end

            elseif event == "MSG_CONNECTED" then
                if g_state == S.DIALING or g_state == S.INCOMING then
                    g_state = S.CONNECTED
                    sys.publish("SIP_CONNECTED")
                end

            elseif event == "MSG_DISCONNECTED" then
                audio_player.set_keep_open(false)
                g_state = S.READY
                stop_voip_audio()
                sys.publish("SIP_DISCONNECTED")

            elseif event == "MSG_ERROR" then
                audio_player.set_keep_open(false)
                break
            end
        end

        ::EXCEPTION_PROC::
        stop_sip()
        sys.cleanMsg(TASK_NAME)
        sys.publish("SIP_LOSE")
        sys.wait(5000)
    end
end

-- 初始化
function sip_talk.init()
    if not exsip then
        log.warn("sip_talk", "exsip不可用，SIP功能禁用")
        return
    end
    if g_initialized then
        log.info("sip_talk", "已初始化，跳过")
        return
    end
    log.info("sip_talk", "初始化对讲模块")
    exsip.on(sip_callback)
    sys.taskInitEx(sip_main_task, TASK_NAME)
    g_initialized = true
end

-- 主动呼叫
function sip_talk.call(target_number)
    sys.sendMsg(TASK_NAME, "user", "MSG_DIAL", target_number)
end

-- 接听来电
function sip_talk.accept()
    sys.sendMsg(TASK_NAME, "user", "MSG_ACCEPT")
end

-- 挂断
function sip_talk.hangup()
    sys.sendMsg(TASK_NAME, "user", "MSG_HANGUP")
end

-- 停止服务
function sip_talk.stop()
    sys.sendMsg(TASK_NAME, "user", "MSG_STOP")
end

-- 是否就绪
function sip_talk.is_ready()
    return g_state == S.READY
end

-- 确保音频已初始化（通话结束后音频会被关闭，下次呼叫前需重新打开）
function sip_talk.ensure_audio()
    audio_player.cancel_close_timer()
    if not g_audio_inited or not audio_player.is_powered() then
        log.info("sip_talk", "重新初始化音频")
        audio_player.open()
        g_audio_inited = true
    end
end

-- 是否通话中
function sip_talk.is_active()
    return g_state == S.DIALING or g_state == S.INCOMING or g_state == S.CONNECTED
end

return sip_talk
