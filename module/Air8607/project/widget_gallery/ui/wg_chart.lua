--[[
@module  wg_chart
@summary WIDGET GALLERY - 图表组组件（面积趋势 / 多路折线 / 柱状 / 火花线 / 热力 / 雷达）
@version 1.0
@date    2026.10.23
@author  江访

=== 卡片位序（3 列 x 2 行）===
  1 面积趋势   2 多路折线   3 柱状图
  4 火花线组   5 热力图     6 雷达图

=== 图元预算 ===
每张卡片控制在 60 个图元以内，整页 6 张约 300 个。
airui 是 LVGL 之上的图元合成，图元数直接决定每帧的遍历与绘制开销，
超过 350 后 30fps 开始吃力（状态栏的「图元」读数可以自证）。
所以：面积图用 18 根柱而不是 48 根、折线降采样到 11 点、热力图不画描边。

=== 面积图为什么用柱子堆而不是填充多边形 ===
airui.shape 只有 line/circle/rect/ellipse 四种图元，没有多边形填充。
用「一根根竖直矩形」拼出面积，顺带每根柱子按高度做透明度渐变，
比纯色填充更好看，代价只是柱数个图元。
]]

local fx = require "fx"
local T = require "theme"

local M = {
    id = "chart",
    name = "图表",
}

M.cards = {
    { name = "面积趋势", en = "AREA" },
    { name = "多路折线", en = "MULTI LINE" },
    { name = "柱状对比", en = "BARS" },
    { name = "火花线组", en = "SPARKS" },
    { name = "热力分布", en = "HEATMAP" },
    { name = "雷达评估", en = "RADAR" },
}

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

-- ==================== 1 面积趋势 ====================
--[[
18 根竖柱拼出面积 + 顶部折线 + 网格 + 最新点光晕。
柱子顶端做白色渐变，底部做同色深压，看起来像有厚度的光带。
]]
local function draw_area(o, P, r, t, dt)
    local ix, iy, iw, ih = content(r.x, r.y, r.w, r.h)
    local plot_y, plot_h = iy + 6, ih - 34
    local vals, n = o.data.get("temp")

    -- 横向网格
    for k = 0, 3 do
        local y = plot_y + plot_h * k / 3
        P:line(ix, y, ix + iw, y, 0x1B2B44, 1, 140, false)
    end

    local COLS = 18
    local cw = iw / COLS
    local xs, ys = P._ax, P._ay
    if not xs then
        xs, ys = {}, {}
        P._ax, P._ay = xs, ys
    end

    for k = 0, COLS - 1 do
        -- 均匀采样 N 点到 COLS 柱
        local si = math.floor(k * (n - 1) / (COLS - 1)) + 1
        local v = vals[si] or 0
        local bh = plot_h * fx.clamp(v, 0, 1)
        local x = ix + k * cw
        -- 三段渐变柱
        P:box(x, plot_y + plot_h - bh, cw - 1, bh, 0x0E6FA0, 210, 2)
        if bh > 10 then
            P:box(x, plot_y + plot_h - bh, cw - 1, bh * 0.55, 0x1AA8E0, 150, 2)
        end
        if bh > 22 then
            P:box(x, plot_y + plot_h - bh, cw - 1, bh * 0.22, 0x6FE0FF, 120, 2)
        end
        -- 顶点（画折线用）
        xs[k + 1] = x + cw * 0.5
        ys[k + 1] = plot_y + plot_h - bh
    end
    P:poly(xs, ys, COLS, 0x9FEBFF, 2, 235, true)

    -- 最新点光晕
    local lx, ly = xs[COLS], ys[COLS]
    P:dot(lx, ly, 12, 0x22E6FF, 60)
    P:dot(lx, ly, 5, 0xFFFFFF, 255)

    -- 底部时间刻度
    for k = 0, 3 do
        local x = ix + iw * k / 3
        P:line(x, plot_y + plot_h + 2, x, plot_y + plot_h + 8,
            T.c.dim2, 1, 160, true)
    end

    put(o.c1, string.format("%.1f", o.data.raw.temp), o)
    put(o.c1b, "C", o)
    put(o.c1c, string.format("MIN %.1f  MAX %.1f",
        o.data.raw.temp - 3.2, o.data.raw.temp + 2.6), o)
end

-- ==================== 2 多路折线 ====================
--[[
四条降采样折线叠在同一个坐标里，右下角图例带小色点。
最新点各画一颗呼吸光晕，四条线的速度不同，视觉上会互相追逐。
]]
local LINE_SERIES = {
    { key = "temp",  col = 0x22E6FF, name = "温度" },
    { key = "hum",   col = 0x2BE59B, name = "湿度" },
    { key = "co2",   col = 0xFFB020, name = "CO2" },
    { key = "power", col = 0xA855F7, name = "功率" },
}
local DOWN = 11

local function draw_lines(o, P, r, t, dt)
    local ix, iy, iw, ih = content(r.x, r.y, r.w, r.h)
    local plot_y, plot_h = iy + 6, ih - 30

    for k = 0, 3 do
        local y = plot_y + plot_h * k / 3
        P:line(ix, y, ix + iw, y, 0x1B2B44, 1, 130, false)
    end

    local xs, ys = P._mx, P._my
    if not xs then
        xs, ys = {}, {}
        P._mx, P._my = xs, ys
    end

    for si, cfg in ipairs(LINE_SERIES) do
        local vals, n = o.data.get(cfg.key)
        for k = 1, DOWN do
            local src = math.floor((k - 1) * (n - 1) / (DOWN - 1)) + 1
            xs[k] = ix + iw * (k - 1) / (DOWN - 1)
            ys[k] = plot_y + plot_h * (1 - fx.clamp(vals[src] or 0, 0, 1))
        end
        P:poly(xs, ys, DOWN, cfg.col, 2, 220, true)
        -- 最新点
        local lx, ly = xs[DOWN], ys[DOWN]
        local br = 6 + 3 * (0.5 + 0.5 * math.sin(t * 3 + si))
        P:dot(lx, ly, br, cfg.col, 70)
        P:dot(lx, ly, 3, 0xFFFFFF, 240)
    end

    -- 图例色点
    for si, cfg in ipairs(LINE_SERIES) do
        local x = ix + (si - 1) * (iw / 4) + 6
        P:dot(x, iy + ih - 8, 4, cfg.col, 255)
    end

    put(o.c2, string.format("温度 %.1f C   湿度 %.0f %%",
        o.data.raw.temp, o.data.raw.hum), o)
end

-- ==================== 3 柱状对比 ====================
--[[
10 根柱子 + 目标虚线 + 均值实线。柱顶做高光条，超目标的柱子换色。
]]
local function draw_bars(o, P, r, t, dt)
    local ix, iy, iw, ih = content(r.x, r.y, r.w, r.h)
    local plot_y, plot_h = iy + 10, ih - 42
    local n = #o.data.bar

    for k = 0, 3 do
        local y = plot_y + plot_h * k / 3
        P:line(ix, y, ix + iw, y, 0x1B2B44, 1, 130, false)
    end

    local slot = iw / n
    local bw = slot - 7
    local sum = 0
    for i = 1, n do
        local v = o.data.bar[i]
        sum = sum + v
        local bh = plot_h * fx.clamp(v, 0, 1)
        local x = ix + (i - 1) * slot + 3
        local over = (v > 0.72)
        local col = over and T.c.amber or T.c.cyan
        -- 柱体（暗底 + 亮面）
        P:box(x, plot_y + plot_h - bh, bw, bh, col, 200, 3)
        P:box(x, plot_y + plot_h - bh, bw, math.min(bh, 8), fx.shade(col, 0.45), 235, 3)
        -- 柱底投影
        P:box(x, plot_y + plot_h - 2, bw, 2, col, 90, 1)
    end

    -- 目标虚线（0.72）
    local ty = plot_y + plot_h * (1 - 0.72)
    P:dash(ix, ty, ix + iw, ty, T.c.amber, 1, 200, 6, 5)
    -- 均值实线
    local avg = sum / n
    local ay = plot_y + plot_h * (1 - avg)
    P:line(ix, ay, ix + iw, ay, T.c.green, 2, 180, true)

    put(o.c3, string.format("AVG %.0f%%", avg * 100), o)
    put(o.c3b, string.format("MAX %.0f%%  TARGET 72%%", o.data.bar[3] * 100), o)
end

-- ==================== 4 火花线组 ====================
--[[
四行迷你趋势，右侧各带一个当前值。每行一条暗轨道 + 一条发光折线 + 端点。
]]
local SPARK_CFG = {
    { col = 0x22E6FF, name = "温度" },
    { col = 0x2BE59B, name = "湿度" },
    { col = 0xFFB020, name = "CO2" },
    { col = 0xA855F7, name = "功率" },
}

local function draw_sparks(o, P, r, t, dt)
    local ix, iy, iw, ih = content(r.x, r.y, r.w, r.h)
    local rows = 4
    local rowh = math.floor((ih - 6) / rows)
    local gw = iw - 64

    for i = 1, rows do
        local y = iy + 2 + (i - 1) * rowh
        local cfg = SPARK_CFG[i]
        local vals = o.data.spark[i]

        -- 行底与基线
        P:box(ix, y + 6, gw, rowh - 18, 0x101A2E, 180, 3)
        P:line(ix, y + rowh - 12, ix + gw, y + rowh - 12, 0x1B2B44, 1, 120, false)

        -- 降采样到 10 点
        local xs, ys = P._sx1, P._sy1
        if not xs then
            xs, ys = {}, {}
            P._sx1, P._sy1 = xs, ys
        end
        local NP = 10
        for k = 1, NP do
            local src = math.floor((k - 1) * (#vals - 1) / (NP - 1)) + 1
            xs[k] = ix + gw * (k - 1) / (NP - 1)
            ys[k] = y + 8 + (rowh - 22) * (1 - fx.clamp(vals[src] or 0, 0, 1))
        end
        P:poly(xs, ys, NP, cfg.col, 2, 230, true)
        P:dot(xs[NP], ys[NP], 4, 0xFFFFFF, 240)
        P:dot(xs[NP], ys[NP], 8, cfg.col, 60)

        put(o.sp[i], string.format("%s  %.0f", cfg.name, (vals[#vals] or 0) * 100), o)
    end
end

-- ==================== 5 热力图 ====================
--[[
12 列 x 4 行色块矩阵，颜色沿 0..1 从深蓝到亮黄。
单元格不画描边（描边会让 48 个格子变成 192 个图元），
改成格与格之间留 2px 空隙，靠底色分隔。
]]
local function draw_heat(o, P, r, t, dt)
    local ix, iy, iw, ih = content(r.x, r.y, r.w, r.h)
    local cols, rows = 12, 4
    local top = iy + 8
    local cell_w = (iw - 4) / cols
    local cell_h = (ih - 30) / rows

    for c = 1, cols do
        local col = o.data.heat[c]
        for rr = 1, rows do
            local v = fx.clamp(col[rr] or 0, 0, 1)
            -- 色带：深蓝 -> 青 -> 黄
            local cc
            if v < 0.5 then
                cc = fx.mix(0x0E2A4E, 0x1FA8E0, v * 2)
            else
                cc = fx.mix(0x1FA8E0, 0xFFD24A, (v - 0.5) * 2)
            end
            P:box(ix + (c - 1) * cell_w + 1, top + (rr - 1) * cell_h + 1,
                cell_w - 2, cell_h - 2, cc, 235, 3)
        end
    end

    -- 行列刻度
    for c = 1, cols, 3 do
        local x = ix + (c - 1) * cell_w + cell_w / 2
        P:line(x, top + rows * cell_h + 3, x, top + rows * cell_h + 9,
            T.c.dim2, 1, 150, true)
    end

    -- 色标条
    local bar_y = iy + ih - 12
    for k = 0, 11 do
        local f = k / 11
        local cc
        if f < 0.5 then
            cc = fx.mix(0x0E2A4E, 0x1FA8E0, f * 2)
        else
            cc = fx.mix(0x1FA8E0, 0xFFD24A, (f - 0.5) * 2)
        end
        P:box(ix + iw * f, bar_y, iw / 12 - 1, 8, cc, 255, 2)
    end

    put(o.c5, string.format("峰值 %d  均值 %d",
        math.floor(o.data.raw.lux), math.floor(o.data.raw.lux * 0.72)), o)
end

-- ==================== 6 雷达图 ====================
--[[
六轴雷达：三圈网格 + 六根轴 + 半透明数据面 + 顶点光点。
数据面用六条边的线画，内部再叠一圈内缩 0.72 的浅色面做"厚度"。
]]
local function draw_radar(o, P, r, t, dt)
    local ix, iy, iw, ih = content(r.x, r.y, r.w, r.h)
    local cx, cy = ix + iw * 0.5, iy + ih * 0.52
    local R = math.min(iw * 0.46, ih * 0.44)
    local n = 6

    -- 网格圈（用折线逼近多边形）
    local xs, ys = P._rx, P._ry
    if not xs then
        xs, ys = {}, {}
        P._rx, P._ry = xs, ys
    end
    for ring = 1, 3 do
        local rr = R * ring / 3
        for k = 1, n do
            local a = -fx.TAU * 0.25 + fx.TAU * (k - 1) / n
            xs[k] = cx + math.cos(a) * rr
            ys[k] = cy + math.sin(a) * rr
        end
        xs[n + 1], ys[n + 1] = xs[1], ys[1]
        P:poly(xs, ys, n + 1, ring == 3 and T.c.line2 or T.c.line, 1,
            ring == 3 and 190 or 130, false)
    end

    -- 轴
    for k = 1, n do
        local a = -fx.TAU * 0.25 + fx.TAU * (k - 1) / n
        P:line(cx, cy, cx + math.cos(a) * R, cy + math.sin(a) * R,
            T.c.line, 1, 140, true)
    end

    -- 数据面（内缩版做底层辉光）
    for layer = 1, 2 do
        local scale = (layer == 1) and 0.72 or 1.0
        for k = 1, n do
            local a = -fx.TAU * 0.25 + fx.TAU * (k - 1) / n
            local rr = R * fx.clamp(o.data.radar[k] or 0, 0, 1) * scale
            xs[k] = cx + math.cos(a) * rr
            ys[k] = cy + math.sin(a) * rr
        end
        xs[n + 1], ys[n + 1] = xs[1], ys[1]
        local col = layer == 1 and 0x2BE59B or 0x9DFFE0
        P:poly(xs, ys, n + 1, col, layer == 1 and 3 or 2, layer == 1 and 90 or 230, true)
    end

    -- 顶点
    for k = 1, n do
        local a = -fx.TAU * 0.25 + fx.TAU * (k - 1) / n
        local rr = R * fx.clamp(o.data.radar[k] or 0, 0, 1)
        P:dot(cx + math.cos(a) * rr, cy + math.sin(a) * rr, 8, 0x2BE59B, 60)
        P:dot(cx + math.cos(a) * rr, cy + math.sin(a) * rr, 3, 0xFFFFFF, 255)
    end

    local sum = 0
    for k = 1, n do sum = sum + (o.data.radar[k] or 0) end
    put(o.c6, string.format("综合 %d", math.floor(sum / n * 100)), o)
end

local DRAW = { draw_area, draw_lines, draw_bars, draw_sparks, draw_heat, draw_radar }

-- ==================== 构建 ====================
function M.build(parent, rects, data)
    local o = { data = data, rects = rects }
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
        airui.label({
            parent = parent, x = r.x + 12, y = r.y + 8, w = r.w - 110, h = 22,
            text = card.name, font_size = T.f.text,
            color = T.c.txt, align = airui.TEXT_ALIGN_LEFT,
        })
        airui.label({
            parent = parent, x = r.x + r.w - 102, y = r.y + 10, w = 90, h = 18,
            text = card.en, font_size = T.f.mini,
            color = T.c.dim2, align = airui.TEXT_ALIGN_RIGHT,
        })
    end

    local r1 = rects[1]
    local ix, iy, iw, ih = content(r1.x, r1.y, r1.w, r1.h)
    o.c1 = airui.label({
        parent = parent, x = ix, y = iy + ih - 30, w = 110, h = 26,
        text = "--", font_size = T.f.body, color = T.c.cyan,
        align = airui.TEXT_ALIGN_LEFT,
    })
    o.c1b = airui.label({
        parent = parent, x = ix + 108, y = iy + ih - 26, w = 30, h = 18,
        text = "C", font_size = T.f.mini, color = T.c.dim2,
        align = airui.TEXT_ALIGN_LEFT,
    })
    o.c1c = airui.label({
        parent = parent, x = ix + iw - 200, y = iy + ih - 26, w = 200, h = 18,
        text = "", font_size = T.f.mini, color = T.c.dim,
        align = airui.TEXT_ALIGN_RIGHT,
    })

    local r2 = rects[2]
    ix, iy, iw, ih = content(r2.x, r2.y, r2.w, r2.h)
    o.c2 = airui.label({
        parent = parent, x = ix, y = iy + ih - 24, w = iw, h = 20,
        text = "", font_size = T.f.mini, color = T.c.dim,
        align = airui.TEXT_ALIGN_LEFT,
    })

    local r3 = rects[3]
    ix, iy, iw, ih = content(r3.x, r3.y, r3.w, r3.h)
    o.c3 = airui.label({
        parent = parent, x = ix, y = iy + ih - 30, w = 130, h = 26,
        text = "--", font_size = T.f.text, color = T.c.green,
        align = airui.TEXT_ALIGN_LEFT,
    })
    o.c3b = airui.label({
        parent = parent, x = ix + iw - 210, y = iy + ih - 28, w = 210, h = 18,
        text = "", font_size = T.f.mini, color = T.c.dim,
        align = airui.TEXT_ALIGN_RIGHT,
    })

    local r4 = rects[4]
    ix, iy, iw, ih = content(r4.x, r4.y, r4.w, r4.h)
    local rowh = math.floor((ih - 6) / 4)
    o.sp = {}
    for i = 1, 4 do
        o.sp[i] = airui.label({
            parent = parent, x = ix + iw - 62, y = iy + 2 + (i - 1) * rowh + 20,
            w = 62, h = 18, text = "--", font_size = T.f.mini,
            color = T.c.dim, align = airui.TEXT_ALIGN_RIGHT,
        })
    end

    local r5 = rects[5]
    ix, iy, iw, ih = content(r5.x, r5.y, r5.w, r5.h)
    o.c5 = airui.label({
        parent = parent, x = ix, y = iy, w = iw, h = 18,
        text = "", font_size = T.f.mini, color = T.c.dim,
        align = airui.TEXT_ALIGN_LEFT,
    })

    local r6 = rects[6]
    ix, iy, iw, ih = content(r6.x, r6.y, r6.w, r6.h)
    o.c6 = airui.label({
        parent = parent, x = ix, y = iy + ih - 26, w = iw, h = 22,
        text = "--", font_size = T.f.text, color = 0x2BE59B,
        align = airui.TEXT_ALIGN_CENTER,
    })

    return o
end

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
