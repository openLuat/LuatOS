--[[
@module  ui_session
@summary 观测计划页：今夜时间轴（暮光+目标可见窗口）、观测队列、曝光计算器
@version 1.0
@date    2026.10.28
]]
local conf  = require("conf")
local theme = require("theme")
local astro = require("astro")

local C = theme.C
local W, H = conf.W, conf.H

local NIGHT_START = 18      -- 时间轴从当地 18:00 开始
local NIGHT_HOURS = 12      -- 到次日 06:00

local function reset(t)
    for i = #t, 1, -1 do t[i] = nil end
    return t
end

--[[计算某天体高度 > thr 的时间窗口（数组 {t0, t1}）
]]
local function windows(obj, t_start, hours, thr)
    local out = {}
    local step = 600
    local lat, lon = conf.site.lat, conf.site.lon
    local n = math.floor(hours * 3600 / step)
    local inwin, s0 = false, nil
    for i = 0, n do
        local t = t_start + i * step
        local alt = astro.horizon(obj.ra, obj.dec, lat, astro.lst(t, lon))
        local ok = alt > thr
        if ok and not inwin then inwin = true; s0 = t end
        if (not ok) and inwin then
            inwin = false
            out[#out + 1] = { s0, t }
        end
    end
    if inwin then out[#out + 1] = { s0, t_start + hours * 3600 } end
    return out
end

local build

build = function(app)
    local page = { arg = nil }
    local st = app.state
    local root = airui.container({
        parent = app.root, x = 0, y = 0, w = W, h = H, color = C.bg1, radius = 0,
    })
    page.root = root
    theme.gradient(root, 0, 0, W, H, C.bg2, C.bg1, 10)

    app.header(root, "今夜观测计划",
        string.format("%s · 波特尔 %d 级 · 北纬 %.2f° 东经 %.2f°",
            conf.site.name, conf.site.bortle, conf.site.lat, conf.site.lon))
    app.nav(root, "session")

    -- 夜景起点：当地 18:00
    local tz = conf.site.tz
    local localnow = st.t + tz * 3600
    local day0 = math.floor(localnow / 86400) * 86400      -- 当地 00:00（已含 tz）
    local t_start = day0 + NIGHT_START * 3600 - tz * 3600   -- 转回 UTC
    local tspan = NIGHT_HOURS * 3600

    -- ==================== 时间轴卡 ====================
    local ct = theme.card(root, 108, 76, 560, 300, C.panel, 14)
    theme.label(ct, 18, 12, 320, 20, "今夜时间轴", 16, C.ink)
    local tl_hint = theme.label(ct, 300, 14, 240, 18, "", 12, C.ink3,
        airui.TEXT_ALIGN_RIGHT)

    local PX, PY, PW, PH = 18, 74, 524, 176
    local function xpos(t)
        local a = (t - t_start) / tspan
        if a < 0 then a = 0 elseif a > 1 then a = 1 end
        return PX + a * PW
    end

    -- 刻度标签
    for h = 0, NIGHT_HOURS, 2 do
        local t = t_start + h * 3600
        theme.label(ct, math.floor(xpos(t)) - 22, PY + PH + 8, 44, 16,
            astro.fmt_hhmm(t, tz), 11, C.ink3, airui.TEXT_ALIGN_CENTER)
    end

    local ok_t, tl_shape = pcall(function()
        return airui.shape({ parent = ct, x = 0, y = 0, w = 560, h = 300, items = {} })
    end)
    tl_shape = ok_t and tl_shape or nil

    -- ==================== 队列卡 ====================
    local cq = theme.card(root, 684, 76, 328, 512, C.panel, 14)
    local qtitle = theme.label(cq, 18, 12, 200, 20, "观测队列", 16, C.ink)
    local qcount = theme.label(cq, 180, 14, 130, 18, "", 12, C.ink3,
        airui.TEXT_ALIGN_RIGHT)

    local qrows = {}
    for i = 1, conf.session.max_queue do
        local y = 44 + (i - 1) * 72
        local row = airui.container({
            parent = cq, x = 12, y = y, w = 304, h = 62,
            color = C.panel2, color_opacity = 255, radius = 10, border_width = 0,
        })
        local nm = theme.label(row, 12, 6, 180, 20, "", 16, C.ink)
        local kd = theme.label(row, 12, 26, 190, 16, "", 11, C.ink3)
        local av = theme.label(row, 200, 8, 60, 20, "", 14, C.cyan,
            airui.TEXT_ALIGN_RIGHT)
        local del = theme.button(row, 250, 32, 46, 22, "移除", 11, C.panel3, C.ink3,
            function() end, 6)
        row:set_hidden(true)
        qrows[i] = { box = row, name = nm, kind = kd, alt = av, del = del, obj = nil }
    end

    -- label 没有 set_hidden，用透明容器包一层来控制显隐
    local empty_box = airui.container({
        parent = cq, x = 18, y = 250, w = 292, h = 60,
        color = C.panel, color_opacity = 0, radius = 0,
    })
    theme.label(empty_box, 0, 0, 292, 60,
        "队列还是空的\n在星图中点选星点，或使用\n「此刻最值得看的目标」加入", 13, C.ink3,
        airui.TEXT_ALIGN_CENTER)

    -- ==================== 曝光计算器 ====================
    local ce = theme.card(root, 108, 388, 560, 200, C.panel, 14)
    theme.label(ce, 18, 12, 260, 20, "曝光计算器", 16, C.ink)
    theme.label(ce, 18, 34, 300, 16, "按 500 法则估算星点拖线极限", 11, C.ink3)

    local ex = st.exposure
    local sl_focal = theme.slider(ce, 18, 62, 300, 10, 100, 1200, ex.focal, C.cyan, nil)
    local sl_aper  = theme.slider(ce, 18, 116, 300, 10, 30, 300, ex.aperture, C.violet, nil)
    local sl_iso   = theme.slider(ce, 18, 170, 300, 10, 400, 12800, ex.iso, C.amber, nil)

    local f_lb = theme.label(ce, 328, 56, 90, 18, "", 14, C.ink)
    local a_lb = theme.label(ce, 328, 110, 90, 18, "", 14, C.ink)
    local i_lb = theme.label(ce, 328, 164, 90, 18, "", 14, C.ink)
    theme.label(ce, 18, 44, 60, 16, "焦距", 11, C.ink3)
    theme.label(ce, 18, 98, 60, 16, "口径", 11, C.ink3)
    theme.label(ce, 18, 152, 60, 16, "ISO", 11, C.ink3)

    local exp_big = theme.label(ce, 392, 46, 150, 46, "--", 34, C.cyan,
        airui.TEXT_ALIGN_CENTER)
    local exp_unit = theme.label(ce, 392, 90, 150, 16, "秒", 11, C.ink3,
        airui.TEXT_ALIGN_CENTER)
    local exp_ratio = theme.label(ce, 380, 112, 174, 18, "", 12, C.ink3,
        airui.TEXT_ALIGN_CENTER)
    local exp_tip = theme.label(ce, 380, 134, 174, 40, "", 11, C.ink3,
        airui.TEXT_ALIGN_CENTER)
    _ = exp_unit

    -- ==================== 时间轴绘制 ====================
    local items = {}
    local dark = astro.twilight(t_start, conf.site.lat, conf.site.lon)

    local function draw_timeline()
        if not tl_shape then return end
        reset(items)

        -- 底色
        items[#items + 1] = { type = "rect", x = PX, y = PY, w = PW, h = PH,
            color = 0x0A1226, width = 0, fill = true,
            fill_color = 0x0A1226, fill_opacity = 255 }

        -- 夜空背景：暮光结束 -> 晨光开始 的深色块（用竖条渐变模拟）
        local function shade(t_from, t_to, color, opa)
            if not t_from or not t_to then return end
            local x1, x2 = xpos(t_from), xpos(t_to)
            if x2 <= x1 then return end
            items[#items + 1] = { type = "rect", x = math.floor(x1), y = PY,
                w = math.floor(x2 - x1), h = PH, color = color, width = 0,
                fill = true, fill_color = color, fill_opacity = opa }
        end
        shade(t_start, dark.civil_end, 0x1B2A4A, 90)
        shade(dark.civil_end, dark.naut_end, 0x14203A, 140)
        shade(dark.naut_end, dark.astro_end, 0x0C1428, 190)
        shade(dark.astro_end, dark.astro_begin, 0x060B18, 230)
        shade(dark.astro_begin, dark.naut_begin or dark.civil_begin, 0x0C1428, 190)
        shade(dark.naut_begin or dark.civil_begin, dark.civil_begin, 0x14203A, 140)
        shade(dark.civil_begin, t_start + tspan, 0x1B2A4A, 90)

        -- 网格与刻度
        for h = 0, NIGHT_HOURS, 1 do
            local x = xpos(t_start + h * 3600)
            items[#items + 1] = { type = "line", x1 = x, y1 = PY, x2 = x, y2 = PY + PH,
                color = C.line, width = 1, opacity = (h % 2 == 0) and 90 or 50 }
        end
        items[#items + 1] = { type = "rect", x = PX, y = PY, w = 1, h = PH,
            color = C.line2, width = 0, fill = true, fill_color = C.line2, fill_opacity = 160 }

        -- 淡蓝/晨红线
        local function mark(t, color, label_y)
            if not t then return end
            local x = xpos(t)
            items[#items + 1] = { type = "line", x1 = x, y1 = PY - 8, x2 = x, y2 = PY + PH,
                color = color, width = 1, opacity = 200, dash_width = 4, dash_gap = 4 }
            _ = label_y
        end
        mark(dark.astro_end, 0x4E7BFF)
        mark(dark.astro_begin, 0xFFB347)

        -- 每个目标的可见窗口条
        local lanes = 0
        for _, obj in ipairs(st.queue) do
            local ws = windows(obj, t_start, NIGHT_HOURS, 20)
            local lane_h = 18
            local y = PY + 14 + lanes * (lane_h + 6)
            if y + lane_h > PY + PH - 4 then break end
            lanes = lanes + 1
            -- 轨道线
            items[#items + 1] = { type = "line", x1 = PX, y1 = y + lane_h, x2 = PX + PW,
                y2 = y + lane_h, color = C.line, width = 1, opacity = 45 }
            for _, w in ipairs(ws) do
                local x1, x2 = xpos(w[1]), xpos(w[2])
                if x2 - x1 >= 2 then
                    items[#items + 1] = { type = "rect", x = math.floor(x1),
                        y = y, w = math.floor(x2 - x1), h = lane_h,
                        radius = 6, color = C.cyan, width = 0,
                        fill = true, fill_color = C.cyan, fill_opacity = 130 }
                end
            end
        end

        -- 当前时刻指针
        local nx = xpos(st.t)
        items[#items + 1] = { type = "line", x1 = nx, y1 = PY - 10, x2 = nx, y2 = PY + PH,
            color = C.amber, width = 2, opacity = 230 }
        items[#items + 1] = { type = "circle", cx = nx, cy = PY - 10, r = 4,
            color = C.amber, fill = true, fill_color = C.amber, fill_opacity = 255, width = 0 }

        if theme.night then
            for i = 1, #items do
                local it = items[i]
                it.color = theme.tint(it.color)
                if it.fill_color then it.fill_color = theme.tint(it.fill_color) end
            end
        end
        tl_shape:set_items(items)
    end

    -- ==================== 队列刷新 ====================
    local function refresh_queue()
        local n = #st.queue
        qcount:set_text(string.format("%d / %d", n, conf.session.max_queue))
        qtitle:set_text("观测队列")
        empty_box:set_hidden(n > 0)
        for i = 1, conf.session.max_queue do
            local row = qrows[i]
            local obj = st.queue[i]
            if obj then
                row.box:set_hidden(false)
                row.obj = obj
                row.name:set_text(obj.cn)
                row.kind:set_text(obj.kind or "恒星")
                local alt = astro.horizon(obj.ra, obj.dec, conf.site.lat, app.lst())
                row.alt:set_text(string.format("%.0f°", alt))
                row.alt:set_color(theme.tint(alt > 25 and C.green or
                    (alt > 0 and C.amber or C.ink3)))
                local id = obj.id
                row.del:set_on_click(function()
                    app.queue_remove(id)
                    app.go("session")
                    app.toast("已移出观测队列")
                end)
                local obj_ = obj
                row.box:set_on_click(function()
                    st.selected = obj_
                    app.go("object", obj_)
                end)
            else
                row.box:set_hidden(true)
            end
        end
    end

    -- ==================== 曝光刷新 ====================
    local function refresh_exposure()
        if not (sl_focal and sl_aper and sl_iso) then return end
        local f = sl_focal:get_value()
        local a = sl_aper:get_value()
        local iso = sl_iso:get_value()
        ex.focal, ex.aperture, ex.iso = f, a, iso

        f_lb:set_text(string.format("%d mm", f))
        a_lb:set_text(string.format("%d mm", a))
        i_lb:set_text(string.format("%d", iso))

        local fratio = f / math.max(a, 1)
        f_lb:set_color(theme.tint(fratio < 5 and C.green or (fratio < 8 and C.ink or C.amber)))
        a_lb:set_color(theme.tint(C.ink))

        -- 500 法则拖线极限（全画幅等效）
        local trail = 500 / math.max(f, 1)
        -- 建议曝光：ISO 3200 基准，随 ISO 反比缩放
        local base = 2 ^ (6.2 - 4.5)      -- 用于深空的基准
        local expo = base * (3200 / math.max(iso, 100)) * (fratio / 5) ^ 2 * 4
        local target = st.selected and st.selected.mag or 6
        expo = expo * (2 ^ (math.max(6 - target, 0) * 0.35))
        if expo < 1 then expo = 1 end
        if expo > 3600 then expo = 3600 end

        local need_track = expo > trail
        exp_big:set_text(string.format("%.0f", math.min(expo, 999)))
        exp_big:set_color(theme.tint(need_track and C.amber or C.cyan))
        exp_ratio:set_text(string.format("拖线极限 %.1f 秒", trail))
        if need_track then
            exp_tip:set_text("超出单张极限\n需赤道仪跟踪或叠加多张")
            exp_tip:set_color(theme.tint(C.amber))
        else
            exp_tip:set_text("可单张直拍\n三脚架固定即可")
            exp_tip:set_color(theme.tint(C.green))
        end
    end

    local frame = 0
    page.tick = function()
        frame = frame + 1
        if frame % 5 == 1 then refresh_exposure() end
        if frame % 10 == 1 then
            draw_timeline()
            refresh_queue()
        end
        if frame % 25 == 1 then
            tl_hint:set_text("此刻 " .. astro.fmt_hhmm(st.t, tz))
        end
    end

    page.touch = nil

    draw_timeline()
    refresh_queue()
    refresh_exposure()
    tl_hint:set_text("此刻 " .. astro.fmt_hhmm(st.t, tz))

    return page
end

return build
