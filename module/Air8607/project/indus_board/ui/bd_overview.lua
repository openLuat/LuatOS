--[[
@module  bd_overview
@summary INDUS BOARD - 视图1 产线总览（KPI / 产线状态条 / 产能趋势 / 告警 / 工单环）
@version 1.0
@date    2026.10.23
@author  江访

=== 不等分栏 rect 表（舞台内容区相对坐标 0..994 x 0..446）===
  左栏 KPI       x   0 .. 232  y  0 .. 446   3 张竖排小卡（h=142 gap=10）
  中栏 产线状态  x 242 .. 652  y  0 .. 268   5 条横向状态条（主视觉上半）
  中栏 产能趋势  x 242 .. 652  y 276 .. 446   18 根渐变柱 + 顶线（主视觉下半）
  右上 实时告警  x 662 .. 994  y  0 .. 270   5 行滚动告警
  右下 工单进度  x 662 .. 994  y 280 .. 446   3 个 270 度点串进度环

=== 组件契约 ===
build(parent, rects, data) -> o     创建 label 等 LVGL 对象，返回句柄
update(o, P, t, dt)                 把动态图元写进图元池 P
rects 是本模块导出的 M.rects，坐标一律是舞台内容区相对坐标，
写 T.inner.x + ... 会整体偏移 (15, 65)。

=== 绘图要点（都是踩过的坑）===
1、o.shape 必须在 build() 第一句创建：LVGL 后建的子对象画在上层，
   画布建晚了会盖住下面所有的 label。
2、分块底与描边用 airui.container 画（静态、不进图元预算），
   动态图元才写进 shape，整页控制在 350 个以内。
3、进度环用「一串实心圆点」逼近粗弧：折线画粗弧在转角处会露接缝，
   圆点半径/不透明度沿弧长渐变还能顺带做出辉光。
4、面积图用一根根竖直 box 堆出来：shape 没有多边形填充，
   18 根渐变柱比 48 根纯色柱好看而且便宜。
5、图元整型字段（width/opacity/radius/r/w/h）必须是整数，
   非整数会在 C 层被 lua_tointeger 静默变 0。fx.lua 的写入方法已统一取整，
   自己算的值（点半径、透明度）也一律 math.floor。
6、文字 200ms 才刷新，且值没变就不 set_text，见 put()。
]]

local fx = require "fx"
local T = require "theme"

local M = {
    id = "overview",
    name = "产线总览",
}

-- ==================== 不等分栏布局 ====================
M.rects = {
    kpi   = { x = 0,   y = 0,   w = 232, h = 446 },
    lines = { x = 242, y = 0,   w = 410, h = 268 },
    cap   = { x = 242, y = 276, w = 410, h = 170 },
    alarm = { x = 662, y = 0,   w = 332, h = 270 },
    order = { x = 662, y = 280, w = 332, h = 166 },
}

-- KPI 三卡：竖排 h=142 gap=10，3*142 + 2*10 = 446
local KPI_H, KPI_GAP = 142, 10

local KPI_CFG = {
    { key = "oee",    name = "OEE",     unit = "%",   col = T.c.cyan,  fmt = "%.1f" },
    { key = "output", name = "今日产量", unit = "pcs", col = T.c.green, fmt = "%.0f" },
    { key = "yield",  name = "良率",     unit = "%",   col = T.c.lime,  fmt = "%.2f" },
}

-- 状态色语义：运行=绿 待机=青 告警=琥珀 停机=红
local STATE_COL = { T.c.green, T.c.cyan, T.c.amber, T.c.red }
local STATE_TXT = { "运行", "待机", "告警", "停机" }

-- 产能面积图柱数（18 根是图元预算与观感的平衡点）
local CAP_COLS = 18

-- 工单环点串数
local RING_DOTS = 14

-- ==================== 文字节流 ====================
--[[只在 hot 帧（200ms 一次）且内容变化时才 set_text
set_text 会让 LVGL 重排文本并额外产生一块脏区，每帧无脑写是纯浪费。
@param table lb label 对象
@param string txt 目标文本
@param table o 视图句柄（借用 o.hot / o._tx 做节拍与去重）
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

-- ==================== 1 KPI 三卡 ====================
--[[
每卡：名称 + 大号数值 + 单位 + 迷你趋势（12 点折线）+ 达成率细条。
趋势线用 fx.spark（内部复用缓冲区，顺序调用即可），
末端补一大一小两颗光点做"最新点"。
]]
local function draw_kpi(o, P, t, dt)
    local R = M.rects.kpi
    local D = o.data

    for i = 1, 3 do
        local cfg = KPI_CFG[i]
        local x = R.x
        local y = R.y + (i - 1) * (KPI_H + KPI_GAP)
        local col = cfg.col

        -- 达成率细条
        local bw = R.w - 24
        local by = y + 116
        P:box(x + 12, by, bw, 5, 0x1B2B44, 220, 2)
        local g = fx.clamp(D.kpi_goal[i] or 0, 0, 1)
        local fw = bw * g
        if fw >= 2 then
            P:box(x + 12, by, fw, 5, col, 235, 2)
            P:dot(x + 12 + fw, by + 2, 5, col, 70)
        end

        -- 迷你趋势
        local vals = D.kpi_spark[i]
        local NP = 12
        local sx, sw = x + 12, R.w - 24
        local sy, sh = y + 82, 28
        fx.spark(P, vals, NP, sx, sy, sw, sh, col, 2, 220)
        local lx = sx + sw
        local ly = sy + sh - fx.clamp(vals[NP] or 0, 0, 1) * sh
        P:dot(lx, ly, 8, col, 60)
        P:dot(lx, ly, 3, 0xFFFFFF, 240)

        -- 趋势基线
        P:line(sx, sy + sh, sx + sw, sy + sh, 0x1B2B44, 1, 130, false)

        put(o.kv[i], string.format(cfg.fmt, D.kpi[cfg.key] or 0), o, "kv" .. i)
        put(o.kg[i], string.format("达成 %d%%", math.floor(g * 100 + 0.5)), o, "kg" .. i)
    end
end

-- ==================== 2 产线状态条 ====================
--[[
5 条横向状态条：线体名 + 当前工单号 + 运行状态灯 + 节拍进度条。
状态灯用「大光晕 + 小实心」两层圆，呼吸相位按序号错开，
一整排灯才不会同频闪。节拍进度条到头就换型（数据侧已处理）。
]]
local function draw_lines(o, P, t, dt)
    local R = M.rects.lines
    local D = o.data
    local rowh = math.floor(R.h / 5)

    for i = 1, 5 do
        local d = D.lines[i]
        if not d then break end
        local y = R.y + (i - 1) * rowh
        local col = STATE_COL[d.state] or T.c.dim

        -- 状态灯（呼吸）
        local ph = t * 2.1 + i * 0.8
        local br = 6 + 2.5 * (0.5 + 0.5 * math.sin(ph))
        local opa = math.floor(45 + 40 * (0.5 + 0.5 * math.sin(ph)))
        P:dot(R.x + 112, y + 38, math.floor(br * 2.2), col, opa)
        P:dot(R.x + 112, y + 38, math.floor(br), col, 255)

        -- 节拍进度条
        local bx, bw = R.x + 130, R.w - 148
        local by, bh = y + 32, 13
        P:box(bx, by, bw, bh, 0x14203A, 230, 6)
        local fw = bw * fx.clamp(d.cycle, 0, 1)
        if fw >= 2 then
            P:box(bx, by, fw, bh, col, 235, 6)
            P:dot(bx + fw, by + bh / 2, math.floor(bh * 0.95), col, 55)
            P:dot(bx + fw, by + bh / 2, math.floor(bh * 0.42), fx.shade(col, 0.55), 190)
        end

        -- 分隔线
        if i < 5 then
            P:line(R.x, y + rowh - 2, R.x + R.w, y + rowh - 2, 0x1B2B44, 1, 120, false)
        end

        put(o.ln[i], d.name, o, "ln" .. i)
        put(o.lw[i], d.wo, o, "lw" .. i)
        put(o.ls[i], STATE_TXT[d.state] or "--", o, "ls" .. i)
        put(o.lp[i], string.format("%d%%", math.floor(d.cycle * 100 + 0.5)), o, "lp" .. i)
    end
end

-- ==================== 3 产能趋势面积图 ====================
--[[
18 根竖柱拼出面积 + 顶部折线 + 网格 + 最新点光晕。
柱子按高度做三段透明度渐变，看起来像有厚度的光带。
]]
local function draw_cap(o, P, t, dt)
    local R = M.rects.cap
    local D = o.data
    local ix, iy = R.x + 12, R.y + 30
    local iw, ih = R.w - 24, R.h - 46

    -- 横向网格
    for k = 0, 3 do
        local y = iy + ih * k / 3
        P:line(ix, y, ix + iw, y, 0x1B2B44, 1, 130, false)
    end

    local vals, n = D.get("cap")
    local xs, ys = P._ovx, P._ovy
    if not xs then
        xs, ys = {}, {}
        P._ovx, P._ovy = xs, ys
    end

    local COLS = CAP_COLS
    local cw = iw / COLS
    for k = 0, COLS - 1 do
        -- 从 48 点曲线均匀采样到 18 柱
        local si = math.floor(k * (n - 1) / (COLS - 1)) + 1
        local v = fx.clamp(vals[si] or 0, 0, 1)
        local bh = ih * v
        local x = ix + k * cw
        P:box(x, iy + ih - bh, cw - 1, bh, 0x0E6FA0, 210, 2)
        if bh > 10 then
            P:box(x, iy + ih - bh, cw - 1, bh * 0.55, 0x1AA8E0, 150, 2)
        end
        if bh > 22 then
            P:box(x, iy + ih - bh, cw - 1, bh * 0.22, 0x6FE0FF, 120, 2)
        end
        xs[k + 1] = x + cw * 0.5
        ys[k + 1] = iy + ih - bh
    end
    P:poly(xs, ys, COLS, 0x9FEBFF, 2, 235, true)

    -- 最新点光晕
    local lx, ly = xs[COLS], ys[COLS]
    P:dot(lx, ly, 12, 0x22E6FF, 60)
    P:dot(lx, ly, 5, 0xFFFFFF, 255)

    -- 底部刻度
    for k = 0, 3 do
        local x = ix + iw * k / 3
        P:line(x, iy + ih + 2, x, iy + ih + 8, T.c.dim2, 1, 160, true)
    end

    put(o.capv, string.format("%.0f 件/h", D.raw.cap), o, "capv")
end

-- ==================== 4 实时告警滚动列表 ====================
--[[
5 行告警：等级色条 + 呼吸光点 + 文字 + 时间。
最上面一行（最新）整行做低透明度底色，视觉上"刚弹出来"。
等级 3 的行光点持续呼吸，其余常亮。
]]
local function draw_alarm(o, P, t, dt)
    local R = M.rects.alarm
    local D = o.data
    local rows = #D.alarms
    local top = R.y + 28
    local rh = math.floor((R.h - 34) / rows)

    for i = 1, rows do
        local a = D.alarms[i]
        if not a then break end
        local y = top + (i - 1) * rh
        local col = (a.level == 3) and T.c.red
            or ((a.level == 2) and T.c.amber or T.c.cyan)

        -- 第一行高亮底
        if i == 1 then
            P:box(R.x + 2, y, R.w - 4, rh - 3, col, 26, 5)
        end

        -- 等级色条
        P:box(R.x + 2, y + 3, 3, rh - 9, col, 255, 2)

        -- 呼吸光点
        local blink = (a.level == 3) and (0.45 + 0.55 * (0.5 + 0.5 * math.sin(t * 3.4))) or 1
        P:dot(R.x + 18, y + rh / 2 - 1, math.floor(11 * blink), col, math.floor(55 * blink))
        P:dot(R.x + 18, y + rh / 2 - 1, 5, col, 255)

        -- 分隔线
        if i < rows then
            P:line(R.x + 2, y + rh - 3, R.x + R.w - 2, y + rh - 3, 0x1B2B44, 1, 120, false)
        end

        put(o.al[i], string.format("%s  %s", a.src, a.text), o, "al" .. i)
        put(o.alt[i], string.format("%d\"", math.floor(a.t)), o, "alt" .. i)
    end
end

-- ==================== 5 环形工单进度 ====================
--[[
3 个 270 度点串进度环 + 中心百分比。
环用点串画：点半径沿弧长递增、末端补一颗高亮头点，形成"拖尾"的辉光感。
导轨用 P:ring 一次性画完，比再铺一圈点便宜 13 个图元。
]]
local function draw_orders(o, P, t, dt)
    local R = M.rects.order
    local D = o.data
    local iw = R.w - 20
    local Rr = math.min(iw / 3 * 0.32, (R.h - 20) * 0.28)

    for i = 1, 3 do
        local g = D.orders[i]
        if not g then break end
        local cx = R.x + 10 + iw * (i * 2 - 1) / 6
        local cy = R.y + 62
        local col = (i == 1) and T.c.cyan or ((i == 2) and T.c.green or T.c.violet)

        -- 导轨
        P:ring(cx, cy, math.floor(Rr) + 5, 0x16243C, 10, 255)

        -- 进度点串（270 度）
        local A0 = -fx.TAU * 0.75
        local span = fx.TAU * 0.75 * fx.clamp(g.v, 0, 1)
        local ND = RING_DOTS
        for k = 0, ND - 1 do
            local f = k / (ND - 1)
            local a = A0 + f * span
            P:dot(cx + math.cos(a) * Rr, cy + math.sin(a) * Rr,
                2 + 4 * f, col, math.floor(70 + 185 * f))
        end
        -- 头部高亮
        local ah = A0 + span
        local hx, hy = cx + math.cos(ah) * Rr, cy + math.sin(ah) * Rr
        P:dot(hx, hy, 5, 0xFFFFFF, 255)

        put(o.op[i], string.format("%d%%", math.floor(g.v * 100 + 0.5)), o, "op" .. i)
        put(o.on[i], g.name, o, "on" .. i)
    end
end

local DRAW = { draw_kpi, draw_lines, draw_cap, draw_alarm, draw_orders }

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

    -- ===== 左栏：3 张 KPI 小卡 =====
    local R = rects.kpi
    o.kv, o.ku, o.kg = {}, {}, {}
    for i = 1, 3 do
        local cfg = KPI_CFG[i]
        local y = R.y + (i - 1) * (KPI_H + KPI_GAP)
        airui.container({
            parent = parent, x = R.x, y = y, w = R.w, h = KPI_H,
            color = T.c.panel, color_opacity = 255, radius = 10,
            border_color = T.c.line, border_width = 1,
        })
        airui.container({
            parent = parent, x = R.x + 1, y = y + 1, w = R.w - 2, h = 2,
            color = T.c.panel_hl, color_opacity = 255, radius = 1,
            border_width = 0,
        })
        airui.label({
            parent = parent, x = R.x + 12, y = y + 6, w = 130, h = 18,
            text = cfg.name, font_size = T.f.mini,
            color = T.c.dim, align = airui.TEXT_ALIGN_LEFT,
        })
        o.ku[i] = airui.label({
            parent = parent, x = R.x + R.w - 70, y = y + 6, w = 58, h = 18,
            text = cfg.unit, font_size = T.f.mini,
            color = T.c.dim2, align = airui.TEXT_ALIGN_RIGHT,
        })
        o.kv[i] = airui.label({
            parent = parent, x = R.x + 12, y = y + 24, w = R.w - 24, h = 54,
            text = "--", font_size = T.f.big,
            color = cfg.col, align = airui.TEXT_ALIGN_LEFT,
        })
        o.kg[i] = airui.label({
            parent = parent, x = R.x + 12, y = y + 124, w = R.w - 24, h = 14,
            text = "", font_size = T.f.mini,
            color = T.c.dim2, align = airui.TEXT_ALIGN_LEFT,
        })
    end

    -- ===== 中栏：产线状态条 =====
    R = rects.lines
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
        text = "产线状态", font_size = T.f.mini,
        color = T.c.dim, align = airui.TEXT_ALIGN_LEFT,
    })
    local rowh = math.floor(R.h / 5)
    o.ln, o.lw, o.ls, o.lp = {}, {}, {}, {}
    for i = 1, 5 do
        local y = R.y + (i - 1) * rowh
        o.ln[i] = airui.label({
            parent = parent, x = R.x + 12, y = y + 5, w = 96, h = 20,
            text = "--", font_size = T.f.text,
            color = T.c.txt, align = airui.TEXT_ALIGN_LEFT,
        })
        o.lw[i] = airui.label({
            parent = parent, x = R.x + R.w - 132, y = y + 7, w = 120, h = 18,
            text = "--", font_size = T.f.mini,
            color = T.c.dim, align = airui.TEXT_ALIGN_RIGHT,
        })
        o.ls[i] = airui.label({
            parent = parent, x = R.x + 122, y = y + 31, w = 44, h = 16,
            text = "--", font_size = T.f.mini,
            color = T.c.dim, align = airui.TEXT_ALIGN_LEFT,
        })
        o.lp[i] = airui.label({
            parent = parent, x = R.x + R.w - 60, y = y + 31, w = 48, h = 16,
            text = "--", font_size = T.f.mini,
            color = T.c.dim2, align = airui.TEXT_ALIGN_RIGHT,
        })
    end

    -- ===== 中栏：产能趋势 =====
    R = rects.cap
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
        text = "产能趋势", font_size = T.f.mini,
        color = T.c.dim, align = airui.TEXT_ALIGN_LEFT,
    })
    o.capv = airui.label({
        parent = parent, x = R.x + R.w - 200, y = R.y + 6, w = 188, h = 18,
        text = "--", font_size = T.f.mini,
        color = T.c.cyan, align = airui.TEXT_ALIGN_RIGHT,
    })

    -- ===== 右上：实时告警 =====
    R = rects.alarm
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
        text = "实时告警", font_size = T.f.mini,
        color = T.c.dim, align = airui.TEXT_ALIGN_LEFT,
    })
    local arh = math.floor((R.h - 34) / 5)
    o.al, o.alt = {}, {}
    for i = 1, 5 do
        local y = R.y + 28 + (i - 1) * arh
        o.al[i] = airui.label({
            parent = parent, x = R.x + 30, y = y + 6, w = R.w - 96, h = 18,
            text = "--", font_size = T.f.mini,
            color = T.c.txt, align = airui.TEXT_ALIGN_LEFT,
        })
        o.alt[i] = airui.label({
            parent = parent, x = R.x + R.w - 62, y = y + 6, w = 50, h = 18,
            text = "", font_size = T.f.mini,
            color = T.c.dim2, align = airui.TEXT_ALIGN_RIGHT,
        })
    end

    -- ===== 右下：工单进度环 =====
    R = rects.order
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
        text = "工单进度", font_size = T.f.mini,
        color = T.c.dim, align = airui.TEXT_ALIGN_LEFT,
    })
    local iw = R.w - 20
    o.op, o.on = {}, {}
    for i = 1, 3 do
        local cx = R.x + 10 + iw * (i * 2 - 1) / 6
        o.op[i] = airui.label({
            parent = parent, x = cx - 44, y = R.y + 50,
            w = 88, h = 24, text = "--", font_size = T.f.text,
            color = T.c.txt, align = airui.TEXT_ALIGN_CENTER,
        })
        o.on[i] = airui.label({
            parent = parent, x = cx - 50, y = R.y + 118,
            w = 100, h = 18, text = "", font_size = T.f.mini,
            color = T.c.dim2, align = airui.TEXT_ALIGN_CENTER,
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
