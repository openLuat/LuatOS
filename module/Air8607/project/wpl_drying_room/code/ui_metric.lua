--[[
@module  ui_metric
@summary 指标详情页：大波形图 + 触摸调节（模拟值 / 报警阈值）
@version 1.0
@date    2026.10.24

布局（1024x600）：
  顶栏 0..64：返回 + 指标名 + 状态
  波形卡 (24,80,976,240)：网格 + 阈值线 + 实时折线
  当前值卡 (24,336,300,160)
  模拟调节卡 (340,336,340,160)
  阈值卡 (696,336,304,160)
]]
local conf = require "conf"
local theme = require "theme"
local sim = require "sim"

local M = {}
local C = theme.C
local SW, SH = conf.W, conf.H

local root = nil
local app_ref = nil
local cur_key = nil

local valueLabel, stateLabel, rangeLabel, yRangeLabel
local waveShape
local simSlider, simValueLabel
local lowSlider, highSlider, lowLabel, highLabel

local WAVE_W, WAVE_H = 944, 176

local function wave_items(hist, range, upper, lower, color)
    local n = #hist
    if n < 2 then return {} end

    -- ===== y 轴自适应（带上下限，避免被启动过渡值撑爆）=====
    local dmin, dmax = hist[1], hist[1]
    for i = 2, n do
        local v = hist[i]
        if v < dmin then dmin = v end
        if v > dmax then dmax = v end
    end
    local full = range[2] - range[1]
    local min_span = full * 0.03
    if min_span < 0.05 then min_span = 0.05 end
    local max_span = full * 0.18
    if max_span < min_span * 4 then max_span = min_span * 4 end

    local span = dmax - dmin
    local mn, mx
    if span > max_span then
        -- 历史跨度太大（例如从室温爬到目标值）：以当前值为中心开窗，超出部分裁掉
        local c = hist[n]
        mn, mx = c - max_span / 2, c + max_span / 2
    elseif span < min_span then
        local c = (dmax + dmin) / 2
        mn, mx = c - min_span / 2, c + min_span / 2
    else
        local p = span * 0.20
        mn, mx = dmin - p, dmax + p
    end
    if mx - mn < 0.0001 then mx = mn + 1 end

    local pad = 4
    local wave_area = WAVE_H - 2 * pad
    local function px(i) return pad + (WAVE_W - 2 * pad) * (i - 1) / (n - 1) end
    local function py(v)
        local t = (v - mn) / (mx - mn)
        if t < 0 then t = 0 end
        if t > 1 then t = 1 end
        return pad + wave_area * (1 - t)
    end

    local items = {}

    -- ===== 面积填充（曲线下方渐变），参考“实时曲线”那种效果 =====
    local segs = n - 1
    if segs > 40 then segs = 40 end
    for s = 1, segs do
        local i0 = math.floor((s - 1) * (n - 1) / segs) + 1
        local i1 = math.floor(s * (n - 1) / segs) + 1
        if i0 < 1 then i0 = 1 end
        if i1 > n then i1 = n end
        local v = hist[i1]
        local y = py(v)
        local x0 = px(i0)
        local x1 = px(i1)
        local w = x1 - x0
        if w < 1 then w = 1 end
        local h = WAVE_H - y
        if h > 0 then
            -- 越靠下填充越实，形成纵向渐变感
            local op = 30 + math.floor(45 * (y / WAVE_H))
            items[#items + 1] = {
                type = "rect", x = x0, y = y, w = w, h = h,
                fill = true, fill_color = color, fill_opacity = op,
            }
        end
    end

    -- 阈值线（落在可视范围内才画）
    if upper and upper >= mn and upper <= mx then
        items[#items + 1] = { type = "line", x1 = 0, y1 = py(upper), x2 = WAVE_W, y2 = py(upper),
                              color = C.gold, width = 1, dash_width = 6, dash_gap = 4, opacity = 180 }
    end
    if lower and lower >= mn and lower <= mx then
        items[#items + 1] = { type = "line", x1 = 0, y1 = py(lower), x2 = WAVE_W, y2 = py(lower),
                              color = C.gold, width = 1, dash_width = 6, dash_gap = 4, opacity = 180 }
    end

    -- 折线（画在填充之上）
    for i = 1, n - 1 do
        items[#items + 1] = {
            type = "line",
            x1 = px(i), y1 = py(hist[i]),
            x2 = px(i + 1), y2 = py(hist[i + 1]),
            color = color, width = 2,
        }
    end

    -- 数据点
    for i = 1, n, 5 do
        items[#items + 1] = {
            type = "circle", cx = px(i), cy = py(hist[i]), r = 2,
            fill = true, fill_color = color,
        }
    end
    return items, mn, mx
end

local function grid_items()
    local items = {}
    for i = 1, 5 do
        local x = math.floor(WAVE_W * i / 6)
        items[#items + 1] = { type = "line", x1 = x, y1 = 0, x2 = x, y2 = WAVE_H, color = C.line, width = 1, opacity = 90 }
    end
    for i = 1, 3 do
        local y = math.floor(WAVE_H * i / 4)
        items[#items + 1] = { type = "line", x1 = 0, y1 = y, x2 = WAVE_W, y2 = y, color = C.line, width = 1, opacity = 90 }
    end
    return items
end

local function apply_thresholds()
    if not cur_key then return end
    local d = sim.def(cur_key)
    local lo = lowSlider and lowSlider:get_value() or d.low
    local hi = highSlider and highSlider:get_value() or d.high
    sim.set_threshold(cur_key, lo, hi)
end

function M.build(app, key)
    M.destroy()
    app_ref = app
    cur_key = key
    local d = sim.def(key)
    local range = sim.range(key)

    root = airui.container({
        parent = nil, x = 0, y = 0, w = SW, h = SH,
        color = C.bg1, radius = 0, border_width = 0,
    })
    theme.gradient(root, 0, 0, SW, SH, C.bg1, C.bg2, 14)

    theme.box(root, 0, 0, SW, 64, 0x1C1209)
    theme.button(root, 16, 14, 104, 36, "返回", 18, C.panel2, C.ink, function()
        theme.defer(function()
            if app_ref then app_ref.close_metric() end
        end)
    end, 10)
    theme.label(root, 136, 14, 400, 36, d.name .. " · 详情", 26, C.ink)
    stateLabel = theme.label(root, 860, 18, 140, 28, "正常", 18, C.ok, airui.TEXT_ALIGN_RIGHT)

    local waveCard = theme.card(root, 24, 80, 976, 240)
    theme.label(waveCard, 16, 12, 200, 22, "实时波形", 16, C.ink)
    theme.label(waveCard, 110, 14, 200, 18, d.unit ~= "" and d.unit or "—", 12, C.ink3)
    yRangeLabel = theme.label(waveCard, 560, 14, 270, 18, "", 11, C.ink3, airui.TEXT_ALIGN_RIGHT)
    theme.label(waveCard, 850, 14, 110, 18, "金虚线=阈值", 11, C.ink3, airui.TEXT_ALIGN_RIGHT)

    theme.shape({ parent = waveCard, x = 16, y = 44, w = WAVE_W, h = WAVE_H, items = grid_items() })
    waveShape = theme.shape({ parent = waveCard, x = 16, y = 44, w = WAVE_W, h = WAVE_H, items = {} })

    local curCard = theme.card(root, 24, 336, 300, 160)
    theme.label(curCard, 16, 14, 200, 22, "当前值", 16, C.ink)
    valueLabel = theme.label(curCard, 16, 44, 268, 56, "--", 44, C.ink)
    rangeLabel = theme.label(curCard, 16, 116, 268, 20, "", 13, C.ink3)

    local simCard = theme.card(root, 340, 336, 340, 160)
    theme.label(simCard, 16, 14, 160, 22, "模拟值调节", 16, C.ink)
    theme.button(simCard, 232, 10, 92, 30, "恢复自动", 13, C.panel2, C.ink2, function()
        theme.defer(function()
            sim.clear_manual(cur_key)
            if simSlider then simSlider:set_value(sim.get(cur_key), false) end
            if app_ref then app_ref.toast("已恢复自动模拟") end
        end)
    end, 8)
    simValueLabel = theme.label(simCard, 16, 44, 308, 24, "", 14, C.ink2)
    local ok_s, sl_s = pcall(function()
        return airui.slider({
            parent = simCard, x = 16, y = 92, w = 308, h = 26,
            min = math.floor(range[1]), max = math.ceil(range[2]),
            value = math.floor(sim.get(key) + 0.5),
            style = {
                bg_color = C.line, bg_opa = 255,
                indicator_color = C.amber, indicator_opa = 255,
                knob_color = 0xFFFFFF, knob_opa = 255,
                knob_border_color = C.amber, knob_border_width = 2,
                radius = 12,
            },
            on_change = function()
                if not simSlider then return end
                local v = simSlider:get_value()
                sim.set_value(cur_key, v)
                if simValueLabel then
                    simValueLabel:set_text(string.format("手动设定：%s%s", sim.fmt(cur_key, v), d.unit))
                end
            end,
        })
    end)
    simSlider = ok_s and sl_s or nil

    local thCard = theme.card(root, 696, 336, 304, 160)
    theme.label(thCard, 16, 14, 200, 22, "报警阈值", 16, C.ink)
    local lo, hi = sim.threshold(key)

    lowLabel = theme.label(thCard, 16, 48, 140, 20,
        string.format("下限 %s", d.low and sim.fmt(key, lo) or "—"), 13, C.ink2)
    if d.low then
        local ok_l, sl_l = pcall(function()
            return airui.slider({
                parent = thCard, x = 16, y = 70, w = 272, h = 22,
                min = math.floor(range[1]), max = math.ceil(range[2]),
                value = math.floor(lo + 0.5),
                style = {
                    bg_color = C.line, bg_opa = 255,
                    indicator_color = C.gold, indicator_opa = 255,
                    knob_color = 0xFFFFFF, knob_opa = 255,
                    knob_border_color = C.gold, knob_border_width = 2,
                    radius = 10,
                },
                on_change = function()
                    if not lowSlider then return end
                    apply_thresholds()
                    lowLabel:set_text(string.format("下限 %s", sim.fmt(cur_key, lowSlider:get_value())))
                end,
            })
        end)
        lowSlider = ok_l and sl_l or nil
    end

    highLabel = theme.label(thCard, 16, 100, 140, 20,
        string.format("上限 %s", d.high and sim.fmt(key, hi) or "—"), 13, C.ink2)
    if d.high then
        local ok_h, sl_h = pcall(function()
            return airui.slider({
                parent = thCard, x = 16, y = 122, w = 272, h = 22,
                min = math.floor(range[1]), max = math.ceil(range[2]),
                value = math.floor(hi + 0.5),
                style = {
                    bg_color = C.line, bg_opa = 255,
                    indicator_color = C.gold, indicator_opa = 255,
                    knob_color = 0xFFFFFF, knob_opa = 255,
                    knob_border_color = C.gold, knob_border_width = 2,
                    radius = 10,
                },
                on_change = function()
                    if not highSlider then return end
                    apply_thresholds()
                    highLabel:set_text(string.format("上限 %s", sim.fmt(cur_key, highSlider:get_value())))
                end,
            })
        end)
        highSlider = ok_h and sl_h or nil
    end

    theme.label(root, 24, 512, 976, 24,
        "拖动滑块可实时改变模拟值 / 报警阈值，波形与状态随之变化", 13, C.ink3)

    M.refresh()
end

function M.refresh()
    if not root or not cur_key then return end
    local d = sim.def(cur_key)
    local st = sim.status(cur_key)
    local col = theme.state_color(st)

    if valueLabel then valueLabel:set_text(sim.fmt(cur_key, sim.get(cur_key)) .. d.unit) end
    if stateLabel then
        stateLabel:set_text(theme.state_text(st))
        stateLabel:set_color(col)
    end

    local lo, hi = sim.threshold(cur_key)
    if rangeLabel then
        local parts = {}
        if d.low then parts[#parts + 1] = "下限 " .. sim.fmt(cur_key, lo) end
        if d.high then parts[#parts + 1] = "上限 " .. sim.fmt(cur_key, hi) end
        rangeLabel:set_text("正常区间：" .. (#parts > 0 and table.concat(parts, "  ") or "—"))
    end

    if waveShape then
        local items, wmn, wmx = wave_items(sim.history(cur_key), sim.range(cur_key), hi, lo, col)
        waveShape:set_items(items)
        if yRangeLabel then
            yRangeLabel:set_text(string.format("可视 %.2f ~ %.2f", wmn, wmx))
        end
    end

    if simValueLabel then
        if sim.is_manual(cur_key) then
            simValueLabel:set_text(string.format("手动设定：%s%s", sim.fmt(cur_key, sim.manual(cur_key)), d.unit))
        else
            simValueLabel:set_text("自动模拟中（拖动滑块可手动接管）")
        end
    end
end

function M.destroy()
    if root then
        pcall(function() root:destroy() end)
        root = nil
    end
    app_ref = nil
    cur_key = nil
    valueLabel, stateLabel, rangeLabel, yRangeLabel = nil, nil, nil, nil
    waveShape = nil
    simSlider, simValueLabel = nil, nil
    lowSlider, highSlider, lowLabel, highLabel = nil, nil, nil, nil
end

return M
