--[[
@module  page_alarms
@summary 华康无菌车间 - 第 4 页 事件（完整事件表 / 筛选 / 统计 / 确认）
@version 1.0
@date    2026.11.11

这一页回答"刚才发生了什么，还有谁没确认"。
总览页只放 6 条未确认，漏掉的前因后果在这里补齐：一屏 10 行，
时间 / 等级 / 内容 / 状态四列对齐，未确认行左侧留一条琥珀竖条。
筛选默认"未确认"，交班时从上往下点确认，点完这一屏空了就交班。

=== 局部几何 ===
  事件表   x  12, y 0, 780x444
  统计卡   x 800, y 0, 212x244
  操作卡   x 800, y 252, 212x192
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
    filter = 1,          -- 0 全部 / 1 未确认 / 2 仅报警；默认未确认，交班时从上往下点
    tList = 0, tStat = 0, tText = 0,
}
M.o = o

local fmt, floor = string.format, math.floor

local function new_shape(parent, w, h)
    return airui.shape({ parent = parent, x = 0, y = 0, w = w, h = h })
end

local TBL = { x = 12,  y = 0,   w = 780, h = 444 }
local STT = { x = 800, y = 0,   w = 212, h = 244 }
local ACT = { x = 800, y = 252, w = 212, h = 192 }

local CHY = 38
local ROWY = 96
local ROWH = 34
local NROW = 10

local LV = { "提示", "提示", "警告", "报警" }
local LVCOL = { c.mint, c.mint, c.amber, c.alarm }

M.title, M.en = "事件", "EVENTS"
M.hint = "点事件行确认 · 点「全部确认」清空未确认 · 支持按等级筛选"

local FILTERS = { "全部", "未确认", "仅报警" }

-- ==================== 事件表 ====================
local function build_table(root)
    local card = kit.card(root, TBL, c.amber)
    kit.head(card, "运行事件", TBL.w)
    o.tblTag = kit.tag(card, TBL.w - 110, 10, 88, "0 条", c.dim2, 11)

    o.tblShape = new_shape(card, TBL.w, TBL.h)
    o.chipShape = new_shape(card, TBL.w, TBL.h)

    o.chip = {}
    for i, name in ipairs(FILTERS) do
        local x = 16 + (i - 1) * 104
        o.chip[i] = kit.text(card, x, CHY + 4, 96, 20, 12, c.dim, airui.TEXT_ALIGN_CENTER, name)
    end

    -- 列头
    kit.text(card, 16, 74, 56, 16, 10, c.dim2, airui.TEXT_ALIGN_LEFT, "时间")
    kit.text(card, 92, 74, 56, 16, 10, c.dim2, airui.TEXT_ALIGN_LEFT, "等级")
    kit.text(card, 152, 74, 400, 16, 10, c.dim2, airui.TEXT_ALIGN_LEFT, "内容")
    kit.text(card, 660, 74, 100, 16, 10, c.dim2, airui.TEXT_ALIGN_RIGHT, "状态")

    o.row = {}
    for i = 1, NROW do
        local y = ROWY + (i - 1) * ROWH
        local E = {}
        E.t = kit.text(card, 16, y + 7, 56, 20, 11, c.dim2, airui.TEXT_ALIGN_LEFT, "")
        E.lv = kit.text(card, 92, y + 7, 56, 20, 11, c.dim, airui.TEXT_ALIGN_LEFT, "")
        E.txt = kit.text(card, 152, y + 6, 480, 22, 12, c.dim, airui.TEXT_ALIGN_LEFT, "")
        E.st = kit.text(card, 660, y + 7, 100, 20, 10, c.dim2, airui.TEXT_ALIGN_RIGHT, "")
        o.row[i] = E
    end
end

-- 按当前筛选取前 10 条，同时记住它们在 data.events 里的下标（确认要下标）
local function pick()
    local list, idx = {}, {}
    for k, ev in ipairs(data.events) do
        local keep = (o.filter == 0)
                     or (o.filter == 1 and not ev.acked)
                     or (o.filter == 2 and ev.level >= 3)
        if keep then
            list[#list + 1] = ev
            idx[#idx + 1] = k
            if #list >= NROW then break end
        end
    end
    return list, idx
end

local function draw_table()
    local list, idx = pick()
    o.rowIdx = idx
    o.rowEv = list

    P:reset()
    for i = 1, NROW do
        local y = ROWY + (i - 1) * ROWH
        local ev = list[i]
        if ev then
            if not ev.acked then
                P:box(16, y + 2, 3, ROWH - 8, c.amber, 200, 1)
            end
            if i < NROW then
                P:line(16, y + ROWH, TBL.w - 16, y + ROWH, c.line, 1, 70)
            end
        end
    end
    o.tblShape:set_items(P:finish())

    -- 筛选胶囊
    P:reset()
    for i = 1, 3 do
        local x = 16 + (i - 1) * 104
        if o.filter == i - 1 then
            P:box(x, CHY, 96, 28, c.ice, 26, 5)
            P:frame(x, CHY, 96, 28, c.ice, 1, 110, 5)
        else
            P:frame(x, CHY, 96, 28, c.line, 1, 150, 5)
        end
    end
    o.chipShape:set_items(P:finish())

    for i = 1, 3 do
        kit.tint(o.chip[i], (o.filter == i - 1) and c.ice or c.dim, o, "fc" .. i)
    end

    for i = 1, NROW do
        local E, ev = o.row[i], list[i]
        if ev then
            kit.put(E.t, ev.t, o, "rt" .. i)
            kit.put(E.lv, LV[ev.level] or "提示", o, "rl" .. i)
            kit.tint(E.lv, LVCOL[ev.level] or c.dim, o, "rlc" .. i)
            kit.put(E.txt, ev.text, o, "rx" .. i)
            kit.tint(E.txt, ev.acked and c.dim2 or (ev.level >= 3 and c.alarm or c.txt), o, "rxc" .. i)
            kit.put(E.st, ev.acked and "已确认" or "未确认", o, "rs" .. i)
            kit.tint(E.st, ev.acked and c.dim2 or c.amber, o, "rsc" .. i)
        else
            kit.put(E.t, "", o, "rt" .. i)
            kit.put(E.lv, "", o, "rl" .. i)
            kit.put(E.txt, i == 1 and "没有符合条件的事件" or "", o, "rx" .. i)
            kit.tint(E.txt, c.dim2, o, "rxc" .. i)
            kit.put(E.st, "", o, "rs" .. i)
        end
    end

    kit.put(o.tblTag, fmt("共 %d 条 / 保留 %d", #data.events, #list), o, "tt")
end

-- ==================== 统计 ====================
local function build_stat(root)
    local card = kit.card(root, STT, c.alarm)
    kit.head(card, "统计", STT.w)

    local items = { "报警", "警告", "提示", "未确认" }
    o.stVal = {}
    for i, name in ipairs(items) do
        local y = 38 + (i - 1) * 38
        kit.text(card, 12, y + 6, 100, 20, 12, c.dim, airui.TEXT_ALIGN_LEFT, name)
        o.stVal[i] = kit.text(card, 120, y + 3, 72, 28, 20, c.txt, airui.TEXT_ALIGN_RIGHT, "0")
    end
    o.stNote = kit.text(card, 12, 202, STT.w - 24, 32, 10, c.dim2, airui.TEXT_ALIGN_LEFT,
                        "计数范围：屏上保留的最近 24 条")
end

local function draw_stat()
    local n1, n2, n3 = 0, 0, 0
    for _, ev in ipairs(data.events) do
        if ev.level >= 3 then n1 = n1 + 1
        elseif ev.level == 2 then n2 = n2 + 1
        else n3 = n3 + 1 end
    end
    local un = data.unacked()

    kit.put(o.stVal[1], fmt("%d", n1), o, "q1")
    kit.put(o.stVal[2], fmt("%d", n2), o, "q2")
    kit.put(o.stVal[3], fmt("%d", n3), o, "q3")
    kit.put(o.stVal[4], fmt("%d", un), o, "q4")
    kit.tint(o.stVal[1], n1 > 0 and c.alarm or c.dim, o, "q1c")
    kit.tint(o.stVal[2], n2 > 0 and c.amber or c.dim, o, "q2c")
    kit.tint(o.stVal[4], un > 0 and c.amber or c.mint, o, "q4c")
end

-- ==================== 操作 ====================
local function build_act(root)
    local card = kit.card(root, ACT, c.mint)
    kit.head(card, "操作", ACT.w)
    o.btnShape = new_shape(card, ACT.w, ACT.h)
    o.btn = kit.text(card, 12, 44, ACT.w - 24, 52, 16, c.ink, airui.TEXT_ALIGN_CENTER, "全部确认")
    o.actNote = kit.text(card, 12, 108, ACT.w - 24, 72, 10, c.dim2, airui.TEXT_ALIGN_LEFT, "")
end

local function draw_act()
    local un = data.unacked()
    P:reset()
    P:box(12, 44, ACT.w - 24, 52, un > 0 and c.amber or c.line, un > 0 and 232 or 50, 6)
    o.btnShape:set_items(P:finish())

    kit.put(o.btn, un > 0 and fmt("全部确认 (%d)", un) or "已全部确认", o, "btn")
    kit.tint(o.btn, un > 0 and c.ink or c.dim2, o, "btnc")
    kit.put(o.actNote, "确认只做留痕，不改变房间状态。\n未确认事件在总览页也会出现。", o, "an")
end

-- ==================== 生命周期 ====================
function M.build(root)
    build_table(root)
    build_stat(root)
    build_act(root)
    M.enter()
end

function M.enter()
    draw_table()
    draw_stat()
    draw_act()
end

function M.update(dt, idle, now)
    o.now = now
    local ms = dt * 1000
    o.tList = o.tList + ms
    o.tStat = o.tStat + ms

    if o.tList >= 500 then o.tList = 0; draw_table() end
    if o.tStat >= 500 then o.tStat = 0; draw_stat(); draw_act() end
end

function M.on_touch(x, y)
    -- 筛选胶囊
    if y >= CHY and y < CHY + 28 then
        for i = 1, 3 do
            local cx = 16 + (i - 1) * 104
            if x >= cx and x < cx + 96 then
                o.filter = i - 1
                o.idle = 0
                draw_table()
                return true
            end
        end
    end

    -- 事件行
    if x >= TBL.x and x < TBL.x + TBL.w and y >= ROWY and y < ROWY + NROW * ROWH then
        local i = floor((y - ROWY) / ROWH) + 1
        local k = o.rowIdx and o.rowIdx[i]
        if k and data.events[k] and not data.events[k].acked then
            data.ack_event(k)
            o.idle = 0
            draw_table()
            draw_stat()
            draw_act()
        end
        return true
    end

    -- 全部确认（列表在筛选"未确认"时点完最明显）
    if x >= ACT.x + 12 and x < ACT.x + ACT.w - 12 and y >= 44 and y < 96 then
        data.ack_all()
        o.idle = 0
        draw_table()
        draw_stat()
        draw_act()
        return true
    end

    return false
end

return M

