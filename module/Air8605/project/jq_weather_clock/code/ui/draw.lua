--[[
@module  draw
@summary 绘图工具：颜色运算 + airui.shape 图元池
@version 1.0
@date    2026.11.08

=== 为什么要有图元池 ===
本工程每帧要重建上百个图元表。如果每帧都新建 Lua 表，GC 的周期性回收
会在画面上变成肉眼可见的顿卡。池子复用同一批表，finish() 把尾部残留置 nil
（shape:set_items 用 lua_rawlen 取长度，尾部留旧表会把上一帧的图元也画出来）。

=== 三个必须遵守的细节（都在真机上踩过）===
1. 所有整型字段必须 math.floor：C 层用 lua_tointeger 读，3.7 这种浮点直接得 0，
   宽度变 0 → 夹成 1，透明度变 0 → 图元"凭空消失"。
2. 每个图元要把**全部字段**写一遍：池子复用上一帧的表，少写一个 fill
   就会继承上一帧的填充状态，表现为"某条线突然变成一块色块"。
3. 纯填充图元（box / dot）必须把边框 opacity 显式压成 0。
   rect 的 width 默认是 1、opacity 默认 255 —— 只设 fill_opacity 的话，
   半透明填充外面还套一圈 100% 不透明的 1px 边框：
   层层叠加的渐变色带会变成"百叶窗"，云和光晕会有一圈硬描边。
]]

local M = {}

-- ==================== 数学 / 颜色 ====================

function M.clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

function M.lerp(a, b, t)
    return a + (b - a) * t
end

function M.split(c)
    return math.floor(c / 65536) % 256, math.floor(c / 256) % 256, c % 256
end

function M.rgb(r, g, b)
    return math.floor(r + 0.5) * 65536 + math.floor(g + 0.5) * 256 + math.floor(b + 0.5)
end

--- 线性混色：t=0 → c1，t=1 → c2
function M.mix(c1, c2, t)
    t = M.clamp(t or 0, 0, 1)
    local r1, g1, b1 = M.split(c1)
    local r2, g2, b2 = M.split(c2)
    return M.rgb(r1 + (r2 - r1) * t, g1 + (g2 - g1) * t, b1 + (b2 - b1) * t)
end

--- k>0 向白靠，k<0 向黑靠
function M.shade(c, k)
    if k >= 0 then return M.mix(c, 0xFFFFFF, k) end
    return M.mix(c, 0x000000, -k)
end

--[[固定种子 LCG：同一份种子每次开机画出的星星/草丛完全一致，
问题可复现（math.random 做不到）。]]
function M.rng(seed)
    local s = math.floor(seed or 1) % 2147483647
    if s <= 0 then s = s + 2147483646 end
    return function()
        s = (s * 16807) % 2147483647
        return s / 2147483647
    end
end

function M.ease_out(t)
    local u = 1 - M.clamp(t, 0, 1)
    return 1 - u * u * u
end

function M.ease_in_out(t)
    t = M.clamp(t, 0, 1)
    if t < 0.5 then return 4 * t * t * t end
    local u = -2 * t + 2
    return 1 - u * u * u / 2
end

local function I(v, def)
    if v == nil then return def or 0 end
    return math.floor(v)
end
M.int = I

-- ==================== 图元池 ====================

--- 创建图元池
--- @return table P  P.items 交给 shape:set_items，P:reset()/P:finish() 包住一帧
function M.pool()
    local items, n, maxn = {}, 0, 0
    local P = { items = items }

    local function slot(kind)
        n = n + 1
        local t = items[n]
        if t == nil then
            t = {}
            items[n] = t
            if n > maxn then maxn = n end
        end
        t.type = kind
        return t
    end

    --[[共用字段清一遍：保证每个图元都显式带上全部键，不继承上一帧状态]]
    local function reset_common(t)
        t.color = 0xFFFFFF
        t.width = 1
        t.opacity = 255
        t.dash_width = 0
        t.dash_gap = 0
        t.round_start = false
        t.round_end = false
        t.rounded = false
        t.fill = false
        t.fill_color = 0xFFFFFF
        t.fill_opacity = 0
        t.x, t.y, t.w, t.h, t.radius = 0, 0, 0, 0, 0
        t.cx, t.cy, t.r, t.rx, t.ry, t.segments = 0, 0, 0, 0, 0, 0
        t.x1, t.y1, t.x2, t.y2 = 0, 0, 0, 0
        t.start_angle, t.end_angle = 0, 0
    end

    function P:reset() n = 0 end
    function P:size() return n end

    function P:finish()
        for i = n + 1, maxn do items[i] = nil end
        maxn = n
        return n
    end

    --- 直线（round=true 两端圆头）
    function P:line(x1, y1, x2, y2, color, width, opa, round)
        local t = slot("line")
        reset_common(t)
        t.x1, t.y1 = I(x1), I(y1)
        t.x2, t.y2 = I(x2), I(y2)
        t.color = color or 0xFFFFFF
        t.width = math.max(1, I(width, 1))
        t.opacity = I(opa, 255)
        t.round_start = round and true or false
        t.round_end = round and true or false
        return t
    end

    --- 实心（圆角）矩形
    function P:box(x, y, w, h, color, opa, radius)
        local t = slot("rect")
        reset_common(t)
        t.x, t.y = I(x), I(y)
        t.w, t.h = math.max(0, I(w)), math.max(0, I(h))
        t.radius = math.max(0, I(radius, 0))
        t.color = color or 0xFFFFFF
        t.fill = true
        t.fill_color = t.color
        t.fill_opacity = I(opa, 255)
        t.opacity = 0    -- 纯填充，不要那圈 1px 实边框（见文件头第 3 条）
        return t
    end

    --- 空心（圆角）矩形
    function P:frame(x, y, w, h, color, width, opa, radius)
        local t = P:box(x, y, w, h, color, 0, radius)
        t.width = math.max(1, I(width, 1))
        t.opacity = I(opa, 255)
        return t
    end

    --- 实心圆点
    function P:dot(cx, cy, r, color, opa)
        local t = slot("circle")
        reset_common(t)
        t.cx, t.cy = I(cx), I(cy)
        t.r = math.max(0, I(r))
        t.color = color or 0xFFFFFF
        t.fill = true
        t.fill_color = t.color
        t.fill_opacity = I(opa, 255)
        t.opacity = 0    -- 同上：只要填充
        return t
    end

    --[[空心圆环
    LVGL 的 circle 描边按「外半径」算，这里对外的语义是「带宽中心线半径」，
    所以内部补半个带宽 —— 这样刻度、轮圈、光晕都能用同一个半径直接叠。]]
    function P:ring(cx, cy, r, color, width, opa)
        local t = slot("circle")
        reset_common(t)
        local w = math.max(1, I(width, 1))
        t.cx, t.cy = I(cx), I(cy)
        t.r = math.max(0, I(r) + math.floor(w / 2))
        t.color = color or 0xFFFFFF
        t.width = w
        t.opacity = I(opa, 255)
        return t
    end

    --- 椭圆（fill=true 为实心）
    function P:ellipse(cx, cy, rx, ry, color, width, opa, fill, fill_opa, segs)
        local t = slot("ellipse")
        reset_common(t)
        t.cx, t.cy = I(cx), I(cy)
        t.rx, t.ry = math.max(0, I(rx)), math.max(0, I(ry))
        t.segments = math.max(3, I(segs, 24))
        t.color = color or 0xFFFFFF
        t.width = math.max(1, I(width, 1))
        -- 实心椭圆默认不要描边；要描边就显式传 opa
        t.opacity = fill and I(opa, 0) or I(opa, 255)
        t.fill = fill and true or false
        t.fill_color = t.color
        t.fill_opacity = fill and I(fill_opa, 255) or 0
        return t
    end

    --[[圆弧（弧度可圆头）
    r 按「带宽中心线」给；角度制，0 度在 3 点钟方向、顺时针增大。]]
    function P:arc(cx, cy, r, a0, a1, color, width, opa, rounded)
        local t = slot("arc")
        reset_common(t)
        local w = math.max(1, I(width, 4))
        t.cx, t.cy = I(cx), I(cy)
        t.r = math.max(0, I(r) + math.floor(w / 2))
        t.start_angle, t.end_angle = I(a0), I(a1)
        t.color = color or 0xFFFFFF
        t.width = w
        t.opacity = I(opa, 255)
        t.rounded = rounded and true or false
        t.round_start = t.rounded
        t.round_end = t.rounded
        return t
    end

    --- n 点折线（两个坐标数组，避免每帧建点元组）
    function P:poly(xs, ys, cnt, color, width, opa, round)
        if cnt < 2 then return end
        for i = 2, cnt do
            P:line(xs[i - 1], ys[i - 1], xs[i], ys[i], color, width, opa, round)
        end
    end

    --[[折线圆弧：大半径用短线段逼近
    lv_draw_arc 的绘制区域是「圆心 ± r」的整个方框，与扫角无关；
    大弧每帧重绘代价极高，所以半径大时改用折线，代价只与弧带实际面积成正比。]]
    function P:arc_poly(cx, cy, r, a0, a1, color, width, opa, step)
        local span = a1 - a0
        if span == 0 then return end
        local w = math.max(1, I(width, 6))
        local stepv = step or 6
        local n_seg = math.max(1, math.ceil(math.abs(span) / stepv))
        local extra = (opa or 255) >= 240 and ((1.5 / (r > 1 and r or 1)) * 57.29578) or 0
        for i = 0, n_seg - 1 do
            local b0 = a0 + span * (i / n_seg) - ((i == 0) and 0 or extra)
            local b1 = a0 + span * ((i + 1) / n_seg) + ((i == n_seg - 1) and 0 or extra)
            local t = P:line(cx + math.cos(math.rad(b0)) * r, cy + math.sin(math.rad(b0)) * r,
                cx + math.cos(math.rad(b1)) * r, cy + math.sin(math.rad(b1)) * r,
                color, w, opa, false)
            if t then
                t.round_start = (i == 0)
                t.round_end = (i == n_seg - 1)
            end
        end
    end

    --- 整圆折线环（底噪光环 / 涟漪）
    function P:ring_poly(cx, cy, r, color, width, opa, step)
        P:arc_poly(cx, cy, r, 0, 360, color, width, opa, step or 8)
    end

    return P
end

return M
