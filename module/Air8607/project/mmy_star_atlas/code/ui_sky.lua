--[[
@module  ui_sky
@summary 全天星图页：方位等距投影的实时星空 + 今夜观测条件 + 目标推荐 + 时间流速
@version 1.0
@date    2026.10.28
]]
local conf  = require("conf")
local theme = require("theme")
local astro = require("astro")
local data  = require("star_data")

local C = theme.C
local W, H = conf.W, conf.H

-- 星图几何
local R  = conf.sky.radius
local CX, CY = 100 + R, 330
local DX, DY = CX - R, CY - R          -- 星图左上角（屏幕坐标）
local DS = R * 2

local SPEED_TEXT = { "1x", "1分", "5分", "30分", "2时" }

local function reset(t)
    for i = #t, 1, -1 do t[i] = nil end
    return t
end

-- 星点视觉尺寸（星等 -> 半径）
local function star_radius(mag)
    local r = 4.8 - mag * 0.85
    if r < 1.1 then r = 1.1 end
    if r > 5.4 then r = 5.4 end
    return r
end

local function star_opa(mag)
    local o = 255 - (mag + 1.6) * 34
    if o < 70 then o = 70 end
    if o > 255 then o = 255 end
    return o
end

local function build(app)
    local page = { arg = nil }
    local st = app.state
    local items = {}

    local root = airui.container({
        parent = app.root, x = 0, y = 0, w = W, h = H, color = C.bg1, radius = 0,
    })
    page.root = root
    theme.gradient(root, 0, 0, W, H, C.bg2, C.bg1, 10)

    local title_lb, sub_lb = app.header(root, conf.name,
        "NIGHT SKY OBSERVATORY · " .. conf.site.name)

    app.nav(root, "sky")

    -- ==================== 星图 ====================
    local disc = airui.container({
        parent = root, x = DX, y = DY, w = DS, h = DS,
        color = 0x02040A, color_opacity = 255, radius = R,
        border_width = 1, border_color = theme.tint(C.line2),
    })

    local ok_shape, sky_shape = pcall(function()
        return airui.shape({ parent = disc, x = 0, y = 0, w = DS, h = DS, items = {} })
    end)
    if not ok_shape then
        log.error("ui_sky", "shape 创建失败", tostring(sky_shape))
    end

    -- 方位标记（固定不动）
    theme.label(disc, R - 14, 4, 28, 18, "N", 14, C.ink3, airui.TEXT_ALIGN_CENTER)
    theme.label(disc, R - 14, DS - 24, 28, 18, "S", 14, C.ink3, airui.TEXT_ALIGN_CENTER)
    theme.label(disc, 4, R - 9, 24, 18, "W", 14, C.ink3, airui.TEXT_ALIGN_CENTER)
    theme.label(disc, DS - 28, R - 9, 24, 18, "E", 14, C.ink3, airui.TEXT_ALIGN_CENTER)

    theme.label(root, DX + 12, DY + DS + 4, DS - 24, 20,
        "方位等距投影  圆心=天顶  点击星点查看详情", 13, C.ink3,
        airui.TEXT_ALIGN_CENTER)

    -- 八个主要星座名（跟随星空移动；label 无 set_hidden，落地平线以下时清空文字）
    local CON_LABELS = {
        { "猎户座", "rigel" }, { "大熊座", "dubhe" }, { "仙后座", "schedar" },
        { "天鹅座", "deneb" }, { "天琴座", "vega" }, { "天蝎座", "antares" },
        { "牧夫座", "arcturus" }, { "金牛座", "aldebaran" },
    }
    local con_lbs = {}
    for _, c in ipairs(CON_LABELS) do
        local s = data.byid[c[2]]
        if s then
            con_lbs[#con_lbs + 1] = {
                name = c[1], ra = s.ra, dec = s.dec,
                lb = theme.label(disc, -100, -100, 64, 18, "", 12, C.ink3,
                    airui.TEXT_ALIGN_CENTER),
            }
        end
    end

    -- ==================== 右下：时间控制 ====================
    local ctrl = theme.card(root, 580, 486, 432, 100, C.panel, 12)
    theme.label(ctrl, 16, 10, 200, 18, "时间流速", 13, C.ink3)

    local speed_lb = theme.label(ctrl, 16, 32, 150, 30, "300x", 24, C.cyan)
    local clock_lb = theme.label(ctrl, 120, 34, 300, 18, "", 13, C.ink2)

    local pause_btn = theme.button(ctrl, 16, 62, 76, 28,
        st.paused and "继续" or "暂停", 14, C.panel3, C.ink, function() end, 8)
    pause_btn:set_style({
        bg_color = theme.tint(C.panel3), bg_opa = 255,
        text_color = theme.tint(C.ink), radius = 8,
        border_width = 1, border_color = theme.tint(C.line2),
        pressed_bg_color = theme.tint(C.line2), pressed_text_color = theme.tint(C.white),
    })

    local spd_btns = {}
    for i = 1, #conf.time.speeds do
        local bx = 104 + (i - 1) * 42
        local b = theme.button(ctrl, bx, 62, 38, 28, SPEED_TEXT[i], 13,
            st.speed_i == i and C.cyan or C.panel3,
            st.speed_i == i and 0x061019 or C.ink2,
            function() end, 8)
        spd_btns[i] = b
    end

    local night_btn = theme.button(ctrl, 322, 62, 94, 28,
        app.theme.night and "夜视 开" or "夜视 关", 13,
        app.theme.night and C.red or C.panel3,
        app.theme.night and 0x1B0400 or C.ink2, function() end, 8)

    local function sync_speed()
        for i = 1, #spd_btns do
            local on = (st.speed_i == i)
            spd_btns[i]:set_style({
                bg_color = theme.tint(on and C.cyan or C.panel3),
                bg_opa = 255,
                text_color = theme.tint(on and 0x061019 or C.ink2),
                radius = 8, border_width = 0,
                pressed_bg_color = theme.tint(C.line2),
                pressed_text_color = theme.tint(C.white),
            })
        end
        speed_lb:set_text(tostring(app.speed()) .. "x")
    end

    for i = 1, #spd_btns do
        spd_btns[i]:set_on_click(function()
            st.speed_i = i
            sync_speed()
            app.toast("时间流速 " .. app.speed() .. "x")
        end)
    end

    pause_btn:set_on_click(function()
        st.paused = not st.paused
        pause_btn:set_text(st.paused and "继续" or "暂停")
        app.toast(st.paused and "星图已暂停" or "星图继续推进")
    end)

    night_btn:set_on_click(function()
        app.theme.night = not app.theme.night
        app.go("sky")
        app.toast(app.theme.night and "夜视红光模式：保护暗适应" or "已恢复彩色模式")
    end)

    -- ==================== 右上：观测条件 ====================
    local cond = theme.card(root, 580, 76, 432, 150, C.panel, 12)
    theme.label(cond, 16, 10, 240, 20, "今夜观测条件", 15, C.ink)
    local idx_lb = theme.label(cond, 16, 34, 90, 46, "--", 38, C.green)
    local idx_tip = theme.label(cond, 100, 50, 120, 18, "指数", 13, C.ink3)

    -- 指数刻度条（24 段电平表）
    local idx_segs = {}
    for i = 1, 24 do
        idx_segs[i] = theme.box(cond, 16 + (i - 1) * 10, 86, 8, 8, C.line, 2)
    end

    local kv = {}
    local names = { "云量", "视宁", "透明度" }
    for i = 1, 3 do
        local y = 102 + (i - 1) * 16
        theme.label(cond, 16, y - 2, 44, 16, names[i], 12, C.ink3)
        local segs = {}
        for k = 1, 14 do
            segs[k] = theme.box(cond, 62 + (k - 1) * 10, y + 3, 8, 5, C.line, 2)
        end
        local vl = theme.label(cond, 208, y - 2, 46, 16, "--", 12, C.ink2,
            airui.TEXT_ALIGN_RIGHT)
        kv[i] = { segs = segs, lb = vl }
    end

    -- 月相图形
    local moon_shape
    local ok2, ms = pcall(function()
        return airui.shape({ parent = cond, x = 286, y = 26, w = 120, h = 110, items = {} })
    end)
    if ok2 then moon_shape = ms end
    local moon_lb = theme.label(cond, 270, 126, 152, 18, "", 12, C.ink3,
        airui.TEXT_ALIGN_CENTER)

    -- ==================== 右下上：目标推荐 ====================
    local rec = theme.card(root, 580, 238, 432, 236, C.panel, 12)
    theme.label(rec, 16, 10, 260, 20, "此刻最值得看的目标", 15, C.ink)
    local rec_hint = theme.label(rec, 250, 12, 166, 18, "", 12, C.ink3,
        airui.TEXT_ALIGN_RIGHT)

    local rows = {}
    for i = 1, 4 do
        local y = 38 + (i - 1) * 48
        local row = airui.container({
            parent = rec, x = 10, y = y, w = 412, h = 44,
            color = C.panel2, color_opacity = 255, radius = 10,
            border_width = 0,
        })
        local name = theme.label(row, 12, 4, 150, 20, "--", 16, C.ink)
        local kind = theme.label(row, 12, 23, 150, 16, "", 11, C.ink3)
        local segs = {}
        for k = 1, 12 do
            segs[k] = theme.box(row, 168 + (k - 1) * 9, 30, 7, 4, C.line, 2)
        end
        local altv = theme.label(row, 276, 6, 62, 18, "", 14, C.ink,
            airui.TEXT_ALIGN_RIGHT)
        local gobtn = theme.button(row, 348, 8, 54, 28, "查看", 12, C.panel3, C.ink2,
            function() end, 8)
        rows[i] = { box = row, name = name, kind = kind, segs = segs,
                    altv = altv, btn = gobtn, obj = nil }
    end

    -- ==================== 星图绘制 ====================
    local hit = {}
    local sel_id = st.selected and st.selected.id or nil
    local last_lst, last_sel = nil, nil
    local cand = data.dso_list()

    --[[重绘星图
作用：把当前时刻的天体投到方位等距圆盘上
参数：force 为 true 时强制重绘（首帧/菜单位变化）
说明：低流速时恒星位移不足 1px，跳过重绘可省 CPU
]]
    local function draw_sky(force)
        if not sky_shape then return end
        local t = st.t
        local lst = astro.lst(t, conf.site.lon)
        local cur_sel = st.selected and st.selected.id or nil
        if not force and last_lst and last_sel == cur_sel
            and math.abs(lst - last_lst) < 0.004 then
            return
        end
        last_lst, last_sel = lst, cur_sel
        reset(items)
        hit = {}

        local lat = conf.site.lat

        -- 盘面：由内向外 4 层同心圆，模拟天顶辉光
        items[#items + 1] = { type = "circle", cx = R, cy = R, r = R - 2,
            color = C.line2, width = 2, opacity = theme.night and 90 or 140 }
        for k = 1, 4 do
            items[#items + 1] = { type = "circle", cx = R, cy = R,
                r = (R - 10) * k / 4, color = C.line, width = 1,
                opacity = 26 + k * 8, dash_width = 3, dash_gap = 7 }
        end
        -- 方位十字
        for _, ang in ipairs({ 0, 90, 180, 270 }) do
            local a = ang * math.pi / 180
            items[#items + 1] = { type = "line",
                x1 = R + (R - 12) * math.sin(a), y1 = R - (R - 12) * math.cos(a),
                x2 = R - (R - 12) * math.sin(a), y2 = R + (R - 12) * math.cos(a),
                color = C.line2, width = 1, opacity = 45, dash_width = 4, dash_gap = 8 }
        end
        -- 天顶标记
        items[#items + 1] = { type = "circle", cx = R, cy = R, r = 3,
            color = C.cyan, fill = true, fill_color = C.cyan, opacity = 120, width = 1 }

        -- 银河带
        local prev
        for _, p in ipairs(data.milkyway) do
            local alt, az = astro.horizon(p[1], p[2], lat, lst)
            local px, py
            if alt > 0 then
                px, py = astro.project(alt, az, R, R, R - 4)
            end
            if not px then
                prev = nil
            else
                if prev then
                    items[#items + 1] = { type = "line", x1 = prev[1], y1 = prev[2],
                        x2 = px, y2 = py, color = 0x6E8AC0, width = 30,
                        opacity = theme.night and 6 or 14, round_start = true, round_end = true }
                end
                prev = { px, py }
            end
        end

        -- 星座连线
        if st.lines then
            for _, ln in ipairs(data.lines) do
                local s1, s2 = data.byid[ln[1]], data.byid[ln[2]]
                if s1 and s2 then
                    local a1, z1 = astro.horizon(s1.ra, s1.dec, lat, lst)
                    local a2, z2 = astro.horizon(s2.ra, s2.dec, lat, lst)
                    if a1 > 0 and a2 > 0 then
                        local x1, y1 = astro.project(a1, z1, R, R, R - 6)
                        local x2, y2 = astro.project(a2, z2, R, R, R - 6)
                        items[#items + 1] = { type = "line", x1 = x1, y1 = y1,
                            x2 = x2, y2 = y2, color = 0x5C8FD6, width = 1,
                            opacity = theme.night and 60 or 105 }
                    end
                end
            end
        end

        -- 恒星
        local lim = st.mag_limit
        local stars = data.stars_list
        for i = 1, #stars do
            local s = stars[i]
            local alt, az = astro.horizon(s.ra, s.dec, lat, lst)
            if alt > 0 and s.mag <= lim + 0.6 then
                local x, y = astro.project(alt, az, R, R, R - 8)
                local rr = star_radius(s.mag)
                local op = star_opa(s.mag)
                -- 地平线附近压暗，模拟大气消光
                if alt < 12 then
                    op = math.floor(op * (0.45 + alt / 22))
                end
                local col = theme.star_color(s.mag, s.bv)
                if rr > 3 then
                    items[#items + 1] = { type = "circle", cx = x, cy = y, r = rr * 2.1,
                        color = col, fill = true, fill_color = col, opacity = 0,
                        fill_opacity = theme.night and 8 or 22, width = 0 }
                end
                items[#items + 1] = { type = "circle", cx = x, cy = y, r = rr,
                    color = col, fill = true, fill_color = col,
                    fill_opacity = op, width = 0 }
                hit[#hit + 1] = { x = x, y = y, obj = s }
            end
        end

        -- 深空天体（虚线小圈）
        for i = 1, #cand do
            local o = cand[i]
            local alt, az = astro.horizon(o.ra, o.dec, lat, lst)
            if alt > 3 then
                local x, y = astro.project(alt, az, R, R, R - 8)
                items[#items + 1] = { type = "circle", cx = x, cy = y, r = 5,
                    color = C.violet, width = 1, opacity = 175,
                    dash_width = 2, dash_gap = 2 }
                hit[#hit + 1] = { x = x, y = y, obj = o }
            end
        end

        -- 星座名（跟着星空走）
        for i = 1, #con_lbs do
            local c = con_lbs[i]
            local calt, caz = astro.horizon(c.ra, c.dec, lat, lst)
            if calt > 6 and st.labels then
                local cx2, cy2 = astro.project(calt, caz, R, R, R - 8)
                c.lb:set_pos(math.floor(cx2) - 32, math.floor(cy2) - 9)
                c.lb:set_text(c.name)
            else
                c.lb:set_text("")
            end
        end

        -- 月亮
        local mra, mdec, illum = astro.moon(t)
        local malt, maz = astro.horizon(mra, mdec, lat, lst)
        if malt > -2 then
            local x, y = astro.project(math.max(malt, 0), maz, R, R, R - 8)
            items[#items + 1] = { type = "circle", cx = x, cy = y, r = 9,
                color = 0xFFF4C4, fill = true, fill_color = 0xFFF4C4,
                fill_opacity = 30, width = 0 }
            items[#items + 1] = { type = "circle", cx = x, cy = y, r = 5,
                color = 0xFFF8DC, fill = true, fill_color = 0xFFF8DC,
                fill_opacity = 235, width = 0 }
        end

        -- 太阳
        local sra, sdec = astro.sun_equatorial(t)
        local salt, saz = astro.horizon(sra, sdec, lat, lst)
        if salt > -3 then
            local x, y = astro.project(math.max(salt, 0), saz, R, R, R - 8)
            items[#items + 1] = { type = "circle", cx = x, cy = y, r = 16,
                color = 0xFFB347, fill = true, fill_color = 0xFFB347,
                fill_opacity = 26, width = 0 }
            items[#items + 1] = { type = "circle", cx = x, cy = y, r = 6,
                color = 0xFFC46B, fill = true, fill_color = 0xFFC46B,
                fill_opacity = 230, width = 0 }
        end

        -- 选中目标高亮
        if sel_id then
            local o = data.byid[sel_id] or st.selected
            if o and o.ra then
                local alt, az = astro.horizon(o.ra, o.dec, lat, lst)
                if alt > -2 then
                    local x, y = astro.project(math.max(alt, 0), az, R, R, R - 8)
                    items[#items + 1] = { type = "circle", cx = x, cy = y, r = 13,
                        color = C.cyan, width = 1, opacity = 200, dash_width = 3, dash_gap = 3 }
                    items[#items + 1] = { type = "line", x1 = x - 20, y1 = y,
                        x2 = x - 14, y2 = y, color = C.cyan, width = 1, opacity = 200 }
                    items[#items + 1] = { type = "line", x1 = x + 14, y1 = y,
                        x2 = x + 20, y2 = y, color = C.cyan, width = 1, opacity = 200 }
                end
            end
        end

        if theme.night then
            for i = 1, #items do
                local it = items[i]
                it.color = theme.tint(it.color)
                if it.fill_color then it.fill_color = theme.tint(it.fill_color) end
            end
        end
        sky_shape:set_items(items)
    end

    -- ==================== 分段电平表 ====================
    local function set_segs(segs, ratio, color)
        local n = #segs
        local lit = math.floor(ratio * n + 0.5)
        if lit < 0 then lit = 0 elseif lit > n then lit = n end
        for i = 1, n do
            segs[i]:set_color(theme.tint(i <= lit and color or C.line))
        end
    end

    -- ==================== 月相 ====================
    local mi = {}
    local function draw_moon(age)
        if not moon_shape then return end
        reset(mi)
        local cx, cy, r = 60, 54, 32
        mi[#mi + 1] = { type = "circle", cx = cx, cy = cy, r = r + 12,
            color = 0xAFC4FF, fill = true, fill_color = 0xAFC4FF,
            fill_opacity = theme.night and 4 or 7, width = 0 }
        mi[#mi + 1] = { type = "circle", cx = cx, cy = cy, r = r,
            color = 0x39456B, fill = true, fill_color = 0x0C1120,
            fill_opacity = 255, width = 1 }

        local elong = (age / 29.530588) * 360
        local term = r * math.cos(elong * math.pi / 180)
        local waxing = elong < 180
        local step = 2
        local x = -r
        while x <= r do
            local dx = x + step / 2
            local lit
            if waxing then lit = dx > term else lit = dx < -term end
            if math.abs(dx) <= r and lit then
                local hw = math.sqrt(r * r - dx * dx)
                mi[#mi + 1] = { type = "rect",
                    x = math.floor(cx + dx - step / 2), y = math.floor(cy - hw),
                    w = step + 1, h = math.floor(hw * 2),
                    color = 0xF7F2DA, fill = true, fill_color = 0xF7F2DA,
                    fill_opacity = 235, width = 0 }
                if hw > 3 then
                    mi[#mi + 1] = { type = "circle",
                        cx = math.floor(cx + dx), cy = math.floor(cy - hw),
                        r = 1, color = 0xF7F2DA, fill = true,
                        fill_color = 0xF7F2DA, fill_opacity = 235, width = 0 }
                    mi[#mi + 1] = { type = "circle",
                        cx = math.floor(cx + dx), cy = math.floor(cy + hw),
                        r = 1, color = 0xF7F2DA, fill = true,
                        fill_color = 0xF7F2DA, fill_opacity = 235, width = 0 }
                end
            end
            x = x + step
        end
        moon_shape:set_items(mi)
    end

    -- ==================== 目标推荐 ====================
    local function refresh_rec()
        local t = st.t
        local lst = astro.lst(t, conf.site.lon)
        local lat = conf.site.lat
        local best = {}
        for i = 1, #cand do
            local o = cand[i]
            local alt, az = astro.horizon(o.ra, o.dec, lat, lst)
            if alt > 12 then
                best[#best + 1] = { o = o, alt = alt, az = az }
            end
        end
        table.sort(best, function(a, b) return a.alt > b.alt end)

        local shown = 0
        for i = 1, 4 do
            local row = rows[i]
            local e = best[i]
            if e then
                shown = shown + 1
                row.obj = e.o
                row.name:set_text(e.o.cn)
                row.kind:set_text(string.format("%s · %s · %.1f等",
                    e.o.kind, astro.compass(e.az), e.o.mag))
                row.altv:set_text(string.format("%.0f°", e.alt))
                local q = e.alt / 90
                set_segs(row.segs, q, theme.quality_color(q))
                local obj = e.o
                row.box:set_on_click(function()
                    st.selected = obj
                    app.go("object", obj)
                end)
                row.btn:set_on_click(function()
                    st.selected = obj
                    app.go("object", obj)
                end)
            else
                row.obj = nil
                row.name:set_text("—")
                row.kind:set_text("当前无合适高度目标")
                row.altv:set_text("")
                set_segs(row.segs, 0, C.line)
            end
        end
        rec_hint:set_text(string.format("可见 %d 个", #best))
    end

    -- ==================== 条件面板 ====================
    local function refresh_cond(env)
        local idx = math.floor(env.index + 0.5)
        idx_lb:set_text(tostring(idx))
        idx_lb:set_color(theme.tint(theme.quality_color(env.index / 100)))
        idx_tip:set_text(idx >= 75 and "适合深空" or (idx >= 45 and "可观测" or "不宜观测"))
        idx_tip:set_color(theme.tint(theme.quality_color(env.index / 100)))
        set_segs(idx_segs, env.index / 100, theme.quality_color(env.index / 100))

        -- 云量越低越好
        set_segs(kv[1].segs, env.cloud, env.cloud > 0.55 and C.red or (env.cloud > 0.3 and C.amber or C.green))
        kv[1].lb:set_text(string.format("%.0f%%", env.cloud * 100))
        -- 视宁度 0.6..3.2"，越小越好
        local see_r = 1 - (env.seeing - 0.6) / 2.6
        set_segs(kv[2].segs, see_r, theme.quality_color(see_r))
        kv[2].lb:set_text(string.format("%.1f\"", env.seeing))
        -- 透明度
        set_segs(kv[3].segs, env.trans, theme.quality_color(env.trans))
        kv[3].lb:set_text(string.format("%.0f%%", env.trans * 100))

        local _, _, illum, age = astro.moon(st.t)
        draw_moon(age)
        moon_lb:set_text(string.format("%s  照亮 %.0f%%",
            astro.moon_phase_name(age), illum * 100))
        _ = age
    end

    -- ==================== 动画循环 ====================
    local frame = 0
    local function tick(dt)
        _ = dt
        frame = frame + 1
        draw_sky()

        local txt, sub = app.clock_text()
        clock_lb:set_text(txt)
        sub_lb:set_text(sub)

        if frame % 10 == 1 then
            refresh_cond(app.env())
            refresh_rec()
        end
    end

    -- ==================== 点选星点 ====================
    local function touch(state, x, y)
        if state ~= airui.TP_DOWN then return end
        local lx, ly = x - DX, y - DY
        local dx, dy = lx - R, ly - R
        if dx * dx + dy * dy > R * R then return end
        local best, bd = nil, 30 * 30
        for i = 1, #hit do
            local h = hit[i]
            local ddx, ddy = h.x - lx, h.y - ly
            local d = ddx * ddx + ddy * ddy
            if d < bd then bd = d; best = h.obj end
        end
        if best then
            st.selected = best
            app.go("object", best)
            return
        end
        -- 空白处：反投影到赤道坐标，靠近某个深空天体也算点中
        local alt, az = astro.unproject(lx, ly, R, R, R)
        if not alt then return end
        local ra, dec = astro.equatorial(alt, az, conf.site.lat, app.lst())
        local lst = astro.lst(st.t, conf.site.lon)
        local pick, pd = nil, 8 * 8
        for i = 1, #cand do
            local o = cand[i]
            local a, z = astro.horizon(o.ra, o.dec, conf.site.lat, lst)
            if a > 0 then
                local px, py = astro.project(a, z, R, R, R - 8)
                local ddx, ddy = px - lx, py - ly
                local d = ddx * ddx + ddy * ddy
                if d < pd then pd = d; pick = o end
            end
        end
        if pick then
            st.selected = pick
            app.go("object", pick)
        else
            app.toast(string.format("该方向：高度 %.0f°  方位 %.0f° %s",
                alt, az, astro.compass(az)))
        end
        _ = ra; _ = dec
    end

    page.ui = {
        clock_lb = clock_lb, idx_lb = idx_lb, env = app.env,
    }
    page.tick = tick
    page.touch = touch

    -- 首帧立即绘制
    draw_sky()
    refresh_cond(app.env())
    refresh_rec()

    return page
end

return build
