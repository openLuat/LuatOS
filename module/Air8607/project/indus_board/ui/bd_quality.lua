--[[
@module  bd_quality
@summary INDUS BOARD - 视图3 质量与能耗（良率环 / 缺陷 Pareto / 热力 / 能耗 / 储罐）
@version 1.0
@date    2026.10.23
@author  江访

=== 不等分栏 rect 表（舞台内容区相对坐标 0..994 x 0..446）===
  左上 良率环形仪表 x   0 .. 330  y   0 .. 216   大点串环 + 外圈 24 刻度
  左下 缺陷 Pareto  x   0 .. 330  y 226 .. 446   8 柱 + 累计折线 + 80% 虚线
  中上 热力分布     x 340 .. 660  y   0 .. 216   10x4 色块 + 色标条
  中下 能耗曲线     x 340 .. 660  y 226 .. 446   双轴：柱状用电 + 折线单位能耗
  右   竖向储罐     x 670 .. 994  y   0 .. 446   3 罐 + 底部水平刻度尺

=== 组件契约 ===
build(parent, rects, data) -> o     创建 label 等 LVGL 对象，返回句柄
update(o, P, t, dt)                 把动态图元写进图元池 P

=== 绘图要点（都是踩过的坑）===
1、o.shape 必须在 build() 第一句创建：LVGL 后建的子对象画在上层，
   画布建晚了会盖住下面所有的 label。
2、分块底与描边用 airui.container 画（静态、不进图元预算）。
3、储罐液体的三层渐变用三根半透明 box 叠出来（shape 没有渐变填充），
   波浪顶面用两条不同相位的折线叠，比单条正弦有"晃动"的感觉。
4、热力图单元格不画描边：描边会让 40 个格子变成 160 个图元，
   改成格与格之间留 2px 空隙，靠底色分隔。
5、图元整型字段（width/opacity/radius/r/w/h）必须是整数，
   非整数会在 C 层被 lua_tointeger 静默变 0。自己算的点半径一律 math.floor。
6、文字 200ms 才刷新，且值没变就不 set_text，见 put()。
]]

local fx = require "fx"
local T = require "theme"

local M = {
    id = "quality",
    name = "质量能耗",
}

-- ==================== 不等分栏布局 ====================
M.rects = {
    yield  = { x = 0,   y = 0,   w = 330, h = 216 },
    pareto = { x = 0,   y = 226, w = 330, h = 220 },
    heat   = { x = 340, y = 0,   w = 320, h = 216 },
    energy = { x = 340, y = 226, w = 320, h = 220 },
    tank   = { x = 670, y = 0,   w = 324, h = 446 },
}

-- 良率环外圈刻度数
local YIELD_TICKS = 24
-- 良率环点串数
local YIELD_DOTS = 20
-- 缺陷类别数
local PARETO_N = 8
-- 热力图 10 列 x 4 行
local HEAT_C, HEAT_R = 10, 4
-- 能耗图柱数
local ENERGY_COLS = 12
-- 储罐波浪采样点（两点一段，6 点 = 5 段）
local WAVE_PTS = 6
-- 水平刻度尺刻度数
local RULER_TICKS = 11

-- ==================== 文字节流 ====================
--[[只在 hot 帧（200ms 一次）且内容变化时才 set_text
@param table lb label 对象
@param string txt 目标文本
@param table o 视图句柄（借用 o.hot / o._tx）
@param string key 缓存键]]
local function put(lb, txt, o, key)
    local c = o._tx
    if not c then
        c = {}
        o._tx = c
    end
    if not o.hot or c[key] == txt then return end
    c[key] = txt
    lb:set_text(txt)
end

-- ==================== 1 良率环形仪表 ====================
--[[
大点串环 + 中心大号读数 + 外圈 24 刻度。
环用点串画，点半径/透明度沿弧长递增做辉光，末端补一颗高亮头点。
良率映射到 90..100 的量程，环才有"没画满"的余量可看。
]]
local function draw_yield(o, P, t, dt)
    local R = M.rects.yield
    local D = o.data
    local cx, cy = R.x + R.w * 0.5, R.y + R.h * 0.54
    local YR = math.min(R.w, R.h) * 0.34

    -- 外圈 24 刻度（长刻度每 4 格一次）
    for k = 0, YIELD_TICKS - 1 do
        local a = k * fx.TAU / YIELD_TICKS
        local long = (k % 4 == 0)
        local r0 = YR * (long and 1.16 or 1.20)
        local r1 = YR * 1.30
        P:line(cx + math.cos(a) * r0, cy + math.sin(a) * r0,
            cx + math.cos(a) * r1, cy + math.sin(a) * r1,
            long and 0x35E0FF or 0x1E5C7A, long and 2 or 1, long and 180 or 100, true)
    end

    -- 导轨
    P:ring(cx, cy, math.floor(YR), 0x16243C, 12, 255)

    -- 进度点串
    local frac = fx.clamp(((D.kpi.yield or 99) - 90) / 10, 0.04, 1)
    local span = frac * fx.TAU * 0.86
    local a0 = -fx.TAU * 0.5 + t * 0.35
    local ND = YIELD_DOTS
    for k = 0, ND - 1 do
        local f = k / (ND - 1)
        local a = a0 + f * span
        local dr = 3 + 5 * f * f
        local yc = fx.mix(T.c.green, 0xFFFFFF, f * 0.25)
        P:dot(cx + math.cos(a) * YR, cy + math.sin(a) * YR,
            math.floor(dr), yc, math.floor(55 + 200 * f))
    end
    -- 头部高亮
    local ah = a0 + span
    local hx, hy = cx + math.cos(ah) * YR, cy + math.sin(ah) * YR
    P:ring(hx, hy, 9, 0xFFFFFF, 2, 150)
    P:dot(hx, hy, 5, 0xFFFFFF, 255)

    put(o.yv, string.format("%.2f", D.kpi.yield), o, "yv")
end

-- ==================== 2 缺陷 Pareto 柱状 ====================
--[[
8 根柱 + 累计折线 + 80% 参考虚线。
柱体两段渐变（暗底 + 亮顶），累计线走右轴 0..1。
]]
local function draw_pareto(o, P, t, dt)
    local R = M.rects.pareto
    local D = o.data
    local ix, iy = R.x + 12, R.y + 32
    local iw, ih = R.w - 24, R.h - 58

    for k = 0, 2 do
        local y = iy + ih * k / 2
        P:line(ix, y, ix + iw, y, 0x1B2B44, 1, 130, false)
    end

    local sum = 0
    for i = 1, PARETO_N do
        sum = sum + (D.pareto[i] or 0)
    end

    local xs, ys = P._pzx, P._pzy
    if not xs then
        xs, ys = {}, {}
        P._pzx, P._pzy = xs, ys
    end

    local slot = iw / PARETO_N
    local bw = slot - 8
    local run = 0
    for i = 1, PARETO_N do
        local v = fx.clamp(D.pareto[i] or 0, 0, 1)
        run = run + (D.pareto[i] or 0)
        local bh = ih * v
        local x = ix + (i - 1) * slot + 4
        P:box(x, iy + ih - bh, bw, bh, 0x0E6FA0, 210, 3)
        if bh > 10 then
            P:box(x, iy + ih - bh, bw, math.min(bh, 8), 0x2FC8FF, 200, 3)
        end
        -- 累计折线（右轴 0..1）
        local cum = (sum > 0) and (run / sum) or 0
        xs[i] = x + bw * 0.5
        ys[i] = iy + ih * (1 - cum)
    end
    P:poly(xs, ys, PARETO_N, T.c.amber, 2, 235, true)

    -- 80% 参考虚线
    local y80 = iy + ih * 0.2
    P:dash(ix, y80, ix + iw, y80, T.c.lime, 1, 200, 6, 5)

    put(o.pv, string.format("不良 %d 件", math.floor(D.kpi.reject or 0)), o, "pv")
end

-- ==================== 3 热力分布 ====================
--[[
10 列 x 4 行色块矩阵，颜色沿 0..1 从深蓝到亮黄。
单元格不画描边（描边会让 40 个格子变成 160 个图元），
改成格与格之间留 2px 空隙，靠底色分隔。
]]
local function heat_color(v)
    if v < 0.5 then
        return fx.mix(0x0E2A4E, 0x1FA8E0, v * 2)
    end
    return fx.mix(0x1FA8E0, 0xFFD24A, (v - 0.5) * 2)
end

local function draw_heat(o, P, t, dt)
    local R = M.rects.heat
    local D = o.data
    local ix, iy = R.x + 12, R.y + 30
    local iw, ih = R.w - 24, R.h - 62
    local cell_w = iw / HEAT_C
    local cell_h = ih / HEAT_R

    for c = 1, HEAT_C do
        local col = D.heat[c]
        for rr = 1, HEAT_R do
            local v = fx.clamp((col and col[rr]) or 0, 0, 1)
            P:box(ix + (c - 1) * cell_w + 1, iy + (rr - 1) * cell_h + 1,
                cell_w - 2, cell_h - 2, heat_color(v), 235, 3)
        end
    end

    -- 色标条
    local bar_y = iy + ih + 12
    for k = 0, 11 do
        local f = k / 11
        P:box(ix + iw * f, bar_y, iw / 12 - 1, 8, heat_color(f), 255, 2)
    end

    put(o.hv, string.format("峰值 %d  均值 %d",
        math.floor(D.raw.energy), math.floor(D.raw.energy * 0.72)), o, "hv")
end

-- ==================== 4 能耗曲线（双轴）====================
--[[
左轴柱状用电、右轴折线单位能耗。
柱体两段渐变，折线走降采样 12 点，最新点补呼吸光晕。
]]
local function draw_energy(o, P, t, dt)
    local R = M.rects.energy
    local D = o.data
    local ix, iy = R.x + 12, R.y + 32
    local iw, ih = R.w - 24, R.h - 58

    for k = 0, 2 do
        local y = iy + ih * k / 2
        P:line(ix, y, ix + iw, y, 0x1B2B44, 1, 130, false)
    end

    -- 柱状：用电
    local ev, en = D.get("energy")
    local slot = iw / ENERGY_COLS
    local bw = slot - 6
    for k = 0, ENERGY_COLS - 1 do
        local si = math.floor(k * (en - 1) / (ENERGY_COLS - 1)) + 1
        local v = fx.clamp(ev[si] or 0, 0, 1)
        local bh = ih * v
        local x = ix + k * slot + 3
        P:box(x, iy + ih - bh, bw, bh, 0x0E6FA0, 200, 2)
        if bh > 12 then
            P:box(x, iy + ih - bh, bw, bh * 0.32, 0x2FC8FF, 170, 2)
        end
    end

    -- 折线：单位能耗
    local uv, un = D.get("unit")
    local xs, ys = P._ezx, P._ezy
    if not xs then
        xs, ys = {}, {}
        P._ezx, P._ezy = xs, ys
    end
    local NP = 12
    for k = 1, NP do
        local src = math.floor((k - 1) * (un - 1) / (NP - 1)) + 1
        xs[k] = ix + iw * (k - 1) / (NP - 1)
        ys[k] = iy + ih * (1 - fx.clamp(uv[src] or 0, 0, 1))
    end
    P:poly(xs, ys, NP, T.c.amber, 2, 235, true)
    local br = 5 + 3 * (0.5 + 0.5 * math.sin(t * 3))
    P:dot(xs[NP], ys[NP], math.floor(br), T.c.amber, 70)
    P:dot(xs[NP], ys[NP], 3, 0xFFFFFF, 240)

    put(o.ev, string.format("%.0f kWh", D.raw.energy), o, "ev")
    put(o.eu, string.format("%.2f kWh/pcs", D.raw.unit), o, "eu")
end

-- ==================== 5 竖向液位 / 储罐 ====================
--[[
3 个立式罐：外框 + 液体三层渐变 + 双相位波浪顶面 + 右侧读数。
液体没有渐变填充，用三根半透明 box 自下而上叠出厚度。
波浪用两条不同相位的折线叠出来，比单条正弦有"晃动"的感觉。
底部一条水平刻度尺：三色区间带 + 磁吸滑标。
]]
local TANK_COL = { T.c.cyan, T.c.lime, T.c.violet }

local function draw_tank(o, P, t, dt)
    local R = M.rects.tank
    local D = o.data

    -- ===== 3 个立式罐 =====
    local slotw = (R.w - 20) / 3
    local ty, th = R.y + 32, 306
    local xs, ys = P._tzx, P._tzy
    if not xs then
        xs, ys = {}, {}
        P._tzx, P._tzy = xs, ys
    end

    for i = 1, 3 do
        local tk = D.tank[i]
        if not tk then break end
        local sx = R.x + 10 + (i - 1) * slotw
        local tw = 56
        local col = TANK_COL[i] or T.c.cyan

        -- 罐体外框
        P:frame(sx, ty, tw, th, T.c.line2, 2, 230, 10)
        P:box(sx + 3, ty + 3, tw - 6, th - 6, 0x0B1524, 255, 8)

        -- 横向刻度线
        for k = 1, 3 do
            local y = ty + th * k / 4
            P:line(sx + 6, y, sx + tw - 6, y, 0x1B2B44, 1, 160, false)
        end

        local lvl = fx.clamp(tk.v, 0.06, 0.98)
        local top = ty + th - 6 - (th - 12) * lvl
        -- 液体：三层渐变
        P:box(sx + 3, top, tw - 6, ty + th - 3 - top, 0x0E4A6E, 255, 4)
        P:box(sx + 3, top + 8, tw - 6, math.max(0, ty + th - 11 - top),
            fx.mix(0x0E4A6E, col, 0.35), 200, 4)
        P:box(sx + 3, top + 18, tw - 6, math.max(0, ty + th - 21 - top),
            fx.mix(0x0E4A6E, col, 0.70), 130, 4)

        -- 波浪顶面（双相位折线）
        local WN = WAVE_PTS
        for k = 1, WN do
            local f = (k - 1) / (WN - 1)
            xs[k] = sx + 3 + (tw - 6) * f
            ys[k] = top + math.sin(t * 2.1 + f * 6.0 + i) * 3
                + math.sin(t * 1.3 + f * 3.2 + i * 0.7) * 2
        end
        P:poly(xs, ys, WN, 0x7FE6FF, 3, 235, true)
        for k = 1, WN do
            ys[k] = ys[k] + 4
        end
        P:poly(xs, ys, WN, fx.mix(0x2BC0FF, col, 0.4), 2, 110, true)

        -- 液面光晕
        P:dot(sx + tw / 2, top + 2, 12, 0x9FEBFF, 40)

        put(o.tk[i], string.format("%d%%", math.floor(lvl * 100 + 0.5)), o, "tk" .. i)
        put(o.tkn[i], tk.name or "", o, "tkn" .. i)
    end

    -- ===== 底部水平刻度尺 =====
    local y0 = R.y + 396
    local bx, bw = R.x + 14, R.w - 28

    -- 三色区间带
    local segs = {
        { a = 0.00, b = 0.55, col = T.c.green },
        { a = 0.55, b = 0.80, col = T.c.amber },
        { a = 0.80, b = 1.00, col = T.c.red },
    }
    for _, s in ipairs(segs) do
        P:box(bx + bw * s.a, y0 - 7, bw * (s.b - s.a) - 1, 14, s.col, 90, 4)
    end
    P:box(bx, y0 - 3, bw, 6, 0x16243C, 255, 3)

    -- 刻度
    for k = 0, RULER_TICKS - 1 do
        local f = k / (RULER_TICKS - 1)
        local x = bx + bw * f
        local long = (k % 5 == 0)
        P:line(x, y0 - 16, x, y0 - 16 + (long and 10 or 5),
            long and T.c.txt or T.c.dim2, long and 2 or 1, long and 200 or 120, true)
    end

    -- 磁吸滑标
    local v = fx.clamp(D.ruler, 0, 1)
    local sx = bx + bw * v
    P:dot(sx, y0, 14, T.c.cyan, 45)
    P:dot(sx, y0, 8, T.c.cyan, 120)
    P:box(sx - 5, y0 - 20, 10, 40, T.c.cyan, 255, 4)
    P:box(sx - 2, y0 - 16, 4, 32, 0xFFFFFF, 210, 2)

    put(o.rv, string.format("%.2f", v * 2.4), o, "rv")
end

local DRAW = { draw_yield, draw_pareto, draw_heat, draw_energy, draw_tank }

-- ==================== 构建 ====================
--[[创建分块底与文字对象
@param table parent 舞台容器
@param table rects 不等分栏矩形表
@param table data  数据源
]]
function M.build(parent, rects, data)
    local o = { data = data, textT = 999, hot = true }

    --[[图元画布必须先创建：LVGL 后建的子对象画在上层，
    画布建晚了会盖住下面所有的 label。]]
    o.shape = airui.shape({
        parent = parent, x = 0, y = 0,
        w = T.inner.w, h = T.inner.h, items = {},
    })

    -- 五个分块的底 + 顶部高光带 + 标题
    local TITLE = {
        { key = "yield",  name = "良率仪表",   en = "YIELD" },
        { key = "pareto", name = "缺陷 Pareto", en = "PARETO" },
        { key = "heat",   name = "热力分布",   en = "HEATMAP" },
        { key = "energy", name = "能耗曲线",   en = "ENERGY" },
        { key = "tank",   name = "储罐液位",   en = "TANK" },
    }
    for _, ti in ipairs(TITLE) do
        local R = rects[ti.key]
        airui.container({
            parent = parent, x = R.x, y = R.y, w = R.w, h = R.h,
            color = T.c.panel, color_opacity = 255, radius = 10,
            border_color = T.c.line, border_width = 1,
        })
        airui.container({
            parent = parent, x = R.x + 1, y = R.y + 1, w = R.w - 2, h = 2,
            color = T.c.panel_hl, color_opacity = 255, radius = 1,
            border_width = 0,
        })
        airui.label({
            parent = parent, x = R.x + 12, y = R.y + 6, w = R.w - 120, h = 18,
            text = ti.name, font_size = T.f.mini,
            color = T.c.dim, align = airui.TEXT_ALIGN_LEFT,
        })
        airui.label({
            parent = parent, x = R.x + R.w - 112, y = R.y + 6, w = 100, h = 18,
            text = ti.en, font_size = T.f.mini,
            color = T.c.dim2, align = airui.TEXT_ALIGN_RIGHT,
        })
    end

    -- 良率中心读数
    local R = rects.yield
    o.yv = airui.label({
        parent = parent, x = R.x + R.w * 0.5 - 90, y = R.y + R.h * 0.54 - 24,
        w = 180, h = 48, text = "--", font_size = T.f.big,
        color = T.c.lime, align = airui.TEXT_ALIGN_CENTER,
    })
    airui.label({
        parent = parent, x = R.x + R.w * 0.5 - 90, y = R.y + R.h * 0.54 + 22,
        w = 180, h = 16, text = "%", font_size = T.f.mini,
        color = T.c.dim2, align = airui.TEXT_ALIGN_CENTER,
    })

    -- Pareto 读数
    R = rects.pareto
    o.pv = airui.label({
        parent = parent, x = R.x + R.w - 160, y = R.y + 6, w = 148, h = 18,
        text = "--", font_size = T.f.mini,
        color = T.c.amber, align = airui.TEXT_ALIGN_RIGHT,
    })

    -- 热力读数
    R = rects.heat
    o.hv = airui.label({
        parent = parent, x = R.x + 12, y = R.y + R.h - 22, w = R.w - 24, h = 18,
        text = "--", font_size = T.f.mini,
        color = T.c.dim, align = airui.TEXT_ALIGN_LEFT,
    })

    -- 能耗读数（双轴两个值）
    R = rects.energy
    o.ev = airui.label({
        parent = parent, x = R.x + 12, y = R.y + R.h - 22, w = 150, h = 18,
        text = "--", font_size = T.f.mini,
        color = T.c.cyan, align = airui.TEXT_ALIGN_LEFT,
    })
    o.eu = airui.label({
        parent = parent, x = R.x + R.w - 170, y = R.y + R.h - 22,
        w = 158, h = 18, text = "--", font_size = T.f.mini,
        color = T.c.amber, align = airui.TEXT_ALIGN_RIGHT,
    })

    -- 储罐：右侧读数 + 罐名 + 刻度尺读数
    R = rects.tank
    local slotw = (R.w - 20) / 3
    o.tk, o.tkn = {}, {}
    for i = 1, 3 do
        local sx = R.x + 10 + (i - 1) * slotw
        o.tk[i] = airui.label({
            parent = parent, x = sx + 60, y = R.y + 170,
            w = 40, h = 20, text = "--", font_size = T.f.mini,
            color = T.c.txt, align = airui.TEXT_ALIGN_LEFT,
        })
        o.tkn[i] = airui.label({
            parent = parent, x = sx - 6, y = R.y + 342,
            w = 68, h = 16, text = "", font_size = T.f.mini,
            color = T.c.dim, align = airui.TEXT_ALIGN_CENTER,
        })
    end
    o.rv = airui.label({
        parent = parent, x = R.x + 14, y = R.y + 412, w = R.w - 28, h = 18,
        text = "--", font_size = T.f.mini,
        color = T.c.cyan, align = airui.TEXT_ALIGN_CENTER,
    })

    return o
end

-- ==================== 每帧绘制 ====================
function M.update(o, P, t, dt)
    -- 文字节拍：200ms 才允许一次 set_text（见 put）
    o.textT = o.textT + dt
    o.hot = false
    if o.textT >= T.perf.text_ms / 1000 then
        o.textT = 0
        o.hot = true
    end

    for i = 1, #DRAW do
        DRAW[i](o, P, t, dt)
    end
end

return M
