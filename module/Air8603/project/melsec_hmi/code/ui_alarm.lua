--[[
@module  ui_alarm
@summary 报警页 + 报警弹窗（最近 8 条，消音/复位/清空）
@version 1.0.0
@date    2026.11.09
]]
local M = {}

M.TITLE = "报警记录"

local conf = require "conf"
local theme = require "ui_theme"
local C = theme.C
local alarm = require "app_alarm"

local W, H = conf.W, conf.H

-- 表格列定义（比例，合计 0.90，右侧留白）
local COLS = {
    { title = "时间",    w = 0.22, align = airui.TEXT_ALIGN_LEFT },
    { title = "通道",    w = 0.15, align = airui.TEXT_ALIGN_LEFT },
    { title = "级别",    w = 0.10, align = airui.TEXT_ALIGN_CENTER },
    { title = string.format("数值(%s)", conf.scale.unit), w = 0.15, align = airui.TEXT_ALIGN_RIGHT },
    { title = string.format("阈值(%s)", conf.scale.unit), w = 0.15, align = airui.TEXT_ALIGN_RIGHT },
    { title = "状态",    w = 0.13, align = airui.TEXT_ALIGN_CENTER },
}

local function col_layout(w)
    local out = {}
    local acc = 0
    for i, c in ipairs(COLS) do
        out[i] = { x = math.floor(acc * w), w = math.floor(c.w * w) }
        acc = acc + c.w
    end
    return out
end

-- 预建固定行数的表格（行数 = 8，不随记录变化重建控件）
local function make_table(parent, x, y, w, row_h, max_rows, font_size)
    local xs = col_layout(w)
    local head_w = math.floor(w * 0.90)

    theme.box(parent, x, y, head_w, 34, C.panel2, 6)
    for i, c in ipairs(COLS) do
        theme.label(parent, x + 8 + xs[i].x, y + 7, xs[i].w - 12, 20, c.title, 13, C.ink3, c.align)
    end

    local cells = {}
    for r = 1, max_rows do
        local ry = y + 38 + (r - 1) * row_h
        if r % 2 == 0 then
            theme.box(parent, x, ry, head_w, row_h - 2, C.panel2, 4, 150)
        end
        cells[r] = {}
        for i, c in ipairs(COLS) do
            cells[r][i] = theme.label(parent, x + 8 + xs[i].x, ry + math.floor((row_h - 20) / 2),
                xs[i].w - 12, 20, "--", font_size or 14, C.ink3, c.align)
        end
    end
    return cells
end

-- 填充表格（带缓存，值不变不调 set_text，避免每 500ms 全量重排）
local function fill_table(cells, recs, cache)
    cache = cache or {}
    for r, row in ipairs(cells) do
        local rec = recs[r]
        local vals, colors
        if rec then
            local lv_color = (rec.level == 2) and C.danger or C.warn
            vals = {
                os.date("%m-%d %H:%M:%S", rec.t or 0),
                rec.name or ("CH" .. tostring(rec.ch)),
                (rec.level == 2) and "报警" or "预警",
                string.format("%.1f", rec.val or 0),
                string.format("%.1f", rec.thr or 0),
                rec.acked and "已确认" or "未确认",
            }
            colors = { C.ink2, C.ink, lv_color, C.ink, C.ink2, rec.acked and C.ink3 or C.amber }
        else
            vals = { "--", "--", "--", "--", "--", "--" }
            colors = { C.ink3, C.ink3, C.ink3, C.ink3, C.ink3, C.ink3 }
        end

        for i, lb in ipairs(row) do
            local k = r * 10 + i
            if cache[k] ~= vals[i] then
                cache[k] = vals[i]
                theme.set_text(lb, vals[i])
                theme.set_color(lb, colors[i])
            end
        end
    end
    return cache
end

-- ===== 报警页 =====

function M.build(body)
    local api = { cache = {} }

    theme.button(body, 20, 4, 110, 38, "消音", 16, C.panel2, C.ink2, function()
        theme.defer(function() alarm.mute() end)
    end)
    theme.button(body, 142, 4, 110, 38, "报警复位", 16, C.amber, 0x05141C, function()
        theme.defer(function() alarm.ack() end)
    end)
    theme.button(body, 264, 4, 110, 38, "清空记录", 16, C.line2, C.ink, function()
        theme.defer(function() alarm.clear() end)
    end)

    api.state = theme.label(body, 400, 12, 600, 24, "", 15, C.ink3)

    api.cells = make_table(body, 20, 56, 984, 46, conf.alarm.max, 15)
    return api
end

function M.refresh(api)
    if not api or not api.cells then
        return
    end
    api.cache = fill_table(api.cells, alarm.recs, api.cache)

    local lv = alarm.max_level()
    local unacked = 0
    for _, r in ipairs(alarm.recs) do
        if not r.acked then
            unacked = unacked + 1
        end
    end
    theme.set_text(api.state, string.format("当前状态：%s    未确认 %d 条    已消音：%s",
        (lv == 2) and "报警" or ((lv == 1) and "预警" or "正常"), unacked,
        alarm.muted and "是" or "否"))
    theme.set_color(api.state, (lv == 2) and C.danger or ((lv == 1) and C.amber or C.ink3))
end

-- ===== 报警弹窗 =====

local popup_root, popup_cells, popup_cache, popup_title

function M.open_popup()
    if popup_root then
        return
    end

    local root = airui.container({
        parent = nil, x = 0, y = 0, w = W, h = H,
        color = 0x000000, color_opacity = 150, radius = 0, border_width = 0,
    })
    local panel = theme.card(root, 92, 74, 840, 452, C.panel, 14, C.line2, 1)

    theme.label(panel, 20, 14, 320, 30, "报警记录", 22, C.ink)
    popup_title = theme.label(panel, 20, 46, 420, 20, "最近 8 条（新报警在前）", 13, C.ink3)

    theme.ghost_button(panel, 480, 16, 100, 36, "消音", 15, C.ink2, function()
        theme.defer(function() alarm.mute() end)
    end)
    theme.button(panel, 590, 16, 100, 36, "复位", 15, C.amber, 0x05141C, function()
        theme.defer(function() alarm.ack() end)
    end, 9)
    theme.button(panel, 700, 16, 120, 36, "关闭", 15, C.line2, C.ink, function()
        theme.defer(function() M.close_popup() end)
    end, 9)

    popup_cells = make_table(panel, 20, 80, 800, 40, conf.alarm.max, 14)
    popup_cache = {}
    fill_table(popup_cells, alarm.recs, popup_cache)
    popup_root = root
end

function M.refresh_popup()
    if popup_root and popup_cells then
        popup_cache = fill_table(popup_cells, alarm.recs, popup_cache)
        if popup_title then
            theme.set_text(popup_title, string.format("最近 %d 条（新报警在前）  已消音：%s",
                #alarm.recs, alarm.muted and "是" or "否"))
        end
    end
end

function M.close_popup()
    if popup_root then
        pcall(popup_root.destroy, popup_root)
    end
    popup_root, popup_cells, popup_cache, popup_title = nil, nil, nil, nil
end

function M.on_hide()
    M.close_popup()
end

return M
