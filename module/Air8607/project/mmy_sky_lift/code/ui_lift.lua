--[[
@module  ui_lift
@summary 主页：索道运行动画 + KPI + 线路状态 + 气象 + 设备 + 事件
@version 1.0
@date    2026.11.06
@note    内容区坐标原点在 (0,0)，实际屏幕 y 需 +56（顶部栏高度）
]]
local theme = require "theme"
local art   = require "art"
local sim   = require "sim"
local conf  = require "conf"

local C = theme.C
local SZ = theme.SZ
local A_LEFT, A_CENTER, A_RIGHT = theme.align_left(), theme.align_center(), theme.align_right()

local M = {}

-- 布局常量（内容区 1024x544）
local L = {
    hero    = { x = 16,  y = 8,   w = 596, h = 298 },
    kpi     = { x = 16,  y = 314, w = 596, h = 104 },
    lines   = { x = 16,  y = 426, w = 596, h = 110 },
    weather = { x = 624, y = 8,   w = 384, h = 152 },
    devices = { x = 624, y = 168, w = 384, h = 176 },
    events  = { x = 624, y = 352, w = 384, h = 184 },
}

-- 钢绳端点（hero 局部坐标）
local CABLE = { x1 = 62, y1 = 236, x2 = 518, y2 = 106, sag = 24 }
local CABIN_W, CABIN_H = 22, 26
local FLake_N = 14

-- ===================== 主页 =====================
function M.create(root)
    local page = { root = root, alive = true }

    -- ==================== 索道动画 ====================
    local hero = theme.card(root, L.hero.x, L.hero.y, L.hero.w, L.hero.h, { radius = 14 })
    local heroW, heroH = L.hero.w, L.hero.h

    -- 天空（10 条渐变，随昼夜改色）
    local sky = {}
    local SKY_N = 10
    for i = 1, SKY_N do
        local hh = math.floor(heroH / SKY_N)
        sky[i] = theme.box(hero, 0, (i - 1) * hh, heroW, (i == SKY_N) and (heroH - (i - 1) * hh) or hh, C.night, 0)
    end

    -- 星空（夜间才亮，白天由 slow() 清空）
    local stars = theme.shape(hero, 0, 0, heroW, heroH, {})
    page.stars = stars

    -- 远山 / 近山
    local far = theme.shape(hero, 0, 0, heroW, heroH, art.ridge_items(heroW, heroH, {
        { 70, 170, 0.58 }, { 238, 116, 0.44 }, { 392, 152, 0.52 }, { 552, 124, 0.48 },
    }, C.ridge, C.snow, 186, 8))
    local near = theme.shape(hero, 0, 0, heroW, heroH, art.ridge_items(heroW, heroH, {
        { 130, 218, 0.52 }, { 332, 184, 0.42 }, { 512, 206, 0.46 },
    }, C.ridge2, C.snow, 238, 8))

    -- 雪面
    local field = theme.shape(hero, 0, 0, heroW, heroH, {
        { type = "rect", x = 0, y = 252, w = heroW, h = 46, radius = 0,
          color = C.powder, fill = true, fill_color = C.powder, width = 1 },
        { type = "ellipse", cx = 120, cy = 272, rx = 150, ry = 12, color = C.powder,
          fill = true, fill_color = theme.mix(C.powder, C.snow, 0.18), width = 1, opacity = 120 },
        { type = "ellipse", cx = 400, cy = 284, rx = 210, ry = 14, color = C.powder,
          fill = true, fill_color = theme.mix(C.powder, C.snow, 0.10), width = 1, opacity = 90 },
    })

    -- 大气罩（昼夜影响山体亮度，只改一个色块）
    local ambient = theme.box(hero, 0, 0, heroW, heroH, 0x050D18, 0, 110)
    page.ambient = ambient

    -- 钢绳（上下行各一根）
    art.cable(hero, 0, 0, heroW, heroH, CABLE.x1, CABLE.y1, CABLE.x2, CABLE.y2, CABLE.sag, C.line2)
    art.cable(hero, 0, 0, heroW, heroH, CABLE.x1, CABLE.y1 + 6, CABLE.x2, CABLE.y2 + 6, CABLE.sag, C.line2)

    -- 站房
    theme.shape(hero, 16, 194, 60, 68, art.station_items(60, 68, C.panel3, C.line2, "right"))
    theme.shape(hero, 496, 64, 60, 68, art.station_items(60, 68, C.panel3, C.line2, "left"))

    -- 站台标识
    theme.label(hero, 22, 258, 80, 16, "下站 1860 m", SZ.xs, C.ink2)
    theme.label(hero, 474, 128, 110, 16, "上站 2480 m", SZ.xs, C.ink2, A_RIGHT)

    -- 缆车（沿钢绳往返）
    local cabins = {}
    local lift = sim.lift("a")
    for i = 1, lift.cabins do
        local c = { t = (i - 1) / lift.cabins, dir = 1, dwell = 0 }
        c.shape = art.cabin(hero, 0, 0, CABIN_W, CABIN_H, lift.color, 0.7)
        cabins[i] = c
    end

    -- 雪粒
    local flakes = {}
    for i = 1, FLake_N do
        local f = {
            x = 18 + (i * 61) % (heroW - 40),
            y = 10 + (i * 43) % 240,
            vy = 1.6 + (i % 4) * 0.7,
            vx = ((i % 3) - 1) * 0.7,
            r = (i % 3 == 0) and 2 or 1,
        }
        f.shape = art.flake(hero, f.x, f.y, f.r, C.snow)
        flakes[i] = f
    end

    -- 场景标题
    theme.label(hero, 16, 12, 200, 18, "A 主索道 · 全景", SZ.s, C.ink)
    theme.label(hero, 16, 30, 260, 16, "8 人吊厢 · 全长 1840 m · 27 座支架", SZ.xs, C.ink3)
    local hero_chip = theme.chip(hero, 500, 12, 78, 22, "运行中", C.bg0, C.green, SZ.xs)
    theme.label(hero, 366, 274, 214, 16, "云脊雪场 · 北坡 2 号沟", SZ.xs, C.ink3, A_RIGHT)
    page.hero_chip = hero_chip

    -- ==================== KPI ====================
    local kpi = theme.card(root, L.kpi.x, L.kpi.y, L.kpi.w, L.kpi.h, { radius = 14 })
    local kpis = {}
    local cell_w = math.floor(L.kpi.w / 4)
    local KPI_DEF = {
        { key = "speed",    cap = "索道速度", unit = "m/s" },
        { key = "capacity", cap = "运力",     unit = "人/小时" },
        { key = "depth",    cap = "平均雪深", unit = "cm" },
        { key = "cars",     cap = "在线缆车", unit = "台" },
    }
    for i, d in ipairs(KPI_DEF) do
        local x = (i - 1) * cell_w
        if i > 1 then theme.vline(kpi, x, 14, L.kpi.h - 28, C.line) end
        local cap = theme.label(kpi, x + 16, 10, cell_w - 24, 16, d.cap, SZ.xs, C.ink3)
        local val = theme.label(kpi, x + 16, 28, cell_w - 24, 42, "--", SZ.hero, C.ink)
        local unit = theme.label(kpi, x + 16, 70, cell_w - 24, 14, d.unit, SZ.xs, C.ink3)
        local sub = theme.label(kpi, x + 16, 86, cell_w - 24, 14, "", SZ.xs, C.ink3)
        kpis[i] = { def = d, cap = cap, val = val, unit = unit, sub = sub }
    end
    page.kpis = kpis

    -- ==================== 线路状态 ====================
    local lc = theme.card(root, L.lines.x, L.lines.y, L.lines.w, L.lines.h, { radius = 14 })
    theme.label(lc, 14, 8, 200, 18, "线路状态", SZ.s, C.ink)
    local line_count = theme.label(lc, 420, 8, 160, 18, "", SZ.xs, C.ink3, A_RIGHT)

    local lift_rows = {}
    for i, v in ipairs(conf.lifts) do
        local y = 32 + (i - 1) * 25
        local dot = theme.box(lc, 14, y + 8, 6, 6, C.green, 3)
        local name = theme.label(lc, 26, y + 2, 96, 18, v.name, SZ.s, C.ink)
        local st = theme.label(lc, 122, y + 3, 74, 16, "", SZ.xs, C.green)
        local bar = theme.segbar(lc, 200, y + 6, 168, 6, 20, C.ice, C.panel3, 2)
        local cap = theme.label(lc, 376, y + 2, 104, 16, "", SZ.xs, C.ink2, A_RIGHT)
        local cars = theme.label(lc, 486, y + 2, 96, 16, "", SZ.xs, C.ink3, A_RIGHT)
        lift_rows[i] = { dot = dot, name = name, st = st, bar = bar, cap = cap, cars = cars, def = v }
    end
    page.lift_rows = lift_rows
    page.line_count = line_count

    -- ==================== 气象 ====================
    local wc = theme.card(root, L.weather.x, L.weather.y, L.weather.w, L.weather.h, { radius = 14 })
    theme.label(wc, 14, 8, 240, 18, "山顶气象", SZ.s, C.ink)
    local wclock = theme.label(wc, 250, 8, 120, 18, "", SZ.xs, C.ink3, A_RIGHT)

    local temp = theme.label(wc, 16, 30, 120, 48, "--", SZ.hero, C.snow)
    local temp_u = theme.label(wc, 82, 60, 40, 16, "℃", SZ.s, C.ink2)
    local cond = theme.label(wc, 16, 80, 120, 16, "", SZ.xs, C.ink2)
    local feels = theme.label(wc, 16, 98, 132, 16, "", SZ.xs, C.ink3)

    local wrows = {}
    local WROW = {
        { icon = "wind",   label = "风速",   key = "wind" },
        { icon = "thermo", label = "湿度",   key = "hum" },
        { icon = "eye",    label = "能见度", key = "vis" },
        { icon = "flake",  label = "湿球",   key = "wet" },
    }
    for i, d in ipairs(WROW) do
        local y = 34 + (i - 1) * 21
        art.icon(wc, d.icon, 156, y, 14, C.ink3)
        theme.label(wc, 176, y, 60, 14, d.label, SZ.xs, C.ink3)
        local val = theme.label(wc, 240, y, 128, 14, "--", SZ.xs, C.ink, A_RIGHT)
        wrows[i] = { def = d, val = val }
    end
    local risk = theme.label(wc, 16, 120, 352, 20, "", SZ.xs, C.green)
    theme.hline(wc, 16, 116, 352, C.line)
    page.weather = { temp = temp, cond = cond, feels = feels, rows = wrows, risk = risk, clock = wclock }

    -- ==================== 设备 ====================
    local dc = theme.card(root, L.devices.x, L.devices.y, L.devices.w, L.devices.h, { radius = 14 })
    theme.label(dc, 14, 8, 200, 18, "设备状态", SZ.s, C.ink)
    local dev_count = theme.label(dc, 240, 8, 130, 18, "", SZ.xs, C.ink3, A_RIGHT)

    local tiles = {}
    for i, v in ipairs(conf.devices) do
        local col = (i - 1) % 3
        local row = math.floor((i - 1) / 3)
        local tw, th, gap = 116, 62, 8
        local x = 12 + col * (tw + gap)
        local y = 34 + row * (th + gap)
        local box = theme.box(dc, x, y, tw, th, C.panel2, 10)
        art.icon_badge(dc, x + 8, y + 9, 22, v.icon, C.ink, C.panel3, 255, 5)
        theme.label(dc, x + 36, y + 9, 74, 18, v.name, SZ.s, C.ink)
        local st = theme.label(dc, x + 10, y + 34, 96, 16, "", SZ.xs, C.ink3)
        local note = theme.label(dc, x + 10, y + 48, 98, 12, "", SZ.xs, C.ink3)
        local dot = theme.box(dc, x + 96, y + 14, 6, 6, C.green, 3)
        box:set_on_click(function()
            sim.toggle_device(v.key)
            page.refresh()
        end)
        tiles[i] = { box = box, st = st, note = note, dot = dot, def = v }
    end
    page.tiles = tiles
    page.dev_count = dev_count

    -- ==================== 事件 ====================
    local ec = theme.card(root, L.events.x, L.events.y, L.events.w, L.events.h, { radius = 14 })
    theme.label(ec, 14, 8, 200, 18, "运行事件", SZ.s, C.ink)
    local ec_more = theme.label(ec, 250, 8, 120, 18, "", SZ.xs, C.ink3, A_RIGHT)
    local erows = {}
    for i = 1, 5 do
        local y = 32 + (i - 1) * 28
        local dot = theme.box(ec, 14, y + 6, 5, 5, C.green, 2)
        local t = theme.label(ec, 26, y + 1, 50, 16, "", SZ.xs, C.ink3)
        local tx = theme.label(ec, 74, y + 1, 296, 16, "", SZ.xs, C.ink2)
        erows[i] = { dot = dot, time = t, text = tx }
    end
    page.event_rows = erows
    page.event_more = ec_more

    -- ==================== 数据刷新 ====================
    local function refresh()
        if not page.alive then return end
        local s = sim.summary()

        -- KPI
        local vals = {
            { string.format("%.1f", s.speed), string.format("目标 %.1f m/s", sim.target("a")) },
            { tostring(s.capacity), string.format("载客率 %d%%", math.floor((sim.lift("a").load or 0) * 100)) },
            { string.format("%.0f", s.depth), string.format("%d / %d 条雪道开放", theme.n(s.open_slopes), theme.n(s.total_slopes)) },
            { tostring(s.cars), string.format("站台排队 %d 人", theme.n(s.queue)) },
        }
        for i, k in ipairs(page.kpis) do
            k.val:set_text(vals[i][1])
            k.sub:set_text(vals[i][2])
            if i == 3 then
                k.val:set_color(s.depth < 45 and C.gold or C.ink)
            elseif i == 1 then
                k.val:set_color(s.speed < 0.3 and C.red or C.ink)
            end
        end

        -- 线路状态
        local online = 0
        for i, row in ipairs(page.lift_rows) do
            local l = sim.lift(row.def.key)
            local running = l.speed > 0.15
            if running then online = online + 1 end
            local level = (l.state == "run") and "ok" or ((l.state == "derate") and "warn" or "danger")
            row.dot:set_color(theme.state_color(level))
            row.st:set_text(l.state_text)
            row.st:set_color(theme.state_color(level))
            row.bar.set(l.speed / math.max(0.1, l.max_speed), l.state == "run" and C.ice or theme.state_color(level))
            row.cap:set_text(string.format("%d 人/h", theme.n(l.capacity)))
            row.cars:set_text(string.format("%d 台 · %d 座", theme.n(l.cabins), theme.n(l.seats)))
        end
        page.line_count:set_text(string.format("%d / 3 条在线", online))
        page.hero_chip.set(sim.lift("a").state_text,
            theme.state_color(sim.lift("a").state == "run" and "ok" or (sim.lift("a").state == "derate" and "warn" or "danger")))

        -- 气象
        local w = sim.weather()
        page.weather.temp:set_text(string.format("%.1f", s.temp))
        page.weather.temp:set_color(s.temp < 0 and C.snow or C.gold)
        page.weather.cond:set_text(s.cond .. " · 海拔 " .. conf.resort.top .. " m")
        page.weather.feels:set_text(string.format("体感 %.1f℃", s.feels))
        page.weather.clock:set_text(s.clock .. " " .. s.phase)
        local rv = {
            string.format("%.1f m/s", w.wind),
            string.format("%d %%", math.floor(w.hum + 0.5)),
            string.format("%.1f km", w.vis),
            string.format("%.1f ℃", w.wetbulb),
        }
        for i, r in ipairs(page.weather.rows) do
            r.val:set_text(rv[i])
            if r.def.key == "wind" then
                r.val:set_color(w.wind >= conf.weather.wind_warn and C.red or C.ink)
            elseif r.def.key == "wet" then
                r.val:set_color(w.wetbulb <= -2 and C.ice or C.gold)
            end
        end
        local level, risk_text = sim.risk()
        page.weather.risk:set_text(risk_text)
        page.weather.risk:set_color(theme.state_color(level))

        -- 设备
        local on, total = 0, 0
        for i, t in ipairs(page.tiles) do
            local d = sim.device(t.def.key)
            total = total + 1
            if d.on then on = on + 1 end
            t.st:set_text(d.on and "已开启" or "已关闭")
            t.st:set_color(d.on and C.ice or C.ink3)
            t.note:set_text(theme.fit(d.note, 9))
            t.dot:set_color(d.on and C.green or C.ink3)
        end
        page.dev_count:set_text(string.format("%d / %d 开启", on, total))

        -- 事件
        local evs = sim.events(5)
        for i, row in ipairs(page.event_rows) do
            local e = evs[i]
            if e then
                row.dot:set_color(theme.state_color(e.level))
                row.time:set_text(e.clock)
                row.text:set_text(theme.fit(e.text, 20))
                row.text:set_color(e.level == "danger" and C.red or C.ink2)
            else
                row.dot:set_color(C.line)
                row.time:set_text("")
                row.text:set_text("")
            end
        end
        page.event_more:set_text(string.format("近 24 条 · %d", #sim.events(24)))
    end
    page.refresh = refresh

    -- ==================== 慢刷新（天空 / 天色）====================
    local sky_bucket = -1
    local function slow()
        if not page.alive then return end
        local d = sim.daylight()
        local bucket = math.floor(d * 12 + 0.5)
        if bucket == sky_bucket then return end
        sky_bucket = bucket
        local top, low, amb, opa = art.sky_colors(d)
        for i = 1, SKY_N do
            sky[i]:set_color(theme.mix(top, low, (i - 1) / (SKY_N - 1)))
        end
        pcall(function()
            page.ambient:set_color(amb, opa)
        end)
        if page.stars then
            local lit = d < 0.4
            local items = {}
            if lit then
                for i = 1, 26 do
                    local sx = (i * 79) % heroW
                    local sy = 8 + (i * 37) % 120
                    items[#items + 1] = {
                        type = "circle", cx = sx, cy = sy, r = 1,
                        color = C.snow, width = 1, opacity = math.floor(80 + (1 - d) * 150),
                        fill = true, fill_color = C.snow, fill_opacity = math.floor(80 + (1 - d) * 140),
                    }
                end
            end
            pcall(function() page.stars:set_items(items) end)
        end
    end
    page.slow = slow

    -- ==================== 帧动画（缆车 / 雪粒）====================
    local function frame()
        if not page.alive then return end
        local l = sim.lift("a")
        local speed = l.speed / math.max(0.5, l.max_speed)
        local step = 0.004 + 0.013 * speed

        for _, c in ipairs(cabins) do
            if c.dwell > 0 then
                c.dwell = c.dwell - 1
            else
                c.t = c.t + step * c.dir
                if c.t >= 1 then c.t = 1; c.dir = -1; c.dwell = 6 end
                if c.t <= 0 then c.t = 0; c.dir = 1; c.dwell = 6 end
            end
            local x, y = art.path_point(CABLE.x1, CABLE.y1, CABLE.x2, CABLE.y2, CABLE.sag, c.t)
            c.shape:set_pos(math.floor(x - CABIN_W / 2), math.floor(y))
        end

        for _, f in ipairs(flakes) do
            f.y = f.y + f.vy
            f.x = f.x + f.vx
            if f.y > heroH - 4 then
                f.y = 8
                f.x = 18 + (f.x * 7 + 37) % (heroW - 40)
            end
            if f.x < 16 then f.x = heroW - 30 elseif f.x > heroW - 20 then f.x = 20 end
            f.shape:set_pos(math.floor(f.x), math.floor(f.y))
        end
    end
    page.frame = frame

    function page.destroy()
        page.alive = false
    end

    refresh()
    slow()
    frame()
    return page
end

return M
