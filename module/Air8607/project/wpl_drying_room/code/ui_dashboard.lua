--[[
@module  ui_dashboard
@summary 烘干室智能控制主控大屏（暖色科技风，三列布局）
@version 1.0
@date    2026.10.24

布局（1024x600）：
  顶栏 0..60：标题 + 设置 + 时间 + 报警
  左列 x16  w300：坚果选择（6 种 + 推荐温度/时长）、烘干进度、设备控制
  中列 x332 w360：温度主波形（可点击）、含氧量/CO/湿度/含水率 2x2
  右列 x708 w300：水质(pH/浊度)、CO2、报警记录、批次环境
]]
local conf = require "conf"
local theme = require "theme"
local sim = require "sim"

local M = {}
local C = theme.C
local SW, SH = conf.W, conf.H

local root = nil
local app_ref = nil

-- 顶栏
local timeLabel, dateLabel, alarmDot, alarmText

-- 坚果卡
local nutIconShape, nutName, nutTempLabel, nutHoursLabel
local nutBtns = {}

-- 进度
local progSegs = {}
local progPct, progTime

-- 设备
local devBtns = {}
local DEV_DEF = {
    { key = "heater", name = "加热器" },
    { key = "fan",    name = "循环风机" },
    { key = "vent",   name = "排湿阀" },
    { key = "mute",   name = "报警消音" },
}

-- 温度波形
local tempValue, tempTargetLabel, tempPill, tempPillText, tempWave, tempSub

-- 指标卡
local cards = {}

-- 水质
local phValue, phPill, turbValue, turbPill

-- CO2
local co2Value, co2Pill, co2Spark

-- 报警
local alarmRows = {}

-- 批次环境
local batchEnv

-- ==================== 图形工具 ====================
local function spark_items(hist, w, h, color, range)
    local n = #hist
    if n < 2 then return {} end
    local mn, mx
    if range then
        mn, mx = range[1], range[2]
    else
        mn, mx = hist[1], hist[1]
        for _, v in ipairs(hist) do
            if v < mn then mn = v end
            if v > mx then mx = v end
        end
    end
    if mx - mn < 0.001 then mx = mn + 1 end
    local pad = 2
    local px = function(i) return pad + (w - 2 * pad) * (i - 1) / (n - 1) end
    local py = function(v) return pad + (h - 2 * pad) * (1 - (v - mn) / (mx - mn)) end
    local items = {}
    for i = 1, n - 1 do
        items[#items + 1] = {
            type = "line",
            x1 = px(i), y1 = py(hist[i]),
            x2 = px(i + 1), y2 = py(hist[i + 1]),
            color = color, width = 2,
        }
    end
    return items
end

-- 温度波形：含推荐区间上下限（虚线）+ 目标线；y 轴按数据 + 阈值自适应
local function temp_wave_items(hist, w, h)
    local n = #hist
    if n < 2 then return {} end
    local lo, hi = sim.threshold("temp")
    local t = sim.target_temp()

    local dmin, dmax = hist[1], hist[1]
    for i = 2, n do
        local v = hist[i]
        if v < dmin then dmin = v end
        if v > dmax then dmax = v end
    end
    -- 纯按数据起伏自适应（不再强制包含阈值），保证波形起伏明显
    local span = dmax - dmin
    local min_span, max_span = 2, 15
    local mn, mx
    if span > max_span then
        local c = hist[n]
        mn, mx = c - max_span / 2, c + max_span / 2
    elseif span < min_span then
        local c = (dmax + dmin) / 2
        mn, mx = c - min_span / 2, c + min_span / 2
    else
        local p = span * 0.15
        mn, mx = dmin - p, dmax + p
    end

    local pad = 3
    local area = h - 2 * pad
    local function px(i) return pad + (w - 2 * pad) * (i - 1) / (n - 1) end
    local function py(v)
        local k = (v - mn) / (mx - mn)
        if k < 0 then k = 0 end
        if k > 1 then k = 1 end
        return pad + area * (1 - k)
    end

    local items = {}

    -- 面积填充（曲线下方渐变），让波形有“量感”
    local segs = n - 1
    if segs > 36 then segs = 36 end
    for s = 1, segs do
        local i0 = math.floor((s - 1) * (n - 1) / segs) + 1
        local i1 = math.floor(s * (n - 1) / segs) + 1
        if i0 < 1 then i0 = 1 end
        if i1 > n then i1 = n end
        local y = py(hist[i1])
        local x0 = px(i0)
        local x1 = px(i1)
        local ww = x1 - x0
        if ww < 1 then ww = 1 end
        local hh = h - y
        if hh > 0 then
            local op = 30 + math.floor(45 * (y / h))
            items[#items + 1] = { type = "rect", x = x0, y = y, w = ww, h = hh,
                                  fill = true, fill_color = C.amber, fill_opacity = op }
        end
    end

    if lo and lo >= mn and lo <= mx then
        items[#items + 1] = { type = "line", x1 = 0, y1 = py(lo), x2 = w, y2 = py(lo),
                              color = C.gold, width = 1, dash_width = 5, dash_gap = 4, opacity = 160 }
    end
    if hi and hi >= mn and hi <= mx then
        items[#items + 1] = { type = "line", x1 = 0, y1 = py(hi), x2 = w, y2 = py(hi),
                              color = C.gold, width = 1, dash_width = 5, dash_gap = 4, opacity = 160 }
    end
    if t then
        items[#items + 1] = { type = "line", x1 = 0, y1 = py(t), x2 = w, y2 = py(t),
                              color = C.orange, width = 1, opacity = 170 }
    end
    for i = 1, n - 1 do
        items[#items + 1] = { type = "line", x1 = px(i), y1 = py(hist[i]), x2 = px(i + 1), y2 = py(hist[i + 1]),
                              color = C.amber, width = 2 }
    end
    for i = 1, n, 5 do
        items[#items + 1] = { type = "circle", cx = px(i), cy = py(hist[i]), r = 2,
                              fill = true, fill_color = C.amber }
    end
    return items
end

-- 坚果剪影（不同种类不同形状）
local function nut_items(kind, color, cx, cy, s)
    local items = {}
    if kind == "peanut" then
        items[1] = { type = "ellipse", cx = cx, cy = cy - 8 * s, rx = 11 * s, ry = 13 * s, fill = true, fill_color = color }
        items[2] = { type = "ellipse", cx = cx, cy = cy + 8 * s, rx = 11 * s, ry = 13 * s, fill = true, fill_color = color }
    elseif kind == "cashew" then
        items[1] = { type = "arc", cx = cx, cy = cy, r = 18 * s, start_angle = 40, end_angle = 320,
                     color = color, width = 10 * s, rounded = true }
    elseif kind == "almond" then
        items[1] = { type = "ellipse", cx = cx, cy = cy, rx = 10 * s, ry = 18 * s, fill = true, fill_color = color }
        items[2] = { type = "line", x1 = cx, y1 = cy + 15 * s, x2 = cx, y2 = cy + 21 * s, color = color, width = 3 }
    elseif kind == "hazel" then
        items[1] = { type = "circle", cx = cx, cy = cy, r = 16 * s, fill = true, fill_color = color }
        items[2] = { type = "line", x1 = cx - 8 * s, y1 = cy + 13 * s, x2 = cx + 8 * s, y2 = cy + 13 * s,
                     color = 0x2E1E13, width = 3 }
    elseif kind == "pistachio" then
        items[1] = { type = "ellipse", cx = cx, cy = cy, rx = 11 * s, ry = 17 * s, fill = true, fill_color = color }
        items[2] = { type = "line", x1 = cx, y1 = cy - 14 * s, x2 = cx, y2 = cy + 14 * s,
                     color = 0x2E1E13, width = 2, dash_width = 3, dash_gap = 2 }
    else -- walnut
        items[1] = { type = "ellipse", cx = cx, cy = cy, rx = 15 * s, ry = 17 * s, fill = true, fill_color = color }
        items[2] = { type = "line", x1 = cx, y1 = cy - 15 * s, x2 = cx, y2 = cy + 15 * s, color = 0x2E1E13, width = 2 }
        items[3] = { type = "line", x1 = cx - 10 * s, y1 = cy - 9 * s, x2 = cx - 3 * s, y2 = cy,
                     color = 0x2E1E13, width = 1.5 }
        items[4] = { type = "line", x1 = cx + 10 * s, y1 = cy - 9 * s, x2 = cx + 3 * s, y2 = cy,
                     color = 0x2E1E13, width = 1.5 }
        items[5] = { type = "line", x1 = cx - 10 * s, y1 = cy + 9 * s, x2 = cx - 3 * s, y2 = cy,
                     color = 0x2E1E13, width = 1.5 }
        items[6] = { type = "line", x1 = cx + 10 * s, y1 = cy + 9 * s, x2 = cx + 3 * s, y2 = cy,
                     color = 0x2E1E13, width = 1.5 }
    end
    return items
end

local function dot(parent, x, y, r, color)
    return theme.box(parent, x, y, r * 2, r * 2, color, r)
end

-- ==================== 顶栏 ====================
local function build_topbar()
    theme.gradient(root, 0, 0, SW, 60, 0x1C1209, 0x2A1A10, 6)
    dot(root, 20, 18, 12, C.amber)
    theme.label(root, 52, 12, 400, 36, conf.name, 24, C.ink)

    theme.button(root, 470, 14, 80, 32, "设置", 14, C.panel2, C.ink2, function()
        theme.defer(function()
            if app_ref then app_ref.open_settings() end
        end)
    end, 8)

    timeLabel = theme.label(root, 600, 12, 240, 26, "", 18, C.ink2, airui.TEXT_ALIGN_RIGHT)
    dateLabel = theme.label(root, 600, 38, 240, 18, "", 12, C.ink3, airui.TEXT_ALIGN_RIGHT)

    alarmDot = theme.box(root, 900, 18, 14, 14, C.ink3, 7)
    theme.label(root, 922, 14, 40, 22, "报警", 15, C.ink2)
    alarmText = theme.label(root, 962, 14, 46, 22, "0", 18, C.ink)
end

-- ==================== 坚果选择 ====================
local function refresh_nut_btns()
    for i, b in ipairs(nutBtns) do
        local sel = (i == sim.nut_index())
        b:set_style({
            bg_color = sel and C.amber or C.panel2,
            text_color = sel and 0x1A120C or C.ink2,
            border_color = sel and C.amber or C.line,
            radius = 8,
        })
    end
end

local function build_nut_card()
    local card = theme.card(root, 16, 72, 300, 300)
    theme.accent_bar(card, 16, 0, 50, C.amber)
    theme.label(card, 16, 14, 200, 22, "坚果种类", 16, C.ink)

    nutIconShape = theme.shape({ parent = card, x = 12, y = 46, w = 70, h = 70, items = {} })
    nutName = theme.label(card, 92, 50, 190, 30, "", 22, C.ink)
    nutTempLabel = theme.label(card, 92, 84, 190, 22, "", 15, C.amber)
    nutHoursLabel = theme.label(card, 92, 110, 190, 22, "", 14, C.ink2)

    local y = 168
    for i, nut in ipairs(conf.nuts) do
        local col = (i - 1) % 3
        local row = math.floor((i - 1) / 3)
        local x = 16 + col * 92
        local yy = y + row * 44
        nutBtns[i] = theme.button(card, x, yy, 86, 36, nut.name, 14, C.panel2, C.ink2, function()
            theme.defer(function()
                sim.set_nut(i)
                refresh_nut_btns()
                if app_ref then app_ref.toast("已切换到 " .. nut.name) end
                M.refresh()
            end)
        end, 8)
    end
end

-- ==================== 烘干进度 ====================
local SEG_N = 20
local function build_progress_card()
    local card = theme.card(root, 16, 388, 300, 90)
    theme.label(card, 16, 10, 120, 22, "烘干进度", 15, C.ink2)
    progPct = theme.label(card, 180, 10, 104, 22, "0%", 15, C.amber, airui.TEXT_ALIGN_RIGHT)
    local segW, gap = 10, 3
    for i = 1, SEG_N do
        progSegs[i] = theme.box(card, 16 + (i - 1) * (segW + gap), 40, segW, 14, C.line, 3)
    end
    progTime = theme.label(card, 16, 60, 268, 20, "", 13, C.ink3)
end

-- ==================== 设备控制 ====================
local function refresh_dev_btns()
    local dv = sim.devices()
    for _, d in ipairs(DEV_DEF) do
        local b = devBtns[d.key]
        if b then
            local on = dv[d.key]
            b:set_style({
                bg_color = on and C.amber or C.panel2,
                text_color = on and 0x1A120C or C.ink3,
                border_color = on and C.amber or C.line,
                radius = 8,
            })
        end
    end
end

local function build_device_card()
    local card = theme.card(root, 16, 494, 300, 90)
    theme.label(card, 16, 10, 200, 20, "设备控制", 15, C.ink2)
    for i, d in ipairs(DEV_DEF) do
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        local x = 16 + col * 138
        local y = 34 + row * 26
        devBtns[d.key] = theme.button(card, x, y, 128, 22, d.name, 12, C.panel2, C.ink2, function()
            theme.defer(function()
                local on = sim.toggle_device(d.key)
                refresh_dev_btns()
                if app_ref then
                    app_ref.toast(d.name .. (on and " 已开启" or " 已关闭"))
                end
            end)
        end, 6)
    end
end

-- ==================== 温度主波形 ====================
local function build_temp_card()
    local card = theme.card(root, 332, 72, 360, 246)
    card:set_on_click(function()
        theme.defer(function()
            if app_ref then app_ref.open_metric("temp") end
        end)
    end)
    theme.accent_bar(card, 12, 0, 60, C.orange)

    theme.label(card, 16, 12, 100, 22, "烘干温度", 15, C.ink2)
    tempPill = theme.box(card, 268, 12, 64, 22, C.ok, 11, 40)
    tempPillText = theme.label(tempPill, 0, 2, 64, 18, "正常", 13, C.ok, airui.TEXT_ALIGN_CENTER)

    tempValue = theme.label(card, 16, 38, 200, 50, "--", 34, C.ink)
    tempTargetLabel = theme.label(card, 210, 52, 122, 22, "", 13, C.ink3, airui.TEXT_ALIGN_RIGHT)

    tempWave = theme.shape({ parent = card, x = 16, y = 96, w = 328, h = 116, items = {} })
    tempSub = theme.label(card, 16, 218, 328, 20, "", 12, C.ink3)
end

-- ==================== 指标卡 ====================
local function build_metric_card(x, y, w, key)
    local card = theme.card(root, x, y, w, 120)
    card:set_on_click(function()
        theme.defer(function()
            if app_ref then app_ref.open_metric(key) end
        end)
    end)
    local d = sim.def(key)
    theme.label(card, 12, 10, 120, 20, d.name, 14, C.ink2)
    theme.label(card, w - 28, 10, 18, 20, ">", 13, C.ink3, airui.TEXT_ALIGN_RIGHT)

    local value = theme.label(card, 12, 30, w - 24, 34, "--", 22, C.ink)
    local pill = theme.box(card, 12, 70, 60, 20, C.ok, 10, 40)
    local pillText = theme.label(pill, 0, 1, 60, 18, "正常", 12, C.ok, airui.TEXT_ALIGN_CENTER)
    local spark = theme.shape({ parent = card, x = 12, y = 94, w = w - 24, h = 20,
                                items = spark_items(sim.history(key), w - 24, 20, C.amber) })
    cards[key] = { value = value, pill = pill, pillText = pillText, spark = spark, unit = d.unit }
end

-- ==================== 水质（pH / 浊度） ====================
local function build_water_card()
    local card = theme.card(root, 708, 72, 300, 136)
    theme.accent_bar(card, 16, 0, 50, C.blue)
    theme.label(card, 16, 12, 200, 22, "水质监测", 16, C.ink)

    theme.label(card, 16, 44, 80, 20, "pH 酸碱度", 13, C.ink3)
    phValue = theme.label(card, 16, 66, 120, 34, "--", 24, C.ink)
    phPill = theme.label(card, 16, 104, 120, 20, "", 13, C.ok)

    theme.label(card, 160, 44, 120, 20, "浊度 NTU", 13, C.ink3)
    turbValue = theme.label(card, 160, 66, 120, 34, "--", 24, C.ink)
    turbPill = theme.label(card, 160, 104, 120, 20, "", 13, C.ok)

    -- 左右两个热区
    local l = theme.box(card, 12, 38, 136, 92, 0x000000, 8, 1)
    l:set_on_click(function()
        theme.defer(function() if app_ref then app_ref.open_metric("ph") end end)
    end)
    local r = theme.box(card, 152, 38, 136, 92, 0x000000, 8, 1)
    r:set_on_click(function()
        theme.defer(function() if app_ref then app_ref.open_metric("turb") end end)
    end)
end

-- ==================== CO2 ====================
local function build_co2_card()
    local card = theme.card(root, 708, 224, 300, 110)
    card:set_on_click(function()
        theme.defer(function() if app_ref then app_ref.open_metric("co2") end end)
    end)
    theme.label(card, 16, 12, 140, 20, "二氧化碳", 14, C.ink2)
    theme.label(card, 272, 12, 16, 20, ">", 13, C.ink3, airui.TEXT_ALIGN_RIGHT)
    co2Value = theme.label(card, 16, 34, 200, 34, "--", 24, C.ink)
    co2Pill = theme.label(card, 16, 72, 120, 20, "", 13, C.ok)
    co2Spark = theme.shape({ parent = card, x = 130, y = 62, w = 156, h = 34,
                             items = spark_items(sim.history("co2"), 156, 34, C.amber) })
end

-- ==================== 报警记录 ====================
local function build_alarm_card()
    local card = theme.card(root, 708, 350, 300, 154)
    theme.accent_bar(card, 16, 0, 50, C.red)
    theme.label(card, 16, 12, 160, 22, "报警记录", 16, C.ink)
    for i = 1, 4 do
        local y = 44 + (i - 1) * 26
        local t = theme.label(card, 16, y, 46, 18, "", 11, C.ink3)
        local txt = theme.label(card, 66, y, 222, 18, "", 12, C.ink2)
        alarmRows[i] = { time = t, text = txt }
    end
end

-- ==================== 批次环境 ====================
local function build_batch_card()
    local card = theme.card(root, 708, 520, 300, 64)
    theme.label(card, 16, 10, 200, 20, "批次 B241024-01", 13, C.ink2)
    batchEnv = theme.label(card, 16, 34, 268, 20, "", 12, C.ink3)
end

-- ==================== 构建 ====================
function M.build(app)
    M.destroy()
    app_ref = app

    root = airui.container({
        parent = nil, x = 0, y = 0, w = SW, h = SH,
        color = C.bg1, radius = 0, border_width = 0,
    })
    theme.gradient(root, 0, 0, SW, SH, C.bg1, C.bg2, 14)

    build_topbar()
    build_nut_card()
    build_progress_card()
    build_device_card()

    build_temp_card()
    build_metric_card(332, 334, 172, "o2")
    build_metric_card(520, 334, 172, "co")
    build_metric_card(332, 466, 172, "hum")
    build_metric_card(520, 466, 172, "moist")

    build_water_card()
    build_co2_card()
    build_alarm_card()
    build_batch_card()

    refresh_nut_btns()
    refresh_dev_btns()
    M.refresh()
end

-- ==================== 刷新 ====================
function M.refresh()
    if not root then return end

    local t = os.date("*t")
    local week = { "日", "一", "二", "三", "四", "五", "六" }
    if timeLabel then timeLabel:set_text(string.format("%02d:%02d", t.hour, t.min)) end
    if dateLabel then dateLabel:set_text(string.format("%04d-%02d-%02d 星期%s", t.year, t.month, t.day, week[t.wday] or "")) end

    if alarmDot then
        if sim.any_alarm() then
            alarmDot:set_color((sim.tick_count() % 2 == 0) and C.red or C.danger)
        else
            alarmDot:set_color(C.ink3)
        end
    end
    if alarmText then alarmText:set_text(tostring(#sim.alarms())) end

    -- 坚果
    local nut = sim.nut()
    if nutIconShape then
        nutIconShape:set_items(nut_items(nut.kind, nut.color, 35, 35, 1.0))
    end
    if nutName then nutName:set_text(nut.name) end
    if nutTempLabel then nutTempLabel:set_text(string.format("推荐 %d~%d °C", nut.temp_min, nut.temp_max)) end
    if nutHoursLabel then nutHoursLabel:set_text(string.format("建议烘干约 %d 小时", nut.hours)) end

    -- 进度
    local prog = sim.progress()
    local lit = math.floor(prog * SEG_N + 0.5)
    for i, seg in ipairs(progSegs) do
        seg:set_color(i <= lit and C.amber or C.line)
    end
    if progPct then progPct:set_text(string.format("%d%%", math.floor(prog * 100 + 0.5))) end
    if progTime then
        progTime:set_text(string.format("已烘 %.1f h / %d h", sim.elapsed_min() / 60, nut.hours))
    end

    -- 温度
    local tv = sim.get("temp")
    local tst = sim.status("temp")
    local tcol = theme.state_color(tst)
    if tempValue then tempValue:set_text(sim.fmt("temp", tv) .. "°C") end
    if tempTargetLabel then tempTargetLabel:set_text(string.format("目标 %.1f°C", sim.target_temp())) end
    if tempPill then tempPill:set_color(tcol) end
    if tempPillText then
        tempPillText:set_text(theme.state_text(tst))
        tempPillText:set_color(tcol)
    end
    if tempWave then tempWave:set_items(temp_wave_items(sim.history("temp"), 328, 116)) end
    if tempSub then
        tempSub:set_text(string.format("推荐 %d~%d°C · 目标线橙 / 区间虚线金", nut.temp_min, nut.temp_max))
    end

    -- 指标卡
    for key, c in pairs(cards) do
        local st = sim.status(key)
        local col = theme.state_color(st)
        c.value:set_text(sim.fmt(key, sim.get(key)) .. c.unit)
        c.pill:set_color(col)
        c.pillText:set_text(theme.state_text(st))
        c.pillText:set_color(col)
        c.spark:set_items(spark_items(sim.history(key), 148, 20, col))
    end

    -- 水质
    if phValue then phValue:set_text(sim.fmt("ph", sim.get("ph"))) end
    if phPill then
        phPill:set_text(theme.state_text(sim.status("ph")))
        phPill:set_color(theme.state_color(sim.status("ph")))
    end
    if turbValue then turbValue:set_text(sim.fmt("turb", sim.get("turb"))) end
    if turbPill then
        turbPill:set_text(theme.state_text(sim.status("turb")))
        turbPill:set_color(theme.state_color(sim.status("turb")))
    end

    -- CO2
    if co2Value then co2Value:set_text(sim.fmt("co2", sim.get("co2")) .. " ppm") end
    if co2Pill then
        co2Pill:set_text(theme.state_text(sim.status("co2")))
        co2Pill:set_color(theme.state_color(sim.status("co2")))
    end
    if co2Spark then co2Spark:set_items(spark_items(sim.history("co2"), 156, 34, C.amber)) end

    -- 报警
    local alarms = sim.alarms()
    for i = 1, 4 do
        local row = alarmRows[i]
        if row then
            local a = alarms[i]
            if a then
                row.time:set_text(a.time)
                row.text:set_text(a.text)
                row.text:set_color(a.level == "danger" and C.danger or C.warn)
            else
                row.time:set_text("")
                row.text:set_text("")
            end
        end
    end

    -- 批次环境
    if batchEnv then
        local env = sim.env()
        batchEnv:set_text(string.format("室温 %.1f°C · 室外湿度 %.0f%% · 气压 %.0f hPa",
            env.room, env.out_hum, env.press))
    end
end

function M.destroy()
    nutBtns = {}
    progSegs = {}
    devBtns = {}
    cards = {}
    alarmRows = {}
    if root then
        pcall(function() root:destroy() end)
        root = nil
    end
    app_ref = nil
end

return M
