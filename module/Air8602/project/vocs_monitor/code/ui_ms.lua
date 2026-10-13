--[[
@module  ui_ms
@summary 质谱视图（全谱扫描 + 主要离子）
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

    -- ========== 面板 A：质谱图 · 全谱扫描 ==========
    local pa = W.panel(root, 0, 0, col1, vh, T)
    W.panel_title(pa, 12, 14, col1 - 12, "质谱图 - 全谱扫描", "m/z 10 - 130 / EI 70eV", T)
    handles.ms = W.spectrum(pa, 1, 42, col1 - 4, vh - 52, T)

    -- ========== 面板 B：主要离子 ==========
    local pb = W.panel(root, col1 + gap, 0, col2, vh, T)
    W.panel_title(pb, 12, 14, col2 - 12, "主要离子", "ABUNDANCE", T)
    handles.table_parent = pb
    handles.table_w = col2

    return root
end

function M.update(st)
    if not handles then return end
    handles.ms.update(st.ms)

    if not handles.ions_built and st.ions_table then
        local rows = {}
        for i, r in ipairs(st.ions_table) do
            rows[i] = { r.idx, r.mz, r.nm, r.ab, level = r.level }
        end
        W.table(handles.table_parent, 0, 44, handles.table_w, 0,
            { "#", "m/z", "归属", "丰度" }, rows, handles.T)
        handles.ions_built = true
    end
end

function M.destroy()
    if handles and handles.root then handles.root:destroy() end
    handles = nil
end

return M
