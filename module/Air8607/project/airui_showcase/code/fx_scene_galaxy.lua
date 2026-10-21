--[[
@module  fx_scene_galaxy
@summary 特效场景 1 - 星系粒子
@version 1.0
@date    2026.10.21
@effect
56 颗粒子按「差速自转」环绕星系核心（越靠内角速度越大，形成旋臂被拖曳的观感），
每颗粒子带一小段沿轨道的拖尾；轨道整体压扁 0.44 倍形成盘面透视。
相邻粒子距离小于阈值时自动连一条淡蓝射线，形成星座网格。
背景星空是静态图元，只在 build 时画一次，不占每帧开销。
]]
local fx = require "fx_core"

local M = {
    id = "galaxy",
    name = "星系粒子",
    desc = "56 颗粒子差速环绕核心，近邻自动连线",
}

-- 粒子数直接决定每帧图元量（每颗 2 个），56 颗 + 连线刚好落在 ~150 的预算内
local N = 40
local LINK_N = 5      -- 每颗粒子只与后面 5 颗比对，避免 O(n^2) 全量遍历
local LINK_D2 = 40 * 40
-- 拖尾相对本体的固定角偏移 0.11 弧度，方向分量预先算好
local TRAIL_C, TRAIL_S = math.cos(0.11), math.sin(0.11)

function M.build(parent, W, H)
    local o = { w = W, h = H, pool = fx.pool() }

    -- 静态星空：整场不变，build 时画一次
    o.stars = airui.shape({ parent = parent, x = 0, y = 0, w = W, h = H, items = {} })
    local rnd = fx.rng(86100721)
    local st = {}
    for i = 1, 26 do
        st[i] = {
            type = "circle",
            cx = math.floor(rnd() * W),
            cy = math.floor(rnd() * H),
            r = (rnd() < 0.18) and 2 or 1,
            color = 0xCBD9F2, width = 1, opacity = 255,
            fill = true, fill_color = 0xCBD9F2,
            fill_opacity = math.floor(28 + rnd() * 92),
        }
    end
    o.stars:set_items(st)

    -- 粒子初始参数（同一颗种子，保证每次开机画面一致）
    o.p = {}
    local R = math.min(W, H) * 0.44
    for i = 1, N do
        local rr = 26 + ((i / N) ^ 0.75) * (R - 26)
        local tw = rnd() * fx.TAU          -- 闪烁相位
        o.p[i] = {
            r = rr,
            a = rnd() * fx.TAU,
            sp = 0.85 / (0.42 + rr / R),   -- 差速：内圈快、外圈慢
            sz = 1 + math.floor(rnd() * 2.6),
            hue = 176 + rnd() * 148,
            -- 闪烁相位固定，存下方向分量，每帧就不用再算 sin(tw)
            twc = math.cos(tw),
            tws = math.sin(tw),
        }
    end
    -- 星系核心 5 层的固定角分量（k*0.9）
    o.core_c, o.core_s = {}, {}
    for k = 1, 5 do
        o.core_c[k] = math.cos(k * 0.9)
        o.core_s[k] = math.sin(k * 0.9)
    end

    o.shape = airui.shape({ parent = parent, x = 0, y = 0, w = W, h = H, items = {} })
    return o
end

function M.update(o, t, dt)
    local P = o.pool
    local W, H = o.w, o.h
    local cx, cy = W * 0.5, H * 0.5
    P:reset()

    -- 星系核心：由外向内叠 5 层，半径越小越亮越暖
    -- 和角公式：sin(t*1.7 + k*0.9) 的固定角分量已在 build 时算好，整帧只需 2 次三角函数
    local cb, sb = fx.cos(t * 1.7), fx.sin(t * 1.7)
    for k = 5, 1, -1 do
        local s = sb * o.core_c[k] + cb * o.core_s[k]
        local rr = 8 + k * 9 + s * 2.5
        local col = fx.mix(0xFFD9A0, 0x2B6CFF, (k - 1) / 4)
        P:dot(cx, cy, rr, col, math.floor(24 + (5 - k) * 12))
    end

    -- 粒子本体 + 轨道拖尾
    local px, py = o.px, o.py
    if not px then
        px, py = {}, {}
        o.px, o.py = px, py
    end
    local twb_c, twb_s = fx.cos(t * 2.1), fx.sin(t * 2.1)
    for i = 1, N do
        local p = o.p[i]
        local a = p.a + t * p.sp
        -- 每颗粒子角速度不同，位置分量只能各算一次；其余三处都改用和角公式
        local ca, sa = fx.cos(a), fx.sin(a)
        local x = cx + ca * p.r
        local y = cy + sa * p.r * 0.44
        px[i], py[i] = x, y

        local tw = 0.62 + 0.38 * (twb_s * p.twc + twb_c * p.tws)
        local col = fx.hsl(p.hue + t * 6, 0.9, 0.52 + 0.14 * tw)

        -- 拖尾：沿轨道往回 0.11 弧度，用和角公式免掉第二次三角函数
        P:line(x, y,
            cx + (ca * TRAIL_C + sa * TRAIL_S) * p.r,
            cy + (sa * TRAIL_C - ca * TRAIL_S) * p.r * 0.44,
            col, 1, math.floor(70 * tw), true)
        P:dot(x, y, p.sz, col, math.floor(150 + 105 * tw))
    end

    -- 近邻连线：距离越近越亮
    for i = 1, N do
        local lim = i + LINK_N
        if lim > N then lim = N end
        for j = i + 1, lim do
            local ddx, ddy = px[i] - px[j], py[i] - py[j]
            local d2 = ddx * ddx + ddy * ddy
            if d2 < LINK_D2 then
                local w = 1 - math.sqrt(d2) / 40
                P:line(px[i], py[i], px[j], py[j], 0x6FD8FF, 1, math.floor(14 + 62 * w), false)
            end
        end
    end

    o.n = P:finish()
    o.shape:set_items(P.items)
end

return M
