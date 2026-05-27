
--[[
@module  tts_speaker
@summary SIP应用的TTS播报模块
@version 1.0
@date    2026.05.22
@author  蒋骞
@usage
本文件为SIP应用的TTS播报模块，核心业务逻辑为：负责SIP应用中与TTS相关的播报功能，包括开机播报、来电播报、拨号播报、挂断播报等。通过监听SIP应用的状态变化和事件，触发相应的TTS播报，并管理TTS播放的优先级和状态，确保在通话过程中合理控制TTS播报，提升用户体验。
@description
1、本文件依赖的模块：
    1）exaudio：音频处理模块，负责TTS音频的播放和控制；
    2）exsip：SIP协议栈模块，提供SIP信令处理；

2、本文件的主要功能：
    1）开机播报：在SIP应用启动时，播放开机TTS；
    2）来电播报：在收到SIP来电时，播放来电TTS；
    3）拨号播报：在拨号过程中，播放拨号TTS；
    4）挂断播报：在挂断通话时，播放挂断TTS。
]]--

local exaudio = require "exaudio"
local exsip = require "exsip"

local g_tag = "sip_app_tts_speaker"

--表示当前是否有 TTS 在播放
local is_playing = false
--voip 是否正在运行，true 时跳过所有 TTS 播报
local voip_running = false
--前正在播放的 TTS 优先级
local current_priority = 0

local TTS_TASK_NAME = "tts_speaker_task"


local function play_end(event)
    log.info("tts_speaker", "播报事件回调，事件类型:", event)
    if event == exaudio.PLAY_DONE then
        log.info("tts_speaker", "播放完成")
        is_playing = false
        current_priority = 0
    end
end

local function format_digits(number)
    if not number then
        return nil
    end
    local digits = tostring(number):gsub("%D", "")
    if digits == "" then
        return nil
    end
    local spaced = digits:gsub("(%d)", "%1 ")
    return spaced:gsub("%s+$", "")
end

-- play_tts: 核心播报函数
-- 优先级数值越高越优先。挂断播报(100) > 来电/拨号(90) > 就绪(50)。
local function play_tts(text, priority)
    priority = priority or 0
    
    if voip_running then
        log.info("tts_speaker", "voip运行中，跳过TTS播报")
        return false
    end

    if is_playing then
        if priority > current_priority then
            log.info("tts_speaker", "高优先级打断当前播报", priority, ">", current_priority)
        else
            log.info("tts_speaker", "正在播放中且优先级不够，忽略", priority, "<=", current_priority)
            return false
        end
    end

    local audio_play_param = {
        type = 1,
        content = text,
        cbfnc = function(event)
            play_end(event)
        end,
        priority = priority
    }

    log.info("tts_speaker", "开始播报:", text)
    local ok, result = pcall(exaudio.play_start, audio_play_param)
    if ok and result then
        is_playing = true
        current_priority = priority
    else
        if not ok then
            log.error("tts_speaker", "exaudio.play_start 最终失败:", result)
        else
            log.error("tts_speaker", "exaudio.play_start 最终失败")
        end
        is_playing = false
        current_priority = 0
    end
    return ok and result
end

function speak_sip_ready_with_network(adapter)
    local text = "通话服务已就绪"
    if adapter then
        if adapter == socket.LWIP_STA then
            local ok, info = pcall(wlan.getInfo)
            local rssi = ok and info and info.rssi
            if type(rssi) == "number" then
                text = text .. "，当前已连接WiFi，信号强度" .. rssi .. "dBm"
                if rssi < -80 then
                    text = text .. "，信号较差"
                elseif rssi < -60 then
                    text = text .. "，信号一般"
                else
                    text = text .. "，信号良好"
                end
            else
                text = text .. "，当前已连接WiFi"
            end
        elseif adapter == socket.LWIP_GP then
            local ok, csq = pcall(mobile.csq)
            if ok and type(csq) == "number" then
                text = text .. "，当前已连接4G，信号强度为" .. csq
                if csq < 15 then
                    text = text .. "，信号较差"
                elseif csq < 25 then
                    text = text .. "，信号一般"
                else
                    text = text .. "，信号良好"
                end
            else
                text = text .. "，当前已连接4G"
            end
        else
            text = text .. "，当前已连接Ethernet"
        end
    end
    log.info("tts_speaker", "初始化播报:", text)
    play_tts(text, 50)
end

function speak_incoming()
    local text
    local current_call = exsip.get_current_call()
    if current_call then
        local digits = format_digits(current_call)
        if digits then
            log.info("tts_speaker", "收到来电，号码", digits)
            text = string.format("收到%s来电", digits)
        end
    else
        log.info("tts_speaker", "收到来电")
        text = "收到来电"
    end
    play_tts(text, 90)
end

function speak_accept()
    log.info("tts_speaker", "接听电话前，停止当前播报")
    is_playing = false
    current_priority = 0
end

function speak_dialing(number)
    local digits = format_digits(number)
    local text
    if digits then
        log.info("tts_speaker", "播报拨号", digits)
        text = string.format("正在拨号，号码%s", digits)
    else
        log.info("tts_speaker", "播报拨号", number)
        text = string.format("正在拨号，号码%s", number)
    end
    play_tts(text, 90)
end

function task_call_ended(reason)
    is_playing = false
    current_priority = 0
    if voip_running then
        voip_running = false
    end
    speak_hungup(reason)
end

function speak_hungup(reason)
    local reason_map = {
        peer_hangup = "对方挂断",
        local_hangup = "我方主动挂断",
        peer_cancel = "对方取消来电",
        call_failed = "呼叫失败",
        socket_closed = "网络断开",
        timeout = "呼叫超时",
        local_reject = "我方已拒接",
    }
    local text
    if reason and reason ~= "" then
        local mapped_reason = reason_map[reason]
        if mapped_reason then
            text = mapped_reason
        else
            text = "对方暂时无法接听,请稍后再拨"
        end
        log.info("tts_speaker", "播报挂断，原因", reason, "->", text)
    else
        log.info("tts_speaker", "播报挂断")
        text = "已挂断"
    end
    play_tts(text, 100)
end

-- 集中式 TTS Task
local function tts_task_func()
    while true do
        local msg = sys.waitMsg(TTS_TASK_NAME)
        if type(msg) ~= "table" then
            log.warn("tts_speaker", "收到非消息数据，忽略:", msg)
        else
            local tts_msg = msg[1]
            if tts_msg == "TTS_READY" then
                speak_sip_ready_with_network(msg[2])
            elseif tts_msg == "TTS_INCOMING" then
                speak_incoming()
            elseif tts_msg == "TTS_ACCEPT" then
                speak_accept()
            elseif tts_msg == "TTS_DIAL" then
                speak_dialing(msg[2])
            elseif tts_msg == "TTS_ENDED" then
                task_call_ended(msg[2])
            end
        end
    end
end


local function ready_tts(para)
    log.info(g_tag, "SIP应用就绪，开始第一个TTS播报")
    sys.sendMsg(TTS_TASK_NAME, "TTS_READY", para)
end

local function incoming_tts()
    local incoming_number = exsip.get_current_call()
     log.info(g_tag, "呼入中，来电号码：", incoming_number)
     sys.sendMsg(TTS_TASK_NAME, "TTS_INCOMING")
end
    
local function accept_tts()
    log.info(g_tag, "接听电话前")
    sys.sendMsg(TTS_TASK_NAME, "TTS_ACCEPT")
end

local function voip_start_tts()
    voip_running = true
end

local function dial_tts(tag, para)
    log.info(g_tag, "收到拨号请求，准备播报拨号信息")
    sys.sendMsg(TTS_TASK_NAME, "TTS_DIAL", para)
end

local function call_ended_tts(reason)
    sys.sendMsg(TTS_TASK_NAME, "TTS_ENDED", reason)
end
    
    
sys.taskInitEx(tts_task_func, TTS_TASK_NAME)

-- sys.subscribe 说明：
-- SIP_APP_MAIN_READY:        sip_app_main.lua 中 SIP 初始化完成后发布
-- SIP_APP_MAIN_INCOMING:     sip_app_main.lua 中 MSG_INCOMING 时发布（收到来电）
-- SIP_APP_MAIN_VOIP_STARTED: sip_app_main.lua / sip_callback 中 voip started 时发布
-- SIP_APP_MAIN_DISCONNECTED: sip_app_main.lua 中 MSG_DISCONNECTED 时发布（通话结束）
-- SIP_APP_MAIN_DIAL_RSP:     sip_app_main.lua 中 MSG_DIAL 时发布（拨号结果）
    
sys.subscribe("SIP_APP_MAIN_READY", ready_tts)
sys.subscribe("SIP_APP_MAIN_INCOMING", incoming_tts)
sys.subscribe("SIP_APP_MAIN_ACCEPT_REQ", accept_tts)
sys.subscribe("SIP_APP_MAIN_VOIP_STARTED", voip_start_tts)
sys.subscribe("SIP_APP_MAIN_DIAL_REQ", dial_tts)
sys.subscribe("SIP_APP_MAIN_DISCONNECTED", call_ended_tts)
    