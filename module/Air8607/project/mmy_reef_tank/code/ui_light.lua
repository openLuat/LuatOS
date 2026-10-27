--[[
@module  ui_light
@summary ReefOS 光照页：三通道调光 + 预设配方 + 混光预览 + 日夜节律
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

-- 可见光带配色（由紫到红），用于底部光谱示意条
local WAVE = { 0x8A5BFF, 0x5B6BFF, 0x2E9BFF, 0x35E0D0, 0x3FE0A0, 0xFFD166, 0xFF8A4B, 0xFF5470 }

local function wave_color(i)
    local idx = math.floor((i - 1) / 3) + 1
    if idx > #WAVE then idx = #WAVE end
    return WAVE[idx]
end

function M.build(p)
    local alive, ready = true, false
    local ui = { rows = {}, cards = {}, bands = {} }
    local last_sig, last_day = nil, nil
    local sync_sliders, refresh_spec, refresh_day

    local bar, clock, date = app.subbar(p, "光照光谱", "三通道混光 · 预设配方 · 日夜节律")

    ------------------------------------------------------------------
    -- 左：三通道调光
    ------------------------------------------------------------------
    local cc = theme.card(p, 16, 66, 560, 254)
    theme.label(cc, 16, 10, 200, 22, "通道强度", SZ.m, C.ink)
    ui.total = theme.label(cc, 16, 10, 560 - 32, 22, "", SZ.xs, C.ink3, RT)

    for i, ch in ipairs(conf.spectrum.channels) do
        local y0 = 42 + (i - 1) * 68
        local row = { ch = ch }
        app.dot(cc, 16, y0 + 8, 4, ch.color)
        theme.label(cc, 30, y0, 40, 20, ch.name, SZ.m, C.ink)
        theme.label(cc, 74, y0 + 2, 240, 18, ch.hint or "", SZ.xs, C.ink3)
        row.pct = theme.label(cc, 400, y0, 144, 22, "0%", SZ.l, C.ink, RT)

        row.bar = theme.segbar(cc, 16, y0 + 30, 528, 6, 22, ch.color, 0x132533, 2)
        row.slider = theme.slider({
            parent = cc, x = 16, y = y0 + 40, w = 528, h = 22,
            min = 0, max = 100, value = sim.spectrum()[ch.key] or 0,
            style = {
                bg_color = C.panel3, indicator_color = ch.color, knob_color = C.ink,
                knob_border_color = ch.color, knob_border_width = 1, radius = 6, pad = 4,
            },
            on_change = function(s)
                if not alive or not ready then return end
                local ok, v = pcall(function() return s:get_value() end)
                if not ok then return end
                sim.set_spectrum(ch.key, v)
                refresh_spec()
            end,
        })
        ui.rows[i] = row
    end

    ------------------------------------------------------------------
    -- 左：混光预览
    ------------------------------------------------------------------
    local pc = theme.card(p, 16, 330, 560, 254)
    theme.label(pc, 16, 10, 200, 22, "混光预览", SZ.m, C.ink)
    ui.preset_name = theme.label(pc, 16, 10, 560 - 32, 22, "", SZ.xs, C.cyan, RT)

    ui.orb = theme.card(pc, 20, 44, 150, 150, {
        color = C.panel2, radius = 75, border_color = C.line2, border_width = 2,
    })
    ui.orb_core = theme.card(pc, 46, 70, 98, 98, { color = C.panel3, radius = 49 })

    ui.big_name = theme.label(pc, 190, 42, 340, 34, "全光谱", SZ.xl, C.ink)
    ui.mood = theme.label(pc, 190, 78, 340, 20, "", SZ.xs, C.ink2)

    local grids = {
        { "总强度", 190, 108 }, { "灯具功率", 380, 108 },
        { "蓝白比", 190, 142 }, { "UV 占比", 380, 142 },
    }
    ui.grid = {}
    for i, g in ipairs(grids) do
        theme.label(pc, g[2], g[3], 90, 16, g[1], SZ.xs, C.ink3)
        ui.grid[i] = theme.label(pc, g[2] + 68, g[3] - 3, 100, 22, "--", SZ.m, C.ink2)
    end

    theme.label(pc, 20, 200, 100, 16, "光谱示意", SZ.xs, C.ink3)
    for i = 1, 24 do
        ui.bands[i] = theme.box(pc, 20 + (i - 1) * 21, 220, 19, 20, C.panel2, 3)
    end

    ------------------------------------------------------------------
    -- 右：预设配方
    ------------------------------------------------------------------
    local rc = theme.card(p, 592, 66, 416, 320)
    theme.label(rc, 16, 10, 200, 22, "预设配方", SZ.m, C.ink)
    theme.label(rc, 16, 10, 416 - 32, 22, "点击即应用", SZ.xs, C.ink3, RT)

    for i, pr in ipairs(conf.spectrum.presets) do
        local y = 40 + (i - 1) * 54
        local card = theme.card(rc, 16, y, 384, 46, {
            color = C.panel2, radius = 8, border_color = C.line, border_width = 1,
            on_click = function()
                if not alive then return end
                sim.apply_preset(i)
                sync_sliders()
                refresh_spec()
                app.toast("已切换到「" .. pr.name .. "」", C.cyan)
            end,
        })
        theme.label(card, 12, 6, 80, 20, pr.name, SZ.m, C.ink)
        theme.label(card, 12, 26, 250, 16, pr.note or "", SZ.xs, C.ink3)

        -- 三色配比小条
        local dots = {}
        for k, ch in ipairs(conf.spectrum.channels) do
            dots[k] = app.dot(card, 276 + (k - 1) * 18, 19, 5, theme.mix(ch.color, C.bg0, 0.55))
        end
        local chip = theme.label(card, 330, 21, 44, 16, "", SZ.xs, C.ink3, RT)

        ui.cards[i] = { card = card, dots = dots, chip = chip, preset = pr }
    end

    ------------------------------------------------------------------
    -- 右：日夜节律
    ------------------------------------------------------------------
    local dc = theme.card(p, 592, 398, 416, 186)
    theme.label(dc, 16, 10, 200, 22, "日夜节律", SZ.m, C.ink)
    theme.label(dc, 16, 10, 416 - 32, 22, "日出 06:30 · 日落 19:00", SZ.xs, C.ink3, RT)

    ui.curve = theme.shape(dc, 16, 38, 384, 92, {})
    for i = 0, 4 do
        theme.label(dc, 16 + i * 88, 132, 30, 16, tostring(i * 6), SZ.xs, C.ink3,
            i == 0 and L or (i == 4 and RT or CT))
    end
    ui.day_state = theme.label(dc, 16, 152, 220, 20, "", SZ.s, C.gold)
    ui.day_span = theme.label(dc, 16, 152, 416 - 32, 20, "", SZ.xs, C.ink3, RT)

    ------------------------------------------------------------------
    -- 刷新逻辑
    ------------------------------------------------------------------
    function sync_sliders()
        local sp = sim.spectrum()
        for i, row in ipairs(ui.rows) do
            if row.slider then
                pcall(function() row.slider:set_value(sp[row.ch.key] or 0, false) end)
            end
        end
    end

    function refresh_spec()
        if not alive or not ready then return end
        local sp = sim.spectrum()
        local sig = sp.blue .. "/" .. sp.white .. "/" .. sp.uv
        if sig == last_sig then return end
        last_sig = sig

        for i, row in ipairs(ui.rows) do
            local v = sp[row.ch.key] or 0
            row.bar.set(v / 100, row.ch.color)
            row.pct:set_text(v .. "%")
            row.pct:set_color(v > 0 and C.ink or C.ink3)
        end

        local total = sp.blue + sp.white + sp.uv
        local strength = math.min(1, total / 300)
        local sf, gl = art.color_from_spectrum(sp.blue, sp.white, sp.uv)

        -- 混光圆：外圈光晕 + 内圈实色
        ui.orb:set_color(theme.mix(C.panel, gl, 0.55))
        ui.orb:set_border_color(theme.mix(C.line2, gl, 0.85), 2)
        ui.orb_core:set_color(theme.mix(C.bg0, sf, 0.55 + 0.45 * strength))

        local name = sim.spectrum_preset_name()
        ui.preset_name:set_text("当前：" .. name)
        ui.big_name:set_text(name)

        local white = sp.white or 0
        local mood
        if total <= 2 then
            mood = "全通道熄灭 · 珊瑚休眠"
        elseif white >= 60 then
            mood = "全光谱白光为主 · 生长与观感兼顾"
        elseif white > 0 and (sp.blue or 0) / white >= 1.6 then
            mood = "高蓝光配方 · 荧光显色突出"
        else
            mood = "混合配方 · 蓝白平衡，光谱温和"
        end
        ui.mood:set_text(mood)

        ui.grid[1]:set_text(math.floor(total / 3 + 0.5) .. "%")
        ui.grid[2]:set_text(math.floor(total * 1.05) .. " W")
        ui.grid[3]:set_text(white > 0 and string.format("%.2f", sp.blue / white) or "—")
        ui.grid[4]:set_text(total > 0 and (math.floor(sp.uv / total * 100) .. "%") or "0%")
        ui.total:set_text(string.format("蓝 %d · 白 %d · UV %d", sp.blue, sp.white, sp.uv))

        -- 光谱示意条
        for i = 1, #ui.bands do
            local lit = 0.14 + 0.86 * strength
            ui.bands[i]:set_color(theme.mix(C.panel2, wave_color(i), lit))
        end

        -- 预设高亮
        for i, it in ipairs(ui.cards) do
            local on = (it.preset.name == name)
            it.card:set_border_color(on and C.cyan or C.line, 1)
            it.card:set_color(on and theme.mix(C.panel2, C.cyan, 0.10) or C.panel2)
            it.chip:set_text(on and "使用中" or "")
            it.chip:set_color(on and C.cyan or C.ink3)
            for k, ch in ipairs(conf.spectrum.channels) do
                local v = (it.preset[ch.key] or 0) / 100
                app.dot_paint(it.dots[k], 5, theme.mix(C.panel3, ch.color, 0.25 + 0.75 * v))
            end
        end
    end

    function refresh_day()
        if not alive then return end
        local phase = sim.day_phase()
        local key = string.format("%.3f", phase)
        if key == last_day then return end
        last_day = key

        local hist = {}
        for i = 1, 48 do
            hist[i] = sim.light_curve((i - 1) / 47) * 100
        end
        local items = art.waveform_items(384, 92, hist, {
            color = C.gold, min = 0, max = 100, grid = 2, dash = true,
        })
        local x = math.floor(phase * 384)
        items[#items + 1] = { type = "line", x1 = x, y1 = 4, x2 = x, y2 = 88,
            color = C.cyan, width = 1, opacity = 160 }
        pcall(function() ui.curve:set_items(items) end)

        local cur = sim.light_curve(phase)
        if cur <= 0.01 then
            local to_sunrise = (phase < 6.5 / 24) and (6.5 - phase * 24) or (24 - phase * 24 + 6.5)
            ui.day_state:set_text("熄灯 · 夜间模式")
            ui.day_state:set_color(C.violet)
            ui.day_span:set_text(string.format("距离日出 %.1f 小时", to_sunrise))
        else
            local on_h = (phase - 6.5 / 24) * 24
            ui.day_state:set_text(string.format("当前光照 %d%%", math.floor(cur * 100 + 0.5)))
            ui.day_state:set_color(C.gold)
            ui.day_span:set_text(string.format("已开灯 %.1f h / 12.5 h", on_h))
        end
    end

    ready = true
    sync_sliders()
    refresh_spec()
    refresh_day()

    return {
        refresh = function()
            if not alive then return end
            clock:set_text(sim.clock())
            date:set_text(sim.date_text())
            refresh_spec()
            refresh_day()
        end,
        destroy = function()
            alive = false
            ready = false
        end,
    }
end

return M
