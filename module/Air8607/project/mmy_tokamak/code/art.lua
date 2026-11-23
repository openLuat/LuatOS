--[[
@module  art
@summary HELIOS-1 图形素材库：环形真空室、极向截面、波形、频谱、图标（全部 airui.shape 图元拼绘）
@version 1.0
@date    2026.11.12
]]
local theme = require "theme"
local C = theme.C

local M = {}

local function I(v) return math.floor(v + 0.5) end

local function clamp01(t)
    if t < 0 then return 0 elseif t > 1 then return 1 end
    return t
end
M.clamp01 = clamp01

local function circle(items, cx, cy, r, color, fill, opa, width, fill_opa)
    items[#items + 1] = {
        type = "circle", cx = I(cx), cy = I(cy), r = math.max(1, I(r)),
        color = color, width = width or 2, opacity = opa or 255,
        fill = fill and true or false,
        fill_color = color, fill_opacity = (fill and (fill_opa or 255) or 0),
    }
end

local function line(items, x1, y1, x2, y2, color, width, opa)
    items[#items + 1] = {
        type = "line", x1 = I(x1), y1 = I(y1), x2 = I(x2), y2 = I(y2),
        color = color, width = width or 2, opacity = opa or 255,
        round_start = true, round_end = true,
    }
end

local function arc(items, cx, cy, r, a1, a2, color, width, opa)
    items[#items + 1] = {
        type = "arc", cx = I(cx), cy = I(cy), r = math.max(1, I(r)),
        start_angle = a1, end_angle = a2, color = color,
        width = width or 2, opacity = opa or 255, rounded = true,
    }
end

local function rect(items, x, y, w, h, color, radius, fill, opa)
    items[#items + 1] = {
        type = "rect", x = I(x), y = I(y), w = math.max(1, I(w)), h = math.max(1, I(h)),
        radius = I(radius or 0), color = color, width = 2, opacity = opa or 255,
        fill = fill and true or false, fill_color = color,
        fill_opacity = (fill and (opa or 255) or 0),
    }
end

local function ellipse(items, cx, cy, rx, ry, color, width, opa, fill, fill_opa)
    items[#items + 1] = {
        type = "ellipse", cx = I(cx), cy = I(cy), rx = math.max(1, I(rx)), ry = math.max(1, I(ry)),
        color = color, width = width or 2, opacity = opa or 255,
        fill = fill and true or false, fill_color = color, fill_opacity = (fill and (fill_opa or 255) or 0),
    }
end

-- ===================== 环形真空室（3/4 视图）=====================
--[[
环形真空室用「同轴椭圆环」堆出来：
  外缘 rx = R + rt，内缘 rx = R - rt，ry 按 squash 压扁（透视）
  逐环 2px 递进，颜色按 sin 曲线做柱面明暗，看起来是一只金属甜甜圈。
等离子体是管芯处一圈更细的彩色环，功率越高越亮；粒子沿环心运动。
]]
function M.torus(parent, cx, cy, R, rt, squash, opts)
    opts = opts or {}
    local w = opts.w or 1024
    local h = opts.h or 600
    local vessel_lo = opts.vessel_lo or 0x080B14
    local vessel_hi = opts.vessel_hi or 0x3A4664
    local plasma_hi = opts.plasma_hi or C.plasma
    local plasma_lo = opts.plasma_lo or C.coral
    local coil = opts.coil or 0x2A3350

    local static = {}
    local outer_rx, outer_ry = R + rt, (R + rt) * squash

    -- 外层辉光：两个低透明度实心椭圆，给深色底一点等离子体溢光
    ellipse(static, cx, cy, outer_rx + 26, outer_ry + 26 * squash, plasma_hi, 1, 24, true, 12)
    ellipse(static, cx, cy, outer_rx + 12, outer_ry + 12 * squash, plasma_hi, 1, 30, true, 18)

    -- 中心孔：先铺深底，避免辉光透进孔里
    local hole_rx, hole_ry = R - rt, (R - rt) * squash
    ellipse(static, cx, cy, hole_rx, hole_ry, C.bg0, 1, 255, true, 255)

    -- 金属环体
    local N = math.max(12, math.floor(rt))
    for k = 0, N - 1 do
        local t = k / (N - 1)
        local rx = outer_rx - 2 * rt * t
        local ry = rx * squash
        local shade = 0.30 + 0.70 * math.sin(math.pi * t)
        local col = theme.mix(vessel_lo, vessel_hi, shade * 0.85)
        ellipse(static, cx, cy, rx, ry, col, 2, 255)
    end

    -- 内外缘高光
    ellipse(static, cx, cy, outer_rx, outer_ry, theme.mix(vessel_hi, C.ink, 0.30), 1, 150)
    ellipse(static, cx, cy, hole_rx, hole_ry, theme.mix(vessel_hi, C.ink, 0.16), 1, 120)

    -- 环向场线圈：外缘一圈短径向刻线，像笼住环体的线圈
    local coils = 16
    for i = 0, coils - 1 do
        local a = math.pi * 2 * i / coils
        local ca, sa = math.cos(a), math.sin(a)
        local x1 = cx + ca * (outer_rx + 1)
        local y1 = cy + sa * (outer_ry + 1 * squash)
        local x2 = cx + ca * (outer_rx + 10)
        local y2 = cy + sa * (outer_ry + 10 * squash)
        line(static, x1, y1, x2, y2, coil, 3, 210)
        circle(static, x2, y2, 2, theme.mix(coil, C.ink, 0.35), false, 200, 1)
    end

    -- 中心螺线管：孔里的竖圆柱
    local sw = math.max(12, I(rt * 0.55))
    rect(static, cx - sw / 2, cy - hole_ry * 0.78, sw, hole_ry * 1.56, 0x1A2135, 4, true, 255)
    for i = 0, 5 do
        local yy = cy - hole_ry * 0.72 + i * (hole_ry * 1.44 / 5)
        line(static, cx - sw / 2 + 2, yy, cx + sw / 2 - 2, yy, 0x394666, 1, 170)
    end

    local shape = theme.shape(parent, 0, 0, w, h, static)

    -- 等离子体带：单独一个 shape，功率变化时整体换色
    local pl = {}
    for k = 0, 11 do
        local t = k / 11
        local rr = R - 9 + 18 * t
        local k2 = math.sin(math.pi * t)
        local col = theme.mix(plasma_hi, plasma_lo, t)
        pl[#pl + 1] = {
            type = "ellipse", cx = I(cx), cy = I(cy), rx = I(rr), ry = I(rr * squash),
            color = col, width = 3, opacity = I(40 + 150 * k2),
        }
    end
    local plasma = theme.shape(parent, 0, 0, w, h, pl)

    -- 粒子：两条流，前侧粒子更大
    local parts = {}
    for i = 1, 12 do
        local front = (i % 2 == 0)
        local sz = front and 6 or 4
        parts[i] = {
            shape = theme.shape(parent, cx, cy, sz, sz, {
                { type = "circle", cx = I(sz / 2), cy = I(sz / 2), r = I(sz / 2) - 1,
                  color = front and 0xFFD9E6 or plasma_hi, width = 1, opacity = 230,
                  fill = true, fill_color = front and 0xFFD9E6 or plasma_hi, fill_opacity = 200 },
            }),
            a = math.pi * 2 * i / 12,
            w = 0.34 + (i % 3) * 0.06,
            dr = (i % 2 == 0) and 2 or -4,
            sz = sz,
        }
    end

    local obj = {
        shape = shape,
        plasma = plasma,
        parts = parts,
        cx = cx, cy = cy, R = R, squash = squash,
        level = -1,
    }

    function obj.set_power(p)
        p = clamp01(p or 0)
        if math.abs(p - obj.level) < 0.04 then return end
        obj.level = p
        local items = {}
        for k = 0, 11 do
            local t = k / 11
            local rr = R - 9 + 18 * t
            local k2 = math.sin(math.pi * t)
            local col = theme.mix(theme.mix(plasma_hi, plasma_lo, t), 0xFFFFFF, 0.25 * p)
            items[#items + 1] = {
                type = "ellipse", cx = I(cx), cy = I(cy), rx = I(rr), ry = I(rr * squash),
                color = col, width = 3,
                opacity = I((26 + 160 * k2) * (0.35 + 0.65 * p)),
            }
        end
        pcall(function() plasma:set_items(items) end)
    end

    function obj.update(t)
        for _, p in ipairs(parts) do
            local a = p.a + t * p.w
            local rr = R + p.dr
            local x = cx + math.cos(a) * rr
            local y = cy + math.sin(a) * rr * squash
            pcall(function() p.shape:set_pos(I(x - p.sz / 2), I(y - p.sz / 2)) end)
        end
    end

    return obj
end

-- ===================== 曲线 =====================
local function catmull(p0, p1, p2, p3, t)
    local t2 = t * t
    local t3 = t2 * t
    return 0.5 * ((2 * p1)
        + (p2 - p0) * t
        + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
        + (3 * p1 - p0 - 3 * p2 + p3) * t3)
end

-- 稀疏样本按 Catmull-Rom 重采样，避免点对点直线画成台阶
function M.resample(hist, n_out)
    local out = {}
    local n = #hist
    if n < 2 or n_out < 2 then return out end
    local last = n_out - 1
    for k = 0, last do
        local fx = (n - 1) * k / last
        local i = math.floor(fx)
        if i > n - 2 then i = n - 2 end
        if i < 0 then i = 0 end
        local t = fx - i
        local i1 = i + 1
        out[k + 1] = catmull(hist[math.max(1, i1 - 1)], hist[i1],
                             hist[math.min(n, i1 + 1)], hist[math.min(n, i1 + 2)], t)
    end
    return out
end

--[[
多序列曲线。每条序列可给独立的 min/max（双 Y 轴），按自身量纲归一化。
series = { {data=, color=, min=, max=, width=, area=, opacity=}, ... }
]]
function M.curve_items(w, h, series, opts)
    opts = opts or {}
    local pad_t = opts.pad_top or 12
    local pad_b = opts.pad_bottom or 16
    local ih = h - pad_t - pad_b
    local items = {}

    -- 网格
    local grid = opts.grid or 4
    for i = 0, grid do
        local y = I(pad_t + ih * i / grid)
        line(items, 0, y, w, y, C.line, 1, 120)
    end
    for i = 1, 5 do
        local x = I(w * i / 6)
        line(items, x, pad_t, x, pad_t + ih, C.line, 1, 60)
    end

    -- 相位色带（x 为 0..1）
    if opts.bands then
        for _, b in ipairs(opts.bands) do
            local x1 = I(b.from * w)
            local x2 = I(b.to * w)
            if x2 > x1 then
                items[#items + 1] = {
                    type = "rect", x = x1, y = pad_t, w = x2 - x1, h = ih,
                    color = b.color, width = 1, opacity = b.opacity or 16,
                    fill = true, fill_color = b.color, fill_opacity = b.opacity or 14,
                }
            end
        end
    end

    for _, s in ipairs(series) do
        local n = #s.data
        if n >= 2 then
            local vmin = s.min or 0
            local vmax = s.max or 1
            if vmax - vmin < 0.000001 then vmax = vmin + 1 end

            local ys = {}
            for i = 1, n do
                local k = clamp01((s.data[i] - vmin) / (vmax - vmin))
                ys[i] = pad_t + ih - k * ih
            end
            local samples = M.resample(ys, math.max(2, math.floor(w / (opts.sample or 4))))

            if s.area then
                local dx = 8
                for x = 0, w - 1, dx do
                    local idx = math.min(#samples, math.max(1, math.floor(x / (w - 1) * (#samples - 1)) + 1))
                    local y = samples[idx]
                    if pad_t + ih - y > 1 then
                        items[#items + 1] = {
                            type = "rect", x = x, y = I(y), w = dx + 1, h = I(pad_t + ih - y),
                            color = s.color, width = 1,
                            fill = true, fill_color = s.color, fill_opacity = s.area_opa or 18,
                        }
                    end
                end
            end

            for i = 2, #samples do
                local x1 = I((i - 2) / (#samples - 1) * (w - 1))
                local x2 = I((i - 1) / (#samples - 1) * (w - 1))
                line(items, x1, samples[i - 1], x2, samples[i], s.color, s.width or 2, s.opacity or 255)
            end

            local ly = samples[#samples]
            circle(items, w - 2, ly, 7, s.color, true, 40, 1, 40)
            circle(items, w - 2, ly, 3, 0xFFFFFF, true, 255, 1, 255)
        end
    end

    return items
end

-- 频谱瀑布：cols 列 × rows 行的小方块，颜色随幅值从冷到热
function M.spectrum_items(w, h, cols, rows, data, bg, hot)
    local items = {}
    local cw = w / cols
    local ch = h / rows
    for c = 1, cols do
        local col_data = data[c]
        if col_data then
            for r = 1, rows do
                local v = clamp01(col_data[r] or 0)
                local col = (v < 0.02) and bg or theme.mix(bg, hot, math.min(1, v * 1.15))
                items[#items + 1] = {
                    type = "rect",
                    x = I((c - 1) * cw) + 1, y = I((r - 1) * ch) + 1,
                    w = math.max(1, I(cw) - 2), h = math.max(1, I(ch) - 2),
                    radius = 1, color = col, width = 1,
                    fill = true, fill_color = col, fill_opacity = I(60 + 195 * v),
                    opacity = I(60 + 195 * v),
                }
            end
        end
    end
    return items
end

-- ===================== 极向截面 =====================
-- D 形轮廓：右半椭圆 + 左侧竖边，用折线逼近（airui 的 arc 是正圆，做不了非等比）
function M.d_points(cx, cy, rx, ry, n)
    local pts = {}
    n = n or 26
    for i = 0, n do
        local a = -math.pi / 2 + math.pi * i / n
        pts[#pts + 1] = { cx + math.cos(a) * rx, cy + math.sin(a) * ry }
    end
    pts[#pts + 1] = { cx - rx, cy + ry }
    pts[#pts + 1] = { cx - rx, cy - ry }
    return pts
end

local function polyline(items, pts, color, width, opa)
    for i = 2, #pts do
        line(items, pts[i - 1][1], pts[i - 1][2], pts[i][1], pts[i][2], color, width, opa)
    end
end

--[[
极向截面：真空室 / 等离子体边界 / 三道磁面 / 中心螺线管 / 6 组 PF 线圈
返回 shape（静态结构），等离子体边界单独返回以便按功率改色
]]
function M.cross_section(parent, w, h)
    local cx, cy = math.floor(w * 0.52), math.floor(h * 0.50)
    local rx, ry = 88, 106

    local items = {}

    -- 真空室（外/内壁）
    polyline(items, M.d_points(cx, cy, rx, ry), C.steel, 3, 255)
    polyline(items, M.d_points(cx, cy, rx - 7, ry - 7), 0x1A2135, 2, 255)

    -- 磁面：三条缩放的 D 形虚线感
    for i = 1, 3 do
        local k = 0.30 + i * 0.17
        local pts = M.d_points(cx + 12, cy, rx * k, ry * k)
        polyline(items, pts, i == 3 and theme.mix(C.violet, C.bg0, 0.35) or C.line2, 1, i == 3 and 130 or 90)
    end

    -- 中心螺线管
    local cs_x = cx - rx - 26
    rect(items, cs_x, cy - ry * 0.82, 20, ry * 1.64, 0x1A2135, 3, true, 255)
    for i = 0, 8 do
        local yy = cy - ry * 0.78 + i * (ry * 1.56 / 8)
        line(items, cs_x + 2, yy, cs_x + 18, yy, 0x3A4766, 1, 180)
    end

    -- PF 线圈：左右各三组
    local coils = {
        { cx - rx - 62, cy - ry * 0.78 }, { cx - rx - 62, cy }, { cx - rx - 62, cy + ry * 0.78 },
        { cx + rx + 34, cy - ry * 0.78 }, { cx + rx + 34, cy }, { cx + rx + 34, cy + ry * 0.78 },
    }
    for i, p in ipairs(coils) do
        rect(items, p[1], p[2] - 14, 26, 28, 0x1D2438, 4, true, 255)
        rect(items, p[1] + 4, p[2] - 10, 18, 20, C.steel, 3, false, 220)
        line(items, p[1] + 4, p[2], p[1] + 22, p[2], C.ion, 1, 120)
    end

    -- 偏滤器：底部两条斜线交于 X 点
    line(items, cx + 6, cy + ry - 6, cx + 44, cy + ry + 12, C.gold, 2, 190)
    line(items, cx + 60, cy + ry - 6, cx + 40, cy + ry + 12, C.gold, 2, 190)

    local shape = theme.shape(parent, 0, 0, w, h, items)

    -- 等离子体边界
    local pl_items = {}
    local pts = M.d_points(cx + 14, cy, rx * 0.66, ry * 0.82)
    polyline(pl_items, pts, C.plasma, 3, 255)
    local pts2 = M.d_points(cx + 14, cy, rx * 0.66 - 4, ry * 0.82 - 4)
    polyline(pl_items, pts2, theme.mix(C.plasma, 0xFFFFFF, 0.35), 1, 150)
    local plasma = theme.shape(parent, 0, 0, w, h, pl_items)

    local geo = {
        cx = cx, cy = cy, rx = rx, ry = ry,
        coils = coils, cs_x = cs_x,
    }

    local obj = { shape = shape, plasma = plasma, geo = geo, level = -1 }

    function obj.set_power(p)
        p = clamp01(p or 0)
        if math.abs(p - obj.level) < 0.05 then return end
        obj.level = p
        local out = {}
        local pts3 = M.d_points(cx + 14, cy, rx * 0.66, ry * 0.82)
        polyline(out, pts3, theme.mix(C.plasma, C.coral, 0.4 * (1 - p)), 2 + math.floor(p * 3), 180 + I(75 * p))
        if p > 0.15 then
            local pts4 = M.d_points(cx + 14, cy, rx * 0.55, ry * 0.70)
            polyline(out, pts4, theme.mix(C.plasma, 0xFFFFFF, 0.5), 1, I(60 + 120 * p))
        end
        pcall(function() plasma:set_items(out) end)
    end

    return obj
end

-- PF 线圈电流：以中线为零点，左右伸展
function M.bar_center_items(w, h, value, full, color, track)
    local items = {}
    local mid = math.floor(w / 2)
    local half = math.floor(w / 2 - 2)
    items[#items + 1] = {
        type = "rect", x = 0, y = math.floor(h / 2), w = w, h = 1,
        color = track or C.line, width = 1, opacity = 200,
        fill = true, fill_color = track or C.line, fill_opacity = 200,
    }
    local k = math.max(-1, math.min(1, (value or 0) / math.max(0.1, full or 10)))
    local len = math.floor(half * math.abs(k))
    if len > 0 then
        local x = (k >= 0) and mid or (mid - len)
        items[#items + 1] = {
            type = "rect", x = x, y = 2, w = len, h = h - 4, radius = 2,
            color = color or C.ion, width = 1,
            fill = true, fill_color = color or C.ion, fill_opacity = 235,
        }
    end
    items[#items + 1] = {
        type = "circle", cx = mid, cy = math.floor(h / 2), r = 2,
        color = C.ink3, width = 1, fill = true, fill_color = C.ink3,
    }
    return items
end

-- ===================== 环形表 =====================
function M.ring_items(size, pct, color, track, width, start_angle)
    local c0 = math.floor(size / 2)
    local r = math.floor(size / 2 - 6)
    width = width or 6
    track = track or C.panel3
    start_angle = start_angle or -90
    local items = {
        { type = "arc", cx = c0, cy = c0, r = r, start_angle = 0, end_angle = 359,
          color = track, width = width, opacity = 255 },
    }
    pct = clamp01(pct or 0)
    if pct > 0.005 then
        items[#items + 1] = {
            type = "arc", cx = c0, cy = c0, r = r,
            start_angle = start_angle,
            end_angle = math.floor(start_angle + 359.6 * pct),
            color = color, width = width, rounded = true,
        }
    end
    return items
end

-- 竖向温度计：外框 + 填充（填充靠改 items 实现）
function M.thermo_items(w, h, pct, color, track)
    local items = {}
    local bw = math.max(8, math.floor(w * 0.44))
    local bx = math.floor((w - bw) / 2)
    items[#items + 1] = {
        type = "rect", x = bx, y = 0, w = bw, h = h, radius = math.floor(bw / 2),
        color = track or C.panel3, width = 1,
        fill = true, fill_color = track or C.panel3, fill_opacity = 255,
    }
    local fh = math.floor((h - 4) * clamp01(pct or 0))
    if fh > 1 then
        items[#items + 1] = {
            type = "rect", x = bx + 2, y = h - 2 - fh, w = bw - 4, h = fh,
            radius = math.floor((bw - 4) / 2), color = color, width = 1,
            fill = true, fill_color = color, fill_opacity = 240,
        }
    end
    return items
end

-- ===================== 图标 =====================
function M.icon_items(kind, s, color)
    local items = {}
    local c = color or C.ink
    local mid = s / 2

    if kind == "torus" then
        ellipse(items, mid, mid, s * 0.44, s * 0.26, c, 2)
        ellipse(items, mid, mid, s * 0.18, s * 0.10, c, 2)
        circle(items, mid + s * 0.30, mid, 1, c, true)

    elseif kind == "bolt" then
        line(items, s * 0.58, s * 0.08, s * 0.26, s * 0.54, c, 2)
        line(items, s * 0.26, s * 0.54, s * 0.50, s * 0.54, c, 2)
        line(items, s * 0.50, s * 0.54, s * 0.40, s * 0.92, c, 2)
        line(items, s * 0.40, s * 0.92, s * 0.76, s * 0.44, c, 2)
        line(items, s * 0.76, s * 0.44, s * 0.52, s * 0.44, c, 2)
        line(items, s * 0.52, s * 0.44, s * 0.58, s * 0.08, c, 2)

    elseif kind == "magnet" then
        arc(items, mid, s * 0.52, s * 0.30, 180, 360, c, 3)
        line(items, s * 0.20, s * 0.52, s * 0.20, s * 0.86, c, 3)
        line(items, s * 0.80, s * 0.52, s * 0.80, s * 0.86, c, 3)
        line(items, s * 0.12, s * 0.86, s * 0.28, s * 0.86, c, 3)
        line(items, s * 0.72, s * 0.86, s * 0.88, s * 0.86, c, 3)

    elseif kind == "beam" then
        line(items, s * 0.08, s * 0.30, s * 0.52, s * 0.30, c, 2)
        line(items, s * 0.08, s * 0.50, s * 0.52, s * 0.50, c, 2)
        line(items, s * 0.08, s * 0.70, s * 0.52, s * 0.70, c, 2)
        line(items, s * 0.58, s * 0.50, s * 0.90, s * 0.50, c, 2)
        line(items, s * 0.90, s * 0.50, s * 0.76, s * 0.38, c, 2)
        line(items, s * 0.90, s * 0.50, s * 0.76, s * 0.62, c, 2)

    elseif kind == "wave" then
        local px, py = 0, mid
        for i = 1, 16 do
            local x = s * i / 16
            local y = mid - math.sin(i / 16 * math.pi * 2) * s * 0.26
            line(items, px, py, x, y, c, 2)
            px, py = x, y
        end

    elseif kind == "snow" then
        for i = 0, 2 do
            local a = math.pi * i / 3
            local dx, dy = math.cos(a) * s * 0.36, math.sin(a) * s * 0.36
            line(items, mid - dx, mid - dy, mid + dx, mid + dy, c, 2)
            line(items, mid + dx * 0.6, mid + dy * 0.6,
                mid + dx * 0.6 - dy * 0.2, mid + dy * 0.6 + dx * 0.2, c, 2)
            line(items, mid - dx * 0.6, mid - dy * 0.6,
                mid - dx * 0.6 + dy * 0.2, mid - dy * 0.6 - dx * 0.2, c, 2)
        end

    elseif kind == "pump" then
        circle(items, mid, mid, s * 0.34, c, false, 255, 2)
        circle(items, mid, mid, s * 0.05, c, true)
        line(items, mid, mid, mid + s * 0.20, mid - s * 0.16, c, 2)
        line(items, mid + s * 0.20, mid - s * 0.16, mid + s * 0.20, mid - s * 0.02, c, 2)

    elseif kind == "drop" then
        arc(items, mid, s * 0.64, s * 0.26, 180, 360, c, 2)
        line(items, s * 0.24, s * 0.64, mid, s * 0.16, c, 2)
        line(items, mid, s * 0.16, s * 0.76, s * 0.64, c, 2)

    elseif kind == "shield" then
        line(items, mid, s * 0.10, s * 0.82, s * 0.28, c, 2)
        line(items, s * 0.82, s * 0.28, s * 0.82, s * 0.56, c, 2)
        line(items, s * 0.82, s * 0.56, mid, s * 0.90, c, 2)
        line(items, mid, s * 0.90, s * 0.18, s * 0.56, c, 2)
        line(items, s * 0.18, s * 0.56, s * 0.18, s * 0.28, c, 2)
        line(items, s * 0.18, s * 0.28, mid, s * 0.10, c, 2)

    elseif kind == "gear" then
        circle(items, mid, mid, s * 0.28, c, false, 255, 2)
        circle(items, mid, mid, s * 0.09, c, false, 255, 2)
        for i = 0, 5 do
            local a = math.pi * 2 * i / 6 - math.pi / 2
            line(items, mid + math.cos(a) * s * 0.30, mid + math.sin(a) * s * 0.30,
                mid + math.cos(a) * s * 0.42, mid + math.sin(a) * s * 0.42, c, 3)
        end

    elseif kind == "warn" then
        line(items, mid, s * 0.12, s * 0.12, s * 0.84, c, 2)
        line(items, s * 0.12, s * 0.84, s * 0.88, s * 0.84, c, 2)
        line(items, s * 0.88, s * 0.84, mid, s * 0.12, c, 2)
        line(items, mid, s * 0.38, mid, s * 0.60, c, 2)
        circle(items, mid, s * 0.71, 1, c, true)

    elseif kind == "check" then
        line(items, s * 0.18, s * 0.52, s * 0.42, s * 0.76, c, 3)
        line(items, s * 0.42, s * 0.76, s * 0.82, s * 0.24, c, 3)

    elseif kind == "play" then
        line(items, s * 0.30, s * 0.18, s * 0.30, s * 0.82, c, 2)
        line(items, s * 0.30, s * 0.18, s * 0.80, mid, c, 2)
        line(items, s * 0.80, mid, s * 0.30, s * 0.82, c, 2)

    elseif kind == "stop" then
        rect(items, s * 0.26, s * 0.26, s * 0.48, s * 0.48, c, 3, true)

    elseif kind == "arrow" then
        line(items, s * 0.16, mid, s * 0.78, mid, c, 2)
        line(items, s * 0.78, mid, s * 0.58, mid - s * 0.18, c, 2)
        line(items, s * 0.78, mid, s * 0.58, mid + s * 0.18, c, 2)

    elseif kind == "atom" then
        circle(items, mid, mid, s * 0.07, c, true)
        ellipse(items, mid, mid, s * 0.42, s * 0.18, c, 2)
        ellipse(items, mid, mid, s * 0.18, s * 0.42, c, 2)

    elseif kind == "thermo" then
        rect(items, s * 0.40, s * 0.10, s * 0.20, s * 0.52, c, 6)
        circle(items, mid, s * 0.76, s * 0.16, c, true)
        line(items, mid, s * 0.34, mid, s * 0.66, c, 2)

    elseif kind == "gauge" then
        arc(items, mid, s * 0.72, s * 0.38, 200, 340, c, 2)
        line(items, mid, s * 0.72, mid + s * 0.20, s * 0.42, c, 2)
        circle(items, mid, s * 0.72, 2, c, true)

    elseif kind == "clock" then
        circle(items, mid, mid, s * 0.36, c, false, 255, 2)
        line(items, mid, mid, mid, s * 0.30, c, 2)
        line(items, mid, mid, s * 0.66, mid, c, 2)

    elseif kind == "spark" then
        line(items, mid, s * 0.10, mid, s * 0.90, c, 2)
        line(items, s * 0.10, mid, s * 0.90, mid, c, 2)
        line(items, s * 0.22, s * 0.22, s * 0.78, s * 0.78, c, 1)
        line(items, s * 0.78, s * 0.22, s * 0.22, s * 0.78, c, 1)

    elseif kind == "grid" then
        rect(items, s * 0.14, s * 0.14, s * 0.30, s * 0.30, c, 2, false)
        rect(items, s * 0.56, s * 0.14, s * 0.30, s * 0.30, c, 2, false)
        rect(items, s * 0.14, s * 0.56, s * 0.30, s * 0.30, c, 2, false)
        rect(items, s * 0.56, s * 0.56, s * 0.30, s * 0.30, c, 2, true)
    end

    return items
end

function M.icon(parent, kind, x, y, s, color)
    local items = M.icon_items(kind, s, color)
    if #items == 0 then return nil end
    return theme.shape(parent, x, y, s, s, items)
end

function M.icon_badge(parent, x, y, size, kind, color, bg, bg_opa, icon_pad)
    local box = theme.box(parent, x, y, size, size, bg or C.panel3, math.floor(size / 3), bg_opa)
    local pad = icon_pad or math.floor(size * 0.24)
    local ic = M.icon(parent, kind, x + pad, y + pad, size - pad * 2, color or C.ink)
    return box, ic
end

-- ===================== 小部件 =====================
function M.dot(parent, x, y, r, color)
    return theme.shape(parent, x - r, y - r, r * 2, r * 2, {
        { type = "circle", cx = r, cy = r, r = r, color = color, width = 1,
          fill = true, fill_color = color, fill_opacity = 255 },
    })
end

-- 虚线水平尺（用于截面上标注高度）
function M.ticks_items(w, n, color, len)
    local items = {}
    for i = 0, n do
        local x = math.floor(w * i / n)
        line(items, x, 0, x, len or 4, color or C.line, 1, 140)
    end
    return items
end

return M
