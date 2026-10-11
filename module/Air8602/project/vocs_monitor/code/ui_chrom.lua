--[[
@module  ui_chrom
@summary 色谱视图（TIC 全谱 + 峰识别结果）
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
    local col2, gap = 282, 12
    local col1 = vw - col2 - gap
    handles = { root = root, T = T }

    -- ========== 面板 A：TIC 色谱图 · 全谱 ==========
    local pa = W.panel(root, 0, 0, col1, vh, T)
    W.panel_title(pa, 12, 14, col1 - 12, "TIC 色谱图 - 全谱", "RT / min - 相对强度", T)
    handles.tic = W.tic_chart(pa, 42, 38, col1 - 62, vh - 68, T)

    -- ========== 面板 B：峰识别结果 ==========
    local pb = W.panel(root, col1 + gap, 0, col2, vh, T)
    W.panel_title(pb, 12, 14, col2 - 12, "峰识别结果", "11 PEAKS", T)
    handles.table_parent = pb
    handles.table_w = col2

    return root
end

function M.update(st)
    if not handles then return end
    handles.tic.update(st.chrom, st.chrom_peaks)

    -- 峰识别结果为静态数据，首次刷新时构建一次
    if not handles.peaks_built and st.peaks_table then
        local rows = {}
        for i, r in ipairs(st.peaks_table) do
            rows[i] = { r.idx, r.rt, r.nm, r.mt, level = r.level }
        end
        W.table(handles.table_parent, 0, 44, handles.table_w, 0,
            { "#", "RT", "组分", "匹配" }, rows, handles.T)
        handles.peaks_built = true
    end
end

function M.destroy()
    if handles and handles.root then handles.root:destroy() end
    handles = nil
end

return M
