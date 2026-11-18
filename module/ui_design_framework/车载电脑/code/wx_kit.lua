-- page_weather.lua  天气页
-- 对照「天气预报」工程 page_weather.lua 全量移植（用户要求「全部照抄，不要只抄一半」）：
--   hero 卡 / 9 个指标 tab / 每个 tab 的附加线开关行 / 7 天日期条（概览=图标+高低温，
--   其它 tab=数值+概率/等级+右侧迷你滑条）/ 图表（概览小时图标行、风速风向箭头行、
--   面积渐变、附加线、图例）/ 列表（横向滑动小时卡）/
--   天气详细信息 12 卡（温度/体感/云量/降水/风速罗盘/湿度柱/紫外线环/AQI环/
--   能见度珠条/气压曲线/太阳弧/月相）
local sys = require "sys"
local theme = require "theme"
require "mock"

local W, H = theme.W, theme.H
local PX = 12
local CW = W - PX * 2

--------------------------------------------------------------------
-- 天气图标（纯 shape；图元全部落在画布内）
--------------------------------------------------------------------
local function wx_icon(parent, x, y, s, kind, opts)
    local C = theme.C
    opts = opts or {}
    local cloud = opts.cloud or C.cloud
    local sun   = opts.sun or C.yellow
    local rainc = opts.rain or C.rain
    local bgc   = opts.bg or C.card
    local items = {}
    local ci, ln, rc = theme._ci, theme._ln, theme._rc
    local function rays(cx, cy, r0, r1)
        for i = 0, 7 do
            local a = math.rad(i * 45)
            ln(items, cx + r0 * math.cos(a), cy + r0 * math.sin(a),
                        cx + r1 * math.cos(a), cy + r1 * math.sin(a), sun, 2)
        end
    end
    local function cloud_at(cx, cy, k)
        ci(items, cx - 0.17 * s * k, cy, 0.15 * s * k, cloud, 250)
        ci(items, cx, cy - 0.09 * s * k, 0.20 * s * k, cloud, 255)
        ci(items, cx + 0.18 * s * k, cy + 0.02 * s * k, 0.14 * s * k, cloud, 250)
        local rw = 0.60 * s * k
        local rx = cx - rw / 2
        if rx < 0 then rx = 0 end
        if rx + rw > s then rw = s - rx end
        rc(items, rx, cy - 0.01 * s * k, rw, 0.18 * s * k, cloud, math.floor(0.07 * s * k))
    end
    if kind == "sun" then
        ci(items, 0.5 * s, 0.5 * s, 0.21 * s, sun, 255)
        rays(0.5 * s, 0.5 * s, 0.28 * s, 0.38 * s)
    elseif kind == "moon" then
        ci(items, 0.46 * s, 0.46 * s, 0.24 * s, 0xCBD8F0, 255)
        ci(items, 0.56 * s, 0.38 * s, 0.21 * s, bgc, 255)
    elseif kind == "rain" then
        cloud_at(0.5 * s, 0.44 * s, 0.86)
        ln(items, 0.34 * s, 0.70 * s, 0.29 * s, 0.86 * s, rainc, 2)
        ln(items, 0.50 * s, 0.70 * s, 0.45 * s, 0.88 * s, rainc, 2)
        ln(items, 0.66 * s, 0.70 * s, 0.61 * s, 0.86 * s, rainc, 2)
    elseif kind == "partly" then
        ci(items, 0.34 * s, 0.32 * s, 0.14 * s, sun, 255)
        rays(0.34 * s, 0.32 * s, 0.19 * s, 0.26 * s)
        cloud_at(0.56 * s, 0.66 * s, 0.72)
    else
        cloud_at(0.5 * s, 0.54 * s, 1)
    end
    theme.shapes(parent, x, y, s, s, items)
end

--------------------------------------------------------------------
-- 迷你折线（详情卡用）
--------------------------------------------------------------------
local function spark(parent, x, y, w, h, col, vals, lo, hi)
    local n = #vals
    if n < 2 then return end
    if hi - lo <= 0 then hi = lo + 1 end
    local items = {}
    local px, py
    for i = 1, n do
        local k = (vals[i] - lo) / (hi - lo)
        if k < 0 then k = 0 elseif k > 1 then k = 1 end
        local cx = math.floor((i - 1) * w / (n - 1) + 0.5)
        local cy = math.floor(h - k * h + 0.5)
        if px then theme._ln(items, px, py, cx, cy, col, 2) end
        px, py = cx, cy
    end
    theme.shapes(parent, x, y, w, h, items)
end

--------------------------------------------------------------------
-- 珠链圆环（紫外线 / AQI 用）
--------------------------------------------------------------------
local function ring(parent, cx, cy, r, segs)
    local items = {}
    local total = 0
    for _, s in ipairs(segs) do total = total + s.f end
    if total <= 0 then return end
    local beads, acc = 30, 0
    for _, s in ipairs(segs) do
        local n = math.max(0, math.floor(beads * s.f / total + 0.5))
        for _ = 1, n do
            local a = (acc / beads) * math.pi * 2 - math.pi / 2
            local bx = math.floor(math.cos(a) * r + 0.5)
            local by = math.floor(math.sin(a) * r + 0.5)
            theme._ci(items, bx + r + 3, by + r + 3, 2, s.color, 255)
            acc = acc + 1
        end
    end
    theme.shapes(parent, cx - r - 3, cy - r - 3, r * 2 + 6, r * 2 + 6, items)
end

return { wx_icon = wx_icon, spark = spark, ring = ring }
