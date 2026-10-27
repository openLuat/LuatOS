--[[
@module  fx_core
@summary 音乐播放器 - 绘图工具库（数学 / 颜色 / 文本裁剪 / 图元对象池）
@version 1.0
@date    2026.10.23

=== 图元对象池为什么必须复用 ===
每帧要重建 100+ 个图元表，直接建新表会产生 3000+ 个临时表/秒，
Lua GC 周期性回收时会有肉眼可见的卡顿。这里复用同一批表，
只在 finish() 时把尾部真正置 nil —— 因为 airui.shape 的 set_items 用
lua_rawlen 取长度，尾部若留着旧表，上一帧的残留图元会被一起画出来。
同理，每个写入方法都会把该图元的全部字段重写一遍，不允许依赖"上一帧留下的默认值"。

=== set_items 的整型陷阱 ===
shape:set_items 走 lua_tointeger，浮点会被**静默**转成 0：不报错，
只是那个物件凭空消失（比崩机更难查）。所以本文件里所有坐标/尺寸/角度都取整。
]]

local M = {}

M.TAU = math.pi * 2

-- ==================== 数学 ====================
function M.clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

function M.lerp(a, b, t)
    return a + (b - a) * t
end

function M.ease_out(t)
    return 1 - (1 - t) * (1 - t)
end

function M.ease_in_out(t)
    if t < 0.5 then return 2 * t * t end
    return 1 - 2 * (1 - t) * (1 - t)
end

--[[把值柔顺地推向目标：k 越大跟得越紧
每帧调用一次即可，不依赖 dt 的绝对精度（Air1603 的 tick 分辨率只有 20ms）
]]
function M.approach(cur, target, k)
    return cur + (target - cur) * M.clamp(k, 0, 1)
end

-- ==================== 颜色 ====================
function M.rgb(r, g, b)
    return math.floor(r + 0.5) * 65536 + math.floor(g + 0.5) * 256 + math.floor(b + 0.5)
end

function M.split(c)
    return math.floor(c / 65536) % 256, math.floor(c / 256) % 256, c % 256
end

--[[线性混色：t=0 取 c1，t=1 取 c2]]
function M.mix(c1, c2, t)
    t = M.clamp(t or 0, 0, 1)
    local r1, g1, b1 = M.split(c1)
    local r2, g2, b2 = M.split(c2)
    return M.rgb(r1 + (r2 - r1) * t, g1 + (g2 - g1) * t, b1 + (b2 - b1) * t)
end

--[[提亮/压暗：k>0 向白靠拢，k<0 向黑靠拢]]
function M.shade(c, k)
    if k >= 0 then return M.mix(c, 0xFFFFFF, k) end
    return M.mix(c, 0x000000, -k)
end

local function hue2channel(p, q, t)
    if t < 0 then t = t + 1 end
    if t > 1 then t = t - 1 end
    if t < 1 / 6 then return p + (q - p) * 6 * t end
    if t < 1 / 2 then return q end
    if t < 2 / 3 then return p + (q - p) * (2 / 3 - t) * 6 end
    return p
end

--[[HSL → 0xRRGGBB
@param number h 色相 0-360（超出自动取模，可放心写 hue + t*10 做流动渐变）
@param number s 饱和度 0-1
@param number l 亮度 0-1
]]
function M.hsl(h, s, l)
    h = ((h or 0) % 360) / 360
    s = M.clamp(s or 1, 0, 1)
    l = M.clamp(l or 0.5, 0, 1)
    local r, g, b
    if s <= 0 then
        r, g, b = l, l, l
    else
        local q = (l < 0.5) and (l * (1 + s)) or (l + s - l * s)
        local p = 2 * l - q
        r = hue2channel(p, q, h + 1 / 3)
        g = hue2channel(p, q, h)
        b = hue2channel(p, q, h - 1 / 3)
    end
    return M.rgb(r * 255, g * 255, b * 255)
end

-- ==================== 随机与噪声 ====================
--[[固定种子线性同余发生器，返回 function() -> 0..1 ]]
function M.rng(seed)
    local s = math.floor(seed or 1) % 2147483647
    if s <= 0 then s = s + 2147483646 end
    return function()
        s = (s * 16807) % 2147483647
        return s / 2147483647
    end
end

local function hash1(n)
    local v = math.sin(n * 127.1) * 43758.5453
    return v - math.floor(v)
end

--[[一维平滑值噪声，返回 0..1；让节奏变化不平铺直叙]]
function M.noise1(x)
    local i = math.floor(x)
    local f = x - i
    local u = f * f * (3 - 2 * f)
    return M.lerp(hash1(i), hash1(i + 1), u)
end

-- ==================== 文本 ====================
--[[毫秒 → "mm:ss"（超过 99 分钟按分钟数继续累加）]]
function M.fmt_time(ms)
    local s = math.floor((ms or 0) / 1000)
    if s < 0 then s = 0 end
    return string.format("%02d:%02d", math.floor(s / 60), s % 60)
end

--[[按像素宽度裁剪文本（超宽补 ".."）
label 默认是 LONG_WRAP，文本超宽会折行把版面顶乱，所以送进 label 前先量一遍。
宽度是估算：ASCII 记 0.56 字宽，其余（汉字/全角）记 1.0 字宽 —— 不追求精确，
只保证"一定不超"，多裁几个字比折行好看。
@param string text 原文
@param number max_px 可用像素宽
@param number font 字号
@return string 裁剪后的文本
]]
function M.fit(text, max_px, font)
    if text == nil then return "" end
    if max_px <= 0 then return "" end
    local n = #text
    local px, i, out = 0, 1, nil
    while i <= n do
        local b = text:byte(i)
        local len = 1
        if b >= 0xF0 then len = 4
        elseif b >= 0xE0 then len = 3
        elseif b >= 0xC0 then len = 2 end
        local w = (len == 1) and 0.56 or 1.0
        px = px + w * font
        if px > max_px then
            if out == nil then return "" end
            return out .. ".."
        end
        out = (out or "") .. text:sub(i, i + len - 1)
        i = i + len
    end
    return text
end

--[[是否是合法 UTF-8（歌词文件常见 GBK 乱码，用来提示用户转码）]]
function M.is_utf8(s)
    local i, n = 1, #s
    while i <= n do
        local b = s:byte(i)
        local need
        if b < 0x80 then need = 0
        elseif b >= 0xF0 and b <= 0xF4 then need = 3
        elseif b >= 0xE0 then need = 2
        elseif b >= 0xC0 then need = 1
        else return false end
        if i + need > n then return false end
        for k = 1, need do
            local c = s:byte(i + k)
            if not c or c < 0x80 or c > 0xBF then return false end
        end
        i = i + need + 1
    end
    return true
end

-- ==================== 图元对象池 ====================
--[[
@return P 图元池对象
  P.items           —— 直接交给 shape:set_items() 的数组
  P:reset()         —— 开始新的一帧
  P:finish()        —— 结束本帧，返回图元个数（并把尾部残留清空）
  P:line / dash / dot / ring / box / frame / ellipse / arc
@usage
  local P = fx.pool()
  P:reset()
  P:dot(10, 10, 3, 0x22E6FF, 255)
  local n = P:finish()
  shape:set_items(P.items)
]]
function M.pool()
    local items = {}
    local n, maxn = 0, 0
    local P = { items = items }

    local function slot()
        n = n + 1
        local t = items[n]
        if t == nil then
            t = {}
            items[n] = t
            if n > maxn then maxn = n end
        end
        return t
    end

    function P:reset()
        n = 0
    end

    function P:size()
        return n
    end

    function P:finish()
        for i = n + 1, maxn do items[i] = nil end
        maxn = n
        return n
    end

    -- 直线（round=true 时两端圆头，用来把折线接成平滑曲线）
    function P:line(x1, y1, x2, y2, color, width, opa, round)
        local t = slot()
        t.type = "line"
        t.x1 = math.floor(x1)
        t.y1 = math.floor(y1)
        t.x2 = math.floor(x2)
        t.y2 = math.floor(y2)
        t.color = color or 0xFFFFFF
        t.width = width or 1
        t.opacity = opa or 255
        t.dash_width = 0
        t.dash_gap = 0
        t.round_start = round and true or false
        t.round_end = round and true or false
        t.fill = false
        t.fill_color = color or 0xFFFFFF
        t.fill_opacity = 0
        return t
    end

    -- 虚线
    function P:dash(x1, y1, x2, y2, color, width, opa, dw, dg)
        local t = self:line(x1, y1, x2, y2, color, width, opa, false)
        t.dash_width = dw or 6
        t.dash_gap = dg or 6
        return t
    end

    -- 实心圆（画粒子/光点的最小代价图元）
    function P:dot(cx, cy, r, color, opa)
        local t = slot()
        t.type = "circle"
        t.cx = math.floor(cx)
        t.cy = math.floor(cy)
        t.r = math.floor(r)
        if t.r < 0 then t.r = 0 end
        t.color = color or 0xFFFFFF
        t.width = 1
        t.opacity = opa or 255
        t.dash_width = 0
        t.dash_gap = 0
        t.round_start = false
        t.round_end = false
        t.fill = true
        t.fill_color = color or 0xFFFFFF
        t.fill_opacity = opa or 255
        return t
    end

    -- 空心圆环
    function P:ring(cx, cy, r, color, width, opa)
        local t = slot()
        t.type = "circle"
        t.cx = math.floor(cx)
        t.cy = math.floor(cy)
        t.r = math.floor(r)
        if t.r < 0 then t.r = 0 end
        t.color = color or 0xFFFFFF
        t.width = width or 1
        t.opacity = opa or 255
        t.dash_width = 0
        t.dash_gap = 0
        t.round_start = false
        t.round_end = false
        t.fill = false
        t.fill_color = color or 0xFFFFFF
        t.fill_opacity = 0
        return t
    end

    -- 实心矩形 / 圆角矩形（画柱状条的主力图元）
    function P:box(x, y, w, h, color, opa, radius)
        local t = slot()
        t.type = "rect"
        t.x = math.floor(x)
        t.y = math.floor(y)
        t.w = math.floor(w)
        t.h = math.floor(h)
        if t.w < 0 then t.w = 0 end
        if t.h < 0 then t.h = 0 end
        t.radius = math.floor(radius or 0)
        t.color = color or 0xFFFFFF
        t.width = 1
        t.opacity = 0
        t.dash_width = 0
        t.dash_gap = 0
        t.round_start = false
        t.round_end = false
        t.fill = true
        t.fill_color = color or 0xFFFFFF
        t.fill_opacity = opa or 255
        return t
    end

    -- 空心矩形边框（fill_opacity = 0，只留描边）
    function P:frame(x, y, w, h, color, width, opa, radius)
        local t = self:box(x, y, w, h, color, 0, radius)
        t.width = width or 1
        t.opacity = opa or 255
        return t
    end

    -- 空心椭圆（填充椭圆在 C 层是逐行画线，代价高，这里只提供描边）
    function P:ellipse(cx, cy, rx, ry, color, width, opa, segments)
        local t = slot()
        t.type = "ellipse"
        t.cx = math.floor(cx)
        t.cy = math.floor(cy)
        t.rx = math.floor(rx)
        t.ry = math.floor(ry)
        if t.rx < 0 then t.rx = 0 end
        if t.ry < 0 then t.ry = 0 end
        t.segments = math.floor(segments or 32)
        t.color = color or 0xFFFFFF
        t.width = width or 1
        t.opacity = opa or 255
        t.dash_width = 0
        t.dash_gap = 0
        t.round_start = false
        t.round_end = false
        t.fill = false
        t.fill_color = color or 0xFFFFFF
        t.fill_opacity = 0
        return t
    end

    --[[圆弧（唱片旋转高光、播放进度环）
    角度单位是度，0 度在 3 点钟方向、顺时针增大；
    start_angle == end_angle 时不画，相差 360 度及以上画整圆。
    ]]
    function P:arc(cx, cy, r, a1, a2, color, width, opa, rounded)
        local t = slot()
        t.type = "arc"
        t.cx = math.floor(cx)
        t.cy = math.floor(cy)
        t.r = math.floor(r)
        if t.r < 0 then t.r = 0 end
        t.start_angle = math.floor(a1)
        t.end_angle = math.floor(a2)
        t.color = color or 0xFFFFFF
        t.width = width or 2
        t.opacity = opa or 255
        t.dash_width = 0
        t.dash_gap = 0
        t.rounded = rounded and true or false
        t.round_start = false
        t.round_end = false
        t.fill = false
        t.fill_color = color or 0xFFFFFF
        t.fill_opacity = 0
        return t
    end

    return P
end

return M
