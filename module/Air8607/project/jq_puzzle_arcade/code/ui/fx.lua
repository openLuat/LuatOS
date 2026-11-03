--[[
@module  fx
@summary 益智乐园 - 绘图工具库（图元池 / 颜色 / 缓动 / 图标）
@version 1.0
@date    2026.11.03

=== 这一层解决什么 ===
1、图元对象池：每帧要重建 200~500 个图元表，如果每帧新建 Lua 表，
   一秒就是上万个临时表，GC 周期性回收会带来肉眼可见的顿卡。
   池子复用同一批表，finish() 时把尾部残留置 nil
   —— 因为 shape:set_items 用 lua_rawlen 取长度，尾部若留旧表会把上一帧的图元也画出来。
   同理每个写入方法都重写该图元的**全部字段**，不依赖"上一帧的默认值"。

2、颜色：棋盘上的方块需要"按数值/按连通状态连续变化"的颜色，
   HSL → RGB 按 hue 插值即可得到光谱渐变；mix/shade 做亮度分层。

3、缓动与噪声：胜负动画、呼吸光晕、预览画面的起伏都靠这一层，
   不写死常量才能"活"起来。

4、图标：翻牌记忆要八种好认的图案，全部用 line/circle/rect 拼，
   零图片素材（hzfont 也缺大部分符号字形）。

=== 约定 ===
图元坐标一律取整（math.floor）：LVGL 用整数坐标绘制，
小数坐标会在 C 层被隐式截断，不同图元的截断方向不一致会导致接缝。
]]

local M = {}

M.TAU = math.pi * 2
M.DEG = math.pi / 180

-- ==================== 数学与缓动 ====================
function M.clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

function M.lerp(a, b, t)
    return a + (b - a) * t
end

--[[帧率无关的指数趋近：每秒收敛 rate 比例
@param number cur 当前值
@param number target 目标值
@param number rate 0..1，越大越快（0.12 约等于每帧收敛 12%）
@param number dt 帧间隔秒
]]
function M.approach(cur, target, rate, dt)
    local k = 1 - (1 - rate) ^ (dt * 60)   -- Lua5.3 没有 math.pow，用 ^
    return cur + (target - cur) * k
end

-- 三次缓出：起步快、尾部慢，最适合"滑入"类动画
function M.ease_out(t)
    local u = 1 - M.clamp(t, 0, 1)
    return 1 - u * u * u
end

-- 回弹缓出：尾端轻微过冲再回位
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

-- ==================== 配色 ====================
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

--[[提亮/压暗：k>0 向白靠，k<0 向黑靠]]
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

--[[HSL → 0xRRGGBB
@param number h 色相 0-360（自动取模，可放心写 hue + t*30 做流动渐变）
@param number s 饱和度 0-1
@param number l 亮度 0-1
]]
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

-- ==================== 随机与噪声 ====================
--[[固定种子 LCG，返回 function() -> 0..1
固定种子保证每次开局序列一致，问题可复现（math.random 做不到）。]]
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

--[[一维平滑值噪声 0..1：让呼吸、脉动不显得机械]]
function M.noise1(x)
    local i = math.floor(x)
    local f = x - i
    local u = f * f * (3 - 2 * f)
    return M.lerp(hash1(i), hash1(i + 1), u)
end

--[[呼吸系数 0..1（周期约 2 秒）
@param number t 秒
@param number phase 相位偏移（多个物件错开，避免整屏同频）
]]
function M.breathe(t, phase)
    return 0.5 + 0.5 * math.sin((t + (phase or 0)) * 3.1)
end

-- ==================== 图元池 ====================
--[[
@return table P 图元池
  P.items        直接交给 shape:set_items()
  P:reset()      开始新的一帧
  P:finish()     结束本帧，返回图元个数（并清空尾部残留）
  写入方法：
    P:line(x1,y1,x2,y2,color,width,opa,round)   直线（round=true 两端圆头）
    P:neon(x1,y1,x2,y2,color,width,opa)         霓虹灯管（宽暗光晕 + 细亮灯芯，2 个图元）
    P:dash(x1,y1,x2,y2,color,width,opa,dw,dg)   虚线
    P:dot(cx,cy,r,color,opa)                    实心圆
    P:ring(cx,cy,r,color,width,opa)             空心圆环
    P:glow(cx,cy,r,color,opa)                   三层实心圆堆出的光晕（3 个图元）
    P:box(x,y,w,h,color,opa,radius)             实心（圆角）矩形
    P:frame(x,y,w,h,color,width,opa,radius)     空心（圆角）矩形
    P:ellipse(cx,cy,rx,ry,color,width,opa,segs) 空心椭圆
    P:arc(cx,cy,r,a0,a1,segs,color,width,opa)   圆弧（用 segs 段折线逼近）
    P:poly(xs,ys,n,color,width,opa)             n 点折线（n-1 个图元）
]]
--[[C 层读取整型字段用的是 lua_tointeger：传入 3.7 这种非整数浮点会直接得到 0
（Lua 5.3 只接受"整数值的浮点"）。宽度变 0 会被夹成 1，透明度变 0 就直接看不见了。
所以所有整型字段在写进图元表之前都过一遍这个取整，杜绝这类静默失效。]]
local function I(v, def)
    if v == nil then return def or 0 end
    return math.floor(v)
end
M.int = I

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

    -- 直线：所有字段一次性写全（见文件头"不依赖上一帧默认值"）
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
        t.fill_color = color or 0xFFFFFF
        t.fill_opacity = 0
        return t
    end

    --[[霓虹灯管：一条宽而暗的底光 + 一条细而亮的灯芯
    深色底上用两条同色不同宽的线叠出"发光"，比真高斯模糊便宜一个数量级。]]
    function P:neon(x1, y1, x2, y2, color, width, opa)
        width = I(width, 2)
        opa = I(opa, 255)
        P:line(x1, y1, x2, y2, color, width * 3, math.floor(opa * 0.2), true)
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
        t.fill_color = color or 0xFFFFFF
        t.fill_opacity = I(opa, 255)
        return t
    end

    function P:ring(cx, cy, r, color, width, opa)
        local t = slot()
        t.type = "circle"
        t.cx = math.floor(cx)
        t.cy = math.floor(cy)
        t.r = math.floor(r)
        if t.r < 0 then t.r = 0 end
        t.color = color or 0xFFFFFF
        t.width = I(width, 1)
        if t.width < 1 then t.width = 1 end
        t.opacity = I(opa, 255)
        t.dash_width = 0
        t.dash_gap = 0
        t.round_start = false
        t.round_end = false
        t.fill = false
        t.fill_color = color or 0xFFFFFF
        t.fill_opacity = 0
        return t
    end

    --[[柔光：三层递减透明度的实心圆
    这套界面的底是奶油白，光晕不再是"发光"而是"彩色糖纸透出来的淡影"，
    所以透明度整体压低，避免在浅底上糊成一团。]]
    function P:glow(cx, cy, r, color, opa)
        opa = I(opa, 90)
        r = math.floor(r)
        P:dot(cx, cy, r, color, math.floor(opa * 0.2))
        P:dot(cx, cy, math.floor(r * 0.7), color, math.floor(opa * 0.34))
        P:dot(cx, cy, math.floor(r * 0.45), color, opa)
    end

    --[[卡片投影：浅底上的"贴纸"感，两层低透明度圆角矩形往下错开
    图元按顺序绘制，所以必须在卡片本体之前调用。]]
    function P:shadow(x, y, w, h, radius, opa)
        opa = I(opa, 44)
        radius = math.floor(radius or 14)
        local col = 0xE7D2AE
        P:box(x + 2, y + 6, w, h, col, math.floor(opa * 0.5), radius)
        P:box(x + 1, y + 3, w, h, col, opa, radius)
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
        t.fill_color = color or 0xFFFFFF
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

    function P:ellipse(cx, cy, rx, ry, color, width, opa, segs)
        local t = slot()
        t.type = "ellipse"
        t.cx = math.floor(cx)
        t.cy = math.floor(cy)
        t.rx = math.floor(rx)
        t.ry = math.floor(ry)
        if t.rx < 0 then t.rx = 0 end
        if t.ry < 0 then t.ry = 0 end
        t.segments = I(segs, 32)
        if t.segments < 12 then t.segments = 12 end
        t.color = color or 0xFFFFFF
        t.width = I(width, 1)
        if t.width < 1 then t.width = 1 end
        t.opacity = I(opa, 255)
        t.dash_width = 0
        t.dash_gap = 0
        t.round_start = false
        t.round_end = false
        t.fill = false
        t.fill_color = color or 0xFFFFFF
        t.fill_opacity = 0
        return t
    end

    --[[圆弧：用 segs 段折线逼近（shape 的 arc 图元只有描边，这里要的是可控宽度的弧）

    !!! 为什么不能每段都圆头 !!!
    每个小线段都用圆头画时，线宽 w 会在每个顶点处鼓出一个半径 w/2 的半圆帽。
    当相邻顶点间距（弦长 = 2r*sin(θ/2)）小于线宽 w 时，这些圆帽就会凸出到折线外侧，
    连成一串"珠子"。所以线段一律平头画，两端需要圆头时单独补两颗实心圆。

    @param bool cap0, cap1 两端是否补圆头（默认 true）
    ]]
    function P:arc(cx, cy, r, a0, a1, segs, color, width, opa, cap0, cap1)
        segs = I(segs, 24)
        if segs < 1 then segs = 1 end
        local step = (a1 - a0) / segs
        local px = cx + math.cos(a0) * r
        local py = cy + math.sin(a0) * r
        local a = a0
        for _ = 1, segs do
            a = a + step
            local x = cx + math.cos(a) * r
            local y = cy + math.sin(a) * r
            P:line(px, py, x, y, color, width, opa, false)
            px, py = x, y
        end
        width = I(width, 1)
        if cap0 ~= false then
            P:dot(cx + math.cos(a0) * r, cy + math.sin(a0) * r,
                math.floor(width / 2), color, opa)
        end
        if cap1 ~= false then
            P:dot(cx + math.cos(a1) * r, cy + math.sin(a1) * r,
                math.floor(width / 2), color, opa)
        end
    end

    -- n 点折线（点数组为两个表，避免每帧建 {x=,y=} 元组）
    function P:poly(xs, ys, cnt, color, width, opa, round)
        if cnt < 2 then return end
        for i = 2, cnt do
            P:line(xs[i - 1], ys[i - 1], xs[i], ys[i], color, width, opa, round)
        end
    end

    return P
end

-- ==================== 3D 透视（大厅预览用到一点点）====================
--[[旋转 + 透视投影
@param number vx,vy,vz 归一化模型坐标
@param number cax,sax 绕 X 轴旋转的 cos/sin
@param number cay,say 绕 Y 轴旋转的 cos/sin
@param number d 视距（越大透视越弱，常用 5~8）
@return number x, number y, number k 屏幕单位坐标与深度系数
]]
function M.project(vx, vy, vz, cax, sax, cay, say, d)
    local x1 = vx * cay - vz * say
    local z1 = vx * say + vz * cay
    local y2 = vy * cax - z1 * sax
    local z2 = vy * sax + z1 * cax
    local k = d / (d + z2)
    return x1 * k, y2 * k, k
end

-- ==================== 图标（翻牌记忆 / 大厅预览共用）====================
local ICON_N = 8

function M.icon_count()
    return ICON_N
end

--[[在 (cx,cy) 画一个半径 r 的图案，kind 1..8
八种图案刻意挑"轮廓差别大"的：点/环/三角/方/菱/十字/波浪/六边形，
在 60px 的卡片上一眼能分清；颜色由调用方按配对给。
]]
function M.icon(P, kind, cx, cy, r, color, opa)
    opa = I(opa, 255)
    color = color or 0xFFFFFF
    local w = math.max(2, math.floor(r * 0.24))

    if kind == 1 then          -- 实心点
        P:dot(cx, cy, math.floor(r * 0.72), color, opa)
    elseif kind == 2 then      -- 空心环
        P:ring(cx, cy, math.floor(r * 0.74), color, w, opa)
    elseif kind == 3 then      -- 三角形
        local pts = { -math.pi / 2, math.pi / 6, math.pi * 5 / 6 }
        for i = 1, 3 do
            local a1 = pts[i]
            local a2 = pts[i % 3 + 1]
            P:line(cx + math.cos(a1) * r * 0.86, cy + math.sin(a1) * r * 0.86,
                cx + math.cos(a2) * r * 0.86, cy + math.sin(a2) * r * 0.86,
                color, w, opa, true)
        end
    elseif kind == 4 then      -- 方形
        local s = math.floor(r * 0.72)
        P:frame(cx - s, cy - s, s * 2, s * 2, color, w, opa, 3)
    elseif kind == 5 then      -- 菱形
        local s = math.floor(r * 0.92)
        local s2 = math.floor(r * 0.58)
        P:line(cx, cy - s, cx + s2, cy, color, w, opa, true)
        P:line(cx + s2, cy, cx, cy + s, color, w, opa, true)
        P:line(cx, cy + s, cx - s2, cy, color, w, opa, true)
        P:line(cx - s2, cy, cx, cy - s, color, w, opa, true)
    elseif kind == 6 then      -- 十字
        P:line(cx - r * 0.8, cy, cx + r * 0.8, cy, color, w, opa, true)
        P:line(cx, cy - r * 0.8, cx, cy + r * 0.8, color, w, opa, true)
    elseif kind == 7 then      -- 波浪
        local xs, ys = P._ixs, P._iys
        if not xs then
            xs, ys = {}, {}
            P._ixs, P._iys = xs, ys
        end
        local n = 9
        for i = 1, n do
            local u = (i - 1) / (n - 1)
            xs[i] = cx + (u - 0.5) * 2 * r * 0.86
            ys[i] = cy + math.sin(u * math.pi * 2) * r * 0.46
        end
        P:poly(xs, ys, n, color, w, opa, true)
    else                       -- 六边形
        local xs, ys = P._ixs, P._iys
        if not xs then
            xs, ys = {}, {}
            P._ixs, P._iys = xs, ys
        end
        for i = 1, 6 do
            local a = -math.pi / 2 + (i - 1) * M.TAU / 6
            xs[i] = cx + math.cos(a) * r * 0.86
            ys[i] = cy + math.sin(a) * r * 0.86
        end
        xs[7] = xs[1]
        ys[7] = ys[1]
        P:poly(xs, ys, 7, color, w, opa, true)
    end
end

-- ==================== 水管臂（6x6 旋转接通）====================
-- 位标记：1=上 2=右 4=下 8=左
--[[把臂位图顺时针旋转 k 个 90 度
@param number mask 臂位图
@param number k 0..3
@return number 旋转后的位图
]]
function M.rot_mask(mask, k)
    k = ((k or 0) % 4 + 4) % 4
    local m = mask % 16
    for _ = 1, k do
        -- 上->右、右->下、下->左 都是"位值乘 2"，只有左(8) 旋转后回到上(1)
        local wrapped = (m >= 8) and 1 or 0
        m = (m * 2) % 16 + wrapped
    end
    return m
end

return M
