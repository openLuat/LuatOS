--[[
@module  fx
@summary 汤姆猫 - 绘图工具库（图元池 / 缓动 / 颜色 / 多边形扫描填充）
@version 1.0
@date    2026.10.25
@author  蒋骞

=== 这一层解决什么 ===
1、图元池：动态层每帧要重算 30~60 个图元，如果每帧新建 Lua 表，一秒就是
   2000+ 临时表，GC 周期回收会带来肉眼可见的顿卡。池子复用同一批表，
   finish() 时把尾部残留置 nil —— shape:set_items 用 lua_rawlen 取长度，
   尾部留旧表会把上一帧的图元一起画出来。所以每个写入方法都重写该图元的
   **全部字段**，不依赖"上一帧的默认值"。

2、原点偏移：图元坐标是相对 shape 左上角的，但猫的几何都用屏幕绝对坐标更
   好读。pool(ox, oy) 在写入时统一减掉原点，调用方永远写绝对坐标。

3、整型化：C 层读图元字段用的是 lua_tointeger，传入 3.7 这种非整数浮点会
   直接得到 0 —— 不报错，只是那个物件"凭空消失"。所以所有整型字段一律先
   math.floor。注意 set_pos/set_color 走 luaL_checkinteger，传小数会直接
   抛错并重启 VM（见 aurora_ui README 的记录），所以对象位置也全部取整。

4、多边形：LVGL 的 shape 只支持 line/circle/ellipse/rect/arc，没有多边形。
   猫耳朵、鼻头这类三角面用扫描线自己填（每行一条 line），因为它们画在
   静态层只画一次，成本可以忽略。
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

-- 三次缓出：起步快、尾部慢，适合"扑过来"的位移
function M.ease_out(t)
    local u = 1 - M.clamp(t, 0, 1)
    return 1 - u * u * u
end

-- 回弹缓出：尾端轻微过冲，爪子收回时有一点弹性
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

--[[帧率无关的指数趋近：每秒收敛 rate 比例
@param number cur 当前值
@param number target 目标值
@param number rate 0..1，越大越快
@param number dt 帧间隔秒
]]
function M.approach(cur, target, rate, dt)
    local k = 1 - (1 - rate) ^ (dt * 60)
    return cur + (target - cur) * k
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

--[[提亮 / 压暗：k>0 向白靠，k<0 向黑靠]]
function M.shade(c, k)
    if k >= 0 then return M.mix(c, 0xFFFFFF, k) end
    return M.mix(c, 0x000000, -k)
end

--[[固定种子 LCG，返回 function() -> 0..1
固定种子保证每次开机画面一致，问题可复现（math.random 做不到）。]]
function M.rng(seed)
    local s = math.floor(seed or 1) % 2147483647
    if s <= 0 then s = s + 2147483646 end
    return function()
        s = (s * 16807) % 2147483647
        return s / 2147483647
    end
end

-- ==================== 图元池 ====================
local function I(v, def)
    if v == nil then return def or 0 end
    return math.floor(v)
end
M.int = I

--[[
创建一个图元池
@number ox 原点 X（写入的绝对坐标会减去它）
@number oy 原点 Y
@return table P 图元池
  P.items        直接交给 shape:set_items()
  P:reset()      开始新的一帧
  P:finish()     结束本帧，返回图元个数（并清空尾部残留）
  写入方法：
    P:line(x1,y1,x2,y2,color,width,opa,round)        直线（round=true 两端圆头）
    P:dot(cx,cy,r,color,opa)                         实心圆
    P:ring(cx,cy,r,color,width,opa)                  空心圆
    P:ellipse_fill(cx,cy,rx,ry,color,opa)            实心椭圆
    P:ellipse(cx,cy,rx,ry,color,width,opa)           空心椭圆
    P:box(x,y,w,h,color,opa,radius)                  实心（圆角）矩形
    P:frame(x,y,w,h,color,width,opa,radius)          空心（圆角）矩形
    P:poly_fill(pts,color,opa)                       任意多边形扫描填充（pts 为 {x1,y1,x2,y2,...}）
]]
function M.pool(ox, oy)
    ox, oy = ox or 0, oy or 0
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

    -- 绝对坐标 → 图层坐标（并取整）
    local function X(v) return math.floor(v - ox) end
    local function Y(v) return math.floor(v - oy) end

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
        t.x1 = math.floor(x1 - ox)
        t.y1 = math.floor(y1 - oy)
        t.x2 = math.floor(x2 - ox)
        t.y2 = math.floor(y2 - oy)
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

    function P:dot(cx, cy, r, color, opa)
        local t = slot()
        t.type = "circle"
        t.cx = X(cx)
        t.cy = Y(cy)
        t.r = I(r, 0)
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

    function P:ring(cx, cy, r, color, width, opa)
        local t = slot()
        t.type = "circle"
        t.cx = X(cx)
        t.cy = Y(cy)
        t.r = I(r, 0)
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
        t.fill_color = t.color
        t.fill_opacity = 0
        return t
    end

    function P:ellipse_fill(cx, cy, rx, ry, color, opa)
        local t = slot()
        t.type = "ellipse"
        t.cx = X(cx)
        t.cy = Y(cy)
        t.rx = I(rx, 0)
        t.ry = I(ry, 0)
        if t.rx < 0 then t.rx = 0 end
        if t.ry < 0 then t.ry = 0 end
        t.segments = 0            -- 0 = 交给 C 层按半径推荐段数
        t.color = color or 0xFFFFFF
        t.width = 1
        t.opacity = 255
        t.dash_width = 0
        t.dash_gap = 0
        t.round_start = false
        t.round_end = false
        t.fill = true
        t.fill_color = t.color
        t.fill_opacity = I(opa, 255)
        return t
    end

    function P:ellipse(cx, cy, rx, ry, color, width, opa)
        local t = slot()
        t.type = "ellipse"
        t.cx = X(cx)
        t.cy = Y(cy)
        t.rx = I(rx, 0)
        t.ry = I(ry, 0)
        if t.rx < 0 then t.rx = 0 end
        if t.ry < 0 then t.ry = 0 end
        t.segments = 0
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

    function P:box(x, y, w, h, color, opa, radius)
        local t = slot()
        t.type = "rect"
        t.x = math.floor(x - ox)
        t.y = math.floor(y - oy)
        t.w = I(w, 0)
        t.h = I(h, 0)
        if t.w < 0 then t.w = 0 end
        if t.h < 0 then t.h = 0 end
        t.radius = I(radius, 0)
        if t.radius < 0 then t.radius = 0 end
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

    --[[任意多边形实心填充（扫描线）
    只适合凸多边形或简单凹多边形：每行取所有边的交点，取最小/最大之间填满。
    pts 为扁平的 {x1,y1,x2,y2,...}，顶点按顺序给出。
    ]]
    function P:poly_fill(pts, color, opa)
        local np = #pts / 2
        if np < 3 then return end
        local ymin, ymax = 1e9, -1e9
        for i = 1, np do
            local y = pts[i * 2]
            if y < ymin then ymin = y end
            if y > ymax then ymax = y end
        end
        local y0 = math.floor(ymin + 0.5)
        local y1 = math.floor(ymax)
        local xs = {}
        for y = y0, y1 do
            local k = 0
            for i = 1, np do
                local j = i % np + 1
                local ax, ay = pts[i * 2 - 1], pts[i * 2]
                local bx, by = pts[j * 2 - 1], pts[j * 2]
                if (ay <= y and by > y) or (by <= y and ay > y) then
                    k = k + 1
                    xs[k] = ax + (y - ay) * (bx - ax) / (by - ay)
                end
            end
            if k >= 2 then
                local lo, hi = xs[1], xs[1]
                for m = 2, k do
                    if xs[m] < lo then lo = xs[m] end
                    if xs[m] > hi then hi = xs[m] end
                end
                if hi - lo >= 0.5 then
                    P:line(lo + ox, y + oy, hi + ox, y + oy, color, 1, opa)
                end
            end
        end
    end

    -- 多边形描边（闭合）
    function P:poly_line(pts, color, width, opa, round)
        local np = #pts / 2
        if np < 2 then return end
        for i = 1, np do
            local j = i % np + 1
            P:line(pts[i * 2 - 1] + ox, pts[i * 2] + oy,
                pts[j * 2 - 1] + ox, pts[j * 2] + oy, color, width, opa, round)
        end
    end

    return P
end

return M
