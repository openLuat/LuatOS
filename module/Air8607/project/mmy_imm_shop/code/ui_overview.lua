--[[
@module  ui_overview
@summary 总览页：车间 KPI + 8 台机矩阵 + 实时报警流 + 状态分布
@version 1.0
@date    2026.11.10
]]
local conf  = require("conf")
local theme = require("theme")
local store = require("store")
local model = require("model")

local C = theme.C
local T = theme
local M = {}

local v = { cards = {}, alarms = {}, dist = {} }

-- 千分位
local function fmt_num(n)
    local s = tostring(math.floor(n or 0))
    if #s <= 3 then return s end
    local parts = {}
    while #s > 3 do
        table.insert(parts, 1, s:sub(-3))
        s = s:sub(1, -4)
    end
    table.insert(parts, 1, s)
    return table.concat(parts, ",")
end

local function state_of(m)
    return conf.state[m.state] or conf.state.stop
end

function M.build(parent)
    local page = airui.container({
        parent = parent, x = 0, y = 0, w = conf.W, h = conf.H, color = -1,
    })
    v.page = page
    M.root = page

    -- ==================== KPI ====================
    v.k_run   = T.kpi(page, 20, 84, 232, 88, "运行机台", "0/8", "台", C.green)
    v.k_alarm = T.kpi(page, 272, 84, 232, 88, "当前报警", "0", "台", C.red)
    v.k_out   = T.kpi(page, 524, 84, 232, 88, "今日产量", "0", "模", C.cyan)
    v.k_cyc   = T.kpi(page, 776, 84, 232, 88, "平均周期", "0.0", "s", C.amber)

    -- ==================== 机台矩阵 ====================
    local MW, MH, GAP = 161, 152, 12
    for i = 1, conf.machine.count do
        local col = (i - 1) % 4
        local row = math.floor((i - 1) / 4)
        local x = 20 + col * (MW + GAP)
        local y = 184 + row * (MH + GAP)
        local card = airui.container({
            parent = page, x = x, y = y, w = MW, h = MH,
            color = C.panel, radius = 12, border_color = C.line, border_width = 1,
            on_click = function()
                model.select(i)
                if M.on_pick then pcall(M.on_pick, i) end
            end,
        })
        local c = {}
        c.card = card
        c.dot = T.dot(card, 14, 18, 8, C.green)
        T.label(card, 28, 12, 90, 20, conf.machine_ids[i], 14, C.ink)
        c.badge, c.badge_box = T.badge(card, MW - 66, 12, 54, 20, "运行", C.green, 11)

        c.prod = T.label(card, 14, 40, MW - 28, 18, "", 12, C.ink2)
        c.order = T.label(card, 14, 58, MW - 28, 16, "", 10, C.ink3)

        c.bar = T.bar(card, 14, 82, MW - 28, 6, {
            max = 100, value = 0, indicator_color = C.green,
        })
        c.prog = T.label(card, 14, 92, MW - 28, 16, "", 10, C.ink3)

        c.shots = T.label(card, 14, 116, 78, 18, "", 12, C.ink2)
        c.cyc = T.label(card, MW - 92, 116, 78, 18, "", 12, C.ink3, T.TEXT_RIGHT)
        v.cards[i] = c
    end

    -- ==================== 实时报警流 ====================
    local ac = T.card(page, 712, 184, 292, 196, "实时报警")
    for i = 1, 5 do
        local y = 42 + (i - 1) * 30
        local r = {}
        r.dot = T.dot(ac, 14, y + 10, 8, C.red)
        r.text = T.label(ac, 28, y + 2, 196, 18, "", 11, C.ink2)
        r.time = T.label(ac, 216, y + 3, 60, 16, "", 10, C.ink3, T.TEXT_RIGHT)
        v.alarms[i] = r
    end

    -- ==================== 状态分布 ====================
    local dc = T.card(page, 712, 392, 292, 196, "设备状态分布")
    local order = { "run", "idle", "alarm", "setup", "stop" }
    for i, key in ipairs(order) do
        local y = 40 + (i - 1) * 28
        local st = conf.state[key]
        local r = { key = key }
        T.dot(dc, 18, y + 6, 10, st.color)
        T.label(dc, 36, y + 2, 96, 18, st.name, 12, C.ink2)
        r.bar = T.bar(dc, 140, y + 8, 92, 6, {
            max = conf.machine.count, value = 0, indicator_color = st.color,
        })
        r.cnt = T.label(dc, 240, y + 2, 36, 18, "0", 12, C.ink, T.TEXT_RIGHT)
        v.dist[i] = r
    end

    return true
end

function M.refresh()
    if not v.page then return end
    local s = model.stats()

    v.k_run:set_text(string.format("%d/%d", s.run, conf.machine.count))
    v.k_alarm:set_text(tostring(s.alarm))
    v.k_alarm:set_color(s.alarm > 0 and C.red or C.ink)
    v.k_out:set_text(fmt_num(store.today().ok))
    v.k_cyc:set_text(string.format("%.1f", s.avg_cycle))

    -- 机台卡
    for i, m in ipairs(model.list()) do
        local c = v.cards[i]
        if c then
            local st = state_of(m)
            c.dot:set_color(st.color)
            c.badge_box:set_color(st.color)
            c.badge:set_text(st.name)
            c.prod:set_text(string.format("%s · %s",
                m.product or "-", m.mold or "-"))
            c.order:set_text(m.order or "未排产")

            local pct = (m.plan and m.plan > 0)
                and math.min(100, m.done / m.plan * 100) or 0
            c.bar:set_value(math.floor(pct + 0.5))
            c.bar:set_indicator_color(st.color)
            c.prog:set_text(string.format("%s / %s  %.0f%%",
                fmt_num(m.done or 0), fmt_num(m.plan or 0), pct))
            c.shots:set_text(string.format("本班 %d 模", m.ok or 0))
            c.cyc:set_text(string.format("周期 %.1fs", m.cycle))
        end
    end

    -- 报警流
    local list = store.alarms()
    for i = 1, 5 do
        local r = v.alarms[i]
        local a = list[i]
        if a then
            r.dot:set_color(conf.level_color[a.level] or C.red)
            r.text:set_text(string.format("%s · %s", a.m, a.name))
            r.time:set_text(a.t)
        else
            r.dot:set_color(C.line)
            r.text:set_text(i == 1 and "暂无报警记录" or "")
            r.time:set_text("")
        end
    end

    -- 状态分布
    for _, r in ipairs(v.dist) do
        local n = s[r.key] or 0
        r.bar:set_value(n)
        r.cnt:set_text(tostring(n))
    end
end

return M
