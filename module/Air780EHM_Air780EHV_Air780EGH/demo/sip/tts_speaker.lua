
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
local audio_drv = require "audio_drv"

local g_tag = "sip_tts_speaker"

--表示当前是否有 TTS 在播放
local is_playing = false
local tts_fallback_timer = nil
--voip 是否正在运行，true 时跳过所有 TTS 播报
local voip_running = false
--前正在播放的 TTS 优先级
local current_priority = 0
--每次 play_tts 调用时递增
local session_id = 0
--当前活跃的 session ID，用于过滤过期回调
local active_session = 0

local function cancel_tts_fallback_timer()
    if tts_fallback_timer then
        sys.timerStop(tts_fallback_timer)
        tts_fallback_timer = nil
    end
end

local function play_end(event, session)
    if event == exaudio.PLAY_DONE then
        if session ~= active_session then
            log.info("tts_speaker", "忽略过期回调，session=", session, "当前=", active_session)
            return
        end
        cancel_tts_fallback_timer()
        log.info("tts_speaker", "播放完成")
        is_playing = false
        current_priority = 0
        active_session = 0
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

-- playDone 事件命名回调：voip 运行中防止 SHUTDOWN 切断通话
local function on_playDone()
    if voip_running then
        log.info("tts_speaker", "voip运行中，TTS完成事件触发，恢复音频")
        local ok, err = pcall(exaudio.pm, audio.RESUME)
        if not ok then
            log.error("tts_speaker", "恢复音频失败:", err)
        end
    end
end

-- taskInit 命名任务函数：通话结束处理
local function task_call_ended(reason)
    stop()
    if voip_running then
        -- voip 启动过（接听后挂断）：需要清理 PCM 残留 + 重置 TTS 队列
        voip_running = false
        sys.wait(200)
        pcall(audio.stop, 0)
        sys.wait(100)
        pcall(exaudio.play_stop, {type = 1})
        sys.wait(500)
        speak_hungup(reason)
    else
        -- voip 没启动过（不接电话直接挂断）：不强制停止 TTS，等它自然完成
        sys.wait(500)
        speak_hungup(reason)
    end
end

-- play_tts: 核心播报函数
-- 每次调用生成唯一 session_id，通过 active_session 过滤过期回调,防止 voip 抢占后旧 TTS 的延迟 DONE 事件错误地重置当前状态。
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
            -- 不主动调用 exaudio.play_stop，让 exaudio.play_start 内部处理打断
            -- 避免 SHUTDOWN/RESUME 频繁切换导致 TTS 引擎状态异常
        else
            log.info("tts_speaker", "正在播放中且优先级不够，忽略", priority, "<=", current_priority)
            return false
        end
    end

    -- session 机制：防止过期回调干扰当前状态
    session_id = session_id + 1
    local my_session = session_id
    active_session = my_session

    local audio_play_param = {
        type = 1,
        content = text,
        cbfnc = function(event)
            play_end(event, my_session)
        end,
        priority = priority
    }

    log.info("tts_speaker", "开始播报:", text)
    -- 第一次尝试
    local ok, result = pcall(exaudio.play_start, audio_play_param)
    -- 失败重试逻辑（最多三次）：
    -- 第一次失败：audio.stop(0) 清理 PCM 残留 + exaudio.play_stop 重置 TTS 队列 + 等待 1秒
    -- 第二次失败：audio_drv.init() 重新初始化 I2S/codec + 等待 2秒
    -- 原因：ivTTS 引擎在 voip 抢占后可能卡在"合成中"状态，需要时间自然停止或硬件重置
    if not ok or not result then
        if not ok then
            log.error("tts_speaker", "exaudio.play_start error:", result)
        else
            log.error("tts_speaker", "exaudio.play_start failed，尝试重建音频后重试")
        end
        pcall(audio.stop, 0)                       -- 清理 audio.start(PCM) 残留状态
        pcall(exaudio.play_stop, {type = 1})
        sys.wait(1000)                             -- 给 TTS 引擎时间自然停止
        ok, result = pcall(exaudio.play_start, audio_play_param)
        if not ok or not result then
            log.error("tts_speaker", "TTS第二次失败，第三次尝试")
            pcall(audio_drv.init)                  -- 仅在长等待后仍失败时才重新初始化
            sys.wait(2000)                         -- 让 init 后的 codec 充分预热
            ok, result = pcall(exaudio.play_start, audio_play_param)
        end
    end
    if ok and result then
        is_playing = true
        current_priority = priority
        cancel_tts_fallback_timer()
        tts_fallback_timer = sys.timerStart(function()
            log.warn("tts_speaker", "TTS回调超时，强制触发play_end")
            play_end(exaudio.PLAY_DONE, my_session)
        end, 8000)
    else
        if not ok then
            log.error("tts_speaker", "exaudio.play_start 最终失败:", result)
        else
            log.error("tts_speaker", "exaudio.play_start 最终失败")
        end
        is_playing = false
        current_priority = 0
        active_session = 0
    end
    return ok and result
end

function speak_sip_ready_with_network(adapter)
    local text = "通话服务已就绪"
    if adapter then
        if adapter == 1 then
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
            -- text = string.format("收到%s来电", digits)
            text = string.format("收到来电")
        end
    else
        log.info("tts_speaker", "收到来电")
        text = "收到来电"
    end
    play_tts(text, 90)
end
function speak_dialing(number)
    local digits = format_digits(number)
    local text
    if digits then
        log.info("tts_speaker", "播报拨号", digits)
        -- text = string.format("正在拨号，号码%s", digits)
        text = string.format("正在拨号")
    else
        log.info("tts_speaker", "播报拨号", number)
        -- text = string.format("正在拨号，号码%s", number)
        text = string.format("正在拨号")
    end
    play_tts(text, 90)
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
        -- Temporarily Unavailable = "对方暂时无法接听",
        -- Busy here = "对方正忙，请稍后再拨",
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

-- stop: 通话建立时调用
-- 让 voip 自己抢占音频通道
function stop()
    if not is_playing then
        return
    end
    log.info("tts_speaker", "通话建立，停止当前播报")
    cancel_tts_fallback_timer()
    -- 不主动调用 exaudio.play_stop，避免 SHUTDOWN 破坏 voip 音频
    -- voip 启动后会自然抢占音频通道，TTS 被中断但不触发 audio.DONE
    is_playing = false
    current_priority = 0
    active_session = 0
end

-- playDone 守护：防止 TTS 完成后 SHUTDOWN 破坏 voip 音频
-- 场景：voip 运行期间，TTS 的 DONE 事件触发 audio_callback 中的 SHUTDOWN，
-- 导致 voip 音频电源被关闭。守护检测到 voip_running=true 时立即 RESUME 恢复。
sys.subscribe("playDone", on_playDone)

local function ready_tts(para)
    log.info(g_tag, "SIP应用就绪，开始第一个TTS播报")
    sys.taskInit(speak_sip_ready_with_network, para)
end

local function incoming_tts()
    local incoming_number = exsip.get_current_call()
     log.info(g_tag, "呼入中，来电号码：", incoming_number)
     sys.taskInit(speak_incoming)
end

local function connected_tts()
    log.info("tts_speaker", "媒体通道开启，抢占音频通道，停止当前播报")
    stop() 
end

local function voip_start_tts()
    voip_running = true
end

local function dial_tts(tag, success, para)
    if success then
        log.info(g_tag, "呼出成功")
        sys.taskInit(speak_dialing, para)
    else
        log.info(g_tag, "呼出失败，原因：", para)
    end
end


-- 区分两种挂断场景：
-- 接听后挂断：voip_running=true,voip 启动过，audio.start(PCM) 有 PCM 残留。
--    必须 audio.stop(0) 清理 PCM + exaudio.play_stop 重置 TTS 队列。
-- 不接电话直接挂断：voip_running=false,voip 从未启动，来电 TTS 还在正常播放。
--    不强制停止 TTS（避免 ivTTS 引擎卡住），等待 500ms 让短文本自然完成。
local function call_ended_tts(reason)
    sys.taskInit(task_call_ended, reason)
end

-- sys.subscribe 说明：
-- SIP_APP_MAIN_READY:        sip_app_main.lua 中 SIP 初始化完成后发布
-- SIP_APP_MAIN_INCOMING:     sip_app_main.lua 中 MSG_INCOMING 时发布（收到来电）
-- SIP_APP_MAIN_CONNECTED:    sip_app_main.lua 中 MSG_CONNECTED 时发布（用户接听）
-- SIP_APP_MAIN_VOIP_STARTED: sip_app_main.lua / sip_callback 中 voip started 时发布
-- SIP_APP_MAIN_DISCONNECTED: sip_app_main.lua 中 MSG_DISCONNECTED 时发布（通话结束）
-- SIP_APP_MAIN_DIAL_RSP:     sip_app_main.lua 中 MSG_DIAL 时发布（拨号结果）
sys.subscribe("SIP_APP_MAIN_READY", ready_tts)
sys.subscribe("SIP_APP_MAIN_INCOMING", incoming_tts)
sys.subscribe("SIP_APP_MAIN_CONNECTED", connected_tts)
sys.subscribe("SIP_APP_MAIN_VOIP_STARTED", voip_start_tts)
sys.subscribe("SIP_APP_MAIN_DISCONNECTED", call_ended_tts)
sys.subscribe("SIP_APP_MAIN_DIAL_RSP", dial_tts)


