--[[
@module  art
@summary AeroDeck 图形素材库：机坪雷达、跑道、飞机、罗盘、波形与线性图标
@version 1.0
@date    2026.11.05
        全部用 airui.shape 的图元（line / rect / circle / ellipse / arc）拼绘，
        不依赖图片资源，方便在小内存设备上直接跑。
]]
local theme = require "theme"
local C = theme.C

local M = {}

local function clamp01(t)
    if t < 0 then return 0 elseif t > 1 then return 1 end
    return t
end

local function rad(deg)
    return deg * math.pi / 180
end

-- ===================== 顶视飞机 =====================
-- 机头朝上，坐标落在 0..s 的正方框内；fill 为 true 时填充机身
function M.plane_items(s, color, fill)
    local cx = s / 2
    local items = {}
    local body = {
        type = "ellipse", cx = math.floor(cx), cy = math.floor(s * 0.50),
        rx = math.max(1, math.floor(s * 0.075)), ry = math.max(2, math.floor(s * 0.36)),
        color = color, width = 1,
        fill = true, fill_color = color, fill_opacity = 255,
    }
    items[#items + 1] = body
    -- 主翼
    items[#items + 1] = {
        type = "line", x1 = math.floor(s * 0.10), y1 = math.floor(s * 0.54),
        x2 = math.floor(s * 0.90), y2 = math.floor(s * 0.54),
        color = color, width = math.max(2, math.floor(s * 0.085)), opacity = 255,
    }
    -- 平尾
    items[#items + 1] = {
        type = "line", x1 = math.floor(s * 0.30), y1 = math.floor(s * 0.84),
        x2 = math.floor(s * 0.70), y2 = math.floor(s * 0.84),
        color = color, width = math.max(1, math.floor(s * 0.055)), opacity = 255,
    }
    if fill then
        items[#items + 1] = {
            type = "circle", cx = math.floor(cx), cy = math.floor(s * 0.14), r = 1,
            color = 0xFFFFFF, fill = true, fill_color = 0xFFFFFF, width = 1,
        }
    end
    return items
end

function M.plane(parent, x, y, s, color)
    return theme.shape(parent, x, y, s, s, M.plane_items(s, color, true))
end

-- ===================== 雷达 =====================
-- 静态底图：同心圆 + 十字 + 方位刻度
function M.radar_bg_items(size, color, ring_color)
    local c = math.floor(size / 2)
    local r = math.floor(size / 2 - 2)
    local items = {
        { type = "circle", cx = c, cy = c, r = r, color = ring_color, width = 1, opacity = 140 },
        { type = "circle", cx = c, cy = c, r = math.floor(r * 0.66), color = ring_color, width = 1, opacity = 90 },
        { type = "circle", cx = c, cy = c, r = math.floor(r * 0.33), color = ring_color, width = 1, opacity = 70 },
        { type = "line", x1 = c - r, y1 = c, x2 = c + r, y2 = c, color = ring_color, width = 1, opacity = 70 },
        { type = "line", x1 = c, y1 = c - r, x2 = c, y2 = c + r, color = ring_color, width = 1, opacity = 70 },
    }
    -- 每 30° 一根短刻度，强化"雷达"观感
    for i = 0, 11 do
        local a = rad(i * 30)
        items[#items + 1] = {
            type = "line",
            x1 = math.floor(c + math.sin(a) * (r - 7)), y1 = math.floor(c - math.cos(a) * (r - 7)),
            x2 = math.floor(c + math.sin(a) * r), y2 = math.floor(c - math.cos(a) * r),
            color = color, width = 1, opacity = 150,
        }
    end
    return items
end

function M.radar_bg(parent, x, y, size, color, ring_color)
    return theme.shape(parent, x, y, size, size,
        M.radar_bg_items(size, color or C.cyan, ring_color or 0x1D3A55))
end

-- 扫描扇区：角度以正北为 0、顺时针；返回图元（尾巴在前的 9 条渐变线）
function M.sweep_items(size, angle, color, slices, span)
    local c = math.floor(size / 2)
    local r = math.floor(size / 2 - 3)
    slices = slices or 9
    span = span or 42
    local items = {}
    for i = 1, slices do
        local t = i / slices
        local a = rad(angle - span * (1 - t))
        local opa = math.floor(10 + 62 * t * t)
        items[#items + 1] = {
            type = "line", x1 = c, y1 = c,
            x2 = math.floor(c + math.sin(a) * r), y2 = math.floor(c - math.cos(a) * r),
            color = color, width = 2, opacity = opa,
        }
    end
    -- 前沿亮线
    local a0 = rad(angle)
    items[#items + 1] = {
        type = "line", x1 = c, y1 = c,
        x2 = math.floor(c + math.sin(a0) * r), y2 = math.floor(c - math.cos(a0) * r),
        color = color, width = 2, opacity = 210,
    }
    items[#items + 1] = {
        type = "arc", cx = c, cy = c, r = r, start_angle = angle - span, end_angle = angle,
        color = color, width = 1, opacity = 45,
    }
    return items
end

-- 航迹点：外圈光晕 + 实心
function M.blip_items(r, color, opa)
    local sz = r * 2 + 4
    return {
        { type = "circle", cx = sz / 2, cy = sz / 2, r = r + 1, color = color, width = 1,
          opacity = math.floor((opa or 60) * 0.5), fill = true, fill_color = color,
          fill_opacity = math.floor((opa or 60) * 0.30) },
        { type = "circle", cx = sz / 2, cy = sz / 2, r = r, color = color, fill = true,
          fill_color = color, width = 1 },
    }
end

-- ===================== 跑道 / 滑行道 =====================
-- 横向跑道：道面 + 中线虚线 + 两端入口标线
function M.runway_items(w, h, color, dash_color)
    local items = {
        { type = "rect", x = 0, y = 0, w = w, h = h, radius = 2,
          color = 0x203245, width = 1, fill = true, fill_color = 0x16283C, fill_opacity = 255 },
    }
    local y = math.floor(h / 2)
    local x = 14
    while x < w - 14 do
        local seg = math.min(18, w - 14 - x)
        if seg > 2 then
            items[#items + 1] = { type = "line", x1 = x, y1 = y, x2 = x + seg, y2 = y,
                color = dash_color or 0xBFD8EE, width = 2, opacity = 210 }
        end
        x = x + seg + 12
    end
    for _, ex in ipairs({ 8, w - 8 }) do
        items[#items + 1] = { type = "line", x1 = ex, y1 = 3, x2 = ex, y2 = h - 3,
            color = color or 0x6F8FA8, width = 2, opacity = 190 }
    end
    return items
end

function M.runway(parent, x, y, w, h, color, dash_color)
    return theme.shape(parent, x, y, w, h, M.runway_items(w, h, color, dash_color))
end

-- ===================== 罗盘 / 风向 =====================
-- dir 为风来向（0=北），指针指向风的来向
function M.compass_items(size, dir, color, track)
    local c = math.floor(size / 2)
    local r = math.floor(size / 2 - 4)
    local items = {
        { type = "circle", cx = c, cy = c, r = r, color = track or 0x1D3A55, width = 1, opacity = 160 },
        { type = "circle", cx = c, cy = c, r = 3, color = color, fill = true, fill_color = color, width = 1 },
    }
    for i = 0, 7 do
        local a = rad(i * 45)
        items[#items + 1] = {
            type = "line",
            x1 = math.floor(c + math.sin(a) * (r - 5)), y1 = math.floor(c - math.cos(a) * (r - 5)),
            x2 = math.floor(c + math.sin(a) * r), y2 = math.floor(c - math.cos(a) * r),
            color = color, width = 1, opacity = 170,
        }
    end
    local a = rad(dir)
    local tipx, tipy = c + math.sin(a) * (r - 9), c - math.cos(a) * (r - 9)
    items[#items + 1] = { type = "line", x1 = c, y1 = c, x2 = math.floor(tipx), y2 = math.floor(tipy),
        color = color, width = 2, opacity = 235, round_end = true }
    -- 箭头
    for _, s in ipairs({ -1, 1 }) do
        local aa = a + math.pi + s * 0.42
        items[#items + 1] = {
            type = "line", x1 = math.floor(tipx), y1 = math.floor(tipy),
            x2 = math.floor(tipx + math.sin(aa) * 6), y2 = math.floor(tipy - math.cos(aa) * 6),
            color = color, width = 2, opacity = 235,
        }
    end
    -- 风力弧：末尾小弧表示强度在 gauge 里另画
    return items
end

function M.compass(parent, x, y, size, dir, color, track)
    return theme.shape(parent, x, y, size, size, M.compass_items(size, dir, color, track))
end

-- ===================== 保障甘特 / 时间轴 =====================
-- n 个节点，done 为已完成个数；返回 {items, 每个节点的中心 x}
function M.gantt_items(w, h, n, done, color, off_color)
    local items = {}
    local gap = 6
    local seg = math.floor((w - (n - 1) * gap) / n)
    if seg < 4 then seg = 4 end
    local centers = {}
    for i = 1, n do
        local x = (i - 1) * (seg + gap)
        local on = i <= done
        items[#items + 1] = {
            type = "rect", x = x, y = math.floor(h / 2) - 4, w = seg, h = 8, radius = 4,
            color = on and color or off_color, width = 0, opacity = 255,
            fill = true, fill_color = on and color or off_color, fill_opacity = on and 255 or 255,
        }
        centers[i] = x + math.floor(seg / 2)
    end
    return items, centers, seg
end

-- ===================== 波形 =====================
-- opts: color, min, max, lo, hi, band(bool), grid(int), dash(bool)
function M.waveform_items(w, h, hist, opts)
    opts = opts or {}
    local color = opts.color or C.cyan
    local vmin = opts.min or 0
    local vmax = opts.max or 1
    if vmax - vmin < 0.000001 then vmax = vmin + 1 end
    local pad = 8
    local ih = h - pad * 2

    local function vy(v)
        return math.floor(pad + ih - clamp01((v - vmin) / (vmax - vmin)) * ih)
    end

    local items = {}
    local grid = opts.grid or 4
    for i = 0, grid do
        local y = math.floor(pad + ih * i / grid)
        items[#items + 1] = { type = "line", x1 = 0, y1 = y, x2 = w, y2 = y,
            color = C.line, width = 1, opacity = 130,
            dash_width = (opts.dash and 4 or 0), dash_gap = (opts.dash and 4 or 0) }
    end
    if opts.band and opts.lo and opts.hi then
        local y1, y2 = vy(opts.hi), vy(opts.lo)
        if y2 > y1 then
            items[#items + 1] = { type = "rect", x = 0, y = y1, w = w, h = y2 - y1,
                color = C.green, width = 0, opacity = 0,
                fill = true, fill_color = C.green, fill_opacity = 20 }
        end
    end
    local n = #hist
    if n >= 2 then
        local step = w / (n - 1)
        for i = 1, n do
            local x = (i - 1) * step
            local y = vy(hist[i])
            if h - y > 2 then
                items[#items + 1] = { type = "rect", x = math.floor(x - 2), y = y,
                    w = 5, h = h - y, color = color, width = 0, opacity = 0,
                    fill = true, fill_color = color, fill_opacity = 26 }
            end
        end
        for i = 2, n do
            items[#items + 1] = { type = "line",
                x1 = math.floor((i - 2) * step), y1 = vy(hist[i - 1]),
                x2 = math.floor((i - 1) * step), y2 = vy(hist[i]),
                color = color, width = 2, round_start = true, round_end = true }
        end
        local lx, ly = w, vy(hist[n])
        items[#items + 1] = { type = "circle", cx = lx - 1, cy = ly, r = 6,
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

-- 圆环进度（KPI / 占用率）
function M.ring_items(size, pct, color, track, width)
    local c = math.floor(size / 2)
    local r = math.floor(size / 2 - 5)
    width = width or 6
    local items = {
        { type = "arc", cx = c, cy = c, r = r, start_angle = 0, end_angle = 359,
          color = track or C.panel3, width = width, opacity = 255 },
    }
    pct = clamp01(pct or 0)
    if pct > 0.01 then
        items[#items + 1] = { type = "arc", cx = c, cy = c, r = r,
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

local function rect(items, x, y, w, h, color, radius, width, fill)
    items[#items + 1] = {
        type = "rect", x = math.floor(x), y = math.floor(y),
        w = math.max(1, math.floor(w)), h = math.max(1, math.floor(h)),
        radius = radius or 0, color = color, width = width or 2, opacity = 255,
        fill = fill and true or false, fill_color = color, fill_opacity = (fill and 255 or 0),
    }
end

-- s 为图标外框边长，返回图元列表（坐标 0..s）
function M.icon_items(kind, s, color)
    local items = {}
    local c = color or C.ink
    local mid = s / 2

    if kind == "plane" then
        return M.plane_items(s, c, true)
    elseif kind == "radar" then
        circle(items, mid, mid, s * 0.36, c, false, 255, 2)
        circle(items, mid, mid, s * 0.16, c, false, 255, 1)
        line(items, mid, mid, mid + s * 0.26, mid - s * 0.22, c, 2)
        circle(items, mid - s * 0.14, mid + s * 0.10, 1.6, c, true)
        circle(items, mid + s * 0.16, mid + s * 0.16, 1.2, c, true)
    elseif kind == "wind" then
        line(items, s * 0.12, s * 0.38, s * 0.66, s * 0.38, c, 2)
        line(items, s * 0.30, s * 0.58, s * 0.80, s * 0.58, c, 2)
        line(items, s * 0.20, s * 0.78, s * 0.58, s * 0.78, c, 2)
        arc(items, s * 0.70, s * 0.30, s * 0.14, 270, 90, c, 2)
    elseif kind == "fog" then
        line(items, s * 0.14, s * 0.42, s * 0.86, s * 0.42, c, 2)
        line(items, s * 0.22, s * 0.58, s * 0.78, s * 0.58, c, 2)
        line(items, s * 0.10, s * 0.74, s * 0.70, s * 0.74, c, 2)
    elseif kind == "snow" then
        line(items, mid, s * 0.14, mid, s * 0.86, c, 2)
        line(items, s * 0.14, mid, s * 0.86, mid, c, 2)
        line(items, s * 0.22, s * 0.22, s * 0.78, s * 0.78, c, 2)
        line(items, s * 0.78, s * 0.22, s * 0.22, s * 0.78, c, 2)
    elseif kind == "clock" then
        circle(items, mid, mid, s * 0.38, c, false, 255, 2)
        line(items, mid, mid, mid, mid - s * 0.20, c, 2)
        line(items, mid, mid, mid + s * 0.16, mid + s * 0.08, c, 2)
    elseif kind == "gear" then
        circle(items, mid, mid, s * 0.22, c, false, 255, 2)
        for i = 0, 7 do
            local a = i * math.pi / 4
            line(items, mid + math.cos(a) * s * 0.28, mid + math.sin(a) * s * 0.28,
                mid + math.cos(a) * s * 0.44, mid + math.sin(a) * s * 0.44, c, 2)
        end
    elseif kind == "back" then
        line(items, s * 0.62, s * 0.20, s * 0.34, s * 0.50, c, 3)
        line(items, s * 0.34, s * 0.50, s * 0.62, s * 0.80, c, 3)
    elseif kind == "arrow" then
        line(items, s * 0.20, mid, s * 0.80, mid, c, 2)
        line(items, s * 0.58, s * 0.30, s * 0.80, mid, c, 2)
        line(items, s * 0.58, s * 0.70, s * 0.80, mid, c, 2)
    elseif kind == "check" then
        line(items, s * 0.24, s * 0.52, s * 0.44, s * 0.72, c, 2)
        line(items, s * 0.44, s * 0.72, s * 0.78, s * 0.30, c, 2)
    elseif kind == "alert" then
        items[#items + 1] = { type = "line", x1 = mid, y1 = s * 0.16, x2 = s * 0.16, y2 = s * 0.84,
            color = c, width = 2, round_start = true }
        items[#items + 1] = { type = "line", x1 = mid, y1 = s * 0.16, x2 = s * 0.84, y2 = s * 0.84,
            color = c, width = 2, round_end = true }
        line(items, s * 0.16, s * 0.84, s * 0.84, s * 0.84, c, 2)
        line(items, mid, s * 0.44, mid, s * 0.64, c, 2)
        circle(items, mid, s * 0.74, 1.6, c, true)
    elseif kind == "gate" then
        rect(items, s * 0.16, s * 0.46, s * 0.68, s * 0.40, c, 2, 2, false)
        line(items, s * 0.16, s * 0.46, mid, s * 0.20, c, 2)
        line(items, mid, s * 0.20, s * 0.84, s * 0.46, c, 2)
        line(items, s * 0.36, s * 0.86, s * 0.36, s * 0.64, c, 2)
        line(items, s * 0.64, s * 0.86, s * 0.64, s * 0.64, c, 2)
    elseif kind == "fuel" then
        rect(items, s * 0.22, s * 0.30, s * 0.56, s * 0.56, c, 3, 2, false)
        line(items, s * 0.38, s * 0.30, s * 0.38, s * 0.16, c, 2)
        line(items, s * 0.38, s * 0.16, s * 0.62, s * 0.16, c, 2)
        line(items, mid, s * 0.48, mid, s * 0.68, c, 2)
        line(items, s * 0.42, s * 0.58, s * 0.58, s * 0.58, c, 2)
    elseif kind == "bag" then
        rect(items, s * 0.20, s * 0.36, s * 0.60, s * 0.46, c, 4, 2, false)
        arc(items, s * 0.38, s * 0.36, s * 0.10, 180, 360, c, 2)
        line(items, s * 0.32, s * 0.52, s * 0.68, s * 0.52, c, 1)
    elseif kind == "bus" then
        rect(items, s * 0.14, s * 0.28, s * 0.72, s * 0.42, c, 4, 2, false)
        circle(items, s * 0.32, s * 0.76, s * 0.07, c, true)
        circle(items, s * 0.68, s * 0.76, s * 0.07, c, true)
        line(items, s * 0.18, s * 0.48, s * 0.82, s * 0.48, c, 1)
    elseif kind == "deice" then
        line(items, s * 0.20, s * 0.82, s * 0.46, s * 0.50, c, 2)
        line(items, s * 0.46, s * 0.50, s * 0.46, s * 0.22, c, 2)
        circle(items, s * 0.72, s * 0.26, s * 0.06, c, true)
        circle(items, s * 0.80, s * 0.44, s * 0.045, c, true)
        circle(items, s * 0.66, s * 0.42, s * 0.035, c, true)
    elseif kind == "pax" then
        circle(items, mid, s * 0.28, s * 0.13, c, false, 255, 2)
        arc(items, mid, s * 0.82, s * 0.26, 200, 340, c, 2)
    elseif kind == "list" then
        for i = 0, 3 do
            local y = s * 0.22 + i * s * 0.19
            circle(items, s * 0.18, y, 1.6, c, true)
            line(items, s * 0.32, y, s * 0.84, y, c, 2)
        end
    elseif kind == "runway" then
        rect(items, s * 0.34, s * 0.10, s * 0.32, s * 0.80, c, 2, 2, false)
        for i = 0, 3 do
            local y = s * 0.22 + i * s * 0.16
            line(items, mid, y, mid, y + s * 0.09, c, 1)
        end
    elseif kind == "bolt" then
        line(items, s * 0.56, s * 0.10, s * 0.32, s * 0.52, c, 2)
        line(items, s * 0.32, s * 0.52, s * 0.58, s * 0.52, c, 2)
        line(items, s * 0.58, s * 0.52, s * 0.42, s * 0.90, c, 2)
    else
        circle(items, mid, mid, s * 0.34, c, false, 255, 2)
    end
    return items
end

function M.icon(parent, kind, x, y, s, color)
    return theme.shape(parent, x, y, s, s, M.icon_items(kind, s, color))
end

return M
