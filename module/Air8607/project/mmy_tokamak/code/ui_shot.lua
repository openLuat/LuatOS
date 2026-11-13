--[[
@module  ui_shot
@summary 放电页：Ip / 辅助加热波形 + 阶段推进表 + 加热配置 + Q 环表 + 控制滑块
@version 1.0
@date    2026.11.12
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
    wave    = { x = 14,  y = 10,  w = 610, h = 322 },
    timeline = { x = 14, y = 344, w = 610, h = 192 },
    heat    = { x = 636, y = 10,  w = 374, h = 206 },
    q       = { x = 636, y = 228, w = 374, h = 140 },
    ctrl    = { x = 636, y = 380, w = 374, h = 156 },
}

local CHART = { x = 46, y = 34, w = 500, h = 236 }

local function mk_slider(parent, x, y, w, h, min, max, value, color, cb)
    return theme.slider({
        parent = parent, x = x, y = y, w = w, h = h,
        min = min, max = max, value = value,
        style = {
            bg_color = C.panel3, bg_opa = 255, border_width = 0,
            indicator_color = color, indicator_opa = 255,
            knob_color = color, knob_opa = 255,
            knob_border_color = color, knob_border_width = 0,
            radius = 99, pad = 3,
        },
        on_change = cb,
    })
end

function M.create(root)
    local page = { root = root, alive = true }

    -- ==================== 波形 ====================
    local wc = theme.card(root, L.wave.x, L.wave.y, L.wave.w, L.wave.h, { radius = 14 })
    theme.label(wc, 14, 8, 260, 18, "等离子体电流 / 辅助加热", SZ.s, C.ink)
    local wclock = theme.label(wc, 300, 9, 130, 16, "", SZ.xs, C.ink3, A_RIGHT)

    art.dot(wc, 446, 16, 3, C.plasma)
    theme.label(wc, 454, 8, 40, 14, "Ip", SZ.xs, C.ink2)
    art.dot(wc, 490, 16, 3, C.coral)
    theme.label(wc, 498, 8, 60, 14, "Paux", SZ.xs, C.ink2)
    theme.label(wc, 544, 8, 52, 14, "MA / MW", SZ.xs, C.ink3, A_RIGHT)

    local chart = theme.shape(wc, CHART.x, CHART.y, CHART.w, CHART.h, {})
    page.chart = chart

    -- 左轴：Ip
    for i = 0, 3 do
        local y = CHART.y + 12 + (CHART.h - 28) * i / 3
        theme.label(wc, 8, y - 7, 34, 14, string.format("%.1f", 2.0 - i * 2 / 3), SZ.xs, C.ink3, A_RIGHT)
    end
    -- 右轴：Paux
    for i = 0, 3 do
        local y = CHART.y + 12 + (CHART.h - 28) * i / 3
        theme.label(wc, 552, y - 7, 42, 14, string.format("%d", 30 - i * 10), SZ.xs, C.ink3)
    end

    theme.label(wc, CHART.x, 278, 120, 14, "60 s 前", SZ.xs, C.ink3)
    theme.label(wc, CHART.x + CHART.w - 80, 278, 80, 14, "当前", SZ.xs, C.ink3, A_RIGHT)
    local hint = theme.label(wc, 14, 298, 582, 14,
        "粉色 = 等离子体电流（左轴）   珊瑚 = 辅助加热总功率（右轴）   竖向色带 = 放电阶段", SZ.xs, C.ink3)
    page.wclock = wclock

    -- ==================== 阶段表 ====================
    local tc = theme.card(root, L.timeline.x, L.timeline.y, L.timeline.w, L.timeline.h, { radius = 14 })
    theme.label(tc, 14, 8, 160, 18, "放电阶段", SZ.s, C.ink)
    local tinfo = theme.label(tc, 220, 9, 376, 16, "", SZ.xs, C.ink3, A_RIGHT)

    local rows = {}
    for i, p in ipairs(conf.phases) do
        local y = 34 + (i - 1) * 21
        local tick = theme.box(tc, 14, y + 4, 3, 12, p.color, 2)
        theme.label(tc, 24, y + 2, 92, 16, p.name, SZ.xs, C.ink2)
        theme.label(tc, 116, y + 2, 40, 16, string.format("%d s", p.dur), SZ.xs, C.ink3)
        local bar = theme.bar(tc, 160, y + 6, 300, 4, 0, p.color, C.panel3)
        local st = theme.label(tc, 470, y + 1, 126, 16, "", SZ.xs, C.ink3, A_RIGHT)
        rows[i] = { def = p, tick = tick, bar = bar, st = st }
    end
    page.ts_rows = rows
    page.tinfo = tinfo

    -- ==================== 加热配置 ====================
    local hc = theme.card(root, L.heat.x, L.heat.y, L.heat.w, L.heat.h, { radius = 14 })
    theme.label(hc, 14, 8, 160, 18, "辅助加热", SZ.s, C.ink)
    local htotal = theme.label(hc, 220, 9, 140, 16, "", SZ.xs, C.ink3, A_RIGHT)

    local hrows = {}
    for i, h in ipairs(conf.heating) do
        local y = 34 + (i - 1) * 50
        local box = theme.box(hc, 12, y, 350, 44, C.panel2, 9)
        theme.label(hc, 22, y + 5, 110, 16, h.name, SZ.s, C.ink)
        local val = theme.label(hc, 254, y + 4, 96, 18, "", SZ.m, C.ink, A_RIGHT)
        local bar = theme.bar(hc, 22, y + 28, 328, 5, 0, h.color, C.panel3)
        local dot = theme.box(hc, 336, y + 9, 6, 6, C.green, 3)
        box:set_on_click(function()
            sim.toggle_device(h.key)
            page.refresh()
        end)
        hrows[i] = { def = h, box = box, val = val, bar = bar, dot = dot }
    end
    page.hrows = hrows
    page.htotal = htotal

    -- ==================== Q 环表 ====================
    local qc = theme.card(root, L.q.x, L.q.y, L.q.w, L.q.h, { radius = 14 })
    theme.label(qc, 14, 8, 160, 18, "能量增益", SZ.s, C.ink)
    local qmode = theme.label(qc, 220, 9, 140, 16, "", SZ.xs, C.ink3, A_RIGHT)

    local ring = theme.shape(qc, 16, 22, 104, 104, art.ring_items(104, 0, C.plasma, C.panel3, 7))
    local qval = theme.label(qc, 16, 56, 104, 30, "0.00", SZ.xl, C.ink, A_CENTER)
    theme.label(qc, 16, 86, 104, 14, "Q = Pfus / Paux", SZ.xs, C.ink3, A_CENTER)
    page.ring = ring
    page.qval = qval
    page.qmode = qmode

    local litres = {}
    local QROW = {
        { cap = "聚变功率", unit = "MW" },
        { cap = "辅助加热", unit = "MW" },
        { cap = "增益余量", unit = "" },
    }
    for i, d in ipairs(QROW) do
        local y = 34 + (i - 1) * 30
        theme.label(qc, 136, y, 100, 16, d.cap, SZ.xs, C.ink3)
        local v = theme.label(qc, 240, y - 2, 100, 18, "--", SZ.m, C.ink, A_RIGHT)
        litres[i] = { def = d, val = v }
    end
    page.qrows = litres

    -- ==================== 控制 ====================
    local cc = theme.card(root, L.ctrl.x, L.ctrl.y, L.ctrl.w, L.ctrl.h, { radius = 14 })
    theme.label(cc, 14, 8, 160, 18, "放电控制", SZ.s, C.ink)
    local cstate = theme.label(cc, 220, 9, 140, 16, "", SZ.xs, C.ink3, A_RIGHT)

    theme.label(cc, 14, 32, 120, 14, "目标电流", SZ.xs, C.ink3)
    local ip_lb = theme.label(cc, 250, 30, 110, 14, "1.20 MA", SZ.xs, C.ink2, A_RIGHT)
    local sl_ip = mk_slider(cc, 14, 46, 346, 26, 60, 200, 120, C.ion, function(self)
        local v = self:get_value()
        sim.set_target_ip(v / 100)
        ip_lb:set_text(string.format("%.2f MA", v / 100))
    end)

    theme.label(cc, 14, 74, 120, 14, "加热总功率", SZ.xs, C.ink3)
    local ht_lb = theme.label(cc, 250, 72, 110, 14, "15.0 MW", SZ.xs, C.ink2, A_RIGHT)
    local sl_ht = mk_slider(cc, 14, 88, 346, 26, 5, 30, 15, C.coral, function(self)
        local v = self:get_value()
        sim.set_heat(v)
        ht_lb:set_text(string.format("%.1f MW", v))
    end)

    local btn_abort = theme.ghost(cc, 14, 120, 166, 26, "终止放电", {
        fg = C.red,
        border = theme.mix(C.red, C.panel, 0.45),
        on_click = function()
            sim.abort()
            page.refresh()
        end,
    })
    local btn_next = theme.button(cc, 194, 120, 166, 26, "下一炮", {
        bg = C.plasma, size = SZ.s,
        on_click = function()
            sim.next_shot()
            page.refresh()
        end,
    })
    page.cstate = cstate

    -- ==================== 刷新 ====================
    local function phase_bands(p)
        -- 从“当前时刻”向左反推每一段的 x 区间（60 个样本 = 60 s）
        local bands = {}
        local ago = p.progress * p.dur      -- 当前段已走过的样本数
        for i = p.index, 1, -1 do
            local d = conf.phases[i]
            local from = math.max(0, 1 - (ago + d.dur) / conf.sim.history)
            local to = math.max(0, 1 - ago / conf.sim.history)
            if to > from then
                bands[#bands + 1] = { from = from, to = to, color = d.color, opacity = (i == p.index) and 30 or 14 }
            end
            ago = ago + d.dur
            if ago > conf.sim.history then break end
        end
        return bands
    end

    local function refresh()
        if not page.alive then return end
        local s = sim.summary()
        local p = sim.phase()

        local series = {
            { data = s.hist.paux, color = C.coral, min = 0, max = 30, width = 1, opacity = 220 },
            { data = s.hist.ip,   color = C.plasma, min = 0, max = 2.0, width = 2, area = true, area_opa = 18 },
        }
        pcall(function()
            page.chart:set_items(art.curve_items(CHART.w, CHART.h, series, {
                pad_top = 12, pad_bottom = 16, grid = 3, bands = phase_bands(p),
                -- 波形每秒重建一次全部图元，节点密度直接决定开销：
                -- 6 px 一段在 1024 宽屏上仍然是连续曲线，图元数量少四成
                dx = 6, fill_dx = 12, sample = 6,
            }))
        end)

        page.wclock:set_text(string.format("T+ %d s", theme.n(p.t_plus)))

        -- 阶段表
        local remain = math.max(0, (conf.phases[p.index].dur - p.progress * conf.phases[p.index].dur))
        page.tinfo:set_text(string.format("%s，剩余 %.0f s", p.name, remain))
        for i, row in ipairs(page.ts_rows) do
            local v, st, col = 0, "等待", C.ink3
            if i < p.index then
                v, st, col = 100, "完成", theme.mix(row.def.color, C.bg1, 0.5)
            elseif i == p.index then
                v = p.progress * 100
                st = string.format("%.0f%%", v)
                col = row.def.color
            end
            if row.bar then theme.setbar(row.bar, v) end
            row.st:set_text(st)
            row.st:set_color(col)
            row.tick:set_color(col)
        end

        -- 加热
        local hs = sim.heating()
        local total = 0
        for i, r in ipairs(page.hrows) do
            local h = hs[i]
            total = total + h.mw
            r.val:set_text(string.format("%.1f MW", h.mw))
            r.val:set_color(h.on and C.ink or C.ink3)
            if r.bar then theme.setbar(r.bar, h.on and (h.base / 12 * 100) or 0) end
            r.dot:set_color(h.on and C.green or C.ink3)
            r.box:set_color(h.on and C.panel2 or theme.mix(C.panel2, C.bg0, 0.35))
        end
        page.htotal:set_text(string.format("%.1f MW", total))

        -- Q
        local qpct = theme.clamp(s.q / 6, 0, 1)
        pcall(function()
            page.ring:set_items(art.ring_items(104, qpct, s.q > 1 and C.green or C.plasma, C.panel3, 7))
        end)
        page.qval:set_text(string.format("%.2f", s.q))
        page.qval:set_color(s.q > 1 and C.green or C.ink)
        page.qmode:set_text(s.q > 5 and "燃烧等离子体" or (s.q > 1 and "净能量增益" or "驱动模式"))
        page.qmode:set_color(s.q > 1 and C.green or C.ink3)

        local margin = s.pfus - s.paux
        local qv = {
            string.format("%.1f", s.pfus),
            string.format("%.1f", s.paux),
            string.format("%+.1f", margin),
        }
        for i, r in ipairs(page.qrows) do
            r.val:set_text(qv[i])
            if i == 3 then
                r.val:set_color(margin > 0 and C.green or C.ink3)
            end
        end

        -- 控制
        page.cstate:set_text(string.format("%s，%.0f%%", p.name, p.progress * 100))
        page.cstate:set_color(p.color)
    end
    page.refresh = refresh

    local function slow() end
    page.slow = slow

    local function frame() end
    page.frame = frame

    function page.destroy()
        page.alive = false
    end

    refresh()
    return page
end

return M
