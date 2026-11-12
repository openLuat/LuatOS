--[[
@module  page_overview
@summary 华康无菌车间 - 第 1 页 总览（KPI / 压差平面 / 待确认事件 / 今日概览）
@version 1.0
@date    2026.11.11

这一页回答"哪一间正在失守"，所以压差平面占了 2/3 的宽度：
房间块放大到能放下完整读数（压差 / 温湿度 / 粒子），门洞气流动画正常速度流动。
右下两条窄卡是补充：上面是最近 6 条未确认事件（点一下确认），
下面是今日超标次数、能耗、换气次数 —— 交接班时最先看这三个数。

=== 局部几何（内容区 1024x444，坐标相对页面容器）===
  KPI 条        y   0 .. 76
  平面卡        x  12, y  84, 664x360
  待确认事件    x 688, y  84, 324x212
  今日概览      x 688, y 304, 324x140
]]

local T = require "theme"
local fx = require "fx"
local kit = require "kit"
local data = require "room_data"

local M = {}

local c, f = T.c, T.f
local P = fx.pool()

local o = {
    now = 0, rot = 0,
    tPlan = 0, tEv = 0, tSum = 0, tText = 0,
    sel_t = 0, sel_i = 0,
    tx = {},
}
M.o = o

local fmt, floor = string.format, math.floor
local function f1(v) return fmt("%.1f", v) end
local function f0(v) return fmt("%d", floor(v + 0.5)) end

local function new_shape(parent, w, h)
    return airui.shape({ parent = parent, x = 0, y = 0, w = w, h = h })
end

local function hit(x, y, rx, ry, rw, rh)
    return x >= rx and x < rx + rw and y >= ry and y < ry + rh
end

--[[房间块（相对平面卡）。上排三间生产房、中间洁净走廊、下排人员物料进出区。
门的 x 是卡内绝对坐标，刻意错开，避免三条气流在走廊里挤成一片。]]
local R = {
    { x = 8,   y = 36,  w = 202, h = 142 },
    { x = 218, y = 36,  w = 240, h = 142 },
    { x = 466, y = 36,  w = 190, h = 142 },
    { x = 8,   y = 244, w = 194, h = 108 },
    { x = 210, y = 244, w = 446, h = 108 },
}
local COR = { x = 8, y = 184, w = 648, h = 54 }
local DOOR = { 150, 330, 560, 150, 420 }

local KPIY, KPIH = 0, 76
local PLN = { x = 12,  y = 84, w = 664, h = 360 }
local EVP = { x = 688, y = 84, w = 324, h = 212 }
local SUM = { x = 688, y = 304, w = 324, h = 140 }

M.title, M.en = "总览", "OVERVIEW"
M.hint = "点房间查看读数，再点同一间模拟开门 · 点事件行直接确认"

-- 大数用 k 缩写：D 级粒子能到 300 万，写全屏就炸了
local function pf(v)
    if v >= 10000 then return fmt("%.0fk", v / 1000) end
    return fmt("%.0f", v)
end

-- ==================== KPI ====================
local KPI_COL = { c.ice, c.amber, c.cyan, c.mint }

local function build_kpi(root)
    local items = {
        { "最低压差", "Pa"  },
        { "平均温度", "C"   },
        { "平均湿度", "%RH" },
        { "环境达标率", "%" },
    }
    o.kpi = {}
    local x = T.kpi.x
    for i, it in ipairs(items) do
        local card = kit.card(root, { x = x, y = KPIY, w = T.kpi.w, h = KPIH }, KPI_COL[i])
        kit.text(card, 12, 6, 160, 16, 11, c.dim2, airui.TEXT_ALIGN_LEFT, it[1])
        local E = {}
        E.val = kit.text(card, 12, 17, 170, 34, 28, c.txt, airui.TEXT_ALIGN_LEFT, "0")
        E.unit = kit.text(card, 12, 50, 40, 12, 10, c.dim2, airui.TEXT_ALIGN_LEFT, it[2])
        E.bar = new_shape(card, T.kpi.w, KPIH)
        o.kpi[i] = E
        x = x + T.kpi.w + T.kpi.gap
    end
end

local function draw_kpi()
    local s = data.state
    local vals = { s.min_dp, s.avg_t, s.avg_rh, s.ok_pct }
    local fr = {
        fx.clamp(s.min_dp / 20, 0, 1),
        fx.clamp((s.avg_t - 16) / 12, 0, 1),
        fx.clamp(s.avg_rh / 100, 0, 1),
        fx.clamp(s.ok_pct / 100, 0, 1),
    }
    for i = 1, 4 do
        local E = o.kpi[i]
        kit.put(E.val, (i == 1 or i == 2) and f1(vals[i]) or f0(vals[i]), o, "kv" .. i)
        P:reset()
        kit.meter(P, 12, KPIH - 12, T.kpi.w - 24, 5, fr[i], KPI_COL[i])
        E.bar:set_items(P:finish())
    end
end

-- ==================== 平面 ====================
local function build_plan(root)
    local card = kit.card(root, PLN, c.ice)
    kit.head(card, "洁净区平面 / 压差梯度", PLN.w)
    o.planSum = kit.text(card, PLN.w - 300, 10, 276, 20, 12, c.dim, airui.TEXT_ALIGN_RIGHT, "")

    o.planShape = new_shape(card, PLN.w, PLN.h)

    o.room = {}
    for i = 1, 5 do
        local g = R[i]
        local E = {}
        local high = g.h >= 140
        E.name = kit.text(card, g.x + 12, g.y + (high and 8 or 6), g.w - 70,
                          high and 22 or 20, high and 18 or 16, c.txt, airui.TEXT_ALIGN_LEFT, "")
        E.grade = kit.tag(card, g.x + g.w - 58, g.y + (high and 10 or 8), 46, "", c.ice, 11)
        E.dp = kit.text(card, g.x + 12, g.y + (high and 32 or 26), 100,
                        high and 42 or 34, high and 30 or 26, c.ice, airui.TEXT_ALIGN_LEFT, "")
        E.unit = kit.text(card, g.x + (high and 104 or 88), g.y + (high and 48 or 38),
                          28, 18, 12, c.dim2, airui.TEXT_ALIGN_LEFT, "Pa")
        E.th = kit.text(card, g.x + 12, g.y + (high and 78 or 62), g.w - 24, 18,
                        high and 13 or 12, c.dim, airui.TEXT_ALIGN_LEFT, "")
        E.part = kit.text(card, g.x + 12, g.y + (high and 98 or 78), g.w - 24, 16,
                          high and 11 or 10, c.dim2, airui.TEXT_ALIGN_LEFT, "")
        o.room[i] = E
    end

    o.corName = kit.text(card, COR.x + 14, COR.y + 8, 300, 20, 14, c.dim, airui.TEXT_ALIGN_LEFT,
                         "洁净走廊  CNC")
    o.corDp = kit.text(card, COR.x + 220, COR.y + 5, 120, 24, 17, c.ice, airui.TEXT_ALIGN_LEFT, "")
    o.corNote = kit.text(card, COR.x + 348, COR.y + 9, 292, 20, 11, c.dim2, airui.TEXT_ALIGN_LEFT,
                         "送风 8600 m3/h   回风 78%   门禁 正常")
end

local function draw_plan()
    P:reset()

    -- 走廊比房间暗一档：读起来是"公共空间"，而不是又一间房
    P:box(COR.x, COR.y, COR.w, COR.h, c.panel2, 255, 4)
    P:frame(COR.x, COR.y, COR.w, COR.h, c.line, 1, 200, 4)

    for i = 1, 5 do
        local r, g = data.rooms[i], R[i]
        local sel = (data.sel == i)
        local base = r.over and c.alarm or (r.iso and c.violet or c.ice)
        P:box(g.x, g.y, g.w, g.h, base, sel and 20 or 12, 6)
        P:frame(g.x, g.y, g.w, g.h, sel and c.ice or c.line, sel and 2 or 1,
                sel and 220 or 170, 6)

        -- 门洞 + 气流：只走 18 像素，不穿过走廊中线，走廊里的文字才留得住
        local dx, up = DOOR[i], (i <= 3)
        local dy = up and (g.y + g.h) or g.y
        local dir = up and 1 or -1
        local flow = r.over and c.alarm or c.ice
        fx.door(P, dx, dy, flow, 170)
        fx.airflow(P, dx, dy, dir, 18, (o.now * 0.8 + i * 0.17) % 1, flow, 130)

        -- 粒子条按"本级别限值的比例"画：A 级 3520 与 D 级 352 万才可比
        local frac = r.p05 / r.lim05
        local mh = (g.h >= 140) and 6 or 5
        kit.meter(P, g.x + 12, g.y + g.h - 18, g.w - 24, mh, frac, kit.part_color(frac))

        if sel then kit.brackets(P, g.x, g.y, g.w, g.h, c.ice, 200, 12) end
    end

    o.planShape:set_items(P:finish())

    for i = 1, 5 do
        local r, E = data.rooms[i], o.room[i]
        kit.put(E.name, r.name, o, "rn" .. i)
        kit.put(E.grade, r.grade, o, "rg" .. i)
        kit.tint(E.grade, r.over and c.alarm or c.ice, o, "rgc" .. i)
        kit.put(E.dp, f1(r.dp), o, "rd" .. i)
        kit.tint(E.dp, kit.dp_color(r.dp), o, "rdc" .. i)
        -- 湿度是浮点：Lua 5.3 的 %d 拒绝带小数的数，这里用 %.0f
        kit.put(E.th, fmt("%.1fC  %.0f%%RH", r.t, r.rh), o, "rt" .. i)
        kit.put(E.part, fmt("P0.5 %s  P5 %s", pf(r.p05), f0(r.p5)), o, "rp" .. i)
    end

    kit.put(o.corDp, "0.0 Pa", o, "cd")
    local r = data.rooms[data.sel]
    kit.put(o.planSum, fmt("%s  %s  %.1fPa  %.1fC", r.name, r.grade, r.dp, r.t), o, "ps")
end

-- ==================== 待确认事件 ====================
local EV_COL = { c.mint, c.mint, c.amber, c.alarm }   -- level 1..3

local function build_ev(root)
    local card = kit.card(root, EVP, c.amber)
    kit.head(card, "待确认事件", EVP.w)
    o.evTag = kit.tag(card, EVP.w - 96, 10, 76, "0 条", c.amber, 12)
    o.evShape = new_shape(card, EVP.w, EVP.h)

    o.evRow = {}
    for i = 1, 6 do
        local y = 36 + (i - 1) * 28
        local E = {}
        E.t = kit.text(card, 8, y + 4, 40, 20, 11, c.dim2, airui.TEXT_ALIGN_LEFT, "")
        E.txt = kit.text(card, 52, y + 3, 190, 22, 12, c.dim, airui.TEXT_ALIGN_LEFT, "")
        E.st = kit.text(card, 246, y + 4, 70, 20, 10, c.dim2, airui.TEXT_ALIGN_RIGHT, "")
        o.evRow[i] = E
    end
end

local function draw_ev()
    local rows, idx = {}, {}
    for k, ev in ipairs(data.events) do
        if not ev.acked then
            rows[#rows + 1] = ev
            idx[#idx + 1] = k
            if #rows >= 6 then break end
        end
    end
    o.evIdx = idx

    P:reset()
    for i = 1, 6 do
        local y = 36 + (i - 1) * 28
        local ev = rows[i]
        if ev then
            P:box(8, y + 6, 2, 16, EV_COL[ev.level] or c.dim, 200, 1)
            if i < 6 then P:line(8, y + 28, EVP.w - 8, y + 28, c.line, 1, 80) end
        end
    end
    o.evShape:set_items(P:finish())

    for i = 1, 6 do
        local E, ev = o.evRow[i], rows[i]
        if ev then
            kit.put(E.t, ev.t, o, "et" .. i)
            kit.put(E.txt, ev.text, o, "ex" .. i)
            kit.put(E.st, "未确认", o, "es" .. i)
            kit.tint(E.st, c.amber, o, "esc" .. i)
            kit.tint(E.txt, ev.level >= 3 and c.alarm or (ev.level == 2 and c.amber or c.dim), o, "exc" .. i)
        else
            kit.put(E.t, "", o, "et" .. i)
            kit.put(E.txt, "", o, "ex" .. i)
            kit.put(E.st, "", o, "es" .. i)
        end
    end

    kit.put(o.evTag, fmt("%d 条", #rows), o, "evn")
end

-- ==================== 今日概览 ====================
local function build_sum(root)
    local card = kit.card(root, SUM, c.mint)
    kit.head(card, "今日概览", SUM.w)

    local xs = { 12, 118, 224 }
    local titles = { "超标次数", "累计能耗", "平均换气" }
    o.sumVal = {}
    for i = 1, 3 do
        kit.text(card, xs[i], 34, 92, 14, 10, c.dim2, airui.TEXT_ALIGN_LEFT, titles[i])
        o.sumVal[i] = kit.text(card, xs[i], 48, 96, 36, 24, c.txt, airui.TEXT_ALIGN_LEFT, "0")
    end
    o.sumNote = kit.text(card, 12, 100, 300, 18, 11, c.dim, airui.TEXT_ALIGN_LEFT, "")
end

local function draw_sum()
    local s = data.state
    kit.put(o.sumVal[1], fmt("%d 次", floor(s.over + 0.5)), o, "s1")
    kit.put(o.sumVal[2], f1(s.energy), o, "s2")
    kit.put(o.sumVal[3], fmt("%d", floor(s.ach + 0.5)), o, "s3")
    kit.tint(o.sumVal[1], s.over > 0 and c.alarm or c.mint, o, "s1c")
    kit.put(o.sumNote, fmt("达标率 %.1f%%   ·   %.1fC / %.0f%%RH", s.ok_pct, s.avg_t, s.avg_rh),
            o, "sn")
end

-- ==================== 生命周期 ====================
function M.build(root)
    build_kpi(root)
    build_plan(root)
    build_ev(root)
    build_sum(root)
    M.enter()
end

function M.enter()
    draw_kpi()
    draw_plan()
    draw_ev()
    draw_sum()
end

function M.update(dt, idle, now)
    o.idle, o.now = idle, now
    local ms = dt * 1000
    o.tText = o.tText + ms
    o.tPlan = o.tPlan + ms
    o.tEv = o.tEv + ms
    o.tSum = o.tSum + ms

    if o.tPlan >= T.perf.plan_ms then o.tPlan = 0; draw_plan() end
    if o.tEv >= 500 then o.tEv = 0; draw_ev() end
    if o.tSum >= 700 then o.tSum = 0; draw_sum() end
    if o.tText >= T.perf.text_ms then o.tText = 0; draw_kpi() end

    -- 15 秒没人碰：房间选择自己往下走。挂在走廊墙上的屏总得有点东西在动，
    -- 但节拍要慢（12 秒一格），否则值班的人会觉得屏幕在抖。
    if idle >= T.perf.auto_sec and (now - o.rot) >= 12 then
        o.rot = now
        data.sel = data.sel % 5 + 1
        draw_plan()
    end
end

function M.on_touch(x, y)
    -- 房间块：点一次选中，4 秒内再点同一间 = 模拟开门
    local px, py = x - PLN.x, y - PLN.y
    for i = 1, 5 do
        local g = R[i]
        if px >= g.x and px < g.x + g.w and py >= g.y and py < g.y + g.h then
            if data.sel == i and o.sel_i == i and (o.now - o.sel_t) < 4 then
                data.open_door(i)
            else
                data.sel = i
                o.sel_t, o.sel_i = o.now, i
            end
            o.idle = 0
            draw_plan()
            return true
        end
    end

    -- 待确认事件：点行确认（已确认的不在列表里）
    local ex, ey = x - EVP.x, y - EVP.y
    if ex >= 0 and ex < EVP.w and ey >= 36 and ey < EVP.h then
        local k = o.evIdx and o.evIdx[floor((ey - 36) / 28) + 1]
        if k then
            data.ack_event(k)
            o.idle = 0
            draw_ev()
            return true
        end
    end

    return false
end

return M

