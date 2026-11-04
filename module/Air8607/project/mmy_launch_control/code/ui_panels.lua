--[[
@module  ui_panels
@summary 右侧三块数据卡：飞行弹道 / 系统检查 / 箭体余量 / 飞行时序
@version 1.0
@date    2026.11.04

刷新策略（这是整屏最费 CPU 的地方，全部按需节流）：
  弹道曲线  250ms 重画（约 90 个图元）
  检查清单  只在自检项变化时重画节点
  余量条    250ms 重画（8 个图元）
  时序流    只在阶段/事件变化时重画（mission.st.rev）
]]
local conf    = require "conf"
local theme   = require "theme"
local kit     = require "kit"
local mission = require "mission"

local C = theme.C
local M = {}

-- ==================== 弹道曲线 ====================
local CH = { w = 352, h = 260, px = 42, py = 44, pw = 294, ph = 148 }
local TAU = conf.mission.orbit_t

local function build_chart(parent)
    local card = theme.card(parent, 348, 64, CH.w, CH.h, C.panel, 12)
    -- 先建图形层，再建文字，保证文字在图形之上
    local shape = theme.shape({ parent = card, x = 0, y = 0, w = CH.w, h = CH.h, items = {} })
    theme.label(card, 14, 10, 160, 20, "飞行弹道", 14, C.ink)
    theme.label(card, 96, 12, 240, 14, "高度 0~200km · 速度 0~3.4km/s", 10, C.ink3)
    theme.label(card, 96, 26, 240, 14, "横轴 任务时间 s（飞行段 6×）", 10, C.ink3)
    -- 图例
    local function legend(x, color, text)
        theme.box(card, x, 230, 10, 3, color, 2)
        theme.label(card, x + 15, 223, 120, 16, text, 11, C.ink3)
    end
    legend(14, C.cyan, "高度")
    legend(74, C.amber, "速度")
    local apogee = theme.label(card, 200, 223, 138, 16, "", 11, C.ink3,
        airui.TEXT_ALIGN_RIGHT)
    return { card = card, shape = shape, apogee = apogee, acc = 1 }
end

local function draw_chart(self)
    local st = mission.st
    local it = {}
    local x0, y0, pw, ph = CH.px, CH.py, CH.pw, CH.ph
    local ybase = y0 + ph

    -- 网格
    for i = 0, 4 do
        local yy = y0 + ph * i / 4
        it[#it + 1] = { type = "line", x1 = x0, y1 = yy, x2 = x0 + pw, y2 = yy,
            color = C.line, width = 1, opacity = (i == 4) and 255 or 120 }
    end
    for i = 0, 4 do
        local xx = x0 + pw * i / 4
        it[#it + 1] = { type = "line", x1 = xx, y1 = y0, x2 = xx, y2 = ybase,
            color = C.line, width = 1, opacity = 90 }
    end

    -- 一级分离分界
    local sep_x = x0 + pw * 150 / TAU
    it[#it + 1] = { type = "line", x1 = sep_x, y1 = y0, x2 = sep_x, y2 = ybase,
        color = C.line2, width = 1, dash_width = 3, dash_gap = 3, opacity = 200 }

    -- 2 = 飞行段：先铺计划弹道（虚线），再画已飞过的实线
    local function px_of(t) return x0 + pw * kit.clamp(t / TAU, 0, 1) end
    local function y_alt(a) return ybase - ph * kit.clamp(a / 200, 0, 1) end
    local function y_vel(v) return ybase - ph * kit.clamp(v / 3400, 0, 1) end

    local step = 10
    local done = (st.phase == "ascent" or st.phase == "orbit")
    local tnow = done and st.mt or 0

    -- 计划弹道（灰色虚线）
    local plan = {}
    for t = 0, TAU, step do
        local a = mission.telemetry_at(t)
        plan[#plan + 1] = { px_of(t), y_alt(a) }
    end
    kit.polyline(it, plan, C.ink3, 1, 110)

    if done and tnow > 0 and #plan > 1 then
        local pts, vpts = {}, {}
        for t = 0, tnow, step do
            local a, v = mission.telemetry_at(t)
            pts[#pts + 1] = { px_of(t), y_alt(a) }
            vpts[#vpts + 1] = { px_of(t), y_vel(v) }
        end
        local a, v = mission.telemetry_at(tnow)
        pts[#pts + 1] = { px_of(tnow), y_alt(a) }
        vpts[#vpts + 1] = { px_of(tnow), y_vel(v) }

        kit.area(it, pts, ybase, C.cyan, 34)
        kit.polyline(it, vpts, C.amber, 2, 235)
        kit.polyline(it, pts, C.cyan, 2, 255)

        -- 光点 + 时间游标
        local cx, cy = pts[#pts][1], pts[#pts][2]
        local vx, vy = vpts[#vpts][1], vpts[#vpts][2]
        -- 游标只在飞行中出现；入轨后 tnow 固定在右边界，那条竖线会被误读成"曲线掉下来"
        if st.phase ~= "orbit" then
            it[#it + 1] = { type = "line", x1 = cx, y1 = y0, x2 = cx, y2 = ybase,
                color = C.cyan, width = 1, opacity = 70 }
        end
        it[#it + 1] = { type = "circle", cx = cx, cy = cy, r = 6, color = C.cyan,
            width = 0, fill = true, fill_color = C.cyan, fill_opacity = 60 }
        it[#it + 1] = { type = "circle", cx = cx, cy = cy, r = 3, color = C.cyan,
            width = 0, fill = true, fill_color = C.cyan, fill_opacity = 255 }
        it[#it + 1] = { type = "circle", cx = vx, cy = vy, r = 3, color = C.amber,
            width = 0, fill = true, fill_color = C.amber, fill_opacity = 255 }
    else
        -- 地面待命：画一个"计划入轨点"
        it[#it + 1] = { type = "circle", cx = x0 + pw, cy = y_alt(200), r = 3,
            color = C.ink3, width = 0, fill = true, fill_color = C.ink3, fill_opacity = 200 }
    end

    theme.set_items(self.shape, it)

    -- 轴标
    local a_now = done and st.alt or 0
    self.apogee:set_text(string.format("当前 %.0f km · 目标 200 km", a_now))
end

-- 采样点刻度（用 label 一次性画好，避免每帧重建）
local function build_chart_axis(parent)
    local labels = {}
    for i = 0, 4 do
        local xx = 348 + CH.px + CH.pw * i / 4
        labels[#labels + 1] = theme.label(parent, math.floor(xx) - 20, 64 + CH.py + CH.ph + 4,
            44, 14, tostring(math.floor(TAU * i / 4)), 10, C.ink3,
            airui.TEXT_ALIGN_CENTER)
    end
    for i = 0, 2 do
        local yy = 64 + CH.py + CH.ph * i / 2
        local v = math.floor(200 * (1 - i / 2))
        theme.label(parent, 348 + 2, math.floor(yy) - 8, 38, 14, tostring(v), 10, C.ink3,
            airui.TEXT_ALIGN_RIGHT)
    end
    return labels
end

-- ==================== 系统检查 ====================
function M.build_checks(parent)
    local card = theme.card(parent, 348, 332, 170, 188, C.panel, 12)
    local self = { card = card, labels = {}, done = -1 }
    self.dots = theme.shape({ parent = card, x = 0, y = 0, w = 170, h = 188, items = {} })
    theme.label(card, 12, 8, 100, 18, "系统检查", 13, C.ink)
    self.tag = theme.label(card, 100, 10, 58, 16, "0/8", 11, C.ink3,
        airui.TEXT_ALIGN_RIGHT)
    for i = 1, mission.check_total() do
        local yy = 34 + (i - 1) * 18
        self.labels[i] = theme.label(card, 26, yy - 3, 130, 18,
            mission.check_name(i), 12, C.ink3)
    end
    return self
end

function M.tick_checks(self)
    local done = mission.st.checks
    if done == self.done then return end
    self.done = done
    local it = {}
    for i = 1, mission.check_total() do
        local cy = 34 + (i - 1) * 18 + 7
        local on = i <= done
        local col = on and C.green or C.ink3
        it[#it + 1] = { type = "circle", cx = 16, cy = cy, r = 3, color = col,
            width = 0, fill = true, fill_color = col, fill_opacity = on and 255 or 110 }
        if on then
            -- 对勾：两个短线
            it[#it + 1] = { type = "line", x1 = 14, y1 = cy, x2 = 16, y2 = cy + 2,
                color = 0x08161A, width = 2, round_start = true, round_end = true }
            it[#it + 1] = { type = "line", x1 = 16, y1 = cy + 2, x2 = 19, y2 = cy - 2,
                color = 0x08161A, width = 2, round_start = true, round_end = true }
        end
        self.labels[i]:set_color(on and C.ink or C.ink3)
    end
    theme.set_items(self.dots, it)
    self.tag:set_text(string.format("%d/%d", done, mission.check_total()))
end

-- ==================== 箭体余量 ====================
local GAUGE = {
    { key = "lox",   name = "液氧 LOX", color = C.cyan },
    { key = "rp1",   name = "煤油 RP-1", color = C.amber },
    { key = "s2",    name = "二级推进剂", color = C.blue },
    { key = "power", name = "箭上电源", color = C.green },
}

function M.build_gauges(parent)
    local card = theme.card(parent, 526, 332, 172, 188, C.panel, 12)
    local self = { card = card, vals = {}, cache = {} }
    self.shape = theme.shape({ parent = card, x = 0, y = 0, w = 172, h = 188, items = {} })
    theme.label(card, 12, 8, 100, 18, "箭体余量", 13, C.ink)
    for i, g in ipairs(GAUGE) do
        local yy = 34 + (i - 1) * 36
        theme.label(card, 12, yy, 100, 14, g.name, 11, C.ink3)
        self.vals[i] = theme.label(card, 96, yy, 64, 14, "--", 11, g.color,
            airui.TEXT_ALIGN_RIGHT)
    end
    return self
end

function M.tick_gauges(self)
    local st = mission.st
    local it = {}
    for i, g in ipairs(GAUGE) do
        local yy = 34 + (i - 1) * 36 + 16
        local v = st.fuel[g.key] or 0
        kit.bar(it, 12, yy, 148, 6, v / 100, g.color, 0x16233A, 3)
        local txt = string.format("%.0f%%", v)
        if txt ~= self.cache[i] then
            self.cache[i] = txt
            self.vals[i]:set_text(txt)
            local col = v < 20 and C.red or g.color
            self.vals[i]:set_color(col)
        end
    end
    theme.set_items(self.shape, it)
end

-- ==================== 飞行时序 ====================
local function fmt_step(t)
    if math.abs(t) < 0.5 then return "T+0" end
    local a = math.floor(math.abs(t) + 0.5)
    local s = t < 0 and "-" or "+"
    if a < 60 then return string.format("%s%d s", s, a) end
    return string.format("%s%d:%02d", s, math.floor(a / 60), a % 60)
end

function M.build_timeline(parent)
    local card = theme.card(parent, 706, 64, 306, 456, C.panel, 12)
    local self = { card = card, rev = -1, names = {}, times = {}, stats = {} }
    self.shape = theme.shape({ parent = card, x = 0, y = 0, w = 306, h = 456, items = {} })
    theme.label(card, 14, 10, 160, 20, "飞行时序", 14, C.ink)
    self.tag = theme.label(card, 190, 12, 100, 16,
        string.format("共 %d 步", #conf.events), 11, C.ink3, airui.TEXT_ALIGN_RIGHT)
    for i, ev in ipairs(conf.events) do
        local cy = 46 + (i - 1) * 40
        self.times[i] = theme.label(card, 14, cy - 8, 46, 16, fmt_step(ev.t), 10, C.ink3)
        self.names[i] = theme.label(card, 86, cy - 10, 132, 20, ev.name, 14, C.ink3)
        self.stats[i] = theme.label(card, 218, cy - 8, 74, 16, "", 10, C.ink3,
            airui.TEXT_ALIGN_RIGHT)
    end
    return self
end

function M.tick_timeline(self)
    local st = mission.st
    if st.rev == self.rev then return end
    self.rev = st.rev

    local it = {}
    for i, ev in ipairs(st.events) do
        local cy = 46 + (i - 1) * 40
        local active = (i == st.active)
        if active then
            it[#it + 1] = { type = "rect", x = 8, y = cy - 18, w = 290, h = 36,
                radius = 8, color = C.amber, width = 0, fill = true,
                fill_color = C.amber, fill_opacity = 22 }
        end
        -- 连接线
        if i < #st.events then
            local col = (ev.state == "done") and C.green or C.line2
            it[#it + 1] = { type = "line", x1 = 74, y1 = cy + 5, x2 = 74,
                y2 = cy + 35, color = col, width = 1, opacity = 160 }
        end
        -- 节点
        local col = C.ink3
        local op = 120
        if ev.state == "done" then col, op = C.green, 255
        elseif active then col, op = C.amber, 255 end
        if active then
            it[#it + 1] = { type = "circle", cx = 74, cy = cy, r = 7,
                color = C.amber, width = 1, opacity = 180 }
        end
        it[#it + 1] = { type = "circle", cx = 74, cy = cy, r = 4, color = col,
            width = 0, fill = true, fill_color = col, fill_opacity = op }

        local name_col = C.ink3
        local stat, stat_col = "待执行", C.ink3
        if ev.state == "done" then
            name_col, stat, stat_col = C.ink2, "已执行", C.green
        elseif active then
            name_col, stat, stat_col = C.ink, "进行中", C.amber
        end
        self.names[i]:set_text(ev.name)
        self.names[i]:set_color(name_col)
        self.stats[i]:set_text(stat)
        self.stats[i]:set_color(stat_col)
    end
    theme.set_items(self.shape, it)

    local done = 0
    for i = 1, #st.events do
        if st.events[i].state == "done" then done = done + 1 end
    end
    self.tag:set_text(string.format("%d/%d 步", done, #st.events))
end

M.CH = CH
M.TAU = TAU
M.build_chart = build_chart
M.build_chart_axis = build_chart_axis
M.draw_chart = draw_chart

return M
