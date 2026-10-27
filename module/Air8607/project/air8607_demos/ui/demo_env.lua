--[[
@module  demo_env
@summary 应用场景 4 - 环保监测
@date    2026.10.26
@effect
左侧区域地图风向图：监测点位分布 + 扩散光圈（涟漪）+ 风向流动粒子，
模拟污染物扩散态势。右侧环境指标区：AQI 圆弧仪表（带色带分段）、
PM2.5 / SO₂ / NOx 三条实时曲线（滚动波形）、噪声与气象卡片。
所有曲线由平滑噪声驱动，读数与波形同步、250ms 节流刷新。
]]
local fx = require "fx"

local M = {
    id = "env",
    name = "环保",
    desc = "环保监测：扩散态势 + AQI 圆表 + 污染物滚动波形",
}

local C = fx.C
local fl = math.floor

-- 监测点位（左侧图内坐标、基础污染强度）
local POINTS = {
    { x = 120, y = 120, base = 0.55, name = "厂区东" },
    { x = 300, y = 90,  base = 0.35, name = "居民区" },
    { x = 420, y = 200, base = 0.72, name = "烟囱下风" },
    { x = 180, y = 300, base = 0.42, name = "河道断面" },
    { x = 500, y = 330, base = 0.30, name = "对照点" },
}

function M.build(root, W, H)
    local o = { w = W, h = H, pool = fx.pool(), txtT = 0 }
    o.shape = airui.shape({ parent = root, x = 0, y = 0, w = W, h = H, items = {} })

    airui.label({
        parent = root, x = 16, y = 10, w = 320, h = 22,
        text = "区域扩散态势", font_size = 16, color = C.dim,
        align = airui.TEXT_ALIGN_LEFT,
    })
    airui.label({
        parent = root, x = 632, y = 10, w = 300, h = 22,
        text = "环境质量实时数据", font_size = 16, color = C.dim,
        align = airui.TEXT_ALIGN_LEFT,
    })

    -- AQI 读数（圆表中央）
    o.lbAqi = airui.label({
        parent = root, x = 702, y = 112, w = 180, h = 46,
        text = "--", font_size = 38, color = C.green,
        align = airui.TEXT_ALIGN_CENTER,
    })
    airui.label({
        parent = root, x = 702, y = 158, w = 180, h = 20,
        text = "空气质量指数 AQI", font_size = 14, color = C.dim2,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- 三条波形读数
    o.lbWave = {}
    for i = 1, 3 do
        o.lbWave[i] = airui.label({
            parent = root, x = 632, y = 202 + (i - 1) * 58, w = 340, h = 18,
            text = "", font_size = 14, color = C.dim,
            align = airui.TEXT_ALIGN_LEFT,
        })
    end

    -- 气象/噪声卡片两行
    o.lbCard = airui.label({
        parent = root, x = 632, y = 386, w = 340, h = 20,
        text = "", font_size = 14, color = C.dim,
        align = airui.TEXT_ALIGN_LEFT,
    })
    o.lbCard2 = airui.label({
        parent = root, x = 632, y = 410, w = 340, h = 20,
        text = "", font_size = 14, color = C.dim,
        align = airui.TEXT_ALIGN_LEFT,
    })

    -- 三条滚动波形缓冲（每条 48 点）
    o.buf = {}
    for c = 1, 3 do
        local a = {}
        for i = 1, 48 do a[i] = 0.3 + 0.3 * fx.noise1(i * 0.31 + c * 7) end
        o.buf[c] = a
    end
    return o
end

function M.update(o, t, dt)
    local P = o.pool
    local W, H = o.w, o.h
    P:reset()

    -- ==================== 左：扩散态势图 ====================
    P:frame(16, 36, 596, 396, C.line, 1, 120, 10)

    -- 底图网格
    for gx = 1, 5 do
        P:line(16 + gx * 99, 42, 16 + gx * 99, 426, C.line, 1, 40, false)
    end
    for gy = 1, 3 do
        P:line(22, 36 + gy * 99, 606, 36 + gy * 99, C.line, 1, 40, false)
    end

    -- 风向流动粒子（从西北向东南）
    for k = 0, 11 do
        local f = ((t * 0.16 + k / 12) % 1)
        local px = 40 + f * 520
        local py = 60 + f * 300 + 26 * math.sin(f * 6 + k)
        P:dot(px, py, 2, 0x3E6D96, 130)
    end

    -- 监测点位：扩散涟漪 + 核心 + 强度环
    for i, pt in ipairs(POINTS) do
        local lv = fx.clamp(pt.base + 0.12 * math.sin(t * 0.5 + i * 1.9), 0, 1)
        -- 两圈涟漪（相位错开）
        for k = 0, 1 do
            local ph = ((t * 0.4 + k * 0.5 + i * 0.17) % 1)
            local r = 10 + ph * 34
            local opa = fl((1 - ph) * 130 * (0.4 + lv * 0.6))
            local col = lv > 0.6 and C.red or (lv > 0.4 and C.amber or C.green)
            P:ring(pt.x, pt.y, r, col, 2, opa)
        end
        local col = lv > 0.6 and C.red or (lv > 0.4 and C.amber or C.green)
        P:dot(pt.x, pt.y, 6, col, 255)
        P:ring(pt.x, pt.y, 11, col, 2, 180)
    end

    -- 风向标（右上角）
    local wa = t * 0.12
    local wx, wy = 548, 78
    P:ring(wx, wy, 22, C.dim2, 1, 120)
    P:line(wx, wy, wx + math.cos(wa) * 18, wy + math.sin(wa) * 18, C.cyan, 3, 230, true)
    P:dot(wx, wy, 3, C.cyan, 255)

    -- ==================== 右：AQI 圆表 + 波形 + 卡片 ====================
    local R = 632
    local cx, cy = R + 142, 108
    local aqiF = 0.42 + 0.22 * (0.5 + 0.5 * math.sin(t * 0.28)) + 0.05 * fx.noise1(t * 0.5)
    local aqi = fl(30 + aqiF * 220)

    -- 色带分段弧（优/良/轻度/中度 4 段静态色带 + 动态指针弧）
    P:arc(cx, cy, 64, 135, 202, C.green, 10, 170, true)
    P:arc(cx, cy, 64, 206, 273, C.amber, 10, 170, true)
    P:arc(cx, cy, 64, 277, 344, 0xFF8A3D, 10, 170, true)
    P:arc(cx, cy, 64, 348, 405, C.red, 10, 170, true)
    local aqiCol = (aqi < 100) and C.green or ((aqi < 150) and C.amber or C.red)
    P:arc(cx, cy, 64, 135, fx.sweep(aqiF, 135, 405), 0xFFFFFF, 10, 255, true)
    P:ring(cx, cy, 48, C.line, 1, 120)

    -- 三条滚动波形
    local spec = {
        { name = "PM2.5", unit = "ug/m3", col = C.cyan,    lo = 18, hi = 86 },
        { name = "SO2",   unit = "ug/m3", col = C.violet,  lo = 6,  hi = 42 },
        { name = "NOx",   unit = "ug/m3", col = C.magenta, lo = 20, hi = 96 },
    }
    for c = 1, 3 do
        local a = o.buf[c]
        for i = 1, 48 do
            a[i] = fx.clamp(a[i] + 0.014 * (fx.noise1(t * 0.5 + i * 0.45 + c * 11) - 0.5), 0.08, 0.95)
        end
        local y0 = 210 + (c - 1) * 58
        P:frame(R, y0 + 18, 340, 30, C.line, 1, 70, 4)
        fx.spark(P, a, 48, R + 2, y0 + 20, 336, 26, spec[c].col, 2, 235)
    end

    -- ==================== 文字节流刷新 ====================
    o.txtT = o.txtT - dt
    if o.txtT <= 0 then
        o.txtT = 0.25
        o.lbAqi:set_text(tostring(aqi))
        o.lbAqi:set_color(aqiCol)
        for c = 1, 3 do
            local sp = spec[c]
            local v = sp.lo + o.buf[c][48] * (sp.hi - sp.lo)
            local grade = (o.buf[c][48] > 0.66) and "超标预警" or ((o.buf[c][48] > 0.38) and "接近限值" or "达标")
            o.lbWave[c]:set_text(string.format("%s  %.0f %s   %s", sp.name, v, sp.unit, grade))
        end
        o.lbCard:set_text(string.format("气象：风速 %.1f m/s  东南风  湿度 %d%%",
            2.2 + 1.4 * fx.noise1(t * 0.3), fl(58 + 16 * fx.noise1(t * 0.2 + 4))))
        o.lbCard2:set_text(string.format("噪声 %.1f dB(A)   恶臭浓度 %d（无量纲）",
            52 + 8 * fx.noise1(t * 0.25 + 8), fl(12 + 9 * fx.noise1(t * 0.22 + 2))))
    end

    o.n = P:finish()
    o.shape:set_items(P.items)
end

return M
