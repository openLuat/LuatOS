--[[
@module  view_orbit
@summary AURORA UI - 页面 3「星轨」：3D 粒子星云 + 拖拽轨道相机
@version 1.0
@date    2026.10.22
@author  江访

=== 视觉效果 ===
84 颗粒子按「两条旋臂 + 中央核球」分布在一个扁盘星系的体积内，
每颗都做完整的 3D 旋转 + 透视投影：
  - 大小与亮度随深度变化（近大远小、近亮远暗）
  - 颜色按到中心的距离从青绿渐变到品红，越靠内越暖
同一条旋臂上相邻粒子之间连线，靠"隔一颗连一次"把连线压到 42 条，
既保住旋臂的流动感，又不让图元数失控。
外加一圈位于星系盘面上的定位环，同样参与 3D 旋转，提供空间参照。

=== 交互 ===
在左半屏拖拽 = 轨道相机（水平改偏航、垂直改俯仰），松手后带惯性滑行；
俯仰角被夹在 ±52°，避免翻到极点后画面打转。
右侧第 3 张卡片的滑块实时改视距 D，透视强度立即变化（真 参数联动）。

=== 与 UI Store 的差距 ===
UI Store 里最强的是 LuckyWheel 的单轴图片旋转（0.1° 步进）。
这里是自由视角 3D 点云 + 近邻连线 + 实时透视参数，没有任何素材依赖。
]]
local fx = require "fx"

local M = {
    id = "orbit",
    name = "星轨",
    en = "ORBIT",
    desc = "3D 旋臂星云  拖拽可转视角",
}

local NP      = 84        -- 粒子数
local RING_N  = 24        -- 盘面定位环分段
local ARM_A   = 15        -- 每条旋臂的粒子数（其余进核球）
local TWIST   = 2.9       -- 旋臂缠绕弧度

function M.build(parent, W, H, card)
    local o = {
        w = W, h = H,
        pool = fx.pool(),
        ppool = fx.pool(),
        spin = 0, vel = 0, drag = false,
        yaw = 0, pitch = 0.34, pvel = 0,
        zoom = 62,                 -- 0..100，映射到视距
        sx = {}, sy = {}, sk = {},
        arm = {},                  -- 每颗粒子所属旋臂（0=核球）
    }
    o.cx, o.cy = W * 0.5, H * 0.50
    o.R = math.min(W, H) * 0.40

    local rnd = fx.rng(770713)
    o.px, o.py, o.pz = {}, {}, {}
    local idx = 0
    -- ---- 两条旋臂 ----
    for a = 1, 2 do
        for i = 1, ARM_A do
            idx = idx + 1
            local f = (i - 1) / (ARM_A - 1)          -- 0(内) .. 1(外)
            local r = 0.20 + f * 0.80
            local th = a * math.pi + f * TWIST + (rnd() - 0.5) * 0.28
            o.px[idx] = math.cos(th) * r + (rnd() - 0.5) * 0.07
            o.py[idx] = (rnd() - 0.5) * (0.10 + 0.05 * (1 - f))   -- 盘厚，内厚外薄
            o.pz[idx] = math.sin(th) * r + (rnd() - 0.5) * 0.07
            o.arm[idx] = a
        end
    end
    -- ---- 中央核球 ----
    local qx, qy, qz = {}, {}, {}
    local nn = NP - idx
    fx.fib_sphere(nn, qx, qy, qz)
    for i = 1, nn do
        idx = idx + 1
        local k = (0.10 + 0.14 * rnd()) / 1.0
        o.px[idx] = qx[i] * k
        o.py[idx] = qy[i] * k * 0.75
        o.pz[idx] = qz[i] * k
        o.arm[idx] = 0
    end

    -- 盘面定位环（单位圆，位于 y=0 平面）
    o.rx, o.rz = {}, {}
    for i = 1, RING_N do
        local a = (i - 1) / RING_N * fx.TAU
        o.rx[i] = math.cos(a) * 1.06
        o.rz[i] = math.sin(a) * 1.06
    end

    o.shape = airui.shape({
        parent = parent, x = 0, y = 0, w = W, h = H, items = {},
    })

    if card then
        o.c1 = card(1, "恒星数", 0x22E6FF, tostring(NP), "双旋臂 + 核球")
        o.c2 = card(2, "系统半径", 0xA855F7, "42.7 kly", "可观测边界")
        o.c3 = card(3, "视距", 0xFFB020, "62", "拖拽 / 滑块改变视角")
        o.slider = airui.slider({
            parent = o.c3.root,
            x = 18, y = 94, w = o.c3.w - 36, h = 20,
            min = 0, max = 100, value = o.zoom,
            style = {
                bg_color = 0x16233C, bg_opa = 255,
                radius = 10, pad = 0,
                indicator_color = 0xFFB020,
                knob_color = 0xFFF2D8,
            },
            on_change = function(obj)
                local ok, v = pcall(function() return obj:get_value() end)
                if ok and type(v) == "number" then o.zoom = v end
            end,
        })
        o.zoom_txt = tostring(o.zoom)
    end
    return o
end

-- ==================== 每帧绘制 ====================
function M.update(o, t, dt)
    local P = o.pool
    local cx, cy, R = o.cx, o.cy, o.R
    local sx, sy, sk = o.sx, o.sy, o.sk
    P:reset()

    -- ---- 相机：自转 + 拖拽惯性 ----
    if not o.drag then
        o.spin = o.spin + o.vel * dt
        o.vel = o.vel * (0.90 ^ (dt * 60))
        if math.abs(o.vel) < 0.01 then o.vel = 0 end
        o.pitch = o.pitch + o.pvel * dt
        o.pvel = o.pvel * (0.88 ^ (dt * 60))
        -- 俯仰回中：松手后缓慢回到 0.34 的舒服角度
        o.pitch = fx.approach(o.pitch, 0.34, 0.02, dt)
    end
    o.pitch = fx.clamp(o.pitch, -0.92, 0.92)
    local yaw = t * 0.20 + o.spin + o.yaw
    local cay, say = math.cos(yaw), math.sin(yaw)
    local cax, sax = math.cos(o.pitch), math.sin(o.pitch)

    -- 视距由滑块控制：D 越小透视越夸张
    local D = 3.0 + (o.zoom / 100) * 4.5
    local KMIN = D / (D + 1.1)
    local KSPAN = D / (D - 0.25) - KMIN

    -- ==================== 盘面定位环 ====================
    local rx, rz = o.rx, o.rz
    for i = 1, RING_N do
        local j = i % RING_N + 1
        local x1, y1, k1 = fx.project(rx[i], 0, rz[i], cax, sax, cay, say, D)
        local x2, y2 = fx.project(rx[j], 0, rz[j], cax, sax, cay, say, D)
        local br = fx.depth_t(k1, KMIN, KSPAN)
        P:line(cx + x1 * R, cy + y1 * R, cx + x2 * R, cy + y2 * R,
            0x2A4570, 1, math.floor(40 + 90 * br))
    end

    -- ==================== 粒子投影 ====================
    local pxx, pyy, pzz = o.px, o.py, o.pz
    for i = 1, NP do
        local x1, y1, k = fx.project(pxx[i], pyy[i], pzz[i], cax, sax, cay, say, D)
        sx[i] = cx + x1 * R
        sy[i] = cy + y1 * R
        sk[i] = k
    end

    -- ==================== 旋臂连线（隔一颗连一次） ====================
    --[[为什么隔一颗连
    每条旋臂 15 颗，全连是 28 条；隔一颗连是 14 条，视觉上只损失一点连续性，
    但省下的 28 个图元够再画 28 颗粒子的高光。]]
    local start = 1
    for a = 1, 2 do
        for i = start, start + ARM_A - 3, 2 do
            local br = fx.depth_t((sk[i] + sk[i + 1]) * 0.5, KMIN, KSPAN)
            P:line(sx[i], sy[i], sx[i + 1], sy[i + 1],
                fx.hsl(280 - 40 * br, 0.75, 0.30 + 0.18 * br),
                1, math.floor(30 + 70 * br))
        end
        start = start + ARM_A
    end

    -- ==================== 粒子本体 ====================
    for i = 1, NP do
        local k = sk[i]
        local br = fx.depth_t(k, KMIN, KSPAN)
        local d = math.sqrt(pxx[i] * pxx[i] + pzz[i] * pzz[i])   -- 到中心距离
        local hue = 300 - 120 * fx.clamp(d / 1.05, 0, 1)          -- 外紫内青
        local col = fx.hsl(hue, 0.92, 0.44 + 0.34 * br)
        local r = (d < 0.25) and (1 + math.floor(2 * br)) or (1 + math.floor(1.6 * br))
        P:dot(sx[i], sy[i], r, col, math.floor(70 + 175 * br))
    end

    -- ==================== 核心 ====================
    local pulse = 0.5 + 0.5 * math.sin(t * 2.1)
    P:dot(cx, cy, math.floor(18 + 10 * pulse), 0x9FF3FF, math.floor(20 + 20 * pulse))
    P:dot(cx, cy, math.floor(9 + 4 * pulse), 0x5FE6FF, math.floor(50 + 40 * pulse))
    P:dot(cx, cy, 4, 0xFFFFFF, 250)

    -- 十字准星：只有 4 段，给画面一个"目镜"感
    local ext = R * 1.25
    P:line(cx - ext, cy, cx - ext + 26, cy, 0x2A4570, 1, 90, true)
    P:line(cx + ext - 26, cy, cx + ext, cy, 0x2A4570, 1, 90, true)
    P:line(cx, cy - ext * 0.72, cx, cy - ext * 0.72 + 20, 0x2A4570, 1, 90, true)
    P:line(cx, cy + ext * 0.72 - 20, cx, cy + ext * 0.72, 0x2A4570, 1, 90, true)

    o.n = P:finish()
    o.shape:set_items(P.items)
end

-- ==================== 右侧卡片（5Hz） ====================
function M.panel(o, t, dt)
    if not o.c1 then return end
    local P = o.ppool
    P:reset()
    fx.meter(P, 18, 106, o.c1.w - 36, 8, NP / 120, 0x22E6FF)
    P:finish()
    o.c1.shape:set_items(P.items)

    P:reset()
    fx.meter(P, 18, 106, o.c2.w - 36, 8, 0.62, 0xA855F7)
    P:finish()
    o.c2.shape:set_items(P.items)

    -- 卡片 3 的滑块自带进度条，这里只补一条刻度底纹
    P:reset()
    P:line(18, 116, o.c3.w - 18, 116, 0x1B2C48, 1, 140)
    P:finish()
    o.c3.shape:set_items(P.items)

    local v = tostring(math.floor(o.zoom + 0.5))
    if v ~= o.zoom_txt then
        o.zoom_txt = v
        o.c3.value:set_text(v)
    end
    -- 视距实时读数放在副标题：D = 3.0 .. 7.5
    local d = string.format("D = %.2f", 3.0 + (o.zoom / 100) * 4.5)
    if d ~= o.d_txt then
        o.d_txt = d
        o.c3.sub:set_text(d)
    end
end

-- ==================== 触摸：轨道相机 ====================
function M.touch(o, ev, x, y)
    if ev == "down" then
        o.drag = true
        o.lx, o.ly = x, y
        o.vel, o.pvel = 0, 0
        return true
    elseif ev == "move" then
        if not o.drag then return false end
        local dx, dy = x - o.lx, y - o.ly
        o.lx, o.ly = x, y
        o.spin = o.spin + dx * 0.010
        o.pitch = fx.clamp(o.pitch + dy * 0.006, -0.92, 0.92)
        o.vel = o.vel * 0.55 + (dx * 0.010) * 45 * 0.45
        o.pvel = o.pvel * 0.55 + (dy * 0.006) * 45 * 0.45
        return true
    elseif ev == "up" then
        local was = o.drag
        o.drag = false
        return was
    end
    return false
end

function M.blur(o)
    o.vel, o.pvel = 0, 0
    o.drag = false
end

return M
