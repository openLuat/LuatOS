--[[
@module  ui_dashboard
@summary 农业大棚智能控制大屏 UI（Air8607 10寸 1024x600 airui 版）
@layout
1024x600 横屏三列布局（对应 docs/agri_greenhouse_dashboard.html 的精简版）：
  顶栏(54)  : 标题 + 实时时钟
  KPI行(58) : 平均温度/平均湿度/CO2/光照/告警/设备运行 6 个指标块
  左列(324) : 环境实时指标(4卡) + 土壤墒情(6行)
  中列(380) : 棚区分布(6卡) + 设备控制(10键 5x2)
  右列(288) : 室外气象 + 灌溉水质 + 智能告警
@note
1. 界面只依赖 mock_data 模块的数据字段，换真实采集源无需改 UI；
2. 颜色按 RGB888 数值传入（与官方 demo 一致）；
3. 中文字库走 airui.font_load 固件内置 hzfont，字号最小 16。
]]
local data = require "mock_data"

local M = {}

-- ==================== 配色 ====================
local C = {
    bg      = 0x0B1524,
    panel   = 0x12253C,
    border  = 0x1E3A5C,
    cyan    = 0x22D9FF,
    green   = 0x2EE6A0,
    amber   = 0xFFC857,
    red     = 0xFF5B6E,
    txt     = 0xDCEBFF,
    txt2    = 0x8FB2D4,
    txt3    = 0x5C7FA6,
}

local SW, SH = 1024, 600

-- 控件引用（刷新时 set_text 用）
local R = {
    kpi = {}, env = {}, zone = {}, soil = {},
    devBtn = {}, devState = {}, alarm = {}, toast = nil,
}

-- ==================== 基础封装 ====================
local function label(parent, x, y, w, h, text, size, color, align)
    return airui.label({
        parent = parent, x = x, y = y, w = w, h = h,
        text = text or "", font_size = size or 16,
        color = color or C.txt, align = align or airui.TEXT_ALIGN_LEFT,
    })
end

local function panel(parent, x, y, w, h, title, en)
    local c = airui.container({
        parent = parent, x = x, y = y, w = w, h = h,
        color = C.panel, radius = 8, border_color = C.border, border_width = 1,
    })
    airui.container({ parent = c, x = 8, y = 9, w = 3, h = 16, color = C.cyan, radius = 2 })
    label(c, 16, 4, w - 116, 22, title, 18, C.txt, airui.TEXT_ALIGN_LEFT)
    if en then
        label(c, w - 96, 6, 84, 18, en, 16, C.txt3, airui.TEXT_ALIGN_RIGHT)
    end
    return c
end

-- 圆点状态色块（用小圆角容器模拟）
local function chip(parent, x, y, w, h, text, color)
    local c = airui.container({
        parent = parent, x = x, y = y, w = w, h = h,
        color = color, color_opacity = 25, radius = 6,
        border_color = color, border_width = 1,
    })
    label(c, 0, (h - 18) / 2, w, 18, text, 16, color, airui.TEXT_ALIGN_CENTER)
    return c
end

-- ==================== 顶栏 + KPI ====================
local function build_top()
    airui.container({ parent = nil, x = 16, y = 12, w = 5, h = 30, color = C.cyan, radius = 2 })
    label(nil, 30, 12, 420, 30, "农业大棚智能控制大屏", 26, C.txt, airui.TEXT_ALIGN_LEFT)
    label(nil, 452, 18, 320, 22, "Agri-Greenhouse Smart Control", 16, C.txt3, airui.TEXT_ALIGN_LEFT)
    R.clock = label(nil, SW - 240, 10, 224, 22, "00:00:00", 18, C.cyan, airui.TEXT_ALIGN_RIGHT)
    R.date  = label(nil, SW - 240, 32, 224, 18, "2026-01-01", 16, C.txt2, airui.TEXT_ALIGN_RIGHT)

    local kpis = {
        { t = "棚内均温",  key = "temp",  color = C.cyan  },
        { t = "棚内均湿",  key = "hum",   color = C.green },
        { t = "CO2浓度",   key = "co2",   color = C.amber },
        { t = "光照强度",  key = "lux",   color = C.cyan  },
        { t = "待处理告警", key = "alarm", color = C.red   },
        { t = "设备运行",  key = "dev",   color = C.green },
    }
    local x, y, w, h, gap = 8, 62, 162, 50, 7
    for i, k in ipairs(kpis) do
        local px = x + (i - 1) * (w + gap)
        local c = airui.container({
            parent = nil, x = px, y = y, w = w, h = h,
            color = C.panel, radius = 8, border_color = C.border, border_width = 1,
        })
        airui.container({ parent = c, x = 0, y = 12, w = 3, h = 26, color = k.color, radius = 2 })
        label(c, 12, 4, w - 22, 16, k.t, 16, C.txt3, airui.TEXT_ALIGN_LEFT)
        R.kpi[k.key] = label(c, 12, 21, w - 22, 26, "-", 22, k.color, airui.TEXT_ALIGN_LEFT)
    end
end

-- ==================== 左列：环境指标 + 土壤墒情 ====================
local function build_env_panel()
    local p = panel(nil, 8, 120, 324, 170, "环境实时指标", "Env")
    local items = {
        { key = "temp", t = "棚内温度", unit = " C",  color = C.cyan  },
        { key = "hum",  t = "空气湿度", unit = " %",  color = C.green },
        { key = "co2",  t = "CO2浓度",  unit = "",    color = C.amber },
        { key = "lux",  t = "光照强度", unit = "klx", color = C.cyan  },
    }
    for i, it in ipairs(items) do
        local cx = 12 + ((i - 1) % 2) * 152
        local cy = 32 + math.floor((i - 1) / 2) * 66
        local c = airui.container({
            parent = p, x = cx, y = cy, w = 148, h = 60,
            color = C.border, color_opacity = 22, radius = 6,
        })
        label(c, 8, 4, 132, 16, it.t, 16, C.txt2, airui.TEXT_ALIGN_LEFT)
        R.env[it.key] = label(c, 8, 24, 132, 30, "-", 24, it.color, airui.TEXT_ALIGN_LEFT)
    end
end

local function build_soil_panel()
    local p = panel(nil, 8, 298, 324, 294, "土壤墒情监测", "Soil")
    -- 表头
    local heads = { { "区域", 8, 96, airui.TEXT_ALIGN_LEFT }, { "含水", 106, 56, airui.TEXT_ALIGN_CENTER },
                    { "pH", 164, 44, airui.TEXT_ALIGN_CENTER }, { "土温", 210, 48, airui.TEXT_ALIGN_CENTER },
                    { "状态", 260, 52, airui.TEXT_ALIGN_CENTER } }
    for _, hd in ipairs(heads) do
        label(p, hd[2], 28, hd[3], 16, hd[1], 16, C.txt3, hd[4])
    end
    for i = 1, 6 do
        local y = 50 + (i - 1) * 40
        airui.container({
            parent = p, x = 6, y = y, w = 312, h = 38,
            color = C.border, color_opacity = 15, radius = 5,
        })
        local r = {}
        r.name = label(p, 12, y + 10, 96, 18, "", 16, C.txt, airui.TEXT_ALIGN_LEFT)
        r.w    = label(p, 106, y + 10, 56, 18, "", 16, C.green, airui.TEXT_ALIGN_CENTER)
        r.ph   = label(p, 164, y + 10, 44, 18, "", 16, C.txt2, airui.TEXT_ALIGN_CENTER)
        r.t    = label(p, 210, y + 10, 48, 18, "", 16, C.txt2, airui.TEXT_ALIGN_CENTER)
        r.st   = label(p, 260, y + 10, 52, 18, "", 16, C.green, airui.TEXT_ALIGN_CENTER)
        R.soil[i] = r
    end
end

-- ==================== 中列：棚区分布 + 设备控制 ====================
local function build_zone_panel()
    local p = panel(nil, 340, 120, 380, 218, "棚区分布总览", "Zones")
    for i = 1, 6 do
        local cx = 8 + ((i - 1) % 3) * 123
        local cy = 30 + math.floor((i - 1) / 3) * 90
        local c = airui.container({
            parent = p, x = cx, y = cy, w = 118, h = 84,
            color = C.cyan, color_opacity = 8, radius = 6,
            border_color = C.border, border_width = 1,
        })
        local r = {}
        r.name = label(c, 6, 3, 106, 16, "", 16, C.txt, airui.TEXT_ALIGN_LEFT)
        r.t    = label(c, 6, 22, 106, 24, "", 20, C.cyan, airui.TEXT_ALIGN_LEFT)
        r.h    = label(c, 6, 46, 106, 18, "", 16, C.green, airui.TEXT_ALIGN_LEFT)
        r.st   = label(c, 6, 64, 106, 16, "", 16, C.green, airui.TEXT_ALIGN_LEFT)
        R.zone[i] = r
    end
end

local function build_dev_panel()
    local p = panel(nil, 340, 346, 380, 246, "设备控制中心", "Devices")
    label(p, 8, 28, 364, 16, "点击按钮开关设备 | 状态实时刷新", 16, C.txt3, airui.TEXT_ALIGN_LEFT)
    for i, d in ipairs(data.devices) do
        local cx = 6 + ((i - 1) % 5) * 72
        local cy = 50 + math.floor((i - 1) / 5) * 92
        local btn = airui.button({
            parent = p, x = cx, y = cy, w = 66, h = 84,
            text = d.name, font_size = 16,
            style = {
                bg_color = C.border, text_color = C.txt, radius = 8,
                bg_opa = 40, border_width = 1, border_color = C.border,
                pressed_bg_color = C.cyan,
            },
            on_click = function()
                d.on = not d.on
                M.refresh_devices()
                M.toast(string.format("%s 已%s", d.name, d.on and "启动" or "停止"))
            end,
        })
        R.devBtn[i] = btn
        -- 状态文字叠在按钮下半部：运行时按钮为青色底，须用深色字保证可读
        R.devState[i] = label(p, cx + 1, cy + 56, 64, 16, d.on and "运行" or "待机", 16,
            d.on and 0x06202E or C.txt3, airui.TEXT_ALIGN_CENTER)
    end
end

-- ==================== 右列：气象 + 水质 + 告警 ====================
local function build_weather_panel()
    local p = panel(nil, 728, 120, 288, 150, "室外气象站", "Weather")
    local items = {
        { k = "outTemp", t = "室外温度", u = " C" }, { k = "outHum", t = "室外湿度", u = " %" },
        { k = "wind", t = "风速", u = "m/s" }, { k = "windDir", t = "风向", u = "" },
    }
    for i, it in ipairs(items) do
        local cx = 8 + ((i - 1) % 2) * 138
        local cy = 30 + math.floor((i - 1) / 2) * 56
        local c = airui.container({
            parent = p, x = cx, y = cy, w = 134, h = 52,
            color = C.border, color_opacity = 22, radius = 6,
        })
        label(c, 8, 3, 118, 16, it.t, 16, C.txt3, airui.TEXT_ALIGN_LEFT)
        R.env[it.k] = label(c, 8, 22, 118, 26, "-", 22, C.cyan, airui.TEXT_ALIGN_LEFT)
    end
    label(p, 8, 126, 272, 16, "", 16, C.txt3, airui.TEXT_ALIGN_LEFT)
    R.env.extra = label(p, 8, 126, 272, 16, "", 16, C.txt3, airui.TEXT_ALIGN_LEFT)
end

local function build_water_panel()
    local p = panel(nil, 728, 278, 288, 126, "灌溉水质", "Water")
    R.env.score = label(p, 10, 32, 78, 40, "92", 34, C.green, airui.TEXT_ALIGN_LEFT)
    label(p, 10, 76, 78, 16, "水质评分", 16, C.txt3, airui.TEXT_ALIGN_LEFT)
    local items = {
        { k = "wt", t = "水温", u = " C" }, { k = "ph", t = "pH", u = "" },
        { k = "ntu", t = "浊度", u = "NTU" }, { k = "level", t = "液位", u = "%" },
    }
    for i, it in ipairs(items) do
        local cx = 96 + ((i - 1) % 2) * 92
        local cy = 30 + math.floor((i - 1) / 2) * 48
        label(p, cx, cy, 88, 14, it.t, 16, C.txt3, airui.TEXT_ALIGN_LEFT)
        R.env[it.k] = label(p, cx, cy + 15, 88, 22, "-", 18, C.txt, airui.TEXT_ALIGN_LEFT)
    end
end

local function build_alarm_panel()
    local p = panel(nil, 728, 412, 288, 180, "智能告警", nil)
    -- 「全清」按钮：一键确认处理全部告警
    airui.button({
        parent = p, x = 224, y = 4, w = 56, h = 24,
        text = "全清", font_size = 16,
        style = {
            bg_color = C.border, text_color = C.txt2, radius = 5,
            bg_opa = 40, border_width = 1, border_color = C.border,
            pressed_bg_color = C.cyan,
        },
        on_click = function()
            for _, a in ipairs(data.alarms) do a.done = true end
            M.refresh_all()
            M.toast("已确认处理全部告警")
        end,
    })
    local sums = { { "紧急", C.red }, { "警告", C.amber }, { "提示", C.cyan }, { "已处理", C.green } }
    R.alarmSum = {}
    for i, s in ipairs(sums) do
        local cx = 8 + (i - 1) * 69
        local c = airui.container({
            parent = p, x = cx, y = 28, w = 64, h = 42,
            color = s[2], color_opacity = 18, radius = 6,
        })
        R.alarmSum[i] = label(c, 0, 2, 64, 22, "0", 18, s[2], airui.TEXT_ALIGN_CENTER)
        label(c, 0, 24, 64, 14, s[1], 16, C.txt3, airui.TEXT_ALIGN_CENTER)
    end
    for i = 1, 3 do
        local y = 74 + (i - 1) * 34
        local c = airui.container({
            parent = p, x = 6, y = y, w = 276, h = 32,
            color = C.border, color_opacity = 15, radius = 5,
        })
        local r = { cur = nil }
        r.dot = airui.container({ parent = c, x = 6, y = 12, w = 8, h = 8, color = C.cyan, radius = 4 })
        r.txt = label(c, 18, 7, 172, 18, "", 16, C.txt2, airui.TEXT_ALIGN_LEFT)
        r.btn = airui.button({
            parent = c, x = 196, y = 4, w = 74, h = 24,
            text = "处理", font_size = 16,
            style = {
                bg_color = C.red, text_color = 0xFFFFFF, radius = 5,
                bg_opa = 55, border_width = 1, border_color = C.red,
                pressed_bg_color = C.cyan,
            },
            on_click = function()
                local a = r.cur
                if not a then return end
                a.done = true
                M.refresh_all()
                M.toast("已确认处理: " .. a.src)
            end,
        })
        R.alarm[i] = r
    end
end

-- ==================== toast ====================
local toastToken = 0

local function build_toast()
    R.toastBox = airui.container({
        parent = nil, x = (SW - 360) / 2, y = 66, w = 360, h = 40,
        color = 0x0A2038, radius = 8, border_color = C.cyan, border_width = 1,
    })
    R.toast = label(R.toastBox, 0, 10, 360, 22, "", 18, C.cyan, airui.TEXT_ALIGN_CENTER)
    -- 用 set_hidden 隐藏：移出画布的盒子在模拟器里不会被裁剪，会残留成右侧“幽灵提示”
    R.toastBox:set_hidden(true)
end

function M.toast(msg)
    if not R.toast then return end
    toastToken = toastToken + 1
    local tk = toastToken
    R.toast:set_text(msg)
    R.toastBox:set_hidden(false)
    sys.timerStart(function()
        -- 仅当没有更新的 toast 时才隐藏，避免连点时旧定时器提前关掉新提示
        if tk == toastToken then R.toastBox:set_hidden(true) end
    end, 2200)
end

-- ==================== 数据刷新 ====================
local function zone_status(z)
    if z.t > z.tOpt[2] + 1 then return "温度偏高", C.amber end
    if z.t < z.tOpt[1] then return "温度偏低", C.amber end
    if z.h > z.hOpt[2] then return "湿度偏高", C.amber end
    if z.h < z.hOpt[1] then return "湿度偏低", C.red end
    return "环境适宜", C.green
end

local function soil_status(s)
    if s.w < 30 then return "缺墒", C.red end
    if s.w < 42 then return "偏干", C.amber end
    return "适宜", C.green
end

function M.refresh_devices()
    for i, d in ipairs(data.devices) do
        local btn, st = R.devBtn[i], R.devState[i]
        if btn then
            btn:set_style({
                bg_color = d.on and C.cyan or C.border,
                text_color = d.on and 0x06202E or C.txt,
                bg_opa = d.on and 255 or 40,
                border_width = 1,
                border_color = d.on and C.cyan or C.border,
            })
        end
        if st then
            st:set_text(d.on and "运行" or "待机")
            st:set_color(d.on and 0x06202E or C.txt3)
        end
    end
    R.kpi.dev:set_text(data.running_count() .. "/10")
end

function M.refresh_all()
    local e = data.env
    -- KPI
    R.kpi.temp:set_text(string.format("%.1fC", e.temp))
    R.kpi.hum:set_text(string.format("%d%%", e.hum))
    R.kpi.co2:set_text(string.format("%dppm", e.co2))
    R.kpi.lux:set_text(string.format("%.1fklx", e.lux))
    local c = data.alarm_counts()
    R.kpi.alarm:set_text(string.format("%d 条", c[1] + c[2] + c[3]))
    R.kpi.dev:set_text(data.running_count() .. "/10")
    -- 环境指标
    R.env.temp:set_text(string.format("%.1fC", e.temp))
    R.env.hum:set_text(string.format("%d%%", e.hum))
    R.env.co2:set_text(string.format("%d", e.co2))
    R.env.lux:set_text(string.format("%.1fklx", e.lux))
    -- 气象
    R.env.outTemp:set_text(string.format("%.1fC", e.outTemp))
    R.env.outHum:set_text(string.format("%d%%", e.outHum))
    R.env.wind:set_text(string.format("%.1fm/s", e.wind))
    R.env.windDir:set_text(e.windDir)
    R.env.extra:set_text(string.format("气压%d 降雨%.1fmm UV%d", e.pressure, e.rain, e.uv))
    -- 水质
    local w = data.water
    R.env.score:set_text(tostring(w.score))
    R.env.wt:set_text(string.format("%.1fC", w.wt))
    R.env.ph:set_text(string.format("%.1f", w.ph))
    R.env.ntu:set_text(string.format("%.1f", w.ntu))
    R.env.level:set_text(string.format("%d%%", w.level))
    -- 棚区卡片
    for i, z in ipairs(data.zones) do
        local r = R.zone[i]
        if r then
            local st, stColor = zone_status(z)
            r.name:set_text(string.format("%s %s", z.id, z.name))
            r.t:set_text(string.format("%.1fC", z.t))
            r.h:set_text(string.format("%d%%", z.h))
            r.st:set_text(st)
            r.st:set_color(stColor)
        end
    end
    -- 土壤表
    for i, s in ipairs(data.soil) do
        local r = R.soil[i]
        if r then
            local st, stColor = soil_status(s)
            r.name:set_text(s.z)
            r.w:set_text(string.format("%d%%", s.w))
            r.ph:set_text(string.format("%.1f", s.ph))
            r.t:set_text(string.format("%.1f", s.t))
            r.st:set_text(st)
            r.st:set_color(stColor)
        end
    end
    -- 告警
    for i = 1, 3 do R.alarmSum[i]:set_text(tostring(c[i])) end
    R.alarmSum[4]:set_text(tostring(c[4]))
    -- 按优先级取前 3 条未处理告警，绑定到行内「处理」按钮
    local pending = {}
    for _, a in ipairs(data.alarms) do
        if not a.done then pending[#pending + 1] = a end
    end
    table.sort(pending, function(x, y) return x.lv < y.lv end)
    for i = 1, 3 do
        local r, a = R.alarm[i], pending[i]
        r.cur = a
        if a then
            local col = ({ C.red, C.amber, C.cyan })[a.lv]
            r.dot:set_hidden(false)
            r.dot:set_color(col, 255)
            r.txt:set_text(string.format("%s %s", a.src, a.msg))
            r.txt:set_color(C.txt2)
            r.btn:set_text("处理")
            r.btn:set_style({
                bg_color = col, text_color = 0xFFFFFF, bg_opa = 55,
                border_width = 1, border_color = col,
            })
        else
            r.dot:set_hidden(true)
            r.txt:set_text("暂无待处理告警")
            r.txt:set_color(C.txt3)
            r.btn:set_text("")
            r.btn:set_style({
                bg_color = C.border, text_color = C.txt3, bg_opa = 30,
                border_width = 1, border_color = C.border,
            })
        end
    end
end

-- ==================== 构建入口 ====================
--[[
构建整屏 UI（在 exd 显示初始化 + airui.init + font_load 之后调用）
]]
function M.build()
    -- 深色全屏背景
    airui.shape({
        x = 0, y = 0, w = SW, h = SH,
        items = {
            { type = "rect", x = 0, y = 0, w = SW, h = SH, fill = true,
              fill_color = C.bg, color = C.bg },
        },
    })
    build_top()
    build_env_panel()
    build_soil_panel()
    build_zone_panel()
    build_dev_panel()
    build_weather_panel()
    build_water_panel()
    build_alarm_panel()
    build_toast()
    M.refresh_all()
    M.refresh_devices()
end

-- 实时时钟刷新（由 main 的定时器驱动）
function M.tick_clock()
    local t = os.date("*t")
    R.clock:set_text(string.format("%02d:%02d:%02d", t.hour, t.min, t.sec))
    local week = { "日", "一", "二", "三", "四", "五", "六" }
    R.date:set_text(string.format("%04d-%02d-%02d 星期%s", t.year, t.month, t.day, week[t.wday]))
end

return M
