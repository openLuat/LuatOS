--[[
@module  page_air
@summary 华康无菌车间 - 第 3 页 送风（AHU 运行参数 / 三级滤器 / 风路 / 能耗）
@version 1.0
@date    2026.11.11

这一页回答"送风侧还撑不撑得住"。
压差失守时，一半的原因不在房间，而在过滤器阻力和送风机频率：
高效阻力爬过 85% 以后，风量不足，远端房间会先掉压差。
所以这里把 AHU 参数、三级滤器阻力、风路和今日能耗放在同一屏，
值班工程师看完就知道是该换滤器，还是该提频率。

=== 局部几何 ===
  AHU 主卡  x  12, y 0, 640x444
  风路卡    x 664, y 0, 348x232
  能耗卡    x 664, y 240, 348x204
]]

local T = require "theme"
local fx = require "fx"
local kit = require "kit"
local data = require "room_data"

local M = {}

local c, f = T.c, T.f
local P = fx.pool()

local o = {
    now = 0,
    tAhu = 0, tE = 0, tText = 0,
}
M.o = o

local fmt, floor = string.format, math.floor
local function f1(v) return fmt("%.1f", v) end

local function new_shape(parent, w, h)
    return airui.shape({ parent = parent, x = 0, y = 0, w = w, h = h })
end

local AHU = { x = 12,  y = 0,   w = 640, h = 444 }
local PTH = { x = 664, y = 0,   w = 348, h = 232 }
local ENG = { x = 664, y = 240, w = 348, h = 204 }

M.title, M.en = "送风", "AIR HANDLING"
M.hint = "高效阻力 > 85% 建议更换 · 频率跟随运行模式"

-- 三级滤器
local FILT = {
    { name = "初效", lim = 0.70 },
    { name = "中效", lim = 0.80 },
    { name = "高效", lim = 0.85 },
}

-- ==================== AHU 主卡 ====================
local MAIN = {
    { key = "freq",    label = "送风机频率", unit = "Hz", max = 50 },
    { key = "sup_t",   label = "送风温度",   unit = "C",  max = 30 },
    { key = "ret_pct", label = "回风比例",   unit = "%",  max = 100 },
}

local function build_ahu(root)
    local card = kit.card(root, AHU, c.cyan)
    kit.head(card, "空调机组 AHU-01", AHU.w)
    o.runTag = kit.tag(card, AHU.w - 100, 10, 80, "RUN", c.mint, 12)

    o.main = {}
    for i = 1, 3 do
        local x = 16 + (i - 1) * 200
        kit.text(card, x, 44, 180, 16, 11, c.dim2, airui.TEXT_ALIGN_LEFT, MAIN[i].label)
        local E = {}
        E.val = kit.text(card, x, 62, 140, 46, 32, c.ice, airui.TEXT_ALIGN_LEFT, "0")
        E.unit = kit.text(card, x, 108, 60, 16, 12, c.dim2, airui.TEXT_ALIGN_LEFT, MAIN[i].unit)
        E.bar = new_shape(card, AHU.w, AHU.h)
        o.main[i] = E
    end

    -- 第二行：风量 / 功率 / 新风比
    o.sub = {}
    local subs = { { "送风量", "m3/h" }, { "风机功率", "kW" }, { "新风比", "%" } }
    for i = 1, 3 do
        local x = 16 + (i - 1) * 200
        kit.text(card, x, 148, 160, 14, 10, c.dim2, airui.TEXT_ALIGN_LEFT, subs[i][1])
        o.sub[i] = kit.text(card, x, 164, 150, 26, 20, c.dim, airui.TEXT_ALIGN_LEFT, "0")
    end

    airui.container({
        parent = card, x = 16, y = 208, w = AHU.w - 32, h = 1,
        color = c.line, color_opacity = 160, border_width = 0,
    })

    kit.text(card, 16, 220, 300, 18, 11, c.dim2, airui.TEXT_ALIGN_LEFT, "三级过滤阻力")

    o.filt = {}
    for i = 1, 3 do
        local y = 244 + (i - 1) * 54
        local E = {}
        E.name = kit.text(card, 16, y + 2, 60, 20, 13, c.dim, airui.TEXT_ALIGN_LEFT, FILT[i].name)
        E.pct = kit.text(card, 500, y + 2, 48, 20, 13, c.txt, airui.TEXT_ALIGN_RIGHT, "0%")
        E.st = kit.text(card, 556, y + 3, 68, 18, 11, c.dim2, airui.TEXT_ALIGN_RIGHT, "")
        o.filt[i] = E
    end
    o.filtShape = new_shape(card, AHU.w, AHU.h)

    o.advice = kit.text(card, 16, 410, AHU.w - 32, 20, 11, c.dim, airui.TEXT_ALIGN_LEFT, "")
end

local function draw_ahu()
    local a = data.ahu
    local vals = { a.freq, a.sup_t, a.ret_pct }

    for i = 1, 3 do
        local E = o.main[i]
        kit.put(E.val, f1(vals[i]), o, "av" .. i)
        P:reset()
        kit.meter(P, 16 + (i - 1) * 200, 132, 176, 6, fx.clamp(vals[i] / MAIN[i].max, 0, 1), c.ice)
        E.bar:set_items(P:finish())
    end

    -- 风机功率按 f^3 估，滤器阻力上涨时实际功率会更高，这里只做趋势参考
    local kw = 4 + (a.freq / 50) ^ 3 * 46
    kit.put(o.sub[1], fmt("%.0f", a.flow), o, "sv1")
    kit.put(o.sub[2], f1(kw), o, "sv2")
    kit.put(o.sub[3], fmt("%d", floor(100 - a.ret_pct + 0.5)), o, "sv3")

    P:reset()
    for i = 1, 3 do
        local fr = a.filt[i]
        local y = 244 + (i - 1) * 54
        local col = fr >= FILT[i].lim and c.alarm or (fr >= FILT[i].lim - 0.12 and c.amber or c.mint)
        kit.meter(P, 16, y + 26, 470, 10, fr, col)
        -- 限值刻度：一根竖线，越过它就该换
        P:line(16 + 470 * FILT[i].lim, y + 23, 16 + 470 * FILT[i].lim, y + 39, c.alarm, 1, 150)
    end
    o.filtShape:set_items(P:finish())

    for i = 1, 3 do
        local fr = data.ahu.filt[i]
        local E = o.filt[i]
        local col = fr >= FILT[i].lim and c.alarm or (fr >= FILT[i].lim - 0.12 and c.amber or c.mint)
        kit.put(E.pct, fmt("%d%%", floor(fr * 100 + 0.5)), o, "fp" .. i)
        kit.tint(E.pct, col, o, "fpc" .. i)
        local st = fr >= FILT[i].lim and "超限" or (fr >= FILT[i].lim - 0.12 and "偏高" or "正常")
        kit.put(E.st, st, o, "fs" .. i)
        kit.tint(E.st, col, o, "fsc" .. i)
    end

    local hi = data.ahu.filt[3]
    local adv
    if hi >= FILT[3].lim then
        adv = "高效过滤器阻力超限，建议 24 小时内更换，并先复核各房间压差"
    elseif hi >= FILT[3].lim - 0.12 then
        adv = "高效过滤器阻力偏高，已接近更换点，请提前备件"
    else
        adv = fmt("三级滤器阻力正常，高效余量 %d%%", floor((1 - hi) * 100 + 0.5))
    end
    kit.put(o.advice, adv, o, "adv")
    kit.tint(o.advice, hi >= FILT[3].lim and c.alarm or (hi >= FILT[3].lim - 0.12 and c.amber or c.dim), o, "advc")

    kit.put(o.runTag, data.state.over > 0 and "ALARM" or "RUN", o, "rt")
    kit.tint(o.runTag, data.state.over > 0 and c.alarm or c.mint, o, "rtc")
end

-- ==================== 风路 ====================
local BOX = 52
local BGAP = 14
local BX0 = 12
local BY = 86
local BH = 44

local function box_x(i)
    return BX0 + (i - 1) * (BOX + BGAP)
end

local function build_path(root)
    local card = kit.card(root, PTH, c.ice)
    kit.head(card, "送风路径", PTH.w)
    o.pathShape = new_shape(card, PTH.w, PTH.h)

    local names = { "回风", "初效", "中效", "高效", "送风" }
    for i = 1, 5 do
        kit.text(card, box_x(i), BY + 12, BOX, 20, 11, c.dim, airui.TEXT_ALIGN_CENTER, names[i])
    end
    -- 滤器下方的阻力读数，和上面的大条呼应，但这里是"站在机房里看"的顺序
    o.pathPct = {}
    for i = 2, 4 do
        o.pathPct[i] = kit.text(card, box_x(i) - 6, BY + BH + 8, BOX + 12, 16, 10,
                                c.dim2, airui.TEXT_ALIGN_CENTER, "")
    end
    kit.text(card, 12, 60, 160, 16, 10, c.dim2, airui.TEXT_ALIGN_LEFT, "新风 22%  ·  回风 78%")
    kit.text(card, 12, 188, 320, 18, 10, c.dim2, airui.TEXT_ALIGN_LEFT,
             "回风经三级过滤后送风，压差靠送风量维持")
end

local function draw_path()
    local a = data.ahu
    P:reset()

    for i = 1, 5 do
        local x = box_x(i)
        local col = c.ice
        if i >= 2 and i <= 4 then
            local fr = a.filt[i - 1]
            col = fr >= FILT[i - 1].lim and c.alarm
                  or (fr >= FILT[i - 1].lim - 0.12 and c.amber or c.mint)
        end
        P:box(x, BY, BOX, BH, col, i >= 2 and i <= 4 and 26 or 14, 5)
        P:frame(x, BY, BOX, BH, col, 1, 150, 5)

        -- 框与框之间的 ">"：fx.tri 只会画上下箭头，横向流向就两条斜线
        if i < 5 then
            local ax = x + BOX + 4
            local ay = BY + BH / 2
            P:line(ax, ay - 4, ax + 5, ay, c.ice, 1, 160)
            P:line(ax + 5, ay, ax, ay + 4, c.ice, 1, 160)
        end
    end

    o.pathShape:set_items(P:finish())

    for i = 2, 4 do
        kit.put(o.pathPct[i], fmt("%d%%", floor(a.filt[i - 1] * 100 + 0.5)), o, "pp" .. i)
    end
end

-- ==================== 能耗 ====================
local function efrac(i)
    -- 确定性曲线：白班高、夜班低，两个谐波叠出"看得见的起伏"，不引入随机数
    local v = 0.52 + 0.30 * math.sin(i * 0.52 + 0.7) + 0.14 * math.sin(i * 1.83)
    return fx.clamp(v, 0.08, 1)
end

local function build_energy(root)
    local card = kit.card(root, ENG, c.amber)
    kit.head(card, "今日能耗", ENG.w)
    kit.tag(card, ENG.w - 96, 10, 76, "kWh", c.dim2, 11)

    o.engVal = kit.text(card, 12, 34, 200, 40, 30, c.txt, airui.TEXT_ALIGN_LEFT, "0")
    o.engShape = new_shape(card, ENG.w, ENG.h)
    o.engNote = kit.text(card, 12, 172, ENG.w - 24, 18, 11, c.dim2, airui.TEXT_ALIGN_LEFT, "")
end

local function draw_energy()
    local e = data.state.energy
    kit.put(o.engVal, f1(e), o, "ev")

    local peak, sum = 0, 0
    P:reset()
    P:line(12, 160, ENG.w - 12, 160, c.line, 1, 120)
    for i = 1, 24 do
        local fr = efrac(i)
        if fr > peak then peak = fr end
        sum = sum + fr
        local x = 14 + (i - 1) * 13.2
        local h = 62 * fr
        local col = (i >= 19) and c.amber or c.ice
        P:box(x, 158 - h, 8, h, col, (i >= 19) and 180 or 80, 1)
    end
    o.engShape:set_items(P:finish())

    -- 柱子表达的是"负荷比例"，不是绝对 kWh：绝对值只在上面那个大数里给，
    -- 免得两个数一个是估算一个是累计，看着互相矛盾
    kit.put(o.engNote, fmt("负荷曲线（近 24 小时）    峰值 %d%%    均值 %d%%",
                           floor(peak * 100 + 0.5), floor(sum / 24 * 100 + 0.5)), o, "en")
end

-- ==================== 生命周期 ====================
function M.build(root)
    build_ahu(root)
    build_path(root)
    build_energy(root)
    M.enter()
end

function M.enter()
    draw_ahu()
    draw_path()
    draw_energy()
end

function M.update(dt, idle, now)
    o.now = now
    local ms = dt * 1000
    o.tAhu = o.tAhu + ms
    o.tE = o.tE + ms
    o.tText = o.tText + ms

    if o.tAhu >= 400 then o.tAhu = 0; draw_ahu() end
    if o.tE >= 1000 then o.tE = 0; draw_energy() end
    if o.tText >= 500 then o.tText = 0; draw_path() end
end

function M.on_touch(x, y)
    return false
end

return M

