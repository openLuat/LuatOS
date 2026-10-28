--[[
@module  ui_tank
@summary ReefOS 主页：生态缸实时视图 + 设备控制 + 日常维护 + 水质总览
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

-- 布局
local TANK  = { x = 16,  y = 66,  w = 544, h = 316 }
local DEV   = { x = 16,  y = 390, w = 544, h = 96 }
local MAINT = { x = 16,  y = 494, w = 544, h = 94 }
local WATER = { x = 572, y = 66,  w = 216, h = 522 }
local SPEC  = { x = 800, y = 66,  w = 208, h = 176 }
local ENVC  = { x = 800, y = 250, w = 208, h = 110 }
local EVT   = { x = 800, y = 368, w = 208, h = 220 }

-- 缸内坐标系（相对卡片内容）
local TW, TH = TANK.w - 2, TANK.h - 2
local SAND_Y = 250

local function now_clock()
    return sim.clock()
end

function M.build(p)
    local alive = true
    local ui = { tiles = {}, rows = {}, evt = {} }
    local fishes, bubbles = {}, {}
    local spec_sig = ""
    local spa = 0
    local refresh_devices, refresh_all, refresh_home

    ------------------------------------------------------------------
    -- 顶栏
    ------------------------------------------------------------------
    local bar = airui.container({ parent = p, x = 0, y = 0, w = conf.W, h = 56, color = C.bg0, radius = 0 })
    theme.box(bar, 0, 55, conf.W, 1, C.line, 0)

    local logo = theme.card(bar, 16, 12, 30, 30, { color = 0x0B2231, radius = 10, border_color = C.line2, border_width = 1 })
    art.icon(logo, "coral", 5, 5, 20, C.cyan)
    theme.label(bar, 54, 6, 200, 28, conf.brand, SZ.l, C.ink)
    theme.label(bar, 54, 32, 240, 16, conf.slogan, SZ.xs, C.ink3)
    theme.vline(bar, 246, 14, 28, C.line)

    theme.label(bar, 262, 15, 130, 26, conf.tank.name .. " " .. conf.tank.volume .. "L", SZ.s, C.ink2)
    ui.stat_text = theme.label(bar, 606, 17, 150, 22, "珊瑚 7 株 · 鱼 3 尾", SZ.xs, C.ink3)

    -- 状态徽章
    local badge = theme.card(bar, 396, 13, 148, 30, { color = C.panel2, radius = 15, border_color = C.line, border_width = 1 })
    ui.badge_dot = app.dot(badge, 12, 12, 3, C.green)
    ui.badge_text = theme.label(badge, 22, 0, 116, 30, "水质稳定", SZ.s, C.green)
    ui.badge = badge

    ui.clock = theme.label(bar, 760, 2, 200, 32, now_clock(), SZ.l, C.ink, RT)
    ui.date = theme.label(bar, 700, 32, 260, 16, sim.date_text(), SZ.xs, C.ink3, RT)

    local setbtn = theme.card(bar, 972, 11, 36, 34, {
        color = C.panel2, radius = 9, border_color = C.line, border_width = 1,
        on_click = function() app.go("settings") end,
    })
    art.icon(setbtn, "gear", 9, 8, 18, C.ink2)

    ------------------------------------------------------------------
    -- 生态缸主视图
    ------------------------------------------------------------------
    local card = theme.card(p, TANK.x, TANK.y, TANK.w, TANK.h, {
        color = 0x04121F, radius = 10, border_color = 0x1E4A63, border_width = 1,
    })
    ui.card = card

    local s = sim.spectrum()
    local surface, glow = art.color_from_spectrum(s.blue, s.white, s.uv)
    ui.water = art.water(card, 1, 1, TW, TH, surface, 0x03101C)
    ui.rays = art.rays(card, 1, 1, TW, TH, glow, 8)
    art.sand(card, 1, SAND_Y, TW, TH - SAND_Y)

    -- 静态珊瑚（左）
    theme.shape(card, 30, 168, 110, 100, art.branch_items(60, 90, 1.0, C.pink))
    theme.shape(card, 128, 214, 76, 62, art.branch_items(34, 46, 0.62, C.coral))
    theme.shape(card, 250, 186, 104, 84, art.fan_items(52, 72, 52, C.violet))
    -- 小海扇
    theme.shape(card, 176, 214, 70, 60, art.fan_items(35, 50, 32, 0x7C6BE0))

    -- 动态：海葵 + 海草 + 水面波光
    ui.anemone = theme.shape(card, 395, 206, 96, 62, art.anemone_items(46, 54, 34, C.green, 0))
    ui.weed = theme.shape(card, 466, 178, 76, 92, art.weed_items(38, 84, 72, C.violet, 0))
    ui.wave = theme.shape(card, 1, 0, TW, 20, art.wave_items(TW, 0, theme.mix(surface, 0xFFFFFF, 0.6)))

    -- 鱼群
    for i, fd in ipairs(conf.fishes) do
        local fw = math.floor(46 * fd.size)
        local fh = math.floor(28 * fd.size)
        local fx = 70 + i * 120
        local fy = 84 + i * 40
        local sh = art.fish(card, fx, fy, fw, fh, fd.color, 1, i == 2)
        fishes[i] = {
            shape = sh, w = fw, h = fh, x = fx, y = fy, base_y = fy,
            dx = fd.speed * 1.7, dir = 1, color = fd.color, flip = (i == 2),
        }
    end

    -- 气泡
    for i = 1, 5 do
        local r = 2 + (i % 3)
        local bx = 60 + i * 90
        local by = 120 + i * 24
        bubbles[i] = { shape = art.bubble(card, bx, by, r), x = bx, y = by, r = r, sp = 0.7 + i * 0.16 }
    end

    -- HUD
    local chip1 = theme.chip(card, 12, 10, 98, 24, "● 实时水体", C.green, 0x08202C, SZ.xs)
    theme.chip(card, 118, 10, 116, 24, conf.tank.site, C.ink2, 0x08202C, SZ.xs)
    ui.spec_chip = theme.chip(card, TW - 130, 10, 118, 24, "全光谱 82%", C.ink2, 0x08202C, SZ.xs)

    local hud = theme.box(card, 1, 272, TW, TH - 272, 0x030E18, 0, 205)
    local hw = math.floor((TW - 24) / 3)
    ui.hud = {}
    for i, key in ipairs({ "temp", "sal", "ph" }) do
        local d = sim.def(key)
        local cx = 12 + (i - 1) * (hw + 4)
        theme.label(hud, cx, 4, hw, 16, d.name, SZ.xs, C.ink3)
        ui.hud[i] = theme.label(hud, cx, 18, hw, 22, "--", SZ.m, C.ink)
        if i > 1 then theme.vline(card, 1 + (i - 1) * (hw + 4) + 2, 274, 38, 0x1B3A4E) end
    end

    ------------------------------------------------------------------
    -- 设备控制
    ------------------------------------------------------------------
    local dcard = theme.card(p, DEV.x, DEV.y, DEV.w, DEV.h)
    theme.label(dcard, 16, 8, 200, 22, "设备控制", SZ.m, C.ink)
    ui.dev_info = theme.label(dcard, 16, 8, DEV.w - 32, 22, "", SZ.xs, C.ink3, RT)

    local function paint_tile(t)
        local on = sim.device_on(t.key)
        pcall(function()
            t.icon:set_items(art.icon_items(t.icon_key, 20, on and C.cyan or 0x44627A))
            t.box:set_border_color(on and 0x1F5670 or C.line, 1)
            t.label:set_color(on and C.ink or C.ink3)
            t.dot:set_items({{ type = "circle", cx = 3, cy = 3, r = 3, fill = true,
                fill_color = on and C.cyan or 0x2A4256, color = on and C.cyan or 0x2A4256, width = 1 }})
        end)
    end

    for i, d in ipairs(conf.devices) do
        local tx = 16 + (i - 1) * 86
        local tile = theme.card(dcard, tx, 32, 80, 52, {
            color = C.panel2, radius = 9, border_color = C.line, border_width = 1,
            on_click = function()
                if not alive then return end
                local on = sim.toggle_device(d.key)
                app.toast(d.name .. (on and " 已开启" or " 已关闭"), on and C.cyan or C.gold)
                refresh_devices()
            end,
        })
        local icon = art.icon(tile, d.icon, 30, 6, 20, 0x44627A)
        local lb = theme.label(tile, 0, 29, 80, 16, d.name, SZ.xs, C.ink3, CT)
        local dot = app.dot(tile, 68, 6, 3, 0x2A4256)
        ui.tiles[i] = { key = d.key, name = d.name, icon_key = d.icon, box = tile, icon = icon, label = lb, dot = dot }
        paint_tile(ui.tiles[i])
    end

    ------------------------------------------------------------------
    -- 日常维护
    ------------------------------------------------------------------
    local mcard = theme.card(p, MAINT.x, MAINT.y, MAINT.w, MAINT.h)
    theme.label(mcard, 16, 8, 160, 22, "日常维护", SZ.m, C.ink)
    ui.feed_info = theme.label(mcard, 16, 8, MAINT.w - 32, 22, "", SZ.xs, C.ink3, RT)

    theme.button(mcard, 16, 34, 162, 46, "立即喂食", {
        bg = C.cyan, size = SZ.s,
        on_click = function()
            if not alive then return end
            local msg = sim.feed()
            app.toast(msg, C.cyan)
            refresh_all()
        end,
    })
    theme.ghost(mcard, 186, 34, 162, 46, "RO 水补水", {
        size = SZ.s,
        on_click = function()
            if not alive then return end
            local msg = sim.topup()
            app.toast(msg, C.blue)
            refresh_all()
        end,
    })
    theme.ghost(mcard, 356, 34, 172, 46, "换水 10%", {
        size = SZ.s,
        on_click = function()
            if not alive then return end
            local msg = sim.water_change()
            app.toast(msg, C.violet)
            refresh_all()
        end,
    })

    ------------------------------------------------------------------
    -- 水质总览（6 项）
    ------------------------------------------------------------------
    local wcard = theme.card(p, WATER.x, WATER.y, WATER.w, WATER.h)
    theme.label(wcard, 14, 12, 120, 22, "水质监测", SZ.m, C.ink)
    theme.label(wcard, 14, 12, WATER.w - 28, 22, "点击看曲线", SZ.xs, C.ink3, RT)

    for i, key in ipairs(conf.home_metrics) do
        local y = 44 + (i - 1) * 78
        local row = theme.card(wcard, 8, y, WATER.w - 16, 74, {
            color = C.panel2, radius = 9, border_color = C.line, border_width = 1,
            on_click = function()
                if alive then app.go("metric", key) end
            end,
        })
        local dot = app.dot(row, 10, 11, 3, C.green)
        local name = theme.label(row, 20, 5, 90, 16, sim.def(key).name, SZ.xs, C.ink2)
        local state = theme.label(row, 96, 5, 96, 16, "正常", SZ.xs, C.green, RT)
        local val = theme.label(row, 8, 18, 126, 32, "--", SZ.xl, C.ink, RT)
        local unit = theme.label(row, 138, 30, 52, 18, sim.unit(key), SZ.xs, C.ink3)
        local spark = theme.shape(row, 8, 52, 184, 16, {})
        ui.rows[i] = { key = key, row = row, dot = dot, name = name, state = state,
                       val = val, unit = unit, spark = spark }
    end

    ------------------------------------------------------------------
    -- 光照光谱
    ------------------------------------------------------------------
    local scard = theme.card(p, SPEC.x, SPEC.y, SPEC.w, SPEC.h, {
        on_click = function() if alive then app.go("light") end end,
    })
    theme.label(scard, 12, 10, 130, 22, "光照光谱", SZ.m, C.ink)
    theme.label(scard, 12, 10, SPEC.w - 24, 22, "调节 ›", SZ.xs, C.cyan, RT)

    ui.bars = {}
    for i, ch in ipairs(conf.spectrum.channels) do
        local y = 42 + (i - 1) * 28
        theme.label(scard, 12, y, 22, 16, ch.name, SZ.xs, C.ink3)
        local bar = theme.segbar(scard, 36, y + 4, 122, 8, 16, ch.color, 0x132533, 2)
        local pct = theme.label(scard, 164, y, 32, 16, "0%", SZ.xs, C.ink2, RT)
        ui.bars[i] = { ch = ch, bar = bar, pct = pct }
    end

    ui.preview = theme.gradient(scard, 12, 126, SPEC.w - 24, 26, surface, theme.mix(surface, 0x03101C, 0.75), 6)
    ui.preview_label = theme.label(scard, 12, 126, SPEC.w - 24, 26, "全光谱", SZ.xs, C.ink, CT)
    theme.label(scard, 12, 156, SPEC.w - 24, 16, "点击进入光谱调节", SZ.xs, C.ink3, CT)

    ------------------------------------------------------------------
    -- 鱼房环境
    ------------------------------------------------------------------
    local ecard = theme.card(p, ENVC.x, ENVC.y, ENVC.w, ENVC.h)
    theme.label(ecard, 12, 10, 130, 22, "鱼房环境", SZ.m, C.ink)
    ui.env = {}
    local env_defs = { { "室温", "℃" }, { "湿度", "%" }, { "功耗", "W" } }
    for i, d in ipairs(env_defs) do
        local x = 12 + (i - 1) * 62
        theme.label(ecard, x, 38, 58, 16, d[1], SZ.xs, C.ink3)
        ui.env[i] = theme.label(ecard, x, 54, 58, 24, "--", SZ.m, C.ink)
    end
    ui.env_note = theme.label(ecard, 12, 84, ENVC.w - 24, 16, "", SZ.xs, C.ink3)

    ------------------------------------------------------------------
    -- 事件记录
    ------------------------------------------------------------------
    local vcard = theme.card(p, EVT.x, EVT.y, EVT.w, EVT.h)
    theme.label(vcard, 12, 10, 130, 22, "事件记录", SZ.m, C.ink)
    ui.evt_count = theme.label(vcard, 12, 10, EVT.w - 24, 22, "", SZ.xs, C.ink3, RT)
    for i = 1, 6 do
        local y = 40 + (i - 1) * 29
        local t = theme.label(vcard, 12, y + 2, 42, 16, "", SZ.xs, C.ink3)
        local d = app.dot(vcard, 56, y + 7, 2, C.green)
        local x = theme.label(vcard, 66, y, EVT.w - 78, 26, "", SZ.xs, C.ink2)
        ui.evt[i] = { time = t, dot = d, text = x }
    end

    ------------------------------------------------------------------
    -- 数据刷新
    ------------------------------------------------------------------
    local wave_color = theme.mix(surface, 0xFFFFFF, 0.6)

    local function apply_spectrum()
        local sp = sim.spectrum()
        local sig = sp.blue .. "/" .. sp.white .. "/" .. sp.uv
        if sig == spec_sig then return end
        spec_sig = sig
        local sf, gl = art.color_from_spectrum(sp.blue, sp.white, sp.uv)
        wave_color = theme.mix(sf, 0xFFFFFF, 0.6)
        pcall(function()
            ui.water:set(sf, 0x03101C)
            ui.rays:set_items(art.rays_items(TW, TH, gl, 8))
            ui.wave:set_items(art.wave_items(TW, spa * 0.5, wave_color))
        end)
    end

    function refresh_devices()
        for _, t in ipairs(ui.tiles) do paint_tile(t) end
        ui.dev_info:set_text(string.format("6 台 · %d 运行 · %dW", sim.on_count(), sim.power()))
    end

    function refresh_home()
        if not alive then return end
        apply_spectrum()
        ui.clock:set_text(now_clock())
        ui.date:set_text(sim.date_text())

        for i, key in ipairs({ "temp", "sal", "ph" }) do
            ui.hud[i]:set_text(sim.fmt(key) .. sim.unit(key))
        end

        local worst = sim.worst_level()
        local col = theme.state_color(worst)
        ui.badge_dot:set_items({{ type = "circle", cx = 3, cy = 3, r = 3, fill = true,
            fill_color = col, color = col, width = 1 }})
        ui.badge_text:set_text(worst == "danger" and "水质报警" or (worst == "warn" and "参数偏离" or "水质稳定"))
        ui.badge_text:set_color(col)
        ui.badge:set_border_color(worst == "ok" and C.line or col, 1)
        ui.stat_text:set_text(string.format("珊瑚 7 株 · 鱼 %d 尾 · 缸龄 2 年", #conf.fishes))

        for _, r in ipairs(ui.rows) do
            local lv = sim.level(r.key)
            local bc = theme.state_color(lv)
            r.val:set_text(sim.fmt(r.key))
            r.val:set_color(lv == "ok" and C.ink or bc)
            r.state:set_text(theme.state_text(lv))
            r.state:set_color(bc)
            r.dot:set_items({{ type = "circle", cx = 3, cy = 3, r = 3, fill = true,
                fill_color = bc, color = bc, width = 1 }})
        end

        local sp = sim.spectrum()
        for i, b in ipairs(ui.bars) do
            local v = sp[b.ch.key] or 0
            b.bar.set(v / 100)
            b.pct:set_text(v .. "%")
        end
        local total = math.floor((sp.blue + sp.white + sp.uv) / 3)
        ui.preview_label:set_text(sim.spectrum_preset_name() .. " · " .. total .. "%")
        ui.spec_chip.set(sim.spectrum_preset_name() .. " " .. total .. "%", C.ink2)

        local e = sim.env()
        ui.env[1]:set_text(string.format("%.1f", e.room))
        ui.env[2]:set_text(string.format("%d", math.floor(e.hum)))
        ui.env[3]:set_text(tostring(sim.power()))
        ui.env_note:set_text(string.format("今日 %.1f kWh · 光周期 %d%%", e.kwh, math.floor(sim.light_curve() * 100 + 0.5)))

        ui.feed_info:set_text("下次自动投喂 " .. sim.remain_text(sim.feed_remain_min()) .. "后")
    end

    function refresh_all()
        if not alive then return end
        refresh_home()
        refresh_devices()

        for _, r in ipairs(ui.rows) do
            local lv = sim.level(r.key)
            pcall(function()
                r.spark:set_items(art.spark_items(184, 16, sim.hist(r.key), theme.state_color(lv)))
            end)
        end

        local list = sim.alarms(6)
        for i = 1, 6 do
            local e = ui.evt[i]
            local a = list[i]
            if a then
                local ac = theme.state_color(a.level)
                e.time:set_text(a.time)
                e.text:set_text(a.text)
                e.text:set_color(a.level == "ok" and C.ink2 or ac)
                e.dot:set_items({{ type = "circle", cx = 2, cy = 2, r = 2, fill = true,
                    fill_color = ac, color = ac, width = 1 }})
            else
                e.time:set_text("")
                e.text:set_text("")
            end
        end
        ui.evt_count:set_text(sim.alarm_count() .. " 条")
    end

    ------------------------------------------------------------------
    -- 动画定时器
    ------------------------------------------------------------------
    local fr = 0
    -- 摆动/波光比鱼群帧慢，用整数分频，避免再起一个定时器
    local sway_every = math.max(1, math.floor((conf.anim.sway_ms / conf.anim.frame_ms) + 0.5))

    -- 由 app 的全局动画节拍驱动：页面自己不起定时器，切页后物理上不可能再有残留回调
    local function anim()
        if not alive then return end
        fr = fr + 1
        local ph = fr * 0.16
        for i, f in ipairs(fishes) do
            local nx = f.x + f.dx
            local lim = TW - f.w - 14
            if nx < 14 then
                nx = 14
                f.dx = math.abs(f.dx)
            elseif nx > lim then
                nx = lim
                f.dx = -math.abs(f.dx)
            end
            f.x = nx
            local dir = f.dx >= 0 and 1 or -1
            if dir ~= f.dir then
                f.dir = dir
                pcall(function() f.shape:set_items(art.fish_items(f.w, f.h, f.color, dir, f.flip)) end)
            end
            local ny = f.base_y + math.sin(ph + i * 2.1) * 9
            pcall(function() f.shape:set_pos(math.floor(f.x), math.floor(ny)) end)
        end
        for _, b in ipairs(bubbles) do
            local by = b.y - b.sp
            if by < 34 then
                by = 246
                b.x = 30 + math.random(0, TW - 90)
            end
            b.y = by
            pcall(function() b.shape:set_pos(math.floor(b.x), math.floor(by)) end)
        end

        if fr % sway_every == 0 then
            spa = spa + 0.42
            pcall(function()
                ui.anemone:set_items(art.anemone_items(46, 54, 34, C.green, spa))
                ui.weed:set_items(art.weed_items(38, 84, 72, C.violet, spa))
                ui.wave:set_items(art.wave_items(TW, spa * 0.5, wave_color))
            end)
        end
    end

    pcall(refresh_all)

    return {
        anim = anim,
        refresh = function()
            if alive then pcall(refresh_home) end
        end,
        tick_minute = function()
            if alive then pcall(refresh_all) end
        end,
        destroy = function()
            alive = false
            fishes, bubbles = {}, {}
        end,
    }
end

return M
