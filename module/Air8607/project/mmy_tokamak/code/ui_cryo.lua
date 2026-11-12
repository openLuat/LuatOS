--[[
@module  ui_cryo
@summary 低温真空页：氦回路流程 / 冷屏温度 / 氦库存 / 真空与 RGA
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
    cryo   = { x = 14,  y = 10,  w = 620, h = 330 },
    vacuum = { x = 14,  y = 352, w = 620, h = 184 },
    temps  = { x = 646, y = 10,  w = 364, h = 240 },
    helium = { x = 646, y = 262, w = 364, h = 130 },
    ctrl   = { x = 646, y = 404, w = 364, h = 132 },
}

-- 流程节点（卡片局部坐标）
local NODE = {
    comp  = { x = 24,  y = 74,  w = 110, h = 64 },
    cold  = { x = 182, y = 54,  w = 118, h = 104 },
    jt    = { x = 348, y = 74,  w = 92,  h = 64 },
    shield = { x = 486, y = 54, w = 112, h = 104 },
}

-- 管路：供气在上，回流在下
local PIPE = {
    { 134, 106, 182, 106 },
    { 300, 106, 348, 106 },
    { 440, 106, 486, 106 },
    { 542, 158, 542, 226 },
    { 542, 226, 79, 226 },
    { 79, 226, 79, 138 },
}

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

local function pipe_items()
    local items = {}
    for _, s in ipairs(PIPE) do
        items[#items + 1] = {
            type = "line", x1 = s[1], y1 = s[2], x2 = s[3], y2 = s[4],
            color = 0x24304A, width = 5, opacity = 255,
            round_start = true, round_end = true,
        }
    end
    for _, s in ipairs(PIPE) do
        items[#items + 1] = {
            type = "line", x1 = s[1], y1 = s[2], x2 = s[3], y2 = s[4],
            color = 0x0B1120, width = 2, opacity = 255,
            round_start = true, round_end = true,
        }
    end
    return items
end

local function box_items(w, h, accent)
    local items = {}
    items[#items + 1] = {
        type = "rect", x = 0, y = 0, w = w, h = h, radius = 8,
        color = 0x151C2E, width = 1, opacity = 255,
        fill = true, fill_color = 0x151C2E, fill_opacity = 255,
    }
    items[#items + 1] = {
        type = "rect", x = 0, y = 0, w = 3, h = h, radius = 2,
        color = accent, width = 1,
        fill = true, fill_color = accent, fill_opacity = 220,
    }
    return items
end

function M.create(root)
    local page = { root = root, alive = true }

    -- ==================== 氦回路 ====================
    local cc = theme.card(root, L.cryo.x, L.cryo.y, L.cryo.w, L.cryo.h, { radius = 14 })
    theme.label(cc, 16, 8, 240, 18, "氦回路，4.5 K 低温系统", SZ.s, C.ink)
    local cstate = theme.label(cc, 300, 9, 300, 16, "", SZ.xs, C.ink3, A_RIGHT)

    theme.shape(cc, 0, 0, L.cryo.w, L.cryo.h, pipe_items())

    -- 节点
    local nodes = {
        { key = "comp", def = NODE.comp, name = "压缩机站", sub = "", color = C.ion },
        { key = "cold", def = NODE.cold, name = "冷箱", sub = "", color = C.violet },
        { key = "jt",   def = NODE.jt,   name = "JT 节流阀", sub = "", color = C.plasma },
        { key = "shield", def = NODE.shield, name = "冷屏 / 磁体", sub = "", color = C.coral },
    }
    local vals = {}
    for i, n in ipairs(nodes) do
        local d = n.def
        theme.shape(cc, d.x, d.y, d.w, d.h, box_items(d.w, d.h, n.color))
        theme.label(cc, d.x + 12, d.y + 10, d.w - 18, 16, n.name, SZ.s, C.ink)
        vals[i] = theme.label(cc, d.x + 12, d.y + 32, d.w - 18, 20, "--", SZ.l, n.color)
        theme.label(cc, d.x + 12, d.y + d.h - 20, d.w - 18, 14, n.sub, SZ.xs, C.ink3)
    end
    page.node_vals = vals

    -- 流向说明
    theme.label(cc, 140, 88, 60, 12, "高压氦", SZ.xs, C.ink3)
    theme.label(cc, 306, 88, 60, 12, "膨胀", SZ.xs, C.ink3)
    theme.label(cc, 448, 88, 46, 12, "冷量", SZ.xs, C.ink3)
    theme.label(cc, 320, 206, 200, 12, "低压回流 → 压缩机", SZ.xs, C.ink3)

    -- 流动粒子
    local dots = {}
    for i, s in ipairs(PIPE) do
        for k = 1, 2 do
            dots[#dots + 1] = {
                seg = s,
                t = (k - 1) * 0.5 + (i % 3) * 0.12,
                speed = 0.012 + (i % 3) * 0.002,
                shape = art.dot(cc, s[1], s[2], 2, i == 6 and C.ion or C.violet),
            }
        end
    end
    page.dots = dots

    -- 底部三项
    local STAT = {
        { cap = "4.5 K 冷屏", key = "t4", unit = "K", color = C.ion },
        { cap = "80 K 冷屏", key = "t80", unit = "K", color = C.violet },
        { cap = "冷泵冷头", key = "tcold", unit = "K", color = C.coral },
    }
    local stats = {}
    for i, d in ipairs(STAT) do
        local x = 24 + (i - 1) * 196
        local box = theme.box(cc, x, 250, 180, 64, C.panel2, 10)
        art.icon(cc, "snow", x + 12, 264, 18, d.color)
        theme.label(cc, x + 38, 258, 130, 14, d.cap, SZ.xs, C.ink3)
        local v = theme.label(cc, x + 12, 278, 156, 28, "--", SZ.xl, C.ink)
        stats[i] = { def = d, val = v, box = box }
    end
    page.stats = stats

    -- ==================== 冷屏温度 ====================
    local tc = theme.card(root, L.temps.x, L.temps.y, L.temps.w, L.temps.h, { radius = 14 })
    theme.label(tc, 14, 8, 200, 18, "温度梯度", SZ.s, C.ink)
    local tavg = theme.label(tc, 200, 9, 148, 16, "", SZ.xs, C.ink3, A_RIGHT)

    local TEMP = {
        { key = "t4",    cap = "4.5 K 冷屏", max = 20,  color = C.ion,    unit = "K" },
        { key = "t80",   cap = "80 K 冷屏",  max = 120, color = C.violet, unit = "K" },
        { key = "tcold", cap = "冷泵冷头",   max = 40,  color = C.coral,  unit = "K" },
        { key = "tsupp", cap = "室温支撑",   max = 320, color = C.gold,   unit = "K" },
    }
    local therms = {}
    for i, d in ipairs(TEMP) do
        local x = 14 + (i - 1) * 86
        theme.label(tc, x, 30, 78, 14, d.cap, SZ.xs, C.ink3, A_CENTER)
        local v = theme.label(tc, x, 46, 78, 24, "--", SZ.l, C.ink, A_CENTER)
        local th = theme.shape(tc, x + 31, 76, 16, 130, art.thermo_items(16, 130, 0, d.color, C.panel3))
        theme.label(tc, x, 210, 78, 14, d.unit, SZ.xs, C.ink3, A_CENTER)
        therms[i] = { def = d, val = v, shape = th }
    end
    page.therms = therms
    page.tavg = tavg

    -- ==================== 氦库存 ====================
    local hc = theme.card(root, L.helium.x, L.helium.y, L.helium.w, L.helium.h, { radius = 14 })
    theme.label(hc, 14, 8, 160, 18, "液氦库存", SZ.s, C.ink)
    local he_val = theme.label(hc, 250, 6, 96, 16, "82%", SZ.xs, C.ink2, A_RIGHT)

    local he_big = theme.label(hc, 14, 30, 80, 44, "82", SZ.hero, C.ion)
    theme.label(hc, 96, 56, 30, 18, "%", SZ.s, C.ink3)
    local he_note = theme.label(hc, 140, 36, 208, 16, "", SZ.xs, C.ink3, A_RIGHT)
    local he_note2 = theme.label(hc, 140, 54, 208, 16, "", SZ.xs, C.ink3, A_RIGHT)

    local he_bar = theme.bar(hc, 14, 88, 336, 8, 82, C.ion, C.panel3)
    local he_mark = theme.box(hc, 14 + math.floor(336 * 0.30), 84, 2, 16, C.gold, 1, 200)
    theme.label(hc, 14, 102, 200, 14, "补液阈值 30%", SZ.xs, C.ink3)
    local he_rate = theme.label(hc, 250, 102, 100, 14, "", SZ.xs, C.ink3, A_RIGHT)
    page.he_big = he_big
    page.he_bar = he_bar
    page.he_val = he_val
    page.he_note = he_note
    page.he_note2 = he_note2
    page.he_rate = he_rate

    -- ==================== 控制 ====================
    local ctrl = theme.card(root, L.ctrl.x, L.ctrl.y, L.ctrl.w, L.ctrl.h, { radius = 14 })
    theme.label(ctrl, 14, 8, 160, 18, "低温控制", SZ.s, C.ink)
    local comp_lb = theme.label(ctrl, 250, 30, 100, 14, "82%", SZ.xs, C.ink2, A_RIGHT)
    theme.label(ctrl, 14, 30, 120, 14, "压缩机负荷", SZ.xs, C.ink3)
    local sl = mk_slider(ctrl, 14, 46, 336, 26, 50, 100, 82, C.ion, function(self)
        local v = self:get_value()
        sim.set_compressor(v)
        comp_lb:set_text(string.format("%d%%", v))
    end)
    page.comp_lb = comp_lb

    local btn_regen = theme.ghost(ctrl, 14, 82, 160, 28, "氦气再生", {
        size = SZ.xs,
        on_click = function()
            sim.log("液氦回路再生启动，预计 14 分钟", "warn")
            sim.summary().he = 94
            page.refresh()
        end,
    })
    local btn_vac = theme.ghost(ctrl, 190, 82, 160, 28, "真空泵组：运行", {
        size = SZ.xs,
        on_click = function()
            sim.toggle_device("vacuum")
            page.refresh()
        end,
    })
    page.btn_vac = btn_vac

    -- ==================== 真空与 RGA ====================
    local vc = theme.card(root, L.vacuum.x, L.vacuum.y, L.vacuum.w, L.vacuum.h, { radius = 14 })
    theme.label(vc, 16, 8, 200, 18, "真空系统", SZ.s, C.ink)
    local vstate = theme.label(vc, 300, 9, 300, 16, "", SZ.xs, C.ink3, A_RIGHT)

    theme.label(vc, 16, 36, 160, 14, "真空室压力", SZ.xs, C.ink3)
    local p_val = theme.label(vc, 16, 50, 130, 38, "--", SZ.xl, C.ink)
    theme.label(vc, 150, 66, 40, 16, "Pa", SZ.xs, C.ink3)
    local p_note = theme.label(vc, 16, 92, 260, 14, "", SZ.xs, C.ink3)
    local p_note2 = theme.label(vc, 16, 110, 260, 14, "", SZ.xs, C.ink3)

    theme.vline(vc, 300, 34, 130, C.line)

    theme.label(vc, 316, 36, 200, 14, "残余气体成分 RGA", SZ.xs, C.ink3)
    local rga = {}
    for i, g in ipairs(conf.vacuum.rga) do
        local y = 56 + (i - 1) * 21
        theme.label(vc, 316, y, 34, 14, g.name, SZ.xs, C.ink2)
        local bar = theme.bar(vc, 352, y + 5, 176, 4, g.val, g.color, C.panel3)
        local v = theme.label(vc, 536, y, 52, 14, "", SZ.xs, C.ink3, A_RIGHT)
        rga[i] = { def = g, bar = bar, val = v }
    end
    page.rga = rga
    page.p_val = p_val
    page.p_note = p_note
    page.p_note2 = p_note2
    page.vstate = vstate

    theme.hline(vc, 16, 150, 588, C.line)
    local pump_a = theme.label(vc, 16, 158, 280, 14, "", SZ.xs, C.ink3)
    local pump_b = theme.label(vc, 320, 158, 280, 14, "", SZ.xs, C.ink3, A_RIGHT)
    page.pump_a = pump_a
    page.pump_b = pump_b

    -- ==================== 刷新 ====================
    local function refresh()
        if not page.alive then return end
        local s = sim.summary()

        cstate:set_text(string.format("压缩机 %d%%，回路 %.2f bar", theme.n(s.compressor), s.valve_p))
        cstate:set_color(s.device.cryo and C.ink3 or C.red)

        local nv = {
            string.format("%d%%", theme.n(s.compressor)),
            string.format("%.2f bar", s.valve_p),
            string.format("%.2f K", s.t4),
            string.format("%.0f K", s.t80),
        }
        for i, v in ipairs(page.node_vals) do
            v:set_text(nv[i])
            v:set_color(s.device.cryo and C.ink or C.red)
        end

        local sv = {
            string.format("%.2f", s.t4),
            string.format("%.1f", s.t80),
            string.format("%.1f", s.tcold),
        }
        for i, st in ipairs(page.stats) do
            st.val:set_text(sv[i])
            st.val:set_color(i == 1 and C.ion or C.ink)
        end

        -- 温度计
        local tv = { s.t4, s.t80, s.tcold, s.tsupp or 296 }
        for i, th in ipairs(page.therms) do
            local v = tv[i]
            th.val:set_text(string.format("%.2f", v))
            pcall(function()
                th.shape:set_items(art.thermo_items(16, 130,
                    theme.clamp(v / th.def.max, 0.02, 1), th.def.color, C.panel3))
            end)
        end
        page.tavg:set_text(string.format("冷屏温差 %.1f K", s.t80 - s.t4))

        -- 氦
        page.he_big:set_text(string.format("%d", theme.n(s.he)))
        page.he_val:set_text(string.format("%d%%", theme.n(s.he)))
        if page.he_bar then theme.setbar(page.he_bar, s.he) end
        page.he_note:set_text("储罐 12.4 m3，液位")
        page.he_note2:set_text(string.format("日蒸发率 %.2f%%", 0.38 + (100 - s.compressor) * 0.004))
        page.he_rate:set_text(string.format("%.1f%%/d", 0.42))

        -- 真空
        local pv = s.p_vessel
        page.p_val:set_text(string.format("%.1e", pv))
        page.p_val:set_color(pv > 1e-4 and C.red or C.ink)
        page.p_note:set_text(string.format("漏率 %.1e Pa m3/s，泵组 %s",
            conf.vacuum.leak, s.device.vacuum and "运行" or "停止"))
        page.p_note2:set_text(string.format("中性束注入器 %.1e Pa", s.p_nbi))
        page.vstate:set_text(s.device.vacuum and "抽气中，真空度达标" or "泵组停机，压力上升")
        page.vstate:set_color(s.device.vacuum and C.green or C.red)

        for _, r in ipairs(page.rga) do
            local v = r.def.val * (1 + 0.03 * math.sin(s.tick * 0.4 + r.def.val))
            if r.bar then theme.setbar(r.bar, v) end
            r.val:set_text(string.format("%.1f%%", v))
        end

        page.pump_a:set_text(string.format("冷泵 A %.1f K，抽速 4200 L/s", s.tcold))
        page.pump_b:set_text(string.format("冷泵 B %.1f K，再生周期 8 h", s.tcold + 0.4))
        page.btn_vac:set_text(s.device.vacuum and "真空泵组：运行" or "真空泵组：停止")
    end
    page.refresh = refresh

    local function slow() end
    page.slow = slow

    -- ==================== 帧动画：管路流动 ====================
    local function frame()
        if not page.alive then return end
        for _, d in ipairs(page.dots) do
            d.t = d.t + d.speed
            if d.t > 1 then d.t = d.t - 1 end
            local s = d.seg
            local x = s[1] + (s[3] - s[1]) * d.t
            local y = s[2] + (s[4] - s[2]) * d.t
            pcall(function() d.shape:set_pos(math.floor(x - 2), math.floor(y - 2)) end)
        end
    end
    page.frame = frame

    function page.destroy()
        page.alive = false
    end

    refresh()
    frame()
    return page
end

return M
