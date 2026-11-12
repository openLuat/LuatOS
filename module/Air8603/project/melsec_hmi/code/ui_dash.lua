--[[
@module  ui_dash
@summary 主监控页：2 路实时数值 + 2 路历史趋势 + 报警条
@version 1.0.0
@date    2026.11.09
]]
local M = {}

M.TITLE = "三菱 FX 温度监控"

local conf = require "conf"
local theme = require "ui_theme"
local C = theme.C
local data = require "app_data"
local alarm = require "app_alarm"
local curve = require "ui_curve"

-- 单通道数值卡
local function build_value_card(body, x, y, w, h, idx)
    local ch = conf.chs[idx]
    local card = theme.card(body, x, y, w, h, C.panel, 12, C.line, 1)
    theme.accent_bar(card, 12, 0, w - 24, ch.color)

    theme.label(card, 18, 16, 220, 26, ch.name, 19, C.ink2)
    local pill_bg, pill_tx = theme.pill(card, w - 134, 14, 116, 30, "正常", C.ok, 14)

    local big = theme.label(card, 14, 46, 286, 96, "--.-", 68, ch.color, airui.TEXT_ALIGN_LEFT)
    local unit = theme.label(card, 302, 98, 70, 34, conf.scale.unit, 24, C.ink3, airui.TEXT_ALIGN_LEFT)
    local raw = theme.label(card, 16, 146, 300, 24, "原始 --", 15, C.ink3)
    local thr = theme.label(card, 16, 170, w - 32, 22,
        string.format("预警 %.1f   报警 %.1f", ch.warn, ch.alarm), 13, C.ink3)

    return { big = big, unit = unit, raw = raw, thr = thr, pill_bg = pill_bg, pill_tx = pill_tx }
end

local function refresh_value_card(ui, idx)
    local ch = conf.chs[idx]
    local v = data.val[idx] or 0
    local r = data.raw[idx] or 0
    local lv = alarm.state[idx] or 0

    if data.online then
        theme.set_text(ui.big, string.format("%.1f", v))
        theme.set_text(ui.raw, string.format("原始值 %d / %d", r, conf.scale.raw_max))
    else
        theme.set_text(ui.big, "--.-")
        theme.set_text(ui.raw, string.format("原始值 %d（离线，保持最后值）", r))
    end
    theme.set_color(ui.big, data.online and ch.color or C.off)

    local text = (lv == 2) and "报警" or ((lv == 1) and "预警" or (data.online and "正常" or "离线"))
    local color = (lv == 2) and C.danger or ((lv == 1) and C.warn or (data.online and C.ok or C.off))
    theme.set_text(ui.pill_tx, text)
    theme.set_color(ui.pill_tx, color)
    pcall(ui.pill_bg.set_color, ui.pill_bg, color)
    theme.set_text(ui.thr, string.format("预警 %.1f   报警 %.1f", ch.warn, ch.alarm))
end

function M.build(body)
    local api = { last_t = {}, vcard = {}, curve = nil }

    -- 左列：两路数值 + 报警条
    api.vcard[1] = build_value_card(body, 20, 0, 470, 200, 1)
    api.vcard[2] = build_value_card(body, 20, 210, 470, 200, 2)

    local bar = theme.card(body, 20, 420, 470, 62, C.panel2, 10, C.line, 1)
    theme.label(bar, 14, 8, 90, 20, "最新报警", 13, C.ink3)
    api.alarm_text = theme.label(bar, 14, 30, 442, 24, "暂无报警记录", 15, C.ink2)
    local pill_bg, pill_tx = theme.pill(bar, 364, 10, 92, 26, "记录 0", C.off, 13)
    api.alarm_pill_bg = pill_bg
    api.alarm_pill = pill_tx

    -- 右列：双通道趋势（build 内部已把 app_data 的历史回填进新 chart）
    api.curve = curve.build(body, 506, 0, 498, 482,
        string.format("趋势 0~%.0f%s · 0→%dmin", conf.scale.val_max, conf.scale.unit,
            math.floor(conf.trend.cap * conf.trend.sample_ms / 60000)),
        { series = 2, axis_ticks = 5 })

    -- 回填时已包含最后一个点，last_t 要跟着初始化，
    -- 否则页面重建后第一次 refresh 会把这个点再 push 一遍（曲线错一格）
    if api.curve then
        api.last_t = api.curve.last_stamp or {}
    end

    return api
end

function M.refresh(api)
    if not api then
        return
    end

    refresh_value_card(api.vcard[1], 1)
    refresh_value_card(api.vcard[2], 2)

    -- 曲线：时间戳变化才推点
    if api.curve then
        for i = 1, #conf.chs do
            local st = data.stamps[i]
            local t = st[#st]
            if t and t ~= api.last_t[i] then
                api.last_t[i] = t
                local h = data.hist[i]
                if #h > 0 then
                    api.curve.push(i, h[#h])
                end
            end
        end
    end

    -- 报警条
    local rec = alarm.recs[1]
    if rec then
        theme.set_text(api.alarm_text, string.format("%s  %s  %.1f%s（阈值 %.1f）",
            os.date("%m-%d %H:%M:%S", rec.t or 0),
            (rec.level == 2) and "报警" or "预警",
            rec.val or 0, conf.scale.unit, rec.thr or 0))
        theme.set_color(api.alarm_text, (rec.level == 2) and C.danger or C.warn)
    else
        theme.set_text(api.alarm_text, "暂无报警记录")
        theme.set_color(api.alarm_text, C.ink2)
    end
    theme.set_text(api.alarm_pill, string.format("记录 %d", #alarm.recs))
    local lv = alarm.max_level()
    local pcol = (lv == 2) and C.danger or ((lv == 1) and C.warn or C.off)
    theme.set_color(api.alarm_pill, pcol)
    pcall(api.alarm_pill_bg.set_color, api.alarm_pill_bg, pcol)
end

return M
