--[[
@module  tick_time
@summary tick 与毫秒换算（时间一律用 mcu.ticks() + mcu.hz() 表达）
@version 1.0
@date    2026.11.05
@author  江访

=== 接口 ===

tick_time.hz()             → 每秒 tick 数
tick_time.now()            → 当前 tick
tick_time.ms(n)            → n 毫秒折算成 tick 数
tick_time.s(n)             → n 秒折算成 tick 数
tick_time.deadline(ms)     → 从现在起 ms 毫秒后的 tick 截止点
tick_time.expired(dl)      → 截止点是否已过
tick_time.elapsed(now, t0) → now - t0 的 tick 差
tick_time.to_ms(dt)        → tick 差折算成毫秒

=== 约定 ===

- mcu.ticks() 不是毫秒：Air1601 / Air1603 / Air8607 是 20ms 一个 tick（mcu.hz() = 50），
  Air8000 是 1ms 一个 tick（mcu.hz() = 1000），PC 模拟器 mcu.hz() 恒返回 1 而 tick 就是毫秒
- 故每秒 tick 数取 mcu.hz()，取到 1 时按 1000 折算，各平台一致
- tick 会回绕（mcu.ticks() 无符号 0~0xffffffff），跨回绕的差值一律走 elapsed
]]

local M = {}

local HZ = 1000
do
    local h = (mcu ~= nil and type(mcu.hz) == "function") and mcu.hz() or nil
    if type(h) == "number" and h > 1 then HZ = h end
end

-- 每秒 tick 数
function M.hz()
    return HZ
end

-- 当前 tick
function M.now()
    return mcu.ticks()
end

-- 毫秒 → tick 数
function M.ms(n)
    return math.floor((n or 0) * HZ / 1000)
end

-- 秒 → tick 数
function M.s(n)
    return math.floor((n or 0) * HZ)
end

-- 从现在起 ms 毫秒后的 tick 截止点
function M.deadline(ms)
    return mcu.ticks() + M.ms(ms)
end

-- now - since 的 tick 差，跨 tick 回绕安全
function M.elapsed(now, since)
    local d = now - since
    if d < 0 then d = d + 0x100000000 end
    return d
end

-- 截止点是否已过
function M.past(now, dl)
    return M.elapsed(now, dl) < 0x80000000
end

-- 截止点是否已过（取当前 tick）
function M.expired(dl)
    return M.past(mcu.ticks(), dl)
end

-- tick 差 → 毫秒
function M.to_ms(dt)
    return math.floor((dt or 0) * 1000 / HZ)
end

return M
