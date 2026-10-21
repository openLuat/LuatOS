--[[
@module  fx_scene_spectrum
@summary 特效场景 2 - 频谱律动
@version 1.0
@date    2026.10.21
@effect
28 段虚拟频谱：三个不同频率的正弦叠加出「不像纯正弦」的跳动曲线，
再乘上一个 2Hz 的节拍脉冲和高频颤动，观感接近真实音乐频谱。
柱体颜色按「频段 + 时间」做 HSL 流动渐变（低频青 → 高频品红）；
每根柱子下方向下投一段半透明倒影；顶部有会缓慢下落的白色峰值保持帽。
]]
local fx = require "fx_core"

local M = {
    id = "spectrum",
    name = "频谱律动",
    desc = "28 段虚拟频谱带峰值保持与倒影",
}

local NB = 28        -- 频段数
local PAD = 26       -- 左右留白
local FALL = 0.42    -- 峰值帽下落速度（每秒）

function M.build(parent, W, H)
    local o = { w = W, h = H, pool = fx.pool(), peak = {}, val = {} }
    for i = 1, NB do
        o.peak[i] = 0.05
        o.val[i] = 0.05
    end
    o.shape = airui.shape({ parent = parent, x = 0, y = 0, w = W, h = H, items = {} })

    --[[预计算每个频段的空间分量
    4 个 sin 都是 sin(t*w ± i*k) 形式，i（频段序号）固定。
    按和角公式展开后空间部分整场不变，每帧只留 4 个时间项共 8 次三角函数
    （原写法是 28 段 x 4 次 = 112 次）。]]
    o.ci, o.si = {}, {}   -- 每项一组 {cos(i*k), sin(i*k)}
    for i = 1, NB do
        o.ci[i] = {
            math.cos(i * 0.62), math.cos(i * 0.95), math.cos(i * 0.23), math.cos(i),
        }
        o.si[i] = {
            math.sin(i * 0.62), math.sin(i * 0.95), math.sin(i * 0.23), math.sin(i),
        }
    end
    return o
end

function M.update(o, t, dt)
    local P = o.pool
    local W, H = o.w, o.h
    P:reset()

    local bw = math.floor((W - PAD * 2) / NB)
    local base = math.floor(H * 0.62)
    local maxh = math.floor(H * 0.44)
    local beat = 0.72 + 0.28 * fx.sin(t * 3.6)

    -- 4 个时间项的 sin/cos：整帧只有这 8 次三角函数
    local s1, c1 = fx.sin(t * 3.3), fx.cos(t * 3.3)
    local s2, c2 = fx.sin(t * 5.1), fx.cos(t * 5.1)
    local s3, c3 = fx.sin(t * 1.6), fx.cos(t * 1.6)
    local s4, c4 = fx.sin(t * 7.3), fx.cos(t * 7.3)

    for i = 1, NB do
        local f = (i - 1) / (NB - 1)
        local ci, si = o.ci[i], o.si[i]
        -- 三频叠加：主摆动 + 细节抖动 + 慢速起伏（和角公式展开，第 2 项时间符号为负）
        local v = (0.5 + 0.5 * (s1 * ci[1] + c1 * si[1])) * 0.55
                + (0.5 + 0.5 * (s2 * ci[2] - c2 * si[2])) * 0.28
                + (0.5 + 0.5 * (s3 * ci[3] + c3 * si[3])) * 0.17
        -- 高频段整体衰减（真实频谱的能量分布特征）
        v = v * (1 - f * 0.5) * beat
        v = v * (0.84 + 0.16 * (0.5 + 0.5 * (s4 * ci[4] + c4 * si[4])))
        v = fx.clamp(v, 0.05, 1)

        -- 峰值保持：快速上升、缓慢下落
        if v > o.peak[i] then
            o.peak[i] = v
        else
            o.peak[i] = o.peak[i] - dt * FALL
            if o.peak[i] < v then o.peak[i] = v end
        end
        o.val[i] = v

        local x = PAD + (i - 1) * bw
        local iw = bw - 3
        local h = math.max(4, math.floor(v * maxh))
        local col = fx.hsl(188 + f * 140 + t * 10, 0.92, 0.40 + 0.24 * v)

        -- 柱体
        P:box(x + 1, base - h, iw, h, col, 255, 3)
        -- 倒影（高度为柱体 34%，压到 60 透明度）
        P:box(x + 1, base + 5, iw, math.floor(h * 0.34), col, 60, 3)
        -- 峰值保持帽
        local py = base - math.max(5, math.floor(o.peak[i] * maxh)) - 5
        P:box(x + 1, py, iw, 3, 0xFFFFFF, 210, 1)
    end

    -- 基座分隔线
    P:line(PAD, base + 3, W - PAD, base + 3, 0x2A4A6B, 2, 255, true)

    o.n = P:finish()
    o.shape:set_items(P.items)
end

return M
