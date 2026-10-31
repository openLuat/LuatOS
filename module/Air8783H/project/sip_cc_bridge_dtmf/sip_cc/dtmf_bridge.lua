-- 每通电话独立的双向按键队列；不把发送确认当成远端 IVR 的处理确认。
local M = {}
local config = require "config"
local pcm_sip = require "pcm_sip"
local LIMIT, TIMEOUT = 32, 5000
local GAP = config.dtmf_interval_ms or 100
assert(type(GAP) == "number" and GAP >= 50 and GAP <= 2000 and GAP % 1 == 0,
    "invalid dtmf_interval_ms (50-2000)")

local function now_ms()
    local high, low = mcu.ticks2(1)
    return high * 1000000.0 + low
end

local function duration(value)
    value = tonumber(value) or config.dtmf_duration_ms or 300
    if value ~= value or value == math.huge or value <= 0 then value = config.dtmf_duration_ms or 300 end
    return math.max(100, math.min(1000, math.floor(value)))
end

function M.new(current, ready)
    local self = {}
    local state, timer
    local pump

    function self.cancel(call, reason)
        if not state or (call and state.call ~= call) then return end
        if timer then sys.timerStop(timer); timer = nil end
        if #state.cc.queue > 0 or #state.sip.queue > 0 or state.cc.pending or state.sip.pending then
            log.warn("bridge_dtmf", "RELAY_CANCELLED", reason)
        end
        state = nil
    end

    local function schedule()
        if timer or not state then return end
        timer = sys.timerStart(function() timer = nil; pump() end, 50)
    end

    local function finish(lane, ok, reason)
        local item = lane.pending
        if not item then return end
        lane.pending = nil
        lane.next_at = math.max(now_ms(), item.started + item.duration) + GAP
        log[ok and "info" or "warn"]("bridge_dtmf", ok and "RELAY_SENT" or "RELAY_FAILED",
            item.direction, item.digit, reason)
        schedule()
    end

    local function send(lane, direction, now)
        if lane.pending then
            if now >= lane.pending.deadline then
                -- 确认超时后不重发，不继续本方向队列，避免异步迟到确认错配下一键。
                finish(lane, false, "confirm_timeout")
                lane.queue, lane.failed = {}, true
            end
            return
        end
        if lane.failed or #lane.queue == 0 or now < lane.next_at then return end
        local item = lane.queue[1]
        local ok, id, method
        if direction == "SIP_TO_CC" then
            ok, id = cc.sendDtmf(0, item.digit, item.duration)
        else
            local call = state.call
            ok, id, method = pcm_sip.send_dtmf(item.digit, item.duration,
                call.call_id, call.sip_generation)
        end
        if not ok and (id == "DTMF request still pending" or id == "busy" or id == "dtmf_busy") and now < item.deadline then
            return
        end
        table.remove(lane.queue, 1)
        if not ok then
            log.warn("bridge_dtmf", "RELAY_REJECTED", direction, item.digit, id)
            lane.next_at = now + GAP
            return
        end
        item.id, item.method, item.direction = id, method, direction
        item.started, item.deadline = now, now + TIMEOUT
        lane.pending = item
        log.info("bridge_dtmf", "RELAY_SUBMITTED", direction, item.digit, method or "CC", id)
    end

    pump = function()
        if not state then return end
        if current() ~= state.call or not ready(state.call) then
            self.cancel(nil, "call_or_media_changed")
            return
        end
        local now = now_ms()
        send(state.cc, "SIP_TO_CC", now)
        send(state.sip, "CC_TO_SIP", now)
        if state and (state.cc.pending or state.sip.pending or #state.cc.queue > 0 or #state.sip.queue > 0) then
            schedule()
        end
    end

    function self.enqueue(call, direction, digit, ms)
        if current() ~= call or not ready(call) or type(digit) ~= "string" or
            not digit:match("^[0-9A-D*#]$") then return false end
        if not state then
            state = {call = call, cc = {queue = {}, next_at = 0}, sip = {queue = {}, next_at = 0}}
        end
        if state.call ~= call then return false end
        local lane = direction == "SIP_TO_CC" and state.cc or state.sip
        if lane.failed or #lane.queue >= LIMIT then
            log.warn("bridge_dtmf", "RELAY_DROPPED", direction, digit, lane.failed and "lane_failed" or "queue_full")
            return false
        end
        lane.queue[#lane.queue + 1] = {digit = digit, duration = duration(ms), deadline = now_ms() + TIMEOUT}
        -- 异步投递，保证 pending 在确认事件处理前已绑定。
        schedule()
        return true
    end

    sys.subscribe("CC_DTMF_TX", function(id, ok, code)
        if state and state.cc.pending and state.cc.pending.id == id then finish(state.cc, ok, code) end
    end)
    function self.sip_result(call, action, data)
        if not state or state.call ~= call or not state.sip.pending then return end
        local item = state.sip.pending
        if data.method == "RFC4733" then
            if item.method ~= "RFC4733" or item.id ~= data.id then return end
            if action == "tx_done" or action == "tx_failed" then finish(state.sip, action == "tx_done", data.reason) end
        elseif item.method == "INFO" and data.request_id == item.id and data.digits == item.digit and
            (action == "completed" or action == "failed") then
            finish(state.sip, action == "completed", data.reason or data.code)
        end
    end
    return self
end

return M
