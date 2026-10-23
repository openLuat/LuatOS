--[[
@module  fx
@summary AURORA UI - 绘图工具库（图元池 / 颜色 / 缓动 / 3D 投影）
@version 1.0
@date    2026.10.22
@author  江访

=== 这一层解决什么 ===
1、图元对象池：每帧要重建 150~250 个图元表，如果每帧新建 Lua 表，
   一秒就是 7500 个临时表，GC 周期性回收会带来肉眼可见的顿卡。
   池子复用同一批表，finish() 时把尾部残留置 nil
   —— 因为 shape:set_items 用 lua_rawlen 取长度，尾部若留旧表会把上一帧的图元也画出来。
   同理每个写入方法都重写该图元的**全部字段**，不依赖"上一帧的默认值"。

2、颜色：特效需要"随位置/时间连续变化"的颜色，写死色值不可能好看。
   HSL → RGB 按 hue 插值即可得到光谱渐变；mix/shade 做亮度分层。

3、缓动：UI Store 里最复杂的过渡只有一条 220ms 的线性位移抽屉。
   这里提供 ease_out_cubic / ease_out_back / 临界阻尼弹簧，
   页面切换、指示器滑动、数值滚动全部走缓动，观感才"贵"。

4、3D：把顶点做旋转矩阵 + 透视除法投到 2D，再用 line/dot 画出来。
   全部 7 个 UI Store demo 都没有真正的 3D 透视。

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
@param number rate 0..1，越大越快（0.12 ≈ 每帧收敛 12%）
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

-- 回弹缓出：尾端轻微过冲再回位，适合指示器滑动
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

--[[临界阻尼弹簧：给惯性类交互用（拖拽松手后的滑行）
@param number x 位移
@param number v 速度
@param number target 目标
@param number k 刚度（越大回位越快，常用 8~20）
@param number dt 帧间隔秒
@return number x, number v 新的位移与速度
]]
function M.spring(x, v, target, k, dt)
    local a = (target - x) * k - v * (2 * math.sqrt(k))
    v = v + a * dt
    x = x + v * dt
    return x, v
end

-- 角度差归一化到 (-π, π]，用于最近方向旋转
function M.angle_delta(a, b)
    local d = (b - a) % M.TAU
    if d > math.pi then d = d - M.TAU end
    return d
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
固定种子保证每次开机画面完全一致，问题可复现（math.random 做不到）。]]
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

--[[一维平滑值噪声 0..1：让节拍与幅度变化不平铺直叙]]
function M.noise1(x)
    local i = math.floor(x)
    local f = x - i
    local u = f * f * (3 - 2 * f)
    return M.lerp(hash1(i), hash1(i + 1), u)
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
    P:box(x,y,w,h,color,opa,radius)             实心（圆角）矩形
    P:frame(x,y,w,h,color,width,opa,radius)     空心（圆角）矩形
    P:ellipse(cx,cy,rx,ry,color,width,opa,segs) 空心椭圆
    P:arc(cx,cy,r,a0,a1,segs,color,width,opa)   圆弧（用 segs 段折线逼近，产生 segs 个图元）
    P:poly(xs,ys,n,color,width,opa)             n 点折线（n-1 个图元）
    P:bars(...) 见 view_spectrum 里自建
]]
--[[C 层读取整型字段用的是 lua_tointeger：传入 3.7 这种非整数浮点会直接得到 0
（Lua 5.3 只接受"整数值的浮点"）。宽度变 0 会被夹成 1，透明度变 0 就直接看不见了。
所以所有整型字段在写进图元表之前都过一遍这个取整，杜绝这类静默失效
—— 它不会报错，只会在真机上出现"某个物件莫名消失"。]]
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
    深色底上用两条同色不同宽的线叠出"发光"，比真高斯模糊便宜一个数量级。
    @return table 灯芯图元]]
    function P:neon(x1, y1, x2, y2, color, width, opa)
        width = I(width, 2)
        opa = I(opa, 255)
        P:line(x1, y1, x2, y2, color, width * 3, math.floor(opa * 0.22), true)
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
        if t.segments < 3 then t.segments = 3 end
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

    --[[圆弧：用 segs 段折线逼近（shape 没有 arc 图元，只有 line/circle/rect/ellipse）

    !!! 为什么以前"看起来不圆" !!!
    每个小线段都用圆头（round_start/round_end）画时，线宽 w 会在每个顶点处
    鼓出一个半径 w/2 的半圆帽。当相邻顶点间距（弦长 = 2r·sin(θ/2)）小于线宽 w 时，
    这些圆帽就会凸出到折线外侧，连成一串"珠子"——半径 180、线宽 13、8 段跨 30°
    的红线区就是典型：弦长 11.8px < 13px，肉眼能数出 7 颗珠子。

    正确做法：
      1) 线段一律平头画（round=false），接缝处的楔形缺口只有 (w/2)·tan(θ/2)，
         13px 宽、10° 一段也就 0.6px，完全看不出来；
      2) 两端需要圆头时，单独补两颗直径 = 线宽的实心圆；
      3) 段数按"弦高"取：弦高 = r(1-cos(θ/2))，取 ≤0.5px 即可，
         r=180 时 θ≈8.5°，240° 的弧 28 段就够，再多纯属浪费图元。

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

-- ==================== 3D 透视 ====================
--[[旋转 + 透视投影
@param number vx,vy,vz 归一化模型坐标
@param number cax,sax 绕 X 轴旋转的 cos/sin
@param number cay,say 绕 Y 轴旋转的 cos/sin
@param number d 视距（越大透视越弱，常用 5~8）
@return number x, number y, number k  屏幕单位坐标（已乘 k，调用方再乘半径）与深度系数
]]
function M.project(vx, vy, vz, cax, sax, cay, say, d)
    local x1 = vx * cay - vz * say
    local z1 = vx * say + vz * cay
    local y2 = vy * cax - z1 * sax
    local z2 = vy * sax + z1 * cax
    local k = d / (d + z2)
    return x1 * k, y2 * k, k
end

--[[深度系数 → 0..1 亮度比
@param number k 投影得到的深度系数
@param number kmin 该模型的最小 k（最远处）
@param number kspan kmax - kmin
]]
function M.depth_t(k, kmin, kspan)
    if kspan <= 0 then return 1 end
    return M.clamp((k - kmin) / kspan, 0, 1)
end

-- ==================== 复合图元（卡片里复用的小部件） ====================

--[[水平能量条：暗轨道 + 发光填充 + 光晕端点
@param table P 图元池
@param number x,y,w,h 几何
@param number frac 0..1 进度
@param number color 填充色
]]
function M.meter(P, x, y, w, h, frac, color)
    frac = M.clamp(frac, 0, 1)
    P:box(x, y, w, h, 0x16233C, 190, math.floor(h / 2))
    local fw = w * frac
    if fw >= 2 then
        P:box(x, y, fw, h, color, 235, math.floor(h / 2))
        -- 端点光晕：一大一小两颗低透明度实心圆，视觉上像"正在发光的前沿"
        P:dot(x + fw, y + h / 2, math.floor(h * 0.95), color, 60)
        P:dot(x + fw, y + h / 2, math.floor(h * 0.45), M.shade(color, 0.6), 190)
    end
end

--[[迷你折线图：把 0..1 的序列画进给定矩形
@param table xs,ys 长度为 n 的缓冲区（值域 0..1 存 ys，xs 由本函数填）
@param number x,y,w,h 目标矩形
@param number base 序列最小值的屏幕 y（h 为满量程高度）
]]
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

--[[单位球的斐波那契格点（黄金角螺旋）
比经纬网格均匀，不会在两极堆积。一次算好，之后每帧只做旋转。
@param number n 点数
@param table xs, ys, zs 输出表（1..n）
]]
function M.fib_sphere(n, xs, ys, zs)
    local GA = 2.399963229728653   -- 黄金角 2π(1 - 1/φ)
    for i = 1, n do
        local vy = 1 - (i - 0.5) * 2 / n
        local r = math.sqrt(math.max(0, 1 - vy * vy))
        local th = i * GA
        xs[i] = r * math.cos(th)
        ys[i] = vy
        zs[i] = r * math.sin(th)
    end
end

return M
