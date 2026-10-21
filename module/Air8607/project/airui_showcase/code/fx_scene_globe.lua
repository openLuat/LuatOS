--[[
@module  fx_scene_globe
@summary AirUI 视觉特效 - 3D 星球（点云球体 + 倾斜轨道）
@version 1.0
@date    2026.10.21

@effect
44 颗按斐波那契球面均匀分布的点构成一颗自转的星球，点的大小与亮度随深度变化
（正对相机的更亮更大，转到背面的变暗变小），因此即使不做深度排序也有明确的体积感。
外加一圈赤道环和一条倾斜 55° 的卫星轨道，轨道上有一颗绕飞的亮点。
整帧约 6 次三角函数，85 个图元。

@note
球面点用斐波那契格点（黄金角螺旋）分布，比经纬网格更均匀，
也不会像经纬网格那样在两极堆成一坨。
]]
local fx = require "fx_core"

local M = {
    id = "globe",
    name = "3D 星球",
    desc = "点云球体自转，赤道环 + 倾斜卫星轨道",
}

local NP = 44          -- 球面点云数量
local NEQ = 20         -- 赤道环点数
local NORB = 18        -- 卫星轨道点数
local ORB_R = 1.40     -- 轨道半径（球半径为 1）
local ORB_TILT = 0.96  -- 轨道倾角约 55°

local VIEW_D = 6.0
-- 单位球的深度系数范围 [D/(D+1), D/(D-1)]
local K_MIN = VIEW_D / (VIEW_D + 1)
local K_SPAN = VIEW_D / (VIEW_D - 1) - K_MIN

function M.build(parent, W, H)
    local o = { w = W, h = H, pool = fx.pool() }
    o.shape = airui.shape({ parent = parent, x = 0, y = 0, w = W, h = H, items = {} })
    o.cx = W * 0.5
    o.cy = H * 0.5
    -- 轨道最大投影约 1.82R，取 0.24 保证不越过舞台上下沿
    o.R = math.min(W, H) * 0.24

    --[[球面点云：斐波那契格点
    y 均匀分层，每层按黄金角错开，得到近似均匀的球面分布。
    整场不变，build 时算一次即可。]]
    o.px3, o.py3, o.pz3 = {}, {}, {}
    local GA = 2.399963229728653     -- 黄金角 2π(1-1/φ)
    for i = 1, NP do
        local vy = 1 - (i - 0.5) * 2 / NP
        local rr = math.sqrt(math.max(0, 1 - vy * vy))
        local th = i * GA
        o.px3[i] = rr * math.cos(th)
        o.py3[i] = vy
        o.pz3[i] = rr * math.sin(th)
    end

    -- 赤道环（单位圆，y=0）
    o.ex, o.ey, o.ez = {}, {}, {}
    for i = 0, NEQ - 1 do
        local a = i / NEQ * fx.TAU
        o.ex[i] = math.cos(a)
        o.ey[i] = 0
        o.ez[i] = math.sin(a)
    end

    -- 卫星轨道：先绕 X 轴倾斜 ORB_TILT，之后每帧再绕 Y 轴自转
    local ct, st = math.cos(ORB_TILT), math.sin(ORB_TILT)
    o.ct, o.st = ct, st
    o.ox, o.oy, o.oz = {}, {}, {}
    for i = 0, NORB - 1 do
        local a = i / NORB * fx.TAU
        local x, z = math.cos(a) * ORB_R, math.sin(a) * ORB_R
        o.ox[i] = x
        o.oy[i] = -z * st
        o.oz[i] = z * ct
    end
    return o
end

function M.update(o, t, dt)
    local P = o.pool
    local cx, cy, R = o.cx, o.cy, o.R
    local D = VIEW_D
    P:reset()

    local ay = t * 0.55                             -- 星球自转角
    local ax = 0.40 + 0.10 * fx.sin(t * 0.33)       -- 俯仰缓慢摆动
    local cax, sax = fx.cos(ax), fx.sin(ax)
    local cay, say = fx.cos(ay), fx.sin(ay)

    -- ==================== 球面点云 ====================
    local px3, py3, pz3 = o.px3, o.py3, o.pz3
    for i = 1, NP do
        local vx, vy, vz = px3[i], py3[i], pz3[i]
        local x1 = vx * cay - vz * say
        local z1 = vx * say + vz * cay
        local y2 = vy * cax - z1 * sax
        local z2 = vy * sax + z1 * cax
        local k = D / (D + z2)
        local br = (k - K_MIN) / K_SPAN
        P:dot(cx + x1 * R * k, cy + y2 * R * k,
            1 + math.floor(2 * br),
            fx.hsl(186 + 40 * br, 0.85, 0.42 + 0.34 * br),
            math.floor(46 + 200 * br))
    end

    -- ==================== 赤道环 ====================
    local ex, ey, ez = o.ex, o.ey, o.ez
    for i = 0, NEQ - 1 do
        local vx, vy, vz = ex[i], ey[i], ez[i]
        local x1 = vx * cay - vz * say
        local z1 = vx * say + vz * cay
        local y2 = vy * cax - z1 * sax
        local z2 = vy * sax + z1 * cax
        local k = D / (D + z2)
        local br = (k - K_MIN) / K_SPAN
        P:dot(cx + x1 * R * k, cy + y2 * R * k, 2,
            fx.hsl(194, 0.90, 0.55 + 0.30 * br),
            math.floor(90 + 150 * br))
    end

    -- ==================== 卫星轨道 ====================
    local orbRot = t * 1.15        -- 轨道比星球转得快，形成交叉感
    local cor, sor = fx.cos(orbRot), fx.sin(orbRot)
    local ox, oy, oz = o.ox, o.oy, o.oz
    local kminO = D / (D + ORB_R)
    local kspanO = D / (D - ORB_R) - kminO

    for i = 0, NORB - 1 do
        local vx, vy, vz = ox[i], oy[i], oz[i]
        local x1 = vx * cor - vz * sor
        local z1 = vx * sor + vz * cor
        local y2 = vy * cax - z1 * sax
        local z2 = vy * sax + z1 * cax
        local k = D / (D + z2)
        local br = (k - kminO) / kspanO
        P:dot(cx + x1 * R * k, cy + y2 * R * k, 1,
            fx.hsl(300, 0.72, 0.40 + 0.28 * br),
            math.floor(40 + 120 * br))
    end

    -- 轨道上的卫星：位置直接取 orbRot 对应的点（复用 cor/sor，不再多算三角函数）
    do
        local sx0 = cor * ORB_R
        local sz0 = sor * ORB_R
        local vy = -sz0 * o.st
        local vz = sz0 * o.ct
        local x1 = sx0 * cor - vz * sor
        local z1 = sx0 * sor + vz * cor
        local y2 = vy * cax - z1 * sax
        local z2 = vy * sax + z1 * cax
        local k = D / (D + z2)
        local br = (k - kminO) / kspanO
        P:dot(cx + x1 * R * k, cy + y2 * R * k, 3,
            fx.hsl(48, 0.95, 0.62 + 0.20 * br), 240)
    end

    -- ==================== 核心高光 ====================
    local pulse = 0.5 + 0.5 * fx.sin(t * 1.9)
    P:dot(cx, cy, math.floor(2 + 2 * pulse), 0xBFF4FF,
        math.floor(70 + 60 * pulse))

    o.n = P:finish()
    o.shape:set_items(P.items)
end

return M
