--[[
@module  ui_trend
@summary 趋势页：大图双通道曲线 + 每通道当前/最大/最小统计
@version 1.0.0
@date    2026.11.09
]]
local M = {}

M.TITLE = "历史趋势"

local conf = require "conf"
local theme = require "ui_theme"
local C = theme.C
local data = require "app_data"
local curve = require "ui_curve"

function M.build(body)
    -- last_t: 曲线去重用（回填时已含最后一点，初值取回填的最后时间戳）
    -- stat_t: 统计去重用（初值为空，保证重建后第一帧就把 max/min/点数 算出来）
    local api = { last_t = {}, stat_t = {}, cards = {} }

    api.curve = curve.build(body, 20, 0, 984, 386,
        string.format("双通道历史趋势 0~%.1f%s · %d 分钟窗口（横轴左→右＝最旧→最新）",
            conf.scale.val_max, conf.scale.unit,
            math.floor(conf.trend.cap * conf.trend.sample_ms / 60000)),
        { series = 2, axis_ticks = 6 })

    -- 回填时已包含最后一个点，last_t 跟着初始化，避免重建后重复 push 一次
    if api.curve then
        api.last_t = api.curve.last_stamp or {}
    end

    for i = 1, #conf.chs do
        local x = (i == 1) and 20 or 520
        local card = theme.card(body, x, 396, 484, 88, C.panel, 10, C.line, 1)
        theme.accent_bar(card, 12, 0, 60, conf.chs[i].color)
        theme.label(card, 16, 12, 160, 24, conf.chs[i].name, 17, C.ink2)

        api.cards[i] = {
            cur = theme.label(card, 16, 40, 150, 34, "--.--", 30, conf.chs[i].color),
            max = theme.label(card, 186, 22, 150, 22, "最大 --", 14, C.ink3),
            min = theme.label(card, 186, 48, 150, 22, "最小 --", 14, C.ink3),
            cnt = theme.label(card, 340, 48, 130, 22, "点数 0", 13, C.ink3),
        }
    end

    return api
end

function M.refresh(api)
    if not api then
        return
    end

    for i = 1, #conf.chs do
        local st = data.stamps[i]
        local t = st[#st]
        local c = api.cards[i]

        theme.set_text(c.cur, data.online and string.format("%.1f", data.val[i] or 0) or "--.-")

        local h = data.hist[i]
        local n = #h

        -- 统计：只在有新采样点时重算，避免每次刷新遍历全部点；
        -- 用独立的 stat_t 去重，切页面回来第一帧会强制重算一次
        if t and t ~= api.stat_t[i] then
            api.stat_t[i] = t

            if n > 0 then
                local mx, mn = -math.huge, math.huge
                for k = 1, n do
                    local v = h[k]
                    if v > mx then mx = v end
                    if v < mn then mn = v end
                end
                theme.set_text(c.max, string.format("最大 %.1f", mx))
                theme.set_text(c.min, string.format("最小 %.1f", mn))
            end
            theme.set_text(c.cnt, string.format("点数 %d / %d", n, conf.trend.cap))
        end

        -- 曲线：回填已含最后一点（last_t 已初始化），只有真正的新采样点才 push
        if t and t ~= api.last_t[i] then
            api.last_t[i] = t
            if api.curve and n > 0 then
                api.curve.push(i, h[n])
            end
        end
    end
end

return M
