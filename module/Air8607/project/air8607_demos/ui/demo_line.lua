--[[
@module  demo_line
@summary 应用场景 3 - 智能产线
@date    2026.10.26
@effect
左侧产线动态图：传送带持续流动、5 个工位依次对经过的工件"加工"
（工位臂下压 + 状态灯变化），工件走到末端进入成品区计数。
右侧智造指标区：OEE 综合大弧 + 可用率/性能/良品率三条能量条、
班次产量与不良数、节拍趋势迷你曲线。工位加工节拍按相位错开，画面成"流水"感。
]]
local fx = require "fx"

local M = {
    id = "line",
    name = "产线",
    desc = "智能产线：传送带工位流 + OEE 能效 + 节拍趋势",
}

local C = fx.C
local fl = math.floor

-- 工位：传送带上的 x 位置、臂长相位
local STATIONS = {
    { x = 130, name = "上料" },
    { x = 250, name = "加工" },
    { x = 370, name = "检测" },
    { x = 490, name = "装配" },
    { x = 590, name = "下料" },
}
local BELT_Y = 250          -- 传送带中心线
local BELT_X0, BELT_X1 = 40, 600

function M.build(root, W, H)
    local o = { w = W, h = H, pool = fx.pool(), txtT = 0 }
    o.shape = airui.shape({ parent = root, x = 0, y = 0, w = W, h = H, items = {} })

    airui.label({
        parent = root, x = 16, y = 10, w = 300, h = 22,
        text = "总装产线实时状态", font_size = 16, color = C.dim,
        align = airui.TEXT_ALIGN_LEFT,
    })
    airui.label({
        parent = root, x = 632, y = 10, w = 300, h = 22,
        text = "OEE 与产出", font_size = 16, color = C.dim,
        align = airui.TEXT_ALIGN_LEFT,
    })

    -- OEE 大数读数
    o.lbOee = airui.label({
        parent = root, x = 702, y = 138, w = 180, h = 44,
        text = "--%", font_size = 36, color = C.cyan,
        align = airui.TEXT_ALIGN_CENTER,
    })
    airui.label({
        parent = root, x = 702, y = 182, w = 180, h = 20,
        text = "综合设备效率 OEE", font_size = 14, color = C.dim2,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- 三条指标条读数
    o.lbKpi = {}
    for i = 1, 3 do
        o.lbKpi[i] = airui.label({
            parent = root, x = 632, y = 232 + (i - 1) * 32, w = 340, h = 22,
            text = "", font_size = 15, color = C.dim,
            align = airui.TEXT_ALIGN_LEFT,
        })
    end

    -- 产量统计两行
    o.lbOut = airui.label({
        parent = root, x = 632, y = 336, w = 340, h = 22,
        text = "", font_size = 15, color = C.dim,
        align = airui.TEXT_ALIGN_LEFT,
    })
    o.lbOut2 = airui.label({
        parent = root, x = 632, y = 362, w = 340, h = 22,
        text = "", font_size = 15, color = C.dim,
        align = airui.TEXT_ALIGN_LEFT,
    })

    -- 节拍趋势缓冲
    o.tempo = {}
    for i = 1, 28 do
        o.tempo[i] = 0.4 + 0.35 * fx.noise1(i * 0.6 + 9)
    end

    -- 工位名（静态文本）
    for i, st in ipairs(STATIONS) do
        airui.label({
            parent = root, x = st.x - 36, y = 188, w = 72, h = 18,
            text = st.name, font_size = 13, color = C.dim,
            align = airui.TEXT_ALIGN_CENTER,
        })
    end
    return o
end

function M.update(o, t, dt)
    local P = o.pool
    local W, H = o.w, o.h
    P:reset()

    -- ==================== 左：产线动态图 ====================
    P:frame(16, 36, 596, 396, C.line, 1, 120, 10)

    -- 传送带：双轨 + 流动的带纹
    P:box(BELT_X0, BELT_Y - 16, BELT_X1 - BELT_X0, 32, C.panel2, 255, 6)
    P:line(BELT_X0, BELT_Y - 16, BELT_X1, BELT_Y - 16, C.line, 2, 255, true)
    P:line(BELT_X0, BELT_Y + 16, BELT_X1, BELT_Y + 16, C.line, 2, 255, true)
    for k = 0, 13 do
        local f = ((t * 0.28 + k / 14) % 1)
        local x = BELT_X0 + (BELT_X1 - BELT_X0) * f
        P:line(x, BELT_Y - 12, x, BELT_Y + 12, C.line, 2, 140, true)
    end

    -- 工件（5 个，随带流动）：走到工位附近被"加工"
    for k = 0, 4 do
        local f = ((t * 0.085 + k / 5) % 1)
        local x = BELT_X0 + 10 + (BELT_X1 - BELT_X0 - 40) * f
        -- 找最近工位，加工中工件发亮
        local near = nil
        for _, st in ipairs(STATIONS) do
            if math.abs(x - st.x) < 18 then near = st break end
        end
        local col = near and C.amber or C.cyan
        P:box(x - 13, BELT_Y - 11, 26, 22, col, near and 255 or 170, 4)
        P:frame(x - 13, BELT_Y - 11, 26, 22, fx.shade(col, 0.35), 1, 255, 4)
    end

    -- 工位：立柱 + 机械臂（周期下压）+ 状态灯
    for i, st in ipairs(STATIONS) do
        local phase = (t * 0.6 + i * 0.77) % 1
        local press = phase < 0.35 and (1 - math.abs(phase / 0.35 - 0.5) * 2) or 0
        local armY = 120 + press * 46

        P:line(st.x, 70, st.x, 120, C.dim2, 3, 220, true)       -- 立柱
        P:box(st.x - 30, 62, 60, 12, C.panel2, 255, 3)          -- 横梁
        P:line(st.x, 120, st.x, armY, C.violet, 3, 230, true)   -- 机械臂
        P:box(st.x - 12, armY, 24, 10, press > 0.05 and C.violet or C.dim2, 230, 2)
        if press > 0.05 then
            P:dot(st.x, armY + 14, 5 + press * 3, C.amber, fl(120 + press * 120))
        end

        -- 状态灯：加工=橙闪，正常=绿常亮
        local lamp = press > 0.05 and C.amber or C.green
        P:dot(st.x + 42, 74, 5, lamp, 255)
        P:dot(st.x + 42, 74, 9, lamp, 70)
    end

    -- 成品区（右端）
    P:box(560, 288, 44, 60, C.panel, 255, 5)
    P:frame(560, 288, 44, 60, C.green, 1, 180, 5)
    for r = 0, 1 do
        for c = 0, 1 do
            P:box(568 + c * 18, 296 + r * 22, 14, 16, C.green, 150, 2)
        end
    end

    -- ==================== 右：OEE + 指标 + 统计 ====================
    local R = 632
    -- OEE 综合弧（大）
    local cx, cy = R + 142, 112
    local oee = 0.72 + 0.1 * (0.5 + 0.5 * math.sin(t * 0.35)) + 0.02 * fx.noise1(t * 0.6)
    P:arc(cx, cy, 62, 135, 405, C.line, 12, 255, true)
    P:arc_grad(cx, cy, 62, 135, fx.sweep(oee, 135, 405), 12,
        C.blue, C.cyan, 12, 255)

    -- 可用率 / 性能 / 良品率
    local kpi = {
        { name = "可用率", v = 0.88 + 0.06 * math.sin(t * 0.3), col = C.cyan },
        { name = "性能率", v = 0.76 + 0.1 * math.sin(t * 0.45 + 1), col = C.violet },
        { name = "良品率", v = 0.94 + 0.03 * math.sin(t * 0.22 + 2), col = C.green },
    }
    for i, k in ipairs(kpi) do
        fx.meter(P, R + 108, 240 + (i - 1) * 32, 220, 12, k.v, k.col)
    end

    -- 节拍趋势
    local TX, TY, TW, TH = R, 388, 340, 28
    P:frame(TX - 2, TY - 2, TW + 4, TH + 4, C.line, 1, 90, 4)
    local tempo = o.tempo
    for i = 1, 28 do
        tempo[i] = fx.clamp(tempo[i] + 0.008 * (fx.noise1(t * 0.4 + i * 0.8) - 0.5), 0.15, 0.95)
    end
    fx.spark(P, tempo, 28, TX, TY, TW, TH, C.amber, 2, 230)

    -- ==================== 文字节流刷新 ====================
    o.txtT = o.txtT - dt
    if o.txtT <= 0 then
        o.txtT = 0.25
        o.lbOee:set_text(string.format("%d.%d%%", fl(oee * 100), fl(oee * 1000) % 10))
        for i, k in ipairs(kpi) do
            o.lbKpi[i]:set_text(string.format("%s  %d%%", k.name, fl(k.v * 100)))
        end
        local done = fl(1200 + t * 1.6)
        o.lbOut:set_text(string.format("班次产量 %d 件   节拍 %.1f s/件", done, 12.4 + 1.6 * fx.noise1(t * 0.2)))
        o.lbOut2:set_text(string.format("不良 %d 件   直通率 %d%%", fl(done * 0.012), fl(kpi[3].v * 100)))
    end

    o.n = P:finish()
    o.shape:set_items(P.items)
end

return M
