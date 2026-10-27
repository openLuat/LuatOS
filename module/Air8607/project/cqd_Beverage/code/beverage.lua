-- 纯 Lua 状态机：选择 -> 待灌注 -> 灌注 -> 空瓶 -> 清空选择。
-- 此工程是 UI 动画，不驱动泵、阀或流量计。
local C = require "config"
local M = {}
local phase, drink, size, elapsed, level = "idle", nil, nil, 0, 0

function M.snapshot()
    return {phase = phase, drink = drink, size = size, elapsed = elapsed,
        level = level, busy = phase == "pouring" or phase == "done"}
end

function M.select(drink_id, size_id)
    if phase == "pouring" or phase == "done" then return false end
    if not C.DRINKS[drink_id] or not C.SIZES[size_id] then return false end
    drink, size, elapsed = drink_id, size_id, 0
    phase, level = "ready", C.SIZES[size_id].level
    return true
end

function M.start()
    if phase ~= "ready" then return false end
    phase, elapsed = "pouring", 0
    return true
end

function M.reset()
    if phase == "pouring" or phase == "done" then return false end
    phase, drink, size, elapsed, level = "idle", nil, nil, 0, 0
    return true
end

function M.advance(ms)
    if type(ms) ~= "number" or ms <= 0 then return false end
    if phase == "pouring" then
        elapsed = elapsed + ms
        local spec = C.SIZES[size]
        local remaining = math.max(0, 1 - elapsed / spec.duration_ms)
        level = math.floor(spec.level * remaining + 0.5)
        if elapsed >= spec.duration_ms then
            phase, elapsed, level = "done", 0, 0
        end
        return true
    elseif phase == "done" then
        elapsed = elapsed + ms
        if elapsed >= C.EMPTY_HOLD_MS then
            phase, drink, size, elapsed, level = "idle", nil, nil, 0, 0
        end
        return true
    end
    return false
end

return M
