--[[
@module  ui_curve
@summary 曲线详情：豆温/炉温主图 + ROR 速率带 + 关键节点 + 分析与存档
@version 1.0
@date    2026.10.30
]]
local conf = require("conf")
local theme = require("theme")
local sim = require("sim")
local art = require("art")
local app = require("app")

local C, SZ = theme.C, theme.SZ

-- 主图几何
local TX, TY, TW, TH = 56, 46, 900, 186
local RX, RY, RW, RH = 56, 252, 900, 56
local VMIN, VMAX = 20, 270
local RMIN, RMAX = -30, 60

local M = {}

local function find_index(hist, v)
    for i = 1, #hist do
        if hist[i] >= v then return i end
    end
    return nil
end

function M.build(p, arg)
    local alive = true
    local U = {}
    local tick = 0
    local target = math.floor((sim.bean().drop_min + sim.bean().drop_max) / 2)

    app.subbar(p, "烘焙曲线详情", sim.bean().name .. " · " .. sim.mode_text())

    -- ===================== 主曲线卡 =====================
    local chartCard = theme.card(p, 24, 72, 976, 320)
    theme.label(chartCard, 20, 12, 180, 22, "烘焙曲线", SZ.m, C.ink)
    theme.box(chartCard, 118, 20, 8, 3, C.copper, 1)
    theme.label(chartCard, 130, 14, 50, 18, "豆温", SZ.xs, C.ink3)
    theme.box(chartCard, 172, 20, 8, 3, C.blue, 1)
    theme.label(chartCard, 184, 14, 50, 18, "炉温", SZ.xs, C.ink3)
    theme.box(chartCard, 226, 20, 8, 3, C.violet, 1)
    theme.label(chartCard, 238, 14, 50, 18, "ROR", SZ.xs, C.ink3)
    U.legend = theme.label(chartCard, 20, 12, 930, 22, "", SZ.xs, C.ink3, theme.RT)

    theme.label(chartCard, 14, TY - 9, 34, 18, tostring(VMAX), SZ.xs, C.ink3, theme.RT)
    theme.label(chartCard, 14, TY + math.floor(TH / 2) - 9, 34, 18,
        tostring(math.floor((VMIN + VMAX) / 2)), SZ.xs, C.ink3, theme.RT)
    theme.label(chartCard, 14, TY + TH - 8, 34, 18, tostring(VMIN), SZ.xs, C.ink3, theme.RT)
    U.temp = theme.shape(chartCard, TX, TY, TW, TH, {})

    U.rorTop = theme.label(chartCard, 14, RY - 6, 34, 16, tostring(RMAX), SZ.xs, C.ink3, theme.RT)
    U.rorZero = theme.label(chartCard, 14, RY + RH - 14, 34, 16, "0", SZ.xs, C.ink3, theme.RT)
    U.ror = theme.shape(chartCard, RX, RY, RW, RH, {})

    theme.label(chartCard, TX, RY + RH + 4, 60, 16, "00:00", SZ.xs, C.ink3)
    theme.label(chartCard, TX + 410, RY + RH + 4, 80, 16, "06:00", SZ.xs, C.ink3, theme.CT)
    theme.label(chartCard, TX + 840, RY + RH + 4, 60, 16, "12:00", SZ.xs, C.ink3, theme.RT)

    -- ===================== 关键节点 =====================
    local nodeCard = theme.card(p, 24, 404, 316, 170)
    theme.label(nodeCard, 16, 12, 200, 20, "关键节点", SZ.m, C.ink)
    local nodes = {
        { key = "turning", name = "回温点", color = C.blue },
        { key = "first_crack", name = "一爆", color = C.gold },
        { key = "second_crack", name = "二爆", color = C.red },
        { key = "drop_t", name = "出豆", color = C.green },
    }
    U.node = {}
    for i, n in ipairs(nodes) do
        local y = 40 + (i - 1) * 30
        theme.box(nodeCard, 16, y + 7, 6, 6, n.color, 3)
        theme.label(nodeCard, 30, y, 100, 20, n.name, SZ.s, C.ink2)
        U.node[i] = theme.label(nodeCard, 130, y, 170, 20, "--:--", SZ.s, C.ink, theme.RT)
    end

    -- ===================== 烘焙分析 =====================
    local anaCard = theme.card(p, 352, 404, 316, 170)
    theme.label(anaCard, 16, 12, 200, 20, "烘焙分析", SZ.m, C.ink)
    U.scoreBig = theme.label(anaCard, 196, 26, 104, 48, "--", SZ.xl, C.crema, theme.RT)
    theme.label(anaCard, 196, 72, 104, 16, "综合评分", SZ.xs, C.ink3, theme.RT)
    local rows = { "发展比", "峰值 ROR", "脱水结束", "本炉时长" }
    U.ana = {}
    for i, name in ipairs(rows) do
        local y = 40 + (i - 1) * 28
        theme.label(anaCard, 16, y, 100, 20, name, SZ.s, C.ink3)
        U.ana[i] = theme.label(anaCard, 16, y, 170, 20, "--", SZ.s, C.ink2, theme.RT)
    end

    -- ===================== 目标与存档 =====================
    local actCard = theme.card(p, 680, 404, 320, 170)
    theme.label(actCard, 16, 12, 200, 20, "目标出豆温度", SZ.m, C.ink)
    U.target = theme.label(actCard, 200, 12, 100, 20, target .. "°C", SZ.m, C.copper2, theme.RT)
    local sl = theme.slider({
        parent = actCard, x = 16, y = 42, w = 288, h = 16,
        min = 185, max = 235, value = target,
        bg_color = C.panel3, bg_opa = 255,
        indicator_color = C.copper2, indicator_opa = 255,
        knob_color = C.ink, knob_opa = 255,
        knob_border_color = C.copper2, knob_border_width = 2,
        on_change = function(s)
            if not alive then return end
            local ok, v = pcall(function() return s:get_value() end)
            if not ok then return end
            target = v
            U.target:set_text(v .. "°C")
            tick = 0
        end,
    })
    U.sl = sl
    theme.label(actCard, 16, 66, 288, 16, "目标线以橙色虚线显示在曲线上", SZ.xs, C.ink3)

    theme.button(actCard, 16, 92, 138, 44, "存为档案", { on_click = function()
        if not alive then return end
        local a = sim.save_curve()
        if a then app.toast("已存档 · " .. a.name, C.green) else app.toast("先出豆才能存档", C.ink2) end
    end })
    theme.ghost(actCard, 166, 92, 138, 44, "返回主屏", { on_click = function()
        if alive then app.go("dash") end
    end })
    theme.label(actCard, 16, 144, 288, 16, "下拉火力/风门在主屏实时调整", SZ.xs, C.ink3)

    theme.label(p, 24, 580, 976, 16,
        "曲线采样 6s/点 · 横轴满量程 12 分钟 · ROR = dBT/dt × 60", SZ.xs, C.ink3)

    -- ===================== 绘制 =====================
    local function paint_force()
        local st = sim.state()
        local b = sim.bean()
        local bt, et, ror = st.hist_bt, st.hist_et, st.hist_ror
        local total = conf.sim.history_n
        local items = {}
        local i150 = bt[1] and (find_index(bt, 150) or (#bt + 1)) or 1
        local icrack = bt[1] and (find_index(bt, b.crack) or (#bt + 1)) or 1
        local marks = {}
        if st.first_crack then
            marks[#marks + 1] = { i = math.floor(st.first_crack / conf.sim.dt_s) + 1, color = C.gold }
        end
        if st.second_crack then
            marks[#marks + 1] = { i = math.floor(st.second_crack / conf.sim.dt_s) + 1, color = C.red }
        end
        if st.drop_t then
            marks[#marks + 1] = { i = math.floor(st.drop_t / conf.sim.dt_s) + 1, color = C.green }
        end

        if #bt >= 2 then
            local r = sim.compare()
            local arr = r and sim.archive_hist(r) or nil
            if arr then
                for _, it in ipairs(art.curve_items(TW, TH, arr, {
                    min = VMIN, max = VMAX, total = total, color = C.ink3,
                    width = 1, area = false, end_dot = false, grid = 0, step = 2,
                    dash_width = 4, dash_gap = 4, opacity = 200,
                })) do items[#items + 1] = it end
            end
            for _, it in ipairs(art.curve_items(TW, TH, et, {
                min = VMIN, max = VMAX, total = total, color = C.blue, width = 1,
                area = false, end_dot = false, grid = 5, step = 2, opacity = 190,
            })) do items[#items + 1] = it end
            for _, it in ipairs(art.curve_items(TW, TH, bt, {
                min = VMIN, max = VMAX, total = total, color = C.copper, width = 2,
                area = true, area_opa = 20, grid = 0, step = 2, marks = marks,
                bands = {
                    { i0 = 1, i1 = i150, color = 0x6FA8DC, opa = 12 },
                    { i0 = i150, i1 = icrack, color = 0xD9A05B, opa = 15 },
                    { i0 = icrack, i1 = #bt, color = 0xFF8A4C, opa = 17 },
                },
                refs = {
                    { v = b.crack, color = C.gold, opa = 150 },
                    { v = target, color = C.copper2, opa = 200 },
                },
            })) do items[#items + 1] = it end
        else
            items = art.curve_items(TW, TH, { conf.sim.ambient, conf.sim.ambient }, {
                min = VMIN, max = VMAX, color = C.line2, width = 1,
                area = false, end_dot = false, grid = 5,
                refs = { { v = target, color = C.copper2, opa = 200 } },
            })
        end
        pcall(function() U.temp:set_items(items) end)

        local ritems = {}
        if #ror >= 2 then
            ritems = art.curve_items(RW, RH, ror, {
                min = RMIN, max = RMAX, total = total, color = C.violet, width = 2,
                area = true, area_opa = 16, grid = 0, step = 2, end_dot = false,
                refs = { { v = 0, color = C.line2, opa = 255 } },
            })
        else
            ritems = art.curve_items(RW, RH, { 0, 0 }, {
                min = RMIN, max = RMAX, color = C.line2, width = 1,
                area = false, end_dot = false,
                refs = { { v = 0, color = C.line2, opa = 255 } },
            })
        end
        pcall(function() U.ror:set_items(ritems) end)

        -- 图例与文字
        U.legend:set_text(string.format("采样 %d 点 · 目标 %d°C · %s",
            #bt, target, b.level_hint))

        local function tlab(t) return t and sim.fmt_time(t) or "--:--" end
        U.node[1]:set_text(tlab(st.turning and st.turning.t))
        U.node[2]:set_text(tlab(st.first_crack))
        U.node[3]:set_text(tlab(st.second_crack))
        U.node[4]:set_text(tlab(st.drop_t))

        U.scoreBig:set_text(tostring(st.score or sim.score()))
        local dev = st.dev_ratio and string.format("%.0f%%", st.dev_ratio * 100) or "--"
        local peak = 0
        for _, v in ipairs(ror) do if v > peak then peak = v end end
        local dry = i150 and ((i150 - 1) * conf.sim.dt_s) or nil
        U.ana[1]:set_text(dev)
        U.ana[2]:set_text(string.format("%.1f °C/min", peak))
        U.ana[3]:set_text(dry and sim.fmt_time(dry) or "--:--")
        U.ana[4]:set_text(sim.fmt_time(st.drop_t or st.t))
    end

    local page = {}
    page.refresh = function()
        if not alive then return end
        tick = tick + 1
        if tick % conf.sim.curve_div == 0 then paint_force() end
    end
    page.refresh_clock = function() end
    page.destroy = function() alive = false end

    tick = 1
    paint_force()
    return page
end

return M
