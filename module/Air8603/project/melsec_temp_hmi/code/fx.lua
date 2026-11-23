--[[
@module  fx
@summary 图元绘制工具层：图元池 / 颜色 / 缓动 / 复合图元
@note
  === 为什么要有这一层 ===
  AirUI 的容器 + label 只能堆矩形和文字，做不出弧、辉光、渐变。
  airui.shape 才是真正的画布：一次 set_items 可以提交几十上百个图元，
  由 LVGL 直接光栅化。所以本工程的"卡片"一律是 shape，文字用 label 叠在上面。

  === 三个必须遵守的约束（都是踩过的坑） ===
  1、坐标必须取整。C 层用 lua_tointeger 读字段，Lua 5.3 只接受"整数值的浮点",
     传 3.7 会静默得到 0 —— 线宽变 0、透明度变 0，物件直接消失。
  2、每帧重建上百个表会让 GC 周期性卡顿。图元池复用同一批表，
     finish() 把尾部残留置 nil（set_items 用 lua_rawlen 取长度，
     尾部留旧表会把上一帧的图元一起画出来）。
  3、rect 的 x2 = x + w 是含端点的，想"正好铺满"要传 w - 1。

  === arc 图元 ===
  坐标系与 LVGL 一致：0 度在 3 点钟方向，顺时针为正，y 轴向下。
  135 度在左下、270 度在正上、405 度（=45 度）在右下。
  r 是**外半径**，弧带落在 [r-width, r]。本模块对外统一按"带宽中心线半径"给，
  写进图元表时补半个带宽，这样刻度、弧头亮点、弧带三者用同一个半径算，不会错位。
]]

local M = {}

M.TAU = math.pi * 2
M.PI  = math.pi

-- ==================== 数学 ====================
function M.clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

function M.lerp(a, b, t) return a + (b - a) * t end

-- 帧率无关的指数趋近：每秒收敛 rate 比例
function M.approach(cur, target, rate, dt)
    local k = 1 - (1 - rate) ^ (dt * 60)
    return cur + (target - cur) * k
end

function M.ease_out(t)
    local u = 1 - M.clamp(t, 0, 1)
    return 1 - u * u * u
end

function M.ease_back(t)
    t = M.clamp(t, 0, 1)
    local u = t - 1
    local s = 1.70158
    return 1 + (s + 1) * u * u * u + s * u * u
end

function M.ease_in_out(t)
    t = M.clamp(t, 0, 1)
    if t < 0.5 then return 4 * t * t * t end
    local u = -2 * t + 2
    return 1 - u * u * u / 2
end

-- ==================== 颜色 ====================
function M.rgb(r, g, b)
    return math.floor(r + 0.5) * 65536 + math.floor(g + 0.5) * 256 + math.floor(b + 0.5)
end

function M.split(c)
    return math.floor(c / 65536) % 256, math.floor(c / 256) % 256, c % 256
end

function M.mix(c1, c2, t)
    t = M.clamp(t or 0, 0, 1)
    local r1, g1, b1 = M.split(c1)
    local r2, g2, b2 = M.split(c2)
    return M.rgb(r1 + (r2 - r1) * t, g1 + (g2 - g1) * t, b1 + (b2 - b1) * t)
end

-- k>0 向白靠，k<0 向黑靠
function M.shade(c, k)
    if k >= 0 then return M.mix(c, 0xFFFFFF, k) end
    return M.mix(c, 0x000000, -k)
end

local function hue2ch(p, q, t)
    if t < 0 then t = t + 1 end
    if t > 1 then t = t - 1 end
    if t < 1 / 6 then return p + (q - p) * 6 * t end
    if t < 1 / 2 then return q end
    if t < 2 / 3 then return p + (q - p) * (2 / 3 - t) * 6 end
    return p
end

function M.hsl(h, s, l)
    h = ((h or 0) % 360) / 360
    s = M.clamp(s or 1, 0, 1)
    l = M.clamp(l or 0.5, 0, 1)
    if s <= 0 then
        local v = l * 255
        return M.rgb(v, v, v)
    end
    local q = (l < 0.5) and (l * (1 + s)) or (l + s - l * s)
    local p = 2 * l - q
    return M.rgb(hue2ch(p, q, h + 1 / 3) * 255,
                 hue2ch(p, q, h) * 255,
                 hue2ch(p, q, h - 1 / 3) * 255)
end

-- ==================== 图元池 ====================
local function I(v, def)
    if v == nil then return def or 0 end
    return math.floor(v)
end
M.int = I

--[[
@return table P 图元池
  P.items   直接交给 shape:set_items()
  P:reset() 开始新的一帧
  P:finish() 结束本帧（清空尾部残留）
  P:line(x1,y1,x2,y2,color,width,opa,round)
  P:neon(x1,y1,x2,y2,color,width,opa)        宽暗光晕 + 细亮灯芯
  P:dash(x1,y1,x2,y2,color,width,opa,dw,dg)
  P:dot(cx,cy,r,color,opa)
  P:ring(cx,cy,r,color,width,opa)
  P:box(x,y,w,h,color,opa,radius)
  P:frame(x,y,w,h,color,width,opa,radius)
  P:arc(cx,cy,r,a0,a1,color,width,opa,rounded)
  P:poly(xs,ys,n,color,width,opa,round)
  P:vgrad(x,y,w,h,c1,c2,steps)              竖向渐变（多条 1px 横线插值）
  P:hline / P:vline                          便捷等宽线
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
        return n
    end

    function P:line(x1, y1, x2, y2, color, width, opa, round)
        local t = slot()
        t.type = "line"
        t.x1 = math.floor(x1)
        t.y1 = math.floor(y1)
        t.x2 = math.floor(x2)
        t.y2 = math.floor(y2)
        t.color = color or 0xFFFFFF
        t.width = I(width, 1); if t.width < 1 then t.width = 1 end
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

    function P:neon(x1, y1, x2, y2, color, width, opa)
        width = I(width, 2)
        opa = I(opa, 255)
        P:line(x1, y1, x2, y2, color, width * 3, math.floor(opa * 0.18), true)
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
        t.r = math.floor(r); if t.r < 0 then t.r = 0 end
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

    -- 统一换算：对外给中心线半径，写入时补半个带宽变成 LVGL 的外半径
    local function arc_outer(r, w)
        local v = math.floor(r) + math.floor(w / 2 + 0.5)
        if v < 0 then v = 0 end
        return v
    end

    function P:ring(cx, cy, r, color, width, opa)
        local t = slot()
        local w = I(width, 1); if w < 1 then w = 1 end
        t.type = "circle"
        t.cx = math.floor(cx)
        t.cy = math.floor(cy)
        t.r = arc_outer(r, w)
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

    function P:box(x, y, w, h, color, opa, radius)
        local t = slot()
        t.type = "rect"
        t.x = math.floor(x)
        t.y = math.floor(y)
        t.w = math.floor(w); if t.w < 0 then t.w = 0 end
        t.h = math.floor(h); if t.h < 0 then t.h = 0 end
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
        t.width = I(width, 1); if t.width < 1 then t.width = 1 end
        t.opacity = I(opa, 255)
        return t
    end

    function P:arc(cx, cy, r, a0, a1, color, width, opa, rounded)
        local t = slot()
        local w = I(width, 8); if w < 1 then w = 1 end
        t.type = "arc"
        t.cx = math.floor(cx)
        t.cy = math.floor(cy)
        t.r = arc_outer(r, w)
        t.start_angle = math.floor(a0)
        t.end_angle = math.floor(a1 + 0.5)
        t.color = color or 0xFFFFFF
        t.width = w
        t.opacity = I(opa, 255)
        t.rounded = rounded and true or false
        t.round_start = t.rounded
        t.round_end = t.rounded
        t.dash_width = 0
        t.dash_gap = 0
        t.fill = false
        t.fill_color = t.color
        t.fill_opacity = 0
        return t
    end

    function P:poly(xs, ys, cnt, color, width, opa, round)
        if cnt < 2 then return end
        for i = 2, cnt do
            P:line(xs[i - 1], ys[i - 1], xs[i], ys[i], color, width, opa, round)
        end
    end

    -- 竖向渐变：steps 条 1px 横线，颜色线性插值
    function P:vgrad(x, y, w, h, c1, c2, steps)
        steps = steps or h
        local sh = h / steps
        for i = 0, steps - 1 do
            local t = (steps > 1) and (i / (steps - 1)) or 0
            P:box(x, y + i * sh, w, math.ceil(sh) + 1, M.mix(c1, c2, t), 255, 0)
        end
    end

    function P:hline(x, y, w, color, opa)
        return P:line(x, y, x + w - 1, y, color, 1, opa or 255, false)
    end

    function P:vline(x, y, h, color, opa)
        return P:line(x, y, x, y + h - 1, color, 1, opa or 255, false)
    end

    return P
end

-- ==================== 复合图元 ====================

-- 圆弧进度：(进度 0..1) → 扫角
function M.sweep(t, a0, a1)
    return a0 + M.clamp(t, 0, 1) * (a1 - a0)
end

--[[水平能量条：暗轨道 + 发光填充 + 端点光斑
@param number frac 0..1 进度]]
function M.meter(P, x, y, w, h, frac, color)
    frac = M.clamp(frac, 0, 1)
    local r = math.floor(h / 2)
    P:box(x, y, w, h, 0x0A1420, 230, r)
    local fw = math.floor(w * frac)
    if fw >= 3 then
        P:box(x, y, fw, h, color, 235, r)
        P:dot(x + fw, y + h / 2, math.floor(h * 0.85), color, 45)
        P:dot(x + fw, y + h / 2, math.max(2, math.floor(h * 0.34)), M.shade(color, 0.55), 210)
    end
end

--[[迷你折线：把 0..1 的序列画进矩形（会复用 P 的点缓存，避免每帧建表）]]
function M.spark(P, vals, n, x, y, w, h, color, width, opa)
    if n < 2 then return end
    local xs, ys = P._sx, P._sy
    if not xs then
        xs, ys = {}, {}
        P._sx, P._sy = xs, ys
    end
    local step = w / (n - 1)
    for i = 1, n do
        xs[i] = x + (i - 1) * step
        ys[i] = y + h - M.clamp(vals[i], 0, 1) * h
    end
    P:poly(xs, ys, n, color, width or 1, opa or 200, true)
end

--[[环形表：轨道 + 进度弧 + 弧头光点
@param number cx,cy 环心  @param number r 中心线半径  @param number band 带宽
@param number t 进度 0..1  @param number color 进度色
@param number base 轨道色  @param number dim 收边细弧色
]]
function M.gauge(P, cx, cy, r, band, t, color, base, dim, a0, a1)
    a0 = a0 or 135
    a1 = a1 or 405
    P:arc(cx, cy, r, a0, a1, base, band, 255, true)
    P:arc(cx, cy, r + band / 2 + 3, a0, a1, dim, 1, 190, true)
    P:arc(cx, cy, r - band / 2 - 3, a0, a1, dim, 1, 140, true)

    local ang = M.sweep(t, a0, a1)
    if t > 0.0015 then
        -- 弧身：外层低透明宽弧做辉光，内层实弧做本体
        P:arc(cx, cy, r, a0, ang, color, band + 6, 26, true)
        P:arc(cx, cy, r, a0, ang, color, band, 255, true)
    end
    -- 弧头光斑
    local rad = ang * M.PI / 180
    local hx, hy = cx + math.cos(rad) * r, cy + math.sin(rad) * r
    P:dot(hx, hy, band * 0.95, color, 40)
    P:dot(hx, hy, band * 0.45, M.shade(color, 0.7), 235)
end

--[[只画进度部分（轨道/刻度已画在静态层）：宽弧做辉光 + 实弧做本体 + 弧头光斑
@param number t 进度 0..1]]
function M.progress(P, cx, cy, r, band, t, color, a0, a1)
    a0 = a0 or 135
    a1 = a1 or 405
    t = M.clamp(t, 0, 1)
    if t <= 0.002 then return end
    local ang = M.sweep(t, a0, a1)
    P:arc(cx, cy, r, a0, ang, color, band + 7, 24, true)
    P:arc(cx, cy, r, a0, ang, color, band, 255, true)
    local rad = ang * M.PI / 180
    local hx, hy = cx + math.cos(rad) * r, cy + math.sin(rad) * r
    P:dot(hx, hy, band * 0.95, color, 38)
    P:dot(hx, hy, band * 0.45, M.shade(color, 0.72), 240)
end

--[[刻度环：沿弧均匀排布短线，major 处更长更亮
@param number vmax 满量程  @param number step 小刻度间隔  @param number major 大刻度间隔]]
function M.ticks(P, cx, cy, r, band, a0, a1, vmax, step, major, c_major, c_minor)
    local v = 0
    while v <= vmax + 0.001 do
        local a = math.rad(M.sweep(v / vmax, a0, a1))
        local ca, sa = math.cos(a), math.sin(a)
        local isM = (math.floor(v / major + 0.5) * major == v)
        local r0 = r - band / 2 - 5
        local r1 = isM and (r0 - 8) or (r0 - 4)
        P:line(cx + ca * r0, cy + sa * r0, cx + ca * r1, cy + sa * r1,
            isM and c_major or c_minor, isM and 2 or 1, isM and 235 or 150, true)
        v = v + step
    end
end

return M
