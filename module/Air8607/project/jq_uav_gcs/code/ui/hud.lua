--[[
@module  hud
@summary UAV GCS - 人工地平仪（姿态球 / 罗盘环 / 速度高度刻度带）
@version 1.0
@date    2026.11.02

=== 姿态球是怎么"填"出来的 ===
shape 没有多边形填充，所以天地球用**逐行扫描填充**：
把球按 4px 一条横带切开（半径 86 → 43 行），每行算三个数：
  1、弦宽      w = sqrt(r² - dy²)
  2、天/地分界 x = (p - dy·ny) / nx   （p 是地平线到球心的距离，nx/ny 是地平面法向）
  3、两段色带  [左边界, 分界] 画一边，[分界, 右边界] 画另一边
一行两个 rect，43 行 = 86 个图元。比"画几千个点"省两个数量级，
而且横滚任意角度都连续 —— 这正是地平仪最需要的东西。

=== 为什么刻度带不滚动 ===
label 不能设坐标，滚动刻度带的数字就只能是"画上去的线"，读不出来。
所以左右两条带改成**固定刻度 + 移动指针 + 中央数值框**：
数字一次摆好，指针每帧算位置，中央框只改文本。既准又省。

=== 角度约定 ===
屏幕角度：0 度指向右，顺时针增大（和 LVGL 的 arc 图元一致）。
航向 0 = 北 = 正上方，所以 屏幕角 = 航向 - 90。
横扫角度顺时针为正，地平线右端向下沉 —— 与真地平仪一致。
]]
local fx = require "fx"
local T = require "theme"
local parts = require "parts"

local C = T.c
local M = {}

local G = nil      -- 构建时确定的几何（theme.att）
local sP = nil     -- 静态层图元池
local P = nil      -- 动态层图元池
local node = {}    -- 需要更新的 label

local SPD_MAX = 20    -- 速度带 0..20 m/s
local ALT_MAX = 60    -- 高度带 0..60 m
local PX_PER_DEG = 1.7

-- ==================== 刻度带（静态） ====================
--[[固定刻度带：轨道 + 大小刻度 + 数字（数字只在避开了中央数值框的位置才摆）
@return table 需要摆数字的 {v=, y=} 列表
]]
local function build_tape(P0, geo, vmax, tick_n, label_step)
    local x, y, w, h = geo.x, geo.y, geo.w, geo.h
    local cyv = y + h / 2
    local marks = {}

    P0:line(x + w - 3, y, x + w - 3, y + h, C.line2, 1, 200, false)
    P0:line(x + w - 3, y, x + w - 9, y, C.line2, 1, 200, false)
    P0:line(x + w - 3, y + h, x + w - 9, y + h, C.line2, 1, 200, false)

    for i = 0, tick_n do
        local v = vmax * i / tick_n
        local ty = cyv + h / 2 - (v / vmax) * h
        local iv = math.floor(v + 0.5)
        local big = (math.abs(v - iv) < 0.01) and (iv % label_step == 0)
        if big then
            P0:line(x + w - 15, ty, x + w - 3, ty, C.dim, 2, 220, false)
            -- 中央数值框会盖住这一段，落进去的数字直接不摆
            if math.abs(ty - cyv) > 18 then
                marks[#marks + 1] = { v = iv, y = ty }
            end
        else
            P0:line(x + w - 8, ty, x + w - 3, ty, C.dim2, 1, 170, false)
        end
    end

    -- 中央数值框底：一块不透明矩形，把指针下面的刻度压掉
    P0:box(x + 1, cyv - 15, w - 4, 30, 0x060B14, 245, 6)
    P0:frame(x + 1, cyv - 15, w - 4, 30, C.cyan, 1, 120, 6)

    return marks
end

function M.build(parent, geo)
    G = geo
    local b = geo.panel
    sP = fx.pool()
    P = fx.pool()
    sP:reset()

    -- 面板底
    parts.panel_bg(sP, b.w, b.h, C.cyan)

    local cx, cy, r, ring = geo.ball.cx, geo.ball.cy, geo.ball.r, geo.ball.ring

    -- 罗盘环：两圈细环 + 24 根刻度（每 15 度）
    sP:ring(cx, cy, ring, C.line2, 1, 220)
    sP:ring(cx, cy, ring - 5, C.line, 1, 140)
    for i = 0, 23 do
        local a = math.rad(i * 15 - 90)
        local major = (i % 6 == 0)
        local r0 = ring - (major and 11 or 7)
        local r1 = ring - 1
        sP:line(cx + math.cos(a) * r0, cy + math.sin(a) * r0,
            cx + math.cos(a) * r1, cy + math.sin(a) * r1,
            major and C.dim or C.dim2, major and 2 or 1, major and 230 or 160, false)
    end

    -- 球的外框与内框
    sP:ring(cx, cy, r + 3, C.line2, 2, 235)
    sP:ring(cx, cy, r, C.line, 1, 170)

    -- 左右刻度带
    local marks_l = build_tape(sP, geo.tape_l, SPD_MAX, 20, 5)
    local marks_r = build_tape(sP, geo.tape_r, ALT_MAX, 12, 20)

    -- 顶部航向标题底
    sP:box(cx - 58, 5, 116, 22, C.panel2, 230, 4)
    sP:line(cx - 40, 26, cx + 40, 26, C.cyan, 1, 140, true)

    sP:finish()

    -- 静态 shape 先建、动态后建，保证动态层压在静态层之上
    local bg = airui.shape({ parent = parent, x = b.x, y = b.y, w = b.w, h = b.h, items = {} })
    bg:set_items(sP.items)
    local dyn = airui.shape({ parent = parent, x = b.x, y = b.y, w = b.w, h = b.h, items = {} })
    M.shape = dyn

    -- ---------- 文字 ----------
    node.hdg = parts.lbl(parent, b.x + cx - 58, b.y + 6, 116, 20, "HDG 000",
        T.f.sub, C.cyan, airui.TEXT_ALIGN_CENTER)

    node.spd = parts.lbl(parent, b.x + geo.tape_l.x, b.y + geo.tape_l.y + 96 - 14,
        geo.tape_l.w - 6, 26, "0.0", T.f.num, C.txt, airui.TEXT_ALIGN_CENTER)
    node.spdu = parts.lbl(parent, b.x + geo.tape_l.x, b.y + geo.tape_l.y + 96 + 15,
        geo.tape_l.w - 6, 16, "m/s", T.f.mini, C.dim2, airui.TEXT_ALIGN_CENTER)

    node.alt = parts.lbl(parent, b.x + geo.tape_r.x, b.y + geo.tape_r.y + 96 - 14,
        geo.tape_r.w - 6, 26, "0.0", T.f.num, C.txt, airui.TEXT_ALIGN_CENTER)
    node.altu = parts.lbl(parent, b.x + geo.tape_r.x, b.y + geo.tape_r.y + 96 + 15,
        geo.tape_r.w - 6, 16, "m", T.f.mini, C.dim2, airui.TEXT_ALIGN_CENTER)

    -- 刻度数字：位置固定，一次摆好
    for i = 1, #marks_l do
        local m = marks_l[i]
        parts.lbl(parent, b.x + geo.tape_l.x, b.y + geo.tape_l.y + m.y - 9,
            geo.tape_l.w - 18, 16, tostring(m.v), T.f.mini, C.dim2, airui.TEXT_ALIGN_RIGHT)
    end
    for i = 1, #marks_r do
        local m = marks_r[i]
        parts.lbl(parent, b.x + geo.tape_r.x, b.y + geo.tape_r.y + m.y - 9,
            geo.tape_r.w - 18, 16, tostring(m.v), T.f.mini, C.dim2, airui.TEXT_ALIGN_RIGHT)
    end

    -- 罗盘方位字：N 上、E 右、S 下、W 左
    local cv = { { "N", 0, -1 }, { "E", 1, 0 }, { "S", 0, 1 }, { "W", -1, 0 } }
    for i = 1, 4 do
        local it = cv[i]
        parts.lbl(parent, b.x + cx + it[2] * (ring + 3) - 12,
            b.y + cy + it[3] * (ring + 3) - 10, 24, 20, it[1],
            T.f.mini, C.dim, airui.TEXT_ALIGN_CENTER)
    end

    -- 球下方：俯仰 / 横滚读数
    node.pr = parts.lbl(parent, b.x + cx - 100, b.y + cy + r + 13, 200, 22,
        "P +0.0    R +0.0", T.f.sub, C.dim, airui.TEXT_ALIGN_CENTER)
end

-- ==================== 姿态球 ====================
local function draw_ball(P0, cx, cy, r, pitch, roll)
    local nR = math.floor(r)
    local nx = -math.sin(math.rad(roll))
    local ny = math.cos(math.rad(roll))
    local p = pitch * PX_PER_DEG

    -- 逐行扫描填充天与地
    local step = 4
    local y = -nR
    while y < nR do
        local dy = y + step / 2
        local w2 = r * r - dy * dy
        if w2 > 0 then
            local w = math.sqrt(w2)
            local ty = cy + y
            local t = fx.clamp((dy + r) / (2 * r), 0, 1)
            local sky = fx.mix(C.sky, C.sky_lo, t)
            local gnd = fx.mix(C.gnd, C.gnd_lo, t)
            local s = dy * ny

            if nx > 0.0001 or nx < -0.0001 then
                local split = (p - s) / nx
                local sx = fx.clamp(split, -w, w)
                -- nx < 0 时右边是天空、左边是地，见文件头的推导
                local left_is_ground = (nx < 0)
                local lcol = left_is_ground and gnd or sky
                local rcol = left_is_ground and sky or gnd
                if sx > -w + 0.5 then
                    P0:box(cx - w, ty, sx + w, step + 1, lcol, 255, 0)
                end
                if w - sx > 0.5 then
                    P0:box(cx + sx, ty, w - sx, step + 1, rcol, 255, 0)
                end
            else
                local col = (s > p) and gnd or sky
                P0:box(cx - w, ty, 2 * w, step + 1, col, 255, 0)
            end
        end
        y = y + step
    end

    --[[地平线要放在填充**之后**画：填充是整块色带，先画的话会被整片盖掉。
这条线是姿态球里最该看清的东西，顺序错了等于没画。]]
    local disc = r * r - p * p
    if disc > 0 then
        local t = math.sqrt(disc)
        local dx2, dy2 = ny, -nx
        P0:line(cx + nx * p + dx2 * t, cy + ny * p + dy2 * t,
            cx + nx * p - dx2 * t, cy + ny * p - dy2 * t, 0xE8F4FF, 2, 235, true)
    end

    -- 俯仰梯：每 10 度一道，随横滚一起转，长度按离球心的距离收窄
    local dx, dy = ny, -nx
    for pv = -40, 40, 10 do
        if pv ~= 0 then
            local off = p - pv * PX_PER_DEG
            local half = math.sqrt(math.max(0, r * r - off * off))
            if half > 6 then
                local hw = math.min(half * 0.62, r * 0.52)
                local ox, oy = cx + nx * off, cy + ny * off
                local opa = math.floor(150 - math.abs(pv) * 1.6)
                P0:line(ox + dx * hw, oy + dy * hw, ox - dx * hw, oy - dy * hw,
                    0xE8F4FF, 1, opa, false)
                -- 两端各补一小段短划，读起来像真 HUD 的梯子
                local ex, ey = ox + dx * hw, oy + dy * hw
                P0:line(ex, ey, ex + nx * 6, ey + ny * 6, 0xE8F4FF, 1, opa, false)
            end
        end
    end

    -- 固定机头符号
    P0:line(cx - 34, cy, cx - 12, cy, 0xFFFFFF, 3, 235, true)
    P0:line(cx + 12, cy, cx + 34, cy, 0xFFFFFF, 3, 235, true)
    P0:line(cx - 12, cy, cx, cy + 8, 0xFFFFFF, 2, 225, false)
    P0:line(cx + 12, cy, cx, cy + 8, 0xFFFFFF, 2, 225, false)
    P0:dot(cx, cy, 2, 0xFFFFFF, 235)

    -- 横滚刻度：球顶一排小刻度 + 一个随 roll 走的三角
    for a = -30, 30, 10 do
        local ang = math.rad(a - 90)
        local c1 = math.cos(ang)
        local s1 = math.sin(ang)
        P0:line(cx + c1 * (r + 2), cy + s1 * (r + 2),
            cx + c1 * (r - 6), cy + s1 * (r - 6),
            (a == 0) and C.txt or C.dim2, (a == 0) and 2 or 1, 190, false)
    end
    local ra = math.rad(roll - 90)
    local mx = cx + math.cos(ra) * (r - 5)
    local my = cy + math.sin(ra) * (r - 5)
    P0:line(mx, my, mx + math.cos(ra + 2.7) * 9, my + math.sin(ra + 2.7) * 9, C.amber, 2, 235, true)
    P0:line(mx, my, mx + math.cos(ra - 2.7) * 9, my + math.sin(ra - 2.7) * 9, C.amber, 2, 235, true)
end

-- ==================== 刻度带指针 ====================
local function draw_marker(P0, geo, vmax, value, color)
    local x, y, w, h = geo.x, geo.y, geo.w, geo.h
    local cyv = y + h / 2
    local t = fx.clamp(value / vmax, 0, 1)
    local my = cyv + h / 2 - t * h
    P0:box(x + w - 19, my - 4, 17, 8, color, 235, 2)
    P0:dot(x + w - 19, my, 6, color, 60)
end

-- ==================== 每帧 ====================
function M.draw(s, t)
    if not G then return end
    P:reset()
    local cx, cy, r, ring = G.ball.cx, G.ball.cy, G.ball.r, G.ball.ring

    draw_ball(P, cx, cy, r, s.pitch, s.roll)

    -- 罗盘：从正北扫到当前航向的弧 + 指针
    local ha = math.rad(s.yaw - 90)
    if s.yaw > 0.5 then
        P:arc(cx, cy, ring - 2, -90, s.yaw - 90, C.cyan, 2, 150, false)
    end
    local hx = cx + math.cos(ha) * (ring - 2)
    local hy = cy + math.sin(ha) * (ring - 2)
    P:line(cx + math.cos(ha) * (ring - 13), cy + math.sin(ha) * (ring - 13),
        hx, hy, C.cyan, 2, 250, true)
    P:dot(hx, hy, 4, C.cyan, 245)
    P:dot(cx - math.cos(ha) * (ring - 7), cy - math.sin(ha) * (ring - 7), 2, C.dim2, 190)

    -- 速度 / 高度指针
    draw_marker(P, G.tape_l, SPD_MAX, s.gs, C.cyan)
    draw_marker(P, G.tape_r, ALT_MAX, s.alt, C.green)

    -- 垂直速度：高度带内侧一根双向短条
    local vs = fx.clamp(s.vspd / 3, -1, 1)
    local bx = G.tape_r.x - 9
    P:line(bx, cy, bx, cy - vs * 44, (s.vspd >= 0) and C.green or C.amber, 3, 215, true)

    P:finish()
    M.shape:set_items(P.items)

    parts.text(node.hdg, string.format("HDG %03d", math.floor(s.yaw + 0.5) % 360))
    parts.text(node.spd, string.format("%.1f", s.gs))
    parts.text(node.alt, string.format("%.1f", s.alt))
    parts.text(node.pr, string.format("P %+.1f    R %+.1f", s.pitch, s.roll))
end

return M
