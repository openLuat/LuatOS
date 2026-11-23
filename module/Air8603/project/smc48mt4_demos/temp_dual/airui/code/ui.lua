--[[
@module  ui
@summary 双路温度监控界面：仪表盘主画面 + 参数设置页
@version 2.0.0
@date    2026.11.16

视觉实现要点（airui 1.3.0）：
  1. airui.shape 支持 line / circle / ellipse / rect / arc 五种图元，
     仪表弧、刻度、曲线、网格全部用它画，不靠控件拼；
  2. 容器不支持渐变，背景分层色带用 shape 的 rect 一次画完；
  3. 曲线用「同一条折线画三遍」做辉光：外层宽而淡、中层中等、内层细而亮；
  4. 只有数值标签是 label，其余全在 shape 上，减少重排。

布局（1024×600）：
  顶栏 0..54
  左列 CH1 66..296 / CH2 306..536   宽 492
  右列 趋势 66..322 / 报警 332..536  宽 492
  底栏 544..600
]]
local M = {}

local conf = require "conf"
local store = require "app_store"
local data = require "app_data"
local alarm = require "app_alarm"

-- ===== 配色 =====
local C = {
    bg_top  = 0x0E1621,
    bg_bot  = 0x141F2C,
    card    = 0x18222E,
    card_hi = 0x1E2A38,
    track   = 0x243240,
    grid    = 0x223041,
    line    = 0x2E3D4E,
    ink     = 0xE8F0F8,
    ink2    = 0x9DB0C6,
    dim     = 0x6B7E94,
    accent  = 0x2F7FD1,
    ok      = 0x22C55E,
    warn    = 0xF59E0B,
    alarm   = 0xEF4444,
    fault   = 0x64748B,
}

local CH_COLOR = { 0x38BDF8, 0xF59E0B }

local SW, SH = conf.W, conf.H

local page_main, page_set
local shape_bg, shape_card, shape_trend, shape_alarm
local L = { val = {}, state = {}, warn = {}, alarm = {}, cur = {}, rows = {}, gauge = {} }
local set_row = {}

-- ===== 通用小工具 =====
local function panel(parent, x, y, w, h, color, radius, line_color)
    return airui.container({
        parent = parent, x = x, y = y, w = w, h = h,
        color = color or C.card,
        radius = radius or 8,
        border_color = line_color or C.line,
        border_width = 1,
    })
end

local function text(parent, x, y, w, h, s, size, color, align)
    return airui.label({
        parent = parent, x = x, y = y, w = w, h = h,
        text = s or "",
        font_size = size or 16,
        color = color or C.ink,
        align = align or airui.TEXT_ALIGN_LEFT,
    })
end

local function button(parent, x, y, w, h, s, size, bg, fg, on_click)
    return airui.button({
        parent = parent, x = x, y = y, w = w, h = h,
        text = s, font_size = size or 16,
        style = {
            bg_color = bg or C.card_hi,
            bg_opa = 255,
            bg_grad_color = 0x101821,
            bg_grad_dir = "ver",
            text_color = fg or C.ink,
            radius = 6,
            border_width = 1,
            border_color = C.line,
            pressed_bg_color = 0x0B1219,
            pressed_text_color = 0xFFFFFF,
        },
        on_click = on_click,
    })
end

local function fmt_time(t)
    t = t or os.time()
    if not t or t <= 0 then return "--:--:--" end
    local d = os.date("*t", t)
    if not d then return "--:--:--" end
    return string.format("%02d:%02d:%02d", d.hour, d.min, d.sec)
end

local function state_color(s)
    if s == alarm.ST.WARN then return C.warn end
    if s == alarm.ST.ALARM then return C.alarm end
    if s == alarm.ST.FAULT then return C.fault end
    return C.ok
end

local function clamp(v, a, b)
    if v < a then return a end
    if v > b then return b end
    return v
end

-- ===== 背景 =====
local function build_bg()
    shape_bg = airui.shape({ parent = page_main, x = 0, y = 0, w = SW, h = SH, items = {} })
    local items = {}
    -- 竖向渐变：12 条色带从深到浅
    local band = math.ceil(SH / 12)
    for i = 0, 11 do
        local t = i / 11
        local r = math.floor(0x0E + (0x14 - 0x0E) * t)
        local g = math.floor(0x16 + (0x1F - 0x16) * t)
        local b = math.floor(0x21 + (0x2C - 0x21) * t)
        items[#items + 1] = {
            type = "rect",
            x = 0, y = i * band, w = SW, h = band + 1,
            fill = true,
            fill_color = r * 65536 + g * 256 + b,
            fill_opacity = 255,
            color = 0x000000, width = 0,
        }
    end
    shape_bg:set_items(items)
end

-- ===== 仪表弧 =====
--[[
画一个环形仪表
@param items table 图元表（追加）
@param cx number 圆心 x
@param cy number 圆心 y
@param r number 半径
@param frac number 0~1 进度
@param col number 进度色
]]
local function add_gauge(items, cx, cy, r, frac, col)
    local A0, A1 = 135, 405          -- 270° 扫角，缺口在正下方
    local sweep = (A1 - A0) * clamp(frac, 0, 1)

    -- 外圈暗底
    items[#items + 1] = {
        type = "arc", cx = cx, cy = cy, r = r,
        start_angle = A0, end_angle = A1,
        width = 12, color = C.track, opacity = 255, round_end = true,
    }
    -- 进度弧（辉光 + 本体）
    if sweep > 1 then
        items[#items + 1] = {
            type = "arc", cx = cx, cy = cy, r = r,
            start_angle = A0, end_angle = math.floor(A0 + sweep),
            width = 22, color = col, opacity = 40, round_end = true,
        }
        items[#items + 1] = {
            type = "arc", cx = cx, cy = cy, r = r,
            start_angle = A0, end_angle = math.floor(A0 + sweep),
            width = 12, color = col, opacity = 255, round_end = true,
        }
    end

    -- 内环：给中心读数一个底，增加层次
    items[#items + 1] = {
        type = "circle", cx = cx, cy = cy, r = r - 14,
        fill = false, color = C.track, width = 1, opacity = 90,
    }

    -- 刻度：11 根，每 27°
    for k = 0, 10 do
        local a = math.rad(A0 + 27 * k)
        local long = (k % 5 == 0)
        local r1 = r + 10
        local r2 = r + (long and 20 or 15)
        items[#items + 1] = {
            type = "line",
            x1 = math.floor(cx + math.cos(a) * r1),
            y1 = math.floor(cy + math.sin(a) * r1),
            x2 = math.floor(cx + math.cos(a) * r2),
            y2 = math.floor(cy + math.sin(a) * r2),
            width = long and 3 or 2,
            color = long and C.ink or 0x93A7BC,
            opacity = long and 240 or 200,
        }
    end
end

-- ===== 卡片 =====
local CARD = {
    { x = 14, y = 66, w = 492, h = 230 },
    { x = 14, y = 306, w = 492, h = 230 },
}

local function build_card(i)
    local g = CARD[i]
    local col = CH_COLOR[i]
    local p = panel(page_main, g.x, g.y, g.w, g.h, C.card, 8, C.line)

    -- 左侧色条
    airui.container({
        parent = p, x = 0, y = 18, w = 4, h = g.h - 36,
        color = col, radius = 2, border_width = 0,
    })

    text(p, 20, 10, 260, 26, ("CH%d   %s"):format(i, conf.chs[i].name), 19, C.ink)
    L.state[i] = text(p, 300, 12, 172, 24, "●  正常", 15, C.ok, airui.TEXT_ALIGN_RIGHT)

    -- 仪表画布（每帧重画）
    local sp = airui.shape({
        parent = p, x = 10, y = 44, w = 210, h = 180, items = {},
    })
    L.gauge = L.gauge or {}
    L.gauge[i] = sp

    -- 中心读数
    L.val[i] = text(p, 10, 104, 210, 60, "--", 44, C.ok, airui.TEXT_ALIGN_CENTER)
    text(p, 10, 168, 210, 22, "℃", 20, C.ink2, airui.TEXT_ALIGN_CENTER)

    -- 右侧数据列
    local rx = 234
    local function item_row(y, k, v)
        text(p, rx, y, 110, 22, k, 14, C.dim)
        return text(p, rx + 110, y - 2, 128, 26, v, 21, C.ink, airui.TEXT_ALIGN_RIGHT)
    end

    L.warn[i]  = item_row(60, "预警值", "0.0")
    L.alarm[i] = item_row(110, "报警值", "0.0")
    L.cur[i]   = item_row(160, "实时值", "---.--")

    return p
end

local function redraw_card(i)
    local sp = L.gauge and L.gauge[i]
    if not sp then return end
    local v = data.val[i]
    local s = alarm.state_of(i)
    local col = state_color(s)
    local vmax = conf.trend.y_max
    local frac = 0
    if data.online and v and v > conf.alarm.raw_fault then
        frac = clamp((v - conf.trend.y_min) / (vmax - conf.trend.y_min), 0, 1)
    end
    local items = {}
    add_gauge(items, 105, 90, 66, frac, col)
    sp:set_items(items)
end

-- ===== 趋势 =====
local TREND = { x = 518, y = 66, w = 492, h = 256 }
local PX, PY, PW, PH = 44, 46, 432, 196   -- 绘图区（相对面板）：左侧 44px 留给 Y 轴刻度，右侧留 12px 给末端光点

local function build_trend()
    local p = panel(page_main, TREND.x, TREND.y, TREND.w, TREND.h, C.card, 8, C.line)
    text(p, 18, 10, 240, 26, "实时趋势   1 小时", 19, C.ink)
    text(p, 260, 12, 100, 22, "CH1", 14, CH_COLOR[1], airui.TEXT_ALIGN_RIGHT)
    text(p, 368, 12, 100, 22, "CH2", 14, CH_COLOR[2], airui.TEXT_ALIGN_RIGHT)

    -- Y 轴刻度文字
    text(p, 6, PY - 12, 34, 18, ("%d"):format(conf.trend.y_max), 12, C.dim)
    text(p, 6, PY + PH / 2 - 10, 34, 18, ("%d"):format((conf.trend.y_max + conf.trend.y_min) / 2), 12, C.dim)
    text(p, 6, PY + PH - 6, 34, 18, ("%d"):format(conf.trend.y_min), 12, C.dim)

    shape_trend = airui.shape({
        parent = p, x = PX, y = PY, w = PW, h = PH, items = {},
    })
end

local function v2y(v)
    local t = clamp((v - conf.trend.y_min) / (conf.trend.y_max - conf.trend.y_min), 0, 1)
    return math.floor(PH - t * PH)
end

local function add_polyline(items, hist, col, step)
    local n = #hist
    if n < 2 then return end
    local first = 1
    if n > 90 then first = n - 89 end
    local cnt = n - first + 1
    local dx = PW / (90 - 1)
    local start_idx = n < 90 and (90 - cnt) or 0

    local pts = {}
    for k = 1, cnt do
        local v = hist[first + k - 1]
        pts[k] = {
            x = math.floor((start_idx + k - 1) * dx),
            y = v2y(v),
        }
    end

    -- 辉光三层
    local layers = {
        { w = 9, opa = 30 },
        { w = 5, opa = 70 },
        { w = 2, opa = 255 },
    }
    for _, ly in ipairs(layers) do
        for k = 2, #pts do
            items[#items + 1] = {
                type = "line",
                x1 = pts[k - 1].x, y1 = pts[k - 1].y,
                x2 = pts[k].x, y2 = pts[k].y,
                width = ly.w, color = col, opacity = ly.opa,
                round_start = true, round_end = true,
            }
        end
    end

    -- 末端光点
    local lastp = pts[#pts]
    items[#items + 1] = {
        type = "circle", cx = lastp.x, cy = lastp.y, r = 9,
        fill = true, fill_color = col, fill_opacity = 60,
        color = col, width = 0, opacity = 255,
    }
    items[#items + 1] = {
        type = "circle", cx = lastp.x, cy = lastp.y, r = 4,
        fill = true, fill_color = col, fill_opacity = 255,
        color = col, width = 0, opacity = 255,
    }
end

local function redraw_trend()
    if not shape_trend then return end
    local items = {}

    -- 网格
    for k = 0, 4 do
        local y = math.floor(k * PH / 4)
        items[#items + 1] = {
            type = "line", x1 = 0, y1 = y, x2 = PW, y2 = y,
            width = 1, color = C.grid, opacity = 255,
        }
    end
    for k = 0, 3 do
        local x = math.floor(k * PW / 3)
        items[#items + 1] = {
            type = "line", x1 = x, y1 = 0, x2 = x, y2 = PH,
            width = 1, color = C.grid, opacity = 120,
        }
    end

    -- 报警线（两路取平均阈值，虚线）
    local am = (conf.chs[1].alarm + conf.chs[2].alarm) / 2
    local ay = v2y(am)
    items[#items + 1] = {
        type = "line", x1 = 0, y1 = ay, x2 = PW, y2 = ay,
        width = 2, color = C.alarm, opacity = 110,
        dash_width = 8, dash_gap = 7,
    }

    -- 两路曲线
    add_polyline(items, data.hist[1] or {}, CH_COLOR[1])
    add_polyline(items, data.hist[2] or {}, CH_COLOR[2])

    shape_trend:set_items(items)
end

-- ===== 报警记录 =====
local ALARM = { x = 518, y = 332, w = 492, h = 204 }
local ROW_N = 6
local ROW_H = 27

local function build_alarm()
    local p = panel(page_main, ALARM.x, ALARM.y, ALARM.w, ALARM.h, C.card, 8, C.line)
    text(p, 18, 10, 240, 26, "报警记录", 19, C.ink)
    L.rec_count = text(p, 340, 12, 132, 22, "0 / 8", 13, C.dim, airui.TEXT_ALIGN_RIGHT)

    -- 左侧色条画布（随记录刷新）
    shape_alarm = airui.shape({
        parent = p, x = 12, y = 42, w = 10, h = ROW_N * ROW_H, items = {},
    })

    for r = 1, ROW_N do
        L.rows[r] = text(p, 30, 42 + (r - 1) * ROW_H, 440, 24, "", 14, C.ink2)
    end
end

local function redraw_alarm()
    if not shape_alarm then return end
    local items = {}
    for r = 1, ROW_N do
        local rec = alarm.records[r]
        if rec then
            local col = C.grid
            if rec.typ == "报警" then col = C.alarm
            elseif rec.typ == "预警" then col = C.warn
            elseif rec.typ == "恢复" or rec.typ == "通信恢复" then col = C.ok
            elseif rec.typ == "断线" or rec.typ == "通信中断" then col = C.fault end
            items[#items + 1] = {
                type = "rect", x = 0, y = (r - 1) * ROW_H + 6, w = 3, h = 14,
                radius = 2, fill = true, fill_color = col, fill_opacity = 255,
                color = col, width = 0, opacity = 255,
            }
        end
    end
    shape_alarm:set_items(items)
end

-- ===== 顶栏 =====
local function build_header()
    local p = airui.container({
        parent = page_main, x = 0, y = 0, w = SW, h = 54,
        color = C.bg_top, radius = 0, border_width = 0,
    })
    -- 顶部细高光 + 底部强调线
    airui.container({
        parent = p, x = 0, y = 0, w = SW, h = 1,
        color = 0x24313F, radius = 0, border_width = 0,
    })
    airui.container({
        parent = p, x = 0, y = 52, w = SW, h = 2,
        color = C.accent, radius = 0, border_width = 0,
    })
    airui.container({
        parent = p, x = 0, y = 53, w = SW, h = 1,
        color = 0x0A1017, radius = 0, border_width = 0,
    })

    airui.container({
        parent = p, x = 20, y = 18, w = 4, h = 18,
        color = C.accent, radius = 2, border_width = 0,
    })
    text(p, 32, 12, 360, 30, "双路温度监控系统", 22, C.ink)
    L.comm = text(p, 560, 16, 240, 22, "●  PLC 通讯中", 14, C.ok)
    L.clock = text(p, 830, 16, 176, 22, "--:--:--", 16, C.ink2, airui.TEXT_ALIGN_RIGHT)
end

-- ===== 底栏 =====
local function build_footer()
    local p = airui.container({
        parent = page_main, x = 0, y = 544, w = SW, h = 56,
        color = C.bg_top, radius = 0, border_width = 0,
    })
    airui.container({
        parent = p, x = 0, y = 0, w = SW, h = 1,
        color = 0x2A3848, radius = 0, border_width = 0,
    })
    L.hint = text(p, 22, 18, 420, 22, "采样 500ms   |   历史 720 点", 13, C.dim)

    L.btn_mute = button(p, 640, 11, 110, 36, "消  音", 16, C.card_hi, C.dim, function()
        if alarm.mute then return end
        alarm.mute_on()
        M.refresh()
    end)

    button(p, 766, 11, 110, 36, "复  位", 16, C.card_hi, C.ink, function()
        alarm.reset()
        M.refresh()
    end)

    button(p, 892, 11, 114, 36, "参数设置", 15, C.accent, 0xFFFFFF, function()
        M.open_settings()
    end)
end

-- ===== 主画面 =====
local function build_main()
    page_main = airui.container({
        x = 0, y = 0, w = SW, h = SH,
        color = C.bg_top, radius = 0, border_width = 0,
    })
    build_bg()
    build_header()
    build_card(1)
    build_card(2)
    build_trend()
    build_alarm()
    build_footer()
end

-- ===== 参数设置页 =====
local ROWS = {
    { key = "warn",  ch = 1, name = "CH1 预警值", min = 0,   max = 49.9, step = 0.5, dec = 1, hint = "达到即提示，不锁存" },
    { key = "alarm", ch = 1, name = "CH1 报警值", min = 0,   max = 49.9, step = 0.5, dec = 1, hint = "达到即报警并记录，建议不超过 45" },
    { key = "warn",  ch = 2, name = "CH2 预警值", min = 0,   max = 49.9, step = 0.5, dec = 1, hint = "两路独立设置" },
    { key = "alarm", ch = 2, name = "CH2 报警值", min = 0,   max = 49.9, step = 0.5, dec = 1, hint = "两路独立设置" },
    { key = "hyst",  ch = 0, name = "回差",       min = 0.0, max = 5.0,  step = 0.1, dec = 1, hint = "降档要多退回这么多；0 表示不设回差" },
    { key = "delay", ch = 0, name = "确认延时",   min = 1,   max = 60,   step = 1,   dec = 0, hint = "单位秒，滤掉瞬时毛刺" },
}

local function row_value(r)
    if r.key == "hyst" then return conf.alarm.hysteresis end
    if r.key == "delay" then return conf.alarm.delay_s end
    return conf.chs[r.ch][r.key]
end

local function row_set(r, v)
    if v < r.min then v = r.min end
    if v > r.max then v = r.max end
    if r.key == "hyst" then
        conf.alarm.hysteresis = v
    elseif r.key == "delay" then
        conf.alarm.delay_s = math.floor(v + 0.5)
    else
        conf.chs[r.ch][r.key] = v
    end
end

local function refresh_settings()
    for i, r in ipairs(ROWS) do
        local lb = set_row[i]
        if lb then
            local v = row_value(r)
            if r.dec == 0 then
                lb:set_text(string.format("%d", math.floor(v + 0.5)))
            else
                lb:set_text(string.format("%." .. r.dec .. "f", v))
            end
        end
    end
end

local function build_settings()
    page_set = airui.container({
        x = 0, y = 0, w = SW, h = SH,
        color = C.bg_top, radius = 0, border_width = 0,
    })

    local hd = airui.container({
        parent = page_set, x = 0, y = 0, w = SW, h = 54,
        color = C.bg_top, radius = 0, border_width = 0,
    })
    airui.container({
        parent = hd, x = 0, y = 52, w = SW, h = 2,
        color = C.accent, radius = 0, border_width = 0,
    })
    airui.container({
        parent = hd, x = 20, y = 18, w = 4, h = 18,
        color = C.accent, radius = 2, border_width = 0,
    })
    text(hd, 32, 12, 360, 30, "参数设置", 22, C.ink)

    local body = panel(page_set, 14, 66, 996, 462, C.card, 8, C.line)

    for i, r in ipairs(ROWS) do
        local y = (i - 1) * 66
        if i > 1 then
            airui.container({
                parent = body, x = 24, y = y, w = 948, h = 1,
                color = C.line, radius = 0, border_width = 0,
            })
        end
        airui.container({
            parent = body, x = 24, y = y + 20, w = 3, h = 24,
            color = (r.ch > 0) and CH_COLOR[r.ch] or C.dim, radius = 2, border_width = 0,
        })
        text(body, 40, y + 20, 260, 26, r.name, 18, C.ink2)
        text(body, 620, y + 22, 340, 24, r.hint or "", 14, C.dim)

        button(body, 300, y + 16, 42, 36, "-", 24, C.card_hi, C.ink, function()
            row_set(r, row_value(r) - r.step)
            refresh_settings()
        end)

        airui.container({
            parent = body, x = 350, y = y + 16, w = 140, h = 36,
            color = 0x141F2C, radius = 4, border_color = C.line, border_width = 1,
        })
        set_row[i] = text(body, 350, y + 21, 140, 28, "", 22, C.ink, airui.TEXT_ALIGN_CENTER)

        button(body, 498, y + 16, 42, 36, "+", 24, C.card_hi, C.ink, function()
            row_set(r, row_value(r) + r.step)
            refresh_settings()
        end)
    end

    button(page_set, 736, 552, 120, 38, "取  消", 16, C.card_hi, C.ink, function()
        M.close_settings()
    end)
    button(page_set, 872, 552, 134, 38, "保  存", 16, C.accent, 0xFFFFFF, function()
        for i = 1, #conf.chs do
            local c = conf.chs[i]
            if c.alarm <= c.warn then c.alarm = c.warn + 1.0 end
        end
        store.save_channels()
        store.set("hyst", conf.alarm.hysteresis)
        store.set("delay", conf.alarm.delay_s)
        refresh_settings()
        M.refresh()
        M.close_settings()
    end)

    page_set:set_hidden(true)
end

-- ===== 对外 =====
function M.open_settings()
    refresh_settings()
    page_set:set_hidden(false)
end

function M.close_settings()
    page_set:set_hidden(true)
end

function M.refresh()
    if not page_main then return end

    L.clock:set_text(fmt_time(os.time()))

    for i = 1, #conf.chs do
        local v = data.val[i]
        local s = alarm.state_of(i)
        local col = state_color(s)

        -- 状态是断线时不给数：避免出现「断线 28.1℃」这种自相矛盾的显示
        if data.online and s ~= alarm.ST.FAULT and v and v > conf.alarm.raw_fault then
            L.val[i]:set_text(string.format("%.1f", v))
            L.cur[i]:set_text(string.format("%.2f", v))
        else
            L.val[i]:set_text("--")
            L.cur[i]:set_text("---.--")
        end
        L.val[i]:set_color(col)
        L.state[i]:set_text("●  " .. alarm.state_name(s))
        L.state[i]:set_color(col)
        L.warn[i]:set_text(string.format("%.1f", conf.chs[i].warn))
        L.alarm[i]:set_text(string.format("%.1f", conf.chs[i].alarm))

        redraw_card(i)
    end

    if data.online then
        L.comm:set_text("●  PLC 通讯中")
        L.comm:set_color(C.ok)
    else
        L.comm:set_text("●  通讯中断")
        L.comm:set_color(C.alarm)
    end

    local n = #alarm.records
    L.rec_count:set_text(("%d / %d"):format(n, conf.alarm.max))
    for r = 1, ROW_N do
        local rec = alarm.records[r]
        if rec then
            L.rows[r]:set_text(string.format("%s   %-4s %-4s %s",
                fmt_time(rec.t),
                alarm.rec_label(rec),
                rec.typ,
                rec.value and string.format("%5.1f℃", rec.value) or "  --  "))
            local rc = C.ink2
            if rec.typ == "报警" then rc = C.alarm
            elseif rec.typ == "预警" then rc = C.warn
            elseif rec.typ == "恢复" or rec.typ == "通信恢复" then rc = C.ok
            elseif rec.typ == "断线" or rec.typ == "通信中断" then rc = C.fault end
            L.rows[r]:set_color(rc)
        else
            L.rows[r]:set_text("")
        end
        if n == 0 and r == 3 then
            L.rows[r]:set_text("       暂无报警记录")
            L.rows[r]:set_color(C.dim)
        end
    end
    redraw_alarm()

    if L.btn_mute then
        L.btn_mute:set_text(alarm.mute and "已消音" or "消  音")
        L.btn_mute:set_style({
            bg_color = alarm.mute and C.card or C.card_hi,
            bg_opa = 255,
            text_color = alarm.mute and C.dim or C.ink,
            radius = 6,
            border_width = 1,
            border_color = C.line,
            pressed_bg_color = 0x0B1219,
            pressed_text_color = 0xFFFFFF,
        })
    end

    L.hint:set_text(("采样 %dms   |   历史 %d 点"):format(conf.poll_ms, #(data.hist[1] or {})))
end

function M.start()
    build_main()
    build_settings()

    data.on_update(function(evt)
        if evt == "poll" or evt == "online" or evt == "offline" then
            M.refresh()
        elseif evt == "sample" then
            redraw_trend()
        end
    end)

    alarm.on_update(function() M.refresh() end)

    sys.timerLoopStart(function() M.refresh() end, 1000)

    M.refresh()
    redraw_trend()
    log.info("ui", "界面已创建")
end

return M
