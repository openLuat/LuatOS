--[[
@module  bd_equipment
@summary INDUS BOARD - 视图2 设备监控（健康矩阵 / 双针表 / 分段负载 / 状态时间轴）
@version 1.0
@date    2026.10.23
@author  江访

=== 不等分栏 rect 表（舞台内容区相对坐标 0..994 x 0..446）===
  左大块 设备健康矩阵 x   0 .. 500  y   0 .. 446
         上半 4x3=12 台设备格（y 0..316）
         下半 4 路降采样温度折线（y 326..446）
  右上 双针仪表       x 510 .. 994  y   0 .. 216   主轴振动 / 轴承温度
  右中 分段负载条     x 510 .. 994  y 226 .. 334   3 行 x 12 格刻度块
  右下 设备状态时间轴 x 510 .. 994  y 344 .. 446   5 个节点横排 + 引导虚线

=== 组件契约 ===
build(parent, rects, data) -> o     创建 label 等 LVGL 对象，返回句柄
update(o, P, t, dt)                 把动态图元写进图元池 P

=== 绘图要点（都是踩过的坑）===
1、o.shape 必须在 build() 第一句创建：LVGL 后建的子对象画在上层，
   画布建晚了会盖住下面所有的 label。
2、设备格底色用 airui.container 画（静态、不进图元预算），
   12 格光晕灯 + 健康弧 + 负载条才是动态图元，整页压在 350 以内。
3、健康度弧用「一串实心圆点」逼近：shape 没有弧形填充，
   P:ring 画导轨（1 个图元）+ 点串画进度，比 P:arc 便宜一半。
4、双针表盘的刻度与红区都是直线段，针走 fx.approach 缓动趋近，
   机械感就是从"针在追读数"来的。
5、图元整型字段（width/opacity/radius/r/w/h）必须是整数，
   非整数会在 C 层被 lua_tointeger 静默变 0。自己算的点半径一律 math.floor。
6、文字 200ms 才刷新，且值没变就不 set_text，见 put()。
]]

local fx = require "fx"
local T = require "theme"

local M = {
    id = "equipment",
    name = "设备监控",
}

-- ==================== 不等分栏布局 ====================
M.rects = {
    mat   = { x = 0,   y = 0,   w = 500, h = 446 },
    gauge = { x = 510, y = 0,   w = 484, h = 216 },
    load  = { x = 510, y = 226, w = 484, h = 108 },
    tl    = { x = 510, y = 344, w = 484, h = 102 },
}

-- 设备矩阵：4 列 x 3 行，格子区占 y 0..316，温度趋势占 y 326..446
local MAT_COLS, MAT_ROWS = 4, 3
local MAT_TOP, MAT_BOT = 28, 316
local TREND_Y, TREND_H = 326, 120

-- 健康度弧点串数（少一点省图元，多了看不出差别）
local ARC_DOTS = 6
-- 双针表刻度数（17 -> 9 格，每 4 格长刻度）
local DIAL_TICKS = 9
-- 分段负载条每行格数
local LOAD_SEG = 12
-- 温度趋势降采样点数
local TREND_PTS = 9

local STATE_COL = { T.c.green, T.c.cyan, T.c.amber, T.c.red }
local STATE_TXT = { "运行", "待机", "告警", "离线" }

-- 双针表配置：名称 / 单位 / 量程上限 / 配色
local DIAL_CFG = {
    { name = "主轴振动", unit = "mm/s", span = 12.0, col = T.c.cyan },
    { name = "轴承温度", unit = "C",    span = 120,  col = T.c.amber },
}

-- 分段负载条行配置
local LOAD_CFG = {
    { name = "主轴负载", col = T.c.cyan },
    { name = "液压负载", col = T.c.green },
    { name = "气源负载", col = T.c.amber },
}

-- 时间轴节点
local TL_COL = { T.c.green, T.c.green, T.c.green, T.c.cyan, T.c.dim2 }

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

-- ==================== 1 设备健康矩阵 ====================
--[[
12 台设备格：设备号 + 状态光晕灯 + 健康度弧 + 负载条。
状态灯呼吸相位按 (行*4+列) 错开，整屏看起来是"波浪式"的活。
健康弧是 240 度点串，导轨用一圈暗环一次性画完。
]]
local function draw_matrix(o, P, t, dt)
    local R = M.rects.mat
    local D = o.data
    local cw = R.w / MAT_COLS
    local chh = (MAT_BOT - MAT_TOP) / MAT_ROWS

    for i = 1, MAT_COLS * MAT_ROWS do
        local d = D.dev[i]
        if not d then break end
        local c = (i - 1) % MAT_COLS
        local rr = math.floor((i - 1) / MAT_COLS)
        local x = R.x + c * cw
        local y = R.y + MAT_TOP + rr * chh
        local col = STATE_COL[d.state] or T.c.dim

        -- 状态光晕灯（呼吸）
        local ph = t * 2.0 + i * 0.7
        local br = 5.5 + 2.5 * (0.5 + 0.5 * math.sin(ph))
        local opa = math.floor(45 + 40 * (0.5 + 0.5 * math.sin(ph)))
        P:dot(x + cw * 0.5, y + 30, math.floor(br * 2.2), col, opa)
        P:dot(x + cw * 0.5, y + 30, math.floor(br), col, 255)

        -- 健康度弧：导轨一圈 + 点串进度
        local cx, cy, AR = x + cw * 0.5, y + 58, 17
        P:ring(cx, cy, AR, 0x16243C, 5, 255)
        local A0 = 150 * fx.DEG
        local span = 240 * fx.DEG * fx.clamp(d.health, 0, 1)
        for k = 0, ARC_DOTS - 1 do
            local f = k / (ARC_DOTS - 1)
            local a = A0 + f * span
            local hcol = fx.mix(col, 0xFFFFFF, f * 0.3)
            P:dot(cx + math.cos(a) * AR, cy + math.sin(a) * AR,
                2 + 3 * f, hcol, math.floor(80 + 175 * f))
        end

        -- 负载条
        local bx, bw = x + 12, cw - 24
        local by, bh = y + 86, 6
        P:box(bx, by, bw, bh, 0x1B2B44, 220, 3)
        local fw = bw * fx.clamp(d.load, 0, 1)
        if fw >= 2 then
            P:box(bx, by, fw, bh, col, 235, 3)
            P:dot(bx + fw, by + 3, 5, fx.shade(col, 0.55), 190)
        end

        put(o.mt[i], d.tag, o, "mt" .. i)
        put(o.mh[i], string.format("%d", math.floor(d.health * 100 + 0.5)), o, "mh" .. i)
        put(o.ms[i], STATE_TXT[d.state] or "--", o, "ms" .. i)
    end
end

-- ==================== 2 设备综合温度趋势 ====================
--[[
4 路降采样折线叠在同一个坐标里，最新点各画一颗呼吸光晕。
4 条线的时间常数不同，视觉上会互相追逐。
]]
local TREND_COL = { T.c.cyan, T.c.green, T.c.amber, T.c.violet }
local TREND_KEY = { "t1", "t2", "t3", "t4" }

local function draw_trend(o, P, t, dt)
    local R = M.rects.mat
    local D = o.data
    local ix, iy = R.x + 12, R.y + TREND_Y + 22
    local iw, ih = R.w - 24, TREND_H - 42

    for k = 0, 2 do
        local y = iy + ih * k / 2
        P:line(ix, y, ix + iw, y, 0x1B2B44, 1, 130, false)
    end

    local xs, ys = P._eqx, P._eqy
    if not xs then
        xs, ys = {}, {}
        P._eqx, P._eqy = xs, ys
    end

    for si = 1, 4 do
        local vals, n = D.get(TREND_KEY[si])
        local NP = TREND_PTS
        for k = 1, NP do
            local src = math.floor((k - 1) * (n - 1) / (NP - 1)) + 1
            xs[k] = ix + iw * (k - 1) / (NP - 1)
            ys[k] = iy + ih * (1 - fx.clamp(vals[src] or 0, 0, 1))
        end
        P:poly(xs, ys, NP, TREND_COL[si], 2, 220, true)
        local br = 5 + 3 * (0.5 + 0.5 * math.sin(t * 3 + si))
        P:dot(xs[NP], ys[NP], math.floor(br), TREND_COL[si], 70)
    end

    -- 图例色点
    for si = 1, 4 do
        P:dot(ix + (si - 1) * (iw / 4) + 6, iy + ih + 6, 4, TREND_COL[si], 255)
    end

    put(o.trendv, string.format("综合温度 %.1f C", D.raw.temp), o, "trendv")
end

-- ==================== 3 双针仪表 ====================
--[[
240 度扫角（150..390 度）的机械表盘：
刻度盘 + 红区 + 指针（长针 + 尾锤 + 轴心光晕）。
指针走 fx.approach 缓动趋近目标值，读数"追"目标，机械感就是从这里来的。
]]
local function draw_gauge(o, P, t, dt)
    local R = M.rects.gauge
    local D = o.data
    local half = R.w / 2

    for i = 1, 2 do
        local cfg = DIAL_CFG[i]
        local cx = R.x + (i - 1) * half + half * 0.5
        local cy = R.y + R.h * 0.56
        local GR = math.min(half * 0.40, R.h * 0.36)
        local col = cfg.col

        local A0, A1 = 150, 390
        local a0, a1 = A0 * fx.DEG, A1 * fx.DEG

        -- 表盘底：两圈暗环压出厚度
        P:dot(cx, cy, math.floor(GR * 1.02), 0x0C1424, 255)
        P:ring(cx, cy, math.floor(GR * 1.02), T.c.line2, 2, 220)
        P:ring(cx, cy, math.floor(GR * 0.90), 0x16243C, 1, 180)

        -- 进度弧（点串，弧长随读数）
        local target = (i == 1) and D.meter.vib or D.meter.temp
        --[[指针缓动：o.needle[i] 逐步趋近 target
        直接画 target 会让针"瞬移"，缓动 0.12 相当于每帧收敛 12%。]]
        local v = o.needle[i] or target
        v = fx.approach(v, target, 0.12, dt)
        o.needle[i] = v
        local vang = a0 + (a1 - a0) * fx.clamp(v, 0, 1)
        local NPT = 12
        for k = 0, NPT - 1 do
            local f = k / (NPT - 1)
            local a = a0 + f * (vang - a0)
            local pc = fx.hsl(192 + f * 26, 0.9, 0.55)
            P:dot(cx + math.cos(a) * GR * 0.80, cy + math.sin(a) * GR * 0.80,
                2 + 5 * f, pc, math.floor(60 + 195 * f))
        end

        -- 红区（后 15%）
        local ar0 = a0 + (a1 - a0) * 0.85
        for k = 0, 4 do
            local a = ar0 + (a1 - ar0) * k / 4
            P:line(cx + math.cos(a) * GR * 0.92, cy + math.sin(a) * GR * 0.92,
                cx + math.cos(a) * GR * 1.00, cy + math.sin(a) * GR * 1.00,
                T.c.red, 3, 220, true)
        end

        -- 刻度
        for k = 0, DIAL_TICKS - 1 do
            local f = k / (DIAL_TICKS - 1)
            local a = a0 + (a1 - a0) * f
            local long = (k % 4 == 0)
            local r0 = GR * (long and 0.60 or 0.66)
            local r1 = GR * 0.72
            P:line(cx + math.cos(a) * r0, cy + math.sin(a) * r0,
                cx + math.cos(a) * r1, cy + math.sin(a) * r1,
                long and T.c.txt or T.c.dim2, long and 2 or 1, long and 210 or 120, true)
        end

        -- 指针：长针 + 尾锤 + 轴心
        local na = a0 + (a1 - a0) * fx.clamp(v, 0, 1)
        local cs, sn = math.cos(na), math.sin(na)
        P:line(cx - cs * GR * 0.18, cy - sn * GR * 0.18,
            cx + cs * GR * 0.74, cy + sn * GR * 0.74, T.c.amber, 5, 255, true)
        P:line(cx - cs * GR * 0.26, cy - sn * GR * 0.26,
            cx - cs * GR * 0.10, cy - sn * GR * 0.10, T.c.amber, 3, 200, true)
        P:dot(cx, cy, 10, 0x1A2436, 255)
        P:ring(cx, cy, 10, T.c.amber, 2, 230)
        P:dot(cx, cy, 3, T.c.txt, 255)

        -- 指针尖端光晕
        P:dot(cx + cs * GR * 0.74, cy + sn * GR * 0.74, 9, T.c.amber, 60)

        put(o.dv[i], string.format("%.1f", v * cfg.span), o, "dv" .. i)
    end
end

-- ==================== 4 分段负载条 ====================
--[[
3 行水平分段条：每行一条暗轨道 + 12 格刻度块 + 一个发光前端。
末端光晕用一大一小两颗低透明度圆叠出来（同 fx.meter 的做法）。
]]
local function draw_load(o, P, t, dt)
    local R = M.rects.load
    local D = o.data
    local rowh = math.floor((R.h - 28) / 3)

    for i = 1, 3 do
        local cfg = LOAD_CFG[i]
        local y = R.y + 26 + (i - 1) * rowh
        local bh = rowh - 16
        local frac = fx.clamp(D.loads[i] or 0, 0, 1)
        local col = cfg.col

        -- 轨道
        local bx, bw = R.x + 92, R.w - 108
        P:box(bx, y, bw, bh, 0x14203A, 230, math.floor(bh / 2))

        -- 12 格刻度块
        local segw = (bw - 4) / LOAD_SEG
        local lit = math.floor(frac * LOAD_SEG + 0.5)
        for k = 0, LOAD_SEG - 1 do
            local on = (k < lit)
            local fade = k / (LOAD_SEG - 1)
            local c = on and fx.mix(col, 0xFFFFFF, fade * 0.35) or 0x1D2C48
            P:box(bx + 2 + k * segw + 1, y + 3, segw - 3, bh - 6, c,
                on and 245 or 190, 2)
        end

        -- 前端光晕
        if lit > 0 then
            local fw = bx + 2 + lit * segw
            P:dot(fw, y + bh / 2, math.floor(bh * 0.95), col, 55)
            P:dot(fw, y + bh / 2, math.floor(bh * 0.42), fx.shade(col, 0.55), 190)
        end

        put(o.lv[i], string.format("%d%%", math.floor(frac * 100 + 0.5)), o, "lv" .. i)
    end
end

-- ==================== 5 设备状态时间轴 ====================
--[[
5 个节点横排 + 引导虚线：节点落在一条基准线上，
向上引出虚线到状态名，当前工序的节点做大光晕。
]]
local function draw_tl(o, P, t, dt)
    local R = M.rects.tl
    local D = o.data
    local n = 5
    local step = (R.w - 40) / (n - 1)
    local y = R.y + 66

    -- 基准线
    P:line(R.x + 14, y, R.x + R.w - 14, y, 0x1B2B44, 2, 180, true)

    for i = 1, n do
        local d = D.tl[i]
        if not d then break end
        local x = R.x + 20 + step * (i - 1)
        local col = TL_COL[d.state] or T.c.dim2

        if d.state == 2 then
            local br = 4 + 2 * (0.5 + 0.5 * math.sin(t * 2.6))
            P:dot(x, y, math.floor(14 + br), col, 55)
        end
        P:dot(x, y, 10, 0x101A2E, 255)
        P:ring(x, y, 8, col, 2, d.state == 2 and 255 or 190)
        P:dot(x, y, 3, col, 255)

        -- 引导虚线
        P:dash(x, y - 12, x, R.y + 30, col, 1, 120, 3, 3)

        put(o.tn[i], d.name, o, "tn" .. i)
    end

    put(o.tlt, string.format("在制工站 %d/%d", 3, n), o, "tlt")
end

local DRAW = { draw_matrix, draw_trend, draw_gauge, draw_load, draw_tl }

-- ==================== 构建 ====================
--[[创建分块底与文字对象
@param table parent 舞台容器
@param table rects 不等分栏矩形表
@param table data  数据源
]]
function M.build(parent, rects, data)
    local o = { data = data, textT = 999, hot = true, needle = {} }

    --[[图元画布必须先创建：LVGL 后建的子对象画在上层，
    画布建晚了会盖住下面所有的 label。]]
    o.shape = airui.shape({
        parent = parent, x = 0, y = 0,
        w = T.inner.w, h = T.inner.h, items = {},
    })

    -- ===== 左大块：设备健康矩阵 =====
    local R = rects.mat
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
        parent = parent, x = R.x + 12, y = R.y + 6, w = 200, h = 18,
        text = "设备健康矩阵", font_size = T.f.mini,
        color = T.c.dim, align = airui.TEXT_ALIGN_LEFT,
    })

    local cw = R.w / MAT_COLS
    local chh = (MAT_BOT - MAT_TOP) / MAT_ROWS
    o.mt, o.mh, o.ms = {}, {}, {}
    for i = 1, MAT_COLS * MAT_ROWS do
        local c = (i - 1) % MAT_COLS
        local rr = math.floor((i - 1) / MAT_COLS)
        local x = R.x + c * cw
        local y = R.y + MAT_TOP + rr * chh
        -- 格底
        airui.container({
            parent = parent, x = x + 3, y = y + 3, w = cw - 6, h = chh - 6,
            color = 0x101A2E, color_opacity = 200, radius = 8,
            border_width = 0,
        })
        o.mt[i] = airui.label({
            parent = parent, x = x, y = y + 8, w = cw, h = 16,
            text = "--", font_size = T.f.mini,
            color = T.c.dim, align = airui.TEXT_ALIGN_CENTER,
        })
        o.ms[i] = airui.label({
            parent = parent, x = x, y = y + 34, w = cw, h = 14,
            text = "--", font_size = T.f.mini,
            color = T.c.dim2, align = airui.TEXT_ALIGN_CENTER,
        })
        o.mh[i] = airui.label({
            parent = parent, x = x, y = y + 52, w = cw, h = 18,
            text = "--", font_size = T.f.mini,
            color = T.c.txt, align = airui.TEXT_ALIGN_CENTER,
        })
    end

    -- 温度趋势标题
    airui.label({
        parent = parent, x = R.x + 12, y = R.y + TREND_Y + 2, w = 220, h = 18,
        text = "设备综合温度", font_size = T.f.mini,
        color = T.c.dim, align = airui.TEXT_ALIGN_LEFT,
    })
    o.trendv = airui.label({
        parent = parent, x = R.x + R.w - 220, y = R.y + TREND_Y + 2,
        w = 208, h = 18, text = "--", font_size = T.f.mini,
        color = T.c.cyan, align = airui.TEXT_ALIGN_RIGHT,
    })

    -- ===== 右上：双针仪表 =====
    R = rects.gauge
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
        parent = parent, x = R.x + 12, y = R.y + 6, w = 200, h = 18,
        text = "双针仪表", font_size = T.f.mini,
        color = T.c.dim, align = airui.TEXT_ALIGN_LEFT,
    })
    local half = R.w / 2
    o.dv, o.du, o.dn = {}, {}, {}
    for i = 1, 2 do
        local cfg = DIAL_CFG[i]
        local cx = R.x + (i - 1) * half + half * 0.5
        o.dn[i] = airui.label({
            parent = parent, x = cx - half * 0.5, y = R.y + 26,
            w = half, h = 18, text = cfg.name, font_size = T.f.mini,
            color = T.c.dim, align = airui.TEXT_ALIGN_CENTER,
        })
        o.dv[i] = airui.label({
            parent = parent, x = cx - 70, y = R.y + R.h * 0.56 - 14,
            w = 140, h = 32, text = "--", font_size = T.f.body,
            color = cfg.col, align = airui.TEXT_ALIGN_CENTER,
        })
        o.du[i] = airui.label({
            parent = parent, x = cx - 70, y = R.y + R.h * 0.56 + 18,
            w = 140, h = 16, text = cfg.unit, font_size = T.f.mini,
            color = T.c.dim2, align = airui.TEXT_ALIGN_CENTER,
        })
    end

    -- ===== 右中：分段负载条 =====
    R = rects.load
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
        parent = parent, x = R.x + 12, y = R.y + 6, w = 200, h = 18,
        text = "分段负载", font_size = T.f.mini,
        color = T.c.dim, align = airui.TEXT_ALIGN_LEFT,
    })
    local lrowh = math.floor((R.h - 28) / 3)
    o.lv, o.ln = {}, {}
    for i = 1, 3 do
        local cfg = LOAD_CFG[i]
        local y = R.y + 26 + (i - 1) * lrowh
        o.ln[i] = airui.label({
            parent = parent, x = R.x + 12, y = y + 1, w = 76, h = 16,
            text = cfg.name, font_size = T.f.mini,
            color = T.c.dim, align = airui.TEXT_ALIGN_LEFT,
        })
        o.lv[i] = airui.label({
            parent = parent, x = R.x + R.w - 60, y = y + 1, w = 48, h = 16,
            text = "--", font_size = T.f.mini,
            color = cfg.col, align = airui.TEXT_ALIGN_RIGHT,
        })
    end

    -- ===== 右下：设备状态时间轴 =====
    R = rects.tl
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
        parent = parent, x = R.x + 12, y = R.y + 6, w = 200, h = 18,
        text = "设备状态时间轴", font_size = T.f.mini,
        color = T.c.dim, align = airui.TEXT_ALIGN_LEFT,
    })
    o.tlt = airui.label({
        parent = parent, x = R.x + R.w - 180, y = R.y + 6, w = 168, h = 18,
        text = "--", font_size = T.f.mini,
        color = T.c.dim2, align = airui.TEXT_ALIGN_RIGHT,
    })
    local tstep = (R.w - 40) / 4
    o.tn = {}
    for i = 1, 5 do
        local x = R.x + 20 + tstep * (i - 1)
        o.tn[i] = airui.label({
            parent = parent, x = x - 36, y = R.y + 26,
            w = 72, h = 16, text = "--", font_size = T.f.mini,
            color = T.c.txt, align = airui.TEXT_ALIGN_CENTER,
        })
    end

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
