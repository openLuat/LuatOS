--[[
@module  ui_chart
@summary 曲线视图（范围分段 / 图例 / 3 统计块 / 三线温度趋势图）
@version 1.0.0
@date    2026.10.12
@usage
由 ui_shell 在切到「曲线」时调用 create(parent,x,y,w,h,T)，
数据更新时调用 update(state)；切走时调用 destroy()。
范围切换调用 mock_data.set_range；数值数组必须为整数。
]]

local W = require "ui_widgets"
local mock_data = require "mock_data"

local M = {}
local handles = nil

local RANGES = { { "近 24 小时", "24h" }, { "近 7 天", "7d" }, { "近 30 天", "30d" } }
local RANGE_IDX = { ["24h"] = 1, ["7d"] = 2, ["30d"] = 3 }
local SERIES = { { "集热器 T1", "amber" }, { "水箱 T2", "red" }, { "回水 T3", "cyan" } }

function M.create(parent, x, y, w, h, T)
    local root = airui.container({
        parent = parent, x = x, y = y, w = w, h = h,
        color = T.bg, color_opacity = 0,
    })
    local CW, CH = w - 2, h - 2
    handles = { root = root, T = T }

    -- 范围分段
    local opts = {}
    for i = 1, #RANGES do opts[i] = RANGES[i][1] end
    handles.seg = W.seg(root, 0, 2, 340, 32, opts, RANGE_IDX[mock_data.get().range] or 1,
        function(_, opt)
            for i = 1, #RANGES do
                if RANGES[i][1] == opt then mock_data.set_range(RANGES[i][2]) end
            end
        end, T)

    -- 图例（色块 + 文字，文字框给足宽度避免换行）
    local lx = CW - 14 - 88
    for i = #SERIES, 1, -1 do
        local col = W.tone(T, SERIES[i][2])
        W.label(root, lx + 16, 8, 72, 18, SERIES[i][1], 10, T.text_soft)
        airui.container({ parent = root, x = W.d(lx), y = 15, w = 12, h = 3,
            radius = W.d(2), color = col })
        lx = lx - 100
    end

    -- 3 统计块
    local sg = 10
    local tw = math.floor((CW - sg * 2) / 3)
    local tiles = {
        { "集热器最高温度", "℃" }, { "集热器最低温度", "℃" }, { "平均得热量", "kWh" },
    }
    handles.stat = {}
    for i = 1, 3 do
        local tx = (i - 1) * (tw + sg)
        local box = airui.container({ parent = root, x = W.d(tx), y = W.d(46), w = W.d(tw), h = W.d(64),
            radius = W.d(12), color = T.panel, border_color = T.ring, border_width = 1 })
        W.label(box, 14, 12, tw - 28, 16, tiles[i][1], 10, T.text_dim)
        local v = W.label(box, 14, 32, tw - 90, 26, "--", 19, T.text_bright)
        W.label(box, 14, 34, tw - 28, 20, tiles[i][2], 10.5, T.text_dim, airui.TEXT_ALIGN_RIGHT)
        handles.stat[i] = v
    end

    -- 曲线卡
    local card_y = 122
    local card_h = CH - card_y
    local card = W.panel(root, 0, card_y, CW, card_h, T)
    handles.sub = W.panel_title(card, 14, 14, CW - 28, "温度变化趋势", "采样间隔 1 天", T)

    -- 图表：左侧留 Y 轴刻度宽度、下方留 X 轴刻度高度、右侧留余量，避免轴标签溢出触发滚动条
    local cx, cy = 46, 44
    local cw, ch = CW - cx - 28, card_h - cy - 34
    local chart = airui.chart({
        parent = card, x = W.d(cx), y = W.d(cy), w = W.d(cw), h = W.d(ch),
        type = "line",
        y_min = 0, y_max = 120,
        point_count = 32,
        update_mode = "shift",
        line_color = T.amber, line_width = 2, point_radius = 0,
        bg_opa = 0, border_width = 0,
        hdiv = 4, vdiv = 4,
        grid_color = T.ring, grid_opa = 110,
        fill = { enable = true, opa_start = 60, opa_end = 0 },
        x_axis = { enable = true, min = 0, max = 30, ticks = 5 },
        y_axis = { enable = true, min = 0, max = 120, ticks = 5 },
    })
    chart:set_series_name(1, SERIES[1][1])
    chart:set_line_color(1, W.tone(T, SERIES[1][2]))
    handles.sid = { 1 }
    handles.sid[2] = chart:add_series({ color = W.tone(T, SERIES[2][2]), name = SERIES[2][1] })
    handles.sid[3] = chart:add_series({ color = W.tone(T, SERIES[3][2]), name = SERIES[3][1] })
    handles.chart = chart

    return root
end

function M.update(st)
    if not handles then return end
    local T = handles.T

    for i = 1, 3 do
        if handles.sid[i] and st.trend[i] then
            handles.chart:set_values(handles.sid[i], st.trend[i])
        end
    end

    local s = st.trend_stat
    if s then
        handles.stat[1]:set_text(string.format("%.1f", s.max))
        handles.stat[2]:set_text(string.format("%.1f", s.min))
        handles.stat[3]:set_text(string.format("%.1f", s.avg))
    end

    local names = { ["24h"] = "采样间隔 1 小时 / 共 25 点", ["7d"] = "采样间隔 1 天 / 共 8 点",
                    ["30d"] = "采样间隔 1 天 / 共 31 点" }
    handles.sub:set_text(names[st.range] or "采样间隔 1 天")
    handles.seg.set(RANGE_IDX[st.range] or 1)
end

function M.destroy()
    if handles and handles.root then handles.root:destroy() end
    handles = nil
end

return M
