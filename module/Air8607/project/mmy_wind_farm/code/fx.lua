--[[
@module  fx
@summary 北岭风电场 - 绘图图元池与配色工具
@version 1.0
@date    2026.11.09

=== 这一层解决什么 ===
1、图元对象池：每帧重建上百个图元表，如果每帧新建 Lua 表，GC 周期性回收会带来
   肉眼可见的顿卡。池子复用同一批表，finish() 把尾部残留置 nil ——
   shape:set_items 用 lua_rawlen 取长度，尾部若留着上一帧的表，那些图元会被
   原样再画一遍（典型症状：故障机复机了，红框还挂在屏上）。
   同理每个写入方法都重写该图元的**全部字段**，不依赖"上一帧的默认值"。

2、颜色：风速低到高要连续过渡，写死色值做不出渐变，mix 够用。

=== 约定 ===
坐标一律取整：C 层读整型字段用 lua_tointeger，传 3.7 这类非整数浮点会静默得到 0，
宽度变 0 会被夹成 1，透明度变 0 就直接看不见。所以所有整型字段进表前都过一遍 I()。
]]

local M = {}

-- ==================== 数学 ====================
function M.clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function I(v, def)
    if v == nil then return def or 0 end
    return math.floor(v)
end
M.int = I

-- 角度规整到 [0, 360)
function M.deg(a)
    a = a % 360
    if a < 0 then a = a + 360 end
    return a
end

-- ==================== 配色 ====================
function M.rgb(r, g, b)
    return math.floor(r + 0.5) * 65536 + math.floor(g + 0.5) * 256 + math.floor(b + 0.5)
end

function M.split(c)
    return math.floor(c / 65536) % 256, math.floor(c / 256) % 256, c % 256
end

-- 线性混色：t=0 取 c1，t=1 取 c2
function M.mix(c1, c2, t)
    t = M.clamp(t or 0, 0, 1)
    local r1, g1, b1 = M.split(c1)
    local r2, g2, b2 = M.split(c2)
    return M.rgb(r1 + (r2 - r1) * t, g1 + (g2 - g1) * t, b1 + (b2 - b1) * t)
end

-- ==================== 图元池 ====================
--[[
@return table P
  P.items        图元数组（交给 shape:set_items）
  P:reset()      开始新的一帧
  P:finish()     结束本帧，清空尾部残留并返回图元数组
  写入方法：
    P:line(x1,y1,x2,y2,color,width,opa,round)      直线（round=true 两端圆头）
    P:neon(x1,y1,x2,y2,color,width,opa)           霓虹灯管（宽暗光晕 + 细亮灯芯）
    P:dash(x1,y1,x2,y2,color,width,opa,dw,dg)     虚线
    P:dot(cx,cy,r,color,opa)                       实心圆
    P:ring(cx,cy,r,color,width,opa)                空心圆环（r 是带宽中心线半径）
    P:arc(cx,cy,r,a1,a2,color,width,opa,round)     圆弧（角度单位度，0 在 3 点钟，顺时针）
    P:box(x,y,w,h,color,opa,radius)                实心（圆角）矩形
    P:frame(x,y,w,h,color,width,opa,radius)        空心（圆角）矩形
    P:poly(xs,ys,n,color,width,opa,round)          n 点折线
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

    function P:reset() n = 0 end
    function P:size() return n end

    function P:finish()
        for i = n + 1, maxn do items[i] = nil end
        maxn = n
        return items
    end

    function P:line(x1, y1, x2, y2, color, width, opa, round)
        local t = slot()
        t.type = "line"
        t.x1 = math.floor(x1)
        t.y1 = math.floor(y1)
        t.x2 = math.floor(x2)
        t.y2 = math.floor(y2)
        t.color = color or 0xFFFFFF
        t.width = I(width, 1)
        if t.width < 1 then t.width = 1 end
        t.opacity = I(opa, 255)
        t.dash_width = 0
        t.dash_gap = 0
        t.round_start = round and true or false
        t.round_end = round and true or false
        t.fill = false
        t.fill_color = t.color
        t.fill_opacity = 0
        return t
    end

    -- 霓虹灯管：宽而暗的底光 + 细而亮的灯芯，深色底上模拟发光
    function P:neon(x1, y1, x2, y2, color, width, opa)
        width = I(width, 2)
        opa = I(opa, 255)
        P:line(x1, y1, x2, y2, color, width * 3, math.floor(opa * 0.16), true)
        return P:line(x1, y1, x2, y2, color, width, opa, true)
    end

    function P:dash(x1, y1, x2, y2, color, width, opa, dw, dg)
        local t = P:line(x1, y1, x2, y2, color, width, opa, false)
        t.dash_width = I(dw, 6)
        t.dash_gap = I(dg, 6)
        return t
    end

    function P:dot(cx, cy, r, color, opa)
        local t = slot()
        t.type = "circle"
        t.cx = math.floor(cx)
        t.cy = math.floor(cy)
        t.r = math.floor(r)
        if t.r < 0 then t.r = 0 end
        t.color = color or 0xFFFFFF
        t.width = 1
        t.opacity = I(opa, 255)
        t.dash_width = 0
        t.dash_gap = 0
        t.round_start = false
        t.round_end = false
        t.fill = true
        t.fill_color = t.color
        t.fill_opacity = I(opa, 255)
        return t
    end

    -- 空心圆环：circle 在 fill=false 时走整圈 border，radius 是外半径，
    -- 所以按带宽中心线 r 换算成 r + width/2
    function P:ring(cx, cy, r, color, width, opa)
        local t = slot()
        local w = I(width, 1)
        if w < 1 then w = 1 end
        t.type = "circle"
        t.cx = math.floor(cx)
        t.cy = math.floor(cy)
        t.r = math.floor(r) + math.floor(w / 2 + 0.5)
        t.color = color or 0xFFFFFF
        t.width = w
        t.opacity = I(opa, 255)
        t.dash_width = 0
        t.dash_gap = 0
        t.round_start = false
        t.round_end = false
        t.fill = false
        t.fill_color = t.color
        t.fill_opacity = 0
        return t
    end

    -- 圆弧：C 层角度以 3 点钟为 0、顺时针增大；起止相同不画，差 360 以上画整圆
    function P:arc(cx, cy, r, a1, a2, color, width, opa, round)
        local t = slot()
        t.type = "arc"
        t.cx = math.floor(cx)
        t.cy = math.floor(cy)
        t.r = math.floor(r)
        if t.r < 1 then t.r = 1 end
        t.start_angle = math.floor(a1)
        t.end_angle = math.floor(a2)
        t.color = color or 0xFFFFFF
        t.width = I(width, 1)
        if t.width < 1 then t.width = 1 end
        t.opacity = I(opa, 255)
        t.dash_width = 0
        t.dash_gap = 0
        t.rounded = round and true or false
        t.round_start = t.rounded
        t.round_end = t.rounded
        t.fill = false
        t.fill_color = t.color
        t.fill_opacity = 0
        return t
    end

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
        t.fill_color = t.color
        t.fill_opacity = I(opa, 255)
        return t
    end

    function P:frame(x, y, w, h, color, width, opa, radius)
        local t = P:box(x, y, w, h, color, 0, radius)
        t.width = I(width, 1)
        if t.width < 1 then t.width = 1 end
        t.opacity = I(opa, 255)
        return t
    end

    -- n 点折线：xs / ys 由调用方持有（复用表，避免每次建元组）
    function P:poly(xs, ys, cnt, color, width, opa, round)
        if cnt < 2 then return end
        for i = 2, cnt do
            P:line(xs[i - 1], ys[i - 1], xs[i], ys[i], color, width, opa, round)
        end
    end

    return P
end

-- ==================== 复合图元 ====================

-- 水平量条：暗轨 + 发光填充 + 端点光点
function M.meter(P, x, y, w, h, frac, color, track)
    P:box(x, y, w, h, track or 0x102428, 255, math.floor(h / 2))
    frac = M.clamp(frac, 0, 1)
    local fw = math.floor(w * frac)
    if fw >= 2 then
        P:box(x, y, fw, h, color, 235, math.floor(h / 2))
        P:dot(x + fw, y + h / 2, math.floor(h * 0.9), color, 50)
        P:dot(x + fw, y + h / 2, math.max(1, math.floor(h * 0.32)), color, 215)
    end
end

-- 竖向量条（机组砖块右侧的"出力刻度"用这个）
function M.vmeter(P, x, y, w, h, frac, color, track)
    P:box(x, y, w, h, track or 0x102428, 255, math.floor(w / 2))
    frac = M.clamp(frac, 0, 1)
    local fh = math.floor(h * frac)
    if fh >= 2 then
        P:box(x, y + h - fh, w, fh, color, 235, math.floor(w / 2))
    end
end

-- 小箭头：在 (x,y) 处按角度 dir（度，0 指右）画一个 V 形
function M.arrow(P, x, y, dir, len, color, width, opa)
    local a = math.rad(dir)
    P:line(x, y, x - math.cos(a - 0.5) * len, y - math.sin(a - 0.5) * len, color, width, opa, true)
    P:line(x, y, x - math.cos(a + 0.5) * len, y - math.sin(a + 0.5) * len, color, width, opa, true)
end

--[[风机转子
@param number ang 弧度，0 表示一片叶片指向正右
画法：轮毂实心点 + 三片圆头长线（主轴）+ 每条主轴上一条更暗的弦线，
      远处看就是"三叶片、带一点桨距"的剪影，比纯线条更有金属感。
@param number r 转子半径（叶片长度）
]]
function M.rotor(P, cx, cy, r, ang, color, width, opa)
    for k = 0, 2 do
        local a = ang + k * 2.0943951        -- 120 度一片
        local ca, sa = math.cos(a), math.sin(a)
        local tx, ty = cx + ca * r, cy + sa * r
        P:line(cx, cy, tx, ty, color, width, opa, true)
        -- 弦线：垂直于主轴偏移 1.6px，把叶片"加宽"一点点
        local ox, oy = -sa * 1.6, ca * 1.6
        local hx, hy = cx + ca * r * 0.22, cy + sa * r * 0.22
        P:line(hx + ox, hy + oy, tx + ox * 0.4, ty + oy * 0.4, color, 1, math.floor(opa * 0.55))
    end
    P:dot(cx, cy, math.max(2, math.floor(r * 0.13)), color, 255)
    P:dot(cx, cy, math.max(1, math.floor(r * 0.06)), 0x000000, 160)
end

--[[风向玫瑰的花瓣
@param number ang 气象方位角（度）：0 = 北，顺时针
@param number len 花瓣长度（从圆心算起）
画法：一根由内向外变粗的辐条 + 末端一段圆弧帽，视觉上就是极坐标直方图的一瓣。
]]
function M.petal(P, cx, cy, ang, len, color, width, opa)
    local a = math.rad(ang - 90)            -- 屏幕坐标：0 = 12 点钟方向
    local ca, sa = math.cos(a), math.sin(a)
    local tx, ty = cx + ca * len, cy + sa * len
    P:line(cx + ca * 4, cy + sa * 4, tx, ty, color, width, opa, true)
    P:arc(cx, cy, len, ang - 90 - 7, ang - 90 + 7, color, width, opa, true)
    P:dot(tx, ty, math.max(1, math.floor(width / 2)), color, math.min(255, opa + 30))
end

return M
