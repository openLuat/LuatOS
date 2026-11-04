--[[
@module  kit
@summary 通用小工具：数值夹取 / 缓动 / 时间与数字格式化 / 图元片段
@version 1.0
@date    2026.11.04
]]
local M = {}

function M.clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

function M.lerp(a, b, t)
    return a + (b - a) * t
end

-- 平滑插值（0..1 进出都平）
function M.smooth(t)
    t = M.clamp(t, 0, 1)
    return t * t * (3 - 2 * t)
end

-- 先快后慢
function M.ease_out(t)
    t = M.clamp(t, 0, 1)
    return 1 - (1 - t) * (1 - t)
end

--- 任务时间格式化成 T-00:00:10 / T+00:00:10
-- @param number t 秒（负数为起飞前）
-- @return string
function M.fmt_t(t)
    local neg = t < 0
    local a = math.floor(math.abs(t) + 0.0001)
    local mm = math.floor(a / 60)
    local ss = a % 60
    return string.format("T%s%02d:%02d:%02d", neg and "-" or "+", 0, mm, ss)
end

-- 只要分秒，卡片里空间不够时用
function M.fmt_ms(t)
    local neg = t < 0
    local a = math.floor(math.abs(t) + 0.0001)
    return string.format("%s%02d:%02d", neg and "-" or "+", math.floor(a / 60), a % 60)
end

function M.fmt_num(v, dec)
    if v == nil then return "--" end
    local s = string.format("%." .. (dec or 0) .. "f", v)
    -- 千分位
    local int, frac = s:match("^(-?%d+)(%.%d*)$")
    if not int then int, frac = s, nil end
    int = int:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    if int:sub(1, 1) == "," then int = int:sub(2) end
    return frac and (int .. frac) or int
end

--- 把圆角柱状条追加到图元数组
function M.bar(items, x, y, w, h, ratio, color, track, radius)
    radius = radius or math.floor(h / 2)
    ratio = M.clamp(ratio or 0, 0, 1)
    items[#items + 1] = { type = "rect", x = x, y = y, w = w, h = h,
        radius = radius, color = track or 0x16233A, width = 0,
        fill = true, fill_color = track or 0x16233A, fill_opacity = 255 }
    local fw = math.floor(w * ratio + 0.5)
    if fw < 1 then return end
    if fw < h then fw = h end          -- 太短时至少保留一个圆头
    items[#items + 1] = { type = "rect", x = x, y = y, w = fw, h = h,
        radius = radius, color = color, width = 0,
        fill = true, fill_color = color, fill_opacity = 255 }
end

--- 折线：把点数组追加成一系列 line 图元
function M.polyline(items, pts, color, width, opacity)
    for i = 2, #pts do
        local p1, p2 = pts[i - 1], pts[i]
        items[#items + 1] = { type = "line",
            x1 = p1[1], y1 = p1[2], x2 = p2[1], y2 = p2[2],
            color = color, width = width or 2, opacity = opacity or 255,
            round_start = true, round_end = true }
    end
end

--- 面积填充（折线到基线之间，用 2px 竖条铺）
function M.area(items, pts, base_y, color, opacity)
    for i = 2, #pts do
        local p1, p2 = pts[i - 1], pts[i]
        local x = math.min(p1[1], p2[1])
        local w = math.max(math.abs(p2[1] - p1[1]) + 1, 1)
        local top = math.min(p1[2], p2[2])
        local h = math.floor(base_y - top)
        if h > 0 then
            items[#items + 1] = { type = "rect", x = x, y = top, w = w, h = h,
                radius = 0, color = color, width = 0,
                fill = true, fill_color = color, fill_opacity = opacity or 60 }
        end
    end
end

--- 实心三角形（用逐行矩形堆出来，shape 没有 polygon 图元）
-- 顶点朝上的等腰三角形，底边 y2，尖端 (cx, y1)
function M.triangle_up(items, cx, y1, half_w, y2, color, opacity)
    local n = math.max(math.floor(y2 - y1), 1)
    for i = 0, n - 1 do
        local t = n > 1 and (i / (n - 1)) or 1
        local hw = math.max(1, math.floor(half_w * t + 0.5))
        items[#items + 1] = { type = "rect", x = cx - hw, y = y1 + i,
            w = hw * 2, h = 1, radius = 0, color = color, width = 0,
            fill = true, fill_color = color, fill_opacity = opacity or 255 }
    end
end

--- 直角三角形（机翼/尾翼），dir = -1 左、1 右
function M.tri_side(items, x, y, w, h, dir, color, opacity)
    local n = math.max(h, 1)
    for i = 0, n - 1 do
        local t = (i + 1) / n
        local ww = math.max(1, math.floor(w * t + 0.5))
        local xx = (dir > 0) and x or (x - ww)
        items[#items + 1] = { type = "rect", x = xx, y = y + i,
            w = ww, h = 1, radius = 0, color = color, width = 0,
            fill = true, fill_color = color, fill_opacity = opacity or 255 }
    end
end

return M
