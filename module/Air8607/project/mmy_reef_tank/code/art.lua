--[[
@module  art
@summary ReefOS 图形素材库：水体、珊瑚、鱼群、波形、图标（全部用 airui.shape 图元拼绘）
@version 1.0
@date    2026.10.27
]]
local theme = require "theme"
local C = theme.C

local M = {}

local function clamp01(t)
    if t < 0 then return 0 elseif t > 1 then return 1 end
    return t
end

-- ===================== 光谱 -> 水色 =====================
-- 返回 surface（水面亮色）, glow（灯光晕色）
function M.color_from_spectrum(blue, white, uv)
    local b, w, u = blue or 0, white or 0, uv or 0
    local lit = theme.blend({
        { 0x2E7BFF, b },
        { 0xE6FBFF, w },
        { 0x9A6BFF, u * 0.75 },
        { 0x061726, 34 },
    })
    local strength = clamp01((b + w + u * 0.6) / 180)
    local surface = theme.mix(0x061523, lit, 0.22 + 0.48 * strength)
    local glow = theme.mix(0x0A2436, lit, 0.30 + 0.45 * strength)
    return surface, glow
end

-- ===================== 水体 =====================
-- 纵向渐变水体，返回 {set=function(surface, deep)} 便于光谱联动
function M.water(parent, x, y, w, h, surface, deep, steps)
    steps = steps or 14
    deep = deep or 0x03101C
    local strips = {}
    local sh = math.floor(h / steps)
    for i = 1, steps do
        local t = (i - 1) / (steps - 1)
        local hh = sh
        if i == steps then hh = h - sh * (steps - 1) end
        if hh > 0 then
            strips[i] = theme.box(parent, x, y + (i - 1) * sh, w, hh, 0x000000, 0)
        end
    end
    local obj = {
        strips = strips,
        set = function(sf, dp)
            dp = dp or deep
            for i, s in ipairs(strips) do
                local t = (i - 1) / (steps - 1)
                s:set_color(theme.mix(sf, dp, t * t))
            end
        end,
    }
    obj.set(surface, deep)
    return obj
end

-- 斜射光柱
function M.rays_items(w, h, color, opacity)
    local seeds = {
        { 0.08, -0.02, 0.30, 0.80 },
        { 0.30, -0.04, 0.44, 0.62 },
        { 0.55, -0.02, 0.48, 0.86 },
        { 0.74, -0.04, 0.90, 0.58 },
        { 0.92, -0.02, 0.78, 0.72 },
    }
    local items = {}
    for i, s in ipairs(seeds) do
        items[#items + 1] = {
            type = "line",
            x1 = math.floor(s[1] * w), y1 = math.floor(s[2] * h),
            x2 = math.floor(s[3] * w), y2 = math.floor(s[4] * h),
            color = color, width = 22 - i * 2, opacity = opacity or 9,
        }
    end
    return items
end

function M.rays(parent, x, y, w, h, color, opacity)
    return theme.shape(parent, x, y, w, h, M.rays_items(w, h, color, opacity))
end

-- ===================== 沙床 / 岩石 =====================
function M.sand(parent, x, y, w, h, sand_color)
    local sand = sand_color or C.sand
    local items = {
        { type = "ellipse", cx = math.floor(w * 0.50), cy = 54, rx = math.floor(w * 0.60), ry = 46,
          color = sand, fill = true, fill_color = sand, width = 1 },
        { type = "ellipse", cx = math.floor(w * 0.22), cy = 62, rx = math.floor(w * 0.34), ry = 34,
          color = 0x24435A, fill = true, fill_color = 0x24435A, fill_opacity = 120, width = 1 },
        { type = "ellipse", cx = math.floor(w * 0.82), cy = 66, rx = math.floor(w * 0.30), ry = 30,
          color = 0x152C3D, fill = true, fill_color = 0x152C3D, fill_opacity = 170, width = 1 },
    }
    local seeds = {
        { 0.12, 0.42, 3 }, { 0.20, 0.58, 2 }, { 0.33, 0.70, 4 }, { 0.46, 0.56, 2 },
        { 0.58, 0.74, 3 }, { 0.70, 0.60, 2 }, { 0.80, 0.76, 4 }, { 0.90, 0.52, 2 },
        { 0.26, 0.86, 2 }, { 0.64, 0.88, 3 },
    }
    for _, s in ipairs(seeds) do
        items[#items + 1] = {
            type = "circle", cx = math.floor(w * s[1]), cy = math.floor(h * s[2]), r = s[3],
            color = 0x35566E, fill = true, fill_color = 0x35566E, fill_opacity = 150, width = 1,
        }
    end
    return theme.shape(parent, x, y, w, h, items)
end

-- ===================== 珊瑚 =====================
local function limb(items, x1, y1, x2, y2, w, color, opa)
    items[#items + 1] = {
        type = "line", x1 = math.floor(x1), y1 = math.floor(y1), x2 = math.floor(x2), y2 = math.floor(y2),
        color = color, width = math.max(1, math.floor(w)), opacity = opa or 255,
        round_start = true, round_end = true,
    }
end

-- 分枝珊瑚
function M.branch_items(cx, by, s, color)
    local items = {}
    limb(items, cx, by, cx - 4 * s, by - 22 * s, 9 * s, color)
    limb(items, cx - 3 * s, by - 18 * s, cx - 26 * s, by - 42 * s, 7 * s, color)
    limb(items, cx - 26 * s, by - 42 * s, cx - 34 * s, by - 56 * s, 6 * s, color)
    limb(items, cx - 3 * s, by - 24 * s, cx + 15 * s, by - 48 * s, 7 * s, color)
    limb(items, cx + 15 * s, by - 48 * s, cx + 27 * s, by - 62 * s, 5 * s, color)
    limb(items, cx + 2 * s, by - 32 * s, cx + 2 * s, by - 66 * s, 6 * s, color)
    limb(items, cx + 2 * s, by - 66 * s, cx - 9 * s, by - 80 * s, 5 * s, color)
    limb(items, cx + 2 * s, by - 66 * s, cx + 13 * s, by - 78 * s, 5 * s, color)
    for _, p in ipairs({ { -34, -56 }, { 27, -62 }, { -9, -80 }, { 13, -78 }, { -26, -42 } }) do
        items[#items + 1] = {
            type = "circle", cx = math.floor(cx + p[1] * s), cy = math.floor(by + p[2] * s),
            r = math.max(2, math.floor(5 * s)), color = color, fill = true, fill_color = color, width = 1,
        }
    end
    return items
end

-- 海扇（网状软珊瑚）
function M.fan_items(cx, by, r, color)
    local items = {}
    limb(items, cx, by, cx, by - r * 0.55, 5, color)
    for i = 0, 6 do
        local a = -math.pi * 0.86 + i * (math.pi * 0.72) / 6
        local len = r * (0.72 + 0.28 * math.cos(i * 1.1))
        limb(items, cx, by - r * 0.5, cx + math.cos(a) * len, by - r * 0.5 + math.sin(a) * len, 3, color, 210)
    end
    for i = 0, 10 do
        local a = -math.pi * 0.82 + i * (math.pi * 0.62) / 10
        local len = r * 0.62
        items[#items + 1] = {
            type = "circle", cx = math.floor(cx + math.cos(a) * len),
            cy = math.floor(by - r * 0.5 + math.sin(a) * len), r = 2,
            color = color, fill = true, fill_color = color, fill_opacity = 200, width = 1,
        }
    end
    return items
end

-- 海葵（触手随 phase 摆动）
function M.anemone_items(cx, by, r, color, phase)
    local items = {}
    local n = 13
    for i = 1, n do
        local base = -math.pi * 0.5 + (i - (n + 1) / 2) * 0.155
        local a = base + math.sin((phase or 0) + i * 0.8) * 0.09
        local len = r * (0.80 + 0.30 * math.abs(math.sin(i * 1.7)))
        local x0 = cx + math.cos(base) * 7
        local y0 = by - 4
        local x2 = x0 + math.cos(a) * len
        local y2 = y0 + math.sin(a) * len
        limb(items, x0, y0, x2, y2, 4, color, 220)
        items[#items + 1] = {
            type = "circle", cx = math.floor(x2), cy = math.floor(y2), r = 3,
            color = color, fill = true, fill_color = theme.mix(color, 0xFFFFFF, 0.4), width = 1,
        }
    end
    items[#items + 1] = {
        type = "ellipse", cx = cx, cy = by, rx = math.floor(r * 0.5), ry = math.floor(r * 0.26),
        color = color, fill = true, fill_color = theme.mix(color, 0x000000, 0.35), width = 1,
    }
    return items
end

-- 海草 / 鞭珊瑚
function M.weed_items(cx, base_y, h, color, phase, blades)
    local items = {}
    blades = blades or 4
    for b = 1, blades do
        local off = (b - (blades + 1) / 2) * 7
        local hh = h * (0.72 + 0.28 * math.abs(math.sin(b * 2.1)))
        local x, y = cx + off, base_y
        local segs = 4
        for i = 1, segs do
            local t = i / segs
            local sway = math.sin((phase or 0) + t * 2.2 + b) * hh * 0.18 * t
            local nx = cx + off + sway
            local ny = base_y - hh * t
            limb(items, x, y, nx, ny, 4 - t, color, 230)
            x, y = nx, ny
        end
    end
    return items
end

-- ===================== 鱼 =====================
-- dir = 1 朝右，-1 朝左
function M.fish_items(w, h, color, dir, flip_tail)
    local items = {}
    local cx, cy = w * 0.44, h * 0.5
    local body_rx, body_ry = w * 0.26, h * 0.24
    local tail_x = cx + body_rx * 0.86
    local tail_tip = tail_x + w * 0.16
    local belly = theme.mix(color, 0xFFFFFF, 0.35)
    local fin = theme.mix(color, 0x000000, 0.28)

    -- 背鳍
    limb(items, cx - body_rx * 0.5, cy - body_ry * 0.75, cx + body_rx * 0.15, cy - body_ry * 1.45, 3, fin)
    -- 尾鳍
    local tw = flip_tail and -1 or 1
    limb(items, tail_x, cy, tail_tip, cy - h * 0.20 * tw, 4, fin)
    limb(items, tail_x, cy, tail_tip, cy + h * 0.20 * tw, 4, fin)
    limb(items, tail_tip, cy - h * 0.20 * tw, tail_tip, cy + h * 0.20 * tw, 3, fin)
    -- 身体
    items[#items + 1] = {
        type = "ellipse", cx = math.floor(cx), cy = math.floor(cy),
        rx = math.floor(body_rx), ry = math.floor(body_ry),
        color = color, fill = true, fill_color = color, width = 1,
    }
    -- 腹部高光
    items[#items + 1] = {
        type = "ellipse", cx = math.floor(cx), cy = math.floor(cy + body_ry * 0.34),
        rx = math.floor(body_rx * 0.82), ry = math.floor(body_ry * 0.46),
        color = belly, fill = true, fill_color = belly, fill_opacity = 110, width = 1,
    }
    -- 眼睛
    items[#items + 1] = {
        type = "circle", cx = math.floor(cx + body_rx * 0.52), cy = math.floor(cy - body_ry * 0.18), r = 2,
        color = 0x06101A, fill = true, fill_color = 0x06101A, width = 1,
    }
    if dir < 0 then
        for _, it in ipairs(items) do
            if it.type == "line" then
                it.x1, it.x2 = w - it.x1, w - it.x2
            elseif it.cx then
                it.cx = w - it.cx
            end
        end
    end
    return items
end

function M.fish(parent, x, y, w, h, color, dir, flip_tail)
    return theme.shape(parent, x, y, w, h, M.fish_items(w, h, color, dir, flip_tail))
end

-- ===================== 气泡 / 水面 =====================
function M.bubble(parent, x, y, r, color)
    local c = color or 0xBFE9FF
    local sz = r * 2 + 2
    return theme.shape(parent, x, y, sz, sz, {
        { type = "circle", cx = r + 1, cy = r + 1, r = r, color = c, width = 1, opacity = 160 },
        { type = "circle", cx = r + 1, cy = r + 1, r = math.max(1, r - 2),
          color = c, width = 1, opacity = 70, fill = true, fill_color = c, fill_opacity = 26 },
        { type = "circle", cx = r, cy = math.max(1, r - 1), r = 1, color = 0xFFFFFF,
          fill = true, fill_color = 0xFFFFFF, fill_opacity = 150, width = 1 },
    })
end

-- 水面波光（随时间重建）
function M.wave_items(w, phase, color)
    local items = {}
    local segs = 22
    local step = w / segs
    local prev_x, prev_y
    for i = 0, segs do
        local x = i * step
        local y = 8 + math.sin(phase + i * 0.55) * 4 + math.sin(phase * 1.7 + i * 0.23) * 2
        if prev_x then
            items[#items + 1] = {
                type = "line", x1 = math.floor(prev_x), y1 = math.floor(prev_y),
                x2 = math.floor(x), y2 = math.floor(y), color = color, width = 2, opacity = 90,
                round_start = true, round_end = true,
            }
        end
        prev_x, prev_y = x, y
    end
    return items
end

-- ===================== 波形图 =====================
-- opts: color, min, max, lo, hi, band(bool), grid(int), dash(bool)
function M.waveform_items(w, h, hist, opts)
    opts = opts or {}
    local color = opts.color or C.cyan
    local vmin = opts.min or 0
    local vmax = opts.max or 1
    if vmax - vmin < 0.000001 then vmax = vmin + 1 end
    local pad = 10
    local ih = h - pad * 2

    local function vy(v)
        local t = (v - vmin) / (vmax - vmin)
        t = clamp01(t)
        return math.floor(pad + ih - t * ih)
    end

    local items = {}
    -- 网格
    local grid = opts.grid or 4
    for i = 0, grid do
        local y = math.floor(pad + ih * i / grid)
        items[#items + 1] = { type = "line", x1 = 0, y1 = y, x2 = w, y2 = y,
            color = C.line, width = 1, opacity = 120,
            dash_width = (opts.dash and 4 or 0), dash_gap = (opts.dash and 4 or 0) }
    end
    -- 正常区间
    if opts.band and opts.lo and opts.hi then
        local y1, y2 = vy(opts.hi), vy(opts.lo)
        if y2 > y1 then
            items[#items + 1] = { type = "rect", x = 0, y = y1, w = w, h = y2 - y1,
                color = C.green, width = 1, opacity = 20,
                fill = true, fill_color = C.green, fill_opacity = 16 }
        end
    end
    local n = #hist
    if n >= 2 then
        local step = w / (n - 1)
        -- 面积
        local area_color = opts.area_color or color
        for i = 1, n do
            local x = (i - 1) * step
            local y = vy(hist[i])
            if h - y > 2 then
                items[#items + 1] = { type = "rect", x = math.floor(x - 2), y = y,
                    w = 5, h = h - y, color = area_color, width = 0, opacity = 0,
                    fill = true, fill_color = area_color, fill_opacity = 26 }
            end
        end
        -- 折线
        for i = 2, n do
            local x1 = (i - 2) * step
            local x2 = (i - 1) * step
            items[#items + 1] = { type = "line",
                x1 = math.floor(x1), y1 = vy(hist[i - 1]),
                x2 = math.floor(x2), y2 = vy(hist[i]),
                color = color, width = 2, round_start = true, round_end = true }
        end
        -- 末点光点
        local lx = w
        local ly = vy(hist[n])
        items[#items + 1] = { type = "circle", cx = lx - 1, cy = ly, r = 7,
            color = color, width = 1, opacity = 90, fill = true, fill_color = color, fill_opacity = 40 }
        items[#items + 1] = { type = "circle", cx = lx - 1, cy = ly, r = 3,
            color = 0xFFFFFF, width = 1, fill = true, fill_color = 0xFFFFFF }
    end
    return items
end

-- 迷你趋势线
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
    local function vy(v)
        return math.floor(h - 2 - clamp01((v - vmin) / (vmax - vmin)) * (h - 4))
    end
    local step = w / (n - 1)
    for i = 2, n do
        items[#items + 1] = { type = "line",
            x1 = math.floor((i - 2) * step), y1 = vy(hist[i - 1]),
            x2 = math.floor((i - 1) * step), y2 = vy(hist[i]),
            color = color, width = 1, round_start = true, round_end = true }
    end
    return items
end

-- 圆环进度（用于光照/水位等）
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
        items[#items + 1] = { type = "arc", cx = cx, cy = cx, r = r,
            start_angle = -90, end_angle = math.floor(-90 + 359.9 * pct),
            color = color, width = width, rounded = true }
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

local function ellipse(items, cx, cy, rx, ry, color, fill, opa)
    items[#items + 1] = {
        type = "ellipse", cx = math.floor(cx), cy = math.floor(cy),
        rx = math.max(1, math.floor(rx)), ry = math.max(1, math.floor(ry)),
        color = color, width = 2, opacity = opa or 255,
        fill = fill and true or false, fill_color = color, fill_opacity = (fill and 255 or 0),
    }
end

local function arc(items, cx, cy, r, a1, a2, color, width, rounded)
    items[#items + 1] = {
        type = "arc", cx = math.floor(cx), cy = math.floor(cy), r = math.max(1, math.floor(r)),
        start_angle = a1, end_angle = a2, color = color, width = width or 2, rounded = rounded ~= false,
    }
end

-- s 为图标外框边长，返回图元列表（坐标 0..s）
function M.icon_items(kind, s, color)
    local items = {}
    local c = color or C.ink
    local mid = s / 2
    if kind == "pump" then
        circle(items, mid, mid, s * 0.38, c, false, 255, 2)
        circle(items, mid, mid, s * 0.10, c, true)
        for i = 0, 2 do
            local a = -math.pi / 2 + i * math.pi * 2 / 3
            items[#items + 1] = { type = "line",
                x1 = math.floor(mid + math.cos(a) * s * 0.13), y1 = math.floor(mid + math.sin(a) * s * 0.13),
                x2 = math.floor(mid + math.cos(a) * s * 0.30), y2 = math.floor(mid + math.sin(a) * s * 0.30),
                color = c, width = 2, round_start = true, round_end = true }
        end
    elseif kind == "wave" then
        arc(items, mid, mid - s * 0.10, s * 0.30, 200, 340, c, 2)
        arc(items, mid, mid + s * 0.14, s * 0.30, 200, 340, c, 2)
        arc(items, mid, mid + s * 0.38, s * 0.30, 200, 340, c, 2)
    elseif kind == "skimmer" then
        items[#items + 1] = { type = "line", x1 = math.floor(s * 0.30), y1 = math.floor(s * 0.44),
            x2 = math.floor(s * 0.70), y2 = math.floor(s * 0.44), color = c, width = 2 }
        items[#items + 1] = { type = "line", x1 = math.floor(s * 0.30), y1 = math.floor(s * 0.44),
            x2 = math.floor(s * 0.34), y2 = math.floor(s * 0.92), color = c, width = 2 }
        items[#items + 1] = { type = "line", x1 = math.floor(s * 0.70), y1 = math.floor(s * 0.44),
            x2 = math.floor(s * 0.66), y2 = math.floor(s * 0.92), color = c, width = 2 }
        items[#items + 1] = { type = "line", x1 = math.floor(s * 0.34), y1 = math.floor(s * 0.92),
            x2 = math.floor(s * 0.66), y2 = math.floor(s * 0.92), color = c, width = 2 }
        circle(items, mid, s * 0.26, s * 0.10, c, false, 255, 2)
        circle(items, s * 0.30, s * 0.10, s * 0.05, c, true)
        circle(items, s * 0.68, s * 0.14, s * 0.04, c, true)
    elseif kind == "heater" then
        items[#items + 1] = { type = "rect", x = math.floor(s * 0.36), y = math.floor(s * 0.16),
            w = math.floor(s * 0.28), h = math.floor(s * 0.58), radius = math.floor(s * 0.12),
            color = c, width = 2, opacity = 255 }
        items[#items + 1] = { type = "line", x1 = math.floor(s * 0.42), y1 = math.floor(s * 0.36),
            x2 = math.floor(s * 0.58), y2 = math.floor(s * 0.36), color = c, width = 2 }
        items[#items + 1] = { type = "line", x1 = math.floor(s * 0.42), y1 = math.floor(s * 0.54),
            x2 = math.floor(s * 0.58), y2 = math.floor(s * 0.54), color = c, width = 2 }
        items[#items + 1] = { type = "line", x1 = mid, y1 = math.floor(s * 0.74),
            x2 = mid, y2 = math.floor(s * 0.92), color = c, width = 2 }
    elseif kind == "chiller" then
        items[#items + 1] = { type = "rect", x = math.floor(s * 0.20), y = math.floor(s * 0.26),
            w = math.floor(s * 0.60), h = math.floor(s * 0.48), radius = 3, color = c, width = 2 }
        for i = 0, 2 do
            items[#items + 1] = { type = "line",
                x1 = math.floor(s * 0.30 + i * s * 0.13), y1 = math.floor(s * 0.62),
                x2 = math.floor(s * 0.38 + i * s * 0.13), y2 = math.floor(s * 0.38),
                color = c, width = 2, round_start = true, round_end = true }
        end
    elseif kind == "uv" then
        circle(items, mid, mid, s * 0.30, c, false, 255, 2)
        circle(items, mid, mid, s * 0.10, c, true)
        for i = 0, 3 do
            local a = -math.pi / 4 + i * math.pi / 2
            items[#items + 1] = { type = "line",
                x1 = math.floor(mid + math.cos(a) * s * 0.38), y1 = math.floor(mid + math.sin(a) * s * 0.38),
                x2 = math.floor(mid + math.cos(a) * s * 0.48), y2 = math.floor(mid + math.sin(a) * s * 0.48),
                color = c, width = 2, round_start = true, round_end = true }
        end
    elseif kind == "feed" then
        circle(items, mid, mid + s * 0.06, s * 0.30, c, false, 255, 2)
        circle(items, mid - s * 0.10, mid - s * 0.02, s * 0.05, c, true)
        circle(items, mid + s * 0.10, mid + s * 0.04, s * 0.04, c, true)
        circle(items, mid + s * 0.02, mid + s * 0.16, s * 0.035, c, true)
    elseif kind == "drop" then
        items[#items + 1] = { type = "line", x1 = mid, y1 = math.floor(s * 0.12),
            x2 = math.floor(s * 0.28), y2 = math.floor(s * 0.56), color = c, width = 2 }
        items[#items + 1] = { type = "line", x1 = mid, y1 = math.floor(s * 0.12),
            x2 = math.floor(s * 0.72), y2 = math.floor(s * 0.56), color = c, width = 2 }
        arc(items, mid, mid + s * 0.06, s * 0.30, 20, 340, c, 2)
    elseif kind == "gear" then
        circle(items, mid, mid, s * 0.22, c, false, 255, 2)
        for i = 0, 7 do
            local a = i * math.pi / 4
            items[#items + 1] = { type = "line",
                x1 = math.floor(mid + math.cos(a) * s * 0.28), y1 = math.floor(mid + math.sin(a) * s * 0.28),
                x2 = math.floor(mid + math.cos(a) * s * 0.44), y2 = math.floor(mid + math.sin(a) * s * 0.44),
                color = c, width = 2, round_start = true, round_end = true }
        end
    elseif kind == "back" then
        items[#items + 1] = { type = "line", x1 = math.floor(s * 0.62), y1 = math.floor(s * 0.20),
            x2 = math.floor(s * 0.34), y2 = math.floor(s * 0.50), color = c, width = 3,
            round_start = true, round_end = true }
        items[#items + 1] = { type = "line", x1 = math.floor(s * 0.34), y1 = math.floor(s * 0.50),
            x2 = math.floor(s * 0.62), y2 = math.floor(s * 0.80), color = c, width = 3,
            round_start = true, round_end = true }
    elseif kind == "arrow" then
        items[#items + 1] = { type = "line", x1 = math.floor(s * 0.34), y1 = math.floor(s * 0.50),
            x2 = math.floor(s * 0.66), y2 = math.floor(s * 0.50), color = c, width = 2,
            round_start = true, round_end = true }
        items[#items + 1] = { type = "line", x1 = math.floor(s * 0.52), y1 = math.floor(s * 0.30),
            x2 = math.floor(s * 0.70), y2 = math.floor(s * 0.50), color = c, width = 2,
            round_start = true, round_end = true }
        items[#items + 1] = { type = "line", x1 = math.floor(s * 0.52), y1 = math.floor(s * 0.70),
            x2 = math.floor(s * 0.70), y2 = math.floor(s * 0.50), color = c, width = 2,
            round_start = true, round_end = true }
    elseif kind == "sun" then
        circle(items, mid, mid, s * 0.20, c, false, 255, 2)
        for i = 0, 7 do
            local a = i * math.pi / 4
            items[#items + 1] = { type = "line",
                x1 = math.floor(mid + math.cos(a) * s * 0.28), y1 = math.floor(mid + math.sin(a) * s * 0.28),
                x2 = math.floor(mid + math.cos(a) * s * 0.44), y2 = math.floor(mid + math.sin(a) * s * 0.44),
                color = c, width = 2, round_start = true, round_end = true }
        end
    elseif kind == "moon" then
        arc(items, mid, mid, s * 0.32, 300, 120, c, 3)
        arc(items, mid - s * 0.10, mid - s * 0.04, s * 0.24, 300, 120, c, 3, false, 0)
    elseif kind == "bolt" then
        items[#items + 1] = { type = "line", x1 = math.floor(s * 0.56), y1 = math.floor(s * 0.10),
            x2 = math.floor(s * 0.32), y2 = math.floor(s * 0.52), color = c, width = 2,
            round_start = true, round_end = true }
        items[#items + 1] = { type = "line", x1 = math.floor(s * 0.32), y1 = math.floor(s * 0.52),
            x2 = math.floor(s * 0.58), y2 = math.floor(s * 0.52), color = c, width = 2,
            round_start = true, round_end = true }
        items[#items + 1] = { type = "line", x1 = math.floor(s * 0.58), y1 = math.floor(s * 0.52),
            x2 = math.floor(s * 0.42), y2 = math.floor(s * 0.90), color = c, width = 2,
            round_start = true, round_end = true }
    elseif kind == "coral" then
        for _, l in ipairs({ { 0.50, 0.92, 0.50, 0.58 }, { 0.50, 0.72, 0.30, 0.46 },
                             { 0.50, 0.66, 0.72, 0.40 }, { 0.30, 0.46, 0.24, 0.28 },
                             { 0.72, 0.40, 0.80, 0.24 } }) do
            items[#items + 1] = { type = "line", x1 = math.floor(s * l[1]), y1 = math.floor(s * l[2]),
                x2 = math.floor(s * l[3]), y2 = math.floor(s * l[4]), color = c, width = 2,
                round_start = true, round_end = true }
        end
        circle(items, s * 0.24, s * 0.26, s * 0.06, c, true)
        circle(items, s * 0.80, s * 0.22, s * 0.06, c, true)
    elseif kind == "check" then
        items[#items + 1] = { type = "line", x1 = math.floor(s * 0.24), y1 = math.floor(s * 0.52),
            x2 = math.floor(s * 0.44), y2 = math.floor(s * 0.72), color = c, width = 2,
            round_start = true, round_end = true }
        items[#items + 1] = { type = "line", x1 = math.floor(s * 0.44), y1 = math.floor(s * 0.72),
            x2 = math.floor(s * 0.78), y2 = math.floor(s * 0.30), color = c, width = 2,
            round_start = true, round_end = true }
    elseif kind == "clock" then
        circle(items, mid, mid, s * 0.38, c, false, 255, 2)
        items[#items + 1] = { type = "line", x1 = mid, y1 = mid,
            x2 = mid, y2 = math.floor(mid - s * 0.20), color = c, width = 2, round_end = true }
        items[#items + 1] = { type = "line", x1 = mid, y1 = mid,
            x2 = math.floor(mid + s * 0.16), y2 = math.floor(mid + s * 0.10), color = c, width = 2, round_end = true }
    else
        circle(items, mid, mid, s * 0.34, c, false, 255, 2)
    end
    return items
end

function M.icon(parent, kind, x, y, s, color)
    return theme.shape(parent, x, y, s, s, M.icon_items(kind, s, color))
end

return M

