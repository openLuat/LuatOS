--[[
@module  ui_cycle
@summary 工艺页：注射压力与模腔压力曲线、螺杆位置、阶段耗时对照、料筒温度、模温回路、工艺参数
@version 1.0
@date    2026.11.15
]]
local theme = require "theme"
local art   = require "art"
local sim   = require "sim"
local conf  = require "conf"

local C = theme.C
local SZ = theme.SZ
local A_LEFT, A_CENTER, A_RIGHT = theme.align_left(), theme.align_center(), theme.align_right()

local M = {}

local L = {
    chart   = { x = 14,  y = 10,  w = 620, h = 210 },
    times   = { x = 14,  y = 230, w = 620, h = 124 },
    barrel  = { x = 14,  y = 364, w = 620, h = 170 },
    mold    = { x = 646, y = 10,  w = 364, h = 210 },
    params  = { x = 646, y = 230, w = 364, h = 304 },
}

local PLOT = { x = 14, y = 44, w = 592, h = 146 }

function M.create(root)
    local page = { root = root, alive = true }

    -- ==================== 压力曲线 ====================
    local ch = theme.card(root, L.chart.x, L.chart.y, L.chart.w, L.chart.h, { radius = 10 })
    theme.label(ch, 14, 8, 300, 18, "注射压力与模腔压力，最近 120 秒", SZ.s, C.ink)
    local ch_hint = theme.label(ch, 340, 9, 266, 16, "bar", SZ.xs, C.ink3, A_RIGHT)
    page.ch_hint = ch_hint

    -- 图例
    local lg = {
        { name = "注射压力", color = C.melt },
        { name = "模腔压力", color = C.amber },
    }
    for i, d in ipairs(lg) do
        local x = 14 + (i - 1) * 96
        theme.box(ch, x, 30, 10, 3, d.color, 1)
        theme.label(ch, x + 14, 23, 80, 14, d.name, SZ.xs, C.ink2)
    end
    theme.label(ch, 520, 23, 86, 14, "量程 0-1600", SZ.xs, C.ink3, A_RIGHT)

    local plot = theme.shape(ch, PLOT.x, PLOT.y, PLOT.w, PLOT.h, {})
    page.plot = plot

    theme.label(ch, 14, 212, 90, 14, "0", SZ.xs, C.ink3)
    theme.label(ch, 510, 212, 96, 14, "-120 s", SZ.xs, C.ink3, A_RIGHT)

    -- 螺杆位置小条
    theme.label(ch, 14, 196, 70, 14, "螺杆位置", SZ.xs, C.ink3)
    local screw_val = theme.label(ch, 78, 196, 74, 14, "", SZ.xs, C.violet)
    local screw_bar = theme.bar(ch, 156, 200, 300, 5, 0, C.violet, C.panel3)
    page.screw_val = screw_val
    page.screw_bar = screw_bar

    -- ==================== 阶段耗时 ====================
    local tc = theme.card(root, L.times.x, L.times.y, L.times.w, L.times.h, { radius = 10 })
    theme.label(tc, 14, 8, 200, 18, "阶段耗时，设定与实测", SZ.s, C.ink)
    local tc_sum = theme.label(tc, 380, 9, 226, 16, "", SZ.xs, C.ink3, A_RIGHT)
    page.tc_sum = tc_sum

    -- 表头
    theme.label(tc, 14, 30, 90, 14, "阶段", SZ.xs, C.ink3)
    theme.label(tc, 110, 30, 70, 14, "设定 s", SZ.xs, C.ink3)
    theme.label(tc, 180, 30, 70, 14, "实测 s", SZ.xs, C.ink3)
    theme.label(tc, 250, 30, 60, 14, "偏差", SZ.xs, C.ink3)

    local rows = {}
    for i, sg in ipairs(conf.stages) do
        local col = (i <= 4) and 0 or 1
        local row = (i - 1) % 4
        local x = 14 + col * 302
        local y = 46 + row * 19
        theme.box(tc, x, y + 4, 3, 10, sg.color, 1)
        theme.label(tc, x + 9, y, 62, 14, sg.name, SZ.xs, C.ink2)
        theme.label(tc, x + 74, y, 46, 14, string.format("%.1f", sg.dur), SZ.xs, C.ink3, A_RIGHT)
        local av = theme.label(tc, x + 128, y, 46, 14, "--", SZ.xs, C.ink2, A_RIGHT)
        local dv = theme.label(tc, x + 182, y, 56, 14, "--", SZ.xs, C.ink3, A_RIGHT)
        rows[i] = { val = av, dev = dv }
    end
    page.rows = rows

    -- ==================== 料筒温度 ====================
    local bc = theme.card(root, L.barrel.x, L.barrel.y, L.barrel.w, L.barrel.h, { radius = 10 })
    theme.label(bc, 14, 8, 200, 18, "料筒五段温度", SZ.s, C.ink)
    local bc_hint = theme.label(bc, 340, 9, 266, 16, "", SZ.xs, C.ink3, A_RIGHT)
    page.bc_hint = bc_hint

    local zones = {}
    for i, z in ipairs(conf.barrel) do
        local y = 34 + (i - 1) * 24
        theme.label(bc, 14, y, 46, 16, z.name, SZ.xs, C.ink3)
        local bar = theme.bar(bc, 62, y + 6, 300, 6, 0, C.run, C.panel3)
        local set_lb = theme.label(bc, 370, y, 54, 16, string.format("%d", z.set), SZ.xs, C.ink3, A_RIGHT)
        local val = theme.label(bc, 430, y, 56, 16, "--", SZ.xs, C.ink, A_RIGHT)
        local dev = theme.label(bc, 492, y, 60, 16, "--", SZ.xs, C.ink3, A_RIGHT)
        local mark = theme.box(bc, 62 + 300 * (z.set - 180) / 80 - 1, y + 2, 2, 14, C.ink2, 0)
        zones[i] = { bar = bar, val = val, dev = dev, set = set_lb, mark = mark }
    end
    page.zones = zones

    -- ==================== 模温回路 ====================
    local mc = theme.card(root, L.mold.x, L.mold.y, L.mold.w, L.mold.h, { radius = 10 })
    theme.label(mc, 14, 8, 200, 18, "模温回路", SZ.s, C.ink)

    -- 回路示意：一条供水环管 + 三个站点，水流粒子沿管移动
    local PIPE_Y = 56
    theme.box(mc, 14, PIPE_Y, 322, 4, C.panel3, 2)
    theme.box(mc, 14, PIPE_Y, 150, 4, theme.mix(C.ice, C.panel3, 0.35), 2)

    local ST = {
        { x = 40,  name = "模温机" },
        { x = 170, name = "定模" },
        { x = 300, name = "动模" },
    }
    for _, d in ipairs(ST) do
        theme.box(mc, d.x - 5, PIPE_Y - 4, 10, 12, C.ice, 3)
        theme.label(mc, d.x - 46, 74, 92, 14, d.name, SZ.xs, C.ink3, A_CENTER)
    end
    theme.label(mc, 40 - 44, 90, 88, 18, "62.0", SZ.m, C.ink, A_CENTER)
    local mold_t = theme.label(mc, 170 - 44, 90, 88, 18, "--", SZ.m, C.ink, A_CENTER)
    local mold_t2 = theme.label(mc, 300 - 44, 90, 88, 18, "--", SZ.m, C.ink, A_CENTER)
    page.mold_t = mold_t
    page.mold_t2 = mold_t2

    theme.hline(mc, 14, 118, L.mold.w - 28, C.line)
    theme.label(mc, 14, 126, 90, 14, "进水温度", SZ.xs, C.ink3)
    local wt = theme.label(mc, 86, 124, 70, 16, "--", SZ.s, C.ink)
    theme.label(mc, 186, 126, 60, 14, "流量", SZ.xs, C.ink3)
    local fl = theme.label(mc, 228, 124, 60, 16, "--", SZ.s, C.ink)
    theme.label(mc, 292, 126, 40, 14, "L/min", SZ.xs, C.ink3)
    page.water_t = wt
    page.flow = fl

    theme.label(mc, 14, 150, 150, 14, "加热功率", SZ.xs, C.ink3)
    local heat_bar = theme.bar(mc, 80, 155, 120, 5, 0, C.amber, C.panel3)
    local heat_val = theme.label(mc, 208, 150, 60, 14, "--", SZ.xs, C.ink2, A_RIGHT)
    page.heat_bar = heat_bar
    page.heat_val = heat_val

    theme.label(mc, 14, 176, 300, 14, "定模 24 路 / 动模 18 路，进出水温差 3.2 ℃", SZ.xs, C.ink3)
    local mc2 = theme.label(mc, 14, 192, 322, 14, "", SZ.xs, C.ink3)
    page.mc2 = mc2

    -- 流向粒子
    local flow_dots = {}
    for i = 1, 8 do
        flow_dots[i] = theme.box(mc, 16, PIPE_Y, 4, 4, C.ice, 2)
    end
    page.flow_dots = flow_dots

    -- ==================== 工艺参数 ====================
    local pc = theme.card(root, L.params.x, L.params.y, L.params.w, L.params.h, { radius = 10 })
    theme.label(pc, 14, 8, 200, 18, "工艺参数", SZ.s, C.ink)
    theme.label(pc, 220, 9, 130, 16, "设定值", SZ.xs, C.ink3, A_RIGHT)

    local params = {}
    for i, d in ipairs(conf.process) do
        local y = 32 + (i - 1) * 34
        theme.label(pc, 14, y, 96, 16, d.name, SZ.xs, C.ink3)
        local val = theme.label(pc, 112, y - 2, 92, 18, "--", SZ.s, C.ink)
        theme.label(pc, 208, y, 48, 16, d.unit, SZ.xs, C.ink3)
        local bar = theme.bar(pc, 262, y + 5, 88, 5, 0, d.color, C.panel3)
        params[i] = { def = d, val = val, bar = bar }
    end
    page.params = params

    -- ==================== 刷新 ====================
    local tcache, ccache, bcache = {}, {}, {}
    local function st(lb, txt)
        if tcache[lb] ~= txt then
            tcache[lb] = txt
            lb:set_text(txt)
        end
    end
    local function sc(obj, col)
        if ccache[obj] ~= col then
            ccache[obj] = col
            pcall(function() obj:set_color(col) end)
        end
    end
    local function sb(bar, v, col)
        if not bar then return end
        v = theme.n(v)
        if bcache[bar] ~= v then
            bcache[bar] = v
            theme.setbar(bar, v)
        end
        if col then theme.setbar_color(bar, col) end
    end

    local round = 0
    local function refresh(force)
        if not page.alive then return end
        round = round + 1
        local s = sim.summary()

        -- 螺杆位置条（每秒刷）
        st(page.screw_val, string.format("%.1f mm", s.screw_mm))
        sb(page.screw_bar, s.screw_mm)

        if force or round % 2 == 0 then
            -- 曲线每两秒重绘一次：120 点按 10 px 抽样，两条序列约 120 个线段
            local series = {
                { data = s.hist.p_inj, color = C.melt, min = 0, max = 1600, width = 2, sample = 10 },
                { data = s.hist.p_cav, color = C.amber, min = 0, max = 1600, width = 2, sample = 10 },
            }
            local items = art.curve_items(PLOT.w, PLOT.h, series, {
                pad_top = 8, pad_bottom = 10, grid = 4,
                refs = {
                    { y = 620 / 1600, color = C.line2, opacity = 90 },
                    { y = 1450 / 1600, color = C.line2, opacity = 70 },
                },
            })
            pcall(function() page.plot:set_items(items) end)
            local peak = 0
            for _, v in ipairs(s.hist.p_inj) do if v > peak then peak = v end end
            st(page.ch_hint, string.format("峰值 %d bar", theme.n(peak)))

            -- 阶段耗时
            local times = sim.stage_times()
            local total_set, total_act = 0, 0
            for i, t in ipairs(times) do
                total_set = total_set + t.set
                total_act = total_act + t.actual
                st(page.rows[i].val, string.format("%.1f", t.actual))
                sc(page.rows[i].val, math.abs(t.dev) > 0.6 and C.amber or C.ink2)
                st(page.rows[i].dev, string.format("%+.1f", t.dev))
                sc(page.rows[i].dev, math.abs(t.dev) > 0.6 and C.amber or C.ink3)
            end
            st(page.tc_sum, string.format("合计 %.1f s，偏差 %+.1f s", total_act, total_act - total_set))
            sc(page.tc_sum, math.abs(total_act - total_set) > 1.2 and C.amber or C.ink3)

            -- 料筒温度
            local inband = 0
            for i, z in ipairs(sim.zones()) do
                local col = theme.deviation_color(z.dev, 3)
                st(page.zones[i].val, string.format("%.1f", z.value))
                sc(page.zones[i].val, col)
                st(page.zones[i].dev, string.format("%+.1f", z.dev))
                sc(page.zones[i].dev, col)
                sb(page.zones[i].bar, z.pct * 100, col)
                if z.level == "ok" then inband = inband + 1 end
            end
            st(page.bc_hint, string.format("%d/%d 在带内，带宽 ±3 ℃", inband, #conf.barrel))
            sc(page.bc_hint, inband == #conf.barrel and C.run or C.amber)

            -- 模温
            st(page.mold_t, string.format("%.1f", s.mold_t))
            st(page.mold_t2, string.format("%.1f", s.mold_t2))
            st(page.water_t, string.format("%.1f", s.water_t))
            st(page.flow, string.format("%.1f", s.flow))
            local hp = theme.clamp((62.0 - s.mold_t) * 25 + 30, 0, 100)
            sb(page.heat_bar, hp, C.amber)
            st(page.heat_val, string.format("%d%%", theme.n(hp)))
            local ok_flow = s.flow >= 10
            st(page.mc2, ok_flow and "循环正常，回水温度稳定" or "流量偏低，检查过滤器与水泵")
            sc(page.mc2, ok_flow and C.ink3 or C.amber)

            -- 工艺参数
            for i, p in ipairs(page.params) do
                local d = p.def
                st(p.val, string.format((d.val >= 100 or d.key == "ejn") and "%.0f" or "%.1f", d.val))
                sb(p.bar, d.val / d.max * 100)
            end
        end
    end
    page.refresh = refresh

    -- ==================== 慢刷新 / 帧动画 ====================
    local phase = 0
    local function slow()
        if not page.alive then return end
    end
    page.slow = slow

    local function frame(f)
        if not page.alive then return end
        -- 环管里的水流粒子：沿供水管从左向右移动，到末端回卷
        phase = phase + 0.012
        for i, d in ipairs(page.flow_dots) do
            local t = (phase + i * 0.125) % 1
            pcall(function() d:set_pos(theme.n(14 + t * 318), 56) end)
        end
    end
    page.frame = frame

    function page.destroy()
        page.alive = false
    end

    refresh(true)
    frame(0)
    return page
end

return M
