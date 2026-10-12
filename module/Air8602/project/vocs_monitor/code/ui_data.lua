--[[
@module  ui_data
@summary 数据视图（浓度趋势 + 统计与事件）
@version 1.0.0
@date    2026.10.10
]]

local W = require "ui_widgets"

local M = {}
local handles = nil

function M.create(parent, x, y, w, h, T)
    local root = airui.container({
        parent = parent, x = x, y = y, w = w, h = h,
        color = T.bg, color_opacity = 0,
    })

    -- 面板整体比视图容器内缩 2px，避免贴住内容区边界触发滚动条
    local vw, vh = w - 2, h - 2
    -- 右栏比设计稿略宽：放大字号后事件文本（最长约 220px）需要更多空间
    local col2, gap = 340, 12
    local col1 = vw - col2 - gap
    handles = { root = root, T = T, stat_unit = {}, event_w = col2 - 26 }

    -- ========== 面板 A：浓度趋势 ==========
    local pa = W.panel(root, 0, 0, col1, vh, T)
    W.panel_title(pa, 12, 14, col1 - 12, "浓度趋势", "近 60 分钟 - μg/m3", T)

    -- 图例（自绘，避免 chart 内置图例在深色主题下白底突兀）
    local legend = { { "苯", T.cyan, 14 }, { "甲苯", T.blue, 64 }, { "TVOC", T.amber, 126 } }
    for _, it in ipairs(legend) do
        airui.container({ parent = pa, x = W.d(it[3]), y = W.d(48), w = W.d(7), h = W.d(7),
            radius = W.d(4), color = it[2] })
        W.label(pa, it[3] + 13, 42, 60, 18, it[1], 11.5, T.text_soft)
    end
    -- 右侧留出更多余量，容纳末端刻度标签
    handles.trend = W.trend_chart(pa, 46, 70, col1 - 84, vh - 102, T, { "苯", "甲苯", "TVOC" })
    -- X 轴单位自绘（图表内置的单位标签会贴到面板边界触发滚动条）
    W.label(pa, col1 - 33, 70 + (vh - 102) + 4, 28, 16, "min", 10, T.text_dim, airui.TEXT_ALIGN_LEFT)

    -- ========== 面板 B：统计与事件 ==========
    local pb = W.panel(root, col1 + gap, 0, col2, vh, T)
    W.panel_title(pb, 12, 14, col2 - 12, "统计与事件", "TODAY", T)

    -- 卡片宽度按右栏实际宽度自适应，卡片高度加大以容纳放大的数值
    local sw = math.floor((col2 - 2 * 13 - 9) / 2)
    local sh, sgap = 58, 9
    local stats = {
        { k = "平均 TVOC", u = "μg/m3" },
        { k = "峰值浓度",  u = "μg/m3" },
        { k = "超标次数",  u = "次" },
        { k = "有效率",    u = "%" },
    }
    for i, s in ipairs(stats) do
        local cx = 13 + ((i - 1) % 2) * (sw + sgap)
        local cy = 44 + math.floor((i - 1) / 2) * (sh + sgap)
        local card = airui.container({
            parent = pb, x = W.d(cx), y = W.d(cy), w = W.d(sw), h = W.d(sh),
            color = T.panel, radius = W.d(6),
            border_color = T.ring, border_width = 1,
        })
        W.label(card, 11, 5, sw - 20, 16, s.k, 10.5, T.text_dim)
        handles.stat_val = handles.stat_val or {}
        handles.stat_val[i] = W.label(card, 11, 25, sw - 20, 24, "--", 17.5, T.text_bright)
        handles.stat_unit[i] = W.label(card, 11 + 30, 32, 60, 16, s.u, 10, T.cyan)
    end

    -- 事件列表（静态数据，首次刷新时构建）
    handles.event_parent = pb

    return root
end

function M.update(st)
    if not handles then return end
    handles.trend.update(st.trend)

    local vals = {
        string.format("%.1f", st.stat.avg),
        string.format("%.1f", st.stat.peak),
        tostring(st.stat.over),
        string.format("%.1f", st.stat.rate),
    }
    for i = 1, 4 do
        handles.stat_val[i]:set_text(vals[i])
        handles.stat_unit[i]:set_pos(W.d(11 + #vals[i] * 12 + 2), W.d(32))
    end

    if not handles.events_built and st.events then
        local Tt = handles.T
        local colors = { warn = Tt.amber, ok = Tt.cyan, info = Tt.blue }
        for i, ev in ipairs(st.events) do
            local ry = 180 + (i - 1) * 36
            -- 时间框放宽到 54：放大字号后 “09:00” 这类全宽数字才不会折行
            W.label(handles.event_parent, 13, ry, 54, 20, ev.time, 10.5, Tt.text_dim)
            airui.container({ parent = handles.event_parent, x = W.d(76), y = W.d(ry + 7),
                w = W.d(6), h = W.d(6), radius = W.d(3), color = colors[ev.level] or Tt.cyan })
            W.label(handles.event_parent, 91, ry, handles.event_w - 78, 20, ev.text, 11.5, Tt.text_soft)
            W.divider(handles.event_parent, 13, ry + 28, handles.event_w, Tt.ring)
        end
        handles.events_built = true
    end
end

function M.destroy()
    if handles and handles.root then handles.root:destroy() end
    handles = nil
end

return M
