--[[
@module  ui_line
@summary 线路页：纵剖面、支架塔、目标速度调节、速度与张力趋势
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
    profile = { x = 16,  y = 8,   w = 992, h = 252 },
    control = { x = 16,  y = 268, w = 326, h = 268 },
    trend   = { x = 350, y = 268, w = 328, h = 268 },
    towers  = { x = 686, y = 268, w = 322, h = 268 },
}

-- 剖面图内部坐标（shape 就地绘制）
local PROFILE = { w = 964, h = 196, x0 = 30, y0 = 150, x1 = 920, y1 = 26, sag = 18 }

local function terrain_y(x)
    local base = 190 - (x / PROFILE.w) * 124
    return base + math.sin(x / 62) * 5
end

-- 趋势图刻度文字
-- 组件自带的轴标注字号是固定的（主题字体 14px），而且那些 label 由 C 层直接创建在图表的
-- 父对象上，脚本拿不到句柄、改不了字号；所以在 airui.chart 里不启用 x_axis / y_axis，
-- 改成本地画 10px 的小字，字号、颜色、位置全在脚本里可控。
-- 字高按“字号 + 行距”给足（10px 字的行高约 13px），否则标签会被压扁或裁掉下半截
local AXIS_FONT, AXIS_LBL_H = 10, 14

-- 在图表左侧画 y 轴刻度：vmin 对应图表底边，vmax 对应顶边
local function axis_y(parent, x, w, top, h, vmin, vmax, values)
    for i = 1, #values do
        local v = values[i]
        local ty = top + h - (v - vmin) / (vmax - vmin) * h - AXIS_LBL_H / 2
        if ty < top + 1 then ty = top + 1 end   -- 顶端标签收在图内，别压到上方的标题行
        theme.label(parent, x, math.floor(ty + 0.5), w, AXIS_LBL_H,
                    tostring(v), AXIS_FONT, C.ink3, A_RIGHT)
    end
end

-- 在图表下方画 x 轴刻度：左端最老（-96 分钟），右端是当前（0）
local function axis_x(parent, cx, cw, y)
    theme.label(parent, cx, y, 40, AXIS_LBL_H, "-96", AXIS_FONT, C.ink3, A_LEFT)
    theme.label(parent, cx + math.floor(cw / 2) - 20, y, 40, AXIS_LBL_H, "-48", AXIS_FONT, C.ink3, A_CENTER)
    theme.label(parent, cx + cw - 40, y, 40, AXIS_LBL_H, "0", AXIS_FONT, C.ink3, A_RIGHT)
end

function M.create(root)
    local page = { root = root, alive = true }
    local lift = sim.lift("a")

    -- ==================== 纵剖面 ====================
    local pc = theme.card(root, L.profile.x, L.profile.y, L.profile.w, L.profile.h, { radius = 14 })
    theme.label(pc, 16, 8, 320, 20, "A 主索道 · 纵剖面", SZ.m, C.ink)
    theme.label(pc, 16, 28, 420, 16, string.format("下站 %d m  →  上站 %d m  ·  水平 %d m  ·  %d 座支架",
        theme.n(lift.bottom), theme.n(lift.top), theme.n(lift.length), theme.n(lift.towers)), SZ.xs, C.ink3)
    local p_chip = theme.chip(pc, 856, 10, 120, 24, lift.state_text, C.bg0, C.green, SZ.xs)
    local p_cap = theme.label(pc, 700, 30, 276, 16, "", SZ.xs, C.ink3, A_RIGHT)

    -- 剖面图元（海拔参考线 + 地形 + 钢绳 + 支架）
    local items = {}
    local PV = PROFILE
    -- 海拔参考线
    local refs = { { y = 26, txt = "2 480 m" }, { y = 88, txt = "2 200 m" }, { y = 150, txt = "1 960 m" } }
    for _, r in ipairs(refs) do
        items[#items + 1] = {
            type = "line", x1 = 0, y1 = r.y, x2 = PV.w, y2 = r.y,
            color = C.line, width = 1, opacity = 110,
        }
    end
    -- 地形（逐列矩形）
    for x = 0, PV.w - 1, 8 do
        local y = math.floor(terrain_y(x + 4))
        items[#items + 1] = {
            type = "rect", x = x, y = y, w = 8, h = PV.h - y,
            color = C.ridge2, fill = true, fill_color = C.ridge2, width = 1,
        }
        items[#items + 1] = {
            type = "rect", x = x, y = y, w = 8, h = 2,
            color = C.powder, fill = true, fill_color = C.powder, width = 1, opacity = 200,
        }
    end

    -- 钢绳
    local px, py
    for i = 0, 24 do
        local x, y = art.path_point(PV.x0, PV.y0, PV.x1, PV.y1, PV.sag, i / 24)
        if px then
            items[#items + 1] = {
                type = "line", x1 = math.floor(px), y1 = math.floor(py),
                x2 = math.floor(x), y2 = math.floor(y), color = C.line2, width = 2,
            }
        end
        px, py = x, y
    end

    -- 支架塔
    local tower_data = {}
    for i = 1, math.min(lift.towers, 14) do
        local t = 0.05 + (i - 1) * (0.90 / 13)
        local x, y = art.path_point(PV.x0, PV.y0, PV.x1, PV.y1, PV.sag, t)
        local base = terrain_y(x)
        items[#items + 1] = {
            type = "line", x1 = math.floor(x), y1 = math.floor(y),
            x2 = math.floor(x), y2 = math.floor(base), color = C.ink3, width = 2, opacity = 220,
        }
        items[#items + 1] = {
            type = "line", x1 = math.floor(x - 6), y1 = math.floor(y + 2),
            x2 = math.floor(x + 6), y2 = math.floor(y + 2), color = C.ink3, width = 2,
        }
        tower_data[i] = {
            no = i,
            alt = math.floor(lift.bottom + (lift.top - lift.bottom) * ((x - PV.x0) / (PV.x1 - PV.x0))),
            tilt = 1.2 + (i % 4) * 0.5,
            t = t,
        }
    end

    -- 站房
    items[#items + 1] = {
        type = "rect", x = PV.x0 - 26, y = math.floor(terrain_y(PV.x0)) - 44, w = 44, h = 46, radius = 3,
        color = C.panel3, fill = true, fill_color = C.panel3, width = 1,
    }
    items[#items + 1] = {
        type = "rect", x = PV.x1 - 14, y = math.floor(terrain_y(PV.x1)) - 44, w = 44, h = 46, radius = 3,
        color = C.panel3, fill = true, fill_color = C.panel3, width = 1,
    }

    theme.shape(pc, 14, 46, PV.w, PV.h, items)

    -- 剖面标注
    theme.label(pc, 16, 46 + PV.y0 - 30, 80, 16, "下站", SZ.xs, C.ink2)
    theme.label(pc, 850, 46 + PV.y1 - 34, 76, 16, "上站", SZ.xs, C.ink2, A_RIGHT)
    theme.label(pc, 940, 46 + 26 - 8, 40, 14, "2 480", SZ.xs, C.ink3, A_RIGHT)
    theme.label(pc, 940, 46 + 150 - 8, 40, 14, "1 960", SZ.xs, C.ink3, A_RIGHT)
    theme.label(pc, 16, 46 + PV.h - 18, 120, 14, "0 m", SZ.xs, C.ink3)
    theme.label(pc, 860, 46 + PV.h - 18, 100, 14, "1 840 m", SZ.xs, C.ink3, A_RIGHT)

    -- 缆车位置标记（沿线移动）
    local marks = {}
    for i = 1, lift.cabins do
        marks[i] = { t = (i - 1) / lift.cabins, dir = 1, dwell = 0 }
        marks[i].shape = theme.box(pc, 0, 0, 10, 12, lift.color, 3)
    end
    page.marks = marks
    page.profile_shape_y = 46

    -- ==================== 运力控制 ====================
    local cc = theme.card(root, L.control.x, L.control.y, L.control.w, L.control.h, { radius = 14 })
    theme.label(cc, 16, 8, 200, 20, "运力控制", SZ.m, C.ink)
    local target_chip = theme.chip(cc, 216, 8, 94, 20, "A 线", C.ink2, C.panel2, SZ.xs)

    local speed_val = theme.label(cc, 16, 34, 120, 48, "5.0", SZ.hero, C.ice)
    theme.label(cc, 118, 62, 46, 16, "m/s", SZ.s, C.ink3)
    local speed_hint = theme.label(cc, 168, 40, 142, 16, "", SZ.xs, C.ink3, A_RIGHT)
    local speed_desc = theme.label(cc, 168, 58, 142, 16, "", SZ.xs, C.ink3, A_RIGHT)

    local slider = theme.slider({
        parent = cc, x = 16, y = 96, w = 294, h = 26,
        min = 0, max = 60, value = math.floor(lift.target * 10 + 0.5),
        on_change = function(self)
            local v = 0
            pcall(function() v = self:get_value() end)
            sim.set_target("a", v / 10)
            page.refresh()
        end,
        style = {
            bg_color = C.panel3, bg_opa = 255,
            border_color = C.line, border_width = 0, radius = 8, pad = 3,
            indicator_color = C.ice, knob_color = C.snow, knob_border_color = C.ice,
            knob_border_width = 2,
        },
    })
    page.slider = slider

    theme.label(cc, 16, 126, 60, 14, "0.0", SZ.xs, C.ink3)
    theme.label(cc, 134, 126, 60, 14, "3.0", SZ.xs, C.ink3, A_CENTER)
    theme.label(cc, 250, 126, 60, 14, "6.0", SZ.xs, C.ink3, A_RIGHT)

    local preset = {
        { text = "标准 5.0", v = 5.0 },
        { text = "低速 2.5", v = 2.5 },
        { text = "停运 0.0", v = 0.0 },
    }
    local presets = {}
    for i, p in ipairs(preset) do
        presets[i] = theme.ghost(cc, 16 + (i - 1) * 100, 148, 92, 30, p.text, {
            size = SZ.xs,
            on_click = function()
                sim.set_target("a", p.v)
                if page.slider then pcall(function() page.slider:set_value(p.v * 10) end) end
                page.refresh()
            end,
        })
    end

    local stat_rows = {}
    local STAT = { "当前运力", "发车间隔", "单程时间" }
    for i, name in ipairs(STAT) do
        local y = 192 + (i - 1) * 24
        theme.label(cc, 16, y, 120, 16, name, SZ.xs, C.ink3)
        stat_rows[i] = theme.label(cc, 136, y, 174, 16, "--", SZ.s, C.ink, A_RIGHT)
    end
    page.stats = stat_rows

    -- ==================== 趋势 ====================
    local tc = theme.card(root, L.trend.x, L.trend.y, L.trend.w, L.trend.h, { radius = 14 })
    theme.label(tc, 14, 8, 200, 20, "运行趋势", SZ.m, C.ink)
    local trend_sub = theme.label(tc, 200, 10, 114, 16, "", SZ.xs, C.ink3, A_RIGHT)

    -- 用 airui 原生图表组件（lv_chart）画趋势：抗锯齿折线 + 网格 + 曲线下方渐变填充。
    -- 曲线细节由 art.resample_curve 插值补点（48 样本 -> 96 点）后交给组件绘制。
    --
    -- 刻度区域预留：左侧 30px 放 y 轴数字（右对齐贴到 x=40），下方 18px 放 x 轴数字。
    local CHART_X, CHART_W, CHART_H, CHART_PTS = 44, 270, 58, 96

    theme.label(tc, 14, 30, 150, 14, "索道速度 (×0.1 m/s)", SZ.xs, C.ink3)
    local sp_now = theme.label(tc, 170, 30, 144, 14, "", SZ.xs, C.ice, A_RIGHT)
    local speed_chart = airui.chart({
        parent = tc, x = CHART_X, y = 46, w = CHART_W, h = CHART_H,
        type = "line",
        y_min = 0, y_max = 60,              -- 0 ~ 6.0 m/s，数值放大 10 倍后传输（组件只收整数）
        point_count = CHART_PTS,
        line_color = C.ice, line_width = 2,
        bg_opa = 0, border_width = 0,
        grid_color = C.line, grid_opa = 110, hdiv = 2, vdiv = 5,
        fill = { enable = true, color = C.ice, opa_start = 90, opa_end = 0 },
    })
    axis_y(tc, 14, 26, 46, CHART_H, 0, 60, { 60, 30, 0 })
    axis_x(tc, CHART_X, CHART_W, 46 + CHART_H + 3)

    theme.label(tc, 14, 126, 150, 14, "钢绳张力 (kN)", SZ.xs, C.ink3)
    local tn_now = theme.label(tc, 170, 126, 144, 14, "", SZ.xs, C.violet, A_RIGHT)
    local TENSION_Y = 142
    local tension_chart = airui.chart({
        parent = tc, x = CHART_X, y = TENSION_Y, w = CHART_W, h = CHART_H,
        type = "line",
        y_min = 200, y_max = 300,
        point_count = CHART_PTS,
        line_color = C.violet, line_width = 2,
        bg_opa = 0, border_width = 0,
        grid_color = C.line, grid_opa = 110, hdiv = 2, vdiv = 5,
    })
    axis_y(tc, 14, 26, TENSION_Y, CHART_H, 200, 300, { 300, 250, 200 })
    axis_x(tc, CHART_X, CHART_W, TENSION_Y + CHART_H + 3)
    -- 适宜张力区间 210 ~ 280 kN：两条常量参考线
    local band_hi = tension_chart:add_series({ color = 0x3F7F6A })
    local band_lo = tension_chart:add_series({ color = 0x3F7F6A })
    do
        local hi, lo = {}, {}
        for i = 1, CHART_PTS do hi[i] = 280; lo[i] = 210 end
        tension_chart:set_values(band_hi, hi)
        tension_chart:set_values(band_lo, lo)
    end

    theme.hline(tc, 14, 228, 300, C.line)
    theme.label(tc, 14, 234, 130, 14, "今日运送", SZ.xs, C.ink3)
    local visitors = theme.label(tc, 140, 232, 174, 18, "", SZ.m, C.snow, A_RIGHT)
    page.speed_chart = speed_chart
    page.tension_chart = tension_chart
    page.sp_now = sp_now
    page.tn_now = tn_now
    page.trend_sub = trend_sub
    page.visitors = visitors

    -- ==================== 支架塔 ====================
    local wc = theme.card(root, L.towers.x, L.towers.y, L.towers.w, L.towers.h, { radius = 14 })
    theme.label(wc, 14, 8, 200, 20, "支架塔监测", SZ.m, C.ink)
    theme.label(wc, 200, 10, 108, 16, string.format("%d 座 · 正常", theme.n(lift.towers)), SZ.xs, C.ink3, A_RIGHT)
    theme.hline(wc, 14, 28, 294, C.line)

    local trows = {}
    for i = 1, math.min(#tower_data, 8) do
        local d = tower_data[i]
        local y = 32 + (i - 1) * 27
        local no = theme.label(wc, 14, y, 46, 16, string.format("#%02d", d.no), SZ.xs, C.ink2)
        local alt = theme.label(wc, 62, y, 84, 16, string.format("%d m", d.alt), SZ.xs, C.ink3)
        local tilt = theme.label(wc, 148, y, 88, 16, string.format("倾角 %.1f°", d.tilt), SZ.xs, C.ink3)
        local bar = theme.segbar(wc, 240, y + 4, 40, 6, 6, C.green, C.panel3, 2)
        bar.set(0.85)
        local dot = theme.box(wc, 296, y + 5, 6, 6, C.green, 3)
        trows[i] = { no = no, alt = alt, tilt = tilt, dot = dot, bar = bar }
    end
    page.trows = trows

    -- ==================== 刷新 ====================
    local function refresh()
        if not page.alive then return end
        local l = sim.lift("a")
        local s = sim.summary()

        p_chip.set(l.state_text, theme.state_color(l.state == "run" and "ok" or (l.state == "derate" and "warn" or "danger")))
        p_cap:set_text(string.format("目标 %.1f m/s · 实际 %.1f m/s", l.target, l.speed))

        speed_val:set_text(string.format("%.1f", l.speed))
        speed_val:set_color(l.speed < 0.3 and C.red or C.ice)
        speed_hint:set_text(string.format("上限 %.1f m/s", l.max_speed))
        speed_desc:set_text(l.state == "run" and "变频器输出稳定" or l.state_text)
        target_chip.set(l.state == "run" and "A 线" or "限速", C.ink2)

        local interval = (l.speed > 0.1) and (l.length / l.speed / l.cabins) or 0
        page.stats[1]:set_text(string.format("%d 人/小时", theme.n(l.capacity)))
        page.stats[2]:set_text(string.format("%.1f s", interval))
        page.stats[3]:set_text(string.format("%.1f min", (l.speed > 0.1) and (l.length / l.speed / 60) or 0))

        page.trend_sub:set_text(s.clock .. " " .. s.phase)
        page.sp_now:set_text(string.format("%.1f m/s", l.speed))
        page.tn_now:set_text(string.format("%.0f kN", l.tension))
        page.visitors:set_text(string.format("%d 人次", theme.n(s.visitors)))

        pcall(function()
            local sp = art.resample_curve(sim.history("speed"), CHART_PTS)
            if #sp > 0 then
                local vals = {}
                for i = 1, #sp do vals[i] = theme.n(sp[i] * 10) end
                page.speed_chart:set_values(1, vals)
            end
            local tn = art.resample_curve(sim.history("tension"), CHART_PTS)
            if #tn > 0 then
                local vals = {}
                for i = 1, #tn do vals[i] = theme.n(tn[i]) end
                page.tension_chart:set_values(1, vals)
            end
        end)

        for i, row in ipairs(page.trows) do
            local d = tower_data[i]
            if d then
                row.alt:set_text(string.format("%d m", d.alt))
            end
        end
    end
    page.refresh = refresh

    -- ==================== 动画 ====================
    local function frame()
        if not page.alive then return end
        local l = sim.lift("a")
        local step = 0.003 + 0.012 * (l.speed / math.max(0.5, l.max_speed))
        for _, m in ipairs(page.marks) do
            if m.dwell > 0 then
                m.dwell = m.dwell - 1
            else
                m.t = m.t + step * m.dir
                if m.t >= 1 then m.t = 1; m.dir = -1; m.dwell = 6 end
                if m.t <= 0 then m.t = 0; m.dir = 1; m.dwell = 6 end
            end
            local x, y = art.path_point(PROFILE.x0, PROFILE.y0, PROFILE.x1, PROFILE.y1, PROFILE.sag, m.t)
            m.shape:set_pos(14 + math.floor(x - 5), page.profile_shape_y + math.floor(y - 6))
        end
    end
    page.frame = frame

    local function slow()
        if not page.alive then return end
    end
    page.slow = slow

    function page.destroy()
        page.alive = false
    end

    refresh()
    frame()
    return page
end

return M
