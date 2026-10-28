--[[
@module  demo_power
@summary 应用场景 1 - 智慧配电房电力运维
@date    2026.10.26
@effect
左侧配电单线图：进线断路器 + 两段母线 + 4 路馈线，
母线与馈线上有流动的"电流光点"表示带电潮流方向，断路器状态灯呼吸。
右侧电力参数区：三相电压弧形表（A/B/C 相）、关键回路负载率能量条、
24 点负荷趋势迷你曲线。数值 250ms 节流刷新，避免每帧重排文本。
]]
local fx = require "fx"

local M = {
    id = "power",
    name = "配电房",
    desc = "智慧配电房电力运维：单线图潮流 + 三相监测 + 负荷趋势",
}

local C = fx.C
local fl = math.floor

-- 馈线定义：母线挂点 x、名称、基础负载率
local FEEDERS = {
    { x = 120, name = "1# 变压器", base = 0.72 },
    { x = 250, name = "2# 变压器", base = 0.58 },
    { x = 380, name = "无功补偿",  base = 0.34 },
    { x = 510, name = "应急电源",  base = 0.12 },
}

function M.build(root, W, H)
    local o = { w = W, h = H, pool = fx.pool(), txtT = 0 }
    o.shape = airui.shape({ parent = root, x = 0, y = 0, w = W, h = H, items = {} })

    -- ===== 左：单线图面板 =====
    o.lbTitle = airui.label({
        parent = root, x = 16, y = 10, w = 300, h = 22,
        text = "10kV 配电单线图", font_size = 16, color = C.dim,
        align = airui.TEXT_ALIGN_LEFT,
    })

    -- ===== 右：参数面板标题 =====
    airui.label({
        parent = root, x = 632, y = 10, w = 300, h = 22,
        text = "实时电力参数", font_size = 16, color = C.dim,
        align = airui.TEXT_ALIGN_LEFT,
    })

    -- 三相电压读数（对应三个弧表）
    o.lbU = {}
    for i = 1, 3 do
        o.lbU[i] = airui.label({
            parent = root, x = 632 + (i - 1) * 118, y = 178, w = 112, h = 22,
            text = "--.- V", font_size = 17, color = C.txt,
            align = airui.TEXT_ALIGN_CENTER,
        })
    end

    -- 负载率行（4 条能量条的读数）：文字一行、能量条一行，严格分离避免叠画
    o.lbLoad = {}
    for i = 1, 4 do
        o.lbLoad[i] = airui.label({
            parent = root, x = 632, y = 210 + (i - 1) * 44, w = 340, h = 20,
            text = "", font_size = 15, color = C.dim,
            align = airui.TEXT_ALIGN_LEFT,
        })
    end

    -- 负荷趋势读数
    o.lbTrend = airui.label({
        parent = root, x = 632, y = 384, w = 340, h = 18,
        text = "今日峰荷 -- kW / 谷荷 -- kW", font_size = 15, color = C.dim,
        align = airui.TEXT_ALIGN_LEFT,
    })

    -- 负荷趋势缓冲（24 点，0..1）
    o.trend = {}
    local rnd = fx.rng(20261026)
    for i = 1, 24 do
        o.trend[i] = 0.35 + 0.5 * fx.noise1(i * 0.7)
    end
    o.rnd = rnd

    -- 三相电压缓动值
    o.u = { 220, 220, 220 }

    -- 馈线名（静态文本，build 时一次建好）
    o.fdNames = {}
    for i, fd in ipairs(FEEDERS) do
        o.fdNames[i] = airui.label({
            parent = root, x = 16 + fd.x - 52, y = 312, w = 104, h = 18,
            text = fd.name, font_size = 13, color = C.dim,
            align = airui.TEXT_ALIGN_CENTER,
        })
    end
    return o
end

function M.update(o, t, dt)
    local P = o.pool
    local W, H = o.w, o.h
    P:reset()

    -- ==================== 左：单线图 ====================
    local L = 16
    local BUS_Y = 196                 -- 母线 y
    P:frame(L, 36, 596, 396, C.line, 1, 120, 10)

    -- 进线：竖直线路 + 断路器方块
    local IN_X = L + 298
    P:line(IN_X, 56, IN_X, 120, C.cyan, 3, 220, true)
    P:box(IN_X - 14, 120, 28, 28, C.panel2, 255, 4)
    P:frame(IN_X - 14, 120, 28, 28, C.green, 2, 255, 4)
    P:line(IN_X - 8, 134, IN_X + 8, 134, C.green, 3, 255, true)
    P:line(IN_X, 148, IN_X, BUS_Y - 6, C.cyan, 3, 220, true)

    -- 母线（两段）：潮流光点沿线流动
    local b0, b1 = L + 40, L + 556
    P:neon(b0, BUS_Y, b1, BUS_Y, C.amber, 3, 230)
    for k = 0, 7 do
        local f = ((t * 0.35 + k / 8) % 1)
        local x = b0 + (b1 - b0) * f
        P:dot(x, BUS_Y, 3, 0xFFE9B8, 210)
    end
    -- 母联开关
    local TIE_X = L + 298
    P:box(TIE_X - 10, BUS_Y - 10, 20, 20, C.deep, 255, 3)
    P:frame(TIE_X - 10, BUS_Y - 10, 20, 20, C.green, 2, 255, 3)

    -- 馈线：竖直出线 + 光点下落 + 断路器 + 负载率小条
    for i, fd in ipairs(FEEDERS) do
        local x = L + fd.x
        local osc = 0.5 + 0.5 * math.sin(t * 0.9 + i * 1.7)
        local load = fx.clamp(fd.base * (0.9 + 0.12 * osc), 0, 1)

        P:line(x, BUS_Y + 6, x, 250, C.cyan, 2, 170, true)
        for k = 0, 3 do
            local f = ((t * 0.5 + k / 4 + i * 0.13) % 1)
            P:dot(x, BUS_Y + 6 + (250 - BUS_Y - 6) * f, 2, 0x9BF2FF, 190)
        end
        -- 断路器
        P:box(x - 11, 250, 22, 22, C.panel2, 255, 4)
        local trip = (i == 3 and (t % 14) > 11)   -- 3# 周期性分闸演示
        P:frame(x - 11, 250, 22, 22, trip and C.red or C.green, 2, 255, 4)
        P:line(x - 5, 261, x + 5, trip and 267 or 261, trip and C.red or C.green, 2, 255, true)

        -- 下引线 + 负载率条
        P:line(x, 272, x, 296, C.cyan, 2, 130, true)
        fx.meter(P, x - 46, 300, 92, 8, load, (load > 0.85) and C.red or C.amber)
    end

    -- 变压器图标（2 路）+ 温升
    for i = 1, 2 do
        local x = L + FEEDERS[i].x
        P:ring(x, 360, 14, C.violet, 2, 220)
        P:ring(x, 360, 9, C.violet, 2, 160)
        local temp = 62 + 10 * math.sin(t * 0.4 + i)
        local frac = fx.clamp((temp - 40) / 60, 0, 1)
        fx.meter(P, x - 46, 386, 92, 8, frac, (temp > 80) and C.red or C.green)
    end

    -- ==================== 右：三相弧表 + 负载率 + 趋势 ====================
    local R = 632
    for i = 1, 3 do
        local cx = R + 59 + (i - 1) * 118
        local cy = 118
        local target = 220 + 6 * math.sin(t * 0.6 + i * 2.1) + 2 * fx.noise1(t * 0.5 + i)
        o.u[i] = fx.approach(o.u[i], target, 0.08, dt)
        local frac = fx.clamp((o.u[i] - 198) / 44, 0, 1)

        P:arc(cx, cy, 44, 135, 405, C.line, 8, 255, true)
        local col = (i == 1) and C.cyan or ((i == 2) and C.green or C.amber)
        P:arc(cx, cy, 44, 135, fx.sweep(frac, 135, 405), col, 8, 255, true)
        P:dot(cx, cy, 3, C.dim2, 255)
    end

    -- 4 条负载率能量条（位于对应文字行下方 22px）
    for i = 1, 4 do
        local fd = FEEDERS[i]
        local osc = 0.5 + 0.5 * math.sin(t * 0.9 + i * 1.7)
        local load = fx.clamp(fd.base * (0.9 + 0.12 * osc), 0, 1)
        fx.meter(P, R, 232 + (i - 1) * 44, 328, 12, load, (load > 0.85) and C.red or C.cyan)
    end

    -- 24 点负荷趋势
    local TX, TY, TW, TH = R, 406, 340, 30
    P:frame(TX - 2, TY - 2, TW + 4, TH + 4, C.line, 1, 90, 4)
    local vals = o.trend
    for i = 1, 24 do
        vals[i] = fx.clamp(vals[i] + 0.006 * fx.noise1(t * 0.35 + i * 0.9) - 0.003, 0.12, 0.95)
    end
    fx.spark(P, vals, 24, TX, TY, TW, TH, C.violet, 2, 230)

    -- ==================== 文字节流刷新 ====================
    o.txtT = o.txtT - dt
    if o.txtT <= 0 then
        o.txtT = 0.25
        local names = { "A 相", "B 相", "C 相" }
        for i = 1, 3 do
            o.lbU[i]:set_text(string.format("%s %.1f V", names[i], o.u[i]))
        end
        for i = 1, 4 do
            local fd = FEEDERS[i]
            local osc = 0.5 + 0.5 * math.sin(t * 0.9 + i * 1.7)
            local load = fx.clamp(fd.base * (0.9 + 0.12 * osc), 0, 1)
            o.lbLoad[i]:set_text(string.format("%s  负载率 %d%%", fd.name, fl(load * 100)))
        end
        local peak, valley = 0, 1
        for i = 1, 24 do
            if vals[i] > peak then peak = vals[i] end
            if vals[i] < valley then valley = vals[i] end
        end
        o.lbTrend:set_text(string.format("今日峰荷 %d kW / 谷荷 %d kW",
            fl(820 + peak * 380), fl(420 + valley * 260)))
    end

    o.n = P:finish()
    o.shape:set_items(P.items)
end

return M
