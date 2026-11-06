--[[
@module  art
@summary SkyLift 图形素材库：雪山、钢绳、缆车、雪粒、曲线、图标（全部用 airui.shape 图元拼绘）
@version 1.0
@date    2026.11.06
]]
local theme = require "theme"
local C = theme.C

local M = {}

local function clamp01(t)
    if t < 0 then return 0 elseif t > 1 then return 1 end
    return t
end
M.clamp01 = clamp01

local function I(v)
    return math.floor(v + 0.5)
end

-- ===================== 天色 =====================
-- daylight: 0 深夜 ~ 1 正午。返回 sky_top, sky_low, ambient(山体大气罩色), amb_opa
function M.sky_colors(daylight)
    daylight = clamp01(daylight)
    local top = theme.mix(0x030812, 0x14365C, daylight)
    local low = theme.mix(0x071323, 0x2F617F, daylight)
    if daylight < 0.18 then
        local k = (0.18 - daylight) / 0.18
        top = theme.mix(top, 0x0C1B3A, k * 0.55)
        low = theme.mix(low, 0x14304F, k * 0.40)
    end
    local ambient = theme.mix(0x050D18, 0x2C5A78, daylight)
    local opa = math.floor(110 - 60 * daylight)
    return top, low, ambient, opa
end

-- ===================== 山体 =====================
-- peaks = { {cx, peakY, slope}, ... }，逐列矩形拼三角山脊；y < snowline 的列用雪色
function M.ridge_items(w, h, peaks, color, snow_color, snowline, step)
    step = step or 8
    local items = {}
    local n = math.ceil(w / step)

    local function ridge_y(x)
        local best = h
        for _, p in ipairs(peaks) do
            local y = p[2] + math.abs(x - p[1]) * p[3]
            if y < best then best = y end
        end
        if best < 0 then best = 0 end
        if best > h then best = h end
        return best
    end

    for i = 0, n - 1 do
        local x = i * step
        local y = I(ridge_y(x + step * 0.5))
        local hh = h - y
        if hh > 0 then
            local col = color
            if snow_color and snowline and y < snowline then
                col = theme.mix(snow_color, color, clamp01((y - (snowline - 46)) / 46) * 0.45)
            end
            items[#items + 1] = {
                type = "rect", x = x, y = y, w = step, h = hh,
                color = col, fill = true, fill_color = col, width = 1, opacity = 255,
            }
        end
    end
    return items
end

-- ===================== 钢绳 =====================
function M.path_point(x1, y1, x2, y2, sag, t)
    local x = x1 + (x2 - x1) * t
    local y = y1 + (y2 - y1) * t + sag * 4 * t * (1 - t)
    return x, y
end

function M.cable_items(x1, y1, x2, y2, sag, color, segs, width, opacity)
    segs = segs or 20
    local items = {}
    local px, py
    for i = 0, segs do
        local x, y = M.path_point(x1, y1, x2, y2, sag, i / segs)
        if px then
            items[#items + 1] = {
                type = "line", x1 = I(px), y1 = I(py), x2 = I(x), y2 = I(y),
                color = color, width = width or 2, opacity = opacity or 255,
            }
        end
        px, py = x, y
    end
    return items
end

function M.cable(parent, x, y, w, h, x1, y1, x2, y2, sag, color)
    return theme.shape(parent, x, y, w, h, M.cable_items(x1, y1, x2, y2, sag, color))
end

-- ===================== 站房 =====================
function M.station_items(w, h, color, roof_color, cabin_side)
    local items = {}
    local bw = math.floor(w * 0.74)
    local bx = math.floor((w - bw) / 2)
    local by = math.floor(h * 0.34)
    items[#items + 1] = {
        type = "rect", x = 0, y = by - 8, w = w, h = 7, radius = 3,
        color = roof_color, fill = true, fill_color = roof_color, width = 1,
    }
    items[#items + 1] = {
        type = "rect", x = bx, y = by, w = bw, h = h - by - 2, radius = 2,
        color = color, fill = true, fill_color = color, width = 1,
    }
    local outlet = (cabin_side == "left") and (bx + bw - 7) or (bx + 1)
    items[#items + 1] = {
        type = "rect", x = outlet, y = by + 4, w = 6, h = 8,
        color = 0x08131F, fill = true, fill_color = 0x08131F, width = 1,
    }
    for i = 0, 2 do
        items[#items + 1] = {
            type = "rect", x = bx + 6 + i * 12, y = by + 16, w = 8, h = 10,
            color = roof_color, fill = true, fill_color = roof_color, width = 1, opacity = 120,
        }
    end
    return items
end

-- ===================== 支架塔 =====================
function M.tower_items(w, h, color, light)
    local cx = math.floor(w / 2)
    local items = {}
    items[#items + 1] = { type = "line", x1 = cx, y1 = 8, x2 = cx, y2 = h, color = color, width = 2 }
    items[#items + 1] = {
        type = "line", x1 = cx - 8, y1 = 8, x2 = cx + 8, y2 = 8,
        color = color, width = 3, round_start = true, round_end = true,
    }
    for _, dx in ipairs({ -8, 8 }) do
        items[#items + 1] = {
            type = "circle", cx = cx + dx, cy = 9, r = 2, color = light,
            fill = true, fill_color = light, width = 1,
        }
    end
    return items
end

-- ===================== 缆车 =====================
function M.cabin_items(w, h, color, load)
    local items = {}
    local body_w = w - 4
    local body_h = h - 12
    local bx = 2
    local by = 10
    items[#items + 1] = {
        type = "line", x1 = math.floor(w / 2), y1 = 0, x2 = math.floor(w / 2), y2 = by,
        color = color, width = 2,
    }
    items[#items + 1] = {
        type = "rect", x = math.floor(w / 2) - 4, y = 0, w = 8, h = 4, radius = 2,
        color = color, fill = true, fill_color = color, width = 1,
    }
    items[#items + 1] = {
        type = "rect", x = bx, y = by, w = body_w, h = body_h, radius = 5,
        color = color, fill = true, fill_color = theme.mix(color, 0x000000, 0.30), width = 1,
    }
    local win = theme.mix(0x0A1A26, 0xD9F0FF, 0.15 + 0.85 * clamp01(load or 0))
    items[#items + 1] = {
        type = "rect", x = bx + 3, y = by + 5, w = body_w - 6, h = math.floor(body_h * 0.45), radius = 2,
        color = win, fill = true, fill_color = win, width = 1, opacity = 235,
    }
    items[#items + 1] = {
        type = "rect", x = bx + 2, y = by + body_h - 6, w = body_w - 4, h = 4, radius = 2,
        color = theme.mix(color, 0x000000, 0.55), fill = true,
        fill_color = theme.mix(color, 0x000000, 0.55), width = 1,
    }
    items[#items + 1] = {
        type = "circle", cx = math.floor(w / 2), cy = by + 1, r = 1, color = C.ice,
        fill = true, fill_color = C.ice, width = 1, opacity = 200,
    }
    return items
end

function M.cabin(parent, x, y, w, h, color, load)
    return theme.shape(parent, x, y, w, h, M.cabin_items(w, h, color, load))
end

-- ===================== 雪粒 / 造雪雾 =====================
function M.flake(parent, x, y, r, color)
    local sz = r * 2 + 2
    local c = color or C.snow
    return theme.shape(parent, x, y, sz, sz, {
        { type = "circle", cx = r + 1, cy = r + 1, r = r,
          color = c, width = 1, opacity = 150, fill = true, fill_color = c, fill_opacity = 190 },
    })
end

function M.plume_items(w, h, color, strength)
    local items = {}
    local k = clamp01(strength or 0)
    if k <= 0.02 then return items end
    local puffs = {
        { 0.20, 0.70, 0.16 }, { 0.42, 0.50, 0.22 }, { 0.64, 0.30, 0.18 }, { 0.82, 0.16, 0.12 },
    }
    for _, p in ipairs(puffs) do
        local r = math.max(3, math.floor(w * p[3] * (0.6 + 0.4 * k)))
        items[#items + 1] = {
            type = "circle", cx = math.floor(w * p[1]), cy = math.floor(h * p[2]), r = r,
            color = color, width = 1, opacity = math.floor(30 + 90 * k),
            fill = true, fill_color = color, fill_opacity = math.floor(12 + 40 * k),
        }
    end
    return items
end

-- ===================== 趋势曲线 =====================
-- Catmull-Rom 三次插值：把稀疏采样补成连续曲线。
-- 历史缓冲只有 48 个样本，画布却有 300 px，若"点对点直线相连"，
-- 每个样本要横跨 6 px 且 y 只在样本处跳变，看起来就是一级级台阶（方波）。
local function catmull(p0, p1, p2, p3, t)
    local t2 = t * t
    local t3 = t2 * t
    return 0.5 * ((2 * p1)
        + (p2 - p0) * t
        + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
        + (3 * p1 - p0 - 3 * p2 + p3) * t3)
end

-- ys 为各样本的像素 y；返回按 x(0..w-1) 取插值后的像素 y
local function make_sampler(ys, n, w, h)
    local last = math.max(1, w - 1)
    return function(x)
        local fx = (n - 1) * x / last
        local i = math.floor(fx)
        if i > n - 2 then i = n - 2 end
        if i < 0 then i = 0 end
        local t = fx - i
        local i1 = i + 1
        local p0 = ys[math.max(1, i1 - 1)]
        local p1 = ys[i1]
        local p2 = ys[math.min(n, i1 + 1)]
        local p3 = ys[math.min(n, i1 + 2)]
        -- Catmull-Rom 会在拐点轻微过冲，钳一下防止冲出画布
        local y = catmull(p0, p1, p2, p3, t)
        if y < 1 then y = 1 elseif y > h - 1 then y = h - 1 end
        return math.floor(y + 0.5)
    end
end

-- 把稀疏样本按时间轴插值重采样成 n_out 个原始量纲的值（给 airui.chart 用）
function M.resample_curve(hist, n_out)
    local out = {}
    local n = #hist
    if n < 2 or n_out < 2 then return out end
    local last = n_out - 1
    for k = 0, last do
        local fx = (n - 1) * k / last
        local i = math.floor(fx)
        if i > n - 2 then i = n - 2 end
        local t = fx - i
        local i1 = i + 1
        out[k + 1] = catmull(hist[math.max(1, i1 - 1)], hist[i1],
                             hist[math.min(n, i1 + 1)], hist[math.min(n, i1 + 2)], t)
    end
    return out
end

function M.waveform_items(w, h, hist, opts)
    opts = opts or {}
    local color = opts.color or C.ice
    local vmin = opts.min or 0
    local vmax = opts.max or 1
    if vmax - vmin < 0.000001 then vmax = vmin + 1 end
    local pad = 10
    local ih = h - pad * 2

    local function vy(v)
        return math.floor(pad + ih - clamp01((v - vmin) / (vmax - vmin)) * ih)
    end

    local items = {}
    local grid = opts.grid or 4
    for i = 0, grid do
        local y = math.floor(pad + ih * i / grid)
        items[#items + 1] = {
            type = "line", x1 = 0, y1 = y, x2 = w, y2 = y,
            color = C.line, width = 1, opacity = 110,
        }
    end

    if opts.band and opts.band.lo and opts.band.hi then
        local y1, y2 = vy(opts.band.hi), vy(opts.band.lo)
        if y2 > y1 then
            items[#items + 1] = {
                type = "rect", x = 0, y = y1, w = w, h = y2 - y1,
                color = C.green, width = 1, opacity = 16,
                fill = true, fill_color = C.green, fill_opacity = 14,
            }
        end
    end

    local n = #hist
    if n >= 2 then
        local ys = {}
        for i = 1, n do ys[i] = vy(hist[i]) end
        local sample = make_sampler(ys, n, w, h)
        local area_color = opts.area_color or color

        -- 面积：每 8 px 一列贴到基线，纵坐标取自插值曲线，阶梯感随之消失
        local fill_dx = opts.fill_dx or 8
        for x = 0, w - 1, fill_dx do
            local y = sample(x)
            if h - y > 2 then
                items[#items + 1] = {
                    type = "rect", x = x, y = y, w = fill_dx + 1, h = h - y,
                    color = area_color, width = 1,
                    fill = true, fill_color = area_color, fill_opacity = 20,
                }
            end
        end

        -- 曲线：每 4 px 一段折线，等效把 48 个样本重采样成约 75 个节点
        local dx = opts.dx or 4
        local px, py = 0, sample(0)
        for x = dx, w - 1, dx do
            local y = sample(x)
            items[#items + 1] = {
                type = "line", x1 = px, y1 = py, x2 = x, y2 = y,
                color = color, width = 2, round_start = true, round_end = true,
            }
            px, py = x, y
        end
        if px < w - 1 then
            local y = sample(w - 1)
            items[#items + 1] = {
                type = "line", x1 = px, y1 = py, x2 = w - 1, y2 = y,
                color = color, width = 2, round_start = true, round_end = true,
            }
        end

        local ly = sample(w - 1)
        items[#items + 1] = {
            type = "circle", cx = w - 2, cy = ly, r = 6,
            color = color, width = 1, opacity = 90, fill = true, fill_color = color, fill_opacity = 40,
        }
        items[#items + 1] = {
            type = "circle", cx = w - 2, cy = ly, r = 3,
            color = 0xFFFFFF, width = 1, fill = true, fill_color = 0xFFFFFF,
        }
    end
    return items
end

function M.spark_items(w, h, hist, color, vmin, vmax)
    local items = {}
    local n = #hist
    if n < 2 then return items end
    if not vmax or vmax - vmin < 0.000001 then
        vmin, vmax = hist[1], hist[1]
        for i = 2, n do
            if hist[i] < vmin then vmin = hist[i] end
            if hist[i] > vmax then vmax = hist[i] end
        end
        if vmax - vmin < 0.000001 then vmax = vmin + 0.000001 end
    end
    local ys = {}
    for i = 1, n do
        ys[i] = math.floor(h - 2 - clamp01((hist[i] - vmin) / (vmax - vmin)) * (h - 4))
    end
    local sample = make_sampler(ys, n, w, h)
    local dx = math.max(2, math.floor(w / 40))
    local px, py = 0, sample(0)
    for x = dx, w - 1, dx do
        local y = sample(x)
        items[#items + 1] = {
            type = "line", x1 = px, y1 = py, x2 = x, y2 = y,
            color = color, width = 1, round_start = true, round_end = true,
        }
        px, py = x, y
    end
    if px < w - 1 then
        items[#items + 1] = {
            type = "line", x1 = px, y1 = py, x2 = w - 1, y2 = sample(w - 1),
            color = color, width = 1, round_start = true, round_end = true,
        }
    end
    return items
end

-- 圆环表（速度 / 载客率）
function M.ring_items(size, pct, color, track, width)
    local cx = math.floor(size / 2)
    local r = math.floor(size / 2 - 5)
    width = width or 6
    track = track or C.panel3
    local items = {
        { type = "arc", cx = cx, cy = cx, r = r, start_angle = 0, end_angle = 359,
          color = track, width = width, opacity = 255 },
    }
    pct = clamp01(pct or 0)
    if pct > 0.01 then
        items[#items + 1] = {
            type = "arc", cx = cx, cy = cx, r = r,
            start_angle = -90, end_angle = math.floor(-90 + 359.9 * pct),
            color = color, width = width, rounded = true,
        }
    end
    return items
end

-- ===================== 线性图标 =====================
local function circle(items, cx, cy, r, color, fill, opa, width)
    items[#items + 1] = {
        type = "circle", cx = math.floor(cx), cy = math.floor(cy), r = math.max(1, math.floor(r)),
        color = color, width = width or 2, opacity = opa or 255,
        fill = fill and true or false, fill_color = color, fill_opacity = (fill and 255 or 0),
    }
end

local function line(items, x1, y1, x2, y2, color, width)
    items[#items + 1] = {
        type = "line", x1 = math.floor(x1), y1 = math.floor(y1),
        x2 = math.floor(x2), y2 = math.floor(y2), color = color, width = width or 2,
        round_start = true, round_end = true,
    }
end

local function arc(items, cx, cy, r, a1, a2, color, width)
    items[#items + 1] = {
        type = "arc", cx = math.floor(cx), cy = math.floor(cy), r = math.max(1, math.floor(r)),
        start_angle = a1, end_angle = a2, color = color, width = width or 2, rounded = true,
    }
end

local function rect(items, x, y, w, h, color, radius, fill, opa)
    items[#items + 1] = {
        type = "rect", x = math.floor(x), y = math.floor(y),
        w = math.max(1, math.floor(w)), h = math.max(1, math.floor(h)),
        radius = math.floor(radius or 0), color = color, width = 2, opacity = opa or 255,
        fill = fill and true or false, fill_color = color, fill_opacity = (fill and 255 or 0),
    }
end

-- s 为图标外框边长，坐标 0..s
function M.icon_items(kind, s, color)
    local items = {}
    local c = color or C.ink
    local mid = s / 2

    if kind == "peak" then
        line(items, s * 0.10, s * 0.80, s * 0.40, s * 0.28, c, 2)
        line(items, s * 0.40, s * 0.28, s * 0.62, s * 0.62, c, 2)
        line(items, s * 0.62, s * 0.62, s * 0.78, s * 0.42, c, 2)
        line(items, s * 0.78, s * 0.42, s * 0.92, s * 0.80, c, 2)
        line(items, s * 0.10, s * 0.80, s * 0.92, s * 0.80, c, 2)

    elseif kind == "back" then
        line(items, s * 0.58, s * 0.22, s * 0.32, mid, c, 2)
        line(items, s * 0.32, mid, s * 0.58, s * 0.78, c, 2)

    elseif kind == "gear" then
        circle(items, mid, mid, s * 0.30, c, false, 255, 2)
        circle(items, mid, mid, s * 0.10, c, false, 255, 2)
        for i = 0, 5 do
            local a = math.pi * 2 * i / 6 - math.pi / 2
            line(items, mid + math.cos(a) * s * 0.32, mid + math.sin(a) * s * 0.32,
                mid + math.cos(a) * s * 0.44, mid + math.sin(a) * s * 0.44, c, 3)
        end

    elseif kind == "drive" then
        -- 主驱动：电机箱 + 绳轮
        rect(items, s * 0.08, s * 0.42, s * 0.44, s * 0.36, c, 2)
        circle(items, s * 0.68, s * 0.60, s * 0.24, c, false, 255, 2)
        circle(items, s * 0.68, s * 0.60, s * 0.05, c, true)
        line(items, s * 0.52, s * 0.60, s * 0.56, s * 0.60, c, 2)

    elseif kind == "motor" then
        -- 备用电机：闪电
        line(items, s * 0.60, s * 0.10, s * 0.30, s * 0.54, c, 2)
        line(items, s * 0.30, s * 0.54, s * 0.52, s * 0.54, c, 2)
        line(items, s * 0.52, s * 0.54, s * 0.42, s * 0.90, c, 2)
        line(items, s * 0.42, s * 0.90, s * 0.72, s * 0.44, c, 2)
        line(items, s * 0.72, s * 0.44, s * 0.50, s * 0.44, c, 2)
        line(items, s * 0.50, s * 0.44, s * 0.60, s * 0.10, c, 2)

    elseif kind == "gun" then
        -- 造雪机：炮筒 + 支架 + 雪雾
        line(items, s * 0.14, s * 0.52, s * 0.62, s * 0.30, c, 3)
        arc(items, s * 0.62, s * 0.30, s * 0.10, 200, 20, c, 2)
        line(items, s * 0.30, s * 0.86, s * 0.34, s * 0.48, c, 2)
        line(items, s * 0.44, s * 0.86, s * 0.38, s * 0.46, c, 2)
        circle(items, s * 0.80, s * 0.20, s * 0.05, c, false, 220, 1)
        circle(items, s * 0.90, s * 0.34, s * 0.04, c, false, 160, 1)

    elseif kind == "heater" then
        -- 除冰加热：波浪热流
        for i = 0, 2 do
            local x = s * (0.26 + i * 0.24)
            line(items, x, s * 0.80, x, s * 0.56, c, 2)
            line(items, x, s * 0.56, x - s * 0.06, s * 0.42, c, 2)
            line(items, x - s * 0.06, s * 0.42, x + s * 0.06, s * 0.30, c, 2)
        end
        line(items, s * 0.14, s * 0.86, s * 0.86, s * 0.86, c, 2)

    elseif kind == "light" then
        -- 照明：灯泡
        arc(items, mid, s * 0.46, s * 0.26, 150, 390, c, 2)
        line(items, s * 0.40, s * 0.70, s * 0.40, s * 0.80, c, 2)
        line(items, s * 0.60, s * 0.70, s * 0.60, s * 0.80, c, 2)
        line(items, s * 0.42, s * 0.84, s * 0.58, s * 0.84, c, 2)
        line(items, mid, s * 0.06, mid, s * 0.14, c, 2)

    elseif kind == "speaker" then
        rect(items, s * 0.14, s * 0.26, s * 0.22, s * 0.48, c, 2)
        line(items, s * 0.36, s * 0.42, s * 0.56, s * 0.18, c, 2)
        line(items, s * 0.56, s * 0.18, s * 0.56, s * 0.82, c, 2)
        line(items, s * 0.56, s * 0.82, s * 0.36, s * 0.58, c, 2)
        arc(items, s * 0.60, mid, s * 0.20, -50, 50, c, 2)
        arc(items, s * 0.62, mid, s * 0.32, -50, 50, c, 2)

    elseif kind == "sun" then
        circle(items, mid, mid, s * 0.20, c, false, 255, 2)
        for i = 0, 7 do
            local a = math.pi * 2 * i / 8
            line(items, mid + math.cos(a) * s * 0.28, mid + math.sin(a) * s * 0.28,
                mid + math.cos(a) * s * 0.40, mid + math.sin(a) * s * 0.40, c, 2)
        end

    elseif kind == "moon" then
        arc(items, s * 0.46, mid, s * 0.30, 40, 320, c, 2)
        arc(items, s * 0.58, mid - s * 0.06, s * 0.24, 120, 250, c, 2)

    elseif kind == "cloud" then
        arc(items, s * 0.36, s * 0.56, s * 0.18, 180, 360, c, 2)
        arc(items, s * 0.56, s * 0.50, s * 0.22, 200, 360, c, 2)
        arc(items, s * 0.74, s * 0.58, s * 0.15, 270, 90, c, 2)
        line(items, s * 0.20, s * 0.74, s * 0.80, s * 0.74, c, 2)

    elseif kind == "wind" then
        line(items, s * 0.12, s * 0.34, s * 0.70, s * 0.34, c, 2)
        arc(items, s * 0.70, s * 0.26, s * 0.10, 90, 270, c, 2)
        line(items, s * 0.12, s * 0.54, s * 0.58, s * 0.54, c, 2)
        arc(items, s * 0.58, s * 0.62, s * 0.10, 270, 90, c, 2)
        line(items, s * 0.12, s * 0.74, s * 0.44, s * 0.74, c, 2)

    elseif kind == "flake" then
        for i = 0, 2 do
            local a = math.pi * i / 3
            local dx, dy = math.cos(a) * s * 0.34, math.sin(a) * s * 0.34
            line(items, mid - dx, mid - dy, mid + dx, mid + dy, c, 2)
            line(items, mid + dx * 0.55, mid + dy * 0.55, mid + dx * 0.55 - dy * 0.22, mid + dy * 0.55 + dx * 0.22, c, 2)
        end

    elseif kind == "thermo" then
        rect(items, s * 0.40, s * 0.12, s * 0.20, s * 0.50, c, 6)
        circle(items, mid, s * 0.76, s * 0.16, c, true)
        line(items, mid, s * 0.34, mid, s * 0.66, c, 2)

    elseif kind == "eye" then
        arc(items, mid, s * 0.74, s * 0.36, 210, 330, c, 2)
        arc(items, mid, s * 0.18, s * 0.36, 30, 150, c, 2)
        circle(items, mid, mid, s * 0.10, c, true)

    elseif kind == "clock" then
        circle(items, mid, mid, s * 0.36, c, false, 255, 2)
        line(items, mid, mid, mid, s * 0.32, c, 2)
        line(items, mid, mid, s * 0.66, mid, c, 2)

    elseif kind == "check" then
        line(items, s * 0.20, s * 0.52, s * 0.42, s * 0.74, c, 3)
        line(items, s * 0.42, s * 0.74, s * 0.80, s * 0.26, c, 3)

    elseif kind == "warn" then
        line(items, mid, s * 0.16, s * 0.16, s * 0.82, c, 2)
        line(items, s * 0.16, s * 0.82, s * 0.84, s * 0.82, c, 2)
        line(items, s * 0.84, s * 0.82, mid, s * 0.16, c, 2)
        line(items, mid, s * 0.40, mid, s * 0.60, c, 2)
        circle(items, mid, s * 0.71, 1, c, true)

    elseif kind == "arrow" then
        line(items, s * 0.20, mid, s * 0.76, mid, c, 2)
        line(items, s * 0.76, mid, s * 0.56, mid - s * 0.18, c, 2)
        line(items, s * 0.76, mid, s * 0.56, mid + s * 0.18, c, 2)

    elseif kind == "gauge" then
        arc(items, mid, s * 0.74, s * 0.38, 200, 340, c, 2)
        line(items, mid, s * 0.74, mid + s * 0.22, s * 0.42, c, 2)
        circle(items, mid, s * 0.74, 2, c, true)

    elseif kind == "groom" then
        -- 压雪车：车身 + 履带 + 雪铲
        rect(items, s * 0.22, s * 0.34, s * 0.44, s * 0.30, c, 2)
        line(items, s * 0.14, s * 0.72, s * 0.78, s * 0.72, c, 2)
        circle(items, s * 0.34, s * 0.72, s * 0.09, c, false, 255, 2)
        circle(items, s * 0.60, s * 0.72, s * 0.09, c, false, 255, 2)
        line(items, s * 0.66, s * 0.44, s * 0.86, s * 0.38, c, 2)
        line(items, s * 0.86, s * 0.38, s * 0.90, s * 0.56, c, 2)

    elseif kind == "people" then
        circle(items, s * 0.36, s * 0.32, s * 0.10, c, false, 255, 2)
        arc(items, s * 0.36, s * 0.86, s * 0.24, 200, 340, c, 2)
        circle(items, s * 0.68, s * 0.36, s * 0.08, c, false, 255, 2)
        arc(items, s * 0.68, s * 0.86, s * 0.20, 200, 340, c, 2)

    elseif kind == "pause" then
        rect(items, s * 0.28, s * 0.20, s * 0.14, s * 0.60, c, 2, true)
        rect(items, s * 0.58, s * 0.20, s * 0.14, s * 0.60, c, 2, true)

    elseif kind == "play" then
        line(items, s * 0.32, s * 0.20, s * 0.32, s * 0.80, c, 2)
        line(items, s * 0.32, s * 0.20, s * 0.78, mid, c, 2)
        line(items, s * 0.78, mid, s * 0.32, s * 0.80, c, 2)
    end

    return items
end

-- 图标绘制：返回 shape，可 set(kind, color) 重生
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

return M


