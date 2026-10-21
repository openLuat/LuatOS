--[[
@module  fx_core
@summary AirUI 视觉特效演示 - 基础工具库（配色 / 数学 / 图元对象池）
@version 1.0
@date    2026.10.21

=== 本模块解决三件事 ===

1. 颜色：特效要用“随时间变化的渐变色”，写死几十个色值既不现实也不好看。
   统一走 HSL → RGB，按 hue 随时间/位置插值即可得到连续的光谱渐变。

2. 确定性随机：星空、目标点、粒子初值必须在每次开机都一致，
   否则每次烧录看到的画面都不同、不好复现问题。用固定种子的 LCG 而不是 math.random。

3. 图元对象池：每帧要重建 150+ 个图元表，直接建新表会产生
   150 x 30 = 4500 个临时表/秒，Lua GC 周期性回收时会带来肉眼可见的卡顿。
   这里复用同一批表，只在 finish() 时把尾部真正置 nil
   —— 因为 airui.shape 的 set_items 用 lua_rawlen 取长度，
   尾部若留着旧表，上一帧的残留图元会被一起画出来。
   同理，每个写入方法都会把该图元的**全部字段**重写一遍，
   不允许依赖“上一帧留下的默认值”。
]]
local M = {}

M.TAU = math.pi * 2

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
    txt     = 0xDCE7F7,
    dim     = 0x76879F,
    dim2    = 0x47566F,
    ink     = 0x04121C,  -- 亮色底上的文字色
}

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

-- ==================== 三角函数查表（性能关键） ====================
--[[为什么不用 math.sin / math.cos
特效每帧要调用三角函数 100~500 次（万花筒一层就是 8 折 x 5 段 x 4 次）。
math.sin 走 libm 软浮点实现，在没有硬 FPU 的 MCU 上一次要好几微秒，
实测本工程里三角函数最密的 gauge / kaleido 两个场景，单图元耗时
是三角函数最少的 spectrum 的两倍多 —— 这部分直接吃掉了一半帧预算。
这里预计算 512 项正弦表，运行时查表 + 线性插值，误差约 2e-5，
远小于一个像素，视觉上完全无差别，但快一个数量级。
]]
local TRIG_N = 512
local TRIG_SCALE = TRIG_N / M.TAU
local SIN_T = {}
for i = 0, TRIG_N do
    SIN_T[i] = math.sin(i * M.TAU / TRIG_N)
end

local HALF_PI = 1.5707963267948966

local function sin_lut(a)
    local f = (a * TRIG_SCALE) % TRIG_N
    local i = math.floor(f)
    local t = f - i
    local s0 = SIN_T[i]
    return s0 + (SIN_T[i + 1] - s0) * t
end

local function cos_lut(a)
    return sin_lut(a + HALF_PI)
end

--[[默认走 math.sin / math.cos，而不是查表
这里踩过一次坑：一开始直接把查表当成优化全量替换，结果在 PC 上反而更慢
（kaleido 单帧 497us -> 760us）—— PC 有硬 FPU，libm 的 sin 本身就很快，
而 Lua 侧查表要付出乘法、取模、两次表索引的解释器开销，得不偿失。
真正的收益来自上面的和角公式把调用次数降下来（kaleido 431 -> 约 50 次），
调用次数降下来之后，用哪种实现差别就不大了。
如果真机实测发现 libm 确实慢（软浮点 MCU），用 M.use_trig_lut(true) 切到查表，
再实测一次对比即可，不用改调用点。]]
local trig_sin, trig_cos = math.sin, math.cos

function M.sin(a) return trig_sin(a) end
function M.cos(a) return trig_cos(a) end

--[[切换三角函数实现
@param bool on true 用查表版，false 用 math 版（默认）
]]
function M.use_trig_lut(on)
    if on then
        trig_sin, trig_cos = sin_lut, cos_lut
    else
        trig_sin, trig_cos = math.sin, math.cos
    end
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

--[[一维平滑值噪声，返回 0..1；用于让节奏变化不平铺直叙]]
function M.noise1(x)
    local i = math.floor(x)
    local f = x - i
    local u = f * f * (3 - 2 * f)
    return M.lerp(hash1(i), hash1(i + 1), u)
end

-- ==================== 图元对象池 ====================

--[[
@return P 图元池对象
  P.items           —— 直接交给 shape:set_items() 的数组
  P:reset()         —— 开始新的一帧
  P:finish()        —— 结束本帧，返回图元个数（并把尾部残留清空）
  P:line / dash / dot / ring / box / frame / ellipse
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
        t.radius = radius or 0
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

    -- 空心椭圆（注意：填充椭圆在 C 层是逐行画线实现的，代价很高，这里只提供描边）
    function P:ellipse(cx, cy, rx, ry, color, width, opa, segments)
        local t = slot()
        t.type = "ellipse"
        t.cx = math.floor(cx)
        t.cy = math.floor(cy)
        t.rx = math.floor(rx)
        t.ry = math.floor(ry)
        if t.rx < 0 then t.rx = 0 end
        if t.ry < 0 then t.ry = 0 end
        t.segments = segments or 32
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

    return P
end

return M
