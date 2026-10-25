--[[
@module  wg_status
@summary WIDGET GALLERY - 状态组组件（设备矩阵 / 告警列表 / 进度环 / KPI / 步骤条 / 时间轴）
@version 1.0
@date    2026.10.23
@author  江访

=== 卡片位序（3 列 x 2 行）===
  1 设备状态矩阵  2 告警列表   3 进度环组
  4 KPI 数字组    5 工艺步骤条 6 事件时间轴

=== 状态色语义（工业看板通用）===
  运行 = 绿     待机 = 青     告警 = 琥珀    故障 / 离线 = 红
  状态灯一律用「大光晕 + 小实心」两层圆画：
  单颗实心圆在 10 寸屏上看不出"在发光"，叠一层半径 2~3 倍、透明度 50~70 的光晕才有灯感。
  呼吸用 sin 调制半径与透明度，但相位按序号错开，一整排灯才不会同频闪。
]]

local fx = require "fx"
local T = require "theme"

local M = {
    id = "status",
    name = "状态",
}

M.cards = {
    { name = "设备状态矩阵", en = "DEVICE" },
    { name = "实时告警",     en = "ALARM" },
    { name = "工单进度",     en = "PROGRESS" },
    { name = "KPI 指标组",   en = "KPI" },
    { name = "工艺步骤",     en = "STEP" },
    { name = "事件时间轴",   en = "TIMELINE" },
}

local function content(x, y, w, h)
    return x + 12, y + 34, w - 24, h - 44
end

-- 状态色表
local STATE_COL = { T.c.green, T.c.cyan, T.c.amber, T.c.red }

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

-- ==================== 1 设备状态矩阵 ====================
--[[
3 列 x 4 行设备格。每格：状态光晕灯 + 设备名 + 负载细条。
状态灯呼吸相位按 (行*3+列) 错开，整屏看起来是"波浪式"的活。
]]
local function draw_device(o, P, r, t, dt)
    local ix, iy, iw, ih = content(r.x, r.y, r.w, r.h)
    local cols, rows = 3, 4
    local cw = iw / cols
    local chh = ih / rows

    for i = 1, cols * rows do
        local d = o.data.dev[i]
        if not d then break end
        local c = (i - 1) % cols
        local rr = math.floor((i - 1) / cols)
        local x = ix + c * cw
        local y = iy + rr * chh

        -- 格底
        P:box(x + 3, y + 3, cw - 6, chh - 6, 0x101A2E, 200, 6)

        -- 状态灯（呼吸）
        local col = STATE_COL[d.state] or T.c.dim
        local ph = (i * 0.7) + t * 2.2
        local br = 7 + 2.5 * (0.5 + 0.5 * math.sin(ph))
        local opa = math.floor(45 + 45 * (0.5 + 0.5 * math.sin(ph)))
        P:dot(x + cw * 0.5, y + 16, br * 2.1, col, opa)
        P:dot(x + cw * 0.5, y + 16, br, col, 255)

        -- 负载细条
        local bw = cw - 22
        P:box(x + 11, y + chh - 18, bw, 5, 0x1B2B44, 220, 2)
        local fw = bw * fx.clamp(d.load, 0, 1)
        if fw >= 2 then
            P:box(x + 11, y + chh - 18, fw, 5, col, 235, 2)
            P:dot(x + 11 + fw, y + chh - 15.5, 5, col, 70)
        end

        put(o.dev[i], d.tag, o)
    end

    -- 图例色点（文字由 build 里的 4 个 label 承担）
    for i = 1, 4 do
        local x = ix + (i - 1) * (iw / 4) + 8
        P:dot(x, iy + ih - 4, 4, STATE_COL[i], 255)
    end
end

-- ==================== 2 告警列表 ====================
--[[
5 行告警。左侧等级色条 + 等级光点 + 文字 + 右侧时间。
最上面一行（最新）整行做低透明度底色，视觉上"刚弹出来"。
]]
local function draw_alarm(o, P, r, t, dt)
    local ix, iy, iw, ih = content(r.x, r.y, r.w, r.h)
    local rows = #o.data.alarms
    local rh = math.floor((ih - 4) / rows)

    for i = 1, rows do
        local a = o.data.alarms[i]
        local y = iy + 2 + (i - 1) * rh
        local col = (a.level == 3) and T.c.red
            or ((a.level == 2) and T.c.amber or T.c.cyan)

        -- 第一行高亮底
        if i == 1 then
            P:box(ix, y, iw, rh - 3, col, 26, 5)
        end

        -- 等级色条
        P:box(ix, y + 3, 3, rh - 9, col, 255, 2)

        -- 等级光点（严重告警呼吸）
        local ph = t * 3.4
        local blink = (a.level == 3) and (0.45 + 0.55 * (0.5 + 0.5 * math.sin(ph))) or 1
        P:dot(ix + 16, y + rh / 2 - 1, 11 * blink, col, math.floor(55 * blink))
        P:dot(ix + 16, y + rh / 2 - 1, 5, col, 255)

        -- 分隔线
        if i < rows then
            P:line(ix, y + rh - 3, ix + iw, y + rh - 3, 0x1B2B44, 1, 120, false)
        end

        put(o.al[i], string.format("%s  %s", a.src, a.text), o)
        put(o.alt[i], string.format("%d\"", a.t), o)
    end
end

-- ==================== 3 工单进度 ====================
--[[
三行进度环 + 中间一个总进度条。
环用点串画（同 wg_gauge 的环形），但只画 270 度，底部留口方便放数字。
]]
local function draw_progress(o, P, r, t, dt)
    local ix, iy, iw, ih = content(r.x, r.y, r.w, r.h)

    local rings = {
        { v = o.data.gauge.a, col = T.c.cyan,   name = "WO-2608" },
        { v = o.data.gauge.b, col = T.c.green,  name = "WO-2609" },
        { v = o.data.gauge.c, col = T.c.violet, name = "WO-2610" },
    }

    local R = math.min(iw / 3 * 0.34, ih * 0.30)
    for i = 1, 3 do
        local g = rings[i]
        local cx = ix + iw * (i * 2 - 1) / 6
        local cy = iy + ih * 0.38

        -- 导轨
        P:ring(cx, cy, math.floor(R) + 5, 0x16243C, 10, 255)

        -- 进度点串
        local A0 = -fx.TAU * 0.75
        local span = fx.TAU * 0.75 * fx.clamp(g.v, 0, 1)
        local ND = 18
        for k = 0, ND - 1 do
            local f = k / (ND - 1)
            local a = A0 + f * span
            P:dot(cx + math.cos(a) * R, cy + math.sin(a) * R,
                2 + 4 * f, g.col, math.floor(70 + 185 * f))
        end

        put(o.pg[i], string.format("%d%%", math.floor(g.v * 100)), o)
        put(o.pgn[i], g.name, o)
    end

    -- 底部总进度条
    local by = iy + ih * 0.74
    local bw = iw - 8
    P:box(ix + 4, by, bw, 16, 0x14203A, 230, 8)
    local total = (o.data.gauge.a + o.data.gauge.b + o.data.gauge.c) / 3
    local fw = bw * fx.clamp(total, 0, 1)
    P:box(ix + 4, by, fw, 16, T.c.cyan, 235, 8)
    P:dot(ix + 4 + fw, by + 8, 12, T.c.cyan, 55)
    P:dot(ix + 4 + fw, by + 8, 5, 0xFFFFFF, 200)

    put(o.pgt, string.format("批次总进度 %d%%", math.floor(total * 100)), o)
end

-- ==================== 4 KPI 指标组 ====================
--[[
2x2 大数字 + 单位 + 同比小箭头 + 迷你火花线。
数字用 label（字库渲染），趋势线用 shape，两者叠在一张卡里。
]]
local function draw_kpi(o, P, r, t, dt)
    local ix, iy, iw, ih = content(r.x, r.y, r.w, r.h)
    local cw, chh = iw / 2, ih / 2

    local items = {
        { v = o.data.kpi.oee,    unit = "%",    col = T.c.cyan,   up = true },
        { v = o.data.kpi.output, unit = "pcs",  col = T.c.green,  up = true },
        { v = o.data.kpi.yield,  unit = "%",    col = T.c.lime,   up = false },
        { v = o.data.kpi.cycle,  unit = "s",    col = T.c.amber,  up = false },
    }

    for i = 1, 4 do
        local it = items[i]
        local c = (i - 1) % 2
        local rr = math.floor((i - 1) / 2)
        local x = ix + c * cw
        local y = iy + rr * chh

        -- 分隔线
        if c == 1 then
            P:line(x, y + 6, x, y + chh - 6, 0x1B2B44, 1, 140, false)
        end
        if rr == 1 then
            P:line(x + 6, y, x + cw - 6, y, 0x1B2B44, 1, 140, false)
        end

        -- 涨跌小三角
        local tri = it.up and 1 or -1
        local tx, ty = x + cw - 34, y + 16
        local tc = it.up and T.c.green or T.c.red
        P:line(tx, ty + tri * -4, tx - 5, ty + tri * 4, tc, 2, 235, true)
        P:line(tx, ty + tri * -4, tx + 5, ty + tri * 4, tc, 2, 235, true)

        -- 迷你火花线
        local sx, sw = x + 10, cw - 56
        local sy, sh = y + chh - 22, 14
        local vals = o.data.spark[((i - 1) % 4) + 1]
        local NP = 10
        local xs, ys = P._kx, P._ky
        if not xs then
            xs, ys = {}, {}
            P._kx, P._ky = xs, ys
        end
        for k = 1, NP do
            local src = math.floor((k - 1) * (#vals - 1) / (NP - 1)) + 1
            xs[k] = sx + sw * (k - 1) / (NP - 1)
            ys[k] = sy + sh * (1 - fx.clamp(vals[src] or 0, 0, 1))
        end
        P:poly(xs, ys, NP, it.col, 2, 220, true)

        put(o.kv[i], string.format("%.1f", it.v), o)
        put(o.ku[i], it.unit, o)
    end
end

-- ==================== 5 工艺步骤 ====================
--[[
五道工序横向排布：已完成的用实线连起来、当前工序高亮呼吸、未到的压暗。
每道工序下方一个进度细条。
]]
local function draw_step(o, P, r, t, dt)
    local ix, iy, iw, ih = content(r.x, r.y, r.w, r.h)
    local n = 5
    local step = iw / (n - 1)
    local y = iy + ih * 0.34
    local cur = 3          -- 当前工序序号（1..n）

    -- 连接线（已完成段亮、未完成段暗）
    P:line(ix, y, ix + iw, y, 0x1B2B44, 3, 220, true)
    local done_x = ix + step * (cur - 1)
    P:line(ix, y, done_x, y, T.c.cyan, 3, 255, true)

    for i = 1, n do
        local x = ix + step * (i - 1)
        local done = (i < cur)
        local now = (i == cur)
        local col = done and T.c.green or (now and T.c.cyan or T.c.dim2)

        if now then
            local br = 5 + 3 * (0.5 + 0.5 * math.sin(t * 3))
            P:dot(x, y, 18 + br, col, 60)
            P:ring(x, y, 14, col, 2, 200)
            P:dot(x, y, 8, col, 255)
        else
            P:dot(x, y, 12, 0x101A2E, 255)
            P:ring(x, y, 12, col, 2, done and 235 or 150)
            if done then
                P:dot(x, y, 5, col, 255)
            end
        end

        -- 步骤进度条
        local bw = step * 0.52
        local bx = x - bw / 2
        local frac = done and 1 or (now and 0.62 or 0)
        P:box(bx, y + 30, bw, 5, 0x1B2B44, 220, 2)
        if frac > 0 then
            P:box(bx, y + 30, bw * frac, 5, col, 235, 2)
        end

        put(o.st[i], string.format("S%d", i), o)
    end

    put(o.stt, string.format("当前工序 S%d  完成 %d/%d", cur, cur - 1, n), o)
end

-- ==================== 6 事件时间轴 ====================
--[[
竖向时间轴：左侧时间轴线 + 节点光点 + 右侧事件文字。
最新事件在最上面，节点做大光晕。
]]
local function draw_timeline(o, P, r, t, dt)
    local ix, iy, iw, ih = content(r.x, r.y, r.w, r.h)
    local rows = 5
    local rh = math.floor((ih - 4) / rows)
    local ax = ix + 22

    -- 轴线
    P:line(ax, iy + 8, ax, iy + ih - 12, 0x1B2B44, 2, 180, true)

    local cols = { T.c.cyan, T.c.green, T.c.amber, T.c.violet, T.c.dim }
    for i = 1, rows do
        local y = iy + 8 + (i - 1) * rh + rh * 0.32
        local col = cols[i]

        if i == 1 then
            local br = 4 + 2 * (0.5 + 0.5 * math.sin(t * 2.6))
            P:dot(ax, y, 14 + br, col, 55)
        end
        P:dot(ax, y, 10, 0x101A2E, 255)
        P:ring(ax, y, 8, col, 2, i == 1 and 255 or 190)
        P:dot(ax, y, 3, col, 255)

        -- 引导虚线到文字
        P:dash(ax + 12, y, ax + 30, y, col, 1, 120, 3, 3)

        put(o.tl[i], string.format("%02d:%02d  事件 %d", 8 + i, 12 + i * 7, i), o)
        put(o.tlt[i], i == 1 and "NOW" or string.format("-%dm", (i - 1) * 6), o)
    end
end

local DRAW = { draw_device, draw_alarm, draw_progress, draw_kpi, draw_step, draw_timeline }

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

    -- 1 设备格名
    local r1 = rects[1]
    local ix, iy, iw, ih = content(r1.x, r1.y, r1.w, r1.h)
    local cw, chh = iw / 3, ih / 4
    o.dev = {}
    for i = 1, 12 do
        local c = (i - 1) % 3
        local rr = math.floor((i - 1) / 3)
        o.dev[i] = airui.label({
            parent = parent,
            x = ix + c * cw, y = iy + rr * chh + 28,
            w = cw, h = 16, text = "--", font_size = T.f.mini,
            color = T.c.dim, align = airui.TEXT_ALIGN_CENTER,
        })
    end

    -- 状态图例：色点由 draw_device 画，文字在这里建（与色点同 x 基准）
    local LEGEND = { "运行", "待机", "告警", "离线" }
    o.lg = {}
    for i = 1, 4 do
        o.lg[i] = airui.label({
            parent = parent,
            x = ix + (i - 1) * (iw / 4) + 16, y = iy + ih - 13,
            w = iw / 4 - 16, h = 16, text = LEGEND[i], font_size = T.f.mini,
            color = T.c.dim, align = airui.TEXT_ALIGN_LEFT,
        })
    end

    -- 2 告警
    local r2 = rects[2]
    ix, iy, iw, ih = content(r2.x, r2.y, r2.w, r2.h)
    local rh = math.floor((ih - 4) / 5)
    o.al, o.alt = {}, {}
    for i = 1, 5 do
        o.al[i] = airui.label({
            parent = parent, x = ix + 30, y = iy + 2 + (i - 1) * rh + 6,
            w = iw - 82, h = 18, text = "--", font_size = T.f.mini,
            color = T.c.txt, align = airui.TEXT_ALIGN_LEFT,
        })
        o.alt[i] = airui.label({
            parent = parent, x = ix + iw - 52, y = iy + 2 + (i - 1) * rh + 6,
            w = 48, h = 18, text = "", font_size = T.f.mini,
            color = T.c.dim2, align = airui.TEXT_ALIGN_RIGHT,
        })
    end

    -- 3 进度环
    local r3 = rects[3]
    ix, iy, iw, ih = content(r3.x, r3.y, r3.w, r3.h)
    o.pg, o.pgn = {}, {}
    for i = 1, 3 do
        local cx = ix + iw * (i * 2 - 1) / 6
        o.pg[i] = airui.label({
            parent = parent, x = cx - 44, y = iy + ih * 0.38 - 11,
            w = 88, h = 22, text = "--", font_size = T.f.text,
            color = T.c.txt, align = airui.TEXT_ALIGN_CENTER,
        })
        o.pgn[i] = airui.label({
            parent = parent, x = cx - 50, y = iy + ih * 0.38 + 34,
            w = 100, h = 18, text = "", font_size = T.f.mini,
            color = T.c.dim2, align = airui.TEXT_ALIGN_CENTER,
        })
    end
    o.pgt = airui.label({
        parent = parent, x = ix, y = iy + ih * 0.74 + 22,
        w = iw, h = 20, text = "", font_size = T.f.mini,
        color = T.c.dim, align = airui.TEXT_ALIGN_CENTER,
    })

    -- 4 KPI
    local r4 = rects[4]
    ix, iy, iw, ih = content(r4.x, r4.y, r4.w, r4.h)
    local kcw, kch = iw / 2, ih / 2
    o.kv, o.ku = {}, {}
    for i = 1, 4 do
        local c = (i - 1) % 2
        local rr = math.floor((i - 1) / 2)
        local x = ix + c * kcw
        local y = iy + rr * kch
        o.kv[i] = airui.label({
            parent = parent, x = x + 10, y = y + 12,
            w = kcw - 70, h = 32, text = "--", font_size = T.f.body,
            color = T.c.txt, align = airui.TEXT_ALIGN_LEFT,
        })
        o.ku[i] = airui.label({
            parent = parent, x = x + 10, y = y + 42,
            w = kcw - 70, h = 18, text = "", font_size = T.f.mini,
            color = T.c.dim2, align = airui.TEXT_ALIGN_LEFT,
        })
    end

    -- 5 步骤
    local r5 = rects[5]
    ix, iy, iw, ih = content(r5.x, r5.y, r5.w, r5.h)
    local step = iw / 4
    o.st = {}
    for i = 1, 5 do
        o.st[i] = airui.label({
            parent = parent, x = ix + step * (i - 1) - 30, y = iy + ih * 0.34 + 12,
            w = 60, h = 18, text = "--", font_size = T.f.mini,
            color = T.c.dim, align = airui.TEXT_ALIGN_CENTER,
        })
    end
    o.stt = airui.label({
        parent = parent, x = ix, y = iy + ih - 22,
        w = iw, h = 20, text = "", font_size = T.f.mini,
        color = T.c.dim, align = airui.TEXT_ALIGN_CENTER,
    })

    -- 6 时间轴
    local r6 = rects[6]
    ix, iy, iw, ih = content(r6.x, r6.y, r6.w, r6.h)
    local trh = math.floor((ih - 4) / 5)
    o.tl, o.tlt = {}, {}
    for i = 1, 5 do
        local y = iy + 8 + (i - 1) * trh
        o.tl[i] = airui.label({
            parent = parent, x = ix + 40, y = y + 4,
            w = iw - 92, h = 18, text = "--", font_size = T.f.mini,
            color = T.c.txt, align = airui.TEXT_ALIGN_LEFT,
        })
        o.tlt[i] = airui.label({
            parent = parent, x = ix + iw - 52, y = y + 4,
            w = 48, h = 18, text = "", font_size = T.f.mini,
            color = T.c.dim2, align = airui.TEXT_ALIGN_RIGHT,
        })
    end

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
