--[[
@module  ui_trend
@summary 趋势页：多通道实时曲线（基于 airui 原生 chart）+ 触摸游标
@version 2.0.0
@date    2026.10.25

实现说明：
  1、曲线本身交给 airui.chart（LVGL lv_chart）：网格线、坐标轴刻度线与刻度标签
     全部由 C 层绘制，Lua 侧只负责喂数据；
  2、各通道量纲不同（℃/kW/%…），而 lv_chart 所有序列共用一条 Y 轴，
     因此先把每个通道按自身可视范围归一化到 0~100 再喂给 chart；
     左侧 Y 轴标签就是归一化百分比，右侧另用标签标注主通道的工程量刻度；
  3、X 轴固定为 CAP 个点（右对齐：最新点永远在最右，未采满的左侧留空），
     空点用 LV_CHART_POINT_NONE 填充，C 层会自动跳过不绘制；
  4、游标（竖向指示线 + 数据点 + 浮动读数框）airui 未提供接口，仍用 airui.shape 叠加；
     触摸选点靠铺在曲线上的一排透明热区实现（airui 的 on_click 不提供坐标，
     只能由热区序号反推位置），选中后可用 ◀ ▶ 逐点微调。

布局（屏幕坐标，1024x600）：
  顶栏 0..56    曲线卡 68..364    通道选择 372..458    图例卡 468..534    导航 548
  卡内：标题/控制行 8..36   chart 44..262（左留 46 给 Y 刻度、右留 58 给工程量刻度、
        下留 34 给 X 刻度，轴标签由 airui 画在父容器上，必须留出边距）
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

local root = nil
local app_ref = nil

local sel = { temp = true }

-- ==================== 常量 ====================
local CAP = mbdev.hist_n()        -- 图表固定点数（与历史容量一致，80）
local NONE = 2147483647           -- LV_CHART_POINT_NONE：该点不绘制
local MAX_SEL = 3
local NY = 4                      -- Y 方向刻度格数
local NX = 5                      -- X 轴刻度标签个数
local NSLOT = 40                  -- 曲线上的触摸热区数量（越大定位越精细）
local TIP_W, TIP_H = 224, 88      -- 游标浮层尺寸
local HINT_IDLE = "触摸曲线读取数值 · ◀ ▶ 微调"

local CARD_X, CARD_Y, CARD_W, CARD_H = 24, 68, 976, 296
local CH_X, CH_Y = 46, 44                    -- chart 在卡内的位置
local CH_W = CARD_W - CH_X - 58              -- 右侧留 58 给主通道工程量刻度
local CH_H = CARD_H - CH_Y - 34              -- 底部留 34 给 X 轴刻度标签
local AXIS_R_W = 50                          -- 右侧工程量刻度标签宽度

local chips = {}
local chartObj = nil                         -- airui.chart 对象
local sids = {}                              -- 三条序列的 id
local cursorShape, tipBox, tipTime = nil, nil, nil
local tipDots, tipRows = {}, {}
local yLabelsR = {}                          -- 右侧工程量刻度
local headerRight, statusLabel = nil, nil
local legends = {}
local cursor = nil                           -- 当前选中的样本序号（1..n，相对历史数组）
local ranges = {}                            -- 各选中通道的工程量可视范围 { lo, hi }

-- ==================== 工具 ====================
local function fmt_dur(s)
    s = math.floor((tonumber(s) or 0) + 0.5)
    if s < 0 then s = 0 end
    if s >= 3600 then return string.format("%dh%02dm", s // 3600, (s % 3600) // 60) end
    if s >= 120 then return string.format("%dm%02ds", s // 60, s % 60) end
    return tostring(s) .. "s"
end

local function sel_count()
    local n = 0
    for _ in pairs(sel) do n = n + 1 end
    return n
end

local function sel_list()
    local out = {}
    for _, key in ipairs(mbdev.TREND) do
        if sel[key] then out[#out + 1] = key end
    end
    return out
end

-- 当前实际已采样点数（开机后从 0 增长到 CAP），游标范围与提示都基于它
local function cur_n()
    local list = sel_list()
    if #list > 0 then return mbdev.hist_len(list[1]) end
    return CAP
end

-- 工程量数组 -> chart 可用的归一化整数数组（右对齐，未采满的左侧填空点）
local function build_buf(hist, lo, hi)
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

local function refresh_chips()
    for i, b in ipairs(chips) do
        if b then
            local key = mbdev.TREND[i]
            local pt = mbdev.point(key)
            local on = sel[key] == true
            b:set_style({
                bg_color = on and (pt.color or C.cyan) or C.panel2,
                text_color = on and 0x05141C or C.ink2,
                border_color = on and (pt.color or C.cyan) or C.line2,
                radius = 9,
            })
        end
    end
end

-- ==================== 构建：游标浮层 ====================
local function build_tip(parent)
    tipBox = airui.container({
        parent = parent, x = CH_X + 20, y = CH_Y + 8, w = TIP_W, h = TIP_H,
        color = 0x0C1826, color_opacity = 242,
        radius = 8, border_color = C.cyan, border_width = 1,
    })
    tipTime = theme.label(tipBox, 10, 8, TIP_W - 20, 18, "", 12, C.ink)
    for i = 1, MAX_SEL do
        tipDots[i] = theme.box(tipBox, 10, 30 + (i - 1) * 20, 10, 10, C.cyan, 5)
        tipRows[i] = theme.label(tipBox, 26, 26 + (i - 1) * 20, TIP_W - 36, 18, "", 13, C.ink)
    end
    tipBox:set_hidden(true)
end

-- ==================== 构建：曲线卡 ====================
local function build_wave()
    local card = theme.card(root, CARD_X, CARD_Y, CARD_W, CARD_H)
    theme.accent_bar(card, 16, 0, 50, C.cyan)
    theme.label(card, 16, 10, 240, 22, "多通道实时趋势", 17, C.ink)
    statusLabel = theme.label(card, 180, 12, 476, 20, "", 12, C.ink3)

    theme.ghost_button(card, 676, 8, 44, 28, "◀", 15, C.ink2, function()
        theme.defer(function() M.move_cursor(-1) end)
    end)
    theme.ghost_button(card, 726, 8, 44, 28, "▶", 15, C.ink2, function()
        theme.defer(function() M.move_cursor(1) end)
    end)
    theme.ghost_button(card, 776, 8, 92, 28, "取消游标", 12, C.ink2, function()
        theme.defer(function()
            cursor = nil
            M.refresh()
        end)
    end)

    -- 右侧：主通道工程量刻度（左侧的归一化百分比由 chart 自己的 Y 轴画）
    for k = 0, NY do
        yLabelsR[k + 1] = theme.label(card, CH_X + CH_W + 4,
            CH_Y + math.floor(CH_H * k / NY) - 7, AXIS_R_W, 14, "", 11, C.ink3)
    end

    -- 曲线本体：网格 / 坐标轴刻度线与标签均由 C 层绘制
    local span_s = math.floor((CAP - 1) * conf.comm.poll_interval_ms / 1000 + 0.5)
    chartObj = airui.chart({
        parent = card, x = CH_X, y = CH_Y, w = CH_W, h = CH_H,
        type = "line",
        update_mode = "shift",
        y_min = 0, y_max = 100,          -- 归一化百分比
        point_count = CAP,
        line_color = C.cyan, line_width = 2, point_radius = 0,
        bg_opa = 0, border_width = 0,
        hdiv = NY + 1, vdiv = NX,        -- 水平格数=Y 刻度数，垂直格数=X 刻度数
        grid_color = C.line, grid_opa = 70,
        x_axis = { enable = true, min = -span_s, max = 0, ticks = NX, unit = "s" },
        y_axis = { enable = true, min = 0, max = 100, ticks = NY + 1, unit = "%" },
    })
    -- 创建时已自带第 1 条序列，这里补齐到 3 条；不用的序列喂空数组即可隐藏
    sids[1] = 1
    sids[2] = chartObj:add_series({ color = C.cyan, name = "ch2" })
    sids[3] = chartObj:add_series({ color = C.cyan, name = "ch3" })

    -- 游标画在 chart 之上（airui 未提供 cursor 接口）
    cursorShape = theme.shape({ parent = card, x = CH_X, y = CH_Y, w = CH_W, h = CH_H, items = {} })
    build_tip(card)

    -- 触摸热区：横铺在绘图区上，点击后按序号反推采样位置
    local slot_w = CH_W / NSLOT
    for k = 1, NSLOT do
        local x0 = CH_X + math.floor((k - 1) * slot_w + 0.5)
        local x1 = CH_X + math.floor(k * slot_w + 0.5)
        local ww = x1 - x0
        if ww < 1 then ww = 1 end
        theme.hotspot(card, x0, CH_Y, ww, CH_H, function()
            theme.defer(function() M.pick_slot(k) end)
        end)
    end
end

-- ==================== 构建：通道选择 / 图例 ====================
local function build_chips()
    for i, key in ipairs(mbdev.TREND) do
        local pt = mbdev.point(key)
        local col = (i - 1) % 4
        local row = math.floor((i - 1) / 4)
        chips[i] = theme.button(root, 24 + col * 244, 372 + row * 46, 236, 40,
            string.format("%s (%s)", pt.name, pt.unit), 14, C.panel2, C.ink2, function()
                theme.defer(function()
                    if sel[key] then
                        sel[key] = nil
                    else
                        if sel_count() >= MAX_SEL then
                            if app_ref then app_ref.toast("最多同时显示 " .. MAX_SEL .. " 条曲线") end
                            refresh_chips()
                            return
                        end
                        sel[key] = true
                    end
                    refresh_chips()
                    M.refresh()
                end)
            end, 9)
    end
end

local function build_legend()
    local card = theme.card(root, 24, 468, 976, 66)
    theme.label(card, 16, 8, 300, 16, "通道图例 / 当前值 / 可视量程", 13, C.ink2)
    for i = 1, MAX_SEL do
        local x = 16 + (i - 1) * 320
        legends[i] = {
            dot = theme.box(card, x, 38, 12, 12, C.cyan, 6),
            name = theme.label(card, x + 20, 34, 130, 20, "", 13, C.ink),
            val = theme.label(card, x + 150, 34, 90, 20, "", 13, C.ink2),
            rng = theme.label(card, x + 240, 34, 76, 20, "", 11, C.ink3),
        }
    end
end

-- ==================== 游标 ====================
-- 由热区序号定位采样点：热区 -> 图表数组索引 -> 历史样本序号
function M.pick_slot(k)
    local n = cur_n()
    if n < 1 then return end
    local idx = math.ceil((k - 0.5) * CAP / NSLOT)
    if idx < 1 then idx = 1 end
    if idx > CAP then idx = CAP end
    local j = idx - (CAP - n)                 -- 右对齐：数组前 (CAP-n) 个是空点
    if j < 1 then j = 1 end
    if j > n then j = n end
    cursor = j
    M.refresh()
end

function M.move_cursor(d)
    local n = cur_n()
    if n < 1 then return end
    if not cursor then
        cursor = n                            -- 未选中时从最新一点开始
    else
        cursor = cursor + d
    end
    if cursor < 1 then cursor = 1 end
    if cursor > n then cursor = n end
    M.refresh()
end

local function update_cursor(list)
    local n = cur_n()
    if (not cursor) or n < 1 or #list == 0 then
        if cursorShape then cursorShape:set_items({}) end
        if tipBox then tipBox:set_hidden(true) end
        return
    end
    if cursor > n then cursor = n end
    if cursor < 1 then cursor = 1 end

    -- 样本序号 -> 图表数组索引 -> 画布 x（与 lv_chart 的映射一致：w * i / (point_cnt-1)）
    local idx = cursor + (CAP - n)
    local cx = (CAP > 1) and (CH_W * (idx - 1) / (CAP - 1)) or 0

    local items = {
        { type = "line", x1 = cx, y1 = 0, x2 = cx, y2 = CH_H,
          color = C.ink, width = 1, opacity = 170 },
        { type = "rect", x = cx - 4, y = 0, w = 8, h = 5, fill = true, fill_color = C.ink },
    }
    for i, key in ipairs(list) do
        local r = ranges[i]
        local v = mbdev.history(key)[cursor]
        if r and v ~= nil then
            local k = (v - r.lo) / (r.hi - r.lo)
            if k < 0 then k = 0 end
            if k > 1 then k = 1 end
            local cy = CH_H * (1 - k)          -- 与 y_min=0 / y_max=100 的映射一致
            local col = mbdev.point(key).color or C.cyan
            items[#items + 1] = { type = "circle", cx = cx, cy = cy, r = 7,
                                  color = col, width = 1, opacity = 170 }
            items[#items + 1] = { type = "circle", cx = cx, cy = cy, r = 4,
                                  fill = true, fill_color = col }
        end
    end
    cursorShape:set_items(items)

    -- 浮动读数框
    local st = mbdev.stamps(list[1])[cursor]
    local age = (n - cursor) * conf.comm.poll_interval_ms / 1000
    local tstr = (st and st > 0) and os.date("%H:%M:%S", st) or "--:--:--"
    tipTime:set_text(string.format("%s   ·   %s前", tstr, fmt_dur(age)))
    for i = 1, MAX_SEL do
        local key = list[i]
        if key then
            local pt = mbdev.point(key)
            tipDots[i]:set_color(pt.color or C.cyan)
            tipDots[i]:set_hidden(false)
            tipRows[i]:set_text(string.format("%s  %s%s", pt.name,
                mbdev.fmt(key, mbdev.history(key)[cursor]), pt.unit))
        else
            tipDots[i]:set_hidden(true)
            tipRows[i]:set_text("")
        end
    end
    -- 优先贴在游标右侧，靠边时翻到左侧
    local tx = CH_X + math.floor(cx) + 12
    if tx + TIP_W > CH_X + CH_W then tx = CH_X + math.floor(cx) - 12 - TIP_W end
    if tx < 8 then tx = 8 end
    tipBox:set_pos(tx, CH_Y + 8)
    tipBox:set_hidden(false)
end

-- ==================== 构建 / 刷新 ====================
function M.build(app)
    M.destroy()
    app_ref = app

    root = airui.container({
        parent = nil, x = 0, y = 0, w = SW, h = SH,
        color = C.bg1, radius = 0, border_width = 0,
    })
    theme.gradient(root, 0, 0, SW, SH, C.bg1, C.bg2, 12)

    headerRight = theme.page_header(root, "趋势曲线 · Trend",
        mbmaster.transport_name() .. " · " .. mbmaster.transport_desc(), C.cyan)

    build_wave()
    build_chips()
    build_legend()

    theme.navbar(root, "trend", NAV_Y, function(id)
        if app_ref then app_ref.show(id) end
    end)

    refresh_chips()
    M.refresh()
end

function M.refresh()
    if not root then return end

    if headerRight then
        headerRight:set_text(mbmaster.transport_name() .. " · " .. mbmaster.transport_desc())
    end

    local list = sel_list()

    -- 各通道按自身可视范围归一化后喂给 chart
    for i = 1, MAX_SEL do
        local key = list[i]
        if key then
            local pt = mbdev.point(key)
            local hist = mbdev.history(key)
            local lo, hi = chart.vis_range(hist, pt)
            ranges[i] = { lo = lo, hi = hi }
            chartObj:set_line_color(sids[i], pt.color or C.cyan)
            chartObj:set_values(sids[i], build_buf(hist, lo, hi))
        else
            ranges[i] = nil
            chartObj:set_values(sids[i], {})        -- 空数组 -> 整条序列填 NONE（隐藏）
        end
    end

    -- 右侧工程量刻度：以主通道（第一个选中通道）标注
    local main = list[1]
    local mpt = main and mbdev.point(main)
    local mrange = ranges[1]
    for k = 0, NY do
        if yLabelsR[k + 1] then
            if mpt and mrange then
                local v = mrange.hi - (mrange.hi - mrange.lo) * (k / NY)
                yLabelsR[k + 1]:set_text(string.format("%." .. mpt.dec .. "f", v))
                yLabelsR[k + 1]:set_color(mpt.color or C.cyan)
            else
                yLabelsR[k + 1]:set_text("")
            end
        end
    end

    update_cursor(list)

    if statusLabel then
        local n = cur_n()
        if cursor and n > 0 then
            local age = (n - cursor) * conf.comm.poll_interval_ms / 1000
            statusLabel:set_text(string.format("游标：第 %d / %d 点 · 距现在 %s · ◀ ▶ 微调",
                cursor, n, fmt_dur(age)))
        else
            statusLabel:set_text(string.format("采样 %d/%d 点 · 间隔 %d ms · 窗口 %s · %s",
                n, CAP, conf.comm.poll_interval_ms,
                fmt_dur((CAP - 1) * conf.comm.poll_interval_ms / 1000), HINT_IDLE))
        end
    end

    for i = 1, MAX_SEL do
        local L = legends[i]
        local key = list[i]
        if L then
            if key then
                local pt = mbdev.point(key)
                L.dot:set_color(pt.color or C.cyan)
                L.name:set_text(pt.name)
                L.val:set_text(mbdev.fmt(key, mbdev.get(key)) .. pt.unit)
                local r = ranges[i]
                L.rng:set_text(r and string.format("%.1f~%.1f", r.lo, r.hi) or "")
            else
                L.dot:set_color(C.panel2)
                L.name:set_text("")
                L.val:set_text("")
                L.rng:set_text("")
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
    chips, legends, yLabelsR = {}, {}, {}
    tipDots, tipRows, sids, ranges = {}, {}, {}, {}
    chartObj, cursorShape, tipBox, tipTime = nil, nil, nil, nil
    headerRight, statusLabel = nil, nil
    cursor = nil
end

return M
