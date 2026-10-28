--[[
@module  demo_pump
@summary 应用场景 2 - 智慧泵站
@date    2026.10.26
@effect
左侧工艺流程图：蓄水池液位波浪动画 + 2 台水泵（旋转叶轮指示运行）
+ 出水管道流动光点 + 电动阀开度。右侧运行参数区：
出口压力 / 瞬时流量两个弧形表、泵组效率与能耗条、当日供水量统计。
液位与流量按平滑噪声缓慢起伏，模拟真实工况。
]]
local fx = require "fx"

local M = {
    id = "pump",
    name = "泵站",
    desc = "智慧泵站：工艺流程 + 压力流量监测 + 能效分析",
}

local C = fx.C
local fl = math.floor

function M.build(root, W, H)
    local o = { w = W, h = H, pool = fx.pool(), txtT = 0 }
    o.shape = airui.shape({ parent = root, x = 0, y = 0, w = W, h = H, items = {} })

    airui.label({
        parent = root, x = 16, y = 10, w = 300, h = 22,
        text = "泵组工艺流程", font_size = 16, color = C.dim,
        align = airui.TEXT_ALIGN_LEFT,
    })
    airui.label({
        parent = root, x = 632, y = 10, w = 300, h = 22,
        text = "运行参数", font_size = 16, color = C.dim,
        align = airui.TEXT_ALIGN_LEFT,
    })

    -- 两个弧表读数
    o.lbArc = {}
    for i = 1, 2 do
        o.lbArc[i] = airui.label({
            parent = root, x = 632 + (i - 1) * 180, y = 178, w = 180, h = 24,
            text = "--", font_size = 17, color = C.txt,
            align = airui.TEXT_ALIGN_CENTER,
        })
    end

    -- 2 台泵状态行：文字一行、能量条一行，严格分离
    o.lbPump = {}
    for i = 1, 2 do
        o.lbPump[i] = airui.label({
            parent = root, x = 632, y = 222 + (i - 1) * 50, w = 340, h = 22,
            text = "", font_size = 15, color = C.dim,
            align = airui.TEXT_ALIGN_LEFT,
        })
    end

    o.lbStat = airui.label({
        parent = root, x = 632, y = 330, w = 340, h = 20,
        text = "", font_size = 15, color = C.dim,
        align = airui.TEXT_ALIGN_LEFT,
    })
    o.lbStat2 = airui.label({
        parent = root, x = 632, y = 404, w = 340, h = 20,
        text = "", font_size = 15, color = C.dim,
        align = airui.TEXT_ALIGN_LEFT,
    })

    -- 缓动状态
    o.press, o.flow = 0.45, 0.6
    o.level = 0.62
    return o
end

function M.update(o, t, dt)
    local P = o.pool
    local W, H = o.w, o.h
    P:reset()

    -- ==================== 左：工艺流程 ====================
    P:frame(16, 36, 596, 396, C.line, 1, 120, 10)

    -- 蓄水池（左侧方槽）：液位 + 波浪线
    local TX, TY, TW, TH = 40, 120, 150, 280
    P:frame(TX, TY, TW, TH, C.line, 2, 200, 6)
    o.level = fx.clamp(o.level + 0.04 * dt * (fx.noise1(t * 0.25) - 0.48), 0.25, 0.9)
    local wy = TY + TH - TH * o.level
    P:box(TX + 3, wy, TW - 6, TY + TH - 3 - wy, C.blue, 90, 0)
    local xs, ys = {}, {}
    for i = 1, 13 do
        xs[i] = TX + 3 + (TW - 6) * (i - 1) / 12
        ys[i] = wy + 4 * math.sin(t * 1.6 + i * 0.9)
    end
    P:poly(xs, ys, 13, 0x6FB6FF, 2, 220, true)

    -- 2 台水泵（圆壳 + 旋转叶轮）→ 出水汇流管
    for i = 1, 2 do
        local px, py = 290, 150 + (i - 1) * 140
        local run = not (i == 2 and (t % 16) > 12)   -- 2# 泵周期性停机
        -- 吸水管：水池 → 泵
        P:line(TX + TW, TY + TH * 0.5, 250, TY + TH * 0.5, C.dim2, 2, 160, true)
        P:line(250, TY + TH * 0.5, 250, py, C.dim2, 2, 160, true)
        P:line(250, py, px - 26, py, C.dim2, 2, 160, true)
        -- 泵体
        P:dot(px, py, 24, C.panel2, 255)
        P:ring(px, py, 24, run and C.cyan or C.dim2, 3, 255)
        -- 叶轮（3 片，旋转）
        local a0 = t * (run and 5.2 or 0) + i * 1.2
        for k = 0, 2 do
            local a = a0 + k * 120
            P:line(px, py, px + math.cos(math.rad(a)) * 17, py + math.sin(math.rad(a)) * 17,
                run and C.cyan or C.dim2, 3, 230, true)
        end
        -- 出水管：泵 → 汇流立管
        P:line(px + 26, py, 500, py, run and C.cyan or C.dim2, 3, run and 190 or 110, true)
        if run then
            for k = 0, 3 do
                local f = ((t * 0.6 + k / 4 + i * 0.2) % 1)
                P:dot(px + 26 + (500 - px - 26) * f, py, 3, 0x9BF2FF, 210)
            end
        end
    end

    -- 汇流立管 + 出厂管（带电动阀）
    local OX = 500
    P:neon(OX, 150, OX, 290, C.cyan, 3, 210)
    for k = 0, 3 do
        local f = ((t * 0.55 + k / 4) % 1)
        P:dot(OX, 150 + 140 * f, 3, 0x9BF2FF, 200)
    end
    P:neon(OX, 220, 588, 220, C.cyan, 3, 210)
    for k = 0, 3 do
        local f = ((t * 0.55 + k / 4) % 1)
        P:dot(OX + (588 - OX) * f, 220, 3, 0x9BF2FF, 200)
    end
    -- 电动阀（开度指示）
    local vopen = 0.55 + 0.35 * (0.5 + 0.5 * math.sin(t * 0.35))
    local VX = 556
    P:box(VX - 12, 208, 24, 24, C.panel2, 255, 4)
    P:frame(VX - 12, 208, 24, 24, C.green, 2, 255, 4)
    P:line(VX, 220, VX + math.cos(-math.pi / 2 + vopen * math.pi / 2) * 9,
        220 + math.sin(-math.pi / 2 + vopen * math.pi / 2) * 9, C.green, 2, 255, true)
    fx.meter(P, VX - 46, 246, 92, 8, vopen, C.green)

    -- 出厂压力表柱（工艺图右下）
    local pfrac = 0.45 + 0.22 * (0.5 + 0.5 * math.sin(t * 0.5 + 1.3))
    fx.meter(P, 260, 356, 220, 12, pfrac, C.amber)

    -- ==================== 右：弧表 + 泵组 + 统计 ====================
    local R = 632
    local pressT = 0.45 + 0.2 * (0.5 + 0.5 * math.sin(t * 0.5 + 1.3))
    local flowT = 0.6 + 0.22 * (0.5 + 0.5 * math.sin(t * 0.42 + 0.4))
    o.press = fx.approach(o.press, pressT, 0.08, dt)
    o.flow = fx.approach(o.flow, flowT, 0.08, dt)

    local arcSpec = {
        { frac = o.press, col = C.amber, name = "出口压力", v = 0.25 + o.press * 0.45, unit = "MPa", fmt = "%.2f" },
        { frac = o.flow,  col = C.cyan,  name = "瞬时流量", v = 120 + o.flow * 480,   unit = "m3/h", fmt = "%.0f" },
    }
    for i, sp in ipairs(arcSpec) do
        local cx = R + 88 + (i - 1) * 180
        local cy = 112
        P:arc(cx, cy, 56, 135, 405, C.line, 10, 255, true)
        P:arc(cx, cy, 56, 135, fx.sweep(sp.frac, 135, 405), sp.col, 10, 255, true)
    end

    -- 泵组效率 / 能耗（位于对应状态文字行下方）
    for i = 1, 2 do
        local run = not (i == 2 and (t % 16) > 12)
        local eff = 0.62 + 0.18 * (0.5 + 0.5 * math.sin(t * 0.3 + i * 2))
        fx.meter(P, R, 246 + (i - 1) * 50, 328, 12, run and eff or 0.02,
            run and C.green or C.dim2)
    end

    -- 当日供水量（双条对比：今日 / 昨日）
    local today = 0.55 + 0.2 * (0.5 + 0.5 * math.sin(t * 0.2))
    fx.meter(P, R, 354, 328, 12, today, C.blue)
    fx.meter(P, R, 380, 328, 12, today * 0.86, C.dim2)

    -- ==================== 文字节流刷新 ====================
    o.txtT = o.txtT - dt
    if o.txtT <= 0 then
        o.txtT = 0.25
        for i, sp in ipairs(arcSpec) do
            o.lbArc[i]:set_text(string.format("%s " .. sp.fmt .. " %s", sp.name, sp.v, sp.unit))
        end
        for i = 1, 2 do
            local run = not (i == 2 and (t % 16) > 12)
            local eff = 0.62 + 0.18 * (0.5 + 0.5 * math.sin(t * 0.3 + i * 2))
            o.lbPump[i]:set_text(string.format("%d# 泵  %s  效率 %d%%  %s",
                i, run and "运行" or "停机", fl((run and eff or 0) * 100),
                run and (fl(38 + eff * 22) .. " kW") or "-- kW"))
        end
        o.lbStat:set_text(string.format("今日供水 %d m3   昨日同期 %d m3",
            fl(3200 + today * 1800), fl(3200 + today * 0.86 * 1800)))
        o.lbStat2:set_text(string.format("水池液位 %d%%   阀门开度 %d%%",
            fl(o.level * 100), fl(vopen * 100)))
    end

    o.n = P:finish()
    o.shape:set_items(P.items)
end

return M
