--[[
@module  page_map
@summary UAV GCS - 地图页（局部航迹 / 航点规划 / 位置读数）
@version 1.0
@date    2026.11.02

这里不是真的地图瓦片，是**局部坐标系战术图**：
起飞点为原点，正北朝上，2.2 像素 / 米，同心圆是 20/40/60/80 m 距离环，
虚线圆是 90 m 电子围栏。无人机按仿真位置实时移动，机头指向航向。

为什么不接真地图：这种 10 寸屏的地面站，飞手真正需要的是"相对起飞点在哪、
离围栏还有多远、回来的路怎么走"，而不是街道底图。纯图元画出来的战术图
刷新快、无网络依赖，也不会因为瓦片加载卡住整屏。

交互：点地图空白处添加航点（最多 8 个），点"清除航点"清空。
]]
local fx = require "fx"
local T = require "theme"
local parts = require "parts"
local sim = require "sim"

local C = T.c
local M = {}

local MV = T.map.view
local SD = T.map.side
local SCALE = T.map.scale
local TP_DOWN = T.TP_DOWN

local CX, CY = MV.w / 2, MV.h / 2

local o = { root = nil }
local P = nil
local stat_shape, dyn_shape
local wp_nodes = {}
local info = {}
local clear_btn = nil

local MAX_WP = 8
local FENCE = 90   -- 电子围栏半径（m）

-- 米 -> 地图像素（局部坐标）
local function mp(x, y)
    return CX + x * SCALE, CY - y * SCALE
end

-- ==================== 静态层 ====================
local function build_static()
    P:reset()
    -- 底
    P:box(0, 0, MV.w - 1, MV.h - 1, 0x060C16, 255, 10)

    -- 点阵底纹（每 24px）
    local gx, gy = 12, 12
    while gx < MV.w do
        gy = 12
        while gy < MV.h do
            P:dot(gx, gy, 1, 0x16253A, 200)
            gy = gy + 24
        end
        gx = gx + 24
    end

    -- 距离环
    for _, r in ipairs({ 20, 40, 60, 80 }) do
        local rr = r * SCALE
        P:ring(CX, CY, rr, C.line2, 1, 150)
        -- 环上的十字刻度
        P:line(CX - 6, CY - rr, CX + 6, CY - rr, C.line2, 1, 190, false)
        P:line(CX - 6, CY + rr, CX + 6, CY + rr, C.line2, 1, 190, false)
        P:line(CX - rr, CY - 6, CX - rr, CY + 6, C.line2, 1, 130, false)
        P:line(CX + rr, CY - 6, CX + rr, CY + 6, C.line2, 1, 130, false)
    end

    -- 电子围栏：用 24 段短弧拼虚线圆
    local fr = FENCE * SCALE
    for i = 0, 23 do
        if i % 2 == 0 then
            local a0 = i * 15
            P:arc(CX, CY, fr, a0, a0 + 8, C.amber, 2, 150, false)
        end
    end

    -- 正北 / 正东十字轴
    P:line(CX, 8, CX, MV.h - 8, C.line, 1, 90, false)
    P:line(8, CY, MV.w - 8, CY, C.line, 1, 90, false)

    -- 起飞点：小房子 + 十字
    P:line(CX - 9, CY + 4, CX, CY - 7, C.cyan, 2, 230, true)
    P:line(CX, CY - 7, CX + 9, CY + 4, C.cyan, 2, 230, true)
    P:frame(CX - 6, CY + 4, 13, 9, C.cyan, 1, 220, 1)
    P:dot(CX, CY - 1, 2, C.cyan, 240)

    -- 比例尺（左下角 20 m）
    local sx, sy = 22, MV.h - 22
    local sl = 20 * SCALE
    P:line(sx, sy, sx + sl, sy, C.dim, 2, 220, false)
    P:line(sx, sy - 5, sx, sy + 5, C.dim, 2, 220, false)
    P:line(sx + sl, sy - 5, sx + sl, sy + 5, C.dim, 2, 220, false)
    P:line(sx + sl / 2, sy - 3, sx + sl / 2, sy + 3, C.dim2, 1, 180, false)

    -- 外框
    P:frame(0, 0, MV.w - 1, MV.h - 1, C.line, 1, 255, 10)
    P:finish()
    stat_shape:set_items(P.items)
end

-- ==================== 构建 ====================
function M.build(parent)
    o.root = parent
    P = fx.pool()

    stat_shape = airui.shape({
        parent = parent, x = MV.x, y = MV.y, w = MV.w, h = MV.h, items = {},
    })
    build_static()

    dyn_shape = airui.shape({
        parent = parent, x = MV.x, y = MV.y, w = MV.w, h = MV.h, items = {},
    })

    -- 地图角标（绝对坐标 = MAP 左上角 + 局部坐标）
    parts.lbl(parent, MV.x + 16, MV.y + 12, 200, 20, "战术图 TACTICAL MAP",
        T.f.mini, C.dim, airui.TEXT_ALIGN_LEFT)
    parts.lbl(parent, MV.x + MV.w - 150, MV.y + 12, 134, 20,
        "N 朝上 / 2.2 px:m", T.f.mini, C.dim2, airui.TEXT_ALIGN_RIGHT)
    parts.lbl(parent, MV.x + 16, MV.y + MV.h - 42, 120, 18, "20 m", T.f.mini,
        C.dim, airui.TEXT_ALIGN_LEFT)
    parts.lbl(parent, MV.x + MV.w - 210, MV.y + MV.h - 42, 194, 18,
        "点击地图添加航点", T.f.mini, C.dim2, airui.TEXT_ALIGN_RIGHT)

    -- ---------- 右侧：位置 ----------
    local c1 = { x = SD.x, y = SD.y, w = SD.w, h = 168 }
    parts.card(parent, c1, "位置 POSITION", "WGS84", C.cyan)
    info.lat = M.kv(parent, c1, 16, 38, 260, "纬度 LAT")
    info.lon = M.kv(parent, c1, 16, 74, 260, "经度 LON")
    info.alt = M.kv(parent, c1, 16, 110, 130, "高度 ALT")
    info.gs = M.kv(parent, c1, 150, 110, 130, "地速 GS")

    -- ---------- 右侧：航点 ----------
    local c2 = { x = SD.x, y = SD.y + 176, w = SD.w, h = 196 }
    parts.card(parent, c2, "航点 WAYPOINTS", "0/8", C.blue)
    for i = 1, 4 do
        wp_nodes[i] = parts.lbl(parent, c2.x + 16, c2.y + 40 + (i - 1) * 30,
            c2.w - 32, 24, "WP" .. i .. "   --", T.f.body, C.dim,
            airui.TEXT_ALIGN_LEFT)
    end
    clear_btn = parts.button(parent, c2.x + c2.w - 96, c2.y + c2.h - 40,
        80, 28, "清除航点", C.red, T.f.mini)
    parts.button_paint(clear_btn, false, C.red)

    -- ---------- 右侧：统计 ----------
    local c3 = { x = SD.x, y = SD.y + 380, w = SD.w, h = 92 }
    parts.card(parent, c3, "统计 STATS", "", C.violet)
    info.track = M.kv(parent, c3, 16, 36, 84, "航迹点")
    info.far = M.kv(parent, c3, 104, 36, 96, "最远")
    info.time = M.kv(parent, c3, 196, 36, 84, "时长")
end

--[[键值对：上面是小标题，下面是大数值
@return userdata 数值 label
]]
function M.kv(parent, card, x, y, w, title)
    parts.lbl(parent, card.x + x, card.y + y, w, 16, title,
        T.f.mini, C.dim2, airui.TEXT_ALIGN_LEFT)
    return parts.lbl(parent, card.x + x, card.y + y + 16, w, 24, "--",
        T.f.body, C.txt, airui.TEXT_ALIGN_LEFT)
end

-- ==================== 动态层 ====================
local TX, TY = {}, {}

local function draw_wp(P0, s)
    for i = 1, s.wp_n do
        local w = s.wp[i]
        local x, y = mp(w.x, w.y)
        P0:ring(x, y, 9, C.blue, 2, 230)
        P0:dot(x, y, 3, C.blue, 240)
        -- 到上一个点的虚线
        local px, py
        if i == 1 then
            px, py = mp(0, 0)
        else
            px, py = mp(s.wp[i - 1].x, s.wp[i - 1].y)
        end
        P0:dash(px, py, x, y, C.blue, 1, 150, 6, 6)
    end
end

local function draw_track(P0, s)
    if s.track_n < 2 then return end
    for i = 1, s.track_n do
        local t = s.track[i]
        TX[i], TY[i] = mp(t.x, t.y)
    end
    for i = 2, s.track_n do
        local opa = math.floor(40 + 180 * (i / s.track_n))
        P0:line(TX[i - 1], TY[i - 1], TX[i], TY[i], C.green, 2, opa, false)
    end
    -- 航迹起点
    P0:dot(TX[1], TY[1], 3, C.green, 180)
end

local function draw_drone(P0, s)
    local x, y = mp(s.px, s.py)
    local rad = math.rad(s.yaw)
    local c, sn = math.cos(rad), math.sin(rad)
    -- 机头方向：航向 0 指北（屏幕 -y）
    local nx, ny = sn, -c

    -- 覆盖圈
    P0:ring(x, y, 16, C.cyan, 1, 110)
    P0:ring(x, y, 22, C.cyan, 1, 55)

    -- 四旋翼十字（随机头旋转 45 度，和 X 型机一致）
    for i = 0, 3 do
        local a = rad + math.pi / 4 + i * math.pi / 2
        local ex, ey = x + math.cos(a) * 13, y + math.sin(a) * 13
        P0:line(x, y, ex, ey, C.cyan, 3, 230, true)
        P0:dot(ex, ey, 3, (i == 0 or i == 2) and C.pink or C.green, 240)
    end
    P0:dot(x, y, 4, C.cyan, 245)

    -- 方向锥
    P0:line(x, y, x + nx * 30, y + ny * 30, C.cyan, 1, 170, false)
    P0:line(x + nx * 22, y + ny * 22, x + nx * 30 - c * 6, y + ny * 30 - sn * 6, C.cyan, 1, 150, true)
    P0:line(x + nx * 22, y + ny * 22, x + nx * 30 + c * 6, y + ny * 30 + sn * 6, C.cyan, 1, 150, true)
end

function M.draw(dt, t)
    local s = sim.s

    P:reset()
    draw_track(P, s)
    draw_wp(P, s)
    draw_drone(P, s)
    P:finish()
    dyn_shape:set_items(P.items)

    -- 位置（做成假的经纬度，看着像真的）
    local lat = 31.2304 + s.py * 0.0000090
    local lon = 121.4737 + s.px * 0.0000105
    parts.text(info.lat, string.format("%.6f N", lat))
    parts.text(info.lon, string.format("%.6f E", lon))
    parts.text(info.alt, string.format("%.1f m", s.alt))
    parts.text(info.gs, string.format("%.1f m/s", s.gs))

    for i = 1, 4 do
        local w = s.wp[i]
        if w then
            local d = math.sqrt(w.x * w.x + w.y * w.y)
            parts.text(wp_nodes[i], string.format("%.0f m", d))
        else
            parts.text(wp_nodes[i], "--")
        end
    end

    local far = 0
    for i = 1, s.track_n do
        local tr = s.track[i]
        local d = math.sqrt(tr.x * tr.x + tr.y * tr.y)
        if d > far then far = d end
    end
    parts.text(info.track, string.format("%d", s.track_n))
    parts.text(info.far, string.format("%.0f m", far))
    parts.text(info.time, sim.fmt_time(s.flight_t))
end

-- ==================== 触摸 ====================
function M.on_touch(state, x, y)
    if state ~= TP_DOWN then return end
    local s = sim.s

    if parts.hit(x, y, clear_btn.x, clear_btn.y, clear_btn.w, clear_btn.h) then
        s.wp_n = 0
        sim.log("info", "航点已清空")
        return
    end

    if not parts.hit(x, y, MV.x, MV.y, MV.w, MV.h) then return end
    -- 地图上点到哪儿就在哪儿插一个航点
    local mx = (x - MV.x - CX) / SCALE
    local my = -(y - MV.y - CY) / SCALE
    if s.wp_n >= MAX_WP then
        sim.log("warn", "航点已满 8 个，请先清除")
        return
    end
    s.wp_n = s.wp_n + 1
    s.wp[s.wp_n] = { x = mx, y = my }
    sim.log("info", string.format("新增航点 %d，距离 %.0f m", s.wp_n,
        math.sqrt(mx * mx + my * my)))
end

function M.leave() end

return M
