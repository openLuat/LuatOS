--[[
@module  view_nexus
@summary AURORA UI - 页面 1「核心」：3D 陀螺仪 + 环形刻度盘
@version 1.0
@date    2026.10.22
@author  江访

=== 视觉效果 ===
三条不同倾角的轨道环在 3D 空间里以各自速度进动，顶点经过旋转矩阵 + 透视除法
投到 2D；线段宽度与亮度按平均深度着色（近处更亮更粗），因此不做深度排序
也有明确的体积感。每个环上有一颗卫星沿轨道飞行并拖一条霓虹尾迹。

外圈是 72 格刻度盘 + 一段从 -90° 起顺时针生长的进度弧（高度按临界阻尼弹簧趋近目标），
弧头带一颗发光端点，刻度盘每 6 格一根长刻度。

=== 交互 ===
在左半屏横向拖拽可给陀螺仪加角速度，松手后按指数衰减滑行（touch_subscribe）。

=== 分层与预算 ===
静态层（刻度盘、十字准线、外环）只在 build 时画一次；
动态层每帧重算约 150 个图元：3 环 x26 段 = 78 线 + 34 星尘 + 进度弧 24 段 + 核心 6。
如果把静态层也放进每帧重算，光刻度盘就白扔掉 70 个图元的预算。
]]
local fx = require "fx"

local M = {
    id = "nexus",
    name = "核心",
    en = "NEXUS",
    desc = "3D 陀螺仪  拖拽可加速自转",
}

local SEG      = 22      -- 每个轨道环的折线段数（段数直接等于图元数，别贪多）
local DUST     = 34      -- 3D 星尘颗粒数
local VIEW_D   = 5.4     -- 视距（归一化单位），越大透视越弱
local DIAL_N   = 72      -- 刻度盘格数
local ARC_SEG  = 14      -- 进度弧分段（每段画霓虹=2 个图元，段数别超过 20）
local SPARK_N  = 26      -- 卡片迷你折线点数

-- 三条轨道的固定倾角（绕 X、绕 Z）与自转速度
local RING_DEF = {
    { ax = 0.00, az = 0.00, sp = 0.62, hue = 190, w = 2 },
    { ax = 1.05, az = 0.55, sp = -0.85, hue = 288, w = 2 },
    { ax = -0.72, az = 1.30, sp = 1.10, hue = 168, w = 1 },
}

local function fmt(v, n)
    return string.format("%." .. n .. "f", v)
end

-- ==================== 构建 ====================
function M.build(parent, W, H, card)
    local o = {
        w = W, h = H,
        pool = fx.pool(),
        ppool = fx.pool(),
        spin = 0, vel = 0, drag = false,
        arc_v = 0.0, arc_t = 0.0,
        temp = 36.0, power = 3.1, sync = 96.0,
        spark1 = {}, spark2 = {}, spark3 = {},
        spark_n = 0,
    }
    o.cx, o.cy = W * 0.5, H * 0.48
    o.R = 114
    o.Rd = o.R * 1.24          -- 刻度盘半径

    -- ---- 单位圆点（三个环共用）----
    o.rc, o.rs = {}, {}
    for i = 1, SEG do
        local a = (i - 1) / SEG * fx.TAU
        o.rc[i] = math.cos(a)
        o.rs[i] = math.sin(a)
    end

    -- ---- 三个环的顶点在 build 时就把自身倾角烘进去 ----
    -- 之后每帧只做相机旋转，省掉 78 次三角函数的矩阵构造
    o.rx, o.ry, o.rz = {}, {}, {}
    for r = 1, #RING_DEF do
        local ax, az = RING_DEF[r].ax, RING_DEF[r].az
        local cax, sax = math.cos(ax), math.sin(ax)
        local caz, saz = math.cos(az), math.sin(az)
        local bx, by, bz = {}, {}, {}
        for i = 1, SEG do
            local x0, y0, z0 = o.rc[i], o.rs[i], 0
            -- 绕 X 轴倾斜
            local y1 = y0 * cax - z0 * sax
            local z1 = y0 * sax + z0 * cax
            -- 绕 Z 轴倾斜
            bx[i] = x0 * caz - y1 * saz
            by[i] = x0 * saz + y1 * caz
            bz[i] = z1
        end
        o.rx[r], o.ry[r], o.rz[r] = bx, by, bz
    end
    -- 投影结果缓存（每帧复用，避免建表）
    o.sx, o.sy, o.sk = {}, {}, {}

    -- ---- 3D 星尘：斐波那契球面 * 随机半径 ----
    local dx, dy, dz = {}, {}, {}
    fx.fib_sphere(DUST, dx, dy, dz)
    local rnd = fx.rng(86071022)
    o.dx, o.dy, o.dz, o.dr = {}, {}, {}, {}
    for i = 1, DUST do
        --[[球壳半径上限受画布约束
        透视系数 k = D/(D+z) 会把靠近相机的点放大，半径 2.6 时投影偏移能到
        2.3 个 R（≈260px），而圆心离 HERO 顶边只有 202px —— 星尘会被裁在边上，
        表现为"闪一下就没了"。收敛到 1.75 以内，最远偏移约 180px，正好不出画。]]
        local k = 0.95 + rnd() * 0.80
        o.dx[i] = dx[i] * k
        o.dy[i] = dy[i] * k
        o.dz[i] = dz[i] * k
        o.dr[i] = (rnd() < 0.25) and 2 or 1
    end

    -- ---- 静态层：刻度盘 + 十字准线 + 外环 ----
    o.static_shape = airui.shape({
        parent = parent, x = 0, y = 0, w = W, h = H, items = {},
    })
    do
        local P = fx.pool()
        local cx, cy, Rd = o.cx, o.cy, o.Rd
        P:ring(cx, cy, math.floor(Rd), 0x1C3A5C, 1, 120)
        P:ring(cx, cy, math.floor(Rd * 0.90), 0x16294A, 1, 90)
        for k = 0, DIAL_N - 1 do
            local a = k / DIAL_N * fx.TAU - math.pi / 2
            local long = (k % 6 == 0)
            local r0 = Rd + 2
            local r1 = Rd + (long and 11 or 6)
            local c, s = math.cos(a), math.sin(a)
            P:line(cx + c * r0, cy + s * r0, cx + c * r1, cy + s * r1,
                long and 0x3D6E9E or 0x22385C, long and 1 or 1, long and 170 or 110, true)
        end
        -- 十字准线（虚线，避免和轨道环抢视觉）
        local ext = Rd + 16
        P:dash(cx - ext, cy, cx - Rd * 0.55, cy, 0x24365A, 1, 80, 7, 7)
        P:dash(cx + Rd * 0.55, cy, cx + ext, cy, 0x24365A, 1, 80, 7, 7)
        P:dash(cx, cy - ext, cx, cy - Rd * 0.55, 0x24365A, 1, 80, 7, 7)
        P:dash(cx, cy + Rd * 0.55, cx, cy + ext, 0x24365A, 1, 80, 7, 7)
        P:finish()
        o.static_shape:set_items(P.items)
    end

    -- ---- 动态层 ----
    o.shape = airui.shape({
        parent = parent, x = 0, y = 0, w = W, h = H, items = {},
    })

    -- ---- 右侧卡片 ----
    if card then
        o.c1 = card(1, "核心温度", 0x22E6FF, "36.0 C", "液冷回路  正常")
        o.c2 = card(2, "输出功率", 0xA855F7, "3.10 kW", "峰值 4.80 kW")
        o.c3 = card(3, "同步率", 0x2BE59D, "96.0 %", "相位锁定")
        o.lbl_t = { value = "36.0 C", sub = "液冷回路  正常" }
        o.lbl_p = { value = "3.10 kW", sub = "峰值 4.80 kW" }
        o.lbl_s = { value = "96.0 %", sub = "相位锁定" }
    end
    return o
end

-- ==================== 每帧绘制 ====================
function M.update(o, t, dt)
    local P = o.pool
    local cx, cy, R, Rd = o.cx, o.cy, o.R, o.Rd
    local sx, sy, sk = o.sx, o.sy, o.sk
    P:reset()

    -- ---- 相机姿态：拖拽角速度衰减 + 常速自转 ----
    if not o.drag then
        o.spin = o.spin + o.vel * dt
        o.vel = o.vel * (0.90 ^ (dt * 60))
        if math.abs(o.vel) < 0.01 then o.vel = 0 end
    end
    local yaw = t * 0.34 + o.spin
    local pitch = 0.40 + 0.13 * math.sin(t * 0.31)
    local cay, say = math.cos(yaw), math.sin(yaw)
    local cax, sax = math.cos(pitch), math.sin(pitch)

    -- 深度系数范围（单位球：D/(D+1) .. D/(D-1)）
    local KMIN = VIEW_D / (VIEW_D + 2.4)
    local KSPAN = VIEW_D / (VIEW_D - 2.4) - KMIN

    -- ==================== 3D 星尘 ====================
    local dx, dy, dz = o.dx, o.dy, o.dz
    for i = 1, DUST do
        local x1, y1, k = fx.project(dx[i], dy[i], dz[i], cax, sax, cay, say, VIEW_D)
        local br = fx.depth_t(k, KMIN, KSPAN)
        P:dot(cx + x1 * R, cy + y1 * R, o.dr[i],
            fx.hsl(200 + 60 * br, 0.55, 0.35 + 0.30 * br),
            math.floor(30 + 130 * br))
    end

    -- ==================== 三个轨道环 ====================
    for r = 1, #RING_DEF do
        local def = RING_DEF[r]
        local bx, by, bz = o.rx[r], o.ry[r], o.rz[r]
        for i = 1, SEG do
            local x1, y1, k = fx.project(bx[i], by[i], bz[i], cax, sax, cay, say, VIEW_D)
            sx[i] = cx + x1 * R
            sy[i] = cy + y1 * R
            sk[i] = k
        end
        --[[两遍画法：先给靠近相机的半环铺一层暗光晕，再逐段按深度上灯芯
        光晕只为前半环服务（后半环本来就该暗），只加 ~40% 的图元，
        比整环都铺一层省一半，观感几乎没差别。]]
        for i = 1, SEG do
            local j = (i == SEG) and 1 or (i + 1)
            local br = fx.depth_t((sk[i] + sk[j]) * 0.5, KMIN, KSPAN)
            if br > 0.5 then
                P:line(sx[i], sy[i], sx[j], sy[j], fx.hsl(def.hue, 0.9, 0.30), 5, 46, true)
            end
            P:line(sx[i], sy[i], sx[j], sy[j],
                fx.hsl(def.hue - 8 + 16 * br, 0.95, 0.42 + 0.34 * br),
                def.w, math.floor(80 + 175 * br), true)
        end

        -- 卫星：沿本环轨道飞行，位置用预烘好的顶点表做线性插值
        local f = ((t * def.sp * 0.5) % 1) * SEG
        local i0 = math.floor(f)
        local ft = f - i0
        local i1 = i0 % SEG + 1
        i0 = i0 + 1
        local vx = bx[i0] + (bx[i1] - bx[i0]) * ft
        local vy = by[i0] + (by[i1] - by[i0]) * ft
        local vz = bz[i0] + (bz[i1] - bz[i0]) * ft
        local x1, y1, k = fx.project(vx, vy, vz, cax, sax, cay, say, VIEW_D)
        local br = fx.depth_t(k, KMIN, KSPAN)
        local mx, my = cx + x1 * R, cy + y1 * R
        local col = fx.hsl(def.hue + 10, 1.0, 0.62 + 0.30 * br)
        P:dot(mx, my, 6 + math.floor(4 * br), col, math.floor(40 + 40 * br))  -- 外光晕
        P:dot(mx, my, 2 + math.floor(2 * br), 0xFFFFFF, math.floor(180 + 75 * br))
    end

    -- ==================== 核心 ====================
    local pulse = 0.5 + 0.5 * math.sin(t * 2.4)
    P:dot(cx, cy, math.floor(16 + 8 * pulse), 0x22E6FF, math.floor(26 + 22 * pulse))
    P:ring(cx, cy, math.floor(9 + 3 * pulse), 0x9BE8FF, 1, math.floor(110 + 100 * pulse))
    P:dot(cx, cy, 4, 0xE8FBFF, 250)

    -- ==================== 外圈进度弧 ====================
    -- 目标值用噪声缓慢漂移，弧长按弹簧趋近，弧头那颗点跟着一起走
    o.arc_t = 0.52 + 0.34 * fx.noise1(t * 0.21)
    o.arc_v = fx.approach(o.arc_v, o.arc_t, 0.06, dt)
    local a0 = -math.pi / 2
    local a1 = a0 + o.arc_v * fx.TAU
    local arc_col = 0x22E6FF
    -- 底轨就是一整圈，用 ring 画只要 1 个图元（arc 折线要 48 个，没必要）
    P:ring(cx, cy, math.floor(Rd), 0x1A2E4A, 2, 210)
    -- 进度弧：首段亮、末端更白，形成"能量流动"感
    local segs = math.floor(ARC_SEG * o.arc_v) + 1
    local step = (a1 - a0) / segs
    local ax0 = cx + math.cos(a0) * Rd
    local ay0 = cy + math.sin(a0) * Rd
    for i = 1, segs do
        local a = a0 + step * i
        local ax1 = cx + math.cos(a) * Rd
        local ay1 = cy + math.sin(a) * Rd
        P:neon(ax0, ay0, ax1, ay1, fx.mix(arc_col, 0xFFFFFF, i / segs * 0.7), 2, 235)
        ax0, ay0 = ax1, ay1
    end
    P:dot(ax0, ay0, 9, 0xBFF4FF, 70)
    P:dot(ax0, ay0, 4, 0xFFFFFF, 240)

    o.n = P:finish()
    o.shape:set_items(P.items)
end

-- ==================== 右侧卡片（5Hz） ====================
function M.panel(o, t, dt)
    if not o.c1 then return end
    -- 数据模拟：噪声驱动 + 弹簧跟随，观感是"实时在变"而不是跳数
    o.temp = fx.approach(o.temp, 34.5 + 3.0 * fx.noise1(t * 0.17 + 3.1), 0.05, dt)
    o.power = fx.approach(o.power, 3.0 + 1.1 * fx.noise1(t * 0.23 + 8.7), 0.05, dt)
    o.sync = fx.approach(o.sync, 94.5 + 4.6 * fx.noise1(t * 0.13 + 1.7), 0.05, dt)

    -- 迷你折线环形历史（每调用一次推进一格，SPARK_N 点约 5 秒历史）
    local n = o.spark_n + 1
    if n > SPARK_N then
        for i = 2, SPARK_N do
            o.spark1[i - 1] = o.spark1[i]
            o.spark2[i - 1] = o.spark2[i]
            o.spark3[i - 1] = o.spark3[i]
        end
        n = SPARK_N
    end
    o.spark1[n] = (o.temp - 33) / 6
    o.spark2[n] = (o.power - 2.6) / 1.6
    o.spark3[n] = (o.sync - 93) / 7
    o.spark_n = n

    local P = o.ppool
    local list = { o.c1, o.c2, o.c3 }
    local vals = { o.spark1, o.spark2, o.spark3 }
    for i = 1, 3 do
        local c = list[i]
        P:reset()
        -- 迷你折线画在数值右侧，能量条压在卡片底部（坐标是卡片局部坐标）
        fx.spark(P, vals[i], n, 196, 40, 122, 42, c.accent, 1, 190)
        local frac = (i == 1) and (o.temp - 33) / 6
            or (i == 2) and (o.power - 2.6) / 1.6
            or (o.sync - 93) / 7
        fx.meter(P, 18, 106, c.w - 36, 8, frac, c.accent)
        P:finish()
        c.shape:set_items(P.items)
    end

    M.sync_text(o)
end

--[[文本刷新：只在数值真的变了才 set_text
LVGL 每次 set_text 都会重新排版文本（形状、宽度、换行），
4Hz 刷新 3 张卡共 6 个 label，如果每帧无条件写，等于每帧多 6 次重排。
]]
function M.sync_text(o)
    local v = fmt(o.temp, 1) .. " C"
    if v ~= o.lbl_t.value then
        o.lbl_t.value = v
        o.c1.value:set_text(v)
    end
    v = fmt(o.power, 2) .. " kW"
    if v ~= o.lbl_p.value then
        o.lbl_p.value = v
        o.c2.value:set_text(v)
    end
    v = fmt(o.sync, 1) .. " %"
    if v ~= o.lbl_s.value then
        o.lbl_s.value = v
        o.c3.value:set_text(v)
    end
end

-- ==================== 触摸：横向拖拽加角速度 ====================
function M.touch(o, ev, x, y)
    if ev == "down" then
        o.drag = true
        o.lx = x
        o.vel = 0
        return true
    elseif ev == "move" then
        if not o.drag then return false end
        local dx = x - o.lx
        o.lx = x
        o.spin = o.spin + dx * 0.012
        -- 速度用一阶低通，避免最后一帧的抖动被放大成甩飞
        o.vel = o.vel * 0.55 + (dx * 0.012) * 45 * 0.45
        return true
    elseif ev == "up" then
        local was = o.drag
        o.drag = false
        return was
    end
    return false
end

-- 页面切走时清掉惯性，避免切回来时陀螺仪突然在转
function M.blur(o)
    o.vel = 0
    o.drag = false
end

return M
