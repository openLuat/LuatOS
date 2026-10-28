--[[
@module  demo_energy
@summary 应用场景 5 - 储能管理
@date    2026.10.26
@effect
左侧能量拓扑：电网 / PCS 变流器 / 电池堆 / 光伏 / 负荷五节点连线，
能量光点的流向随"充电 / 放电"模式每 8 秒切换一次；下方电池簇矩阵
（8x4 模块格）按 SOC 着色，运行模块呼吸闪烁。
右侧储能参数区：SOC 大圆表 + 充放电功率条（零点居中，正负分流向色）、
3 组电池簇温度、今日充/放电量统计。SOC 随模式缓慢单调爬升/下降。
]]
local fx = require "fx"

local M = {
    id = "energy",
    name = "储能",
    desc = "储能管理：能量拓扑 + SOC/功率监测 + 电池簇矩阵",
}

local C = fx.C
local fl = math.floor

-- 五节点坐标（build 画名称标签、update 画连线，共用一份定义）
local NODES = {
    grid = { x = 90,  y = 110, name = "电网" },
    pv   = { x = 300, y = 62,  name = "光伏" },
    pcs  = { x = 300, y = 170, name = "PCS" },
    batt = { x = 520, y = 110, name = "电池堆" },
    load = { x = 300, y = 282, name = "负荷" },
}

function M.build(root, W, H)
    local o = { w = W, h = H, pool = fx.pool(), txtT = 0 }
    o.shape = airui.shape({ parent = root, x = 0, y = 0, w = W, h = H, items = {} })

    airui.label({
        parent = root, x = 16, y = 10, w = 320, h = 22,
        text = "储能系统能量拓扑", font_size = 16, color = C.dim,
        align = airui.TEXT_ALIGN_LEFT,
    })
    airui.label({
        parent = root, x = 632, y = 10, w = 300, h = 22,
        text = "储能运行参数", font_size = 16, color = C.dim,
        align = airui.TEXT_ALIGN_LEFT,
    })

    -- SOC 大数读数
    o.lbSoc = airui.label({
        parent = root, x = 702, y = 112, w = 180, h = 46,
        text = "--%", font_size = 38, color = C.cyan,
        align = airui.TEXT_ALIGN_CENTER,
    })
    airui.label({
        parent = root, x = 702, y = 158, w = 180, h = 20,
        text = "电池荷电状态 SOC", font_size = 14, color = C.dim2,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- 功率与模式
    o.lbP = airui.label({
        parent = root, x = 632, y = 196, w = 340, h = 20,
        text = "", font_size = 16, color = C.txt,
        align = airui.TEXT_ALIGN_LEFT,
    })

    -- 3 组簇温：文字一行、温度条一行，严格分离
    o.lbTemp = {}
    for i = 1, 3 do
        o.lbTemp[i] = airui.label({
            parent = root, x = 632, y = 242 + (i - 1) * 40, w = 340, h = 20,
            text = "", font_size = 14, color = C.dim,
            align = airui.TEXT_ALIGN_LEFT,
        })
    end

    -- 今日充/放电量（文字一行、对比条一行）
    o.lbKwh = airui.label({
        parent = root, x = 632, y = 356, w = 340, h = 20,
        text = "", font_size = 15, color = C.dim,
        align = airui.TEXT_ALIGN_LEFT,
    })
    o.lbKwh2 = airui.label({
        parent = root, x = 632, y = 398, w = 340, h = 20,
        text = "", font_size = 15, color = C.dim,
        align = airui.TEXT_ALIGN_LEFT,
    })

    o.soc = 0.56

    -- 拓扑节点名称（静态文本）
    for _, nd in pairs(NODES) do
        airui.label({
            parent = root, x = nd.x - 40, y = nd.y - 10, w = 80, h = 20,
            text = nd.name, font_size = 13, color = C.dim,
            align = airui.TEXT_ALIGN_CENTER,
        })
    end
    return o
end

function M.update(o, t, dt)
    local P = o.pool
    local W, H = o.w, o.h
    P:reset()

    -- ==================== 左：能量拓扑 ====================
    P:frame(16, 36, 596, 396, C.line, 1, 120, 10)

    -- 模式切换：8 秒一个周期（0..8 充电，8..16 放电）
    local charge = (t % 16) < 8
    local mode = charge and 1 or -1     -- 光点流动方向

    -- 五节点坐标（与 build 共用模块级 NODES）
    local NODE = NODES

    -- 连线 + 流动光点（方向随模式）
    local links = {
        { "grid", "pcs" }, { "pv", "pcs" }, { "pcs", "batt" }, { "pcs", "load" },
    }
    for li, lk in ipairs(links) do
        local a, b = NODE[lk[1]], NODE[lk[2]]
        P:line(a.x, a.y, b.x, b.y, C.line, 3, 220, true)
        local dx, dy = b.x - a.x, b.y - a.y
        local dark = (lk[1] == "load")     -- 负荷线只出不进
        for k = 0, 2 do
            local f = ((t * 0.5 + k / 3 + li * 0.17) % 1)
            if mode < 0 and not dark then
                f = 1 - f    -- 放电时电源侧（电网/光伏/电池）光点反向
            end
            local col = charge and C.green or C.amber
            if dark then col = C.cyan end
            P:dot(a.x + dx * f, a.y + dy * f, 3, col, 210)
        end
    end

    -- 节点框
    for _, nd in pairs(NODE) do
        local w2, h2 = 66, 34
        P:box(nd.x - w2 / 2, nd.y - h2 / 2, w2, h2, C.panel2, 255, 6)
        P:frame(nd.x - w2 / 2, nd.y - h2 / 2, w2, h2, C.line, 1, 255, 6)
    end

    -- 电池簇矩阵 8x4（下方）：颜色随 SOC，运行簇呼吸
    local GX, GY, CW, CH = 60, 330, 62, 22
    for r = 0, 3 do
        for c = 0, 7 do
            local i = r * 8 + c
            local socI = fx.clamp(o.soc + 0.06 * math.sin(i * 1.7) - 0.03, 0.05, 1)
            local col = fx.mix(C.violet, C.green, socI)
            local pulse = 0.72 + 0.28 * (0.5 + 0.5 * math.sin(t * 2 + i * 0.6))
            P:box(GX + c * (CW + 4), GY + r * (CH + 4), CW, CH, col, fl(150 + 90 * pulse), 3)
        end
    end

    -- ==================== 右：SOC 弧 + 功率条 + 簇温 ====================
    local R = 632
    local cx, cy = R + 142, 108
    local socT = fx.clamp(o.soc + dt * (charge and 0.006 or -0.007), 0.12, 0.95)
    o.soc = fx.approach(o.soc, socT, 0.5, dt)

    P:arc(cx, cy, 64, 135, 405, C.line, 12, 255, true)
    local socCol = fx.mix(C.amber, C.green, (o.soc - 0.15) / 0.8)
    P:arc_grad(cx, cy, 64, 135, fx.sweep(o.soc, 135, 405), 12,
        socCol, fx.shade(socCol, 0.3), 12, 255)

    -- 功率条：零点居中，左=充电（绿），右=放电（橙）
    local pw = 0.35 + 0.3 * (0.5 + 0.5 * math.sin(t * 0.6))
    local PX, PY, PW = R + 20, 222, 300
    P:line(PX + PW / 2, PY - 4, PX + PW / 2, PY + 18, C.dim2, 1, 180, false)
    if charge then
        fx.meter(P, PX + PW / 2 - PW * 0.5 * pw, PY, PW * 0.5 * pw, 12, 1, C.green)
    else
        fx.meter(P, PX + PW / 2, PY, PW * 0.5 * pw, 12, 1, C.amber)
    end

    -- 3 组簇温条（位于对应温度文字行下方）
    for i = 1, 3 do
        local temp = 26 + 6 * fx.noise1(t * 0.3 + i * 5)
        local frac = fx.clamp((temp - 18) / 30, 0, 1)
        fx.meter(P, R + 118, 264 + (i - 1) * 40, 210, 10, frac,
            (temp > 32) and C.amber or C.cyan)
    end

    -- 今日充/放电对比条
    local kch = 0.62 + 0.15 * math.sin(t * 0.18)
    fx.meter(P, R, 380, 328, 12, kch, C.green)
    fx.meter(P, R, 422, 328, 12, kch * 0.78, C.amber)

    -- ==================== 文字节流刷新 ====================
    o.txtT = o.txtT - dt
    if o.txtT <= 0 then
        o.txtT = 0.25
        o.lbSoc:set_text(string.format("%d%%", fl(o.soc * 100)))
        o.lbSoc:set_color(socCol)
        o.lbP:set_text(string.format("运行模式：%s   功率 %.0f kW",
            charge and "充电" or "放电", 180 + pw * 620))
        for i = 1, 3 do
            local temp = 26 + 6 * fx.noise1(t * 0.3 + i * 5)
            o.lbTemp[i]:set_text(string.format("%d# 电池簇   温度 %.1f ℃   状态 %s",
                i, temp, (temp > 32) and "偏高" or "正常"))
        end
        o.lbKwh:set_text(string.format("今日充电 %d kWh", fl(2400 + kch * 1600)))
        o.lbKwh2:set_text(string.format("今日放电 %d kWh   循环寿命 %d 次",
            fl(2400 + kch * 0.78 * 1600), 1286 + fl(t / 40)))
    end

    o.n = P:finish()
    o.shape:set_items(P.items)
end

return M
