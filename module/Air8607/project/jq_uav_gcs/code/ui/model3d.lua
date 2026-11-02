--[[
@module  model3d
@summary UAV GCS - 线框房间与四旋翼机体（真 3D 透视，逐帧重绘）
@version 1.0
@date    2026.11.02

=== 为什么不是图片 ===
机体要跟着横滚/俯仰/偏航连续转，任何一张静态图都只能"假转"。
这里把顶点做旋转 + 透视投影，再用 line / circle 画出来：
任意姿态、任意缩放都是准确的，而且没有任何图片解码开销。

=== 相机 ===
相机在 z = -d 处朝 +z 看，光心高度 y0：
  sx = cx + x * f / (z + d)
  sy = cy - (y - y0) * f / (z + d)
参数（见 theme.att.cam）：cx=295 cy=232 f=600 d=9 y0=0.55
把它代进房间的 8 个角，得到的包围盒正好是 x 65..545、y 117..366，
完整落进 590x404 的视图里 —— 这一点必须靠算，靠试会溢出到按钮区。

=== 尺度换算（踩过的坑）===
投影返回的第三个值 k 是"每世界单位多少像素"（≈66），
所有屏幕尺寸都必须写成 `世界半径 * k`，不能写死像素再乘 k/0.66 之类的比值，
否则一个 5px 的电机就会变成 500px 的大圆。

=== 坐标约定 ===
机体坐标系：+x 右、+y 上、+z 机头。
机体旋转顺序：偏航（绕 y）-> 俯仰（绕 x）-> 横滚（绕 z），见 fx.rot3。
仿真里的 pitch 正 = 抬头，roll 正 = 右滚，所以传进旋转前要取反（见 draw）。
]]
local fx = require "fx"
local T = require "theme"

local C = T.c
local M = {}

-- ==================== 房间 ====================
local ROOM = { x = 2.6, z0 = -2.5, z1 = 3.5, yb = -0.9, yt = 1.8 }

-- 相机中心处的 k（f/d = 600/9），所有"每单位像素"的基准
local K0 = 66.7

-- ==================== 机体尺寸 ====================
local ARM    = 1.55    -- 电机到机心的 x/z 偏移
local BR     = 0.72    -- 机身六边形半径
local PROP_R = 0.78    -- 桨盘半径
local MOT_Y  = 0.06

-- 前两桨粉色、后两桨绿色：转起来以后一眼能分清机头朝哪
local MOTORS = {
    { x =  ARM, z =  ARM, col = C.pink,  led = C.pink },   -- 右前
    { x = -ARM, z =  ARM, col = C.pink,  led = C.pink },   -- 左前
    { x =  ARM, z = -ARM, col = C.green, led = C.green },  -- 右后
    { x = -ARM, z = -ARM, col = C.green, led = C.green },  -- 左后
}

local GEAR_X = { -0.42, 0.42 }

-- 机身六边形（xz 平面，机头朝 +z）
local BODY = {}
do
    for i = 0, 5 do
        local a = i * math.pi / 3 + math.pi / 6
        BODY[i + 1] = { x = math.cos(a) * BR, z = math.sin(a) * BR }
    end
end

-- ==================== 静态房间 ====================
--[[房间画一次就够：相机不动，网格的投影结果每帧都一样。
把这 60 多根线塞进静态 shape，比每帧重算省下 60 次投影 + 60 个图元。]]
function M.build_room(P, cam)
    local fy = ROOM.yb
    local step = 0.5

    -- 地面网格：x 方向与 z 方向各铺一遍，越远越淡
    local x = -ROOM.x
    while x <= ROOM.x + 0.001 do
        local x1, y1 = fx.proj3(x, fy, ROOM.z0, cam)
        local x2, y2, k2 = fx.proj3(x, fy, ROOM.z1, cam)
        local t = fx.clamp(k2 / K0, 0.5, 1)
        P:line(x1, y1, x2, y2, C.line2, 1, math.floor(50 + 80 * t), false)
        x = x + step
    end
    local z = ROOM.z0
    while z <= ROOM.z1 + 0.001 do
        local x1, y1 = fx.proj3(-ROOM.x, fy, z, cam)
        local x2, y2, k = fx.proj3(ROOM.x, fy, z, cam)
        local t = fx.clamp(k / K0, 0.5, 1)
        P:line(x1, y1, x2, y2, C.line2, 1, math.floor(50 + 85 * t), false)
        z = z + step
    end

    -- 后墙：竖线 + 横线，做成"训练场"的背板
    local wz = ROOM.z1
    local wx = -ROOM.x
    while wx <= ROOM.x + 0.001 do
        local x1, y1 = fx.proj3(wx, ROOM.yb, wz, cam)
        local x2, y2 = fx.proj3(wx, ROOM.yt, wz, cam)
        P:line(x1, y1, x2, y2, C.line, 1, 55, false)
        wx = wx + step
    end
    local wy = ROOM.yb
    while wy <= ROOM.yt + 0.001 do
        local x1, y1 = fx.proj3(-ROOM.x, wy, wz, cam)
        local x2, y2 = fx.proj3(ROOM.x, wy, wz, cam)
        P:line(x1, y1, x2, y2, C.line, 1, 55, false)
        wy = wy + step
    end

    -- 地平线：相机光心高度的水平线，给空间一个"远处"的暗示
    P:line(0, cam.cy, cam.cx * 2, cam.cy, C.line2, 1, 80, false)

    -- 地面中心：起飞点标记（圆环 + 两侧短刻线）
    local hx, hy, hk = fx.proj3(0, fy, 0, cam)
    local r = math.max(8, math.floor(0.36 * hk))
    P:ring(hx, hy, r, C.cyan, 1, 85)
    P:ring(hx, hy, math.max(4, math.floor(r * 0.45)), C.cyan, 1, 55)
    P:line(hx - r - 9, hy, hx - r - 3, hy, C.cyan, 1, 110, true)
    P:line(hx + r + 3, hy, hx + r + 9, hy, C.cyan, 1, 110, true)
end

-- ==================== 机体 ====================
-- 深度决定亮度：近处亮、远处暗，线框才不像贴纸
local function depth_col(col, k)
    local t = fx.clamp(k / K0, 0.6, 1.3)
    if t >= 1 then return fx.shade(col, (t - 1) * 0.6) end
    return fx.shade(col, (t - 1) * 0.9)
end

local ORDER = { 1, 2, 3, 4 }
local DEPTH = { 0, 0, 0, 0 }
local function by_depth(a, b) return DEPTH[a] > DEPTH[b] end

-- 顶点缓冲：每帧复用，避免 30fps 下每秒 60 张临时表
local BX, BY = { 0, 0, 0, 0, 0, 0 }, { 0, 0, 0, 0, 0, 0 }
local TX, TY = { 0, 0, 0, 0, 0, 0 }, { 0, 0, 0, 0, 0, 0 }

--[[画一台四旋翼
@param table P 图元池
@param table cam 相机
@param table s 仿真状态（取 roll / pitch / yaw / rpm / cmd）
@param number t 秒，用于桨叶旋转相位
]]
function M.draw(P, cam, s, t)
    local cp, sp = math.cos(math.rad(-s.pitch)), math.sin(math.rad(-s.pitch))
    local cr, sr = math.cos(math.rad(-s.roll)), math.sin(math.rad(-s.roll))
    local cyw, syw = math.cos(math.rad(s.yaw)), math.sin(math.rad(s.yaw))

    local function P3(x, y, z)
        local rx, ry, rz = fx.rot3(x, y, z, cyw, syw, cp, sp, cr, sr)
        return fx.proj3(rx, ry, rz, cam)
    end

    local rpm = s.rpm[1] or 0
    local spin = rpm * 0.004 + t * 2.6
    local thr = fx.clamp(rpm / 7600, 0, 1)

    -- ---------- 地面投影（机体正下方的一圈光） ----------
    local sx0, sy0, sk0 = fx.proj3(0, ROOM.yb, 0, cam)
    local rr = math.max(10, math.floor((0.5 + 0.45 * thr) * sk0))
    P:ellipse(sx0, sy0, rr, math.floor(rr * 0.34), C.cyan, 1,
        math.floor(24 + 42 * thr), 28)

    -- ---------- 机臂 + 电机 + 桨 ----------
    -- 远的先画：按旋转后的 z 排序，避免近处机臂被远处桨盘盖住看不出层次
    for i = 1, 4 do
        local m = MOTORS[i]
        local _, _, rz = fx.rot3(m.x, MOT_Y, m.z, cyw, syw, cp, sp, cr, sr)
        DEPTH[i] = rz
        ORDER[i] = i
    end
    table.sort(ORDER, by_depth)

    for oi = 1, 4 do
        local i = ORDER[oi]
        local m = MOTORS[i]

        -- 机臂：一条宽暗线（结构）+ 一条亮线（机臂上的线缆光）
        local ax1, ay1, ak1 = P3(0, 0, 0)
        local ax2, ay2, ak2 = P3(m.x * 0.88, MOT_Y, m.z * 0.88)
        local col = depth_col(m.col, (ak1 + ak2) / 2)
        P:line(ax1, ay1, ax2, ay2, 0x0A0F18, 9, 255, true)
        P:line(ax1, ay1, ax2, ay2, col, 3, 230, true)

        -- 电机
        local mx, my, mk = P3(m.x, MOT_Y, m.z)
        local mr = math.max(3, math.floor(0.085 * mk))
        P:dot(mx, my, mr + 2, 0x05080F, 255)
        P:dot(mx, my, mr, col, 240)

        -- 桨盘：转速越高越像一片圆盘
        local segs = 12
        local px, py
        for k = 0, segs do
            local a = k / segs * fx.TAU
            local x, y = P3(m.x + math.cos(a) * PROP_R, MOT_Y + 0.12, m.z + math.sin(a) * PROP_R)
            if k > 0 then
                P:line(px, py, x, y, col, 1, math.floor(28 + 52 * thr), false)
            end
            px, py = x, y
        end

        -- 桨叶：两根穿过电机中心的细线，靠相位转起来
        for b = 0, 1 do
            local a = spin + b * math.pi / 2
            local c, sn = math.cos(a), math.sin(a)
            local x1, y1 = P3(m.x + c * PROP_R * 0.95, MOT_Y + 0.12, m.z + sn * PROP_R * 0.95)
            local x2, y2 = P3(m.x - c * PROP_R * 0.95, MOT_Y + 0.12, m.z - sn * PROP_R * 0.95)
            P:line(x1, y1, x2, y2, col, 3, math.floor(70 + 120 * thr), true)
        end

        -- 推力柱：从电机沿机体 +y 伸出，长度随油门，"宽暗 + 细亮"叠出光柱
        local tl = 0.3 + 1.0 * thr
        local ux, uy, uz = fx.rot3(m.x, MOT_Y + tl, m.z, cyw, syw, cp, sp, cr, sr)
        local tx, ty = fx.proj3(ux, uy, uz, cam)
        local c2 = fx.mix(col, 0xFFFFFF, 0.45)
        P:line(mx, my, tx, ty, col, 7, 38, false)
        P:line(mx, my, tx, ty, c2, 2, math.floor(85 + 120 * thr), true)
        P:dot(tx, ty, 3, c2, math.floor(110 + 120 * thr))
    end

    -- ---------- 机身 ----------
    for i = 1, 6 do
        BX[i], BY[i] = P3(BODY[i].x, 0, BODY[i].z)
    end
    -- 没有多边形填充，用一条很粗的暗线围出"机身有厚度"的错觉
    P:poly(BX, BY, 6, 0x0A0F18, 10, 255, true)
    P:line(BX[6], BY[6], BX[1], BY[1], 0x0A0F18, 10, 255, true)
    local edge = depth_col(C.dim, K0)
    P:poly(BX, BY, 6, edge, 2, 235, true)
    P:line(BX[6], BY[6], BX[1], BY[1], edge, 2, 235, true)

    -- 上盖：抬 0.18 再画一个略小的六边形
    for i = 1, 6 do
        TX[i], TY[i] = P3(BODY[i].x * 0.78, 0.18, BODY[i].z * 0.78)
    end
    P:poly(TX, TY, 6, 0x1A2436, 5, 255, true)
    P:line(TX[6], TY[6], TX[1], TY[1], 0x1A2436, 5, 255, true)
    P:poly(TX, TY, 6, C.cyan, 1, 145, true)
    P:line(TX[6], TY[6], TX[1], TY[1], C.cyan, 1, 145, true)

    -- 机臂与机身的连接点：四颗小灯，颜色和桨一致
    for i = 1, 4 do
        local m = MOTORS[i]
        local x, y = P3(m.x * 0.42, 0.2, m.z * 0.42)
        P:dot(x, y, 2, m.led, 220)
    end

    -- ---------- 机头方向标 ----------
    local nx1, ny1 = P3(0, 0.2, BR * 0.9)
    local nx2, ny2 = P3(0, 0.2, BR * 1.5)
    P:line(nx1, ny1, nx2, ny2, C.cyan, 2, 210, true)
    P:dot(nx2, ny2, 3, C.cyan, 240)

    -- ---------- 起落架 ----------
    for gi = 1, 2 do
        local sx = GEAR_X[gi]
        local g1x, g1y = P3(sx, -0.42, -0.34)
        local g2x, g2y = P3(sx, -0.42, 0.34)
        local s1x, s1y = P3(sx, -0.62, -0.34)
        local s2x, s2y = P3(sx, -0.62, 0.34)
        P:line(g1x, g1y, g2x, g2y, C.dim2, 3, 240, true)
        P:line(g1x, g1y, s1x, s1y, C.dim2, 2, 200, true)
        P:line(g2x, g2y, s2x, s2y, C.dim2, 2, 200, true)
        P:line(s1x, s1y, s2x, s2y, C.dim2, 3, 240, true)
    end

    -- ---------- 云台相机 ----------
    local c1x, c1y = P3(-0.18, -0.18, 0.5)
    local c2x, c2y = P3(0.18, -0.36, 0.74)
    P:frame(math.min(c1x, c2x), math.min(c1y, c2y),
        math.abs(c2x - c1x) + 1, math.abs(c2y - c1y) + 1, C.dim, 1, 185, 3)
    P:dot((c1x + c2x) / 2, (c1y + c2y) / 2, 2, 0x05080F, 255)
end

return M
