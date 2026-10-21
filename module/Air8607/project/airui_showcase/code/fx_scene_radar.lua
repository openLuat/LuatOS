--[[
@module  fx_scene_radar
@summary 特效场景 3 - 雷达扫描
@version 1.0
@date    2026.10.21
@effect
经典 PPI 雷达：4 圈距离环 + 十字准线 + 两条对角虚线 + 36 格方位刻度。
扫描线每帧只前进一小段角度，用 14 条递减透明度的线堆出「余晖扇形」，
比画一整个实心扇形便宜得多，观感也更接近荧光屏。
7 个目标点各自缓慢漂移；判定「上一帧角度 → 本帧角度」是否跨过目标方位，
跨过则点亮回波（亮点 + 向外扩散的涟漪环，随后按时间衰减）。
]]
local fx = require "fx_core"

local M = {
    id = "radar",
    name = "雷达扫描",
    desc = "扫描线扫过 7 个目标触发回波高亮",
}

local TICKS = 36
local GHOST = 14      -- 余晖线数量
local SWEEP_SPEED = 1.15  -- 弧度/秒

function M.build(parent, W, H)
    local o = { w = W, h = H, pool = fx.pool(), sa = 0 }
    o.shape = airui.shape({ parent = parent, x = 0, y = 0, w = W, h = H, items = {} })

    local rnd = fx.rng(660117)
    o.tg = {}
    for i = 1, 7 do
        o.tg[i] = {
            a = rnd() * fx.TAU,
            r = (0.22 + rnd() * 0.72),   -- 归一化半径，绘制时再乘实际 R
            sp = (rnd() - 0.5) * 0.12,   -- 目标自身缓慢漂移
            lit = 0,
        }
    end
    -- 方位刻度角固定，预存方向分量（原写法每帧 36x2 = 72 次三角函数）
    o.tc, o.ts = {}, {}
    for k = 0, TICKS - 1 do
        local a = k * fx.TAU / TICKS
        o.tc[k] = math.cos(a)
        o.ts[k] = math.sin(a)
    end
    return o
end

function M.update(o, t, dt)
    local P = o.pool
    local cx, cy = o.w * 0.5, o.h * 0.5
    local R = math.min(o.w, o.h) * 0.46
    P:reset()

    -- 距离环
    for k = 1, 4 do
        P:ring(cx, cy, math.floor(R * k / 4), 0x1E5C7A, 1, 120)
    end
    -- 十字准线 + 对角虚线
    P:line(cx - R, cy, cx + R, cy, 0x1E5C7A, 1, 110, false)
    P:line(cx, cy - R, cx, cy + R, 0x1E5C7A, 1, 110, false)
    P:dash(cx - 0.70 * R, cy - 0.70 * R, cx + 0.70 * R, cy + 0.70 * R, 0x1E5C7A, 1, 90, 6, 6)
    P:dash(cx - 0.70 * R, cy + 0.70 * R, cx + 0.70 * R, cy - 0.70 * R, 0x1E5C7A, 1, 90, 6, 6)

    -- 方位刻度：每 3 格一根长刻度（角度固定，方向分量在 build 时已算好）
    for k = 0, TICKS - 1 do
        local c, s = o.tc[k], o.ts[k]
        local long = (k % 3 == 0)
        local r0 = R * (long and 0.93 or 0.96)
        P:line(cx + c * r0, cy + s * r0, cx + c * R, cy + s * R,
            long and 0x35E0FF or 0x1E5C7A, long and 2 or 1, long and 200 or 130, true)
    end

    -- 扫描线：本帧角度与余晖扇形
    local sa = (t * SWEEP_SPEED) % fx.TAU
    local prev = o.sa
    o.sa = sa
    local span = (sa - prev) % fx.TAU

    for k = 0, GHOST - 1 do
        local a = sa - k * 0.055
        local opa = math.floor(190 * ((1 - k / GHOST) ^ 1.6))
        P:line(cx, cy, cx + fx.cos(a) * R, cy + fx.sin(a) * R, 0x2BFFD0, 2, opa, false)
    end
    -- 最前缘高亮
    P:line(cx, cy, cx + fx.cos(sa) * R, cy + fx.sin(sa) * R, 0xB6FFF0, 3, 255, true)

    -- 目标点与回波
    for i = 1, #o.tg do
        local g = o.tg[i]
        g.a = (g.a + g.sp * dt) % fx.TAU

        -- 扫描线本帧是否跨过该目标方位
        if span >= 0 and span < 1 then
            local rel = (g.a - prev) % fx.TAU
            if rel <= span then g.lit = 1 end
        end
        g.lit = g.lit - dt * 0.55
        if g.lit < 0 then g.lit = 0 end

        local x = cx + fx.cos(g.a) * g.r * R
        local y = cy + fx.sin(g.a) * g.r * R
        local col = fx.mix(0x2BFF9E, 0xFFFFFF, g.lit)
        P:dot(x, y, 3 + g.lit * 4, col, math.floor(70 + 185 * g.lit))
        if g.lit > 0.05 then
            P:ring(x, y, math.floor(6 + (1 - g.lit) * 11), col, 2, math.floor(150 * g.lit))
        end
    end

    -- 站点中心
    P:dot(cx, cy, 4, 0xB6FFF0, 255)

    o.n = P:finish()
    o.shape:set_items(P.items)
end

return M
