--[[
@module  ui_metric
@summary ReefOS 参数详情页：趋势曲线 + 当前读数 + 养护建议 + 手动模拟 + 报警阈值
@version 1.0
@date    2026.10.27
]]
local conf = require "conf"
local theme = require "theme"
local art = require "art"
local sim = require "sim"
local app = require "app"

local C, SZ = theme.C, theme.SZ
local L, CT, RT = airui.TEXT_ALIGN_LEFT, airui.TEXT_ALIGN_CENTER, airui.TEXT_ALIGN_RIGHT

local M = {}

function M.build(p, key)
    local keys = sim.keys()
    local idx = 1
    for i, k in ipairs(keys) do
        if k == key then idx = i end
    end
    key = keys[idx]
    local def = sim.def(key)
    local scale = def.scale or 1

    local alive = true
    local ui = {}

    local title = def.name .. (def.unit ~= "" and ("（" .. def.unit .. "）") or "")
    local bar, clock, date = app.subbar(p, title, "第 " .. idx .. " / " .. #keys .. " 项 · 曲线为最近 48 次采样")

    local prevb = theme.card(bar, 566, 10, 36, 36, {
        color = C.panel2, radius = 9, border_color = C.line, border_width = 1,
        on_click = function() app.go("metric", keys[(idx - 2) % #keys + 1]) end,
    })
    art.icon(prevb, "back", 9, 9, 18, C.ink2)
    local nextb = theme.card(bar, 608, 10, 36, 36, {
        color = C.panel2, radius = 9, border_color = C.line, border_width = 1,
        on_click = function() app.go("metric", keys[idx % #keys + 1]) end,
    })
    art.icon(nextb, "arrow", 9, 9, 18, C.ink2)
    theme.label(bar, 650, 16, 60, 24, idx .. " / " .. #keys, SZ.s, C.ink3, CT)

    ------------------------------------------------------------------
    -- 趋势曲线
    ------------------------------------------------------------------
    local wc = theme.card(p, 16, 66, 704, 300)
    theme.label(wc, 16, 10, 260, 22, "趋势 · 最近 60 分钟", SZ.m, C.ink)
    ui.range_text = theme.label(wc, 16, 10, 704 - 32, 22, "", SZ.xs, C.ink3, RT)
    ui.wave = theme.shape(wc, 12, 38, 680, 200, {})

    ui.stats = {}
    local stat_names = { "最低", "平均", "最高" }
    for i = 1, 3 do
        local x = 16 + (i - 1) * 232
        theme.label(wc, x, 248, 90, 16, stat_names[i], SZ.xs, C.ink3)
        ui.stats[i] = theme.label(wc, x + 52, 244, 160, 24, "--", SZ.m, C.ink2)
    end

    ------------------------------------------------------------------
    -- 当前读数
    ------------------------------------------------------------------
    local vc = theme.card(p, 736, 66, 272, 150)
    theme.label(vc, 16, 10, 200, 22, "当前读数", SZ.m, C.ink)
    ui.value = theme.label(vc, 16, 34, 176, 54, "--", SZ.hero, C.ink)
    ui.unit = theme.label(vc, 190, 58, 68, 22, def.unit, SZ.xs, C.ink3)
    ui.ratio = theme.segbar(vc, 16, 100, 240, 8, 20, C.cyan, 0x132533, 2)
    ui.chip = theme.chip(vc, 16, 116, 84, 24, "正常", C.green, 0x0C2230, SZ.xs)
    ui.delta = theme.label(vc, 108, 116, 148, 24, "", SZ.xs, C.ink3, RT)

    ------------------------------------------------------------------
    -- 养护建议
    ------------------------------------------------------------------
    local tc = theme.card(p, 736, 224, 272, 142)
    theme.label(tc, 16, 10, 200, 22, "养护建议", SZ.m, C.ink)
    ui.tip = theme.label(tc, 16, 36, 240, 68, def.tip or "", SZ.xs, C.ink2)
    ui.ref = theme.label(tc, 16, 110, 240, 18, "", SZ.xs, C.cyan)

    ------------------------------------------------------------------
    -- 手动模拟
    ------------------------------------------------------------------
    local mc = theme.card(p, 16, 374, 704, 104)
    theme.label(mc, 16, 10, 260, 22, "手动模拟", SZ.m, C.ink)
    ui.mode = theme.label(mc, 16, 10, 704 - 32, 22, "", SZ.xs, C.ink3, RT)

    local smin = math.floor(def.min * scale + 0.5)
    local smax = math.ceil(def.max * scale)
    local slider
    if theme.slider then
        slider = theme.slider({
            parent = mc, x = 16, y = 42, w = 540, h = 26,
            min = smin, max = smax, value = sim.to_slider(key),
            style = {
                bg_color = C.panel3, indicator_color = C.cyan, knob_color = C.ink,
                knob_border_color = C.cyan, knob_border_width = 1, radius = 6, pad = 3,
            },
            on_change = function(s)
                if not alive then return end
                local ok, v = pcall(function() return s:get_value() end)
                if not ok then return end
                sim.set_value(key, sim.from_slider(key, v))
                refresh_value()
                refresh_wave()
            end,
        })
    end
    theme.label(mc, 16, 74, 160, 16, "下限 " .. sim.fmt(key, def.min), SZ.xs, C.ink3)
    theme.label(mc, 396, 74, 160, 16, "上限 " .. sim.fmt(key, def.max), SZ.xs, C.ink3, RT)
    theme.ghost(mc, 572, 34, 116, 36, "恢复自动", {
        size = SZ.s,
        on_click = function()
            if not alive then return end
            sim.clear_manual(key)
            if slider then pcall(function() slider:set_value(sim.to_slider(key), true) end) end
            app.toast("已交还自动演化", C.cyan)
            refresh_value()
            refresh_wave()
        end,
    })

    ------------------------------------------------------------------
    -- 报警阈值
    ------------------------------------------------------------------
    local hc = theme.card(p, 16, 486, 704, 104)
    theme.label(hc, 16, 10, 260, 22, "报警阈值", SZ.m, C.ink)
    theme.label(hc, 16, 10, 704 - 32, 22, "金色偏离 · 红色超限", SZ.xs, C.ink3, RT)

    ui.th_lo_text = theme.label(hc, 16, 30, 300, 16, "", SZ.xs, C.gold)
    ui.th_hi_text = theme.label(hc, 368, 30, 300, 16, "", SZ.xs, C.gold)

    local th = sim.threshold(key)
    local slo, shi
    if theme.slider then
        slo = theme.slider({
            parent = hc, x = 16, y = 50, w = 320, h = 22,
            min = smin, max = smax, value = math.floor((th.lo or def.min) * scale + 0.5),
            style = { bg_color = C.panel3, indicator_color = C.gold, knob_color = C.ink,
                      knob_border_color = C.gold, knob_border_width = 1, radius = 5, pad = 3 },
            on_change = function(s)
                if not alive then return end
                local ok, v = pcall(function() return s:get_value() end)
                if not ok then return end
                sim.set_threshold(key, "lo", sim.from_slider(key, v))
                refresh_th()
                refresh_value()
            end,
        })
        shi = theme.slider({
            parent = hc, x = 368, y = 50, w = 320, h = 22,
            min = smin, max = smax, value = math.floor((th.hi or def.max) * scale + 0.5),
            style = { bg_color = C.panel3, indicator_color = C.gold, knob_color = C.ink,
                      knob_border_color = C.gold, knob_border_width = 1, radius = 5, pad = 3 },
            on_change = function(s)
                if not alive then return end
                local ok, v = pcall(function() return s:get_value() end)
                if not ok then return end
                sim.set_threshold(key, "hi", sim.from_slider(key, v))
                refresh_th()
                refresh_value()
            end,
        })
    end
    theme.label(hc, 16, 80, 672, 16, "越过阈值触发偏离提示；越过硬门限（软硬两档）触发红色报警并写入事件记录。",
        SZ.xs, C.ink3)

    ------------------------------------------------------------------
    -- 刷新逻辑
    ------------------------------------------------------------------
    function refresh_th()
        local t = sim.threshold(key)
        local lo = t.lo and sim.fmt(key, t.lo) or "—"
        local hi = t.hi and sim.fmt(key, t.hi) or "—"
        ui.th_lo_text:set_text("下限 " .. lo .. (def.unit ~= "" and (" " .. def.unit) or ""))
        ui.th_hi_text:set_text("上限 " .. hi .. (def.unit ~= "" and (" " .. def.unit) or ""))
        ui.ref:set_text("正常区间 " .. lo .. " ~ " .. hi .. (def.unit ~= "" and (" " .. def.unit) or ""))
        ui.range_text:set_text("推荐 " .. lo .. " ~ " .. hi)
    end

    function refresh_wave()
        local lv = sim.level(key)
        local col = theme.state_color(lv)
        local t = sim.threshold(key)
        local hist = sim.hist(key)
        pcall(function()
            ui.wave:set_items(art.waveform_items(680, 200, hist, {
                color = col, min = def.min, max = def.max,
                lo = t.lo, hi = t.hi, band = true, grid = 4, dash = true,
            }))
        end)
        local n = #hist
        if n > 0 then
            local mn, mx, sum = hist[1], hist[1], 0
            for i = 1, n do
                local v = hist[i]
                if v < mn then mn = v end
                if v > mx then mx = v end
                sum = sum + v
            end
            ui.stats[1]:set_text(sim.fmt(key, mn) .. " " .. def.unit)
            ui.stats[2]:set_text(sim.fmt(key, sum / n) .. " " .. def.unit)
            ui.stats[3]:set_text(sim.fmt(key, mx) .. " " .. def.unit)
            local base = hist[math.max(1, n - 8)]
            local d = hist[n] - base
            ui.delta:set_text(string.format("%s%s / 10 分钟", d >= 0 and "+" or "", sim.fmt(key, d)))
            ui.delta:set_color(math.abs(d) > (def.hi - def.lo) * 0.15 and C.gold or C.ink3)
        end
    end

    function refresh_value()
        if not alive then return end
        local lv = sim.level(key)
        local col = theme.state_color(lv)
        local v = sim.value(key)
        ui.value:set_text(sim.fmt(key, v))
        ui.value:set_color(lv == "ok" and C.ink or col)
        ui.unit:set_text(def.unit)
        ui.ratio.set(sim.ratio(key), col)
        ui.chip.set(theme.state_text(lv), col)
        ui.chip.box:set_color(lv == "ok" and 0x0C2230 or theme.mix(C.panel, col, 0.22), nil)
        ui.mode:set_text(sim.is_manual(key) and "手动模拟中 · 数据已锁定" or "自动演化中 · 数据来自水体模型")
        ui.mode:set_color(sim.is_manual(key) and C.gold or C.ink3)
        ui.chip.box:set_border_color(col, 1)
    end

    refresh_th()
    refresh_value()
    refresh_wave()

    return {
        refresh = function()
            if not alive then return end
            clock:set_text(sim.clock())
            date:set_text(sim.date_text())
            if not sim.is_manual(key) then
                refresh_value()
                refresh_wave()
            end
        end,
        destroy = function()
            alive = false
        end,
    }
end

return M
