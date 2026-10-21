--[[
@module  fx_scene_tunnel
@summary 特效场景 6 - 时空隧道
@version 1.0
@date    2026.10.21
@effect
透视隧道：12 层圆角方框按 (进度)^2 的透视曲线由远及近放大并逐渐提亮，
配合 12 条旋转辐条形成「穿过隧道」的速度感。
60 颗流星按各自的径向速度向屏幕外飞散，越靠外拖尾越长、越亮；
用 (r)^2 做径向映射而不是线性，才有一闪而过的加速感。
]]
local fx = require "fx_core"

local M = {
    id = "tunnel",
    name = "时空隧道",
    desc = "透视方框与流星向外飞散",
}

local LAYERS = 12
local SPOKES = 12
local STARS = 60

function M.build(parent, W, H)
    local o = { w = W, h = H, pool = fx.pool() }
    o.shape = airui.shape({ parent = parent, x = 0, y = 0, w = W, h = H, items = {} })

    local rnd = fx.rng(1024 * 600)
    o.st = {}
    for i = 1, STARS do
        -- 流星的飞散角度整场不变，直接存方向分量，省掉每帧 2 次三角函数
        local a = rnd() * fx.TAU
        o.st[i] = {
            ca = math.cos(a),
            sa = math.sin(a),
            p = rnd(),                    -- 初始相位，保证流星均匀分布
            sp = 0.10 + rnd() * 0.22,     -- 径向速度（每秒推进的归一化进度）
        }
    end
    -- 辐条的固定角分量 cos(k*TAU/SPOKES) / sin(k*TAU/SPOKES)
    o.kc, o.ks = {}, {}
    for k = 0, SPOKES - 1 do
        local a = k * fx.TAU / SPOKES
        o.kc[k] = math.cos(a)
        o.ks[k] = math.sin(a)
    end
    return o
end

function M.update(o, t, dt)
    local P = o.pool
    local W, H = o.w, o.h
    local cx, cy = W * 0.5, H * 0.5
    local R = math.min(W, H) * 0.48
    P:reset()

    -- 辐条：和角公式拆出固定角分量，整帧只需 2 次三角函数
    local ct, st = fx.cos(t * 0.12), fx.sin(t * 0.12)
    for k = 0, SPOKES - 1 do
        local c = o.kc[k] * ct - o.ks[k] * st
        local s = o.ks[k] * ct + o.kc[k] * st
        P:line(cx + c * R * 0.10, cy + s * R * 0.10,
               cx + c * R * 1.25, cy + s * R * 1.25, 0x1F6FA8, 1, 90, false)
    end

    -- 透视方框：s 由 0（远）到 1（近），尺寸按 s^2 展开
    for k = 0, LAYERS - 1 do
        local s = ((k + t * 0.55) % LAYERS) / LAYERS
        local e = s * s
        local sw = 40 + e * (W * 1.15)
        local sh = 24 + e * (H * 1.30)
        local opa = math.floor(40 + 200 * e)
        local col = fx.hsl(268 + s * 70, 0.95, 0.34 + 0.30 * e)
        P:frame(cx - sw / 2, cy - sh / 2, sw, sh, col, math.max(1, math.floor(1 + 3 * e)), opa, 6)
    end

    -- 流星拖尾
    for i = 1, STARS do
        local p = o.st[i]
        local r = (p.p + t * p.sp) % 1
        local e = r * r * 1.15
        local r2 = r - 0.05
        if r2 < 0 then r2 = 0 end
        local e2 = r2 * r2 * 1.15
        local rr = 8 + e * R * 1.5
        local rrq = 8 + e2 * R * 1.5
        local c, s = p.ca, p.sa
        local col = fx.hsl(190 + e * 120, 0.9, 0.48 + 0.30 * e)
        -- e 的上界是 1.15（透视系数），这里必须夹到 255，否则透明度会溢出成一个乱值
        local opa = math.floor(fx.clamp(60 + 195 * e, 0, 255))
        P:line(cx + c * rrq, cy + s * rrq, cx + c * rr, cy + s * rr,
            col, math.max(1, math.floor(1 + 2 * e)), opa, true)
    end

    -- 隧道尽头的光核
    P:dot(cx, cy, 26, 0x6A3CFF, 50)
    P:dot(cx, cy, 14, 0xB79BFF, 120)
    P:dot(cx, cy, 6, 0xFFFFFF, 220)

    o.n = P:finish()
    o.shape:set_items(P.items)
end

return M
