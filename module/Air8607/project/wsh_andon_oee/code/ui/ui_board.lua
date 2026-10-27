--[[
@module  ui_board
@summary Andon 主看板（P0 版）：顶栏 + 工位网格 + OEE 三分项 + 异常 + 帕累托 + 底栏 + 操作弹窗
@author  王世豪
@version 1.1
@date    2026.10.26
@usage
=== 布局（1024x600）===
顶栏 0..64        产线名 / 班次·工单·型号 / 时间 / 在线数 / 安全天数
工位 16..672      4 列 x 2 行，卡片显示状态、产量、异常时长
三分项 16..662    可用率 / 性能 / 良率（OEE 拆解）
右列 684..1008    实时异常 4 条 + 停机原因帕累托
底栏 506..600     今日产量达成进度条 + OEE + 不良 + 停机 + 平均/最长响应
点工位卡片      弹出操作面板（呼叫 / 响应 / 恢复）
]]
local conf = require "conf"
local theme = require "theme"
local line_sim = require "line_sim"
local oee = require "oee"
local rtc_util = require "rtc_util"

local M = {}

local C = theme.C
local SW, SH = conf.W, conf.H

local root, overlay, ov_title, ov_hint
local sel_idx = 0

local COL_W, CARD_W, CARD_H, ROW_H = 166, 158, 174, 182
local GRID_X, GRID_Y = 16, 72

local cards = {}
local alarm_rows = {}
local pareto_rows = {}
local lb_time, lb_online, lb_safety
local lb_avail, lb_perf, lb_qual3
local lb_prod_title, prod_seg, lb_ach
local lb_oee, lb_ng, lb_down, lb_avg, lb_max

-- ==================== 分段进度条工具 ====================
local function make_seg(parent, x, y, seg_w, seg_h, gap, n, color, radius)
    local t = {}
    for i = 1, n do
        t[i] = theme.box(parent, x + (i - 1) * (seg_w + gap), y, seg_w, seg_h, color, radius)
        t[i]:set_hidden(true)
    end
    return t
end

local function set_seg(seg, k)
    k = k < 0 and 0 or k
    for i = 1, #seg do
        seg[i]:set_hidden(i > k)
    end
end

local function round(x)
    return math.floor(x + 0.5)
end

-- ==================== 顶部 ====================
local function build_header(parent)
    theme.box(parent, 0, 0, SW, 64, C.panel, 0)
    theme.box(parent, 0, 63, SW, 1, C.line, 0)

    theme.label(parent, 16, 8, 320, 28, conf.line.name, 26, C.ink)
    theme.label(parent, 16, 38, 440, 20,
        string.format("%s - %s - %s", conf.line.shift, conf.line.work_order, conf.line.product),
        16, C.ink3)

    lb_time = theme.label(parent, 380, 12, 240, 42, "--:--:--", 32, C.accent)

    lb_online = theme.label(parent, 700, 8, 310, 22, "", 18, C.ink2, airui.TEXT_ALIGN_RIGHT)
    lb_safety = theme.label(parent, 700, 34, 310, 22,
        string.format("安全运行 %d 天", conf.line.safety_days), 18, C.run, airui.TEXT_ALIGN_RIGHT)
end

-- ==================== 工位卡片 ====================
local function build_station(parent, idx, col, row)
    local st = conf.stations[idx]
    local x = GRID_X + col * COL_W
    local y = GRID_Y + row * ROW_H

    local card = theme.card(parent, x, y, CARD_W, CARD_H, C.card, 10, C.line, 2)

    local bars = {
        run   = theme.box(card, 0, 0, CARD_W, 6, C.run, 10),
        idle  = theme.box(card, 0, 0, CARD_W, 6, C.idle, 10),
        chg   = theme.box(card, 0, 0, CARD_W, 6, C.changeover, 10),
        warn  = theme.box(card, 0, 0, CARD_W, 6, C.warn, 10),
        alarm = theme.box(card, 0, 0, CARD_W, 6, C.alarm, 10),
        dark  = theme.box(card, 0, 0, CARD_W, 6, C.alarm_dark, 10),
    }
    bars.idle:set_hidden(true)
    bars.chg:set_hidden(true)
    bars.warn:set_hidden(true)
    bars.alarm:set_hidden(true)
    bars.dark:set_hidden(true)

    local lb_name = theme.label(card, 10, 14, 138, 24, st.name, 18, C.ink2)
    local lb_state = theme.label(card, 10, 42, 138, 42, "运行", 30, C.run)
    local lb_prod = theme.label(card, 10, 92, 138, 44, "0", 40, C.ink)
    theme.label(card, 10, 136, 50, 22, "件", 16, C.ink3)
    local lb_time = theme.label(card, 10, 150, 140, 20, "", 16, C.ink3)

    airui.button({
        parent = card, x = 0, y = 0, w = CARD_W, h = CARD_H,
        text = "",
        style = { bg_color = 0x000000, bg_opa = 0, radius = 0, border_width = 0 },
        on_click = function()
            theme.defer(function() M.open_panel(idx) end)
        end,
    })

    cards[idx] = { card = card, bars = bars, lb_state = lb_state, lb_prod = lb_prod, lb_time = lb_time }
end

-- ==================== OEE 三分项 ====================
local function build_three(parent)
    local items = {
        { key = "avail", x = 16,  name = "可用率" },
        { key = "perf",  x = 234, name = "性能" },
        { key = "qual",  x = 452, name = "良率" },
    }
    for _, it in ipairs(items) do
        theme.card(parent, it.x, 436, 210, 60, C.card, 10, C.line, 1)
        theme.label(parent, it.x + 14, 446, 180, 22, it.name, 16, C.ink3)
        local lb = theme.label(parent, it.x + 14, 468, 180, 28, "0%", 24, C.accent)
        if it.key == "avail" then lb_avail = lb
        elseif it.key == "perf" then lb_perf = lb
        else lb_qual3 = lb end
    end
end

-- ==================== 右侧异常面板 ====================
local function build_alarm_panel(parent)
    local x, y, w, h = 684, 72, 324, 300
    theme.card(parent, x, y, w, h, C.panel, 10, C.line, 1)
    theme.label(parent, x + 14, y + 8, 200, 28, "实时异常", 22, C.ink)

    for i = 1, 4 do
        local ry = y + 44 + (i - 1) * 62
        theme.box(parent, x + 10, ry, 4, 52, C.alarm, 2)
        local lb_main = theme.label(parent, x + 24, ry + 2, 290, 26, "", 18, C.ink)
        local lb_dur = theme.label(parent, x + 24, ry + 30, 150, 22, "", 16, C.ink2)
        local lb_state = theme.label(parent, x + 178, ry + 30, 130, 22, "", 16, C.warn)
        alarm_rows[i] = { main = lb_main, dur = lb_dur, state = lb_state }
    end
end

-- ==================== 停机帕累托 ====================
local function build_pareto(parent)
    local x, y, w, h = 684, 380, 324, 126
    theme.card(parent, x, y, w, h, C.panel, 10, C.line, 1)
    theme.label(parent, x + 14, y + 6, 280, 22, "停机原因 (帕累托)", 18, C.ink3)

    for i = 1, 4 do
        local ry = y + 36 + (i - 1) * 22
        local lb_name = theme.label(parent, x + 12, ry, 84, 18, "", 15, C.ink2)
        local segs = make_seg(parent, x + 100, ry + 3, 10, 12, 2, 12, C.accent, 2)
        local lb_pct = theme.label(parent, x + 268, ry, 44, 18, "", 15, C.ink)
        pareto_rows[i] = { name = lb_name, segs = segs, pct = lb_pct }
    end
end

-- ==================== 底栏 ====================
local function build_footer(parent)
    theme.box(parent, 0, 506, SW, 94, C.panel, 0)
    theme.box(parent, 0, 506, SW, 1, C.line, 0)

    theme.label(parent, 16, 510, 200, 22, "今日产量", 16, C.ink3)
    lb_prod_title = theme.label(parent, 16, 532, 360, 26, "0 / 0", 22, C.ink)
    theme.box(parent, 16, 564, 300, 16, C.offline, 4)
    prod_seg = make_seg(parent, 16, 564, 18, 16, 2, 15, C.run, 4)
    lb_ach = theme.label(parent, 326, 560, 80, 24, "0%", 22, C.run)

    theme.label(parent, 420, 510, 120, 22, "OEE", 16, C.ink3)
    lb_oee = theme.label(parent, 420, 534, 160, 44, "0.0%", 44, C.warn)

    lb_ng = theme.label(parent, 600, 520, 150, 24, "不良 0 件", 18, C.ink)
    lb_down = theme.label(parent, 600, 550, 150, 24, "停机 0 min", 18, C.ink)

    lb_avg = theme.label(parent, 770, 520, 240, 24, "平均响应 0.0'", 17, C.ink2)
    lb_max = theme.label(parent, 770, 550, 240, 24, "最长响应 0.0'", 17, C.ink2)
end

-- ==================== 工位操作弹窗 ====================
local function build_overlay(parent)
    overlay = airui.container({
        parent = parent, x = 0, y = 0, w = SW, h = SH,
        color = 0x000000, color_opacity = 190, radius = 0, border_width = 0,
    })
    overlay:set_hidden(true)

    local pw, ph = 460, 380
    local px, py = math.floor((SW - pw) / 2), math.floor((SH - ph) / 2)
    theme.card(overlay, px, py, pw, ph, C.card2, 14, C.line2, 2)

    ov_title = theme.label(overlay, px + 20, py + 16, 420, 36, "工位", 26, C.ink)
    ov_hint = theme.label(overlay, px + 20, py + 54, 420, 24, "选择异常类型进行呼叫", 17, C.ink3)

    for i, tp in ipairs(conf.alarm_types) do
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        local bx = px + 20 + col * 212
        local by = py + 88 + row * 68
        theme.button(overlay, bx, by, 200, 56, tp.name, 22, function()
            theme.defer(function()
                line_sim.call_alarm(sel_idx, tp.key, "操作工")
                M.close_panel()
            end)
        end)
    end

    theme.button(overlay, px + 20, py + 236, 200, 56, "已响应", 22, function()
        theme.defer(function()
            line_sim.ack_alarm(sel_idx, "班组长")
        end)
    end)
    theme.button(overlay, px + 240, py + 236, 200, 56, "恢复生产", 22, function()
        theme.defer(function()
            line_sim.recover(sel_idx)
            M.close_panel()
        end)
    end, true)

    theme.button(overlay, px + 20, py + 306, 420, 52, "关闭", 20, function()
        theme.defer(function() M.close_panel() end)
    end)
end

-- ==================== 对外 ====================
function M.open_panel(idx)
    local st = line_sim.stations()[idx]
    if not st then return end
    sel_idx = idx
    ov_title:set_text(string.format("%s - %s", st.name, line_sim.state_text(st)))
    if st.state == "alarm" and st.alarm then
        ov_hint:set_text(string.format("当前异常：%s（%s）",
            st.alarm.name, st.alarm.ack and "已响应" or "待响应"))
    else
        ov_hint:set_text("选择异常类型进行呼叫，或标记响应/恢复")
    end
    overlay:set_hidden(false)
end

function M.close_panel()
    sel_idx = 0
    if overlay then overlay:set_hidden(true) end
end

function M.refresh()
    -- 时间
    local t = rtc_util.now()
    if t then
        lb_time:set_text(string.format("%02d:%02d:%02d", t.hour, t.min, t.sec))
    end

    -- 工位
    local blink = (os.time() % 2 == 1)
    for i, st in ipairs(line_sim.stations()) do
        local c = cards[i]
        if c then
            local b = c.bars
            b.run:set_hidden(true)
            b.idle:set_hidden(true)
            b.chg:set_hidden(true)
            b.warn:set_hidden(true)
            b.alarm:set_hidden(true)
            b.dark:set_hidden(true)

            if st.state == "run" then
                b.run:set_hidden(false)
                c.lb_state:set_text("运行")
                c.lb_state:set_color(C.run)
                c.lb_time:set_text("")
            elseif st.state == "idle" then
                b.idle:set_hidden(false)
                c.lb_state:set_text("待机")
                c.lb_state:set_color(C.idle)
                c.lb_time:set_text("")
            elseif st.state == "changeover" then
                b.chg:set_hidden(false)
                c.lb_state:set_text("换型")
                c.lb_state:set_color(C.changeover)
                c.lb_time:set_text("")
            elseif st.state == "alarm" and st.alarm then
                local lv = st.alarm.level or 1
                if lv >= 3 then
                    if blink then b.alarm:set_hidden(false) else b.dark:set_hidden(false) end
                    c.lb_state:set_color(C.alarm)
                elseif lv == 2 then
                    b.warn:set_hidden(false)
                    c.lb_state:set_color(C.warn)
                else
                    b.alarm:set_hidden(false)
                    c.lb_state:set_color(C.alarm)
                end
                c.lb_state:set_text("异常")
                c.lb_time:set_text(string.format("%s 已等 %s",
                    st.alarm.name, oee.fmt_dur(os.time() - st.alarm.start)))
            end

            c.lb_prod:set_text(tostring(st.produced))
        end
    end

    -- 顶栏统计
    local n = line_sim.count_by_state()
    lb_online:set_text(string.format("运行 %d/%d   异常 %d", n.run, #conf.stations, n.alarm))
    lb_online:set_color(n.alarm > 0 and C.alarm or C.run)

    -- OEE 三分项 + 总
    local stt = line_sim.stats()
    local o = oee.compute(stt)
    lb_avail:set_text(string.format("%.0f%%", o.availability * 100))
    lb_perf:set_text(string.format("%.0f%%", o.performance * 100))
    lb_qual3:set_text(string.format("%.0f%%", o.quality * 100))
    lb_oee:set_text(string.format("%.1f%%", o.oee * 100))
    if o.oee >= 0.85 then lb_oee:set_color(C.run)
    elseif o.oee >= 0.6 then lb_oee:set_color(C.warn)
    else lb_oee:set_color(C.alarm) end

    -- 异常列表
    local act = line_sim.active_alarms()
    local stations = line_sim.stations()
    for i = 1, 4 do
        local row = alarm_rows[i]
        local a = act[i]
        if a and row then
            row.main:set_text(string.format("%s  %s", stations[a.station].name, a.name))
            row.dur:set_text("已等 " .. oee.fmt_dur(os.time() - a.start))
            if a.ack then
                row.state:set_text("已响应")
                row.state:set_color(C.run)
            else
                row.state:set_text("待响应")
                row.state:set_color(a.level >= 3 and C.alarm or C.warn)
            end
        elseif row then
            row.main:set_text(i == 1 and "暂无异常" or "")
            row.dur:set_text("")
            row.state:set_text("")
        end
    end

    -- 停机帕累托
    local list, total = oee.pareto(stt.by_type)
    for i = 1, 4 do
        local row = pareto_rows[i]
        local it = list[i]
        if it and row then
            row.name:set_text(it.name)
            row.pct:set_text(string.format("%.0f%%", it.pct * 100))
            set_seg(row.segs, round(it.pct * 12))
        elseif row then
            row.name:set_text("")
            row.pct:set_text("")
            set_seg(row.segs, 0)
        end
    end

    -- 底栏
    local ach = (conf.line.target > 0) and (stt.produced / conf.line.target) or 0
    if ach > 1 then ach = 1 end
    lb_prod_title:set_text(string.format("%d / %d", stt.produced, conf.line.target))
    set_seg(prod_seg, round(ach * 15))
    lb_ach:set_text(string.format("%.1f%%", ach * 100))
    lb_ach:set_color(ach >= 1 and C.run or (ach >= 0.8 and C.warn or C.ink2))
    lb_ng:set_text(string.format("不良 %d 件", stt.produced - stt.good))
    lb_down:set_text(string.format("停机 %d min", math.floor(stt.down_sec / 60)))
    lb_avg:set_text(string.format("平均响应 %.1f'", stt.avg_response / 60))
    lb_max:set_text(string.format("最长响应 %.1f'", stt.max_response / 60))
end

function M.build(parent)
    root = airui.container({
        parent = parent, x = 0, y = 0, w = SW, h = SH,
        color = 0x000000, color_opacity = 0, radius = 0, border_width = 0,
    })

    -- 背景：冷蓝竖向渐变（科技感，顶亮底暗）
    theme.gradient(root, 0, 0, SW, SH, 0x16344F, 0x0A1322, 18)

    build_header(root)
    for i = 1, 8 do
        local col = (i - 1) % 4
        local row = math.floor((i - 1) / 4)
        build_station(root, i, col, row)
    end
    build_three(root)
    build_alarm_panel(root)
    build_pareto(root)
    build_footer(root)
    build_overlay(root)

    M.refresh()
    return root
end

function M.show()
    if root then root:set_hidden(false) end
    M.refresh()
end

function M.hide()
    if root then root:set_hidden(true) end
end

return M
