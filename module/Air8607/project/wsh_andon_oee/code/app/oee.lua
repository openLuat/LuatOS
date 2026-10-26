--[[
@module  oee
@summary OEE 计算与停机帕累托分析
@author  王世豪
@version 1.0
@date    2026.10.26
@usage
OEE = 可用率(A) × 性能(P) × 良率(Q)
 A = 运行时间 / 计划时间
 P = 实际产量 / (运行时间 / 节拍)
 Q = 良品数 / 总产量
]]
local conf = require "conf"

local M = {}

function M.compute(stats)
    -- 可用率
    local A = 0
    if stats.plan_sec > 0 then
        A = stats.run_sec / stats.plan_sec
        if A > 1 then A = 1 end
    end

    -- 性能（理论产量 = 运行时间 / 节拍）
    local ideal = 0
    if conf.line.cycle_time > 0 then
        ideal = stats.run_sec / conf.line.cycle_time
    end
    local P = 0
    if ideal > 0 then
        P = stats.produced / ideal
        if P > 1 then P = 1 end
    end

    -- 良率
    local Q = 0
    if stats.produced > 0 then
        Q = stats.good / stats.produced
    end

    return {
        availability = A,
        performance = P,
        quality = Q,
        oee = A * P * Q,
    }
end

--[[按异常类型汇总停机秒数，降序返回列表与总停机秒数]]
function M.pareto(by_type)
    local list = {}
    local total = 0
    for key, sec in pairs(by_type or {}) do
        local name = key
        for _, t in ipairs(conf.alarm_types) do
            if t.key == key then
                name = t.name
                break
            end
        end
        list[#list + 1] = { key = key, name = name, sec = sec }
        total = total + sec
    end
    table.sort(list, function(a, b) return a.sec > b.sec end)
    for _, it in ipairs(list) do
        it.pct = (total > 0) and (it.sec / total) or 0
    end
    return list, total
end

--[[秒 -> mm:ss]]
function M.fmt_dur(sec)
    sec = math.floor(sec or 0)
    return string.format("%02d:%02d", math.floor(sec / 60), sec % 60)
end

return M
