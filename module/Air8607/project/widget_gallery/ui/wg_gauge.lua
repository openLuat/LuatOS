--[[
@module  wg_gauge
@summary WIDGET GALLERY - 仪表组组件（环形进度 / 指针表 / 液位 / 分段条 / 扇形 / 刻度尺）
@version 1.0
@date    2026.10.23
@author  江访

=== 卡片位序（3 列 x 2 行）===
  1 环形进度   2 指针表     3 液位柱
  4 分段电量条 5 扇形弧表   6 水平刻度尺

=== 组件契约 ===
build(parent, rects, data) -> o     创建 label 等 LVGL 对象，返回句柄
update(o, P, t, dt, data)           把动态图元写进图元池 P
rects[i] = {x,y,w,h} 是第 i 张卡片的外框，内容区由 content() 统一推导。

=== 绘图要点（都是踩过的坑）===
1、圆弧一律用「一串实心圆点」逼近粗弧：折线画粗弧在转角处会露接缝，
   圆点半径/不透明度沿弧长渐变还能顺带做出辉光。
2、P:ring 的描边是往圆心方向画的，暗色导轨半径要外扩线宽的一半，
   否则亮弧会有一半压在导轨外面。
3、图元坐标全部 math.floor（fx.lua 的写入方法已统一取整）。
4、文字只在 200ms 节拍上刷新，且值没变就不 set_text。
]]

local fx = require "fx"
local T = require "theme"

local M = {
    id = "gauge",
    name = "仪表",
}

-- 卡片标题（顺序即卡位）
M.cards = {
    { name = "环形进度",   en = "RING" },
    { name = "指针表盘",   en = "DIAL" },
    { name = "液位柱",     en = "LEVEL" },
    { name = "分段电量条", en = "SEG BAR" },
    { name = "扇形弧表",   en = "FAN ARC" },
    { name = "水平刻度尺", en = "SCALE" },
}

-- 卡片内容区：外框内缩 12，标题条占 34，底部留 10
local function content(x, y, w, h)
    return x + 12, y + 34, w - 24, h - 44
end

-- ==================== 文字节流 ====================
--[[
只在 200ms 节拍上 set_text，且内容没变就不刷
set_text 会让 LVGL 重排文本并额外产生一块脏区，29 处读数每帧刷就是每秒上千次。
节拍从动画时间 t 推（t*5 即每 0.2s 一格），不依赖外部时钟。
o._tx 以 label 为键缓存上一次的文本，值没变直接跳过。
@param table lb  文字对象
@param string txt 新文本
@param table o   视图句柄（带 _hot / _tx）
]]
local function put(lb, txt, o)
    if not o._hot then return end
    if o._tx[lb] == txt then return end
    o._tx[lb] = txt
    lb:set_text(txt)
end

-- ==================== 1 环形进度 ====================
--[[
三环同心 + 外圈刻度盘。环用点串画，点半径沿弧长递增、末端补一颗高亮头点，
形成"拖尾"的辉光感。中心显示最外环读数。
]]
local RINGS = {
    { k = 1.00, dots = 20, hue = 192, sp = 0.55, name = "A" },
    { k = 0.76, dots = 17, hue = 286, sp = -0.42, name = "B" },
    { k = 0.54, dots = 14, hue = 336, sp = 0.78, name = "C" },
}
local TICKS = 24
local DOT_MAX = 8

local function draw_ring(o, P, r, t, dt)
    local ix, iy, iw, ih = content(r.x, r.y, r.w, r.h)
    local cx, cy = ix + iw * 0.5, iy + ih * 0.5
    local R = math.min(iw, ih) * 0.42

    -- 外圈刻度盘（长刻度每 4 格一次）
    for k = 0, TICKS - 1 do
        local a = k * fx.TAU / TICKS
        local long = (k % 4 == 0)
        local r0 = R * (long and 1.10 or 1.14)
        local r1 = R * 1.20
        P:line(cx + math.cos(a) * r0, cy + math.sin(a) * r0,
            cx + math.cos(a) * r1, cy + math.sin(a) * r1,
            long and 0x35E0FF or 0x1E5C7A, long and 2 or 1, long and 180 or 100, true)
    end

    for i, rg in ipairs(RINGS) do
        local rr = R * rg.k
        local col = fx.hsl(rg.hue + t * 6, 0.88, 0.58)
        local frac = (i == 1) and (o.data.gauge.a)
            or ((i == 2) and o.data.gauge.b or o.data.gauge.c)
        local span = fx.clamp(frac, 0.04, 1) * fx.TAU * 0.86
        local a0 = -fx.TAU * 0.5 + t * rg.sp

        -- 暗色导轨：外扩 DOT_MAX 让它刚好罩住环点能占到的范围
        P:ring(cx, cy, math.floor(rr) + DOT_MAX, 0x16243C, DOT_MAX * 2, 255)

        local D = rg.dots
        for k = 0, D - 1 do
            local f = k / (D - 1)
            local a = a0 + f * span
            local dr = 2 + (DOT_MAX - 2) * f * f
            local opa = math.floor(55 + 200 * f)
            P:dot(cx + math.cos(a) * rr, cy + math.sin(a) * rr, dr, col, opa)
        end
        -- 头部高亮
        local ah = a0 + span
        local hx, hy = cx + math.cos(ah) * rr, cy + math.sin(ah) * rr
        P:ring(hx, hy, DOT_MAX + 3, 0xFFFFFF, 2, 150)
        P:dot(hx, hy, DOT_MAX - 1, 0xFFFFFF, 255)
    end

    -- 中心读数（文字由 build 时创建的 label 承担）
    put(o.c1, string.format("%d%%", math.floor(o.data.gauge.a * 100)), o)
end

-- ==================== 2 指针表盘 ====================
--[[
240 度扫角（150°..390°）的机械表盘：
刻度盘 + 大刻度数字 + 红区 + 指针（长针 + 尾锤 + 轴心光晕）。
指针走缓动趋近，读数"追"目标值，机械感就是从这里来的。
]]
local function draw_dial(o, P, r, t, dt)
    local ix, iy, iw, ih = content(r.x, r.y, r.w, r.h)
    local cx, cy = ix + iw * 0.5, iy + ih * 0.52
    local R = math.min(iw, ih) * 0.44

    local A0, A1 = 150, 390              -- 屏幕角度：0=右，顺时针为正（y 轴向下）
    local a0, a1 = A0 * fx.DEG, A1 * fx.DEG

    -- 表盘底：两圈暗环压出厚度
    P:dot(cx, cy, math.floor(R * 1.02), 0x0C1424, 255)
    P:ring(cx, cy, math.floor(R * 1.02), T.c.line2, 2, 220)
    P:ring(cx, cy, math.floor(R * 0.90), 0x16243C, 1, 180)

    -- 进度弧（点串，弧长随读数）
    local v = o.data.gauge.d
    local vang = a0 + (a1 - a0) * fx.clamp(v, 0, 1)
    local NPT = 22
    for k = 0, NPT - 1 do
        local f = k / (NPT - 1)
        local a = a0 + f * (vang - a0)
        local col = fx.hsl(192 + f * 26, 0.9, 0.55)
        P:dot(cx + math.cos(a) * R * 0.80, cy + math.sin(a) * R * 0.80,
            2 + 6 * f, col, math.floor(60 + 195 * f))
    end

    -- 红区（后 15%）
    local ar0 = a0 + (a1 - a0) * 0.85
    for k = 0, 6 do
        local a = ar0 + (a1 - ar0) * k / 6
        P:line(cx + math.cos(a) * R * 0.92, cy + math.sin(a) * R * 0.92,
            cx + math.cos(a) * R * 1.00, cy + math.sin(a) * R * 1.00,
            T.c.red, 3, 220, true)
    end

    -- 刻度：17 格，每 4 格长刻度
    for k = 0, 16 do
        local f = k / 16
        local a = a0 + (a1 - a0) * f
        local long = (k % 4 == 0)
        local r0 = R * (long and 0.60 or 0.66)
        local r1 = R * 0.72
        P:line(cx + math.cos(a) * r0, cy + math.sin(a) * r0,
            cx + math.cos(a) * r1, cy + math.sin(a) * r1,
            long and T.c.txt or T.c.dim2, long and 2 or 1, long and 210 or 120, true)
    end

    -- 指针：长针 + 尾锤 + 轴心
    local na = a0 + (a1 - a0) * fx.clamp(v, 0, 1)
    local cs, sn = math.cos(na), math.sin(na)
    P:line(cx - cs * R * 0.18, cy - sn * R * 0.18,
        cx + cs * R * 0.74, cy + sn * R * 0.74, T.c.amber, 5, 255, true)
    P:line(cx - cs * R * 0.26, cy - sn * R * 0.26,
        cx - cs * R * 0.10, cy - sn * R * 0.10, T.c.amber, 3, 200, true)
    P:dot(cx, cy, 10, 0x1A2436, 255)
    P:ring(cx, cy, 10, T.c.amber, 2, 230)
    P:dot(cx, cy, 3, T.c.txt, 255)

    -- 指针尖端光晕
    P:dot(cx + cs * R * 0.74, cy + sn * R * 0.74, 9, T.c.amber, 60)

    put(o.c2, string.format("%d", math.floor(v * 160)), o)
    put(o.c2b, "kPa", o)
end

-- ==================== 3 液位柱 ====================
--[[
立式储罐：外框 + 网格刻度 + 液体（分层渐变 + 波浪顶面）+ 顶部高光。
波浪用两条不同相位的折线叠出来，比单条正弦有"晃动"的感觉。
]]
local function draw_level(o, P, r, t, dt)
    local ix, iy, iw, ih = content(r.x, r.y, r.w, r.h)

    -- 左：储罐  右：三根细液位管
    local tw = math.floor(iw * 0.42)
    local tx, ty = ix + 6, iy + 4
    local th = ih - 8

    -- 罐体外框
    P:frame(tx, ty, tw, th, T.c.line2, 2, 230, 10)
    P:box(tx + 3, ty + 3, tw - 6, th - 6, 0x0B1524, 255, 8)

    -- 横向刻度线
    for k = 1, 5 do
        local y = ty + th * k / 6
        P:line(tx + 6, y, tx + tw - 6, y, 0x1B2B44, 1, 160, false)
    end

    local lvl = o.data.gauge.b
    local top = ty + th - 6 - (th - 12) * fx.clamp(lvl, 0.06, 0.98)
    -- 液体：三层渐变
    P:box(tx + 3, top, tw - 6, ty + th - 3 - top, 0x0E4A6E, 255, 4)
    P:box(tx + 3, top + 6, tw - 6, math.max(0, ty + th - 9 - top), 0x1279B8, 200, 4)
    P:box(tx + 3, top + 14, tw - 6, math.max(0, ty + th - 17 - top), 0x1EA8E8, 120, 4)

    -- 波浪顶面（两相位折线）
    local xs, ys = P._lx, P._ly
    if not xs then
        xs, ys = {}, {}
        P._lx, P._ly = xs, ys
    end
    local WN = 8
    for i = 1, WN do
        local f = (i - 1) / (WN - 1)
        xs[i] = tx + 3 + (tw - 6) * f
        ys[i] = top + math.sin(t * 2.1 + f * 6.0) * 3 + math.sin(t * 1.3 + f * 3.2) * 2
    end
    P:poly(xs, ys, WN, 0x7FE6FF, 3, 235, true)
    for i = 1, WN do
        ys[i] = ys[i] + 4
    end
    P:poly(xs, ys, WN, 0x2BC0FF, 2, 110, true)

    -- 罐顶高光 + 液面光晕
    P:dot(tx + tw / 2, top + 2, 14, 0x9FEBFF, 40)

    -- 右侧三根细管
    local gx = tx + tw + 26
    local gw = math.floor((ix + iw - 6 - gx) / 3) - 10
    local tubes = {
        { v = o.data.gauge.a, col = T.c.green, name = "L1" },
        { v = o.data.gauge.c, col = T.c.violet, name = "L2" },
        { v = o.data.gauge.d, col = T.c.amber, name = "L3" },
    }
    for i, tb in ipairs(tubes) do
        local bx = gx + (i - 1) * (gw + 14)
        P:frame(bx, ty + 4, gw, th - 8, T.c.line, 1, 200, 8)
        local bh = (th - 16) * fx.clamp(tb.v, 0.05, 1)
        P:box(bx + 3, ty + th - 7 - bh, gw - 6, bh, tb.col, 220, 6)
        -- 管内高光
        P:line(bx + gw * 0.32, ty + th - 10 - bh, bx + gw * 0.32, ty + th - 10,
            0xFFFFFF, 1, 60, true)
        P:dot(bx + gw / 2, ty + th - 8 - bh, 6, tb.col, 70)
    end

    put(o.c3, string.format("%d%%", math.floor(lvl * 100)), o)
end

-- ==================== 4 分段电量条 ====================
--[[
四行水平分段条：每行一条暗轨道 + 若干"刻度块" + 一个发光前端。
末端光晕用一大一小两颗低透明度圆叠出来（同 fx.meter 的做法）。
]]
local function draw_segbar(o, P, r, t, dt)
    local ix, iy, iw, ih = content(r.x, r.y, r.w, r.h)
    local ROWS = 4
    local rowh = math.floor((ih - 8) / ROWS)
    local cols = { T.c.cyan, T.c.green, T.c.amber, T.c.magenta }

    for i = 1, ROWS do
        local y = iy + 2 + (i - 1) * rowh
        local bh = rowh - 16
        local frac = (i == 1) and o.data.gauge.a
            or ((i == 2) and o.data.gauge.b or ((i == 3) and o.data.gauge.c or o.data.gauge.d))
        local col = cols[i]

        -- 轨道
        P:box(ix, y, iw, bh, 0x14203A, 230, math.floor(bh / 2))

        -- 分段刻度块（12 格，亮格按 frac 点亮）
        local SEG = 12
        local segw = (iw - 4) / SEG
        local lit = math.floor(frac * SEG + 0.5)
        for k = 0, SEG - 1 do
            local on = (k < lit)
            local fade = (k / (SEG - 1))
            local c = on and fx.mix(col, 0xFFFFFF, fade * 0.35) or 0x1D2C48
            P:box(ix + 2 + k * segw + 1, y + 3, segw - 3, bh - 6, c,
                on and 245 or 190, 2)
        end

        -- 前端光晕
        local fw = ix + 2 + lit * segw
        if lit > 0 then
            P:dot(fw, y + bh / 2, math.floor(bh * 0.95), col, 55)
            P:dot(fw, y + bh / 2, math.floor(bh * 0.42), fx.shade(col, 0.55), 190)
        end

        -- 行标
        put(o.seg[i], string.format("B%d  %d%%", i, math.floor(frac * 100)), o)
    end
end

-- ==================== 5 扇形弧表 ====================
--[[
VU 表式的扇形：沿圆弧排布的 14 个扇区块，颜色沿弧长做色相渐变，
当前档位之后的扇区压暗。中心一个大号读数，底部一条峰值保持条。
]]
local function draw_fan(o, P, r, t, dt)
    local ix, iy, iw, ih = content(r.x, r.y, r.w, r.h)
    local cx, cy = ix + iw * 0.5, iy + ih * 0.86
    local R = math.min(iw * 0.5, ih * 0.86)

    local A0, A1 = 180, 360          -- 上半圆（y 轴向下：180=左，360=右）
    local NSEG = 14
    local v = o.data.gauge.c
    local lit = math.floor(fx.clamp(v, 0, 1) * NSEG + 0.5)

    for k = 0, NSEG - 1 do
        local f = k / (NSEG - 1)
        local a = (A0 + (A1 - A0) * f) * fx.DEG
        local a2 = (A0 + (A1 - A0) * (f + 1 / NSEG * 0.72)) * fx.DEG
        local r0, r1 = R * 0.52, R * 0.94
        local on = (k < lit)
        local col = fx.hsl(200 - f * 200, 0.9, on and 0.58 or 0.22)

        -- 扇区用 2 条同心短弧叠出"厚度"
        for band = 0, 1 do
            local br = r0 + (r1 - r0) * (band + 0.5) / 2
            local segs = 2
            local step = (a2 - a) / segs
            local px, py = cx + math.cos(a) * br, cy + math.sin(a) * br
            for s = 1, segs do
                local aa = a + step * s
                local qx, qy = cx + math.cos(aa) * br, cy + math.sin(aa) * br
                P:line(px, py, qx, qy, col, on and 11 or 8, on and 255 or 120, false)
                px, py = qx, qy
            end
        end
    end

    -- 峰值保持
    local pk = o.peak or 0
    if v > pk then
        pk = v
    else
        pk = pk - 0.06 * dt
        if pk < 0 then pk = 0 end
    end
    o.peak = pk
    local pa = (A0 + (A1 - A0) * fx.clamp(pk, 0, 1)) * fx.DEG
    P:line(cx + math.cos(pa) * R * 0.48, cy + math.sin(pa) * R * 0.48,
        cx + math.cos(pa) * R * 0.98, cy + math.sin(pa) * R * 0.98,
        0xFFFFFF, 2, 210, true)

    -- 中心读数与基准线
    P:line(cx - R * 0.98, cy, cx + R * 0.98, cy, T.c.line2, 1, 160, false)
    put(o.c5, string.format("%d", math.floor(v * 100)), o)
end

-- ==================== 6 水平刻度尺 ====================
--[[
线性刻度尺：区间带（绿/黄/红三段）+ 刻度 + 数字 + 滑标。
滑标走 ease_out 趋近，带一个跟随的小光晕，看起来像"磁吸"到刻度上。
]]
local function draw_scale(o, P, r, t, dt)
    local ix, iy, iw, ih = content(r.x, r.y, r.w, r.h)
    local y0 = iy + ih * 0.52
    local bx, bw = ix + 8, iw - 16

    -- 区间带
    local segs = {
        { a = 0.00, b = 0.55, col = T.c.green },
        { a = 0.55, b = 0.80, col = T.c.amber },
        { a = 0.80, b = 1.00, col = T.c.red },
    }
    for _, s in ipairs(segs) do
        P:box(bx + bw * s.a, y0 - 7, bw * (s.b - s.a) - 1, 14, s.col, 90, 4)
    end
    P:box(bx, y0 - 3, bw, 6, 0x16243C, 255, 3)

    -- 刻度：11 格，每 5 格长刻度
    for k = 0, 10 do
        local f = k / 10
        local x = bx + bw * f
        local long = (k % 5 == 0)
        P:line(x, y0 - 14, x, y0 - 14 + (long and 12 or 6),
            long and T.c.txt or T.c.dim2, long and 2 or 1, long and 200 or 120, true)
        P:line(x, y0 + 2, x, y0 + 2 + (long and 12 or 6),
            long and T.c.txt or T.c.dim2, long and 2 or 1, long and 200 or 120, true)
    end

    -- 滑标（磁吸感）
    local v = o.data.gauge.a
    local sx = bx + bw * fx.clamp(v, 0, 1)
    P:dot(sx, y0, 16, T.c.cyan, 45)
    P:dot(sx, y0, 9, T.c.cyan, 120)
    P:box(sx - 5, y0 - 22, 10, 44, T.c.cyan, 255, 4)
    P:box(sx - 2, y0 - 18, 4, 36, 0xFFFFFF, 210, 2)
    -- 上下引线
    P:line(sx, iy + 6, sx, y0 - 22, T.c.cyan, 1, 120, true)
    P:line(sx, y0 + 22, sx, iy + ih - 30, T.c.cyan, 1, 120, true)

    put(o.c6, string.format("%.1f", v * 160), o)
    put(o.c6b, "kPa", o)
end

local DRAW = { draw_ring, draw_dial, draw_level, draw_segbar, draw_fan, draw_scale }

-- ==================== 构建 ====================
--[[创建卡片与文字对象
@param table parent 舞台容器
@param table rects 6 张卡片的外框矩形
@param table data  数据源
]]
function M.build(parent, rects, data)
    local o = { data = data, rects = rects, peak = 0 }
    o._tx = {}          -- 文字节流缓存（见 put）
    o._hot = false

    --[[图元画布必须先创建：LVGL 后建的子对象画在上层，
    画布建晚了会盖住下面所有的 label。]]
    o.shape = airui.shape({
        parent = parent, x = 0, y = 0,
        w = T.inner.w, h = T.inner.h, items = {},
    })

    for i = 1, 6 do
        local r = rects[i]
        local card = M.cards[i]
        -- 卡片底 + 描边 + 顶部高光带
        airui.container({
            parent = parent, x = r.x, y = r.y, w = r.w, h = r.h,
            color = T.c.panel, color_opacity = 255, radius = 10,
            border_color = T.c.line, border_width = 1,
        })
        airui.container({
            parent = parent, x = r.x + 1, y = r.y + 1, w = r.w - 2, h = 2,
            color = T.c.panel_hl, color_opacity = 255, radius = 1,
            border_width = 0,
        })
        -- 标题
        airui.label({
            parent = parent, x = r.x + 12, y = r.y + 8, w = r.w - 90, h = 22,
            text = card.name, font_size = T.f.text,
            color = T.c.txt, align = airui.TEXT_ALIGN_LEFT,
        })
        airui.label({
            parent = parent, x = r.x + r.w - 82, y = r.y + 10, w = 70, h = 18,
            text = card.en, font_size = T.f.mini,
            color = T.c.dim2, align = airui.TEXT_ALIGN_RIGHT,
        })
    end

    -- 需要 set_text 的文字对象（坐标按内容区推导）
    local r1 = rects[1]
    local ix, iy, iw, ih = content(r1.x, r1.y, r1.w, r1.h)
    o.c1 = airui.label({
        parent = parent, x = ix + iw / 2 - 60, y = iy + ih / 2 - 18,
        w = 120, h = 36, text = "--", font_size = T.f.val,
        color = T.c.cyan, align = airui.TEXT_ALIGN_CENTER,
    })

    local r2 = rects[2]
    ix, iy, iw, ih = content(r2.x, r2.y, r2.w, r2.h)
    o.c2 = airui.label({
        parent = parent, x = ix + iw / 2 - 60, y = iy + ih * 0.86 - 16,
        w = 120, h = 32, text = "--", font_size = T.f.body,
        color = T.c.amber, align = airui.TEXT_ALIGN_CENTER,
    })
    o.c2b = airui.label({
        parent = parent, x = ix + iw / 2 - 60, y = iy + ih * 0.86 + 12,
        w = 120, h = 18, text = "kPa", font_size = T.f.mini,
        color = T.c.dim2, align = airui.TEXT_ALIGN_CENTER,
    })

    local r3 = rects[3]
    ix, iy, iw, ih = content(r3.x, r3.y, r3.w, r3.h)
    o.c3 = airui.label({
        parent = parent, x = ix + iw * 0.42 + 26, y = iy + ih * 0.5 - 16,
        w = 120, h = 32, text = "--", font_size = T.f.body,
        color = T.c.cyan, align = airui.TEXT_ALIGN_LEFT,
    })

    -- 分段条四行行标
    local r4 = rects[4]
    ix, iy, iw, ih = content(r4.x, r4.y, r4.w, r4.h)
    local rowh = math.floor((ih - 8) / 4)
    o.seg = {}
    for i = 1, 4 do
        o.seg[i] = airui.label({
            parent = parent, x = ix, y = iy + 2 + (i - 1) * rowh + rowh - 16,
            w = iw, h = 16, text = "--", font_size = T.f.mini,
            color = T.c.dim, align = airui.TEXT_ALIGN_LEFT,
        })
    end

    local r5 = rects[5]
    ix, iy, iw, ih = content(r5.x, r5.y, r5.w, r5.h)
    o.c5 = airui.label({
        parent = parent, x = ix + iw / 2 - 60, y = iy + ih * 0.30,
        w = 120, h = 40, text = "--", font_size = T.f.val,
        color = T.c.lime, align = airui.TEXT_ALIGN_CENTER,
    })

    local r6 = rects[6]
    ix, iy, iw, ih = content(r6.x, r6.y, r6.w, r6.h)
    o.c6 = airui.label({
        parent = parent, x = ix + iw / 2 - 60, y = iy + 6,
        w = 120, h = 32, text = "--", font_size = T.f.body,
        color = T.c.cyan, align = airui.TEXT_ALIGN_CENTER,
    })
    o.c6b = airui.label({
        parent = parent, x = ix + iw / 2 - 60, y = iy + ih - 24,
        w = 120, h = 18, text = "kPa", font_size = T.f.mini,
        color = T.c.dim2, align = airui.TEXT_ALIGN_CENTER,
    })

    return o
end

-- ==================== 每帧绘制 ====================
function M.update(o, P, t, dt)
    -- 200ms 节拍：只在这一帧允许 set_text（见 put）
    local beat = math.floor(t * 5)
    o._hot = (beat ~= o._t5)
    o._t5 = beat

    for i = 1, 6 do
        DRAW[i](o, P, o.rects[i], t, dt)
    end
end

return M
