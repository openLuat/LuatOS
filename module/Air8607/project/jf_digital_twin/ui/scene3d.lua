--[[
@module  scene3d
@summary DIGITAL TWIN - 透视相机与 3D 复合图元（地面网格 / 光柱 / 环 / 流光）
@version 1.0
@date    2026.10.23
@author  江访

=== 这一层解决的问题 ===
airui.shape 只有 line / circle / rect / ellipse 四种图元，**没有多边形填充**。
想在实拍风格的车间底图上画出"确实站在地面上"的网格、光柱和光流，
只有一条路：自己算透视，把三维点投到二维，再用线/点/矩形拼出来。

=== 相机模型 ===
世界坐标 x 向右、y 向上（地面 y=0）、z 向前。相机在 (0, eye_h, -dist)，
先按 yaw 绕 Y 轴转，再按 pitch 绕 X 轴俯，最后做透视除法：

    k  = focal / z_cam          -- 透视缩放
    sx = cx + x_cam * k
    sy = cy - y_cam * k

pitch = atan(eye_h / dist) 时地平线正好压在主点 cy 上（本工程 y=292），
所以"远处的东西往 cy 收敛"是相机算出来的，不是手摆的。

=== 为什么全部走同一个 project() ===
地面网格、光柱底座、热点环、流光路径共用一套相机，
它们的灭点、近大远小、亮度衰减才是自洽的；
任何一种"手工摆坐标"的做法，一动视角就会露馅。

=== 图元预算 ===
一帧的地面层控制在 140 个图元以内（见 readme 的图元预算表）：
网格 16 条线 + 扫描高亮 6 条 + 4 根光柱 48 + 3 条光流 30 + 3 个热点环 24。
]]

local fx = require "fx"
local T = require "theme"

local M = {}

local cam = T.cam
local CP, SP = math.cos(cam.pitch), math.sin(cam.pitch)

-- 每帧可复用的临时表（避免每帧新建 -> GC 顿卡）
local bx, by, bk = {}, {}, {}
local bxn, byn = 0, 0

--[[三维点 -> 屏幕点
@param number x,y,z 世界坐标（地面 y=0）
@return number sx, sy 屏幕坐标
@return number k 透视缩放（1.0 ≈ 原点平面），用来做亮度/粗细衰减
]]
function M.project(x, y, z)
    local dy = y - cam.eye_h
    local dz = z + cam.dist
    -- 绕 X 轴俯 θ：y' = dy*cosθ + dz*sinθ，z' = -dy*sinθ + dz*cosθ
    -- 符号写反的话原点不会落在主点上（地平线跟着歪），透视就全错。
    local ry = dy * CP + dz * SP
    local rz = -dy * SP + dz * CP
    if rz < 0.35 then rz = 0.35 end   -- 别让点跑到相机背后
    local k = cam.focal / rz
    return cam.cx + x * k, cam.cy - ry * k, k
end

-- 把 z 换算成 0..1 的深度比（0 最近，1 最远），用于亮度衰减
local Z_NEAR, Z_FAR = -1.0, 13.0
local function depth(z)
    local t = (z - Z_NEAR) / (Z_FAR - Z_NEAR)
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
    return t
end
M.depth = depth

--[[地面网格
@param table P 图元池
@param number t 时间（秒），驱动扫描高亮
@param number x0,x1 横向范围
@param number z0,z1 纵向范围
@param number step 格距
]]
function M.grid(P, t, x0, x1, z0, z1, step, base_col, hi_col)
    local d
    -- 沿 z 走的线（把 x 固定）
    local x = x0
    while x <= x1 + 0.001 do
        local x1s, y1s, k1 = M.project(x, 0, z0)
        local x2s, y2s, k2 = M.project(x, 0, z1)
        d = 1 - 0.55 * depth((z0 + z1) * 0.5)
        local opa = math.floor(96 * d)
        if opa > 4 then
            P:line(x1s, y1s, x2s, y2s, base_col, 1, opa)
        end
        x = x + step
    end

    -- 沿 x 走的线（把 z 固定）：越近越亮，扫描带经过时提亮
    local z = z0
    local scanZ = z0 + ((t * 1.35) % (z1 - z0))
    while z <= z1 + 0.001 do
        local xa, ya = M.project(x0, 0, z)
        local xb, yb = M.project(x1, 0, z)
        d = 1 - depth(z)
        local opa = math.floor((34 + 104 * d * d))
        local col, w = base_col, 1
        local dz = math.abs(z - scanZ)
        if dz < 0.65 then
            -- 扫描带：一条随 z 前移的高亮线，替掉网格线（不加图元）
            col = hi_col
            opa = math.floor(opa * (1.35 - dz))
            w = 2
        end
        if opa > 4 then
            P:line(xa, ya, xb, yb, col, w, opa > 255 and 255 or opa)
        end
        z = z + step
    end
    return P
end

--[[地面上的圆（透视后是椭圆，只能点串逼近）
@param number segs 分段数（6 段在 r 较小时已经看不出棱角）
]]
function M.ring(P, x, z, r, color, width, opa, segs)
    segs = segs or 8
    local px, py
    for i = 0, segs do
        local a = i / segs * 6.283185307179586
        local sx, sy = M.project(x + math.cos(a) * r, 0, z + math.sin(a) * r)
        if i > 0 then
            P:line(px, py, sx, sy, color, width or 1, opa)
        end
        px, py = sx, sy
    end
end

--[[全息光柱：底座环 + 三层渐隐柱体 + 顶盖 + 顶部呼吸光点
这是"3D 感"的主力图元，一根约 12 个图元。
@param number h 柱高（世界单位）
@param number frac 0..1 填充比例（决定亮段的高度）
]]
function M.pillar(P, x, z, h, frac, color, t, phase)
    local d = depth(z)
    local dim = 1 - 0.45 * d
    local bh = h * (0.25 + 0.75 * fx.clamp(frac, 0, 1))
    local w = 0.16

    M.ring(P, x, z, w * 2.6, color, 1, math.floor(70 * dim), 10)

    -- 柱体：三层自下而上收窄的竖线，透明度递减，做出"体积光"的错觉
    local x0, y0, k0 = M.project(x - w, 0, z)
    local x1, y1 = M.project(x - w, bh, z)
    local x2, y2 = M.project(x + w, 0, z)
    local x3, y3 = M.project(x + w, bh, z)
    P:line(x0, y0, x1, y1, color, 2, math.floor(150 * dim))
    P:line(x2, y2, x3, y3, color, 2, math.floor(150 * dim))
    local xm, ym, km = M.project(x, 0, z)
    local xt, yt = M.project(x, bh, z)
    P:line(xm, ym, xt, yt, fx.shade(color, 0.55), 1, math.floor(80 * dim))

    -- 顶盖：一根横线 + 一颗呼吸光点
    P:line(x1, y1, x3, y3, color, 2, math.floor(220 * dim))
    local pulse = 0.6 + 0.4 * math.sin(t * 2.4 + (phase or 0))
    P:dot(xt, yt, 2 + 2 * pulse, color, math.floor(200 * dim))
    P:dot(xt, yt, math.floor(7 * pulse) + 3, color, math.floor(60 * dim))
    return P
end

--[[极简光柱：2 根竖线 + 顶横线 + 顶光点 + 底座点（5 个图元）
用在需要铺一片"数据林"的视图（能效态势 4x3 阵列），
比 pillar() 省一半图元，远看仍是柱体。
]]
function M.bar3d(P, x, z, h, color, t, phase, w)
    local d = depth(z)
    local dim = 1 - 0.5 * d
    w = w or 0.075
    local x0, y0 = M.project(x - w, 0, z)
    local x1, y1 = M.project(x - w, h, z)
    local x2, y2 = M.project(x + w, 0, z)
    local x3, y3 = M.project(x + w, h, z)
    P:line(x0, y0, x1, y1, color, 1, math.floor(130 * dim))
    P:line(x2, y2, x3, y3, color, 1, math.floor(130 * dim))
    P:line(x1, y1, x3, y3, color, 2, math.floor(210 * dim))
    local pulse = 0.55 + 0.45 * math.sin(t * 2.6 + (phase or 0))
    P:dot(x1, y1, math.floor(1 + 1.6 * pulse), color, math.floor(210 * dim))
    P:dot((x0 + x2) / 2, (y0 + y2) / 2, 2, color, math.floor(90 * dim))
end

--[[三段折线的地面光路 + 沿线奔跑的光点
@param table xs, zs 世界坐标数组（1..n）
@param number t 时间
@param number speed 光点速度（世界单位/秒）
]]
function M.flow(P, xs, zs, n, t, color, speed, dots, opa)
    -- 先把 n 个点预算好投影，避免重复 project
    for i = 1, n do
        bx[i], by[i], bk[i] = M.project(xs[i], 0, zs[i])
    end
    bxn = n
    for i = 2, n do
        local d = 1 - depth((zs[i - 1] + zs[i]) * 0.5)
        P:line(bx[i - 1], by[i - 1], bx[i], by[i], color, 1,
            math.floor((opa or 90) * (0.35 + 0.65 * d)))
    end

    -- 光点：按总长度均分，位置 = (t*speed) 对总长取模
    local total = 0
    local seg = {}
    for i = 2, n do
        local dx = xs[i] - xs[i - 1]
        local dz = zs[i] - zs[i - 1]
        seg[i] = math.sqrt(dx * dx + dz * dz)
        total = total + seg[i]
    end
    if total <= 0 then return end
    dots = dots or 3
    for i = 1, dots do
        local s = ((t * (speed or 1.6)) + (i - 1) * total / dots) % total
        local acc = 0
        for j = 2, n do
            if acc + seg[j] >= s then
                local u = (s - acc) / seg[j]
                local wx = xs[j - 1] + (xs[j] - xs[j - 1]) * u
                local wz = zs[j - 1] + (zs[j] - zs[j - 1]) * u
                local sx, sy = M.project(wx, 0, wz)
                local d = 1 - depth(wz)
                P:dot(sx, sy, 3, color, math.floor(230 * d))
                P:dot(sx, sy, 6, color, math.floor(58 * d))
                break
            end
            acc = acc + seg[j]
        end
    end
end

--[[线框立方体（设备占位）。只画看得见的三面棱，8 个顶点 9 条线。
@param number w,d 底面宽深，h 高
]]
function M.box(P, x, z, w, d, h, color, opa)
    local hw, hd = w / 2, d / 2
    local a, b, c, e = {}, {}, {}, {}
    -- 底面四点
    a[1], a[2] = M.project(x - hw, 0, z - hd)
    b[1], b[2] = M.project(x + hw, 0, z - hd)
    c[1], c[2] = M.project(x + hw, 0, z + hd)
    e[1], e[2] = M.project(x - hw, 0, z + hd)
    local a2, b2, c2, e2 = {}, {}, {}, {}
    a2[1], a2[2] = M.project(x - hw, h, z - hd)
    b2[1], b2[2] = M.project(x + hw, h, z - hd)
    c2[1], c2[2] = M.project(x + hw, h, z + hd)
    e2[1], e2[2] = M.project(x - hw, h, z + hd)
    local dd = 1 - depth(z)
    local o = math.floor(opa * (0.3 + 0.7 * dd))
    P:line(a[1], a[2], b[1], b[2], color, 1, o)
    P:line(b[1], b[2], c[1], c[2], color, 1, o)
    P:line(e[1], e[2], a[1], a[2], color, 1, o)
    P:line(a2[1], a2[2], b2[1], b2[2], color, 1, o)
    P:line(b2[1], b2[2], c2[1], c2[2], color, 1, o)
    P:line(e2[1], e2[2], a2[1], a2[2], color, 1, o)
    P:line(a[1], a[2], a2[1], a2[2], color, 1, o)
    P:line(b[1], b[2], b2[1], b2[2], color, 1, o)
    P:line(c[1], c[2], c2[1], c2[2], color, 1, o)
    P:line(e[1], e[2], e2[1], e2[2], color, 1, o)
end

--[[世界点 -> 屏幕点（对外暴露，视图层挂 label / 图片要算锚点）
@return number sx, sy, k
]]
function M.at(x, y, z)
    return M.project(x, y, z)
end

return M
