--[[
@module  ui_process
@summary 工艺页：机台信息 + 成型周期阶段条 + 多通道实时曲线 + 工艺参数表与在线调节
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

local v = { sel = 1, phase_box = {}, phase_name = {}, phase_bar = {} }
M.on_pick = nil    -- 由 ui.lua 注入：点机台卡后切页

local function fmt_val(p, val)
    if p.step < 1 then return string.format("%.1f", val) end
    return string.format("%d", math.floor(val + 0.5))
end

local function round_to(val, step)
    return math.floor(val / step + 0.5) * step
end

-- ==================== 构建 ====================
function M.build(parent)
    local page = airui.container({
        parent = parent, x = 0, y = 0, w = conf.W, h = conf.H, color = -1,
    })
    v.page = page
    M.root = page

    -- ---------- 机台信息卡 ----------
    local ic = T.card(page, 20, 84, 372, 104)
    v.m_id = T.label(ic, 18, 14, 150, 30, "IMM-01", 24, C.ink)
    v.m_badge, v.m_badge_box = T.badge(ic, 150, 20, 62, 22, "运行", C.green, 12)
    v.m_prev = T.ghost(ic, 250, 16, 44, 30, "◀", 14, C.ink2, function()
        local i = model.sel - 1
        if i < 1 then i = conf.machine.count end
        model.select(i)
        M.refresh()
    end, 8)
    v.m_next = T.ghost(ic, 300, 16, 44, 30, "▶", 14, C.ink2, function()
        local i = model.sel + 1
        if i > conf.machine.count then i = 1 end
        model.select(i)
        M.refresh()
    end, 8)

    v.m_prod = T.label(ic, 18, 50, 200, 18, "", 13, C.ink2)
    v.m_order = T.label(ic, 18, 70, 336, 18, "", 11, C.ink3)
    v.m_cyc = T.label(ic, 200, 50, 154, 18, "", 13, C.cyan, T.TEXT_RIGHT)

    -- ---------- 成型周期阶段条 ----------
    local pc = T.card(page, 20, 200, 372, 132, "成型周期")
    v.p_total = T.label(pc, 210, 14, 144, 20, "", 12, C.ink3, T.TEXT_RIGHT)
    local pw, ph, pg = 50, 46, 6
    for i, ph_cfg in ipairs(conf.phases) do
        local x = 18 + (i - 1) * (pw + pg)
        local box = T.frame(pc, x, 44, pw, ph, C.panel2, 8, C.line)
        v.phase_box[i] = box
        v.phase_name[i] = T.label(box, 0, 8, pw, 16, ph_cfg.name, 11, C.ink3,
            T.TEXT_CENTER)
        v.phase_bar[i] = T.bar(box, 6, ph - 12, pw - 12, 3, {
            max = 100, value = 0, indicator_color = C.cyan,
            bg_color = C.line,
        })
    end
    v.phase_txt = T.label(pc, 18, 100, 336, 18, "", 11, C.ink3)

    -- ---------- 工艺参数卡 ----------
    local rc = T.card(page, 20, 344, 372, 246, "工艺参数")
    -- 表头
    local heads = { "参数", "设定", "实测", "偏差" }
    local hx = { 8, 124, 192, 260 }
    for i, h in ipairs(heads) do
        T.label(rc, 18 + hx[i], 40, 70, 16, h, 10, C.ink3)
    end

    local data = {}
    for i, p in ipairs(conf.params) do
        data[i] = { p.name .. "(" .. p.unit .. ")", "-", "-", "-" }
    end
    v.tbl = T.table(rc, 14, 60, 344, 156, {
        rows = #conf.params, cols = 4,
        data = data,
        row_height = 19,
        col_width = { 112, 68, 68, 68 },
        style = {
            bg_color = C.panel2, bg_opa = 255, border_width = 0, radius = 8,
            cell_bg_color = C.panel2, cell_border_width = 0,
            cell_text_color = C.ink2, cell_text_align = T.TEXT_LEFT,
            cell_vertical_align = "center", cell_font_size = 11,
            selected_cell_bg_color = C.panel3,
        },
        -- 兼容 (row,col) 与 (self,row,col) 两种回调签名
        on_click = function(a, b)
            local row = (type(a) == "number") and a or b
            if type(row) == "number" and row >= 0 and row < #conf.params then
                v.sel = row + 1
                M.refresh()
            end
        end,
    })

    -- 调节行
    v.btn_dec = T.ghost(rc, 14, 222, 48, 32, "-", 18, C.ink, function()
        M.step(-1)
    end, 8)
    v.sel_txt = T.label(rc, 70, 226, 190, 24, "", 13, C.ink)
    v.btn_inc = T.ghost(rc, 310, 222, 48, 32, "+", 18, C.ink, function()
        M.step(1)
    end, 8)

    -- ---------- 实时曲线 ----------
    local cc = T.card(page, 404, 84, 600, 290, "实时工艺曲线")
    -- 图例
    local legends = {
        { C.cyan, "射胶压力" }, { C.orange, "料筒温度" }, { C.amber, "模具温度" },
    }
    for i, lg in ipairs(legends) do
        T.dot(cc, 226 + (i - 1) * 106, 20, 8, lg[1])
        T.label(cc, 238 + (i - 1) * 106, 15, 90, 18, lg[2], 11, C.ink3)
    end

    v.chart = T.chart(cc, 14, 44, 572, 232, {
        type = "line", update_mode = "circular", point_count = 180,
        y_axes = {
            { min = 0, max = 160, unit = "MPa", ticks = 5, side = "left", color = C.cyan },
            { min = 0, max = 300, unit = "℃", ticks = 5, side = "right", color = C.orange },
        },
        hdiv = 4, vdiv = 5, line_width = 2, point_radius = 0,
        grid_color = C.line, grid_opa = 70,
        bg_color = C.panel2, border_width = 0,
    })
    if v.chart then
        v.s_press = 1
        v.s_barrel = v.chart:add_series({ color = C.orange, name = "料筒", y_axis = 2 })
        v.s_mold = v.chart:add_series({ color = C.amber, name = "模温", y_axis = 2 })
    end

    -- ---------- 周期趋势 ----------
    local tc = T.card(page, 404, 386, 600, 202, "最近 30 模周期")
    v.cyc_txt = T.label(tc, 360, 14, 226, 20, "", 12, C.ink3, T.TEXT_RIGHT)
    v.bar_chart = T.chart(tc, 14, 44, 572, 144, {
        type = "bar", point_count = 30,
        y_axis = { min = 20, max = 40, unit = "s", ticks = 5 },
        hdiv = 4, vdiv = 4, bar_radius = 3, bar_group_gap = 2,
        grid_color = C.line, grid_opa = 70,
        bg_color = C.panel2, border_width = 0,
    })
    if v.bar_chart then
        v.bar_chart:set_line_color(1, C.purple)
    end

    return true
end

-- ==================== 参数调节 ====================
function M.step(dir)
    local p = conf.params[v.sel]
    if not p then return end
    local cur = store.params()[p.key] or p.def
    local nv = round_to(cur + dir * p.step, p.step)
    if nv < p.min then nv = p.min end
    if nv > p.max then nv = p.max end
    if nv == cur then return end
    if p.step < 1 then nv = math.floor(nv * 10 + 0.5) / 10 end
    store.set_param(p.key, nv)
    store.save_params()
    M.refresh()
end

-- ==================== 刷新 ====================
function M.refresh()
    if not v.page then return end
    local m = model.current()
    if not m then return end
    local st = conf.state[m.state] or conf.state.stop

    v.m_id:set_text(m.id)
    v.m_badge_box:set_color(st.color)
    v.m_badge:set_text(st.name)
    v.m_prod:set_text(string.format("%s · 模具 %s", m.product or "-", m.mold or "-"))
    v.m_order:set_text(string.format("工单 %s   模穴 %d   已产 %d/%d",
        m.order or "未排产", m.cavity or 0, m.done or 0, m.plan or 0))
    v.m_cyc:set_text(string.format("%.1f / %.1fs", m.t_cyc, m.cycle))

    -- 阶段条
    local idx, ratio = model.phase_of(m)
    for i in ipairs(conf.phases) do
        local on = (i == idx)
        v.phase_box[i]:set_color(on and T.dim(C.cyan, 0.28) or C.panel2)
        v.phase_name[i]:set_color(on and C.cyan or C.ink3)
        v.phase_bar[i]:set_value(on and math.floor(ratio * 100) or 0)
        v.phase_bar[i]:set_indicator_color(on and C.cyan or C.line)
    end
    v.phase_txt:set_text(string.format("第 %d 模 · %s %.0f%%",
        m.shots + 1, idx > 0 and conf.phases[idx].name or "待机", ratio * 100))
    v.p_total:set_text(string.format("节拍 %.1fs", m.cycle))

    -- 参数表
    local p = store.params()
    local sel_name, sel_val = "", ""
    for i, def in ipairs(conf.params) do
        local set = p[def.key] or def.def
        local act = model.actual(m, def.key)
        local dev = act - set
        v.tbl:set_cell_text(i - 1, 0, def.name)
        v.tbl:set_cell_text(i - 1, 1, fmt_val(def, set) .. def.unit)
        v.tbl:set_cell_text(i - 1, 2, fmt_val(def, act))
        v.tbl:set_cell_text(i - 1, 3, string.format("%+.1f", dev))
        local over = math.abs(dev) > math.abs(set) * 0.06
        v.tbl:set_cell_style("row", i - 1, {
            cell_bg_color = (i == v.sel) and C.panel3 or C.panel2,
            cell_text_color = over and C.orange or ((i == v.sel) and C.ink or C.ink2),
        })
        if i == v.sel then
            sel_name = def.name .. " · " .. def.unit
            sel_val = fmt_val(def, set)
        end
    end
    v.sel_txt:set_text(string.format("%s  =  %s", sel_name, sel_val))

    -- 曲线
    if v.chart then
        v.chart:push(v.s_press, math.floor(model.actual(m, "inj_press") + 0.5))
        if v.s_barrel then
            v.chart:push(v.s_barrel, math.floor(model.actual(m, "barrel_t") + 0.5))
        end
        if v.s_mold then
            v.chart:push(v.s_mold, math.floor(model.actual(m, "mold_t") + 0.5))
        end
    end

    -- 周期柱状
    if v.bar_chart then
        local vals = {}
        local sum = 0
        for i = 1, #m.hist do
            vals[i] = math.floor(m.hist[i] + 0.5)
            sum = sum + m.hist[i]
        end
        if #vals > 0 then
            v.bar_chart:set_values(1, vals)
            v.cyc_txt:set_text(string.format("均值 %.1fs · 当前 %.1fs",
                sum / #vals, m.last_cycle))
        end
    end
end

return M
