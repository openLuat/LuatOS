--[[
@module  ui_alarm
@summary 报警页：筛选 + 报警记录表 + 单条/全部确认
@version 1.0
@date    2026.11.10
]]
local conf  = require("conf")
local theme = require("theme")
local store = require("store")

local C = theme.C
local T = theme
local M = {}

local v = { filter = 1, sel = 1, sig = nil }

local FILTERS = { "全部", "未确认", "严重" }

-- 按筛选条件取列表
local function filtered()
    local all = store.alarms()
    if v.filter == 1 then return all end
    local out = {}
    for _, a in ipairs(all) do
        if v.filter == 2 and not a.ack then
            table.insert(out, a)
        elseif v.filter == 3 and a.level == 3 then
            table.insert(out, a)
        end
    end
    return out
end

function M.build(parent)
    local page = airui.container({
        parent = parent, x = 0, y = 0, w = conf.W, h = conf.H, color = -1,
    })
    v.page = page
    M.root = page

    -- ---------- 工具条 ----------
    local tc = T.card(page, 20, 84, 984, 76)
    T.label(tc, 18, 12, 200, 22, "报警记录", 15, C.ink)
    v.stat = T.label(tc, 18, 40, 300, 20, "", 12, C.ink3)

    v.fbtn = {}
    for i, name in ipairs(FILTERS) do
        local x = 300 + (i - 1) * 96
        v.fbtn[i] = T.ghost(tc, x, 20, 88, 32, name, 13, C.ink2, function()
            v.filter = i
            v.sel = 1
            v.sig = nil
            M.refresh()
        end, 8)
    end
    v.btn_all = T.button(tc, 856, 20, 110, 32, "全部确认", 13,
        T.dim(C.green, 0.30), C.green, function()
            store.ack_all()
            v.sig = nil
            M.refresh()
        end, 8)

    -- ---------- 报警表 ----------
    local lc = T.card(page, 20, 172, 984, 408)
    v.tbl = T.table(lc, 14, 14, 956, 336, {
        rows = 10, cols = 6,
        row_height = 32,
        col_width = { 108, 96, 96, 320, 88, 108 },
        style = {
            bg_color = C.panel2, bg_opa = 255, border_width = 0, radius = 8,
            cell_bg_color = C.panel2, cell_border_width = 0,
            cell_text_color = C.ink2, cell_text_align = T.TEXT_LEFT,
            cell_vertical_align = "center", cell_font_size = 12,
            selected_cell_bg_color = C.panel3,
        },
        on_click = function(a, b)
            local row = (type(a) == "number") and a or b
            if type(row) == "number" and row >= 0 and row < 10 then
                v.sel = row + 1
                M.refresh()
            end
        end,
    })

    v.tip = T.label(lc, 18, 364, 500, 20, "", 11, C.ink3)
    v.btn_ack = T.ghost(lc, 820, 358, 150, 32, "确认选中报警", 13, C.cyan, function()
        local list = filtered()
        local a = list[v.sel]
        if a then
            -- store 里的下标与过滤列表不同，按内容回查
            for idx, r in ipairs(store.alarms()) do
                if r.t == a.t and r.m == a.m and r.code == a.code then
                    store.ack_alarm(idx)
                    break
                end
            end
            v.sig = nil
            M.refresh()
        end
    end, 8)

    return true
end

function M.refresh()
    if not v.page then return end

    local list = store.alarms()
    local unacked, sev = 0, 0
    for _, a in ipairs(list) do
        if not a.ack then unacked = unacked + 1 end
        if a.level == 3 then sev = sev + 1 end
    end
    v.stat:set_text(string.format("共 %d 条 · 未确认 %d 条 · 严重 %d 条",
        #list, unacked, sev))

    for i = 1, #FILTERS do
        local on = (i == v.filter)
        pcall(v.fbtn[i].set_style, v.fbtn[i], {
            bg_color = on and C.panel3 or C.panel2, bg_opa = 255,
            text_color = on and C.cyan or C.ink2, radius = 8,
            border_color = on and C.cyan or C.line2, border_width = 1,
            pressed_bg_color = C.line2, pressed_text_color = C.white,
        })
    end

    local rows = filtered()
    local sig = tostring(v.filter) .. "#" .. #rows .. "#" .. unacked
        .. "#" .. tostring(v.sel)
    if sig == v.sig then return end
    v.sig = sig

    for r = 0, 9 do
        local a = rows[r + 1]
        if a then
            v.tbl:set_cell_text(r, 0, a.t or "--:--:--")
            v.tbl:set_cell_text(r, 1, a.m or "-")
            v.tbl:set_cell_text(r, 2, a.code or "-")
            v.tbl:set_cell_text(r, 3, a.name or "-")
            v.tbl:set_cell_text(r, 4, conf.level_name[a.level] or "-")
            v.tbl:set_cell_text(r, 5, a.ack and "已确认" or "未确认")
            local bg = a.ack and C.panel2
                or T.dim(conf.level_color[a.level] or C.red, 0.14)
            v.tbl:set_cell_style("row", r, {
                cell_bg_color = bg,
                cell_text_color = a.ack and C.ink3 or C.ink,
                cell_border_color = ((r + 1) == v.sel) and C.cyan or bg,
                cell_border_width = 1,
            })
        else
            for c = 0, 5 do
                v.tbl:set_cell_text(r, c, (r == 0 and c == 0) and "暂无记录" or "")
            end
            v.tbl:set_cell_style("row", r, {
                cell_bg_color = C.panel2, cell_text_color = C.ink3,
                cell_border_color = C.panel2, cell_border_width = 0,
            })
        end
    end

    local cur = rows[v.sel]
    if cur then
        v.tip:set_text(string.format("选中 %s %s %s · %s · %s",
            cur.t, cur.m, cur.code, cur.name,
            cur.ack and "已确认" or "待确认"))
    else
        v.tip:set_text("点击表格行选择报警，再点右侧按钮确认")
    end
end

return M
