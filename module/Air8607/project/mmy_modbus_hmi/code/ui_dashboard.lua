--[[
@module  ui_dashboard
@summary Modbus 中控大屏 - 总览页
@version 2.0.0
@date    2026.10.25

实时趋势波形卡改用 airui 原生 chart（airui.chart，LVGL lv_chart）：
网格、X 轴刻度标签、渐变填充由 C 层绘制；原生 chart 没有阈值线，
仍叠一层 shape 画虚线与当前点标记。

纵轴的两个坑（airui 当前的限制）：
  1、没有暴露 set_range，绘图用的 y_min/y_max 只能在创建时定一次，之后改不了；
     set_y_axis 只改标签、不动绘图映射。所以"量程随数据自适应"只能靠
     每帧把数据按可视范围归一化到 0~100 来实现。
  2、轴标签是 snprintf("%ld")，只会原样打印喂进去的整数，没有缩放/小数能力，
     显示不了工程量。所以关掉原生 y_axis，改用一排 label 按真实值标注。

布局（1024x600）：
  顶栏 0..56      标题 + 传输方式 + 在线数 + 时间 + 报警指示
  左列 x12 w232   5 个从站设备卡（点击进详情）
  中列 x252 w496  4 个关键指标卡(2x2) + 实时趋势波形（可切换通道）
  右列 x756 w256  通讯统计 + 最新报警
  底栏 y548       页面导航
]]
local conf = require "conf"
local theme = require "theme"
local chart = require "chart"
local mbdev = require "mbdev"
local mbmaster = require "mbmaster"

local M = {}
local C = theme.C
local SW, SH = conf.W, conf.H
local NAV_Y = 548

local CAP = mbdev.hist_n()        -- 图表固定点数
local NONE = 2147483647           -- LV_CHART_POINT_NONE：该点不绘制
local AXIS_L_W = 40               -- 左侧 Y 轴刻度标签宽度
local CH_X, CH_Y = 46, 42         -- chart 在卡内的位置（左侧留 46 给 Y 轴刻度标签）
local CH_W, CH_H = 434, 162       -- 下方留 30 给 X 轴刻度标签、再下是量程说明
local NY, NX = 4, 5               -- Y 方向格数、X 轴刻度标签个数

local root = nil
local app_ref = nil
local wave_key = "temp"

local timeLabel, dateLabel, transLabel, onlineLabel, alarmDot, alarmCount
local devRows = {}
local kpiCards = {}
local chips = {}
local waveChart, waveOverlay, waveRangeLabel
local waveYLabels = {}            -- 左侧工程量刻度
local commRows = {}
local alarmRows = {}

-- ==================== 工具 ====================
local function dev_key_point(dev)
    for _, pt in ipairs(dev.points) do
        if pt.dtype ~= "bool" and not pt.bits then return pt end
    end
    return dev.points[1]
end

local function fmt_addr(pt)
    if pt.fc == 0x01 then return string.format("0%04d", pt.addr + 1) end
    if pt.fc == 0x02 then return string.format("1%04d", pt.addr + 1) end
    if pt.fc == 0x03 then return string.format("4%04d", pt.addr + 1) end
    return string.format("3%04d", pt.addr + 1)
end

-- ==================== 顶栏 ====================
local function build_topbar()
    theme.box(root, 0, 0, SW, 56, 0x0A1420)
    theme.accent_bar(root, 0, 54, SW, C.line)

    theme.dot(root, 22, 20, 8, C.cyan)
    theme.label(root, 44, 10, 380, 26, conf.name, 21, C.ink)
    theme.label(root, 44, 34, 380, 16, conf.subtitle, 11, C.ink3)

    transLabel = theme.label(root, 400, 18, 190, 22, "", 13, C.cyan)
    onlineLabel = theme.label(root, 590, 18, 130, 22, "", 13, C.ink2)

    timeLabel = theme.label(root, 700, 8, 168, 26, "", 19, C.ink, airui.TEXT_ALIGN_RIGHT)
    dateLabel = theme.label(root, 700, 34, 168, 16, "", 11, C.ink3, airui.TEXT_ALIGN_RIGHT)

    alarmDot = theme.box(root, 884, 20, 14, 14, C.ink3, 7)
    theme.label(root, 904, 16, 36, 22, "报警", 13, C.ink2)
    alarmCount = theme.label(root, 940, 14, 60, 24, "0", 17, C.ink, airui.TEXT_ALIGN_RIGHT)
end

-- ==================== 设备卡 ====================
local function build_device_card(i, dev)
    local y = 60 + (i - 1) * 96
    local kp = dev_key_point(dev)
    local card = theme.card(root, 12, y, 232, 88)
    card:set_on_click(function()
        theme.defer(function() if app_ref then app_ref.open_device(dev.id) end end)
    end)
    theme.accent_bar(card, 12, 0, 42, dev.color)

    theme.label(card, 12, 8, 146, 20, dev.name, 15, C.ink)
    theme.label(card, 12, 26, 146, 16, string.format("#%d · %s", dev.id, dev.model), 11, C.ink3)
    local pill, pillText = theme.pill(card, 172, 8, 48, 18, "在线", C.ok, 11)
    local val = theme.label(card, 12, 44, 130, 26, "--", 21, kp.color or C.cyan)
    local vn = theme.label(card, 12, 70, 130, 14, kp.name, 11, C.ink3)
    local al = theme.label(card, 148, 48, 76, 18, "", 11, C.ink3, airui.TEXT_ALIGN_RIGHT)

    devRows[i] = { card = card, pill = pill, pillText = pillText, val = val,
                   kp = kp, alarm = al, dev = dev, vn = vn }
end

-- ==================== 关键指标卡 ====================
local function build_kpi(i, key)
    local pt = mbdev.point(key)
    local col = (i - 1) % 2
    local row = math.floor((i - 1) / 2)
    local x = 252 + col * 252
    local y = 60 + row * 112

    local card = theme.card(root, x, y, 244, 104)
    card:set_on_click(function()
        theme.defer(function() if app_ref then app_ref.open_device(pt.dev_id) end end)
    end)
    theme.accent_bar(card, 14, 0, 44, pt.color)
    theme.label(card, 14, 10, 150, 20, pt.name, 14, C.ink2)
    local pill, pillText = theme.pill(card, 188, 10, 44, 18, "正常", C.ok, 11)
    local value = theme.label(card, 14, 32, 150, 34, "--", 26, C.ink)
    theme.label(card, 158, 42, 72, 22, pt.unit, 13, C.ink3)
    local spark = theme.shape({ parent = card, x = 14, y = 74, w = 216, h = 22, items = {} })

    kpiCards[key] = { pill = pill, pillText = pillText, value = value, spark = spark, pt = pt }
end

-- ==================== 趋势波形 ====================
local function refresh_chips()
    for i, b in ipairs(chips) do
        if b then
            local key = mbdev.KPI[i]
            local sel = (key == wave_key)
            local pt = mbdev.point(key)
            b:set_style({
                bg_color = sel and (pt.color or C.cyan) or C.panel2,
                text_color = sel and 0x05141C or C.ink2,
                border_color = sel and (pt.color or C.cyan) or C.line2,
                radius = 8,
            })
        end
    end
end

local function build_wave_card()
    local card = theme.card(root, 252, 284, 496, 260)
    theme.accent_bar(card, 14, 0, 44, C.cyan)
    theme.label(card, 16, 10, 100, 22, "实时趋势", 16, C.ink)

    for i, key in ipairs(mbdev.KPI) do
        local pt = mbdev.point(key)
        chips[i] = theme.button(card, 100 + (i - 1) * 96, 8, 90, 26, pt.name, 12,
            C.panel2, C.ink2, function()
                theme.defer(function()
                    wave_key = key
                    refresh_chips()
                    M.refresh()
                end)
            end, 8)
    end

    -- 曲线本体：网格 / 坐标轴刻度与标签 / 渐变填充全部交给 C 层
    local span_s = math.floor((CAP - 1) * conf.comm.poll_interval_ms / 1000 + 0.5)
    waveChart = airui.chart({
        parent = card, x = CH_X, y = CH_Y, w = CH_W, h = CH_H,
        type = "line",
        update_mode = "shift",
        y_min = 0, y_max = 100,          -- 归一化百分比，固定不变（理由见下）
        point_count = CAP,
        line_color = C.cyan, line_width = 2, point_radius = 0,
        bg_opa = 0, border_width = 0,
        hdiv = NY + 1, vdiv = NX,        -- 水平格数=Y 刻度数，垂直格数=X 刻度数
        grid_color = C.line, grid_opa = 70,
        fill = { enable = true, opa_start = 60, opa_end = 0 },
        x_axis = { enable = true, min = -span_s, max = 0, ticks = NX, unit = "s" },
    })
    -- 不启用原生 y_axis：airui 的轴标签是 snprintf("%ld")，只能原样打印喂进去的整数，
    -- 没有缩放能力。曲线数据是归一化后的 0~100，直接显示就成了"0/25/50/75/100"，
    -- 工程量刻度改由下面这排 label 按真实值标注。
    for k = 0, NY do
        waveYLabels[k + 1] = theme.label(card, 4, CH_Y + math.floor(CH_H * k / NY) - 7,
            AXIS_L_W, 14, "", 11, C.ink3, airui.TEXT_ALIGN_RIGHT)
    end

    -- 阈值虚线 + 当前点标记：原生 chart 没有，叠一层 shape
    waveOverlay = theme.shape({ parent = card, x = CH_X, y = CH_Y, w = CH_W, h = CH_H, items = {} })
    waveRangeLabel = theme.label(card, 16, 234, 464, 18, "", 11, C.ink3)
end

-- 工程量数组 -> 归一化整数数组（0~100，右对齐，未采满的左侧填空点）
--
-- 为什么归一化：airui 没有暴露 set_range，绘图用的 y_min/y_max 只能在创建时定一次，
-- 之后改不了。要"量程随数据自适应"，只能每帧在 Lua 侧按可视范围把数据折算成 0~100。
local function wave_buf(hist, lo, hi)
    local n = #hist
    local buf = {}
    for i = 1, CAP do buf[i] = NONE end
    if n < 1 then return buf end
    local off = CAP - n
    local span = hi - lo
    if span < 0.000001 then span = 1 end
    for j = 1, n do
        local k = (hist[j] - lo) / span
        if k < 0 then k = 0 end
        if k > 1 then k = 1 end
        buf[off + j] = math.floor(k * 100 + 0.5)
    end
    return buf
end

-- 阈值虚线 + 当前点（原生 chart 没有阈值线，只能叠一层）
local function update_wave_overlay(pt, hist, lo, hi)
    local items = {}
    local function pyv(v)
        if v == nil then return nil end
        local k = (v - lo) / (hi - lo)
        if k < 0 or k > 1 then return nil end
        return CH_H * (1 - k)
    end
    local function hline(v, col, op)
        local y = pyv(v)
        if y then
            items[#items + 1] = { type = "line", x1 = 0, y1 = y, x2 = CH_W, y2 = y,
                                  color = col, width = 1, dash_width = 6, dash_gap = 4,
                                  opacity = op }
        end
    end
    hline(pt.dlo, C.red, 170)
    hline(pt.dhi, C.red, 170)
    hline(pt.lo, C.amber, 150)
    hline(pt.hi, C.amber, 150)

    local n = #hist
    if n > 0 then
        local y = pyv(hist[n])
        if y then
            local col = pt.color or C.cyan
            items[#items + 1] = { type = "circle", cx = CH_W, cy = y, r = 4,
                                  fill = true, fill_color = col }
            items[#items + 1] = { type = "circle", cx = CH_W, cy = y, r = 7,
                                  color = col, width = 1, opacity = 160 }
        end
    end
    waveOverlay:set_items(items)
end

-- ==================== 通讯统计 ====================
local COMM_DEF = {
    { "ok",        "成功帧" },
    { "fail",      "失败帧" },
    { "timeout",   "超时" },
    { "crc",       "CRC 错误" },
    { "exception", "异常响应" },
    { "avg",       "平均耗时" },
    { "cycle",     "轮询轮次" },
}

local function build_comm_card()
    local c = theme.card(root, 756, 60, 256, 248)
    theme.accent_bar(c, 16, 0, 46, C.green)
    theme.label(c, 16, 12, 180, 22, "通讯统计", 16, C.ink)
    for i, r in ipairs(COMM_DEF) do
        local y = 44 + (i - 1) * 26
        theme.label(c, 16, y, 130, 20, r[2], 13, C.ink3)
        commRows[r[1]] = theme.label(c, 150, y, 90, 20, "0", 15, C.ink, airui.TEXT_ALIGN_RIGHT)
    end
end

-- ==================== 最新报警 ====================
local function build_alarm_card()
    local a = theme.card(root, 756, 316, 256, 228)
    theme.accent_bar(a, 16, 0, 46, C.red)
    theme.label(a, 16, 12, 180, 22, "最新报警", 16, C.ink)
    for i = 1, 5 do
        local y = 42 + (i - 1) * 36
        local t = theme.label(a, 16, y, 56, 16, "", 11, C.ink3)
        local x = theme.label(a, 76, y, 164, 16, "", 12, C.ink2)
        alarmRows[i] = { time = t, text = x }
    end
end

-- ==================== 构建 ====================
function M.build(app)
    M.destroy()
    app_ref = app

    root = airui.container({
        parent = nil, x = 0, y = 0, w = SW, h = SH,
        color = C.bg1, radius = 0, border_width = 0,
    })
    theme.gradient(root, 0, 0, SW, SH, C.bg1, C.bg2, 12)

    build_topbar()
    for i, dev in ipairs(mbdev.devices()) do build_device_card(i, dev) end
    for i, key in ipairs(mbdev.KPI) do build_kpi(i, key) end
    build_wave_card()
    build_comm_card()
    build_alarm_card()

    theme.navbar(root, "dashboard", NAV_Y, function(id)
        if app_ref then app_ref.show(id) end
    end)

    refresh_chips()
    M.refresh()
end

-- ==================== 刷新 ====================
function M.refresh()
    if not root then return end

    local t = os.date("*t")
    local week = { "日", "一", "二", "三", "四", "五", "六" }
    if timeLabel then timeLabel:set_text(string.format("%02d:%02d", t.hour, t.min)) end
    if dateLabel then
        dateLabel:set_text(string.format("%04d-%02d-%02d 周%s", t.year, t.month, t.day, week[t.wday] or ""))
    end
    if transLabel then
        transLabel:set_text(mbmaster.transport_name() .. " · " .. mbmaster.transport_desc())
    end
    if onlineLabel then
        onlineLabel:set_text(string.format("在线 %d/%d", mbdev.online_count(), #mbdev.devices()))
        onlineLabel:set_color(mbdev.online_count() == #mbdev.devices() and C.ok or C.warn)
    end
    if alarmDot then
        alarmDot:set_color(mbdev.any_alarm() and
            ((mbmaster.cycle() % 2 == 0) and C.red or C.danger) or C.ink3)
    end

    local act = 0
    for _, a in ipairs(mbdev.alarms()) do
        if a.level == "danger" or a.level == "warn" then act = act + 1 end
    end
    if alarmCount then
        alarmCount:set_text(tostring(act))
        alarmCount:set_color(act > 0 and C.red or C.ink)
    end

    -- 设备卡
    for _, r in ipairs(devRows) do
        local dev = r.dev
        local online = mbdev.online(dev.id)
        local col = online and C.ok or C.off
        r.pill:set_color(col)
        r.pillText:set_text(online and "在线" or "离线")
        r.pillText:set_color(col)
        local v = mbdev.get(r.kp.key)
        if r.kp.dtype == "bool" then
            r.val:set_text(mbdev.fmt(r.kp.key, v))
        else
            r.val:set_text(mbdev.fmt(r.kp.key, v) .. r.kp.unit)
        end
        local na = mbdev.dev_alarm_count(dev.id)
        r.alarm:set_text(na > 0 and (na .. " 项告警") or "")
        r.alarm:set_color(na > 0 and C.warn or C.ink3)
    end

    -- 关键指标卡
    for key, c in pairs(kpiCards) do
        local st = mbdev.status(key)
        local col = theme.state_color(st)
        c.value:set_text(mbdev.fmt(key, mbdev.get(key)))
        c.pill:set_color(col)
        c.pillText:set_text(theme.state_text(st))
        c.pillText:set_color(col)
        c.spark:set_items(chart.spark(mbdev.history(key), 216, 22, col))
    end

    -- 波形
    if waveChart then
        local pt = mbdev.point(wave_key)
        local hist = mbdev.history(wave_key)
        local lo, hi = chart.vis_range(hist, pt)
        waveChart:set_line_color(1, pt.color or C.cyan)
        waveChart:set_values(1, wave_buf(hist, lo, hi))
        update_wave_overlay(pt, hist, lo, hi)

        -- 左侧工程量刻度：曲线是归一化值，这里按真实工程量标注
        local dec = pt.dec or 1
        for k = 0, NY do
            if waveYLabels[k + 1] then
                waveYLabels[k + 1]:set_text(string.format("%." .. dec .. "f",
                    hi - (hi - lo) * (k / NY)))
                waveYLabels[k + 1]:set_color(pt.color or C.cyan)
            end
        end

        if waveRangeLabel then
            waveRangeLabel:set_text(string.format("%s  当前 %s%s   可视 %.2f ~ %.2f   阈值 %s ~ %s   采样 %d 点",
                fmt_addr(pt), mbdev.fmt(wave_key, mbdev.get(wave_key)), pt.unit, lo, hi,
                pt.lo and tostring(pt.lo) or "—", pt.hi and tostring(pt.hi) or "—",
                #hist))
        end
    end

    -- 通讯统计
    local s = mbmaster.stats()
    if commRows.ok then commRows.ok:set_text(tostring(s.ok)) end
    if commRows.fail then
        commRows.fail:set_text(tostring(s.fail))
        commRows.fail:set_color(s.fail > 0 and C.warn or C.ink)
    end
    if commRows.timeout then
        commRows.timeout:set_text(tostring(s.timeout))
        commRows.timeout:set_color(s.timeout > 0 and C.warn or C.ink)
    end
    if commRows.crc then
        commRows.crc:set_text(tostring(s.crc))
        commRows.crc:set_color(s.crc > 0 and C.danger or C.ink)
    end
    if commRows.exception then
        commRows.exception:set_text(tostring(s.exception))
        commRows.exception:set_color(s.exception > 0 and C.warn or C.ink)
    end
    if commRows.avg then commRows.avg:set_text(tostring(s.avg_ms) .. " ms") end
    if commRows.cycle then commRows.cycle:set_text(tostring(s.cycles)) end

    -- 报警
    local alarms = mbdev.alarms()
    for i = 1, 5 do
        local row = alarmRows[i]
        if row then
            local a = alarms[i]
            if a then
                row.time:set_text(a.time)
                row.text:set_text(a.text)
                row.text:set_color(a.level == "danger" and C.danger or
                                   a.level == "warn" and C.warn or C.ok)
            else
                row.time:set_text("")
                row.text:set_text("")
            end
        end
    end
end

function M.destroy()
    if root then
        pcall(function() root:destroy() end)
        root = nil
    end
    app_ref = nil
    devRows, kpiCards, chips, commRows, alarmRows = {}, {}, {}, {}, {}
    timeLabel, dateLabel, transLabel, onlineLabel, alarmDot, alarmCount = nil, nil, nil, nil, nil, nil
    waveChart, waveOverlay, waveRangeLabel = nil, nil, nil
    waveYLabels = {}
end

return M
