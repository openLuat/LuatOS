--[[
@module  ui_mold
@summary 模具工单页：模具寿命台账 + 生产工单列表 + 选中工单进度与完工预估
@version 1.0
@date    2026.11.10
]]
local conf  = require("conf")
local theme = require("theme")
local store = require("store")
local model = require("model")

local C = theme.C
local T = theme
local M = {}

local v = { rows = {}, sel = 1, last_sig = nil }

local function mold_state(remain)
    if remain < 10 then return C.red end
    if remain < 20 then return C.orange end
    return C.green
end

local function machine_of(order_id)
    for _, m in ipairs(model.list()) do
        if m.order == order_id and (m.state == "run" or m.state == "alarm") then
            return m
        end
    end
    return nil
end

-- 未排产时的提示语
local function left_text(o)
    return o.done > 0 and "已暂停" or "等待排产"
end

function M.build(parent)
    local page = airui.container({
        parent = parent, x = 0, y = 0, w = conf.W, h = conf.H, color = -1,
    })
    v.page = page
    M.root = page

    -- ==================== 模具台账 ====================
    local mc = T.card(page, 20, 84, 480, 504, "模具寿命台账", "单位：万模次")
    for i, md in ipairs(conf.molds) do
        local y = 44 + (i - 1) * 56
        local r = { id = md.id }
        r.id = T.label(mc, 18, y + 4, 110, 22, md.id, 15, C.ink)
        T.label(mc, 134, y + 6, 118, 20, md.product, 12, C.ink2)
        T.label(mc, 256, y + 6, 56, 20, md.cavity .. " 穴", 11, C.ink3)
        r.remain = T.label(mc, 300, y + 6, 142, 20, "", 12, C.green, T.TEXT_RIGHT)
        r.used = T.label(mc, 18, y + 26, 220, 18, "", 11, C.ink3)
        r.bar = T.bar(mc, 18, y + 46, 424, 6, {
            max = 100, value = 0, indicator_color = C.green,
        })
        if i > 1 then
            T.hline(mc, 18, y - 4, 424, C.line)
        end
        v.rows[i] = r
    end

    -- ==================== 生产工单 ====================
    local oc = T.card(page, 512, 84, 492, 504, "生产工单")
    v.order_sub = T.label(oc, 300, 16, 174, 20, "", 12, C.ink3, T.TEXT_RIGHT)

    local data = {}
    for i, o in ipairs(conf.orders) do
        data[i] = { o.id, o.product, o.mold, "0%", "待排产" }
    end
    v.tbl = T.table(oc, 14, 44, 464, 248, {
        rows = #conf.orders, cols = 5,
        data = data,
        row_height = 30,
        col_width = { 108, 88, 66, 108, 76 },
        style = {
            bg_color = C.panel2, bg_opa = 255, border_width = 0, radius = 8,
            cell_bg_color = C.panel2, cell_border_width = 0,
            cell_text_color = C.ink2, cell_text_align = T.TEXT_LEFT,
            cell_vertical_align = "center", cell_font_size = 11,
            selected_cell_bg_color = C.panel3,
        },
        on_click = function(a, b)
            local row = (type(a) == "number") and a or b
            if type(row) == "number" and row >= 0 and row < #conf.orders then
                v.sel = row + 1
                M.refresh()
            end
        end,
    })

    -- 工单详情
    local dc = T.frame(oc, 14, 306, 464, 184, C.panel2, 12, C.line)
    T.label(dc, 16, 10, 200, 20, "工单详情", 12, C.ink3)
    v.d_id = T.label(dc, 16, 34, 240, 26, "", 17, C.ink)
    v.d_state, v.d_state_box = T.badge(dc, 300, 34, 148, 24, "", C.green, 12)
    v.d_line1 = T.label(dc, 16, 68, 432, 18, "", 12, C.ink2)
    v.d_bar = T.bar(dc, 16, 96, 432, 10, {
        max = 100, value = 0, indicator_color = C.cyan,
    })
    v.d_pct = T.label(dc, 16, 114, 200, 18, "", 12, C.ink2)
    v.d_eta = T.label(dc, 240, 114, 208, 18, "", 12, C.ink3, T.TEXT_RIGHT)
    v.d_line2 = T.label(dc, 16, 140, 432, 18, "", 11, C.ink3)
    v.d_line3 = T.label(dc, 16, 160, 432, 18, "", 11, C.ink3)

    return true
end

function M.refresh()
    if not v.page then return end

    -- 模具
    local warn = 0
    for i, md in ipairs(conf.molds) do
        local r = v.rows[i]
        local used = store.mold_used(md.id)
        local remain = math.max(0, (md.life - used) / md.life * 100)
        if remain < 20 then warn = warn + 1 end
        local col = mold_state(remain)
        r.bar:set_value(math.floor(used / md.life * 100))
        r.bar:set_indicator_color(col)
        r.used:set_text(string.format("%.1f / %d 万模次", used, md.life))
        r.remain:set_text(string.format("剩余 %.0f%%", remain))
        r.remain:set_color(col)
    end

    -- 工单表（产量变化时才重写单元格，避免 1Hz 全表刷新）
    local sig, n_run = 0, 0
    for _, m in ipairs(model.list()) do
        sig = sig + (m.done or 0)
    end
    for _, o in ipairs(conf.orders) do
        if machine_of(o.id) then n_run = n_run + 1 end
    end
    v.order_sub:set_text(string.format("在产 %d / 共 %d", n_run, #conf.orders))

    if sig ~= v.last_sig then
        v.last_sig = sig
        for i, o in ipairs(conf.orders) do
            local mm = machine_of(o.id)
            local pct = o.plan > 0 and math.min(100, o.done / o.plan * 100) or 0
            local st = (pct >= 100) and "已完成" or (mm and "生产中" or "待排产")
            v.tbl:set_cell_text(i - 1, 3, string.format("%.0f%%", pct))
            v.tbl:set_cell_text(i - 1, 4, st)
        end
    end

    -- 详情
    local o = conf.orders[v.sel]
    if o then
        local mm = machine_of(o.id)
        local pct = o.plan > 0 and math.min(100, o.done / o.plan * 100) or 0
        local col = (pct >= 100) and C.green or (mm and C.cyan or C.ink3)
        v.d_id:set_text(o.id .. "  " .. o.product)
        v.d_state_box:set_color(col)
        v.d_state:set_text((pct >= 100) and "已完成" or (mm and "生产中" or "待排产"))
        v.d_line1:set_text(string.format("计划 %d 模   已产 %d 模   模具 %s",
            o.plan, o.done, o.mold))
        v.d_bar:set_value(math.floor(pct))
        v.d_bar:set_indicator_color(col)
        v.d_pct:set_text(string.format("完成 %.1f%%", pct))

        if mm then
            local left = math.max(0, o.plan - o.done)
            local mins = left * mm.cycle / 60
            v.d_eta:set_text(string.format("剩余 %d 模 · 预计 %d h %d min",
                left, math.floor(mins / 60), math.floor(mins % 60)))
            v.d_line2:set_text(string.format("机台 %s   模穴 %d   周期 %.1fs   良品 %d",
                mm.id, mm.cavity, mm.cycle, mm.ok))
            v.d_line3:set_text(string.format("状态 %s   当前模具 %s",
                conf.state[mm.state].name, mm.mold))
        else
            v.d_eta:set_text(left_text(o))
            v.d_line2:set_text("该工单尚未分配到机台，请在上位机排产")
            v.d_line3:set_text("")
        end
    end
end

return M
