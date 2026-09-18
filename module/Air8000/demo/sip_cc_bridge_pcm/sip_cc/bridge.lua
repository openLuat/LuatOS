--[[
@module  bridge
@summary SIP 与 CC 的纯 PCM 桥接协调器
@version 1.1
@date    2026.09.18
@usage
业务通话、等待来电、旧通话清理和呼叫间隔分别管理。
只经带身份的消息控制 SIP/CC；直接查询模块的停止确认和原生资源状态。
]]

local config = require "config"
local cc_main = require "cc_main"
local pcm_sip = require "pcm_sip"
local bridge = {}

local WAIT_MS, GAP_MS, POLL_MS, RECOVERY_MS = 3000, 500, 100, 3000
local current, pending, cleanup
local next_owner = 0
local cooldown_until
local wake_timer
local recovering = false
local recovery_timer
local rebooted = false
local drive

local function now_ms()
    local high, low = mcu.ticks2(1)
    return high * 1000000.0 + low
end

local function logi(...)
    log.info("bridge", ...)
end

local function new_call(direction)
    next_owner = next_owner + 1
    return {
        owner = next_owner, direction = direction,
        sip_state = "sip_idle", cc_state = "cc_idle",
        sip_done = true, cc_done = true,
    }
end

local function matches_sip(call, call_id, generation, owner)
    if not call or (call_id == nil and generation == nil and owner == nil) then return false end
    if owner ~= nil and owner ~= call.owner then return false end
    if generation ~= nil and call.sip_generation ~= nil and generation ~= call.sip_generation then return false end
    if call_id ~= nil and call.call_id ~= nil and call_id ~= call.call_id then return false end
    -- 外呼在首次协议回调前没有 Call-ID，必须通过本地 owner 绑定。
    if call.sip_generation == nil and call.call_id == nil and owner ~= call.owner then return false end
    return true
end

local function find_sip(call_id, generation, owner)
    if matches_sip(current, call_id, generation, owner) then return current end
    if matches_sip(pending, call_id, generation, owner) then return pending end
    if matches_sip(cleanup, call_id, generation, owner) then return cleanup end
end

local function bind_sip(call, call_id, generation)
    call.call_id = call.call_id or call_id
    call.sip_generation = call.sip_generation or generation
end

local function matches_cc(call, generation, owner)
    if not call or not call.owns_cc then return false end
    if owner ~= nil and owner ~= call.owner then return false end
    if generation ~= nil and call.cc_generation ~= nil and generation ~= call.cc_generation then return false end
    return owner == call.owner or (generation ~= nil and generation == call.cc_generation)
end

local function find_cc(generation, owner)
    if matches_cc(current, generation, owner) then return current end
    if matches_cc(pending, generation, owner) then return pending end
    if matches_cc(cleanup, generation, owner) then return cleanup end
end

local function sip_request(name, call, ...)
    local owner = call.direction == "incoming" and call.owner or nil
    if name == "SIP_FAIL_REQ" then
        local code, reason = ...
        sys.publish(name, code, reason, call.call_id, call.sip_generation, owner)
    else
        sys.publish(name, call.call_id, call.sip_generation, owner)
    end
end

local function stop_sip(call, code, reason)
    if call.sip_done or call.sip_stop_requested then return end
    call.sip_stop_requested = true
    call.sip_state = "sip_disconnecting"
    if code then
        sip_request("SIP_FAIL_REQ", call, code, reason)
    else
        sip_request("SIP_HANGUP_REQ", call)
    end
end

local function stop_cc(call)
    if not call.owns_cc or call.cc_done or call.cc_stop_requested then return end
    call.cc_stop_requested = true
    call.cc_state = "cc_disconnecting"
    sys.publish("CC_HANGUP_REQ", call.cc_generation, call.owner)
end

local function begin_cleanup(call)
    if call.ending then return end
    call.ending = true
    if current == call then current = nil end
    if pending == call then pending = nil end
    -- 活动通话只会在上一通清理和间隔结束后建立，不会覆盖旧清理记录。
    cleanup = call
    cooldown_until = nil
    stop_sip(call)
    stop_cc(call)
    drive()
end

local function pcm_released()
    if cc_main.is_media_idle() then return true end
    -- 手机新来电由 C 层先创建自己的 session。它的 active=1 不是旧资源；
    -- 只允许这个尚未接听的 session，其他队列和 SDK 状态仍必须全部归零。
    local call = pending
    if not call or call.direction ~= "incoming" or call.cc_done or
        cc_main.get_state() ~= "cc_ringing" or
        cc_main.get_generation() ~= call.cc_generation then return false end
    local stats = cc_main.get_stats()
    return stats and stats.selected == true and stats.session == call.pcm_session and
        stats.active == 1 and stats.media_ready == 0 and
        stats.dl_queued == 0 and stats.ul_queued == 0 and stats.sdk_active == 0 and
        stats.sdk_pending == 0 and stats.sdk_stop_waiting == 0
end

local function resources_released()
    -- 被拒绝的另一通手机来电也须等终结，不能仅靠 bridgeAudioStop 的零统计放行。
    local cc_idle = cc_main.get_state() == "cc_idle"
    local own_ringing = pending and pending.direction == "incoming" and not pending.cc_done and
        cc_main.get_state() == "cc_ringing" and cc_main.get_generation() == pending.cc_generation
    return (cc_idle or own_ringing) and pcm_sip.is_media_idle() and pcm_released()
end

local function reboot(reason)
    if rebooted then return end
    rebooted = true
    if wake_timer then sys.timerStop(wake_timer); wake_timer = nil end
    if recovery_timer then sys.timerStop(recovery_timer); recovery_timer = nil end
    log.error("bridge", "无真实 PCM，重启恢复", reason)
    rtos.reboot()
end

local function expire_pending(call)
    if pending ~= call then return end
    pending = nil
    log.warn("bridge", "等待旧通话释放超时", call.call_id, call.owner)
    if call.direction == "outgoing" then
        -- 从未拥有 CC/VoIP 的等待来电，只拒绝这一个 Call-ID。
        stop_sip(call, 480, "Temporarily Unavailable")
    else
        stop_cc(call)
        -- 如果旧通话还在清理，保留新 CC 的终结屏障，不能覆盖旧记录。
        pending = call
        call.expired = true
        call.deadline = nil
    end
end

local function parse_number(uri)
    if type(uri) ~= "string" then return nil end
    local address = uri:match("<%s*([^>]+)>") or uri
    local number = address:match("^[Ss][Ii][Pp][Ss]?:([^@;?%s]+)")
    if number and number ~= "" then return number end
end

local function start_pending(call)
    pending = nil
    current = call
    call.deadline = nil
    if call.direction == "outgoing" then
        if config.auto_answer_sip then
            call.sip_state = "sip_progressing"
            logi("旧通话已释放，启动 SIP 183", call.call_id)
            sip_request("SIP_PROGRESS_REQ", call)
        end
    elseif config.auto_handle_mobile_incoming then
        call.sip_done = false
        call.sip_state = "sip_dialing"
        logi("呼入场景：拨打 SIP", call.owner)
        sys.publish("SIP_DIAL_REQ", config.remote_sip_uri, call.owner)
    end
end

local function schedule_wake(delay)
    wake_timer = sys.timerStart(function()
        wake_timer = nil
        drive()
    end, math.max(1, delay))
end

drive = function()
    if wake_timer then sys.timerStop(wake_timer); wake_timer = nil end
    if rebooted then return end
    local now = now_ms()
    if pending and pending.deadline and now >= pending.deadline then expire_pending(pending) end
    if cleanup and cleanup.cc_done and cleanup.sip_done and resources_released() then
        logi("旧通话清理完成", cleanup.call_id, cleanup.owner)
        cleanup = nil
        cooldown_until = now + GAP_MS
    end
    if pending and pending.expired and pending.cc_done then
        -- 该入站等待结束后，必须再次等待其 PCM/SDK 释放。
        if not cleanup then
            local call = pending
            pending = nil
            cleanup = call
            call.ending = true
        end
    end
    if recovering then
        if not cleanup and not current and not pending and cc_main.get_state() == "cc_idle" and
            pcm_sip.is_media_idle() and cc_main.is_media_idle() then
            reboot("cleanup_done")
            return
        end
    elseif not cleanup and (not cooldown_until or now >= cooldown_until) then
        cooldown_until = nil
        if pending and not pending.expired and resources_released() then start_pending(pending) end
    end

    -- 只在清理/等待阶段读取原生状态。空闲阶段最多保留一个间隔到期定时器。
    if cleanup or pending or recovering then
        local delay = POLL_MS
        if pending and pending.deadline then delay = math.min(delay, pending.deadline - now) end
        if cooldown_until and cooldown_until > now then delay = math.min(delay, cooldown_until - now) end
        schedule_wake(delay)
    elseif cooldown_until then
        schedule_wake(cooldown_until - now)
    end
end

local function on_sip_incoming(from, uri, to, call_id, generation)
    if find_sip(call_id, generation) then return end
    if recovering or current or pending then
        sys.publish("SIP_FAIL_REQ", recovering and 480 or 486,
            recovering and "Temporarily Unavailable" or "Busy Here", call_id, generation)
        return
    end
    -- CC 真正占用且没有旧清理记录时，不能把正常通话误当作挂断收尾。
    if not cleanup and cc_main.get_state() ~= "cc_idle" then
        sys.publish("SIP_FAIL_REQ", 486, "Busy Here", call_id, generation)
        return
    end
    local call = new_call("outgoing")
    call.call_id, call.sip_generation = call_id, generation
    call.sip_state, call.sip_done = "sip_incoming", false
    call.number = parse_number(uri) or parse_number(to) or config.target_phone_number
    call.deadline = now_ms() + WAIT_MS
    pending = call
    logi("SIP 来电", call_id, "目标", call.number)
    drive()
end

local function on_sip_bound(call_id, generation, owner)
    local call = find_sip(call_id, generation, owner)
    if call then bind_sip(call, call_id, generation) end
end

local function on_sip_progressing(call_id, generation, owner)
    local call = find_sip(call_id, generation, owner)
    if not call or call ~= current or call.ending or call.direction ~= "outgoing" or call.owns_cc then return end
    bind_sip(call, call_id, generation)
    call.sip_state = "sip_progressing"
    if cc_main.get_state() ~= "cc_idle" then begin_cleanup(call); return end
    -- 先认领再投递。重复 183 / started 不会重复拨号。
    call.owns_cc, call.cc_done = true, false
    call.cc_state = "cc_dialing"
    logi("183 和 VoIP started 已确认，拨打手机", call.number, call.call_id)
    sys.publish("CC_DIAL_REQ", call.number, call.owner)
end

local function on_sip_connected(call_id, generation, owner)
    local call = find_sip(call_id, generation, owner)
    if not call or call ~= current or call.ending then return end
    bind_sip(call, call_id, generation)
    call.sip_state = "sip_connected"
    if call.direction == "incoming" and not call.cc_accept_requested and call.cc_state == "cc_ringing" then
        call.cc_accept_requested = true
        call.cc_state = "cc_answering"
        sys.publish("CC_ACCEPT_REQ", call.cc_generation, call.owner)
    end
    if call.cc_state == "cc_connected" then call.connected_at = call.connected_at or now_ms() end
end

local function on_sip_ended(reason, call_id, generation, owner)
    local call = find_sip(call_id, generation, owner)
    if not call then return end
    bind_sip(call, call_id, generation)
    call.sip_done, call.sip_state = true, "sip_idle"
    logi("SIP 结束", reason, call.call_id)
    if call == pending and not call.owns_cc then
        pending = nil
        -- 等待中的 SIP 取消不改变旧清理和间隔。
        drive()
    elseif call == cleanup then
        stop_cc(call)
        drive()
    else
        begin_cleanup(call)
    end
end

local function on_cc_incoming(number, generation, session)
    if find_cc(generation) then return end
    local call = new_call("incoming")
    call.cc_generation, call.pcm_session = generation, session
    call.owns_cc, call.cc_done, call.cc_state = true, false, "cc_ringing"
    if not cc_main.claim_owner(generation, call.owner) then return end
    if recovering or current or pending or (cleanup and not cleanup.cc_done) then
        stop_cc(call)
        return
    end
    call.deadline = now_ms() + WAIT_MS
    pending = call
    logi("手机来电，等待桥接可用", number, generation)
    drive()
end

local function on_cc_state(new_state, old_state, generation, owner, session)
    local call = find_cc(generation, owner)
    if not call then return end
    call.cc_generation = call.cc_generation or generation
    call.pcm_session = call.pcm_session or session
    -- idle 只是状态通知；真正终结由下面的事件解除屏障。
    if not call.cc_stop_requested or new_state == "cc_idle" or new_state == "cc_disconnecting" then
        call.cc_state = new_state
    end
end

local function on_cc_connected(generation, owner, session)
    local call = find_cc(generation, owner)
    if not call or call ~= current or call.ending or call.cc_stop_requested then return end
    call.cc_generation, call.pcm_session = generation, session
    call.cc_state = "cc_connected"
    if call.direction == "outgoing" and not call.sip_accept_requested then
        call.sip_accept_requested = true
        sip_request("SIP_ACCEPT_REQ", call)
    end
    if call.sip_state == "sip_connected" then call.connected_at = call.connected_at or now_ms() end
end

local function on_cc_ended(reason, generation, owner, session)
    local call = find_cc(generation, owner)
    if not call then return end
    call.cc_generation, call.pcm_session = generation, session
    call.cc_done, call.cc_state = true, "cc_idle"
    logi("CC 终结", reason, generation)
    if call == cleanup then
        stop_sip(call)
        drive()
    elseif call == pending and cleanup then
        call.expired, call.deadline = true, nil
        drive()
    else
        begin_cleanup(call)
    end
end

local function on_cc_failed(reason, generation, owner, session, terminal)
    if terminal then on_cc_ended(reason, generation, owner, session); return end
    local call = find_cc(generation, owner)
    if not call then return end
    call.cc_generation, call.pcm_session = generation, session
    -- 启动超时/SDK 错误只是发起挂断；继续等待 CC 终结事件。
    call.cc_stop_requested, call.cc_state = true, "cc_disconnecting"
    if call == cleanup then
        stop_sip(call)
        drive()
    elseif call == pending and cleanup then
        call.expired, call.deadline = true, nil
        drive()
    else
        begin_cleanup(call)
    end
end

local function on_cc_dial_rejected(reason, owner)
    local call = find_cc(nil, owner)
    if not call then return end
    call.cc_done, call.cc_state = true, "cc_idle"
    log.warn("bridge", "CC 拒绝本次拨号", reason, owner)
    if call == cleanup then drive() else begin_cleanup(call) end
end

local function on_anomaly(reason, detail)
    if reason ~= "NO_MODEM_PCM" or type(detail) ~= "table" then return end
    log.error("bridge", "CC_BRIDGE_MEDIA_ANOMALY", reason, detail.session, detail.missing_calls)
    if config.cc_media_reboot_on_error == false or recovering then return end
    recovering = true
    cooldown_until = nil
    recovery_timer = sys.timerStart(function() reboot("cleanup_timeout") end, RECOVERY_MS)
    if pending then
        if pending.direction == "outgoing" then
            local call = pending
            pending = nil
            stop_sip(call, 480, "Temporarily Unavailable")
        else
            pending.expired, pending.deadline = true, nil
            stop_cc(pending)
        end
    end
    if current then begin_cleanup(current) end
    if cleanup then stop_sip(cleanup); stop_cc(cleanup) end
    drive()
end

sys.subscribe("SIP_INCOMING", on_sip_incoming)
sys.subscribe("SIP_CALL_BOUND", on_sip_bound)
sys.subscribe("SIP_PROGRESSING", on_sip_progressing)
sys.subscribe("SIP_CONNECTED", on_sip_connected)
sys.subscribe("SIP_DISCONNECTED", on_sip_ended)
sys.subscribe("SIP_FAILED", on_sip_ended)
sys.subscribe("SIP_MEDIA_STATE", function() drive() end)
sys.subscribe("CC_INCOMING", on_cc_incoming)
sys.subscribe("CC_STATE_CHANGED", on_cc_state)
sys.subscribe("CC_CONNECTED", on_cc_connected)
sys.subscribe("CC_DISCONNECTED", on_cc_ended)
sys.subscribe("CC_FAILED", on_cc_failed)
sys.subscribe("CC_DIAL_REJECTED", on_cc_dial_rejected)
sys.subscribe("CC_BRIDGE_MEDIA_ANOMALY", on_anomaly)

function bridge.get_state()
    local call = current or pending or cleanup
    return {
        sip_state = call and call.sip_state or "sip_idle",
        cc_state = cc_main.get_state(),
        in_call = current ~= nil and current.sip_state == "sip_connected" and current.cc_state == "cc_connected",
        call_direction = call and call.direction,
        call_duration = current and current.connected_at and (now_ms() - current.connected_at) / 1000 or 0,
        waiting = pending ~= nil,
        cleanup_pending = cleanup ~= nil,
        cooldown_remaining_ms = cooldown_until and math.max(0, cooldown_until - now_ms()) or 0,
        recovering = recovering,
        current_call_id = current and current.call_id,
        pending_call_id = pending and pending.call_id,
    }
end

logi("SIP/CC 纯 PCM 桥接协调器已加载")
return bridge
