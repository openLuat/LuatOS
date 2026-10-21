--[[
@module  fx_scene_gauge
@summary 特效场景 4 - 环形仪表
@version 1.0
@date    2026.10.21
@effect
三层同心环形进度条：airui.shape 没有 arc 图元，这里用「沿圆弧排布的一串实心圆点」
来逼近粗弧线 —— 圆点半径与不透明度从头到尾递增，末端再补一颗高亮头点，
比用折线段画弧更平滑（折线在转角处会露出接缝），代价也只是同样数量的图元。
外圈 36 格刻度盘 + 每环一条暗色导轨。
中心大号数字显示最外环读数，左下角三行图例显示三环实时百分比。
数值每 160ms 才刷新一次文字，避免每帧重排文本拖慢帧率。
]]
local fx = require "fx_core"

local M = {
    id = "gauge",
    name = "环形仪表",
    desc = "三层同心环形进度与外圈刻度盘",
}

local RINGS = {
    { k = 0.40, sp = 0.62, span = 0.70, hue = 188, dots = 24, name = "CPU", base = 62 },
    { k = 0.31, sp = -0.95, span = 0.82, hue = 288, dots = 22, name = "GPU", base = 48 },
    { k = 0.22, sp = 1.45, span = 0.62, hue = 336, dots = 20, name = "MEM", base = 71 },
}
local TICKS = 24
local DOT_MAX = 9

--[[基准半径：0.40 x 短边
再大就会让「最外环 + 环点半径 + 刻度盘」一起顶出舞台上下沿被裁掉。
短边 446 → RR=178，最外环外沿 187、刻度盘外沿 202，上下各留 20px 余量。]]
local function base_r(W, H)
    return math.min(W, H) * 0.40
end

function M.build(parent, W, H)
    local o = { w = W, h = H, pool = fx.pool(), txtT = 0 }
    o.shape = airui.shape({ parent = parent, x = 0, y = 0, w = W, h = H, items = {} })

    local cx, cy = W * 0.5, H * 0.5
    local RR = base_r(W, H)

    -- 中心大号读数（最外环数值）
    o.big = airui.label({
        parent = parent, x = math.floor(cx - 90), y = math.floor(cy - 26),
        w = 180, h = 52, text = "--", font_size = 40,
        color = fx.C.cyan, align = airui.TEXT_ALIGN_CENTER,
    })
    airui.label({
        parent = parent, x = math.floor(cx - 90), y = math.floor(cy + 26),
        w = 180, h = 22, text = "SYSTEM LOAD", font_size = 16,
        color = fx.C.dim2, align = airui.TEXT_ALIGN_CENTER,
    })

    -- 刻度盘角度固定，预存方向分量（原写法每帧 36x2 = 72 次三角函数）
    o.tc, o.ts = {}, {}
    for k = 0, TICKS - 1 do
        local a = k * fx.TAU / TICKS
        o.tc[k] = math.cos(a)
        o.ts[k] = math.sin(a)
    end

    -- 左下角图例
    o.legend = {}
    for i, rg in ipairs(RINGS) do
        o.legend[i] = airui.label({
            parent = parent, x = 18, y = H - 96 + (i - 1) * 26,
            w = 190, h = 24, text = rg.name .. "  --", font_size = 18,
            color = fx.hsl(rg.hue, 0.85, 0.68), align = airui.TEXT_ALIGN_LEFT,
        })
    end
    return o
end

function M.update(o, t, dt)
    local P = o.pool
    local W, H = o.w, o.h
    local cx, cy = W * 0.5, H * 0.5
    local RR = base_r(W, H)
    P:reset()

    -- 外圈刻度盘（角度固定，方向分量在 build 时已算好）
    for k = 0, TICKS - 1 do
        local c, s = o.tc[k], o.ts[k]
        local long = (k % 3 == 0)
        local r0 = RR * (long and 1.06 or 1.09)
        local r1 = RR * 1.14
        P:line(cx + c * r0, cy + s * r0, cx + c * r1, cy + s * r1,
            long and 0x35E0FF or 0x1E5C7A, long and 2 or 1, long and 190 or 110, true)
    end

    local pct = {}
    for i, rg in ipairs(RINGS) do
        local r = RR * (rg.k / 0.40)
        local col = fx.hsl(rg.hue + t * 8, 0.9, 0.56)

        --[[暗色导轨（整圈）
        LVGL 的圆环描边是往圆心方向画的，所以半径要外扩 DOT_MAX、描边宽取 2*DOT_MAX，
        才能让导轨带恰好覆盖「环点能占到的范围」(r-DOT_MAX .. r+DOT_MAX)，
        否则环点会有一半压在导轨外面。]]
        P:ring(cx, cy, math.floor(r) + DOT_MAX, 0x16243C, DOT_MAX * 2, 255)

        -- 弧长随时间呼吸，读数同步变化
        local breathe = 0.62 + 0.38 * (0.5 + 0.5 * fx.sin(t * 0.8 + i * 1.4))
        local span = rg.span * fx.TAU * breathe
        local a0 = t * rg.sp
        local val = fx.clamp(breathe, 0, 1)
        pct[i] = math.floor(val * 100)

        local D = rg.dots
        for k = 0, D - 1 do
            local f = k / (D - 1)
            local a = a0 + f * span
            local dr = 2 + (DOT_MAX - 2) * f * f
            local opa = math.floor(60 + 195 * f)
            P:dot(cx + fx.cos(a) * r, cy + fx.sin(a) * r, dr, col, opa)
        end
        -- 头部高亮
        local ah = a0 + span
        P:ring(cx + fx.cos(ah) * r, cy + fx.sin(ah) * r, DOT_MAX + 3, 0xFFFFFF, 2, 160)
        P:dot(cx + fx.cos(ah) * r, cy + fx.sin(ah) * r, DOT_MAX - 1, 0xFFFFFF, 255)
    end

    --[[文字刷新：set_text 会让 LVGL 重排文本并额外产生一块脏区，
    所以降频到 250ms，且中心大号读数只在数值真的变了才写。]]
    o.txtT = (o.txtT or 0) - dt
    if o.txtT <= 0 then
        o.txtT = 0.25
        if pct[1] ~= o.lastPct then
            o.lastPct = pct[1]
            o.big:set_text(tostring(pct[1]) .. "%")
            o.big:set_color(fx.hsl(RINGS[1].hue + t * 8, 0.9, 0.72))
        end
        for i, rg in ipairs(RINGS) do
            o.legend[i]:set_text(string.format("%s  %d%%", rg.name, pct[i]))
        end
    end

    o.n = P:finish()
    o.shape:set_items(P.items)
end

return M
