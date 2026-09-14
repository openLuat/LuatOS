
--[[
@module  tts_speaker
@summary SIP应用的TTS播报模块
@version 1.1
@date    2026.07.14
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
    3）来电铃声：TTS 播报结束后循环播放铃声文件，直到接听或挂断；
    4）拨号播报：在拨号过程中，播放拨号TTS；
    5）挂断播报：在挂断通话时，播放挂断TTS。
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

-- 铃声相关状态
local RINGTONE_PATH = "/luadb/test_16k.mp3"
local RING_TASK_NAME = "ringtone_task"
local ringtone_needed = false       -- 是否需要启动铃声
local ringtone_stop_flag = false    -- 通知铃声任务退出循环
local ringtone_playing = false      -- 铃声任务是否正在循环播放
local pending_hangup_reason = nil   -- 等待 VoIP 完全停止后播报的挂断原因
local active_tts_token = 0          -- 忽略被打断播放的迟到回调
local pending_tts = nil             -- 等待当前 TTS 真正停止后再启动的播报
local play_end

local function start_tts_now(text, priority)
    if voip_running then
        log.info("tts_speaker", "voip运行中，跳过TTS播报")
        return false
    end

    active_tts_token = active_tts_token + 1
    local token = active_tts_token
    local audio_play_param = {
        type = 1,
        content = text,
        cbfnc = function(event)
            if token ~= active_tts_token then
                return
            end
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
        log.error("tts_speaker", "exaudio.play_start 最终失败:", result)
        is_playing = false
        current_priority = 0
    end
    return ok and result
end

local function start_pending_tts()
    if voip_running then
        pending_tts = nil
        return
    end
    if not pending_tts then
        return
    end
    local item = pending_tts
    pending_tts = nil
    start_tts_now(item.text, item.priority)
end

-- exaudio.play_start() 内部会等待事件，必须由 TTS task 协程执行；
-- timer/播放回调只能投递消息，不能直接调用 start_pending_tts()。
local function schedule_pending_tts(delay, token)
    sys.timerStart(function()
        sys.sendMsg(TTS_TASK_NAME, "TTS_START_PENDING", token)
    end, delay)
end

play_end = function(event)
    log.info("tts_speaker", "播报事件回调，事件类型:", event)
    if event == exaudio.PLAY_DONE then
        log.info("tts_speaker", "播放完成")
        is_playing = false
        current_priority = 0
        if pending_tts then
            -- 旧播放资源释放后，再由 TTS task 协程启动下一段播报。
            schedule_pending_tts(20, active_tts_token)
            return
        end
        -- TTS 播报完成后，如果仍需要铃声且铃声任务尚未启动，则触发铃声任务
        if ringtone_needed and not ringtone_playing then
            sys.publish("RING_START")
        end
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
            -- 逻辑状态不能代替底层停止：先停止当前 TTS，等回调后再启动新请求。
            pending_tts = {text = text, priority = priority}
            local token = active_tts_token
            local ok, err = pcall(exaudio.play_stop, {type = 1})
            if not ok then
                log.error("tts_speaker", "停止当前TTS异常:", err)
            end
            -- 旧 audio 框架停止播放时不保证一定回调 PLAY_DONE，超时仅作兜底。
            sys.timerStart(function()
                if pending_tts and token == active_tts_token then
                    sys.sendMsg(TTS_TASK_NAME, "TTS_START_PENDING", token)
                end
            end, 100)
            return true
        else
            log.info("tts_speaker", "正在播放中且优先级不够，忽略", priority, "<=", current_priority)
            return false
        end
    end

    return start_tts_now(text, priority)
end

function speak_sip_ready_with_network(adapter)
    -- 服务就绪时不再需要铃声
    ringtone_needed = false
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

function speak_dialing(number)
    -- 拨号时取消可能残留的铃声需求
    ringtone_needed = false
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
    if voip_running then
        -- SIP 信令结束早于 VoIP task 的 I2S/DMA 释放；不能在这里启动 TTS。
        pending_hangup_reason = reason
        log.info("tts_speaker", "VoIP停止中，延后播报挂断提示")
        return
    end
    speak_hungup(reason)
end

local function voip_stopped_tts()
    voip_running = false
    if pending_hangup_reason then
        local reason = pending_hangup_reason
        pending_hangup_reason = nil
        log.info("tts_speaker", "VoIP已停止，开始播报挂断提示")
        sys.sendMsg(TTS_TASK_NAME, "TTS_ENDED", reason)
    end
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

-- 铃声任务：循环播放铃声文件，直到收到 RING_STOP
local function ringtone_task_func()
    while true do
        -- 等待需要播放铃声的事件
        sys.waitUntil("RING_START")
        if not ringtone_needed then
            log.info("ringtone_task", "RING_START 收到，但已不需要铃声，跳过")
        else
            ringtone_playing = true
            ringtone_stop_flag = false
            log.info("ringtone_task", "开始循环播放铃声")
            while not ringtone_stop_flag do
                local track_done = false
                local ok, result = pcall(exaudio.play_start, {
                    type = 0,
                    content = RINGTONE_PATH,
                    priority = 80,
                    cbfnc = function(event)
                        -- 只有真正收到 PLAY_DONE 才表示本段铃声播放结束
                        if event == exaudio.PLAY_DONE then
                            track_done = true
                        end
                    end
                })
                if not ok then
                    log.error("ringtone_task", "exaudio.play_start 异常:", result)
                    break
                end
                if not result then
                    log.error("ringtone_task", "exaudio.play_start 返回失败")
                    break
                end
                -- 等待当前铃声片段真正播放完成，或收到停止指令
                while not track_done and not ringtone_stop_flag do
                    sys.waitUntil({"playDone", "RING_STOP"}, 1000)
                end
                if ringtone_stop_flag then
                    break
                end
            end
            ringtone_playing = false
            log.info("ringtone_task", "铃声循环结束")
        end
    end
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
            elseif tts_msg == "TTS_DIAL" then
                speak_dialing(msg[2])
            elseif tts_msg == "TTS_ENDED" then
                task_call_ended(msg[2])
            elseif tts_msg == "TTS_START_PENDING" then
                if msg[2] == active_tts_token then
                    is_playing = false
                    current_priority = 0
                    start_pending_tts()
                end
            end
        end
    end
end

local function stop_ringtone()
    if ringtone_needed or ringtone_playing then
        log.info("tts_speaker", "停止铃声")
        local was_ringtone_playing = ringtone_playing
        ringtone_needed = false
        ringtone_stop_flag = true
        sys.publish("RING_STOP")
        -- ringtone_needed 仅表示“稍后需要响铃”。来电 TTS 播放期间它也是 true，
        -- 此时不能用 type=0 的通用 stop 打断 TTS；由 play_tts(type=1) 串行切换。
        if was_ringtone_playing then
            local ok, err = pcall(exaudio.play_stop, {type = 0})
            if not ok then
                log.error("tts_speaker", "exaudio.play_stop 异常:", err)
            end
        end
    end
end

local function ready_tts(para)
    log.info(g_tag, "SIP应用就绪，开始第一个TTS播报")
    ringtone_needed = false
    sys.sendMsg(TTS_TASK_NAME, "TTS_READY", para)
end

local function incoming_tts()
    local incoming_number = exsip.get_current_call()
    log.info(g_tag, "呼入中，来电号码：", incoming_number)
    ringtone_needed = true
    sys.sendMsg(TTS_TASK_NAME, "TTS_INCOMING")
end

local function accept_tts()
    log.info(g_tag, "接听电话前")
    -- 先作废已排队或正在回调的 TTS，避免停止铃声后迟到回调再次启动播放。
    pending_tts = nil
    active_tts_token = active_tts_token + 1
    if is_playing then
        local ok, err = pcall(exaudio.play_stop, {type = 1})
        if not ok then
            log.error(g_tag, "停止当前TTS异常:", err)
        end
    end
    is_playing = false
    current_priority = 0
    stop_ringtone()
    -- audio.play() 的停止动作是异步的；留出一个确定的 DMA 释放窗口后再让主状态机应答。
    sys.timerStart(function()
        sys.publish("SIP_APP_TTS_ACCEPT_AUDIO_READY")
    end, 120)
end

local function voip_start_tts()
    voip_running = true
    pending_hangup_reason = nil
    stop_ringtone()
end

local function dial_tts(tag, para)
    log.info(g_tag, "收到拨号请求，准备播报拨号信息")
    stop_ringtone()
    sys.sendMsg(TTS_TASK_NAME, "TTS_DIAL", para)
end

local function call_ended_tts(reason)
    stop_ringtone()
    sys.sendMsg(TTS_TASK_NAME, "TTS_ENDED", reason)
end


sys.taskInitEx(tts_task_func, TTS_TASK_NAME)
sys.taskInitEx(ringtone_task_func, RING_TASK_NAME)

-- sys.subscribe 说明：
-- SIP_APP_MAIN_READY:        sip_app_main.lua 中 SIP 初始化完成后发布
-- SIP_APP_MAIN_INCOMING:     sip_app_main.lua 中 MSG_INCOMING 时发布（收到来电）
-- SIP_APP_MAIN_ACCEPT_AUDIO_PREPARE: 接听前停止本地音频后发布
-- SIP_APP_MAIN_VOIP_STARTED: sip_app_main.lua / sip_callback 中 voip started 时发布
-- SIP_APP_MAIN_VOIP_STOPPED: sip_app_main.lua / sip_callback 中 voip stopped 时发布
-- SIP_APP_MAIN_DISCONNECTED: sip_app_main.lua 中 MSG_DISCONNECTED 时发布（通话结束）
-- SIP_APP_MAIN_DIAL_RSP:     sip_app_main.lua 中 MSG_DIAL 时发布（拨号结果）

sys.subscribe("SIP_APP_MAIN_READY", ready_tts)
sys.subscribe("SIP_APP_MAIN_INCOMING", incoming_tts)
sys.subscribe("SIP_APP_MAIN_ACCEPT_AUDIO_PREPARE", accept_tts)
sys.subscribe("SIP_APP_MAIN_VOIP_STARTED", voip_start_tts)
sys.subscribe("SIP_APP_MAIN_VOIP_STOPPED", voip_stopped_tts)
sys.subscribe("SIP_APP_MAIN_DIAL_REQ", dial_tts)
sys.subscribe("SIP_APP_MAIN_DISCONNECTED", call_ended_tts)
