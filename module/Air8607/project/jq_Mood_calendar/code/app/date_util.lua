--[[
@module  date_util
@summary 纯 Lua 日历计算：星期、月历网格
@author  蒋骞
@version 1.0
@date    2026.10.30

@note os.time 传入 table 时：
如果只给 year/month/day 不显式给 hour/min/sec，hour 会按标准 Lua 语义取默认值 12，
算出的是当天中午 12:00。所以计算天数差时一律走本模块的 midnight()，
显式补 hour=0/min=0/sec=0。
]]
local M = {}

M.WEEK_CN = { "日", "一", "二", "三", "四", "五", "六" }

--[[某天零点的时间戳（显式补 hour=0，避免默认取 12）]]
function M.midnight(y, m, d)
    return os.time({ year = y, month = m, day = d, hour = 0, min = 0, sec = 0 })
end

function M.is_leap(y)
    return (y % 4 == 0 and y % 100 ~= 0) or (y % 400 == 0)
end

function M.days_in_month(y, m)
    local d = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
    if m == 2 and M.is_leap(y) then return 29 end
    return d[m] or 30
end

--[[某天是星期几（1 = 周日 .. 7 = 周六，Lua os.date wday 语义）]]
function M.wday_of(y, m, d)
    local t = os.date("*t", M.midnight(y, m, d))
    return (t and t.wday) or 1
end

function M.week_cn(wday)
    return M.WEEK_CN[wday] or ""
end

--[[生成某月日历网格：固定 6 行 x 7 列 = 42 格（周日打头）
@return table 每项 { day = number, cur = bool }
        cur=false 表示是上月/下月的补位格
]]
function M.month_grid(y, m)
    local lead = M.wday_of(y, m, 1) - 1            -- 1 号前面要补几天
    local prev_days = M.days_in_month((m == 1) and (y - 1) or y, (m == 1) and 12 or (m - 1))
    local cur_days = M.days_in_month(y, m)

    local grid = {}
    local start_prev = prev_days - lead + 1
    for i = 1, lead do
        grid[#grid + 1] = { day = start_prev + i - 1, cur = false }
    end
    for d = 1, cur_days do
        grid[#grid + 1] = { day = d, cur = true }
    end
    local nxt = 1
    while #grid < 42 do
        grid[#grid + 1] = { day = nxt, cur = false }
        nxt = nxt + 1
    end
    return grid
end

return M
