--[[
@module  fx
@summary UAV GCS - 绘图工具库（图元池 / 颜色 / 缓动 / 3D 投影）
@version 1.0
@date    2026.11.02

=== 这一层解决什么 ===
1、图元对象池：姿态页每帧要重建 250~350 个图元（地平仪扫描填充、刻度尺、3D 机体），
   如果每帧新建 Lua 表，一秒就是上万张临时表，GC 周期回收会带来肉眼可见的顿卡。
   池子复用同一批表，finish() 时把尾部残留置 nil
   —— 因为 shape:set_items 用 lua_rawlen 取长度，尾部若留旧表会把上一帧的图元也画出来。
   同理每个写入方法都重写该图元的**全部字段**，不依赖"上一帧的默认值"。

2、颜色：地平仪的天地过渡、机臂的渐变、链路质量条都要"随数值连续变化"的颜色，
   写死色值不可能好看，mix/shade/hsl 三件套够了。

3、缓动：趋近用帧率无关的指数逼近（approach），页面元素进场用 ease_out，
   这样 30fps 的循环在掉帧时也不会"变慢"。

4、3D：把顶点做旋转矩阵 + 透视除法投到 2D，再用 line/dot 画出来。
   机体姿态、线框房间、航迹锥体全部走这一套。

=== 约定 ===
图元坐标一律取整（math.floor）：LVGL 用整数坐标绘制，
小数坐标会在 C 层被隐式截断，不同图元的截断方向不一致会导致接缝。
]]
local M = {}

M.TAU = math.pi * 2
local floor = math.floor

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
Lua 5.3 没有 math.pow，用 ^ 运算。
]]
function M.approach(cur, target, rate, dt)
    local k = 1 - (1 - rate) ^ (dt * 60)
    return cur + (target - cur) * k
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

--[[atan2 兜底：PC 与部分固件的 math 表里没有 math.atan2，
Lua 5.3 的双参 math.atan(y, x) 就是 atan2。]]
function M.atan2(y, x)
    if math.atan2 then return math.atan2(y, x) end
    return math.atan(y, x)
end

-- 角度差归一化到 (-180, 180]，用于"朝目标航向转弯"
function M.deg_delta(a, b)
    local d = (b - a) % 360
    if d > 180 then d = d - 360 end
    return d
end

-- ==================== 配色 ====================
function M.rgb(r, g, b)
    return floor(r + 0.5) * 65536 + floor(g + 0.5) * 256 + floor(b + 0.5)
end

function M.split(c)
    return floor(c / 65536) % 256, floor(c / 256) % 256, c % 256
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

--[[HSL → 0xRRGGBB，色相自动取模，可放心写 hue + t*30 做流动渐变]]
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
--[[固定种子 LCG：固定种子保证每次开机画面完全一致，问题可复现。]]
function M.rng(seed)
    local s = floor(seed or 1) % 2147483647
    if s <= 0 then s = s + 2147483646 end
    return function()
        s = (s * 16807) % 2147483647
        return s / 2147483647
    end
end

local function hash1(n)
    local v = math.sin(n * 127.1) * 43758.5453
    return v - floor(v)
end

-- 一维平滑值噪声 0..1：让抖动不平铺直叙
function M.noise1(x)
    local i = floor(x)
    local f = x - i
    local u = f * f * (3 - 2 * f)
    return M.lerp(hash1(i), hash1(i + 1), u)
end

-- ==================== 图元池 ====================
--[[
@return table P 图元池
  P.items        直接交给 shape:set_items()
  P:reset()      开始新的一帧
  P:finish()     结束本帧（清空尾部残留）
  写入方法：
    P:line(x1,y1,x2,y2,color,width,opa,round)   直线（round=true 两端圆头）
    P:dash(x1,y1,x2,y2,color,width,opa,dw,dg)   虚线
    P:dot(cx,cy,r,color,opa)                    实心圆
    P:ring(cx,cy,r,color,width,opa)             空心圆环
    P:box(x,y,w,h,color,opa,radius)             实心（圆角）矩形
    P:frame(x,y,w,h,color,width,opa,radius)     空心（圆角）矩形
    P:arc(cx,cy,r,a0,a1,color,width,opa,round)  真圆弧（原生 lv_draw_arc，不是折线逼近）
    P:ellipse(cx,cy,rx,ry,...)                  空心椭圆
    P:poly(xs,ys,n,color,width,opa,round)       n 点折线
]]
--[[C 层读取整型字段用的是 lua_tointeger：传入 3.7 这种非整数浮点会直接得到 0
（Lua 5.3 只接受"整数值的浮点"）。宽度变 0 会被夹成 1，透明度变 0 就直接看不见了。
所以所有整型字段在写进图元表之前都过一遍这个取整，杜绝这类静默失效。]]
local function I(v, def)
    if v == nil then return def or 0 end
    return floor(v)
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

    local function common(t, color, width, opa)
        t.color = color or 0xFFFFFF
        t.width = I(width, 1)
        if t.width < 1 then t.width = 1 end
        t.opacity = I(opa, 255)
        t.dash_width = 0
        t.dash_gap = 0
        t.round_start = false
        t.round_end = false
        t.fill = false
        t.fill_color = t.color
        t.fill_opacity = 0
    end

    -- 直线：所有字段一次性写全（见文件头"不依赖上一帧默认值"）
    function P:line(x1, y1, x2, y2, color, width, opa, round)
        local t = slot()
        t.type = "line"
        t.x1 = floor(x1)
        t.y1 = floor(y1)
        t.x2 = floor(x2)
        t.y2 = floor(y2)
        common(t, color, width, opa)
        if round then
            t.round_start = true
            t.round_end = true
        end
        return t
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
        t.cx = floor(cx)
        t.cy = floor(cy)
        t.r = floor(r)
        if t.r < 0 then t.r = 0 end
        common(t, color, 1, opa)
        t.fill = true
        t.fill_color = t.color
        t.fill_opacity = I(opa, 255)
        return t
    end

    function P:ring(cx, cy, r, color, width, opa)
        local t = slot()
        t.type = "circle"
        t.cx = floor(cx)
        t.cy = floor(cy)
        t.r = floor(r)
        if t.r < 0 then t.r = 0 end
        common(t, color, width, opa)
        return t
    end

    function P:box(x, y, w, h, color, opa, radius)
        local t = slot()
        t.type = "rect"
        t.x = floor(x)
        t.y = floor(y)
        t.w = floor(w)
        t.h = floor(h)
        if t.w < 0 then t.w = 0 end
        if t.h < 0 then t.h = 0 end
        t.radius = I(radius, 0)
        common(t, color, 1, 0)
        t.fill = true
        t.fill_color = t.color
        t.fill_opacity = I(opa, 255)
        return t
    end

    function P:frame(x, y, w, h, color, width, opa, radius)
        local t = P:box(x, y, w, h, color, 0, radius)
        common(t, color, width, opa)
        return t
    end

    --[[真圆弧：shape 自 2026.10.22 起支持 arc 图元（lv_draw_arc 直出）。
    角度单位为度，0 度在 3 点钟方向、顺时针增大；起止角相差 360 视为整圆。
    比"用折线逼近"省几十个图元，而且任意扫角都是真圆。]]
    function P:arc(cx, cy, r, a0, a1, color, width, opa, rounded)
        local t = slot()
        t.type = "arc"
        t.cx = floor(cx)
        t.cy = floor(cy)
        t.r = floor(r)
        t.start_angle = floor(a0)
        t.end_angle = floor(a1)
        common(t, color, width, opa)
        if rounded then
            t.round_start = true
            t.round_end = true
        end
        return t
    end

    function P:ellipse(cx, cy, rx, ry, color, width, opa, segs)
        local t = slot()
        t.type = "ellipse"
        t.cx = floor(cx)
        t.cy = floor(cy)
        t.rx = floor(rx)
        t.ry = floor(ry)
        if t.rx < 0 then t.rx = 0 end
        if t.ry < 0 then t.ry = 0 end
        t.segments = I(segs, 32)
        if t.segments < 3 then t.segments = 3 end
        common(t, color, width, opa)
        return t
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
--[[
相机模型：相机在 z = -d 处朝 +z 看，光心高度 y0，焦距 f。
  sx = cx + x * f / (z + d)
  sy = cy - (y - y0) * f / (z + d)
k = f / (z + d) 就是"每世界单位多少像素"，可直接当近大远小的亮度系数用。
]]
function M.proj3(x, y, z, cam)
    local zz = z + cam.d
    if zz < 0.45 then zz = 0.45 end
    local k = cam.f / zz
    return cam.cx + x * k, cam.cy - (y - cam.y0) * k, k
end

--[[绕三个轴旋转：先偏航（绕 y），再俯仰（绕 x），最后横滚（绕 z）
@param number x,y,z 模型坐标
@param number cy,sy 偏航 cos/sin
@param number cp,sp 俯仰 cos/sin
@param number cr,sr 横滚 cos/sin
@return number x, y, z
]]
function M.rot3(x, y, z, cy, sy, cp, sp, cr, sr)
    -- 偏航
    local x1 = x * cy + z * sy
    local z1 = -x * sy + z * cy
    -- 俯仰（绕 x 轴，抬头为正）
    local y1 = y * cp - z1 * sp
    local z2 = y * sp + z1 * cp
    -- 横滚（绕 z 轴，右滚为正）
    local x2 = x1 * cr - y1 * sr
    local y2 = x1 * sr + y1 * cr
    return x2, y2, z2
end

return M
