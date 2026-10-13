--[[
@module  ui_overview
@summary 总览视图（实时 TIC 色谱图 / 质谱图 / 4 项指标 / 组分浓度）
@version 1.0.0
@date    2026.10.10
@usage
由 ui_shell 在切到「总览」时调用 create(parent,x,y,w,h,T)，
数据更新时调用 update(state)；切走时调用 destroy()。
本模块只负责渲染，数据全部来自传入的 state 快照。
]]

local W = require "ui_widgets"

local M = {}
local handles = nil

function M.create(parent, x, y, w, h, T)
    local root = airui.container({
        parent = parent, x = x, y = y, w = w, h = h,
        color = T.bg, color_opacity = 0,
    })

    -- 面板整体比视图容器内缩 2px：子控件贴住容器内容区边界会触发滚动条
    local vw, vh = w - 2, h - 2
    local col2, gap = 326, 12
    local col1 = vw - col2 - gap
    local row1 = 312
    local row2 = vh - row1 - gap
    local mx = col1 + gap           -- 右列起点

    handles = { root = root, metric = {}, voc_name = {}, voc_val = {}, voc_bar = {} }

    -- ========== 面板 A：实时 TIC 色谱图 ==========
    local pa = W.panel(root, 0, 0, col1, row1, T)
    W.panel_title(pa, 12, 14, col1 - 12, "实时 TIC 色谱图", "RT / min - 相对强度", T)
    -- 宽度多留 8px：末端 X 轴刻度标签不会贴到面板内容区边界
    handles.tic = W.tic_chart(pa, 42, 38, col1 - 62, row1 - 68, T)

    -- ========== 面板 B：质谱图 ==========
    local pb = W.panel(root, mx, 0, col2, row1, T)
    handles.ms_sub = W.panel_title(pb, 12, 14, col2 - 12, "质谱图", "SCAN 1042", T)
    handles.ms = W.spectrum(pb, 1, 38, col2 - 2, row1 - 42, T)

    -- ========== 指标行：4 张指标卡 ==========
    local card_gap = 12
    local card_w = (col1 - 3 * card_gap) / 4
    local mc = {
        { label = "TIC 强度", unit = "×10", sub = "cps",              color = T.cyan  },
        { label = "检出组分", unit = "种",   sub = "VOCs identified",  color = T.blue  },
        { label = "分析周期", unit = "%",    sub = "12.5 min / cycle", color = T.amber },
        { label = "载气压力", unit = "kPa",  sub = "Carrier gas",      color = T.cyan  },
    }
    for i, cfg in ipairs(mc) do
        local cxx = (i - 1) * (card_w + card_gap)
        handles.metric[i] = W.metric_card(root, cxx, row1 + gap, card_w, row2,
            { label = cfg.label, value = "--", unit = cfg.unit, sub = cfg.sub, pct = 0, color = cfg.color }, T)
    end
    -- 设计稿的 “×10⁶” 用独立小字号上标实现（hzfont 无上标字符）
    -- 挂在卡片上而非单位标签上，避免负坐标导致父控件溢出
    handles.sup = airui.label({
        parent = handles.metric[1].card,
        x = W.d(W.unit_x("--") + 24), y = W.d(67), w = W.d(22), h = W.d(14),
        text = "6", font_size = W.d(10), color = T.cyan,
    })

    -- ========== 面板 C：组分浓度 ==========
    local pc = W.panel(root, mx, row1 + gap, col2, row2, T)
    W.panel_title(pc, 12, 14, col2 - 12, "组分浓度", "μg/m3", T)

    local pad, name_w, val_w, rgap = 14, 58, 46, 9
    local bar_x = pad + name_w + rgap
    local bar_w = col2 - pad - val_w - rgap - bar_x
    local val_x = col2 - pad - val_w
    for i = 1, 4 do
        local ry = 40 + (i - 1) * 32
        handles.voc_name[i] = W.label(pc, pad, ry, name_w, 20, "", 12, T.text_soft)
        handles.voc_val[i] = W.label(pc, val_x, ry, val_w, 20, "0.0", 12.5, T.text_bright, airui.TEXT_ALIGN_RIGHT)
        handles.voc_bar[i] = W.bar(pc, bar_x, ry + 8, bar_w, 5, 0, T.cyan, T.bar_bg)
    end

    return root
end

function M.update(st)
    if not handles then return end
    handles.tic.update(st.chrom, st.chrom_peaks)
    handles.ms.update(st.ms)
    if handles.ms_sub then handles.ms_sub:set_text(st.ms_scan) end

    local m = st.metrics
    local items = {
        { v = string.format("%.2f", m.tic), pct = math.max(8, math.min(100, (m.tic - 0.9) / 0.7 * 100)) },
        { v = tostring(math.floor(m.cmp + 0.5)), pct = math.max(10, math.min(100, m.cmp / 15 * 100)) },
        { v = tostring(math.floor(m.cyc + 0.5)), pct = m.cyc },
        { v = string.format("%.1f", m.pre), pct = math.max(10, math.min(100, (m.pre - 58) / 8 * 100)) },
    }
    for i = 1, 4 do
        local card = handles.metric[i]
        if card then
            card.val:set_text(items[i].v)
            card.unit:set_pos(W.d(W.unit_x(items[i].v)), W.d(76))
            card.bar:set_value(math.floor(items[i].pct + 0.5))
            if i == 1 and handles.sup then
                handles.sup:set_pos(W.d(W.unit_x(items[i].v) + 24), W.d(67))
            end
        end
    end

    for i = 1, #st.vocs do
        local row = st.vocs[i]
        if handles.voc_val[i] then
            handles.voc_name[i]:set_text(row.name)
            handles.voc_val[i]:set_text(string.format("%.1f", row.val))
            handles.voc_bar[i]:set_value(math.floor(row.val / 18 * 100 + 0.5))
        end
    end
end

function M.destroy()
    if handles and handles.root then handles.root:destroy() end
    handles = nil
end

return M
