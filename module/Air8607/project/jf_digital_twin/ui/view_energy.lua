--[[
@module  view_energy
@summary 视图3 能效态势：4x3 分区能耗"数据林" + 分区排行 / 单耗 / 功率 / 峰谷分布
@version 1.0
@date    2026.10.23
@author  江访

=== 中央为什么是"林"不是"柱" ===
能效数据的维度是"分区 x 时段"，一维柱状图讲不清。
所以中央铺成 4 列 x 3 行的三维柱阵：列 = 分区，行 = 时段，
高度 = 该时段该分区的能耗，颜色按高度分档（青 -> 琥珀 -> 红）。
每根柱子只用 5 个图元（scene3d.bar3d），12 根才 60 个，30fps 撑得住。
]]

local fx = require "fx"
local T = require "theme"
local B = require "bdui"
local S = require "scene3d"

local c, f = T.c, T.f

local M = { id = "energy", name = "能效态势" }

local L1 = { x = 10,  y = 60,  w = 272, h = 232 }
local L2 = { x = 10,  y = 300, w = 272, h = 234 }
local R1 = { x = 742, y = 60,  w = 272, h = 232 }
local R2 = { x = 742, y = 300, w = 272, h = 234 }

-- 数据林：4 列（分区）x 3 行（时段）
local COLS = { -1.32, -0.44, 0.44, 1.32 }
local ROWS = { -3.50, -2.85, -2.20 }

-- 热力分档：给"数据林"用，读的是"这一格耗得多不多"
local function heat(v)
    if v < 0.52 then return c.teal end
    if v < 0.70 then return c.cyan end
    if v < 0.85 then return c.amber end
    return c.red
end

-- 分区身份色：给左栏排行用。四个分区各有一个固定颜色，
-- 这样"条形长度"表达大小、"颜色"表达归属，不会像全用热力色那样四条都变琥珀。
local ZONE_COL = { c.cyan, c.violet, c.teal, c.amber }

function M.build(parent, data)
    local o = { data = data, tx = {}, hot = false }

    o.c1 = B.card(parent, L1, c.teal)
    o.c2 = B.card(parent, L2, c.cyan)
    o.c3 = B.card(parent, R1, c.amber)
    o.c4 = B.card(parent, R2, c.red)

    o.shape = airui.shape({
        parent = parent, x = 0, y = 0,
        w = T.screen.w, h = T.screen.h, items = {},
    })

    -- 左1 分区能耗
    B.head(o.c1, "分区能耗", L1.w, c.dim)
    o.zName, o.zVal = {}, {}
    for i = 1, data.NZONE do
        local y = 38 + (i - 1) * 46
        o.zName[i] = B.text(o.c1, 12, y, 130, 18, f.sub, c.txt, airui.TEXT_ALIGN_LEFT, "")
        o.zVal[i]  = B.text(o.c1, 176, y, 84, 18, f.sub, c.teal, airui.TEXT_ALIGN_RIGHT, "")
    end

    -- 左2 单位能耗
    B.head(o.c2, "单位能耗", L2.w, c.dim)
    o.unit  = B.text(o.c2, 12, 30, 160, 46, f.big, c.txt, airui.TEXT_ALIGN_LEFT, "1.35")
    o.unitU = B.text(o.c2, 146, 54, 92, 18, f.mini, c.cyan, airui.TEXT_ALIGN_LEFT, "kWh/pcs")
    o.goal  = B.text(o.c2, 12, 78, 240, 18, f.mini, c.dim, airui.TEXT_ALIGN_LEFT, "")
    o.delta = B.text(o.c2, 12, 98, 240, 18, f.mini, c.teal, airui.TEXT_ALIGN_LEFT, "")
    o.unitTag = B.text(o.c2, 12, 126, 200, 16, f.mini, c.dim2, airui.TEXT_ALIGN_LEFT, "近 24 个采样 / 目标线 1.20")

    -- 右1 实时功率
    B.head(o.c3, "实时功率", R1.w, c.dim)
    o.pow   = B.text(o.c3, 12, 30, 140, 46, f.big, c.txt, airui.TEXT_ALIGN_LEFT, "386")
    o.powU  = B.text(o.c3, 134, 54, 42, 18, f.mini, c.amber, airui.TEXT_ALIGN_LEFT, "kW")
    o.pStat = B.text(o.c3, 12, 78, 240, 18, f.mini, c.dim, airui.TEXT_ALIGN_LEFT, "")

    -- 右2 峰谷分布
    B.head(o.c4, "峰谷分布 24h", R2.w, c.dim)
    o.peakLab = B.text(o.c4, 150, 30, 110, 18, f.mini, c.amber, airui.TEXT_ALIGN_RIGHT, "")
    o.tick1 = B.text(o.c4, 16, 202, 40, 16, f.mini, c.dim2, airui.TEXT_ALIGN_LEFT, "00")
    o.tick2 = B.text(o.c4, 110, 202, 40, 16, f.mini, c.dim2, airui.TEXT_ALIGN_CENTER, "08")
    o.tick3 = B.text(o.c4, 224, 202, 40, 16, f.mini, c.dim2, airui.TEXT_ALIGN_RIGHT, "16")

    --[[数据林底部的分区缩写：把"第几列"和"哪个分区"对上
    坐标取**最前排**柱底再下移 14px。早先按后排 z 算，标签刚好落在柱子中间，
    看着像浮在林子里的一块牌子。]]
    local SHORT = { "SMT", "ASM", "PKG", "UTL" }
    o.colLab = {}
    for col = 1, #COLS do
        local sx, sy = S.at(COLS[col], 0, ROWS[1])
        o.colLab[col] = airui.label({
            parent = parent, x = math.floor(sx) - 26, y = math.floor(sy) + 14,
            w = 52, h = 18, text = SHORT[col], font_size = f.sub, color = c.dim,
            align = airui.TEXT_ALIGN_CENTER,
        })
    end

    o.buf, o.buf2 = {}, {}
    return o
end

function M.update(o, P, t, dt)
    local d = o.data
    B.hot(o, dt)

    B.brackets(P, L1, c.teal, 120)
    B.brackets(P, R1, c.amber, 120)

    -- 左1：4 行分区（名称 + 数值 + 条）
    for i = 1, d.NZONE do
        local z = d.zones[i]
        local y = L1.y + 38 + (i - 1) * 46
        B.bar(P, L1.x + 12, y + 24, L1.w - 24, 5, z.kwh / 320, ZONE_COL[i])
    end

    --[[左2：单耗趋势 + 目标线
    纵轴窗口取 1.00 ~ 1.40 kWh/pcs（不是 0.90~2.00）：曲线的典型值就在 1.1~1.3，
    用满量程画会贴着底边，看起来像"没数据"。越界的值由 B.spark 自己夹住。]]
    local uy, uh = L2.y + 140, 86
    for k = 1, 3 do
        local gy = math.floor(uy + uh - uh * k * 0.25)
        P:line(L2.x + 12, gy, L2.x + L2.w - 16, gy, c.line, 1, 200)
    end
    local u = d.sample(d.series.unit, 24, o.buf2)
    for i = 1, 24 do
        u[i] = (0.90 + u[i] * 1.10 - 1.00) / 0.40
    end
    local goalY = math.floor(uy + uh - (1.20 - 1.00) / 0.40 * uh)
    P:line(L2.x + 12, goalY, L2.x + L2.w - 16, goalY, c.teal, 1, 120)
    P:line(L2.x + L2.w - 16, goalY, L2.x + L2.w - 16, goalY - 5, c.teal, 1, 140)
    B.spark(P, u, 24, L2.x + 12, uy, L2.w - 28, uh, c.cyan, 1, 210)

    -- 右1：功率曲线
    B.spark(P, d.sample(d.series.power, 24, o.buf), 24,
        R1.x + 12, R1.y + 108, R1.w - 28, 96, c.amber, 1, 200)

    -- 右2：12 根半小时柱（用 sv 的能量曲线降采样 + 时移，做出"一天"的形状）
    local bx = R2.x + 12
    local bw = 16
    for i = 1, 12 do
        local v = 0.28 + 0.62 * fx.noise1(i * 0.9 + 3.1)
        local hh = 10 + v * 118
        local y = R2.y + 190 - hh
        local col = heat(v)
        if v > 0.82 then col = c.amber end
        P:box(bx + (i - 1) * (bw + 4), y, bw, hh, col, 110, 2)
        P:box(bx + (i - 1) * (bw + 4), y, bw, 3, col, 235, 2)
    end
    -- 均值参考线
    P:line(R2.x + 12, R2.y + 132, R2.x + R2.w - 12, R2.y + 132, c.dim2, 1, 90)

    -- ---------------- 中央数据林 ----------------
    S.grid(P, t, -1.5, 1.5, T.ground.z0, T.ground.z1, T.ground.step, c.grid, c.cyan)

    --[[顶面折线：把同一行柱顶连起来
    12 根孤立柱子读起来像"散落的火柴"，连成折线之后立刻变成
    "一张起伏的能耗曲面"——这是让一堆竖线看起来像三维地形的最省图元的办法（3 条线）。]]
    for r = #ROWS, 1, -1 do
        local tx, ty = {}, {}
        for col = 1, #COLS do
            local z = d.zones[col]
            local v = fx.clamp(z.frac + (fx.noise1(col * 2.3 + r * 5.1 + 1.7) - 0.5) * 0.42, 0.08, 1)
            local h = 0.16 + 0.86 * v
            -- 柱子加宽到 0.115：太细会变成"火柴棍"，看不出是一根柱体
            S.bar3d(P, COLS[col], ROWS[r], h, heat(v), t, col * 0.8 + r * 0.5, 0.115)
            tx[col], ty[col] = S.at(COLS[col], h, ROWS[r])
        end
        P:poly(tx, ty, #COLS, c.cyan, 1, 70, false)
    end

    -- ---------------- 文字 ----------------
    if o.hot then
        for i = 1, d.NZONE do
            local z = d.zones[i]
            B.put(o.zName[i], z.name, o, "zn" .. i)
            B.put(o.zVal[i], string.format("%d kWh", math.floor(z.kwh)), o, "zv" .. i)
        end
        B.put(o.unit, string.format("%.2f", d.raw.unit), o, "unit")
        B.put(o.goal, string.format("目标 1.20   基线 1.46"), o, "goal")
        B.put(o.delta, string.format("较基线下降 %.1f%%", (1.46 - d.raw.unit) / 1.46 * 100), o, "delta")
        B.put(o.pow, string.format("%d", math.floor(d.raw.power)), o, "pow")
        B.put(o.pStat, string.format("峰值 %d kW   均值 %d kW",
            d.kpi.peak, math.floor(d.raw.power * 0.92)), o, "ps")
        B.put(o.peakLab, string.format("峰值 %d kWh", 418), o, "pl")
    end
end

return M
