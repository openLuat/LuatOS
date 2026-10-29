--[[
@module  ui_object
@summary 天体详情页：实时地平方位、12 小时高度轨迹、升落/中天时刻、加入观测队列
@version 1.0
@date    2026.10.28
]]
local conf  = require("conf")
local theme = require("theme")
local astro = require("astro")

local C = theme.C
local W = conf.W

local SPAN_H = 12          -- 轨迹窗口：12 小时
local START_OFF = -3       -- 从 3 小时前开始

local function reset(t)
    for i = #t, 1, -1 do t[i] = nil end
    return t
end

local function build(app, obj)
    local page = { arg = obj }
    local st = app.state
    local items = {}
    local lat, lon = conf.site.lat, conf.site.lon

    if not obj then obj = { id = "none", cn = "未知", ra = 0, dec = 0, mag = 0 } end

    local root = airui.container({
        parent = app.root, x = 0, y = 0, w = W, h = conf.H, color = C.bg1, radius = 0,
    })
    page.root = root
    theme.gradient(root, 0, 0, W, conf.H, C.bg2, C.bg1, 10)

    local is_dso = obj.kind ~= nil
    local sub = is_dso and (obj.kind .. " · " .. (obj.cn or "")) or
        ((obj.bayer or "") .. " · " .. (obj.con_cn or ""))
    local _, sub_clock = app.header(root, obj.cn or "未知天体", sub)
    _ = sub_clock

    app.nav(root, "sky")

    -- ==================== 卡 A：基本信息 ====================
    local ca = theme.card(root, 108, 76, 292, 232, C.panel, 14)
    theme.accent_bar(ca, 16, 16, 40, is_dso and C.violet or C.cyan)
    theme.label(ca, 16, 28, 260, 40, obj.cn or "", 28, C.ink)
    theme.label(ca, 16, 68, 260, 20, is_dso and obj.kind or (obj.bayer or ""), 14, C.violet)
    theme.hline(ca, 16, 96, 260, C.line)

    local rows = {
        { "视星等", string.format("%.1f", obj.mag or 0) },
        { "赤经", astro.fmt_ra(obj.ra) },
        { "赤纬", astro.fmt_dec(obj.dec) },
        { "所属", is_dso and "深空" or (obj.con_cn or "-") },
    }
    for i, r in ipairs(rows) do
        local y = 106 + (i - 1) * 30
        theme.label(ca, 16, y, 90, 20, r[1], 13, C.ink3)
        theme.label(ca, 100, y, 176, 20, r[2], 15, C.ink, airui.TEXT_ALIGN_RIGHT)
    end

    -- ==================== 卡 B：实时状态 ====================
    local cb = theme.card(root, 108, 320, 292, 268, C.panel, 14)
    theme.label(cb, 16, 12, 200, 18, "此刻状态", 14, C.ink2)

    local alt_lb = theme.label(cb, 16, 34, 160, 52, "--", 42, C.cyan)
    local alt_unit = theme.label(cb, 24, 84, 40, 16, "度", 12, C.ink3)
    _ = alt_unit
    local az_lb = theme.label(cb, 150, 44, 130, 24, "", 16, C.ink2, airui.TEXT_ALIGN_RIGHT)
    local vis_lb = theme.label(cb, 150, 68, 130, 18, "", 12, C.ink3, airui.TEXT_ALIGN_RIGHT)

    -- 方位罗盘
    local okc, compass = pcall(function()
        return airui.shape({ parent = cb, x = 166, y = 100, w = 110, h = 110, items = {} })
    end)
    compass = okc and compass or nil
    theme.label(cb, 166 + 41, 92, 28, 16, "N", 11, C.ink3, airui.TEXT_ALIGN_CENTER)

    theme.hline(cb, 16, 218, 260, C.line)
    local kv2 = {}
    local names = { "最高高度", "中天时刻", "升起", "落下" }
    for i = 1, 4 do
        local y = 224 + math.floor((i - 1) / 2) * 22
        local x = ((i - 1) % 2 == 0) and 16 or 150
        theme.label(cb, x, y, 60, 16, names[i], 11, C.ink3)
        kv2[i] = theme.label(cb, x + 56, y, 74, 16, "--", 12, C.ink,
            airui.TEXT_ALIGN_RIGHT)
    end

    -- ==================== 卡 C：高度轨迹 ====================
    local cc = theme.card(root, 412, 76, 600, 372, C.panel, 14)
    theme.label(cc, 20, 12, 300, 20, "12 小时地平高度轨迹", 15, C.ink)
    local curve_hint = theme.label(cc, 300, 14, 280, 18, "", 12, C.ink3,
        airui.TEXT_ALIGN_RIGHT)

    local PX, PY, PW, PH = 52, 40, 516, 282
    -- y: alt 90 -> PY, alt -40 -> PY+PH
    local function ypos(alt)
        local a = (90 - alt) / 130
        if a < 0 then a = 0 elseif a > 1 then a = 1 end
        return PY + a * PH
    end

    -- 坐标轴标签
    for _, alt in ipairs({ 0, 30, 60 }) do
        theme.label(cc, 14, math.floor(ypos(alt)) - 9, 34, 16, tostring(alt), 11,
            C.ink3, airui.TEXT_ALIGN_RIGHT)
    end
    theme.label(cc, 14, math.floor(ypos(-30)) - 9, 34, 16, "-30", 11, C.ink3,
        airui.TEXT_ALIGN_RIGHT)

    local t0 = math.floor(st.t / 3600) * 3600 + START_OFF * 3600
    local tspan = SPAN_H * 3600
    local function xpos(t)
        local a = (t - t0) / tspan
        if a < 0 then a = 0 elseif a > 1 then a = 1 end
        return PX + a * PW
    end

    local hour_lbs, hour_offs = {}, {}
    for h = 0, SPAN_H, 2 do
        local t = t0 + h * 3600
        local hx = math.floor(xpos(t)) - 20
        local lb = theme.label(cc, hx, PY + PH + 8, 40, 16,
            astro.fmt_hhmm(t, conf.site.tz), 11, C.ink3, airui.TEXT_ALIGN_CENTER)
        hour_lbs[#hour_lbs + 1] = lb
        hour_offs[#hour_offs + 1] = h
    end

    local ok_t, track = pcall(function()
        return airui.shape({ parent = cc, x = 0, y = 0, w = 600, h = 372, items = {} })
    end)
    track = ok_t and track or nil

    -- ==================== 卡 D：时刻与操作 ====================
    local cd = theme.card(root, 412, 460, 600, 128, C.panel, 14)
    theme.label(cd, 20, 12, 300, 18, "今晚观测窗口", 14, C.ink2)

    local win_segs = {}
    for i = 1, 34 do
        win_segs[i] = theme.box(cd, 20 + (i - 1) * 10, 40, 8, 10, C.line, 4)
    end

    local rise_lb = theme.label(cd, 20, 58, 340, 18, "", 12, C.ink3)
    local transit_lb = theme.label(cd, 20, 78, 340, 18, "", 12, C.ink3)
    local max_lb = theme.label(cd, 20, 98, 340, 18, "", 12, C.ink3)

    local qbtn = theme.button(cd, 384, 30, 190, 42, "加入观测队列", 16,
        C.cyan, 0x061019, function() end, 10)
    local backbtn = theme.ghost_button(cd, 384, 80, 190, 34, "返回星图", 14,
        C.ink2, function() app.go("sky") end)
    _ = backbtn

    if app.in_queue(obj.id) then
        qbtn:set_text("已在队列中")
        qbtn:set_style({
            bg_color = theme.tint(C.panel3), bg_opa = 255,
            text_color = theme.tint(C.ink3), radius = 10, border_width = 1,
            border_color = theme.tint(C.line2),
        })
    else
        qbtn:set_on_click(function()
            local ok, msg = app.queue_add(obj)
            app.toast(msg, ok and C.green or C.amber)
            if ok then
                qbtn:set_text("已在队列中")
                qbtn:set_style({
                    bg_color = theme.tint(C.panel3), bg_opa = 255,
                    text_color = theme.tint(C.ink3), radius = 10, border_width = 1,
                    border_color = theme.tint(C.line2),
                })
            end
        end)
    end

    -- ==================== 绘制 ====================
    local samples = astro.track(obj.ra, obj.dec, lat, lon, t0, SPAN_H, 6)
    local win_key = nil

    --[[滚动时间窗：仿真时间每推进 30 分钟就重采样一次轨迹，
让“当前时刻”始终落在窗口中间偏左的位置
]]
    local function resample()
        local key = math.floor(st.t / 1800)
        if key == win_key then return end
        win_key = key
        t0 = math.floor(st.t / 1800) * 1800 + START_OFF * 3600
        samples = astro.track(obj.ra, obj.dec, lat, lon, t0, SPAN_H, 6)
        for i = 1, #hour_lbs do
            local tt = t0 + hour_offs[i] * 3600
            hour_lbs[i]:set_pos(math.floor(xpos(tt)) - 20, PY + PH + 8)
            hour_lbs[i]:set_text(astro.fmt_hhmm(tt, conf.site.tz))
        end
    end

    local function draw_track()
        if not track then return end
        reset(items)

        -- 网格
        for _, alt in ipairs({ 60, 30, 0 }) do
            local y = ypos(alt)
            items[#items + 1] = { type = "line", x1 = PX, y1 = y, x2 = PX + PW, y2 = y,
                color = (alt == 0) and C.line2 or C.line,
                width = (alt == 0) and 2 or 1, opacity = (alt == 0) and 200 or 90,
                dash_width = (alt == 0) and 0 or 4, dash_gap = (alt == 0) and 0 or 8 }
        end
        for h = 0, SPAN_H, 2 do
            local x = xpos(t0 + h * 3600)
            items[#items + 1] = { type = "line", x1 = x, y1 = PY, x2 = x, y2 = PY + PH,
                color = C.line, width = 1, opacity = 60, dash_width = 3, dash_gap = 9 }
        end

        -- 曲线
        local prev
        local max_alt = -90
        for i = 1, #samples do
            local s = samples[i]
            if s.alt > max_alt then max_alt = s.alt end
            local px, py = xpos(s.t), ypos(s.alt)
            if prev then
                local above = (s.alt > 0 and prev.alt > 0)
                items[#items + 1] = { type = "line", x1 = prev.x, y1 = prev.y,
                    x2 = px, y2 = py,
                    color = above and C.cyan or 0x3A4A6A,
                    width = above and 2 or 1,
                    opacity = above and 210 or 90,
                    dash_width = above and 0 or 3, dash_gap = above and 0 or 6 }
            end
            prev = { x = px, y = py, alt = s.alt }
        end

        -- 曲线下方柔和填充（用竖直短线近似）
        prev = nil
        for i = 1, #samples, 2 do
            local s = samples[i]
            if s.alt > 0 then
                local px = xpos(s.t)
                local py = ypos(s.alt)
                local gy = ypos(0)
                if gy - py > 2 then
                    items[#items + 1] = { type = "line", x1 = px, y1 = py, x2 = px, y2 = gy,
                        color = C.cyan, width = 6, opacity = 14 }
                end
            end
        end

        -- 当前位置
        local nx = xpos(st.t)
        items[#items + 1] = { type = "line", x1 = nx, y1 = PY - 6, x2 = nx, y2 = PY + PH,
            color = C.amber, width = 1, opacity = 180, dash_width = 4, dash_gap = 4 }
        local alt_now, az_now = app.altaz(obj)
        if alt_now > -40 then
            items[#items + 1] = { type = "circle", cx = nx, cy = ypos(alt_now), r = 5,
                color = C.amber, fill = true, fill_color = C.amber,
                fill_opacity = 255, width = 0 }
        end
        _ = az_now

        if theme.night then
            for i = 1, #items do
                local it = items[i]
                it.color = theme.tint(it.color)
                if it.fill_color then it.fill_color = theme.tint(it.fill_color) end
            end
        end
        track:set_items(items)
        curve_hint:set_text(string.format("峰值 %.0f°", max_alt))
    end

    local function draw_compass(alt, az)
        if not compass then return end
        local it = {}
        local cx, cy, r = 55, 55, 42
        it[1] = { type = "circle", cx = cx, cy = cy, r = r, color = C.line2, width = 1, opacity = 160 }
        it[2] = { type = "circle", cx = cx, cy = cy, r = r - 12, color = C.line, width = 1, opacity = 80 }
        for _, a in ipairs({ 0, 90, 180, 270 }) do
            local rad = a * math.pi / 180
            it[#it + 1] = { type = "line",
                x1 = cx + (r - 6) * math.sin(rad), y1 = cy - (r - 6) * math.cos(rad),
                x2 = cx + r * math.sin(rad), y2 = cy - r * math.cos(rad),
                color = C.ink3, width = 1, opacity = 140 }
        end
        -- 视线方向指针（长度随高度变化）
        local rad = az * math.pi / 180
        local rr = (r - 8) * (1 - alt / 120)
        it[#it + 1] = { type = "line", x1 = cx, y1 = cy,
            x2 = cx + rr * math.sin(rad), y2 = cy - rr * math.cos(rad),
            color = C.cyan, width = 3, round_end = true, opacity = 230 }
        it[#it + 1] = { type = "circle", cx = cx, cy = cy, r = 3,
            color = C.cyan, fill = true, fill_color = C.cyan, fill_opacity = 255, width = 0 }
        if theme.night then
            for i = 1, #it do
                local t = it[i]
                t.color = theme.tint(t.color)
                if t.fill_color then t.fill_color = theme.tint(t.fill_color) end
            end
        end
        compass:set_items(it)
    end

    local function refresh()
        local alt, az = app.altaz(obj)
        alt_lb:set_text(string.format("%.0f", alt))
        alt_lb:set_color(theme.tint(alt > 0 and C.cyan or C.ink3))
        az_lb:set_text(string.format("%s %.0f°", astro.compass(az), az))
        vis_lb:set_text(alt > 0 and "地平线以上" or "地平线以下")
        vis_lb:set_color(theme.tint(alt > 0 and C.green or C.ink3))

        local maxalt = 90 - math.abs(lat - obj.dec)
        kv2[1]:set_text(string.format("%.0f°", maxalt))
        local tr = astro.transit(obj.ra, lon, st.t)
        kv2[2]:set_text(astro.fmt_hhmm(tr, conf.site.tz))

        local hour0 = math.floor(st.t / 3600) * 3600
        local rise, set = astro.rise_set(obj.ra, obj.dec, lat, lon, hour0, 86400)
        kv2[3]:set_text(rise and astro.fmt_hhmm(rise, conf.site.tz) or "不升")
        kv2[4]:set_text(set and astro.fmt_hhmm(set, conf.site.tz) or "不落")

        -- 未来 24 小时可见窗口：34 段，每段约 42 分钟
        local seg = 86400 / 34
        for i = 1, 34 do
            local ts = hour0 + (i - 0.5) * seg
            local a = astro.horizon(obj.ra, obj.dec, lat, astro.lst(ts, lon))
            win_segs[i]:set_color(theme.tint(a > 0 and C.green or C.line))
        end

        if alt > 0 then
            rise_lb:set_text("此刻已在地平线上")
            if set then
                max_lb:set_text(string.format("可观测至 %s，约 %.1f 小时",
                    astro.fmt_hhmm(set, conf.site.tz),
                    math.max(0, (set - st.t) / 3600)))
            else
                max_lb:set_text("未来 24 小时不落（拱极星）")
            end
        elseif rise and set and set > rise then
            rise_lb:set_text("升起 " .. astro.fmt_hhmm(rise, conf.site.tz) ..
                "   落下 " .. astro.fmt_hhmm(set, conf.site.tz))
            max_lb:set_text(string.format("可观测 %.1f 小时", (set - rise) / 3600))
        else
            rise_lb:set_text("未来 24 小时不升（拱极或不可见）")
            max_lb:set_text(string.format("最高高度 %.0f°", maxalt))
        end
        transit_lb:set_text("中天 " .. astro.fmt_hhmm(tr, conf.site.tz) ..
            string.format("，届时高度 %.0f°", maxalt))

        draw_compass(alt, az)
    end

    local frame = 0
    page.tick = function()
        frame = frame + 1
        resample()
        draw_track()
        if frame % 10 == 1 then refresh() end
    end

    page.touch = nil
    draw_track()
    refresh()

    return page
end

return build
