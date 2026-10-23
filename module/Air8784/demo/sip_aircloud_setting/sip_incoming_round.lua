--[[
@module sip_incoming_round
@summary SIP来电的手机顺序转拨与蜂窝释放保护
@version 1.0
@date 2026.09.29
@usage
new(opts) 注入dial/release/finish，不主动接听或挂断SIP。
每个号码等待30秒；失败后强制释放CC，收到挂断完成并稳定500毫秒才继续。
释放10秒仍未确认则结束本轮，不并发拨号。接通过任一号码后不再顺延。
]]
local M = {}
function M.new(opts)
    local api = {}
    local phase, targets, index = "idle", {}, 0
    local dial_timer, release_timer, settle_timer
    local function stop_timer(timer) if timer then sys.timerStop(timer) end end
    local function clear_timers()
        stop_timer(dial_timer); stop_timer(release_timer); stop_timer(settle_timer)
        dial_timer, release_timer, settle_timer = nil, nil, nil
    end
    function api.cancel()
        clear_timers(); phase = "idle"; targets = {}; index = 0
    end
    local function finish(reason)
        api.cancel(); opts.finish(reason)
    end
    local function release_timeout()
        release_timer = nil
        if phase == "releasing" then finish("CC Release Timeout") end
    end
    local function release_current()
        if phase ~= "dialing" then return end
        clear_timers(); phase = "releasing"
        release_timer = sys.timerStart(release_timeout, 10000)
        opts.release()
    end
    local function dial_timeout()
        dial_timer = nil
        release_current()
    end
    local function dial_current()
        phase = "dialing"
        dial_timer = sys.timerStart(dial_timeout, 30000)
        opts.dial(targets[index], index, #targets)
    end
    local function released()
        settle_timer = nil
        if phase ~= "releasing" then return end
        stop_timer(release_timer); release_timer = nil
        index = index + 1
        if index > #targets then finish("All Phone Targets Failed")
        else dial_current() end
    end
    function api.start(numbers)
        if phase ~= "idle" or type(numbers) ~= "table" or #numbers == 0 then return false end
        targets = {}; for i, number in ipairs(numbers) do targets[i] = number end
        index = 1; dial_current(); return true
    end
    function api.active() return phase ~= "idle" end
    function api.connected()
        if phase == "dialing" then clear_timers(); phase = "connected"; return true end
        if phase == "releasing" then opts.release(); return false end
        return phase == "connected"
    end
    function api.failed()
        if phase == "dialing" then release_current(); return true end
        return phase == "releasing"
    end
    function api.disconnected(reason)
        if phase == "dialing" then release_current() end
        if phase ~= "releasing" then return false end
        if reason ~= "hangup_done" and not settle_timer then return true end
        -- Coalesce DISCONNECTED and HANGUP_CALL_DONE before the next dial.
        stop_timer(settle_timer)
        settle_timer = sys.timerStart(released, 500)
        return true
    end
    return api
end
return M
