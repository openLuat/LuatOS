--[[
@module  view_line
@summary 视图2 产线透视：五条产线的立体产能柱阵 + 运行状态 / 工单环 / 节拍趋势
@version 1.0
@date    2026.10.23
@author  江访

=== 和视图1 的区别 ===
视图1 是"车间长什么样"（实景），视图2 是"五条线各产出多少"（数据透视）：
中央是一排按透视站立的产能光柱，柱高 = 当班产出，柱身颜色 = 运行状态。
底图压到 opacity 120 当背景纹理，主角换成数据本身。

=== 为什么柱高要按 world 单位给 ===
柱子的屏幕高度 = h * cos(pitch) * k，k 随 z 衰减。
如果直接给"像素高度"，远近不同的柱子透视会互相矛盾；
给 world 高度（0.2~0.9），近大远小才是自洽的。
]]

local T = require "theme"
local B = require "bdui"
local S = require "scene3d"

local c, f = T.c, T.f

local M = { id = "line", name = "产线透视" }

-- 把产出（120..320 pcs/h）归一化到 0..1
local function norm(v)
    if not v then return 0 end
    if v < 120 then return 0 elseif v > 320 then return 1 end
    return (v - 120) / 200
end

-- 五根柱子的世界坐标（一排，z 略有前后差，看着才不像贴纸）
local BARS = {
    { x = -1.32, z = -3.35 },
    { x = -0.66, z = -3.05 },
    { x =  0.00, z = -2.85 },
    { x =  0.66, z = -3.05 },
    { x =  1.32, z = -3.35 },
}

local L1 = { x = 10,  y = 60,  w = 272, h = 232 }
local L2 = { x = 10,  y = 300, w = 272, h = 234 }
local R1 = { x = 742, y = 60,  w = 272, h = 232 }
local R2 = { x = 742, y = 300, w = 272, h = 234 }

function M.build(parent, data)
    local o = { data = data, tx = {}, hot = false }

    o.c1 = B.card(parent, L1, c.cyan)
    o.c2 = B.card(parent, L2, c.violet)
    o.c3 = B.card(parent, R1, c.teal)
    o.c4 = B.card(parent, R2, c.amber)

    o.shape = airui.shape({
        parent = parent, x = 0, y = 0,
        w = T.screen.w, h = T.screen.h, items = {},
    })

    -- ---------- 左1 产线运行 ----------
    B.head(o.c1, "产线运行", L1.w, c.dim)
    o.rowName, o.rowOut, o.rowWo = {}, {}, {}
    for i = 1, data.NLINE do
        local y = 32 + (i - 1) * 40
        o.rowName[i] = B.text(o.c1, 26, y, 84, 18, f.sub, c.txt, airui.TEXT_ALIGN_LEFT, "")
        o.rowOut[i]  = B.text(o.c1, 176, y, 84, 18, f.sub, c.teal, airui.TEXT_ALIGN_RIGHT, "")
        o.rowWo[i]   = B.text(o.c1, 26, y + 17, 130, 16, f.mini, c.dim2, airui.TEXT_ALIGN_LEFT, "")
    end

    -- ---------- 左2 工单进度（3 个 270 度环）+ 趋势 ----------
    B.head(o.c2, "在制工单", L2.w, c.dim)
    o.ordVal, o.ordName = {}, {}
    for i = 1, 3 do
        local cx = 46 + (i - 1) * 90
        -- 环心在 y=98，读数必须落在环内（y 84 起），否则会压到环上
        o.ordVal[i]  = B.text(o.c2, cx - 45, 84, 90, 26, f.val, c.txt, airui.TEXT_ALIGN_CENTER, "")
        o.ordName[i] = B.text(o.c2, cx - 45, 138, 90, 16, f.mini, c.dim, airui.TEXT_ALIGN_CENTER, "")
    end
    o.ordTrendTag = B.text(o.c2, 12, 152, 140, 16, f.mini, c.dim2, airui.TEXT_ALIGN_LEFT, "当班产出趋势")

    -- ---------- 右1 产能构成 ----------
    B.head(o.c3, "产能构成", R1.w, c.dim)
    o.capName, o.capVal = {}, {}
    for i = 1, data.NLINE do
        local y = 36 + (i - 1) * 34
        o.capName[i] = B.text(o.c3, 12, y, 80, 16, f.mini, c.dim, airui.TEXT_ALIGN_LEFT, "")
        o.capVal[i]  = B.text(o.c3, 204, y, 56, 16, f.mini, c.teal, airui.TEXT_ALIGN_RIGHT, "")
    end

    -- ---------- 右2 节拍趋势 ----------
    B.head(o.c4, "节拍与产出", R2.w, c.dim)
    o.cycle  = B.text(o.c4, 12, 30, 150, 46, f.big, c.txt, airui.TEXT_ALIGN_LEFT, "12.4")
    o.cycleU = B.text(o.c4, 128, 54, 44, 18, f.mini, c.amber, airui.TEXT_ALIGN_LEFT, "s")
    o.minMax = B.text(o.c4, 168, 34, 92, 16, f.mini, c.dim, airui.TEXT_ALIGN_RIGHT, "")
    o.minMax2 = B.text(o.c4, 168, 52, 92, 16, f.mini, c.dim2, airui.TEXT_ALIGN_RIGHT, "最快 / 最慢")
    o.sparkTag = B.text(o.c4, 12, 82, 150, 16, f.mini, c.dim2, airui.TEXT_ALIGN_LEFT, "近 20 个采样")

    --[[柱底标签：只放产线名，一行
    早先这里压了"名字 + pcs/h"两行，五根柱子横向间距只有 68px，
    相邻两行必然叠字；产出读数在左侧「产线运行」里已经有了。]]
    o.barTag = {}
    for i = 1, #BARS do
        local sx, sy = S.at(BARS[i].x, 0, BARS[i].z)
        o.barTag[i] = airui.label({
            parent = parent, x = math.floor(sx) - 30, y = math.floor(sy) + 10,
            w = 60, h = 18, text = "", font_size = f.sub, color = c.cyan,
            align = airui.TEXT_ALIGN_CENTER,
        })
    end

    o.buf = {}

    -- 传送带折线（两端各延长 0.12，让光点从画面外进来）
    o.px, o.pz = {}, {}
    o.px[1], o.pz[1] = BARS[1].x - 0.12, BARS[1].z
    for i = 1, #BARS do
        o.px[i + 1] = BARS[i].x
        o.pz[i + 1] = BARS[i].z
    end
    o.px[#BARS + 2] = BARS[#BARS].x + 0.12
    o.pz[#BARS + 2] = BARS[#BARS].z
    return o
end

function M.update(o, P, t, dt)
    local d = o.data
    B.hot(o, dt)

    -- ---------------- 面板 ----------------
    B.brackets(P, L1, c.cyan, 120)
    B.brackets(P, R2, c.amber, 120)

    -- 左1：每行一条节拍进度条 + 状态灯
    for i = 1, d.NLINE do
        local L = d.lines[i]
        local y = L1.y + 32 + (i - 1) * 40
        local scon = B.STATE_COL[L.state]
        local br = 3 + 1.4 * (0.5 + 0.5 * math.sin(t * 2.0 + L.phase))
        P:dot(L1.x + 14, y + 8, math.floor(br * 2.2), scon, 40)
        P:dot(L1.x + 14, y + 8, math.floor(br), scon, 235)
        B.bar(P, L1.x + 26, y + 36, L1.w - 40, 4, L.cycle, scon)
    end

    -- 左2：三个 270 度环（导轨 + 点串）
    for i = 1, 3 do
        local L = d.lines[i]
        local cx = L2.x + 46 + (i - 1) * 90
        local cy = L2.y + 98
        B.gauge(P, cx, cy, 30, L.cycle, B.STATE_COL[L.state],
            math.pi * 0.75, math.pi * 2.25, 5, 12)
    end
    -- 趋势
    B.spark(P, d.sample(d.series.prod, 20, o.buf), 20,
        L2.x + 12, L2.y + 172, L2.w - 28, 44, c.violet, 1, 200)

    -- 右1：五条水平产能条
    for i = 1, d.NLINE do
        local L = d.lines[i]
        local y = R1.y + 36 + (i - 1) * 34
        local frac = norm(L.out)
        B.bar(P, R1.x + 88, y + 4, 108, 6, frac, c.teal)
    end

    -- 右2：产出曲线
    B.spark(P, d.sample(d.series.prod, 24, o.buf), 24,
        R2.x + 12, R2.y + 106, R2.w - 28, 92, c.amber, 1, 190)

    -- ---------------- 中央柱阵 ----------------
    S.grid(P, t, -1.5, 1.5, T.ground.z0, T.ground.z1, T.ground.step, c.grid, c.cyan)

    --[[传送带光流：必须沿柱底（BARS 的 x/z）连成折线
    早先图省事画在固定的 z=-3.1 直线上，结果那根线浮在柱底上方十几像素，
    看起来像"柱子悬空"——世界坐标不一致的叠加层一眼就能看出来。
    折线在 build 里预建成 o.px / o.pz，每帧只做投影，不新建表。]]
    S.flow(P, o.px, o.pz, #o.px, t, c.teal, 2.2, 6, 130)

    for i = #BARS, 1, -1 do
        local L = d.lines[i]
        local b = BARS[i]
        local h = 0.22 + 0.62 * norm(L.out)
        S.pillar(P, b.x, b.z, h, L.cycle, B.STATE_COL[L.state], t, i * 0.9)
    end

    -- ---------------- 文字（5Hz）----------------
    if o.hot then
        for i = 1, d.NLINE do
            local L = d.lines[i]
            B.put(o.rowName[i], L.name, o, "rn" .. i)
            B.put(o.rowOut[i], string.format("%d pcs/h", math.floor(L.out * 1.6)), o, "ro" .. i)
            B.put(o.rowWo[i], string.format("%s  %s", L.wo, B.STATE_TXT[L.state]), o, "rw" .. i)
            B.put(o.capName[i], L.name, o, "cn" .. i)
            B.put(o.capVal[i], string.format("%.0f%%", norm(L.out) * 100), o, "cv" .. i)
            B.put(o.barTag[i], L.name, o, "bt" .. i)
        end

        for i = 1, 3 do
            local L = d.lines[i]
            B.put(o.ordVal[i], string.format("%d%%", math.floor(L.cycle * 100)), o, "ov" .. i)
            B.put(o.ordName[i], L.wo, o, "on" .. i)
        end

        B.put(o.cycle, string.format("%.1f", d.kpi.cycle), o, "cy")
        B.put(o.minMax, string.format("%.1f / %.1f s", 11.2, 13.6), o, "mm")
    end
end

return M
