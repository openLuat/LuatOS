--[[
@module  ui_apron
@summary AeroDeck 主页：机坪雷达 + 航班保障列表 + 运行 KPI + 跑道气象 + 事件流
@version 1.0
@date    2026.11.05
]]
local conf = require "conf"
local theme = require "theme"
local art = require "art"
local sim = require "sim"
local app = require "app"

local C, SZ = theme.C, theme.SZ
local CT, RT = airui.TEXT_ALIGN_CENTER, airui.TEXT_ALIGN_RIGHT

local M = {}

-- ===================== 布局常量（1024x600 手工排布）=====================
local RADAR = { x = 16,  y = 66,  w = 600, h = 330 }
local LIST  = { x = 16,  y = 404, w = 600, h = 180 }
local KPI   = { x = 624, y = 66,  w = 384, h = 146 }
local WXC   = { x = 624, y = 220, w = 384, h = 150 }
local EVT   = { x = 624, y = 378, w = 384, h = 206 }

local R_SIZE = 282              -- 雷达画布边长
local R_X, R_Y = 155, 32        -- 雷达画布在卡片内的位置
local R_C = R_SIZE / 2
local R_LEN = R_SIZE / 2 - 18

local ROW_N = 6

function M.build(p)
    local alive = true
    local ui = { rows = {}, blips = {}, evt = {}, kpi = {} }
    local sweep_angle = 0
    local frame = 0
    local refresh_all, refresh_radar, refresh_list

    ------------------------------------------------------------------
    -- 顶栏
    ------------------------------------------------------------------
    local bar = airui.container({ parent = p, x = 0, y = 0, w = conf.W, h = 56, color = C.bg0, radius = 0 })
    theme.box(bar, 0, 55, conf.W, 1, C.line, 0)

    local logo = theme.card(bar, 16, 11, 34, 34, { color = 0x0B2231, radius = 11,
        border_color = C.line2, border_width = 1 })
    art.icon(logo, "radar", 6, 6, 22, C.cyan)

    theme.label(bar, 58, 5, 200, 28, conf.brand, SZ.l, C.ink)
    theme.label(bar, 58, 32, 220, 16, conf.slogan, SZ.xs, C.ink3)
    theme.vline(bar, 250, 14, 28, C.line)

    theme.label(bar, 266, 8, 200, 20, conf.airport.name .. " · " .. conf.airport.term, SZ.s, C.ink2)
    theme.label(bar, 266, 30, 200, 16, "跑道 " .. conf.airport.runway, SZ.xs, C.ink3)

    local badge = theme.card(bar, 412, 13, 168, 30, { color = C.panel2, radius = 15,
        border_color = C.line, border_width = 1 })
    ui.badge_dot = app.dot(badge, 13, 12, 3, C.green)
    ui.badge_text = theme.label(badge, 24, 0, 134, 30, "机坪运行正常", SZ.s, C.green)
    ui.badge = badge

    ui.clock = theme.label(bar, 600, 0, 300, 32, sim.clock(), SZ.xl, C.ink, RT)
    ui.lvp_chip = theme.chip(bar, 600, 34, 100, 18, "", C.ink3, C.panel2, SZ.xs)
    ui.date = theme.label(bar, 706, 34, 194, 18, sim.date_text(), SZ.xs, C.ink3, RT)

    local wxbtn = theme.card(bar, 920, 11, 36, 34, {
        color = C.panel2, radius = 9, border_color = C.line, border_width = 1,
        on_click = function() if alive then app.go("weather") end end,
    })
    art.icon(wxbtn, "wind", 9, 8, 18, C.ink2)

    local setbtn = theme.card(bar, 964, 11, 36, 34, {
        color = C.panel2, radius = 9, border_color = C.line, border_width = 1,
        on_click = function() if alive then app.go("settings") end end,
    })
    art.icon(setbtn, "gear", 9, 8, 18, C.ink2)

    ------------------------------------------------------------------
    -- 机坪雷达
    ------------------------------------------------------------------
    local rc = theme.card(p, RADAR.x, RADAR.y, RADAR.w, RADAR.h, {
        color = 0x061019, radius = 12, border_color = 0x1B3C56, border_width = 1,
    })
    theme.label(rc, 16, 10, 200, 22, "机坪雷达", SZ.m, C.ink)
    ui.radar_note = theme.label(rc, 300, 10, RADAR.w - 316, 22, "", SZ.xs, C.ink3, RT)

    art.radar_bg(rc, R_X, R_Y, R_SIZE, C.cyan, 0x1D3A55)
    -- 跑道示意：机位在南侧，跑道横在北侧，让雷达图不至于半边空
    theme.shape(rc, R_X + 52, R_Y + 22, 178, 20, art.runway_items(178, 20, 0x3E5C78, 0x8FB3CC))
    theme.label(rc, R_X + 52, R_Y + 6, 60, 14, "18L/36R", SZ.xs, 0x3E5C78)
    ui.sweep = theme.shape(rc, R_X, R_Y, R_SIZE, R_SIZE, art.sweep_items(R_SIZE, 0, C.cyan))

    theme.label(rc, R_X + R_C - 10, R_Y + 2, 20, 14, "N", SZ.xs, C.ink3, CT)
    theme.label(rc, R_X + 2, R_Y + 6, 20, 14, "W", SZ.xs, 0x3E5C78)
    theme.label(rc, R_X + R_SIZE - 20, R_Y + 6, 18, 14, "E", SZ.xs, 0x3E5C78, RT)
    theme.label(rc, R_X + R_C - 10, R_Y + R_SIZE - 16, 20, 14, "S", SZ.xs, 0x3E5C78, CT)
    theme.label(rc, R_X + R_C + 4, R_Y + R_C - 46, 40, 14, "1.5", SZ.xs, 0x2A4A63)
    theme.label(rc, R_X + R_C + 4, R_Y + R_C - 92, 40, 14, "3.0", SZ.xs, 0x2A4A63)

    local lg = theme.box(rc, 15, RADAR.h - 26, 240, 18, 0x061019, 0, 180)
    local legend = { { "在机位", C.cyan }, { "已推出", C.amber }, { "异常", C.red } }
    for i, it in ipairs(legend) do
        app.dot(lg, 6 + (i - 1) * 76, 7, 2, it[2])
        theme.label(lg, 14 + (i - 1) * 76, 1, 60, 16, it[1], SZ.xs, C.ink3)
    end
    ui.radar_chip = theme.chip(rc, RADAR.w - 168, RADAR.h - 28, 152, 22,
        "", C.ink3, 0x0A1826, SZ.xs)

    for _, f in ipairs(sim.flights()) do
        local box = theme.card(rc, 0, 0, 46, 34, {
            color = 0x000000, radius = 4, border_width = 0, opacity = 0,
            on_click = function()
                if alive then app.go("flight", f.idx) end
            end,
        })
        local icon = art.icon(box, "plane", 15, 1, 16, C.cyan)
        app.dot(box, 21, 2, 2, C.cyan)
        local lb = theme.label(box, 0, 18, 46, 14, f.gate, SZ.xs, C.ink3, CT)
        ui.blips[f.idx] = { box = box, icon = icon, label = lb, f = f, shown = true }
    end

    ------------------------------------------------------------------
    -- 航班保障列表
    ------------------------------------------------------------------
    local lc = theme.card(p, LIST.x, LIST.y, LIST.w, LIST.h)
    theme.label(lc, 14, 8, 200, 22, "航班保障", SZ.m, C.ink)
    ui.list_note = theme.label(lc, 200, 8, LIST.w - 216, 22, "", SZ.xs, C.ink3, RT)

    local hx = { 22, 100, 176, 226, 272, 380, 508 }
    local hnames = { "航班", "航司", "机位", "计划", "状态", "保障进度", "等级" }
    for i, n in ipairs(hnames) do
        theme.label(lc, hx[i], 31, 100, 14, n, SZ.xs, 0x445F7A)
    end

    for i = 1, ROW_N do
        local y = 47 + (i - 1) * 22
        local row = theme.card(lc, 8, y, LIST.w - 16, 20, {
            color = C.panel2, radius = 6, border_color = C.line, border_width = 1,
            on_click = function()
                local it = ui.rows[i]
                if alive and it and it.f then app.go("flight", it.f.idx) end
            end,
        })
        local it = {}
        it.cs = theme.label(row, 14, 2, 74, 16, "", SZ.s, C.ink)
        it.air = theme.label(row, 92, 3, 76, 14, "", SZ.xs, C.ink3)
        it.gate = theme.label(row, 168, 2, 44, 16, "", SZ.xs, C.ink2)
        it.std = theme.label(row, 218, 3, 46, 14, "", SZ.xs, C.ink2)
        it.status = theme.label(row, 264, 3, 110, 14, "", SZ.xs, C.ink2)
        it.bar = theme.segbar(row, 372, 7, 122, 6, 16, C.cyan, 0x16283C, 2)
        it.chip = theme.chip(row, 500, 1, 54, 18, "", C.ink3, C.panel3, SZ.xs)
        it.dot = app.dot(row, 563, 8, 2, C.green)
        it.f = nil
        ui.rows[i] = it
    end

    ------------------------------------------------------------------
    -- 运行指标
    ------------------------------------------------------------------
    local kc = theme.card(p, KPI.x, KPI.y, KPI.w, KPI.h)
    theme.label(kc, 16, 8, 160, 22, "运行指标", SZ.m, C.ink)
    ui.kpi_note = theme.label(kc, 180, 8, KPI.w - 196, 22, "", SZ.xs, C.ink3, RT)

    local kdefs = {
        { name = "在场航班", unit = "架次", color = C.cyan },
        { name = "保障准点率", unit = "%", color = C.green },
        { name = "机位占用", unit = "", color = C.amber },
        { name = "待除冰", unit = "架", color = C.orange },
    }
    for i, d in ipairs(kdefs) do
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        local x = 16 + col * 180
        local y = 38 + row * 50
        local cell = theme.card(kc, x, y, 168, 44, { color = C.panel2, radius = 8,
            border_color = C.line, border_width = 1 })
        app.dot(cell, 10, 20, 3, d.color)
        theme.label(cell, 20, 6, 110, 14, d.name, SZ.xs, C.ink3)
        local val = theme.label(cell, 14, 18, 100, 24, "--", SZ.l, C.ink)
        local unit = theme.label(cell, 108, 24, 52, 16, d.unit, SZ.xs, C.ink3)
        ui.kpi[i] = { def = d, cell = cell, val = val, unit = unit }
    end

    ------------------------------------------------------------------
    -- 跑道气象
    ------------------------------------------------------------------
    local wc = theme.card(p, WXC.x, WXC.y, WXC.w, WXC.h, {
        on_click = function() if alive then app.go("weather") end end,
    })
    theme.label(wc, 16, 8, 160, 22, "跑道气象", SZ.m, C.ink)
    theme.label(wc, 16, 8, WXC.w - 32, 22, "调节 ›", SZ.xs, C.cyan, RT)

    ui.compass = art.compass(wc, 14, 38, 76, 0, C.cyan, 0x1D3A55)
    ui.wind_main = theme.label(wc, 98, 38, 160, 26, "--", SZ.l, C.ink)
    ui.wind_sub = theme.label(wc, 98, 64, 200, 18, "", SZ.xs, C.ink3)
    ui.wx_chip = theme.chip(wc, WXC.w - 110, 38, 94, 22, "干跑道", C.ink2, C.panel2, SZ.xs)

    for i, r in ipairs({ { "能见度", "vis" }, { "跑道视程", "rvr" }, { "机坪温度", "temp" } }) do
        local x = 16 + (i - 1) * 120
        theme.label(wc, x, 90, 110, 14, r[1], SZ.xs, C.ink3)
        ui["wx_" .. r[2]] = theme.label(wc, x, 104, 116, 22, "--", SZ.m, C.ink)
    end
    ui.wx_footer = theme.label(wc, 16, 128, WXC.w - 32, 16, "", SZ.xs, C.ink3)

    ------------------------------------------------------------------
    -- 运行事件
    ------------------------------------------------------------------
    local ec = theme.card(p, EVT.x, EVT.y, EVT.w, EVT.h)
    theme.label(ec, 14, 8, 160, 22, "运行事件", SZ.m, C.ink)
    ui.evt_note = theme.label(ec, 160, 8, EVT.w - 176, 22, "", SZ.xs, C.ink3, RT)
    for i = 1, 6 do
        local y = 36 + (i - 1) * 28
        local t = theme.label(ec, 14, y + 2, 40, 16, "", SZ.xs, C.ink3)
        local d = app.dot(ec, 58, y + 7, 2, C.green)
        local x = theme.label(ec, 68, y, EVT.w - 82, 22, "", SZ.xs, C.ink2)
        ui.evt[i] = { time = t, dot = d, text = x }
    end

    ------------------------------------------------------------------
    -- 雷达刷新：航迹点定位 + 着色
    ------------------------------------------------------------------
    function refresh_radar()
        if not alive then return end
        for _, b in pairs(ui.blips) do
            local f = b.f
            if f.gone or (f.exit or 0) >= 1.01 then
                -- 已离场：挪到画布外，避免在雷达上留残点
                if b.shown then
                    b.shown = false
                    pcall(function() b.box:set_pos(-90, -90) end)
                end
            else
                local ang, rr = sim.pos(f)
                local a = math.rad(ang)
                local px = R_X + R_C + math.sin(a) * rr * R_LEN - 23
                local py = R_Y + R_C - math.cos(a) * rr * R_LEN - 17
                pcall(function() b.box:set_pos(math.floor(px), math.floor(py)) end)
                b.shown = true
                local col
                if sim.level(f) ~= "ok" then
                    col = theme.state_color(sim.level(f))
                elseif f.deice then
                    col = C.orange
                elseif f.node >= #conf.nodes then
                    col = C.amber
                else
                    col = C.cyan
                end
                pcall(function() b.icon:set_items(art.plane_items(16, col, true)) end)
                b.label:set_text(f.gate)
            end
        end
    end

    ------------------------------------------------------------------
    -- 列表刷新
    ------------------------------------------------------------------
    function refresh_list()
        if not alive then return end
        local list = {}
        for _, f in ipairs(sim.flights()) do
            if not f.gone then list[#list + 1] = f end
        end
        for i = 1, ROW_N do
            local it, f = ui.rows[i], list[i]
            if f then
                it.f = f
                local lv = sim.level(f)
                local col = theme.state_color(lv)
                it.cs:set_text(f.cs)
                it.air:set_text(f.airline)
                it.gate:set_text(f.gate)
                it.std:set_text(f.std)
                it.status:set_text(sim.status_text(f))
                it.status:set_color(f.deice and C.orange or C.ink2)
                it.bar.set(sim.progress(f), f.deice and C.orange or
                    (f.node >= #conf.nodes and C.amber or C.cyan))
                it.chip.set(sim.level_text(f), lv == "ok" and C.green or col)
                app.dot_paint(it.dot, 2, col)
            else
                it.f = nil
                it.cs:set_text("")
                it.air:set_text("")
                it.gate:set_text("")
                it.std:set_text("")
                it.status:set_text("")
                it.bar.set(0, C.cyan)
                it.chip.set("", C.ink3)
                app.dot_paint(it.dot, 2, C.line)
            end
        end
        ui.list_note:set_text(string.format("%d 架次在坪 · 共 %d 班", #list, sim.count()))
    end

    ------------------------------------------------------------------
    -- 整体刷新
    ------------------------------------------------------------------
    function refresh_all()
        if not alive then return end
        ui.clock:set_text(sim.clock())
        ui.date:set_text(sim.date_text())
        ui.lvp_chip.set(sim.lvp_text(), sim.lvp() and C.red or C.ink3)

        local worst = sim.worst_level()
        local bcol = theme.state_color(worst)
        app.dot_paint(ui.badge_dot, 3, bcol)
        ui.badge_text:set_text(worst == "danger" and "机坪异常处置" or
            (worst == "warn" and "机坪需关注" or "机坪运行正常"))
        ui.badge_text:set_color(bcol)
        ui.badge:set_border_color(worst == "ok" and C.line or bcol, 1)

        local rate = sim.on_time_rate()
        ui.kpi[1].val:set_text(tostring(sim.on_stand()))
        ui.kpi[2].val:set_text(rate .. "%")
        ui.kpi[2].val:set_color(rate >= 85 and C.ink or C.gold)
        ui.kpi[3].val:set_text(sim.occupied() .. "/" .. sim.stand_total())
        ui.kpi[4].val:set_text(tostring(sim.deice_count()))
        ui.kpi[4].val:set_color(sim.deice_count() > 0 and C.orange or C.ink)
        ui.kpi_note:set_text(string.format("平均延误 %.0f 分钟", sim.avg_delay()))

        ui.radar_note:set_text(string.format("SSR · 6 NM · %d 目标", sim.on_stand()))

        local w = sim.wx()
        ui.radar_chip.set(string.format("%s · %.1f m/s", sim.wind_sector(), w.wind_spd), C.ink3)
        ui.compass:set_items(art.compass_items(76, w.wind_dir, C.cyan, 0x1D3A55))
        ui.wind_main:set_text(string.format("%03d° · %.1f m/s", math.floor(w.wind_dir), w.wind_spd))
        ui.wind_sub:set_text(string.format("阵风 %.1f · 侧风 %.1f m/s", w.gust, sim.crosswind()))
        ui.wx_chip.set(sim.state_name(), sim.mu() < 0.3 and C.orange or C.ink2)
        -- %d 只能吃有整数表示的数值：这里统一 floor 兜底，
        -- 模型侧万一再算进浮点，也不会把 refresh 打断在半途。
        ui.wx_vis:set_text(string.format("%d m", math.floor(w.vis)))
        ui.wx_vis:set_color(w.vis < conf.wx.vis.lo and C.red or
            (w.vis < conf.wx.vis.hi and C.gold or C.ink))
        ui.wx_rvr:set_text(string.format("%d m", math.floor(w.rvr)))
        ui.wx_rvr:set_color(w.rvr < conf.wx.rvr.lo and C.red or
            (w.rvr < conf.wx.rvr.hi and C.gold or C.ink))
        ui.wx_temp:set_text(string.format("%.1f ℃", w.temp))
        ui.wx_temp:set_color(w.temp < conf.wx.temp.lo and C.cyan or C.ink)
        ui.wx_footer:set_text(string.format("海压 %d hPa · 露点 %.1f ℃ · μ %.2f",
            math.floor(w.qnh), w.dew, sim.mu()))

        local list = sim.alarms(6)
        for i = 1, 6 do
            local e, a = ui.evt[i], list[i]
            if a then
                local ac = theme.state_color(a.level)
                e.time:set_text(a.time)
                e.text:set_text(a.text)
                e.text:set_color(a.level == "ok" and C.ink2 or ac)
                app.dot_paint(e.dot, 2, ac)
            else
                e.time:set_text("")
                e.text:set_text("")
            end
        end
        ui.evt_note:set_text(sim.alarm_count() .. " 条")

        refresh_list()
        refresh_radar()
    end

    ------------------------------------------------------------------
    -- 动画：雷达扫描 + 报警点呼吸
    ------------------------------------------------------------------
    local function anim()
        if not alive then return end
        frame = frame + 1
        sweep_angle = (sweep_angle + 6) % 360
        if frame % 2 == 0 then
            pcall(function()
                ui.sweep:set_items(art.sweep_items(R_SIZE, sweep_angle, C.cyan))
            end)
        end
        if frame % 8 == 0 then refresh_radar() end
        if frame % 10 == 0 then
            local on = math.floor(frame / 10) % 2 == 0
            for i = 1, ROW_N do
                local it = ui.rows[i]
                if it.f then
                    local lv = sim.level(it.f)
                    if lv ~= "ok" then app.blink(it.dot, 2, theme.state_color(lv), on) end
                end
            end
            if sim.worst_level() == "danger" then
                app.blink(ui.badge_dot, 3, C.red, on)
            end
        end
    end

    pcall(refresh_all)

    return {
        anim = anim,
        -- 不再在这里 pcall：让异常冒到 app 的定时器里被 log.error 打出来，
        -- 否则 refresh 内部任何一处抛错都会静默中断，界面"有数据但永不更新"
        refresh = function() if alive then refresh_all() end end,
        tick_minute = function() if alive then ui.clock:set_text(sim.clock()) end end,
        destroy = function()
            alive = false
        end,
    }
end

return M
