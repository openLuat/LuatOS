--[[
@module  ui_snow
@summary 雪况页：雪道雪深、造雪机、造雪气象窗口、24h 雪深趋势、雪场提示
@version 1.0
@date    2026.11.06
]]
local theme = require "theme"
local art   = require "art"
local sim   = require "sim"
local conf  = require "conf"

local C = theme.C
local SZ = theme.SZ
local A_LEFT, A_CENTER, A_RIGHT = theme.align_left(), theme.align_center(), theme.align_right()

local M = {}

local L = {
    slopes = { x = 16,  y = 8,   w = 560, h = 306 },
    guns   = { x = 16,  y = 322, w = 560, h = 214 },
    window = { x = 592, y = 8,   w = 416, h = 140 },
    chart  = { x = 592, y = 156, w = 416, h = 200 },
    tips   = { x = 592, y = 364, w = 416, h = 172 },
}

local function toast(text, level)
    local ok, app = pcall(require, "app")
    if ok and app and app.toast then app.toast(text, level) end
end

function M.create(root)
    local page = { root = root, alive = true }

    -- ==================== 雪道雪况 ====================
    local sc = theme.card(root, L.slopes.x, L.slopes.y, L.slopes.w, L.slopes.h, { radius = 14 })
    theme.label(sc, 16, 10, 200, 20, "雪道雪况", SZ.m, C.ink)
    local s_sum = theme.label(sc, 300, 12, 244, 16, "", SZ.xs, C.ink3, A_RIGHT)
    theme.hline(sc, 16, 32, 528, C.line)

    local rows = {}
    for i, def in ipairs(conf.slopes) do
        local y = 40 + (i - 1) * 64
        local name = theme.label(sc, 16, y, 96, 20, def.name, SZ.m, C.ink)
        local level = theme.chip(sc, 108, y + 1, 52, 18, def.level, C.ink2, C.panel2, SZ.xs)
        local state = theme.chip(sc, 168, y + 1, 58, 18, "开放", C.bg0, C.green, SZ.xs)

        local depth = theme.label(sc, 316, y - 4, 96, 28, "--", SZ.l, C.snow, A_RIGHT)
        local unit = theme.label(sc, 418, y + 4, 26, 16, "cm", SZ.xs, C.ink3)
        local target = theme.label(sc, 448, y + 2, 96, 16, "", SZ.xs, C.ink3, A_RIGHT)

        local bar = theme.segbar(sc, 16, y + 32, 300, 10, 24, C.blue, C.panel3, 3)
        local meta = theme.label(sc, 16, y + 46, 420, 14, "", SZ.xs, C.ink3)

        local row = { def = def, name = name, level = level, state = state,
                      depth = depth, target = target, bar = bar, meta = meta }

        local hit = theme.box(sc, 8, y - 2, 536, 58, C.panel, 8, 0)
        hit:set_on_click(function()
            local s = sim.slope(def.key)
            toast(string.format("%s · 雪深 %.0f cm · 目标 %.0f cm · 压雪 %s",
                def.name, s.depth, s.target, def.groom), "ok")
        end)
        hit:set_hidden(true)   -- 仅用于点击热区，不显示

        rows[i] = row
    end
    page.rows = rows
    page.s_sum = s_sum

    -- ==================== 造雪机 ====================
    local gc = theme.card(root, L.guns.x, L.guns.y, L.guns.w, L.guns.h, { radius = 14 })
    theme.label(gc, 16, 10, 200, 20, "造雪机", SZ.m, C.ink)
    local g_sum = theme.label(gc, 250, 12, 294, 16, "", SZ.xs, C.ink3, A_RIGHT)

    local guns = {}
    for i, def in ipairs(conf.guns) do
        local w, h, gap = 172, 152, 10
        local x = 16 + (i - 1) * (w + gap)
        local y = 36
        local box = theme.box(gc, x, y, w, h, C.panel2, 10)
        art.icon(gc, "gun", x + 10, y + 10, 18, C.blue)
        theme.label(gc, x + 34, y + 8, 100, 20, def.name, SZ.s, C.ink)

        local st_text = theme.label(gc, x + 10, y + 34, 152, 16, "", SZ.xs, C.ink3)
        local out = theme.label(gc, x + 10, y + 54, 152, 26, "--", SZ.l, C.ice)
        theme.label(gc, x + 104, y + 62, 58, 14, "cm/h", SZ.xs, C.ink3, A_RIGHT)

        theme.label(gc, x + 10, y + 82, 60, 14, "喷嘴", SZ.xs, C.ink3)
        local nozzle_val = theme.label(gc, x + 112, y + 82, 50, 14, "", SZ.xs, C.ink2, A_RIGHT)

        local slider = theme.slider({
            parent = gc, x = x + 10, y = y + 96, w = 152, h = 22,
            min = 0, max = 100, value = sim.gun(def.key).nozzle,
            on_change = function(self)
                local v = 0
                pcall(function() v = self:get_value() end)
                sim.set_nozzle(def.key, v)
                page.refresh()
            end,
            style = {
                bg_color = C.panel3, bg_opa = 255, border_width = 0, radius = 7, pad = 2,
                indicator_color = C.blue, knob_color = C.snow, knob_border_color = C.blue,
                knob_border_width = 2,
            },
        })

        local btn = theme.ghost(gc, x + 10, y + 122, 152, 24, "启动", {
            size = SZ.xs,
            on_click = function()
                sim.toggle_gun(def.key)
                page.refresh()
            end,
        })

        guns[i] = { def = def, box = box, st = st_text, out = out, nozzle = nozzle_val,
                    slider = slider, btn = btn }
    end
    page.guns = guns
    page.g_sum = g_sum

    -- ==================== 气象窗口 ====================
    local wc = theme.card(root, L.window.x, L.window.y, L.window.w, L.window.h, { radius = 14 })
    theme.label(wc, 16, 10, 220, 20, "造雪气象窗口", SZ.m, C.ink)
    local w_chip = theme.chip(wc, 288, 11, 112, 20, "条件良好", C.bg0, C.green, SZ.xs)
    theme.hline(wc, 16, 36, 384, C.line)

    local cells = {}
    local CELL = { { cap = "干球", unit = "℃" }, { cap = "湿球", unit = "℃" }, { cap = "湿度", unit = "%" } }
    for i, d in ipairs(CELL) do
        local x = 16 + (i - 1) * 128
        theme.label(wc, x, 44, 110, 14, d.cap, SZ.xs, C.ink3)
        local v = theme.label(wc, x, 60, 110, 30, "--", SZ.l, C.ink)
        theme.label(wc, x + 76, 70, 34, 14, d.unit, SZ.xs, C.ink3)
        cells[i] = { def = d, val = v }
    end

    local btn_snow = theme.button(wc, 16, 98, 182, 30, "人工增雪 2 小时", {
        size = SZ.xs,
        bg = C.blue, fg = C.bg0,
        on_click = function()
            sim.burst()
            toast("已启动人工增雪，持续 2 小时", "ok")
            page.refresh()
        end,
    })
    local btn_groom = theme.ghost(wc, 210, 98, 190, 30, "一键压雪", {
        size = SZ.xs,
        on_click = function()
            sim.groom()
            toast("压雪作业完成，雪面已平整", "ok")
            page.refresh()
        end,
    })

    -- ==================== 趋势 ====================
    local tc = theme.card(root, L.chart.x, L.chart.y, L.chart.w, L.chart.h, { radius = 14 })
    theme.label(tc, 16, 10, 220, 20, "平均雪深趋势", SZ.m, C.ink)
    local chart_sub = theme.label(tc, 240, 12, 160, 16, "", SZ.xs, C.ink3, A_RIGHT)
    local chart = theme.shape(tc, 16, 40, 384, 118, {})

    theme.hline(tc, 16, 164, 384, C.line)
    local foot = {}
    for i, cap in ipairs({ "当前雪深", "今日补雪", "融雪速率" }) do
        local x = 16 + (i - 1) * 128
        theme.label(tc, x, 170, 120, 14, cap, SZ.xs, C.ink3)
        foot[i] = theme.label(tc, x, 184, 120, 16, "--", SZ.s, C.ink)
    end
    page.foot = foot
    page.chart = chart
    page.chart_sub = chart_sub
    page.btn_snow = btn_snow
    page.btn_groom = btn_groom
    page.w_chip = w_chip
    page.cells = cells

    -- ==================== 雪场提示 ====================
    local tipc = theme.card(root, L.tips.x, L.tips.y, L.tips.w, L.tips.h, { radius = 14 })
    theme.label(tipc, 16, 10, 220, 20, "雪面作业提示", SZ.m, C.ink)
    local tip_clock = theme.label(tipc, 240, 12, 160, 16, "", SZ.xs, C.ink3, A_RIGHT)
    theme.hline(tipc, 16, 34, 384, C.line)
    local tips = {}
    for i = 1, 4 do
        local y = 44 + (i - 1) * 32
        local dot = theme.box(tipc, 16, y + 6, 5, 5, C.ice, 2)
        tips[i] = { dot = dot, text = theme.label(tipc, 28, y, 372, 16, "", SZ.xs, C.ink2) }
    end
    page.tips = tips
    page.tip_clock = tip_clock

    -- ==================== 刷新 ====================
    local function refresh()
        if not page.alive then return end
        local open, total = sim.open_slopes()

        -- 雪道
        for i, row in ipairs(page.rows) do
            local s = sim.slope(row.def.key)
            row.depth:set_text(string.format("%.0f", s.depth))
            row.depth:set_color(s.depth < s.target * 0.55 and C.red
                or (s.depth < s.target * 0.8 and C.gold or C.snow))
            row.target:set_text(string.format("目标 %.0f", s.target))
            row.bar.set(math.min(1, s.depth / math.max(1, s.target * 1.15)),
                s.depth < s.target * 0.55 and C.red or (s.depth < s.target * 0.8 and C.gold or C.blue))
            row.state.set(s.open and "开放" or "封闭", s.open and C.bg0 or C.gold)
            row.state.box:set_color(s.open and C.green or C.panel3)
            row.meta:set_text(string.format("全长 %d m · 坡度 %d° · 压雪 %s",
                theme.n(row.def.len), theme.n(row.def.grad), tostring(row.def.groom)))
        end
        page.s_sum:set_text(string.format("%d / %d 条开放 · 平均 %.0f cm", open, total, sim.avg_depth()))

        -- 造雪机
        local on_count, total_out = 0, 0
        for i, g in ipairs(page.guns) do
            local d = sim.gun(g.def.key)
            if d.on and not d.fault then on_count = on_count + 1 end
            total_out = total_out + d.output
            if d.fault then
                g.st:set_text("水压故障 · 待复位")
                g.st:set_color(C.red)
                g.btn:set_text("复位")
                g.out:set_text("0.0")
                g.out:set_color(C.ink3)
            elseif d.on then
                g.st:set_text(d.output > 0 and "造雪中" or "待温等待")
                g.st:set_color(d.output > 0 and C.ice or C.gold)
                g.btn:set_text("停止")
                g.out:set_text(string.format("%.1f", d.output * 0.1))
                g.out:set_color(d.output > 0 and C.ice or C.ink3)
            else
                g.st:set_text("已停止")
                g.st:set_color(C.ink3)
                g.btn:set_text("启动")
                g.out:set_text("0.0")
                g.out:set_color(C.ink3)
            end
            g.nozzle:set_text(string.format("%d %%", theme.n(d.nozzle)))
            g.box:set_border_color(d.on and C.line2 or C.line, 1)
        end
        page.g_sum:set_text(string.format("%d / 3 台运行 · 产雪 %.1f cm/h", on_count, total_out * 0.1))

        -- 气象窗口
        local w = sim.weather()
        page.cells[1].val:set_text(string.format("%.1f", w.temp))
        page.cells[2].val:set_text(string.format("%.1f", w.wetbulb))
        page.cells[2].val:set_color(w.wetbulb <= -2 and C.ice or C.gold)
        page.cells[3].val:set_text(string.format("%d", math.floor(w.hum + 0.5)))
        local can = w.wetbulb <= -2
        page.w_chip.set(can and "具备造雪条件" or "湿球偏高", can and C.bg0 or C.bg0)
        page.w_chip.box:set_color(can and C.green or C.gold)

        -- 趋势
        local hist = sim.history("depth")
        pcall(function()
            page.chart:set_items(art.waveform_items(384, 118, hist, {
                color = C.blue, min = 0, max = 100, band = { lo = 40, hi = 100 },
            }))
        end)
        page.chart_sub:set_text(string.format("近 %d 个采样点", #hist))
        page.foot[1]:set_text(string.format("%.0f cm", sim.avg_depth()))
        local added = 0
        for _, s in ipairs(sim.slopes()) do
            added = added + math.max(0, s.depth - s.target * 0.82)
        end
        page.foot[2]:set_text(string.format("%.1f cm", added))
        page.foot[3]:set_text(string.format("%.2f cm/h", math.max(0, w.temp) * 0.06))
        page.tip_clock:set_text(sim.clock() .. " " .. sim.phase_text())

        -- 提示
        local list = {}
        local dry = w.wetbulb > -2
        list[#list + 1] = { dry and "湿球温度偏高，造雪效率下降" or "湿球温度达标，造雪机可满负荷", dry and "warn" or "ok" }
        for _, s in ipairs(sim.slopes()) do
            if s.depth < s.target * 0.6 then
                list[#list + 1] = { string.format("%s 雪深 %.0f cm，低于警戒线", s.name, s.depth), "danger" }
                break
            end
        end
        if #list < 2 then
            list[#list + 1] = { string.format("上次压雪 %s，建议 2 小时内复压", sim.data.groom_at), "ok" }
        end
        if #list < 3 then
            list[#list + 1] = { string.format("A 线运力 %d 人/小时，队伍 %d 人",
                theme.n(sim.lift("a").capacity), theme.n(sim.data.queue)), "ok" }
        end
        if #list < 4 then
            list[#list + 1] = { string.format("今日运送 %d 人次，雪面承载正常", theme.n(sim.data.visitors)), "ok" }
        end
        for i, row in ipairs(page.tips) do
            local t = list[i]
            if t then
                row.text:set_text(theme.fit(t[1], 26))
                row.text:set_color(t[2] == "danger" and C.red or (t[2] == "warn" and C.gold or C.ink2))
                row.dot:set_color(theme.state_color(t[2]))
                row.dot:set_hidden(false)
            else
                row.text:set_text("")
                row.dot:set_hidden(true)
            end
        end
    end
    page.refresh = refresh

    function page.destroy()
        page.alive = false
    end

    refresh()
    return page
end

return M
