--[[
@module  cat
@summary 汤姆猫 - 猫本体（几何 / 静态绘制 / 动态绘制 / 命中测试）
@version 1.0
@date    2026.10.25
@author  蒋骞

=== 为什么几何放在这里 ===
绘制和命中测试必须用同一套数字，否则"看着在头上，点下去却算肚子"。
所以所有坐标只在 G 表里写一次：draw_static / draw_dynamic / hit 都读同一张表。

=== 分层 ===
静态层（build 时画一次，之后不动）：
  背景光晕 / 地板 / 落影 / 耳朵 / 身体 / 肚皮 / 后脚 / 头 / 额头条纹 /
  口鼻 / 眼睛白与瞳色 / 鼻头 / 胡须
动态层（每帧重算）：
  尾巴摆动 / 瞳孔偏移 / 眼睑（眨眼与眯眼）/ 嘴巴（闭 / 张）/ 两只前爪 /
  触摸粒子 / 触摸涟漪

前爪是这个 UI 的主角：点击猫身任意位置，两只前爪会扑到点击点两侧把那里
"捂住"，停一下再弹回身侧。爪子画在动态层最上面，所以永远压在猫身上。
]]
local T = require "theme"
local C = T.c

local M = {}

-- ==================== 几何（屏幕绝对坐标） ====================
local G = {
    body   = { x = 660, y = 432, rx = 172, ry = 150 },
    belly  = { x = 660, y = 466, rx = 110, ry = 112 },
    head   = { x = 660, y = 202, rx = 152, ry = 142 },
    muzzle = { x = 660, y = 276, rx = 92, ry = 56 },
    eye_l  = { x = 613, y = 196, rx = 42, ry = 46 },
    eye_r  = { x = 707, y = 196, rx = 42, ry = 46 },
    foot_l = { x = 586, y = 548, rx = 70, ry = 36 },
    foot_r = { x = 734, y = 548, rx = 70, ry = 36 },

    -- 耳朵：三角（左上、右上）
    ear_l  = { 546, 158, 588, 44, 678, 104 },
    ear_r  = { 774, 158, 732, 44, 642, 104 },
    -- 鼻头三角
    nose   = { 646, 246, 674, 246, 660, 266 },
    -- 尾巴：三次贝塞尔 P0..P3（P3 是尾巴尖，动态层按相位让它摆）
    tail   = { 818, 508, 900, 512, 968, 404, 916, 316 },
}
M.G = G

-- 前爪静止位（垂在肚皮两侧）
M.rest_l = { x = 548, y = 470 }
M.rest_r = { x = 772, y = 470 }
M.paw_rx, M.paw_ry = 46, 40

-- ==================== 命中区域 ====================
-- say    ：点到这里念的中文台词（同时显示在气泡里），UTF-8 汉字请控制在 6 字内
-- lid    ：被摸到时的眯眼程度（0 睁眼 .. 1 闭眼）
-- spread ：两只前爪相对点击点左右分开的距离（太窄会把自己的嘴挡住）
-- dy     ：前爪中心相对点击点的上下偏移
local REGIONS = {
    head  = { say = "谢谢主人",   color = C.accent,    lid = 0.15, spread = 64, dy = 22 },
    ear   = { say = "耳朵好痒",   color = C.ear_in,    lid = 0.35, spread = 84, dy = 34 },
    eye   = { say = "别戳眼睛",   color = C.iris,      lid = 0.60, spread = 92, dy = 30 },
    face  = { say = "主人你好",   color = C.tongue,    lid = 0.55, spread = 92, dy = 34 },
    belly = { say = "肚子好舒服", color = C.accent2,   lid = 0.75, spread = 78, dy = -4 },
    paw   = { say = "手也摸摸",   color = C.accent2,   lid = 0.20, spread = 66, dy = 0 },
    foot  = { say = "脚脚怕痒",   color = C.accent,    lid = 0.25, spread = 80, dy = -16 },
    tail  = { say = "别拽尾巴",   color = C.nose,      lid = 0.05, spread = 86, dy = 10 },
    body  = { say = "再摸一下",   color = C.fur_light, lid = 0.15, spread = 80, dy = 6 },
}
M.REGIONS = REGIONS

--[[点是否落在椭圆内]]
local function in_ellipse(x, y, e, pad)
    pad = pad or 0
    local dx = (x - e.x) / (e.rx + pad)
    local dy = (y - e.y) / (e.ry + pad)
    return dx * dx + dy * dy <= 1
end

--[[三角面命中：用叉积判同侧]]
local function in_tri(x, y, t)
    local x1, y1, x2, y2, x3, y3 = t[1], t[2], t[3], t[4], t[5], t[6]
    local d1 = (x - x2) * (y1 - y2) - (x1 - x2) * (y - y2)
    local d2 = (x - x3) * (y2 - y3) - (x2 - x3) * (y - y3)
    local d3 = (x - x1) * (y3 - y1) - (x3 - x1) * (y - y1)
    local has_neg = (d1 < 0) or (d2 < 0) or (d3 < 0)
    local has_pos = (d1 > 0) or (d2 > 0) or (d3 > 0)
    return not (has_neg and has_pos)
end

--[[命中测试：返回区域 id（REGIONS 的键），点空了返回 nil
判定顺序 = 视觉层级顺序，前面的区域优先级更高：
  前爪 → 眼睛 → 口鼻 → 耳朵 → 头 → 后脚 → 肚皮 → 尾巴 → 身体
前爪排第一：它画在最上层，爪子捂住脸的时候再点一次，应该算"摸爪子"。
@param number x 屏幕坐标
@param number y 屏幕坐标
@param table paw_l 左爪中心（当前姿态，可为 nil）
@param table paw_r 右爪中心
@param number tail_x 尾巴尖 X（当前姿态）
@param number tail_y 尾巴尖 Y
]]
function M.hit(x, y, paw_l, paw_r, tail_x, tail_y)
    if type(x) ~= "number" or type(y) ~= "number" then return nil end
    if x ~= x or y ~= y then return nil end          -- NaN 保护
    if x < 0 or y < 0 or x >= T.screen.w or y >= T.screen.h then return nil end

    -- 前爪只有中心点，半径用固定的爪掌尺寸（略放大一点，手指按不准也能命中）
    if paw_l then
        local dx = (x - paw_l.x) / (M.paw_rx + 8)
        local dy = (y - paw_l.y) / (M.paw_ry + 8)
        if dx * dx + dy * dy <= 1 then return "paw" end
    end
    if paw_r then
        local dx = (x - paw_r.x) / (M.paw_rx + 8)
        local dy = (y - paw_r.y) / (M.paw_ry + 8)
        if dx * dx + dy * dy <= 1 then return "paw" end
    end

    if in_ellipse(x, y, G.eye_l, 4) or in_ellipse(x, y, G.eye_r, 4) then return "eye" end
    if in_ellipse(x, y, G.muzzle, 2) then return "face" end
    if in_tri(x, y, G.ear_l) or in_tri(x, y, G.ear_r) then return "ear" end
    if in_ellipse(x, y, G.head, 0) then return "head" end

    -- 后脚画在肚皮之上，而且肚皮的下缘本来就压着脚背，所以先判脚
    if in_ellipse(x, y, G.foot_l, 0) or in_ellipse(x, y, G.foot_r, 0) then return "foot" end
    if in_ellipse(x, y, G.belly, 0) then return "belly" end

    if tail_x and tail_y then
        local dx, dy = x - tail_x, y - tail_y
        if dx * dx + dy * dy <= 62 * 62 then return "tail" end
    end

    if in_ellipse(x, y, G.body, 0) then return "body" end
    return nil
end

-- ==================== 静态层 ====================
local function ell(P, e, color, opa)
    P:ellipse_fill(e.x, e.y, e.rx, e.ry, color, opa or 255)
end

local function ello(P, e, color, w, opa)
    P:ellipse(e.x, e.y, e.rx, e.ry, color, w, opa or 255)
end

-- 三角以质心为心缩放，用来画耳内那层粉色
local function shrink_tri(t, k)
    local cx = (t[1] + t[3] + t[5]) / 3
    local cy = (t[2] + t[4] + t[6]) / 3
    local o = {}
    for i = 1, 6, 2 do
        o[i] = cx + (t[i] - cx) * k
        o[i + 1] = cy + (t[i + 1] - cy) * k
    end
    return o
end

--[[画一次就够的部分（背景 + 猫的静止部件）
@param table P 图元池（原点 0,0）
]]
function M.draw_static(P)
    -- ---------- 背景 ----------
    P:ellipse_fill(700, 330, 336, 300, C.bg_halo)
    P:box(0, 512, 1024, 96, C.floor, 255, 0)
    P:line(0, 512, 1024, 512, 0xE2C49C, 2, 255)
    -- 墙面装饰点
    for _, d in ipairs({ { 934, 128, 24 }, { 878, 68, 12 }, { 1000, 238, 9 },
                         { 424, 116, 11 }, { 470, 566, 8 }, { 986, 470, 14 } }) do
        P:dot(d[1], d[2], d[3], C.wall_dot, 200)
    end
    -- 落地影
    P:ellipse_fill(660, 566, 214, 28, C.shadow, 64)

    -- ---------- 耳朵（先画，头会盖住根部） ----------
    for _, t in ipairs({ G.ear_l, G.ear_r }) do
        P:poly_fill(t, C.fur, 255)
        P:poly_line(t, C.outline, 3, 255, true)
        P:poly_fill(shrink_tri(t, 0.52), C.ear_in, 255)
    end

    -- ---------- 身体 ----------
    ell(P, G.body, C.fur)
    ello(P, G.body, C.outline, 3)
    ell(P, G.belly, C.belly)
    ello(P, G.belly, 0xE3E9F1, 2, 255)

    -- 身体两侧的虎斑：贴着轮廓、够长、有点弧度才像毛，短直笔画像划痕
    for _, s in ipairs({ { 498, 384, 546, 414 }, { 494, 436, 542, 464 } }) do
        P:line(s[1], s[2], s[3], s[4], C.fur_dark, 11, 120, true)
        P:line(1320 - s[1], s[2], 1320 - s[3], s[4], C.fur_dark, 11, 120, true)
    end

    -- ---------- 后脚 ----------
    for _, f in ipairs({ G.foot_l, G.foot_r }) do
        ell(P, f, C.fur)
        ello(P, f, C.outline, 3)
        P:ellipse_fill(f.x - 26, f.y - 4, 13, 10, C.pad)
        P:ellipse_fill(f.x, f.y - 9, 13, 10, C.pad)
        P:ellipse_fill(f.x + 26, f.y - 4, 13, 10, C.pad)
        P:ellipse_fill(f.x, f.y + 13, 22, 11, C.pad)
    end

    -- ---------- 头 ----------
    ell(P, G.head, C.fur)
    ello(P, G.head, C.outline, 3)
    -- 额头三道条纹
    P:line(636, 94, 630, 128, C.fur_dark, 8, 170, true)
    P:line(660, 86, 660, 122, C.fur_dark, 8, 170, true)
    P:line(684, 94, 690, 128, C.fur_dark, 8, 170, true)

    -- ---------- 口鼻 ----------
    ell(P, G.muzzle, C.muzzle)
    ello(P, G.muzzle, 0xE4E8EF, 2)
    -- 胡须
    for _, s in ipairs({ { 1, -1 }, { 1, 0 }, { 1, 1 } }) do
        local bx = 578
        local by = 288 + s[2] * 12
        P:line(bx, by, bx - 78, by - 14 + s[2] * 10, C.white, 2, 190)
        P:line(1320 - bx, by, 1320 - bx + 78, by - 14 + s[2] * 10, C.white, 2, 190)
    end

    -- ---------- 眼睛（白 + 瞳色，瞳孔在动态层） ----------
    for _, e in ipairs({ G.eye_l, G.eye_r }) do
        ell(P, e, C.white)
        ello(P, e, C.outline, 3)
        P:dot(e.x + (e.x < 660 and 3 or -3), e.y + 2, 21, C.iris)
        P:dot(e.x + (e.x < 660 and -8 or 8), e.y - 12, 7, C.white, 230)
    end

    -- ---------- 鼻头 ----------
    P:poly_fill(G.nose, C.nose, 255)
    P:poly_line(G.nose, C.outline, 2, 255, true)
end

-- ==================== 动态层 ====================

-- 尾巴中轴 11 个点：模块级复用，别每帧新建 11 张小表（GC 顿卡的常见来源）
local TAIL = {}
for i = 1, 11 do TAIL[i] = { 0, 0 } end

--[[尾巴中轴采样：三次贝塞尔 + 相位摆动（结果写进 TAIL，返回同一个表）
@return table 11 个点 {x, y}
]]
local function tail_path(ph)
    local sway = math.sin(ph) * 26
    local x0, y0 = G.tail[1], G.tail[2]
    local x1, y1 = G.tail[3], G.tail[4]
    local x2, y2 = G.tail[5], G.tail[6] + sway * 0.4
    local x3, y3 = G.tail[7] + sway, G.tail[8] + sway * 0.7
    local pts = TAIL
    for i = 0, 10 do
        local t = i / 10
        local u = 1 - t
        local a = u * u * u
        local b = 3 * u * u * t
        local d = 3 * u * t * t
        local e = t * t * t
        local p = pts[i + 1]
        p[1] = a * x0 + b * x1 + d * x2 + e * x3
        p[2] = a * y0 + b * y1 + d * y2 + e * y3
    end
    return pts
end

--[[尾巴尖坐标（命中测试用）
@return number x, number y
]]
function M.tail_tip(ph)
    local p = tail_path(ph or 0)
    return p[11][1], p[11][2]
end

--[[画一只前爪：爪掌 + 三颗脚趾 + 掌心肉垫]]
local function draw_paw(P, p)
    P:ellipse_fill(p.x, p.y, M.paw_rx, M.paw_ry, C.fur_light)
    P:ellipse(p.x, p.y, M.paw_rx, M.paw_ry, C.outline, 3)
    P:ellipse_fill(p.x - 18, p.y - 18, 12, 9, C.pad)
    P:ellipse_fill(p.x, p.y - 23, 12, 9, C.pad)
    P:ellipse_fill(p.x + 18, p.y - 18, 12, 9, C.pad)
    P:ellipse_fill(p.x, p.y + 12, 20, 13, C.pad)
end

--[[
动态层绘制
@param table P 图元池（原点 = theme.stage 的左上角）
@param table v 姿态视图：
  paw_l/paw_r {x,y}   两只前爪中心
  eye_dx/eye_dy       瞳孔偏移（像素）
  lid                 眼睑闭合 0..1
  mouth               张嘴 0..1
  tail_ph             尾巴相位（弧度）
  parts               粒子数组 {x,y,vx,vy,life,r,color}
  ripple              涟漪 {x,y,r,life,color} 或 nil
]]
function M.draw_dynamic(P, v)
    -- ---------- 尾巴 ----------
    local pts = tail_path(v.tail_ph or 0)
    for i = 1, 10 do
        local w = 30 - (i - 1) * 2                 -- 30 → 12，渐细
        local col = (i >= 8) and C.fur_dark or C.fur
        P:line(pts[i][1], pts[i][2], pts[i + 1][1], pts[i + 1][2], col, w, 255, true)
    end

    -- ---------- 瞳孔 ----------
    local dx, dy = v.eye_dx or 0, v.eye_dy or 0
    for _, e in ipairs({ G.eye_l, G.eye_r }) do
        P:ellipse_fill(e.x + dx, e.y + dy, 9, 20, C.pupil)
    end

    -- ---------- 眼睑（眨眼 / 眯眼，画在瞳孔之上） ----------
    local lid = v.lid or 0
    if lid > 0.04 then
        if lid > 1 then lid = 1 end
        for _, e in ipairs({ G.eye_l, G.eye_r }) do
            local h = e.ry * lid
            local top = e.y - e.ry
            P:ellipse_fill(e.x, top + h, e.rx + 3, h, C.fur)
            P:line(e.x - e.rx - 2, top + h * 2, e.x + e.rx + 2, top + h * 2,
                C.outline, 4, 255, true)
        end
    end

    -- ---------- 嘴巴 ----------
    local m = v.mouth or 0
    if m > 0.06 then
        P:ellipse_fill(660, 292 + 6 * m, 14 + 16 * m, 7 + 21 * m, C.mouth)
        P:ellipse_fill(660, 298 + 14 * m, 9 + 7 * m, 5 + 6 * m, C.tongue)
        P:line(646 - 16 * m, 288, 660 - 34 - 6 * m, 280, C.outline, 3, 255, true)
        P:line(674 + 16 * m, 288, 660 + 34 + 6 * m, 280, C.outline, 3, 255, true)
    else
        -- 闭嘴："w" 形
        P:line(660, 266, 660, 278, C.outline, 3, 255, true)
        P:line(660, 278, 640, 289, C.outline, 3, 255, true)
        P:line(660, 278, 680, 289, C.outline, 3, 255, true)
    end

    -- ---------- 两只前爪（永远在最上层） ----------
    if v.paw_l then draw_paw(P, v.paw_l) end
    if v.paw_r then draw_paw(P, v.paw_r) end

    -- ---------- 触摸粒子 ----------
    local parts = v.parts
    if parts then
        for i = 1, #parts do
            local p = parts[i]
            local k = p.life / p.max
            if k > 0 then
                local opa = math.floor(240 * k)
                P:dot(p.x, p.y, math.max(2, p.r * k), p.color, opa)
            end
        end
    end

    -- ---------- 触摸涟漪 ----------
    local rp = v.ripple
    if rp and rp.life > 0 then
        local k = rp.life / rp.max
        P:ring(rp.x, rp.y, rp.r, rp.color, 3, math.floor(150 * k))
    end
end

return M
