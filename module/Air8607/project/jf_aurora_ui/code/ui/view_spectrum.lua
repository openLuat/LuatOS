--[[
@module  view_spectrum
@summary AURORA UI - 页面 2「声场」：镜像频谱 + 峰值保持 + 拍频冲击波
@version 1.0
@date    2026.10.22
@author  江访

=== 视觉效果 ===
1、30 段镜像频谱：左右完全对称（第 i 段与第 31-i 段共用同一份能量），
   柱体颜色按频段 + 幅度做 HSL 插值，顶部有一片"峰值帽"缓慢下落。
2、倒影：基线下方再画一遍 45% 高度的柱体，透明度只有 40，
   深色底上像一块会呼吸的玻璃地板，这是纯绘制最容易做出"高级感"的一招。
3、顶部瀑布：46 列窄条记录最近 46 帧的总能量，颜色随能量从青到品红。
4、拍频检测：低频能量越过阈值时从基线中心发出几圈扩散冲击波
   （环 + 一条贯穿基线的高亮横线），并给整屏一个短促的亮度脉冲。

=== 为什么能量是"造"出来的 ===
本工程是纯 UI 演示，不采集麦克风。能量由一维平滑噪声 + 正弦包络合成，
低频段幅度大、高频段衰减，再加一个 2.4Hz 的节拍源触发冲击波，
观感与真实音乐频谱一致，且固定种子可复现。

=== 预算 ===
30 柱 + 30 倒影 + 30 峰值帽 + 46 瀑布列 + 4 冲击波环 ≈ 140 个图元/帧。
]]
local fx = require "fx"

local M = {
    id = "spectrum",
    name = "声场",
    en = "SPECTRUM",
    desc = "30 段镜像频谱  拍频冲击波",
}

--[[频段数与柱宽必须和 HERO 宽度对得上
HERO 宽 628，30 段 x 20px = 600 < 628，两侧各留 14px 余量。
一开始写的 PITCH=22（总宽 660）会让最左最右两根柱子被裁掉半截，
这种"差一点点出界"的问题只在栅格化/真机截图里才看得出来。]]
local NB      = 30        -- 频段数（镜像后仍是 30 根柱）
local BW      = 13        -- 柱宽
local PITCH   = 20        -- 柱间距（含间隔）
local BASE_Y  = 0.62      -- 基线在 hero 高度中的比例
local MAX_H   = 190       -- 柱体最大高度（顶到 y≈72，正好在瀑布下方留出呼吸位）
local REFL    = 0.42      -- 倒影高度比
local WF_N    = 46        -- 瀑布列数
local WF_H    = 22        -- 瀑布条高

local function fmt(v, n)
    return string.format("%." .. n .. "f", v)
end

function M.build(parent, W, H, card)
    local o = {
        w = W, h = H,
        pool = fx.pool(),
        ppool = fx.pool(),
        v = {}, peak = {}, wf = {},
        nwf = 0,
        bass = 0, energy = 0, beat = 0,
        rings = {},
        play = 0, vol = 62,
    }
    o.cx = W * 0.5
    o.base = math.floor(H * BASE_Y)
    -- 低频包络：第 1 段最响，向高频线性衰减，模拟音乐频谱的能量分布
    o.env = {}
    for i = 1, NB do
        local d = math.abs(i - NB * 0.5) / (NB * 0.5)   -- 0(中间) .. 1(两端)
        o.env[i] = 0.42 + 0.58 * (1 - d * d)
        o.v[i] = 0
        o.peak[i] = 0
    end
    for i = 1, WF_N do o.wf[i] = 0 end
    for i = 1, 4 do o.rings[i] = { r = -1, life = 0 } end
    o.ring_i = 1

    o.shape = airui.shape({
        parent = parent, x = 0, y = 0, w = W, h = H, items = {},
    })

    if card then
        o.c1 = card(1, "采样率", 0x22E6FF, "48.0 kHz", "24bit / 立体声")
        o.c2 = card(2, "低频能量", 0xFF3D9A, "0.00", "实时包络")
        o.c3 = card(3, "音量", 0x2BE59D, "62 %", "触摸滑块可调")
        --[[用原生 airui.slider 做音量条
        7 个 UI Store demo 里 slider / switch / chart / animimg 一个都没用过，
        这里把滑块塞进玻璃卡片，滑块样式全部按卡片配色重写，避免 LVGL 默认蓝。]]
        o.slider = airui.slider({
            parent = o.c3.root,
            x = 18, y = 92, w = o.c3.w - 36, h = 22,
            min = 0, max = 100, value = 62,
            style = {
                bg_color = 0x16233C, bg_opa = 255,
                radius = 11, pad = 0,
                indicator_color = 0x2BE59D,
                knob_color = 0xE9FFF6,
            },
            -- 回调只收到组件自身（airui 的 VALUE_CHANGED 不会带数值参数），
            -- 所以用 slider:get_value() 回读，而不是指望第二个参数
            on_change = function(obj)
                local ok, v = pcall(function() return obj:get_value() end)
                if ok and type(v) == "number" then o.vol = v end
            end,
        })
        o.lbl_v = "62 %"
    end
    return o
end

-- ==================== 每帧绘制 ====================
function M.update(o, t, dt)
    local P = o.pool
    local W, H = o.w, o.h
    local cx, base = o.cx, o.base
    P:reset()

    -- ==================== 能量合成 ====================
    --[[三路噪声叠加：慢速（段落感）+ 中速（鼓点）+ 快速（抖动）
    节拍用 2.4Hz 的相位做包络，过零后给一个短促的冲击。]]
    local beat_phase = (t * 2.4) % 1
    local kick = (beat_phase < 0.16) and (1 - beat_phase / 0.16) or 0
    local bass = fx.clamp(0.32 + 0.52 * fx.noise1(t * 1.7) + 0.34 * kick, 0, 1)
    o.bass = bass
    local total = 0
    for i = 1, NB do
        local env = o.env[i]
        local nz = fx.noise1(t * (2.6 + i * 0.13) + i * 7.7)
        -- 越靠两端的频段抖动越快、幅度越小
        local target = env * (0.34 + 0.60 * nz) + env * kick * 0.55
        local cur = o.v[i]
        -- 上升快、下落慢：这是频谱观感的关键，单纯线性跟随会显得"塑料"
        local rate = (target > cur) and 0.55 or 0.13
        cur = cur + (target - cur) * (1 - (1 - rate) ^ (dt * 60))
        o.v[i] = cur
        total = total + cur
        -- 峰值帽：只升不降，之后按固定速度下落
        if cur > o.peak[i] then
            o.peak[i] = cur
        else
            o.peak[i] = math.max(cur, o.peak[i] - dt * 0.42)
        end
    end
    o.energy = total / NB

    -- ==================== 拍频冲击波 ====================
    if kick > 0.9 and beat_phase < 0.06 then
        local g = o.rings[o.ring_i]
        g.r = 10
        g.life = 1
        o.ring_i = o.ring_i % 4 + 1
        o.beat = 1
    end
    o.beat = math.max(0, o.beat - dt * 2.6)

    -- ==================== 顶部瀑布 ====================
    local wf = o.wf
    o.nwf = o.nwf % WF_N + 1
    wf[o.nwf] = o.energy
    local wf_w = 12
    local wf_x0 = cx - WF_N * wf_w * 0.5
    for i = 1, WF_N do
        local idx = (o.nwf + i - 1) % WF_N + 1
        local e = wf[idx]
        local col = fx.hsl(196 - 96 * e, 0.85, 0.28 + 0.32 * e)
        P:box(wf_x0 + (i - 1) * wf_w, 26, wf_w - 3, WF_H, col, math.floor(60 + 170 * e), 2)
    end
    -- 瀑布下面的两条装饰细线
    P:line(wf_x0, 26 + WF_H + 5, wf_x0 + WF_N * wf_w - 3, 26 + WF_H + 5, 0x1B2C48, 1, 120)

    -- ==================== 基线 ====================
    local half = (NB * PITCH) * 0.5
    P:line(cx - half - 10, base, cx + half + 10, base,
        fx.mix(0x22E6FF, 0xFFFFFF, o.beat * 0.7), 1,
        math.floor(120 + 120 * o.beat))

    -- ==================== 柱体 ====================
    for i = 1, NB do
        -- 镜像：两侧共用同一份能量，中间最高
        local mi = (i <= NB * 0.5) and i or (NB - i + 1)
        local e = o.v[mi]
        local pk = o.peak[mi]
        local x = cx - half + (i - 1) * PITCH + (PITCH - BW) * 0.5
        local hgt = math.max(2, e * MAX_H)
        -- 色相：中间青绿、两侧品红，幅度越高越亮
        local hue = 186 - 96 * math.min(1, e * 1.15)
        local col = fx.hsl(hue, 0.92, 0.40 + 0.30 * e)

        -- 倒影（先画，被柱体压住上沿，看起来像玻璃反射）
        local rh = hgt * REFL
        P:box(x, base + 2, BW, rh, col, 40, 3)
        -- 柱体
        P:box(x, base - hgt, BW, hgt, col, 232, 3)
        -- 顶部高光（一段更亮的短柱，柱头才有"灯管"感）
        P:box(x, base - hgt, BW, math.min(4, hgt), fx.shade(col, 0.55), 235, 2)
        -- 峰值帽
        local py = base - pk * MAX_H
        if py < base - 3 then
            P:box(x, py - 2, BW, 3, 0xFFFFFF, 200, 1)
        end
    end

    -- ==================== 冲击波 ====================
    for i = 1, 4 do
        local g = o.rings[i]
        if g.life > 0 then
            g.r = g.r + dt * 320
            g.life = g.life - dt * 1.5
            if g.life <= 0 then
                g.life = 0
            else
                local opa = math.floor(120 * g.life)
                P:ellipse(cx, base, g.r, g.r * 0.42, 0xBFF4FF, 2, opa, 40)
                P:ellipse(cx, base, g.r * 0.72, g.r * 0.30, 0x22E6FF, 1,
                    math.floor(opa * 0.6), 36)
            end
        end
    end

    -- 拍频瞬间的横向贯穿高亮（宽度夹住，别伸出 HERO 被裁掉两头）
    if o.beat > 0.05 then
        local w2 = math.min(half * (1 + 0.1 * o.beat), 308)
        P:line(cx - w2, base, cx + w2, base, 0xFFFFFF, 2, math.floor(220 * o.beat))
    end

    o.n = P:finish()
    o.shape:set_items(P.items)
end

-- ==================== 右侧卡片（5Hz） ====================
function M.panel(o, t, dt)
    if not o.c1 then return end
    o.play = (o.play + dt) % 214.0      -- 3:34 循环

    local P = o.ppool
    -- 卡 1：采样率（静态数值）+ 一条占满的能量条
    P:reset()
    fx.meter(P, 18, 106, o.c1.w - 36, 8, 0.88, 0x22E6FF)
    P:finish()
    o.c1.shape:set_items(P.items)

    -- 卡 2：低频能量实时条
    P:reset()
    fx.meter(P, 18, 106, o.c2.w - 36, 8, o.bass, 0xFF3D9A)
    P:finish()
    o.c2.shape:set_items(P.items)

    -- 卡 3：音量条（滑块本体是原生 airui.slider，这里只画刻度底纹）
    P:reset()
    P:line(18, 112, o.c3.w - 18, 112, 0x1B2C48, 1, 140)
    P:finish()
    o.c3.shape:set_items(P.items)

    local v = fmt(o.bass, 2)
    if v ~= o.bass_txt then
        o.bass_txt = v
        o.c2.value:set_text(v)
    end
    v = tostring(math.floor(o.vol + 0.5)) .. " %"
    if v ~= o.lbl_v then
        o.lbl_v = v
        o.c3.value:set_text(v)
    end
    local sec = math.floor(o.play)
    local txt = string.format("%02d:%02d", math.floor(sec / 60), sec % 60)
    if txt ~= o.play_txt then
        o.play_txt = txt
        o.c1.sub:set_text(txt .. " / 03:34")
    end
end

-- 本页没有拖拽交互：触摸交给外壳做通用处理
function M.touch(o, ev, x, y)
    return false
end

return M
