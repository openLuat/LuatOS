--[[
@module  art
@summary ROAST LAB 矢量绘制：烘焙曲线 / 环形温度表 / 豆形剪影 / 图标
@version 1.0
@date    2026.10.30
说明：
  所有函数返回 airui.shape 的 items 数组，由调用方放入 shape 控件。
  只使用 line / rect / circle / ellipse / arc 五种图元，兼容性好、开销低。
]]
local M = {}

local floor, min, max, abs = math.floor, math.min, math.max, math.abs
local rad, cos, sin = math.rad, math.cos, math.sin

local function clamp01(t)
    if t < 0 then return 0 end
    if t > 1 then return 1 end
    return t
end
M.clamp01 = clamp01

-- ===================== 圆弧（自动跨 0°/360° 拆分）=====================
-- C 层把 end_angle 限制在 0..359，跨越 360 的弧必须拆成两段
local function arc_item(items, cx, cy, r, a0, a1, color, width, rounded, opa)
    if a1 <= a0 then return end
    if a0 >= 360 then a0 = a0 - 360; a1 = a1 - 360 end
    local function seg(s, e)
        if e - s < 0.5 then return end
        items[#items + 1] = {
            type = "arc", cx = cx, cy = cy, r = r,
            start_angle = floor(s + 0.5), end_angle = floor(e + 0.5),
            color = color, width = width, opacity = opa or 255,
            rounded = rounded and true or false,
        }
    end
    if a1 <= 359 then
        seg(a0, a1)
    else
        seg(a0, 359)
        seg(0, a1 - 360)
    end
end

-- ===================== 烘焙曲线 =====================
-- hist: 数值数组；o: min,max,color,width,area,area_opa,grid,bands,refs,marks,end_dot,step
function M.curve_items(w, h, hist, o)
    o = o or {}
    local n = #hist
    local items = {}
    local vmin = o.min or 0
    local vmax = o.max or 1
    if vmax - vmin < 0.001 then vmax = vmin + 1 end
    local pad = o.pad or 4
    local ih = h - pad * 2

    local function vy(v)
        return floor(pad + ih - clamp01((v - vmin) / (vmax - vmin)) * ih + 0.5)
    end
    -- o.total：横轴总点数（对比曲线按时间对齐时，数组长度可小于 total）
    local step = (n > 1) and (w / ((o.total or n) - 1)) or 0
    local function vx(i)
        return floor((i - 1) * step + 0.5)
    end

    -- 横向网格
    local g = o.grid or 0
    for i = 0, g do
        local y = floor(pad + ih * i / max(g, 1) + 0.5)
        items[#items + 1] = {
            type = "line", x1 = 0, y1 = y, x2 = w, y2 = y,
            color = o.grid_color or 0x2E211A, width = 1, opacity = o.grid_opa or 120,
        }
    end

    -- 纵轴相位色带（按采样点下标）
    if o.bands then
        for _, b in ipairs(o.bands) do
            local x0 = vx(max(b.i0 or 1, 1))
            local x1 = vx(min(b.i1 or n, n))
            if x1 > x0 then
                items[#items + 1] = {
                    type = "rect", x = x0, y = pad, w = x1 - x0, h = ih,
                    color = b.color, fill = true, fill_color = b.color,
                    fill_opacity = b.opa or 18, width = 0, opacity = 0,
                }
            end
        end
    end

    -- 水平参考线（一爆温度、目标出豆温度）
    if o.refs then
        for _, r in ipairs(o.refs) do
            local y = vy(r.v)
            items[#items + 1] = {
                type = "line", x1 = 0, y1 = y, x2 = w, y2 = y,
                color = r.color or 0xE8C07D, width = 1, opacity = r.opa or 170,
                dash_width = r.dash or 6, dash_gap = r.dash or 6,
            }
        end
    end

    if n >= 2 then
        -- 面积填充
        if o.area ~= false then
            local astep = max(1, floor(o.area_step or 3))
            for i = 1, n - 1, astep do
                local j = min(i + astep, n)
                local x0 = vx(i)
                local x1 = vx(j)
                local y = vy(hist[i])
                if x1 > x0 and h - y > 0 then
                    items[#items + 1] = {
                        type = "rect", x = x0, y = y, w = x1 - x0, h = h - y,
                        color = o.color, fill = true, fill_color = o.color,
                        fill_opacity = o.area_opa or 20, width = 0, opacity = 0,
                    }
                end
            end
        end

        -- 折线
        local dstep = max(1, floor(o.step or 1))
        local i = 1
        while i < n do
            local j = min(i + dstep, n)
            items[#items + 1] = {
                type = "line", x1 = vx(i), y1 = vy(hist[i]), x2 = vx(j), y2 = vy(hist[j]),
                color = o.color, width = o.width or 2, opacity = o.opacity or 255,
                round_start = true, round_end = true,
                dash_width = o.dash_width or 0, dash_gap = o.dash_gap or 0,
            }
            i = j
        end

        -- 末端光点
        if o.end_dot ~= false then
            local lx = min(vx(n), w - 6)
            local ly = vy(hist[n])
            items[#items + 1] = {
                type = "circle", cx = lx, cy = ly, r = 6, color = o.color,
                fill = true, fill_color = o.color, fill_opacity = 26, width = 1, opacity = 90,
            }
            items[#items + 1] = {
                type = "circle", cx = lx, cy = ly, r = 3, color = 0xFFFFFF,
                fill = true, fill_color = 0xFFFFFF, fill_opacity = 255, width = 1,
            }
        end
    end

    -- 竖向事件标记
    if o.marks then
        for _, m in ipairs(o.marks) do
            local x = vx(m.i)
            if x >= 0 and x <= w then
                items[#items + 1] = {
                    type = "line", x1 = x, y1 = 0, x2 = x, y2 = h,
                    color = m.color or 0xE8C07D, width = 1, opacity = 190,
                    dash_width = 4, dash_gap = 4,
                }
            end
        end
    end
    return items
end

-- ===================== 环形温度表 =====================
-- start 135, sweep 270 → 缺口在正下方
function M.gauge_items(cx, cy, r, v, vmin, vmax, o)
    o = o or {}
    local start = o.start or 135
    local sweep = o.sweep or 270
    local width = o.width or 12
    local items = {}

    -- 刻度
    local ticks = o.ticks or 12
    for i = 0, ticks do
        local t = i / ticks
        local a = rad(start + sweep * t)
        local r1 = r - width / 2 - 4
        local r2 = r1 - ((i % 3 == 0) and 7 or 4)
        items[#items + 1] = {
            type = "line",
            x1 = floor(cx + r1 * cos(a) + 0.5), y1 = floor(cy + r1 * sin(a) + 0.5),
            x2 = floor(cx + r2 * cos(a) + 0.5), y2 = floor(cy + r2 * sin(a) + 0.5),
            color = o.tick_color or 0x4A3427, width = 1, opacity = 200,
        }
    end

    -- 底环
    arc_item(items, cx, cy, r, start, start + sweep, o.track or 0x2A1E18, width, false, 255)

    -- 相位色段（可选：脱水/梅纳/发展 三段底色）
    if o.segments then
        for _, s in ipairs(o.segments) do
            local a0 = start + sweep * clamp01((s.from - vmin) / (vmax - vmin))
            local a1 = start + sweep * clamp01((s.to - vmin) / (vmax - vmin))
            arc_item(items, cx, cy, r, a0, a1, s.color, width, false, s.opa or 40)
        end
    end

    -- 进度
    local pct = clamp01((v - vmin) / (vmax - vmin))
    local a_end = start + sweep * pct
    if pct > 0.006 then
        arc_item(items, cx, cy, r, start, a_end, o.color or 0xC8763C, width, true, 255)
    end

    -- 标记点（一爆 / 二爆 / 目标出豆）
    if o.marks then
        for _, m in ipairs(o.marks) do
            local t = clamp01((m.v - vmin) / (vmax - vmin))
            local a = rad(start + sweep * t)
            items[#items + 1] = {
                type = "circle",
                cx = floor(cx + r * cos(a) + 0.5), cy = floor(cy + r * sin(a) + 0.5),
                r = m.r or 4, color = m.color or 0xE8C07D,
                fill = true, fill_color = o.bg or 0x1A1310, fill_opacity = 255, width = 2,
            }
        end
    end
    return items
end

-- 引脚式指示线（从圆心指向当前值）
function M.needle_items(cx, cy, r0, r1, v, vmin, vmax, color, o)
    o = o or {}
    local start = o.start or 135
    local sweep = o.sweep or 270
    local a = rad(start + sweep * clamp01((v - vmin) / (vmax - vmin)))
    local items = {
        {
            type = "line",
            x1 = floor(cx + r0 * cos(a) + 0.5), y1 = floor(cy + r0 * sin(a) + 0.5),
            x2 = floor(cx + r1 * cos(a) + 0.5), y2 = floor(cy + r1 * sin(a) + 0.5),
            color = color or 0xE9A45F, width = 3, round_start = true, round_end = true,
        },
        { type = "circle", cx = cx, cy = cy, r = 4, color = color or 0xE9A45F, fill = true, fill_color = color or 0xE9A45F },
    }
    return items
end

-- ===================== 豆形剪影 =====================
-- kind: long(长粒) / round(圆豆) / flat(扁豆) / pea(小圆豆)
function M.bean_items(cx, cy, s, color, kind)
    kind = kind or "long"
    local rx, ry, rot = 0.46, 0.30, 0
    if kind == "round" then rx, ry = 0.40, 0.36
    elseif kind == "flat" then rx, ry, rot = 0.50, 0.28, -12
    elseif kind == "pea" then rx, ry = 0.34, 0.34 end
    rx, ry = floor(rx * s + 0.5), floor(ry * s + 0.5)
    local items = {
        { type = "ellipse", cx = cx, cy = cy, rx = rx, ry = ry, color = color,
          fill = true, fill_color = color, fill_opacity = 235, width = 2 },
        -- 中线（咖啡豆的沟槽）
        { type = "arc", cx = cx, cy = cy, r = floor(ry * 0.86 + 0.5),
          start_angle = 40 + rot, end_angle = 320 + rot, color = 0x1A1310, width = 2, opacity = 220 },
        { type = "line", x1 = cx - floor(rx * 0.2), y1 = cy - ry + 2, x2 = cx + floor(rx * 0.2), y2 = cy + ry - 2,
          color = 0x1A1310, width = 2, opacity = 200 },
        -- 高光
        { type = "ellipse", cx = cx - floor(rx * 0.32), cy = cy - floor(ry * 0.30),
          rx = floor(rx * 0.22 + 0.5), ry = floor(ry * 0.14 + 0.5), color = 0xFFFFFF,
          fill = true, fill_color = 0xFFFFFF, fill_opacity = 46, width = 0 },
    }
    return items
end

-- ===================== 图标（24 网格矢量）=====================
local ICONS = {
    flame = function(u, c)
        return {
            { type = "line", x1 = u(12), y1 = u(3), x2 = u(12), y2 = u(8), color = c, width = 2, round_end = true },
            { type = "arc", cx = u(12), cy = u(14), r = u(7), start_angle = 30, end_angle = 210, color = c, width = 2, rounded = true },
            { type = "arc", cx = u(12), cy = u(15), r = u(3), start_angle = 30, end_angle = 210, color = c, width = 2, rounded = true },
        }
    end,
    fan = function(u, c)
        return {
            { type = "circle", cx = u(12), cy = u(12), r = u(2), color = c, width = 2 },
            { type = "arc", cx = u(12), cy = u(9), r = u(4), start_angle = 200, end_angle = 340, color = c, width = 2, rounded = true },
            { type = "arc", cx = u(9), cy = u(14), r = u(4), start_angle = 80, end_angle = 220, color = c, width = 2, rounded = true },
            { type = "arc", cx = u(15), cy = u(14), r = u(4), start_angle = 320, end_angle = 100, color = c, width = 2, rounded = true },
        }
    end,
    drum = function(u, c)
        return {
            { type = "rect", x = u(3), y = u(5), w = u(18), h = u(14), radius = u(5), color = c, width = 2 },
            { type = "line", x1 = u(7), y1 = u(9), x2 = u(7), y2 = u(15), color = c, width = 2 },
            { type = "line", x1 = u(12), y1 = u(8), x2 = u(12), y2 = u(16), color = c, width = 2 },
            { type = "line", x1 = u(17), y1 = u(9), x2 = u(17), y2 = u(15), color = c, width = 2 },
        }
    end,
    temp = function(u, c)
        return {
            { type = "rect", x = u(9), y = u(3), w = u(6), h = u(12), radius = u(3), color = c, width = 2 },
            { type = "circle", cx = u(12), cy = u(17), r = u(4), color = c, width = 2, fill = true, fill_color = c, fill_opacity = 60 },
            { type = "line", x1 = u(12), y1 = u(16), x2 = u(12), y2 = u(8), color = c, width = 2 },
        }
    end,
    clock = function(u, c)
        return {
            { type = "circle", cx = u(12), cy = u(12), r = u(8), color = c, width = 2 },
            { type = "line", x1 = u(12), y1 = u(12), x2 = u(12), y2 = u(7), color = c, width = 2 },
            { type = "line", x1 = u(12), y1 = u(12), x2 = u(16), y2 = u(13), color = c, width = 2 },
        }
    end,
    back = function(u, c)
        return {
            { type = "line", x1 = u(14), y1 = u(5), x2 = u(8), y2 = u(12), color = c, width = 2, round_start = true, round_end = true },
            { type = "line", x1 = u(8), y1 = u(12), x2 = u(14), y2 = u(19), color = c, width = 2, round_start = true, round_end = true },
        }
    end,
    arrow = function(u, c)
        return {
            { type = "line", x1 = u(9), y1 = u(6), x2 = u(15), y2 = u(12), color = c, width = 2, round_start = true, round_end = true },
            { type = "line", x1 = u(15), y1 = u(12), x2 = u(9), y2 = u(18), color = c, width = 2, round_start = true, round_end = true },
        }
    end,
    save = function(u, c)
        return {
            { type = "rect", x = u(4), y = u(4), w = u(16), h = u(16), radius = u(3), color = c, width = 2 },
            { type = "line", x1 = u(8), y1 = u(4), x2 = u(8), y2 = u(9), color = c, width = 2 },
            { type = "line", x1 = u(8), y1 = u(9), x2 = u(16), y2 = u(9), color = c, width = 2 },
            { type = "rect", x = u(8), y = u(13), w = u(8), h = u(7), radius = u(1), color = c, width = 1 },
        }
    end,
    list = function(u, c)
        return {
            { type = "circle", cx = u(5), cy = u(7), r = u(1), color = c, fill = true, fill_color = c },
            { type = "circle", cx = u(5), cy = u(12), r = u(1), color = c, fill = true, fill_color = c },
            { type = "circle", cx = u(5), cy = u(17), r = u(1), color = c, fill = true, fill_color = c },
            { type = "line", x1 = u(9), y1 = u(7), x2 = u(19), y2 = u(7), color = c, width = 2 },
            { type = "line", x1 = u(9), y1 = u(12), x2 = u(19), y2 = u(12), color = c, width = 2 },
            { type = "line", x1 = u(9), y1 = u(17), x2 = u(19), y2 = u(17), color = c, width = 2 },
        }
    end,
    gear = function(u, c)
        local items = {
            { type = "circle", cx = u(12), cy = u(12), r = u(7), color = c, width = 2 },
            { type = "circle", cx = u(12), cy = u(12), r = u(3), color = c, width = 2 },
        }
        for i = 0, 7 do
            local a = rad(i * 45)
            items[#items + 1] = {
                type = "line",
                x1 = floor(u(12) + u(7) * cos(a)), y1 = floor(u(12) + u(7) * sin(a)),
                x2 = floor(u(12) + u(9.5) * cos(a)), y2 = floor(u(12) + u(9.5) * sin(a)),
                color = c, width = 2,
            }
        end
        return items
    end,
    compare = function(u, c)
        return {
            { type = "line", x1 = u(3), y1 = u(18), x2 = u(21), y2 = u(18), color = c, width = 2 },
            { type = "line", x1 = u(5), y1 = u(16), x2 = u(10), y2 = u(8), color = c, width = 2, round_end = true },
            { type = "line", x1 = u(10), y1 = u(8), x2 = u(15), y2 = u(14), color = c, width = 2, round_end = true },
            { type = "line", x1 = u(15), y1 = u(14), x2 = u(20), y2 = u(5), color = c, width = 2, round_end = true, dash_width = 4, dash_gap = 3 },
        }
    end,
    drop = function(u, c)
        return {
            { type = "line", x1 = u(12), y1 = u(3), x2 = u(12), y2 = u(8), color = c, width = 2 },
            { type = "arc", cx = u(12), cy = u(14), r = u(6), start_angle = 20, end_angle = 200, color = c, width = 2, rounded = true },
            { type = "line", x1 = u(6), y1 = u(20), x2 = u(18), y2 = u(20), color = c, width = 2 },
        }
    end,
}

function M.icon_items(kind, s, color)
    local f = ICONS[kind]
    if not f then return {} end
    local k = s / 24
    local function u(v) return floor(v * k + 0.5) end
    return f(u, color or 0xC8763C)
end

-- 直接创建图标控件
function M.icon(parent, kind, x, y, s, color)
    return airui.shape({
        parent = parent, x = x, y = y, w = s, h = s,
        items = M.icon_items(kind, s, color),
    })
end

-- 迷你趋势线（数值表底部小火花线）
function M.spark_items(w, h, hist, color, vmin, vmax)
    local items = {}
    local n = #hist
    if n < 2 then return items end
    vmin = vmin or hist[1]
    vmax = vmax or hist[1]
    if vmax - vmin < 0.001 then vmax = vmin + 1 end
    local step = w / (n - 1)
    local function vy(v)
        return floor(h - 2 - clamp01((v - vmin) / (vmax - vmin)) * (h - 4) + 0.5)
    end
    for i = 1, n - 1 do
        items[#items + 1] = {
            type = "line",
            x1 = floor((i - 1) * step + 0.5), y1 = vy(hist[i]),
            x2 = floor(i * step + 0.5), y2 = vy(hist[i + 1]),
            color = color, width = 2, round_start = true, round_end = true,
        }
    end
    items[#items + 1] = {
        type = "circle", cx = floor((n - 1) * step + 0.5), cy = vy(hist[n]), r = 2,
        color = color, fill = true, fill_color = color, width = 1,
    }
    return items
end

return M
