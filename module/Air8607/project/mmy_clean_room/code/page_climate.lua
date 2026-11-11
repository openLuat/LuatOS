--[[
@module  page_climate
@summary 华康无菌车间 - 第 2 页 气候（监测点 / 24h 温湿度曲线 / 三张读数卡）
@version 1.0
@date    2026.11.11

这一页回答"是刚掉下来，还是一直在往下走"。
单屏时趋势只有 230 像素宽，看不出趋势；这页把图放大到 672x180 双道：
上道温度、下道湿度，合规带做底，末端一个呼吸光点提示"这是现在"。
左侧五个监测点常驻，点一下整页跟着换，不必回总览再点房间。

=== 局部几何 ===
  监测点列表   x  12, y 0, 224x444
  趋势卡       x 248, y 0, 764x296
  读数卡 1..3  x 248 / 506 / 764, y 304, 248x140
]]

local T = require "theme"
local fx = require "fx"
local kit = require "kit"
local data = require "room_data"

local M = {}

local c, f = T.c, T.f
local P = fx.pool()

local o = {
    now = 0,
    tTr = 0, tList = 0, tStat = 0,
    tx = {},
}
M.o = o

local fmt, floor = string.format, math.floor
local function f1(v) return fmt("%.1f", v) end

local function new_shape(parent, w, h)
    return airui.shape({ parent = parent, x = 0, y = 0, w = w, h = h })
end

local LIST = { x = 12,  y = 0, w = 224, h = 444 }
local TRC  = { x = 248, y = 0, w = 764, h = 296 }
local STC  = { x = 248, y = 304, w = 248, h = 140 }
local ROWH = 72
local ROWY = 42

-- 图区：温度 16..28C、湿度 40..70%RH，两条带子之间留 12px 给刻度
local TR = { x = 56, w = 672, ty = 52, th = 84, hy = 148, hh = 84 }
local TMIN, TMAX = 16, 28
local HMIN, HMAX = 40, 70

M.title, M.en = "气候", "CLIMATE"
M.hint = "点左侧监测点切换曲线 · 曲线末端光点是当前值"

-- ==================== 监测点列表 ====================
local function build_list(root)
    local card = kit.card(root, LIST, c.amber)
    kit.head(card, "监测点 / 5", LIST.w)
    o.listShape = new_shape(card, LIST.w, LIST.h)

    o.row = {}
    for i = 1, 5 do
        local y = ROWY + (i - 1) * ROWH
        local E = {}
        E.name = kit.text(card, 12, y + 8, 140, 22, 16, c.txt, airui.TEXT_ALIGN_LEFT, "")
        E.grade = kit.tag(card, LIST.w - 52, y + 10, 40, "", c.ice, 11)
        E.dp = kit.text(card, 12, y + 32, 120, 18, 13, c.ice, airui.TEXT_ALIGN_LEFT, "")
        E.th = kit.text(card, 12, y + 50, 180, 16, 11, c.dim2, airui.TEXT_ALIGN_LEFT, "")
        o.row[i] = E
    end
end

local function draw_list()
    P:reset()
    for i = 1, 5 do
        local r = data.rooms[i]
        local y = ROWY + (i - 1) * ROWH
        local sel = (data.sel == i)
        if sel then
            P:box(8, y - 2, LIST.w - 16, ROWH - 6, c.ice, 20, 6)
            P:box(8, y + 6, 3, ROWH - 22, c.ice, 220, 2)
        end
        if i < 5 then
            P:line(12, y + ROWH - 10, LIST.w - 12, y + ROWH - 10, c.line, 1, 90)
        end
        -- 状态点：越限红、隔离紫、正常薄荷，放在行尾
        local col = r.over and c.alarm or (r.iso and c.violet or c.mint)
        P:dot(LIST.w - 18, y + 20, 4, col, 220)
    end
    o.listShape:set_items(P:finish())

    for i = 1, 5 do
        local r, E = data.rooms[i], o.row[i]
        kit.put(E.name, r.name, o, "ln" .. i)
        kit.tint(E.name, (data.sel == i) and c.txt or c.dim, o, "lnc" .. i)
        kit.put(E.grade, r.grade, o, "lg" .. i)
        kit.put(E.dp, fmt("%.1f Pa", r.dp), o, "ld" .. i)
        kit.tint(E.dp, kit.dp_color(r.dp), o, "ldc" .. i)
        kit.put(E.th, fmt("%.1fC  %.0f%%RH  %d 次/h", r.t, r.rh, r.ach), o, "lt" .. i)
    end
end

-- ==================== 趋势 ====================
local function build_trend(root)
    local card = kit.card(root, TRC, c.cyan)
    kit.head(card, "24 小时温湿度趋势", TRC.w)
    o.trName = kit.tag(card, TRC.w - 300, 10, 140, "", c.ice, 12)
    o.trNow = kit.tag(card, TRC.w - 150, 10, 138, "", c.dim, 11)

    o.trShape = new_shape(card, TRC.w, TRC.h)

    -- Y 轴刻度是固定量程，位置和值都不变，建一次就够，别放进每帧预算
    local ty = { TMAX, (TMIN + TMAX) / 2, TMIN }
    for i = 1, 3 do
        local y = TR.ty + (i - 1) * TR.th / 2 - 8
        kit.text(card, 8, y, 44, 16, 10, c.dim2, airui.TEXT_ALIGN_RIGHT, fmt("%.0f", ty[i]))
    end
    local hy = { HMAX, (HMIN + HMAX) / 2, HMIN }
    for i = 1, 3 do
        local y = TR.hy + (i - 1) * TR.hh / 2 - 8
        kit.text(card, 8, y, 44, 16, 10, c.dim2, airui.TEXT_ALIGN_RIGHT, fmt("%.0f", hy[i]))
    end

    -- X 轴在两条带子之下（不是温度带之下），否则会盖住湿度曲线
    local xt = { "-24h", "-18h", "-12h", "-6h", "现在" }
    for i = 1, 5 do
        local x = TR.x + (i - 1) * TR.w / 4
        local w = 56
        local lx = x - w / 2
        if lx < 4 then lx = 4 end
        if lx + w > TRC.w - 4 then lx = TRC.w - w - 4 end
        kit.text(card, lx, TR.hy + TR.hh + 8, w, 14, 10, c.dim2,
                 airui.TEXT_ALIGN_CENTER, xt[i])
    end

    o.trFoot = kit.text(card, 56, TRC.h - 28, 520, 18, 11, c.dim2, airui.TEXT_ALIGN_LEFT,
                        "合规带：温度 18~26C   湿度 45~60%RH   采样 15 分钟")
end

local function ytemp(v)
    return TR.ty + TR.th - (v - TMIN) / (TMAX - TMIN) * TR.th
end

local function yhum(v)
    return TR.hy + TR.hh - (v - HMIN) / (HMAX - HMIN) * TR.hh
end

local function draw_trend()
    local r = data.rooms[data.sel]
    local h = r.hist
    local n = data.NPT

    P:reset()

    -- 合规带做底：曲线压着带子两侧走的时候，一眼就知道偏了
    local y1, y2 = ytemp(26), ytemp(18)
    P:box(TR.x, y1, TR.w, y2 - y1, c.mint, 12, 0)
    y1, y2 = yhum(60), yhum(45)
    P:box(TR.x, y1, TR.w, y2 - y1, c.mint, 12, 0)

    for i = 0, 2 do
        local ty = TR.ty + TR.th * i / 2
        local hyy = TR.hy + TR.hh * i / 2
        P:line(TR.x, ty, TR.x + TR.w, ty, c.line, 1, 70)
        P:line(TR.x, hyy, TR.x + TR.w, hyy, c.line, 1, 70)
    end
    for i = 0, 3 do
        local x = TR.x + TR.w * i / 4
        P:line(x, TR.ty, x, TR.ty + TR.th, c.line, 1, 44)
        P:line(x, TR.hy, x, TR.hy + TR.hh, c.line, 1, 44)
    end

    kit.line(P, h.t, n, TR.x, TR.ty, TR.w, TR.th, TMIN, TMAX, c.amber, 2, 220)
    kit.line(P, h.rh, n, TR.x, TR.hy, TR.w, TR.hh, HMIN, HMAX, c.cyan, 2, 220)

    -- 末端：一个会呼吸的光圈。曲线再密，也得让人一眼找到"现在"
    local xe = TR.x + TR.w - 1
    local yt = ytemp(h.t[n] or r.t)
    local yh = yhum(h.rh[n] or r.rh)
    local pulse = 6 + 3 * math.sin(o.now * 3)
    P:dash(TR.x, yt, xe, yt, c.amber, 1, 60, 4, 6)
    P:dash(TR.x, yh, xe, yh, c.cyan, 1, 60, 4, 6)
    P:dot(xe, yt, pulse, c.amber, 24)
    P:dot(xe, yt, 3, c.amber, 240)
    P:dot(xe, yh, pulse, c.cyan, 24)
    P:dot(xe, yh, 3, c.cyan, 240)

    o.trShape:set_items(P:finish())

    kit.put(o.trName, fmt("%s / %s", r.name, r.grade), o, "tn")
    kit.put(o.trNow, fmt("%.1fC   %.0f%%RH", r.t, r.rh), o, "tw")
end

-- ==================== 读数卡 ====================
local ST = {
    { title = "温度",  unit = "C",   col = c.amber },
    { title = "湿度",  unit = "%RH", col = c.cyan  },
    { title = "压差",  unit = "Pa",  col = c.ice   },
}

local function build_stat(root)
    o.st = {}
    for i = 1, 3 do
        local x = STC.x + (i - 1) * (STC.w + 10)
        local card = kit.card(root, { x = x, y = STC.y, w = STC.w, h = STC.h }, ST[i].col)
        kit.head(card, ST[i].title, STC.w)
        local E = {}
        E.val = kit.text(card, 12, 34, 150, 40, 30, c.txt, airui.TEXT_ALIGN_LEFT, "0")
        E.unit = kit.text(card, 12, 60, 40, 14, 11, c.dim2, airui.TEXT_ALIGN_LEFT, ST[i].unit)
        E.range = kit.text(card, 12, 78, STC.w - 24, 16, 11, c.dim2, airui.TEXT_ALIGN_LEFT, "")
        E.note = kit.text(card, 12, 100, STC.w - 24, 16, 11, c.dim, airui.TEXT_ALIGN_LEFT, "")
        E.bar = new_shape(card, STC.w, STC.h)
        o.st[i] = E
    end
end

local function range_of(arr, n)
    local lo, hi = 1e9, -1e9
    for i = 1, n do
        local v = arr[i]
        if v < lo then lo = v end
        if v > hi then hi = v end
    end
    if lo > hi then return 0, 0 end
    return lo, hi
end

local function draw_stat()
    local r = data.rooms[data.sel]
    local n = data.NPT
    local tlo, thi = range_of(r.hist.t, n)
    local rlo, rhi = range_of(r.hist.rh, n)
    local dlo, dhi = range_of(r.hist.dp, n)

    kit.put(o.st[1].val, f1(r.t), o, "v1")
    kit.put(o.st[2].val, fmt("%d", floor(r.rh + 0.5)), o, "v2")
    kit.put(o.st[3].val, f1(r.dp), o, "v3")

    kit.put(o.st[1].range, fmt("24h  %.1f ~ %.1f", tlo, thi), o, "a1")
    kit.put(o.st[2].range, fmt("24h  %.0f ~ %.0f", rlo, rhi), o, "a2")
    kit.put(o.st[3].range, fmt("24h  %.1f ~ %.1f", dlo, dhi), o, "a3")

    local tcol = kit.th_color(r.t, 18, 26, 2)
    local hcol = kit.th_color(r.rh, 45, 60, 5)
    local dcol = kit.dp_color(r.dp)
    kit.tint(o.st[1].val, tcol, o, "c1")
    kit.tint(o.st[2].val, hcol, o, "c2")
    kit.tint(o.st[3].val, dcol, o, "c3")

    kit.put(o.st[1].note, (r.t < 18 or r.t > 26) and "超出 18~26C 合规框" or "在 18~26C 合规框内", o, "n1")
    kit.tint(o.st[1].note, tcol, o, "n1c")
    kit.put(o.st[2].note, (r.rh < 45 or r.rh > 60) and "超出 45~60%RH 合规框" or "在 45~60%RH 合规框内", o, "n2")
    kit.tint(o.st[2].note, hcol, o, "n2c")
    kit.put(o.st[3].note, r.iso and "已挂牌隔离，停止送风"
                        or (r.door and "门开启中，压差正在掉" or "下限 10.0Pa（对走廊）"), o, "n3")
    kit.tint(o.st[3].note, r.iso and c.violet or (r.door and c.amber or c.dim2), o, "n3c")

    P:reset()
    kit.meter(P, 12, STC.h - 16, STC.w - 24, 6, fx.clamp((r.t - 16) / 12, 0, 1), tcol)
    o.st[1].bar:set_items(P:finish())
    P:reset()
    kit.meter(P, 12, STC.h - 16, STC.w - 24, 6, fx.clamp(r.rh / 100, 0, 1), hcol)
    o.st[2].bar:set_items(P:finish())
    P:reset()
    kit.meter(P, 12, STC.h - 16, STC.w - 24, 6, fx.clamp(r.dp / 25, 0, 1), dcol)
    o.st[3].bar:set_items(P:finish())
end

-- ==================== 生命周期 ====================
function M.build(root)
    build_list(root)
    build_trend(root)
    build_stat(root)
    M.enter()
end

function M.enter()
    draw_list()
    draw_trend()
    draw_stat()
end

function M.update(dt, idle, now)
    o.now = now
    local ms = dt * 1000
    o.tList = o.tList + ms
    o.tTr = o.tTr + ms
    o.tStat = o.tStat + ms

    if o.tList >= 500 then o.tList = 0; draw_list() end
    if o.tTr >= T.perf.trend_ms then o.tTr = 0; draw_trend() end
    if o.tStat >= 300 then o.tStat = 0; draw_stat() end
end

function M.on_touch(x, y)
    if x < LIST.x or x >= LIST.x + LIST.w then return false end
    local i = floor((y - ROWY) / ROWH) + 1
    if i >= 1 and i <= 5 and data.sel ~= i then
        data.sel = i
        o.idle = 0
        draw_list()
        draw_trend()
        draw_stat()
        return true
    end
    return false
end

return M

