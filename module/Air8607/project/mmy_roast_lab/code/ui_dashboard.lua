--[[
@module  ui_dashboard
@summary ROAST LAB 主控大屏：烘焙曲线 + 环形温度表 + 烤炉控制 + 事件 + 曲线档案
@version 1.0
@date    2026.10.30
]]
local conf = require("conf")
local theme = require("theme")
local sim = require("sim")
local art = require("art")
local app = require("app")

local C, SZ = theme.C, theme.SZ

-- 曲线卡几何
local CX, CY, CW, CHH = 40, 34, 356, 196
local VMIN, VMAX = 20, 270

local M = {}

local function find_index(hist, v)
    for i = 1, #hist do
        if hist[i] >= v then return i end
    end
    return nil
end

function M.build(p)
    local alive = true
    local U = {}
    local tick = 0
    local last_bean = 0

    -- ===================== 顶栏 =====================
    local bar = airui.container({ parent = p, x = 0, y = 0, w = conf.W, h = 56, color = C.bg0, radius = 0 })
    theme.box(bar, 0, 55, conf.W, 1, C.line, 0)
    theme.box(bar, 16, 24, 9, 9, C.copper, 4)
    theme.label(bar, 34, 7, 240, 26, "ROAST LAB", SZ.l, C.ink)
    theme.label(bar, 35, 32, 260, 18, "咖啡烘焙工坊 · 智能曲线烘焙", SZ.xs, C.ink3)

    U.chip_batch = theme.chip(bar, 300, 15, 108, 26, "批次 #A18", C.ink2, C.panel3)
    U.chip_mode = theme.chip(bar, 416, 15, 88, 26, "待机", C.ink2, C.panel3)
    U.clock = theme.label(bar, 690, 7, 140, 24, app.clock(), SZ.m, C.ink, theme.RT)
    theme.label(bar, 690, 31, 140, 18, app.date_text(), SZ.xs, C.ink3, theme.RT)
    theme.ghost(bar, 844, 12, 78, 32, "豆单", { on_click = function()
        if alive then app.go("beans") end
    end })
    theme.ghost(bar, 930, 12, 78, 32, "设置", { on_click = function()
        if alive then app.go("settings") end
    end })

    -- ===================== 左：当前豆种 =====================
    local beanCard = theme.card(p, 16, 64, 272, 170, { on_click = function()
        if alive then app.go("beans") end
    end })
    theme.box(beanCard, 0, 0, 272, 2, C.copper, 0, 90)
    theme.label(beanCard, 16, 12, 160, 18, "当前豆种", SZ.xs, C.ink3)
    U.beanShape = theme.shape(beanCard, 16, 34, 64, 64, {})
    U.beanName = theme.label(beanCard, 92, 32, 168, 26, "", SZ.l, C.ink)
    U.beanEn = theme.label(beanCard, 92, 58, 168, 16, "", SZ.xs, C.copper2)
    U.beanOrigin = theme.label(beanCard, 92, 76, 172, 16, "", SZ.xs, C.ink2)
    U.beanProc = theme.label(beanCard, 92, 94, 172, 16, "", SZ.xs, C.ink3)
    U.beanFlavor = theme.label(beanCard, 16, 112, 240, 16, "", SZ.xs, C.crema)
    theme.hline(beanCard, 16, 132, 240, C.line)
    U.beanTip = theme.label(beanCard, 16, 138, 240, 16, "", SZ.xs, C.ink2)
    theme.label(beanCard, 16, 154, 240, 16, "点按更换豆种 ›", SZ.xs, C.copper, theme.RT)

    -- ===================== 左：烘焙阶段 =====================
    local phaseCard = theme.card(p, 16, 242, 272, 112)
    theme.label(phaseCard, 16, 10, 150, 20, "烘焙阶段", SZ.m, C.ink)
    U.phaseTime = theme.label(phaseCard, 16, 10, 240, 20, "00:00", SZ.xs, C.ink3, theme.RT)
    U.phaseName = theme.label(phaseCard, 16, 60, 160, 24, "待机", SZ.l, C.ink2)
    U.phaseSide = theme.label(phaseCard, 16, 64, 240, 20, "", SZ.xs, C.ink3, theme.RT)
    U.phaseInfo = theme.label(phaseCard, 16, 86, 240, 16, "", SZ.xs, C.ink3)
    U.track, U.trackLabel = {}, {}

    -- ===================== 左：批次操作 =====================
    local opCard = theme.card(p, 16, 362, 272, 198)
    theme.label(opCard, 16, 10, 160, 20, "批次操作", SZ.m, C.ink)
    theme.label(opCard, 16, 10, 240, 20, "本地模拟", SZ.xs, C.ink3, theme.RT)

    U.btnStart = theme.button(opCard, 16, 36, 118, 46, "入 豆", { on_click = function()
        if not alive then return end
        if sim.start() then
            app.toast("已入豆 · 记录回温点", C.copper2)
        else
            app.toast("烘焙进行中，请先出豆", C.gold)
        end
    end })
    theme.button(opCard, 142, 36, 114, 46, "出豆冷却", {
        bg = C.panel2, fg = C.ink, border = C.line2, border_width = 1, pressed = C.panel3,
        on_click = function()
            if not alive then return end
            if sim.drop() then
                app.toast("已出豆 · 进入冷却", C.blue)
            else
                app.toast("当前没有在烘的豆子", C.ink2)
            end
        end,
    })
    theme.ghost(opCard, 16, 90, 118, 46, "存曲线", { on_click = function()
        if not alive then return end
        local a = sim.save_curve()
        if a then app.toast("已存档 · " .. a.name, C.green) else app.toast("先出豆才能存档", C.ink2) end
    end })
    theme.ghost(opCard, 142, 90, 114, 46, "重置", { on_click = function()
        if not alive then return end
        sim.reset()
        app.toast("已复位到待机", C.ink2)
    end })
    theme.ghost(opCard, 16, 144, 240, 38, "查看完整曲线  ›", { on_click = function()
        if alive then app.go("curve") end
    end })

    -- ===================== 中：烘焙曲线 =====================
    local curveCard = theme.card(p, 304, 64, 412, 286, { on_click = function()
        if alive then app.go("curve") end
    end })
    theme.label(curveCard, 16, 10, 200, 22, "烘焙曲线", SZ.m, C.ink)
    theme.box(curveCard, 262, 18, 8, 3, C.copper, 1)
    theme.label(curveCard, 274, 12, 60, 18, "豆温 BT", SZ.xs, C.ink3)
    theme.box(curveCard, 330, 18, 8, 3, C.blue, 1)
    theme.label(curveCard, 342, 12, 54, 18, "炉温 ET", SZ.xs, C.ink3)
    theme.label(curveCard, 8, CY - 9, 28, 18, tostring(VMAX), SZ.xs, C.ink3, theme.RT)
    theme.label(curveCard, 8, CY + math.floor(CHH / 2) - 9, 28, 18,
        tostring(math.floor((VMIN + VMAX) / 2)), SZ.xs, C.ink3, theme.RT)
    theme.label(curveCard, 8, CY + CHH - 8, 28, 18, tostring(VMIN), SZ.xs, C.ink3, theme.RT)
    U.curve = theme.shape(curveCard, CX, CY, CW, CHH, {})
    theme.label(curveCard, CX, CY + CHH + 4, 60, 16, "00:00", SZ.xs, C.ink3)
    theme.label(curveCard, CX + 140, CY + CHH + 4, 80, 16, "06:00", SZ.xs, C.ink3, theme.CT)
    theme.label(curveCard, CX + 300, CY + CHH + 4, 56, 16, "12:00", SZ.xs, C.ink3, theme.RT)
    U.curveInfo = theme.label(curveCard, 16, 258, 200, 18, "", SZ.xs, C.ink2)
    U.curveHint = theme.label(curveCard, 16, 258, 380, 18, "", SZ.xs, C.ink3, theme.RT)

    -- ===================== 中：烤炉控制 =====================
    local ctrlCard = theme.card(p, 304, 358, 412, 202)
    theme.label(ctrlCard, 16, 10, 200, 22, "烤炉控制", SZ.m, C.ink)
    theme.label(ctrlCard, 16, 10, 380, 22, "拖动立即生效", SZ.xs, C.ink3, theme.RT)

    local rows = {
        { key = "heat", name = "火力", icon = "flame", unit = "%", color = C.copper, min = 0, max = 100 },
        { key = "air", name = "风门", icon = "fan", unit = "%", color = C.blue, min = 0, max = 100 },
        { key = "drum", name = "滚筒", icon = "drum", unit = " rpm", color = C.gold, min = 20, max = 100 },
    }
    U.rows = {}
    for i, r in ipairs(rows) do
        local y = 36 + (i - 1) * 54
        art.icon(ctrlCard, r.icon, 16, y - 2, 16, r.color)
        theme.label(ctrlCard, 38, y - 4, 90, 22, r.name, SZ.s, C.ink2)
        local val = theme.label(ctrlCard, 200, y - 4, 196, 22, "", SZ.s, r.color, theme.RT)
        local sl = theme.slider({
            parent = ctrlCard, x = 16, y = y + 22, w = 380, h = 16,
            min = r.min, max = r.max, value = sim.get(r.key),
            bg_color = C.panel3, bg_opa = 255,
            indicator_color = r.color, indicator_opa = 255,
            knob_color = C.ink, knob_opa = 255,
            knob_border_color = r.color, knob_border_width = 2,
            on_change = function(s)
                if not alive then return end
                local ok, v = pcall(function() return s:get_value() end)
                if not ok then return end
                sim.set(r.key, v)
                val:set_text(string.format("%d%s", v, r.unit))
            end,
        })
        U.rows[i] = { key = r.key, unit = r.unit, val = val, slider = sl }
    end
    theme.label(ctrlCard, 16, 182, 380, 16,
        "火力↑ 升温快  ·  风门↑ 炉温低但排烟好  ·  转速↓ 升温不稳", SZ.xs, C.ink3)

    -- ===================== 右：环形温度表 =====================
    local gaugeCard = theme.card(p, 736, 64, 272, 196)
    theme.label(gaugeCard, 16, 10, 120, 20, "豆温", SZ.m, C.ink)
    U.etText = theme.label(gaugeCard, 16, 10, 240, 20, "", SZ.xs, C.ink3, theme.RT)
    U.gauge = theme.shape(gaugeCard, 10, 30, 148, 148, {})
    U.btText = theme.label(gaugeCard, 10, 84, 148, 42, "", SZ.hero, C.ink, theme.CT)
    theme.label(gaugeCard, 118, 96, 34, 20, "°C", SZ.xs, C.ink3)
    U.rorText = theme.label(gaugeCard, 10, 128, 148, 18, "", SZ.xs, C.gold, theme.CT)

    theme.label(gaugeCard, 166, 40, 96, 16, "预测烘焙度", SZ.xs, C.ink3)
    U.levelName = theme.label(gaugeCard, 166, 56, 96, 24, "", SZ.m, C.crema)
    for i = 1, #conf.levels do
        theme.box(gaugeCard, 166 + (i - 1) * 15, 88, 13, 8, conf.levels[i].color, 1)
    end
    U.levelMark = theme.shape(gaugeCard, 166, 82, 90, 20, {})
    U.crackText = theme.label(gaugeCard, 166, 104, 96, 16, "", SZ.xs, C.ink3)
    U.distText = theme.label(gaugeCard, 166, 124, 96, 16, "", SZ.xs, C.ink2)
    U.scoreText = theme.label(gaugeCard, 166, 144, 96, 16, "", SZ.xs, C.ink2)

    -- ===================== 右：事件 =====================
    local evCard = theme.card(p, 736, 268, 272, 140)
    theme.label(evCard, 16, 10, 160, 20, "烘焙事件", SZ.m, C.ink)
    local clear = theme.card(evCard, 196, 6, 60, 26, { color = C.panel2, radius = 13,
        border_color = C.line, on_click = function()
            if alive then
                sim.clear_events()
                app.toast("事件已清空", C.ink2)
            end
        end })
    theme.label(clear, 0, 4, 60, 18, "清空", SZ.xs, C.ink2, theme.CT)

    U.ev = {}
    for i = 1, 4 do
        local y = 36 + (i - 1) * 25
        U.ev[i] = {
            dot = theme.box(evCard, 16, y + 6, 4, 4, C.line2, 2),
            t = theme.label(evCard, 26, y, 44, 18, "", SZ.xs, C.ink3),
            txt = theme.label(evCard, 72, y, 184, 18, "", SZ.xs, C.ink2),
        }
    end

    -- ===================== 右：曲线档案 =====================
    local arcCard = theme.card(p, 736, 416, 272, 144)
    theme.label(arcCard, 16, 10, 160, 20, "曲线档案", SZ.m, C.ink)
    U.arcTip = theme.label(arcCard, 16, 10, 240, 20, "点按对比", SZ.xs, C.ink3, theme.RT)
    U.arc = {}
    for i = 1, 3 do
        local y = 34 + (i - 1) * 36
        local row = { y = y }
        row.bar = theme.box(arcCard, 16, y, 3, 30, C.line2, 1)
        row.name = theme.label(arcCard, 26, y + 1, 140, 18, "", SZ.xs, C.ink)
        row.meta = theme.label(arcCard, 26, y + 17, 170, 14, "", SZ.xs, C.ink3)
        row.score = theme.label(arcCard, 176, y + 5, 80, 20, "", SZ.s, C.crema, theme.RT)
        row.hit = theme.card(arcCard, 8, y - 4, 250, 36, {
            color = C.panel3, radius = 6, opacity = 0, border_width = 0,
            on_click = function()
                if not alive then return end
                local a = sim.archives()[i]
                if not a then return end
                local cur = sim.set_compare(i)
                app.toast(cur and ("对比 · " .. a.name) or "已取消对比", C.copper2)
            end,
        })
        U.arc[i] = row
    end

    theme.label(p, 16, 570, 700, 18, "Air8607 · 1024×600 · 页面数据为本地烘焙模型模拟",
        SZ.xs, C.ink3)
    theme.label(p, 700, 570, 308, 18, "点按曲线卡片进入详情", SZ.xs, C.ink3, theme.RT)

    -- ===================== 绘制函数 =====================
    local trackObjs = {}

    -- 阶段轨道：豆种切换时一爆温度变化，需要按比例重建
    local function build_track()
        for _, o in ipairs(trackObjs) do pcall(function() o:destroy() end) end
        trackObjs, U.track, U.trackLabel = {}, {}, {}
        local ps = sim.phases()
        local span = 262 - 25
        local x = 16
        for i, s in ipairs(ps) do
            local w = math.floor(240 * (s.to - s.from) / span) - 2
            if w < 14 then w = 14 end
            U.track[i] = theme.box(phaseCard, x, 34, w, 10, C.panel3, 3)
            U.trackLabel[i] = theme.label(phaseCard, x, 45, w + 4, 14, s.name, SZ.xs, C.ink3)
            trackObjs[#trackObjs + 1] = U.track[i]
            trackObjs[#trackObjs + 1] = U.trackLabel[i]
            x = x + w + 2
        end
    end

    local function paint_bean()
        local b = sim.bean()
        pcall(function() U.beanShape:set_items(art.bean_items(32, 32, 64, b.color, b.kind)) end)
        U.beanName:set_text(b.name)
        U.beanEn:set_text(b.en)
        U.beanOrigin:set_text(b.origin)
        U.beanProc:set_text(b.process .. " · " .. b.altitude)
        U.beanFlavor:set_text(b.flavor)
        U.beanTip:set_text(string.format("推荐 %s · %d~%d°C · %s 分钟",
            b.level_hint, b.drop_min, b.drop_max, b.minutes))
        U.crackText:set_text("一爆 " .. b.crack .. "°C")
        build_track()
    end

    local function paint_curve(st)
        local bt, et = st.hist_bt, st.hist_et
        local b = sim.bean()
        local items = {}
        if #bt >= 2 then
            -- 对比曲线（灰色虚线，按时间对齐）
            local cmp = sim.compare()
            local arr = cmp and sim.archive_hist(cmp) or nil
            if arr then
                local g = art.curve_items(CW, CHH, arr, {
                    min = VMIN, max = VMAX, total = conf.sim.history_n,
                    color = C.ink3, width = 1, area = false, end_dot = false,
                    grid = 0, step = 2, dash_width = 4, dash_gap = 4, opacity = 210,
                })
                for _, it in ipairs(g) do items[#items + 1] = it end
            end
            -- 炉温
            local e = art.curve_items(CW, CHH, et, {
                min = VMIN, max = VMAX, total = conf.sim.history_n,
                color = C.blue, width = 1, area = false, end_dot = false,
                grid = 4, step = 2, opacity = 190,
            })
            for _, it in ipairs(e) do items[#items + 1] = it end
            -- 豆温
            local i150 = find_index(bt, 150) or (#bt + 1)
            local icrack = find_index(bt, b.crack) or (#bt + 1)
            local marks = {}
            if st.first_crack then
                marks[#marks + 1] = { i = math.floor(st.first_crack / conf.sim.dt_s) + 1, color = C.gold }
            end
            if st.second_crack then
                marks[#marks + 1] = { i = math.floor(st.second_crack / conf.sim.dt_s) + 1, color = C.red }
            end
            if st.drop_t then
                marks[#marks + 1] = { i = math.floor(st.drop_t / conf.sim.dt_s) + 1, color = C.green }
            end
            local d = art.curve_items(CW, CHH, bt, {
                min = VMIN, max = VMAX, total = conf.sim.history_n,
                color = C.copper, width = 2, area = true, area_opa = 22,
                grid = 0, step = 2, marks = marks,
                bands = {
                    { i0 = 1, i1 = i150, color = 0x6FA8DC, opa = 12 },
                    { i0 = i150, i1 = icrack, color = 0xD9A05B, opa = 15 },
                    { i0 = icrack, i1 = #bt, color = 0xFF8A4C, opa = 17 },
                },
                refs = {
                    { v = b.crack, color = C.gold, opa = 150 },
                    { v = (b.drop_min + b.drop_max) / 2, color = C.copper2, opa = 90 },
                },
            })
            for _, it in ipairs(d) do items[#items + 1] = it end
        else
            items = art.curve_items(CW, CHH, { conf.sim.ambient, conf.sim.ambient }, {
                min = VMIN, max = VMAX, color = C.line2, width = 1,
                area = false, end_dot = false, grid = 4,
            })
        end
        pcall(function() U.curve:set_items(items) end)
    end

    local function paint_gauge(st)
        local b = sim.bean()
        local _, ph = sim.phase()
        local items = art.gauge_items(74, 74, 62, st.bt, VMIN, VMAX, {
            width = 11, track = C.panel3, color = ph.color, ticks = 12,
            segments = {
                { from = 25, to = 150, color = 0x6FA8DC, opa = 34 },
                { from = 150, to = b.crack, color = 0xD9A05B, opa = 38 },
                { from = b.crack, to = VMAX, color = 0xFF8A4C, opa = 42 },
            },
            marks = {
                { v = (b.drop_min + b.drop_max) / 2, color = C.copper2, r = 3 },
                { v = b.crack, color = C.gold, r = 4 },
                { v = b.crack + conf.roast.crack_gap, color = C.red, r = 3 },
            },
        })
        pcall(function() U.gauge:set_items(items) end)
        U.btText:set_text(string.format("%.1f", st.bt))
        U.rorText:set_text(string.format("ROR %s%.1f °C/min", st.ror >= 0 and "+" or "", st.ror))
        U.etText:set_text(string.format("炉温 ET %.1f°C", st.et))
    end

    local function paint_numbers(st)
        local b = sim.bean()
        local lv = sim.level(st.drop_bt or st.bt)
        U.levelName:set_text(lv.name)
        U.levelName:set_color(lv.color)
        local pos = sim.level_pos(st.drop_bt or st.bt)
        pcall(function()
            U.levelMark:set_items({
                { type = "rect", x = math.floor(pos * 86), y = 2, w = 3, h = 16,
                  color = C.ink, fill = true, fill_color = C.ink },
            })
        end)
        local dist = b.crack - st.bt
        U.distText:set_text(dist > 0 and string.format("距一爆 %.1f°C", dist) or "已过一爆")
        U.scoreText:set_text("评分 " .. (st.score or sim.score()))
    end

    local function paint_events()
        local evs = sim.events()
        for i = 1, 4 do
            local e, row = evs[i], U.ev[i]
            if e then
                row.t:set_text(e.t)
                row.txt:set_text(e.text)
                row.txt:set_color(e.level == "danger" and C.red or (e.level == "warn" and C.gold
                    or (e.level == "ok" and C.green or C.ink2)))
                pcall(function() row.dot:set_color(theme.state_color(e.level)) end)
            else
                row.t:set_text("")
                row.txt:set_text(i == 1 and "暂无事件" or "")
                row.txt:set_color(C.ink3)
                pcall(function() row.dot:set_color(C.line2) end)
            end
        end
    end

    local function paint_arch()
        local list = sim.archives()
        for i = 1, 3 do
            local a, row = list[i], U.arc[i]
            if a then
                row.name:set_text(a.name)
                row.meta:set_text(string.format("%s · 出豆 %.1f°C", a.date, a.drop))
                row.score:set_text((a.score or 0) .. " 分")
                local on = (sim.compare() == i)
                pcall(function()
                    row.bar:set_color(on and C.copper or C.line2)
                    row.name:set_color(on and C.copper2 or C.ink)
                end)
            else
                row.name:set_text("—")
                row.meta:set_text("")
                row.score:set_text("")
                pcall(function() row.bar:set_color(C.line2) end)
            end
        end
        U.arcTip:set_text(sim.compare() and "已选对比 · 再点取消" or "点按对比")
    end

    local function paint_phase(st)
        local ps = sim.phases()
        local idx, ph = sim.phase()
        for i = 1, #ps do
            local lit = (i <= idx) and st.mode ~= "idle"
            pcall(function()
                U.track[i]:set_color(lit and ps[i].color or C.panel3)
                U.trackLabel[i]:set_color(lit and C.ink2 or C.ink3)
            end)
        end
        local idle = (st.mode == "idle")
        U.phaseName:set_text(idle and "待机" or (ph.name .. "阶段"))
        U.phaseName:set_color(idle and C.ink2 or ph.color)
        U.phaseTime:set_text(sim.fmt_time(st.t))
        if st.first_crack then
            U.phaseSide:set_text("发展 " .. sim.fmt_time(st.t - st.first_crack))
        elseif idle then
            U.phaseSide:set_text("等待入豆")
        else
            U.phaseSide:set_text(string.format("距一爆 %.1f°C", math.max(sim.bean().crack - st.bt, 0)))
        end
        U.phaseInfo:set_text(string.format("体温 %.1f°C · 炉温 %.1f°C", st.bt, st.et))
    end

    -- ===================== 对外接口 =====================
    local page = {}

    page.refresh = function()
        if not alive then return end
        tick = tick + 1
        local st = sim.state()
        if last_bean ~= st.bean then
            last_bean = st.bean
            paint_bean()
        end
        U.chip_batch:set("批次 #A" .. st.batch)
        U.chip_mode:set(sim.mode_text(), sim.mode_color(), C.panel3)
        U.btnStart:set_text(st.mode == "roast" and "烘焙中…" or "入 豆")
        paint_numbers(st)
        paint_phase(st)
        local hint = sim.hint()
        U.curveInfo:set_text(string.format("BT %.1f°C  ET %.1f°C", st.bt, st.et))
        U.curveHint:set_text(hint.text)
        U.curveHint:set_color(theme.state_color(hint.level))
        for _, r in ipairs(U.rows) do
            r.val:set_text(string.format("%d%s", sim.get(r.key), r.unit))
        end
        if tick % conf.sim.curve_div == 0 then
            paint_gauge(st)
            paint_curve(st)
            paint_events()
            paint_arch()
        end
    end

    page.refresh_clock = function()
        if alive then U.clock:set_text(app.clock()) end
    end

    page.destroy = function() alive = false end

    -- 首次绘制
    tick = 1
    local st0 = sim.state()
    last_bean = st0.bean
    paint_bean()
    paint_curve(st0)
    paint_gauge(st0)
    paint_numbers(st0)
    paint_phase(st0)
    paint_events()
    paint_arch()
    for _, r in ipairs(U.rows) do
        r.val:set_text(string.format("%d%s", sim.get(r.key), r.unit))
    end
    U.chip_batch:set("批次 #A" .. st0.batch)
    U.chip_mode:set(sim.mode_text(), sim.mode_color(), C.panel3)
    do
        local h = sim.hint()
        U.curveHint:set_text(h.text)
        U.curveHint:set_color(theme.state_color(h.level))
        U.curveInfo:set_text(string.format("BT %.1f°C  ET %.1f°C", st0.bt, st0.et))
    end

    return page
end

return M
