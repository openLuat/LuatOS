--[[
@module  fx
@summary EV DASH - 绘图工具库（图元池 / 颜色 / 缓动 / 圆弧）
@version 1.0
@date    2026.10.23
@author  江访

=== 这一层解决什么 ===
1、图元对象池：每帧要重建上百个图元表，如果每帧新建 Lua 表，GC 周期性回收
   会带来肉眼可见的顿卡。池子复用同一批表，finish() 把尾部残留置 nil
   —— shape:set_items 用 lua_rawlen 取长度，尾部若留旧表会把上一帧的图元也画出来。
   同理每个写入方法都重写该图元的**全部字段**，不依赖"上一帧的默认值"。

2、颜色：弧光需要"随进度连续变化"的颜色，写死色值做不出渐变。
   HSL → RGB 按 hue 插值即可得到光谱渐变；mix/shade 做亮度分层。

3、缓动：指针/数字/弧长全部走缓动，观感才"贵"。

=== 关于 arc 图元（本工程的核心）===
airui.shape 自 2026.10.22 起支持 arc 图元（lv_draw_arc 直出），
坐标系与 LVGL 一致：0 度在 3 点钟方向，顺时针为正，y 轴向下。
即：135 度在左下、270 度在正上、405 度（=45 度）在右下。
弧宽从半径向内长（r 是外沿），两端圆头用 rounded=true。

性能提醒：arc 的绘制区域是"圆心 ± r"的整个方框（内部用角度掩膜裁剪），
一个弧的代价远大于一条直线。所以本工程只在"必须圆滑"的地方用 arc：
速度弧（3 段渐变色）、两侧小环（电量 / 功率）、两条装饰弧，
刻度线、折线、条形全部用 line / circle / rect 这类便宜的图元。

=== 约定 ===
图元坐标一律取整（math.floor）：LVGL 用整数坐标绘制，
小数坐标会在 C 层被静默截断（lua_tointeger 取不到整数就得到 0），
宽度变 0、透明度变 0 都会让物件"凭空消失"。
]]

local M = {}

M.TAU = math.pi * 2
M.DEG = math.pi / 180

-- ==================== 配色 ====================
M.C = {
    bg      = 0x05070E,  -- 全屏底色
    deep    = 0x080C18,  -- 舞台底色
    panel   = 0x0D1424,  -- 面板
    panel2  = 0x131E33,  -- 按钮底
    line    = 0x24365A,  -- 分隔/描边
    cyan    = 0x22E6FF,
    violet  = 0xA855F7,
    magenta = 0xFF3D9A,
    amber   = 0xFFB020,
    green   = 0x2BE59B,
    blue    = 0x3B82F6,
    red     = 0xFF5252,
    txt     = 0xDCE7F7,
    dim     = 0x76879F,
    dim2    = 0x47566F,
    ink     = 0x04121C,  -- 亮色底上的文字色
}

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
    local k = 1 - (1 - rate) ^ (dt * 60)
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

--[[一维平滑值噪声 0..1：让演示曲线的起伏不平铺直叙]]
function M.noise1(x)
    local i = math.floor(x)
    local f = x - i
    local u = f * f * (3 - 2 * f)
    return M.lerp(hash1(i), hash1(i + 1), u)
end

-- ==================== 图元池 ====================
--[[C 层读取整型字段用的是 lua_tointeger：传入 3.7 这种非整数浮点会直接得到 0
（Lua 5.3 只接受"整数值的浮点"）。宽度变 0 会被夹成 1，透明度变 0 就直接看不见了。
所以所有整型字段在写进图元表之前都过一遍这个取整，杜绝这类静默失效。]]
local function I(v, def)
    if v == nil then return def or 0 end
    return math.floor(v)
end
M.int = I

--[[
@return table P 图元池
  P.items        直接交给 shape:set_items()
  P:reset()      开始新的一帧
  P:finish()     结束本帧，返回图元个数（并清空尾部残留）
  写入方法：
    P:line(x1,y1,x2,y2,color,width,opa,round)      直线（round=true 两端圆头）
    P:neon(x1,y1,x2,y2,color,width,opa)           霓虹灯管（宽暗光晕 + 细亮灯芯）
    P:dash(x1,y1,x2,y2,color,width,opa,dw,dg)     虚线
    P:dot(cx,cy,r,color,opa)                       实心圆（r 是外半径）
    P:ring(cx,cy,r,color,width,opa)                空心圆环（r 是带宽中心线半径）
    P:box(x,y,w,h,color,opa,radius)                实心（圆角）矩形
    P:frame(x,y,w,h,color,width,opa,radius)        空心（圆角）矩形
    P:ellipse(cx,cy,rx,ry,color,width,opa,segs)    空心椭圆
    P:arc(cx,cy,r,a0,a1,color,width,opa,rounded)   圆弧（r 是带宽中心线半径，角度制）
    P:arc_grad(cx,cy,r,a0,a1,segs,c1,c2,width,opa) 分段渐变圆弧
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
        return n
    end

    -- 直线：所有字段一次性写全
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

    --[[霓虹灯管：一条宽而暗的底光 + 一条细而亮的灯芯
    深色底上用两条同色不同宽的线叠出"发光"，比真高斯模糊便宜一个数量级。]]
    function P:neon(x1, y1, x2, y2, color, width, opa)
        width = I(width, 2)
        opa = I(opa, 255)
        P:line(x1, y1, x2, y2, color, width * 3, math.floor(opa * 0.20), true)
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

    --[[半径换算：LVGL 的 lv_draw_arc 把 dsc.radius 当成"外半径"，
    实心弧带落在 [r-width, r]，而不是 [r-width/2, r+width/2]。
    本工程对外统一按"带宽中心线半径"给（直觉、且和刻度/弧头亮点同一个半径），
    写进图元表时在这里补半个带宽，否则整条弧会比设计位置内缩半个带宽，
    弧头亮点（按中心线半径算的坐标）就会跑到弧带外面去。]]
    local function arc_outer(r, w)
        local v = math.floor(r) + math.floor(w / 2 + 0.5)
        if v < 0 then v = 0 end
        return v
    end

    --[[空心圆环：整圆走 lv_draw_arc 的"整圈即 border"快路径，
    比用 arc 图元画 0..360 便宜得多，适合做轨道、外框、涟漪。]]
    function P:ring(cx, cy, r, color, width, opa)
        local t = slot()
        local w = I(width, 1)
        if w < 1 then w = 1 end
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
        t.fill_color = t.color
        t.fill_opacity = 0
        return t
    end

    --[[折线弧：用一串带端帽的短线段拼出弧带
    @param number step 角度步长（度），弦长 = r*step*π/180
    @param function color_fn 可选，function(t) → 该段颜色，t 为 0..1（逐段渐变）

    为什么大弧要用折线而不是 arc 图元：
    lv_draw_arc 的绘制区域是"圆心 ± r"的整圆方框（r=221 时 472²=22 万像素），
    内部再用角度掩膜裁剪，**与弧的扫角无关**。放在每帧重绘的图层里，
    5 条弧就是 110 万像素的掩膜 + 混合，真机（PSRAM 帧缓冲）直接 3fps。
    折线的代价只与弧带实际面积成正比（带宽 22、展开 1100px ≈ 2.4 万像素），
    步长取到弦长 < 带宽时相邻段自然重叠、接缝是亚像素级，看不出折线。
    小半径的环（卡片里 84x84 的环）仍用 arc，那点面积无所谓，圆度更好。
    ]]
    function P:arc_poly(cx, cy, r, a0, a1, color, width, opa, step, color_fn)
        local span = a1 - a0
        if span == 0 then return end
        local w = I(width, 8)
        if w < 1 then w = 1 end
        local stepv = step or 3
        local n = math.max(1, math.ceil(math.abs(span) / stepv))
        --[[相邻线段必须"重叠"而不是"对接"：LVGL 的线段是抗锯齿绘制的，
        两段共端点时两侧边缘各覆盖一半，会露出一条更暗的细线（看起来像竹节）。
        所以在内部分界处各多画 1.5px，用邻段的不透明内部盖住那条缝。
        半透明的弧不能重叠（重叠处会被混合两次而变亮），只能保持对接。]]
        local extra = 0
        if (opa or 255) >= 240 then
            extra = (1.5 / (r > 1 and r or 1)) * 57.29578   -- 1.5px 对应的角度
        end
        for i = 0, n - 1 do
            local t0 = i / n
            local t1 = (i + 1) / n
            local b0 = a0 + span * t0 - ((i == 0) and 0 or extra)
            local b1 = a0 + span * t1 + ((i == n - 1) and 0 or extra)
            local x1 = cx + math.cos(math.rad(b0)) * r
            local y1 = cy + math.sin(math.rad(b0)) * r
            local x2 = cx + math.cos(math.rad(b1)) * r
            local y2 = cy + math.sin(math.rad(b1)) * r
            local t = P:line(x1, y1, x2, y2, color_fn and color_fn((t0 + t1) * 0.5) or color, w, opa, false)
            if t then
                t.round_start = (i == 0)
                t.round_end = (i == n - 1)
            end
        end
    end

    -- 折线圆环（整圆）：给底噪光环、涟漪这类用
    function P:ring_poly(cx, cy, r, color, width, opa, step)
        P:arc_poly(cx, cy, r, 0, 360, color, width, opa, step or 4)
    end

    --[[圆弧（原生 arc 图元）
    @param number r 半径，按"带宽中心线"给（内部会补半个带宽换成 LVGL 的外半径）
    @param number a0,a1 起止角度，单位度。0 度在 3 点钟方向，顺时针增大。
           允许超过 360（如 135..405），C 层会自行折算；起止相同则不画。
    @param bool rounded 两端圆头（弧带宽 > 12 时建议开）
    ]]
    function P:arc(cx, cy, r, a0, a1, color, width, opa, rounded)
        local t = slot()
        local w = I(width, 8)
        if w < 1 then w = 1 end
        t.type = "arc"
        t.cx = math.floor(cx)
        t.cy = math.floor(cy)
        t.r = arc_outer(r, w)
        t.start_angle = math.floor(a0)
        t.end_angle = math.floor(a1)
        t.color = color or 0xFFFFFF
        t.width = w
        t.opacity = I(opa, 255)
        -- arc 只认 rounded 一个开关，但 round_start/round_end 也会被 C 层读取，
        -- 这里一并写死，避免池子复用上一帧的圆头状态
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

    --[[分段渐变圆弧：把 a0..a1 切成 segs 段，逐段线性插值 c1 → c2
    相邻段共用端点（并额外overlap 0.5 度），全不透明时看不出接缝。
    段数只影响参差程度：18 段在 270 度上每段 15 度，弧长 r=210 时约 55px，
    肉眼已看不出色阶，再细分只是白白多画几次掩膜。
    ]]
    function P:arc_grad(cx, cy, r, a0, a1, segs, c1, c2, width, opa)
        segs = I(segs, 18)
        if segs < 1 then segs = 1 end
        local step = (a1 - a0) / segs
        for i = 0, segs - 1 do
            local s0 = a0 + step * i
            local s1 = s0 + step + (i < segs - 1 and 0.5 or 0)
            local col = M.mix(c1, c2, segs == 1 and 1 or (i / (segs - 1)))
            P:arc(cx, cy, r, s0, s1, col, width, opa, false)
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

-- ==================== 复合图元 ====================

--[[水平能量条：暗轨道 + 发光填充 + 光晕端点
@param table P 图元池
@param number x,y,w,h 几何
@param number frac 0..1 进度
@param number color 填充色
]]
function M.meter(P, x, y, w, h, frac, color)
    frac = M.clamp(frac, 0, 1)
    P:box(x, y, w, h, 0x101A26, 200, math.floor(h / 2))
    local fw = w * frac
    if fw >= 2 then
        P:box(x, y, fw, h, color, 235, math.floor(h / 2))
        P:dot(x + fw, y + h / 2, math.floor(h * 0.95), color, 60)
        P:dot(x + fw, y + h / 2, math.floor(h * 0.45), M.shade(color, 0.6), 190)
    end
end

--[[迷你折线图：把 0..1 的序列画进给定矩形
@param table vals 长度为 n 的缓冲区（值域 0..1）
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

--[[屏幕角度换算：把"进度 0..1"映射到扫角 a0..a1
@param number t 0..1
@param number a0,a1 角度制起止
@return number 角度（度）
]]
function M.sweep(t, a0, a1)
    return a0 + M.clamp(t, 0, 1) * (a1 - a0)
end

return M
