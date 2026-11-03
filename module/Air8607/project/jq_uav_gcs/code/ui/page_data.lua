--[[
@module  page_data
@summary UAV GCS - 数据页（六张遥测卡：姿态 / 电机 / 电池 / 传感器 / 高度 / 链路）
@version 1.0
@date    2026.11.02

六张卡 3 列 x 2 行，每张 328x232。
这一页是"工程师视角"：姿态页看的是"飞机现在怎么样"，这一页看的是"各子系统数据对不对"。
刷新率 10Hz（人眼对卡片数字的跳变不敏感，对姿态球的连续转动才敏感），
姿态球走 30fps、这一页走 10Hz，整屏的绘制预算就分开了。

卡片顺序刻意和飞控日志一致：
  姿态 -> 电机 -> 电池 -> 传感器 -> 高度 -> 链路
排查问题时从上往下扫，正好是"控制 -> 动力 -> 能源 -> 感知 -> 导航 -> 通信"。
]]
local fx = require "fx"
local T = require "theme"
local parts = require "parts"
local sim = require "sim"

local C = T.c
local M = {}

local D = T.data
local o = { root = nil }
local P = nil
local card = {}

-- ==================== 小工具 ====================
local function geo_of(col, row)
    return {
        x = D.x + col * (D.w + D.gap),
        y = D.y + row * (D.h + D.gap),
        w = D.w, h = D.h,
    }
end

local function new_card(g, title, en, tint)
    local c = {
        geo = g,
        bg = parts.card(o.root, g, title, en, tint),
    }
    c.dyn = airui.shape({
        parent = o.root, x = g.x, y = g.y, w = g.w, h = g.h, items = {},
    })
    return c
end

-- 卡片内文字（绝对坐标 = 卡片左上角 + 局部坐标）
local function L(c, x, y, w, h, txt, size, col, align)
    return parts.lbl(o.root, c.geo.x + x, c.geo.y + y, w, h, txt, size, col, align)
end

--[[双向条：以中心为 0，frac ∈ [-1, 1]
用于横滚/俯仰/三轴加速度这类"有正负"的量]]
local function bar_center(P0, x, y, w, h, frac, color)
    frac = fx.clamp(frac, -1, 1)
    P0:box(x, y, w, h, C.panel2, 220, math.floor(h / 2))
    local cx = x + w / 2
    local half = w / 2 - 1
    if math.abs(frac) > 0.01 then
        local fw = frac * half
        local bx = (fw >= 0) and cx or (cx + fw)
        P0:box(bx, y, math.abs(fw), h, color, 230, math.floor(h / 2))
        P0:dot(cx + fw, y + h / 2, math.floor(h * 0.42), fx.shade(color, 0.6), 230)
    end
    P0:line(cx, y - 2, cx, y + h + 2, C.dim2, 1, 200, false)
end

-- ==================== 构建 ====================
function M.build(parent)
    o.root = parent
    P = fx.pool()

    -- ---------- 1 姿态 ----------
    local c1 = new_card(geo_of(0, 0), "姿态角 ATTITUDE", "deg", C.violet)
    card[1] = c1
    local rows = {
        { "ROLL  横滚", C.violet },
        { "PITCH 俯仰", C.blue },
        { "YAW   航向", C.cyan },
    }
    c1.rows = {}
    for i = 1, 3 do
        local y = 42 + (i - 1) * 58
        L(c1, 16, y, 120, 18, rows[i][1], T.f.mini, C.dim, airui.TEXT_ALIGN_LEFT)
        c1.rows[i] = L(c1, 196, y - 4, 116, 26, "0.0", T.f.mid, rows[i][2],
            airui.TEXT_ALIGN_RIGHT)
    end

    -- ---------- 2 电机 ----------
    local c2 = new_card(geo_of(1, 0), "电机转速 MOTOR", "RPM", C.green)
    card[2] = c2
    c2.rpm = {}
    for i = 1, 4 do
        local x = 22 + (i - 1) * 76
        c2.rpm[i] = L(c2, x, 38, 64, 18, "0", T.f.mini, C.dim, airui.TEXT_ALIGN_CENTER)
        L(c2, x, 196, 64, 18, "M" .. i, T.f.mini, C.dim2, airui.TEXT_ALIGN_CENTER)
    end
    L(c2, 16, 214, 296, 16, "M1 前右 / M2 前左 / M3 后右 / M4 后左",
        T.f.mini, C.dim2, airui.TEXT_ALIGN_LEFT)

    -- ---------- 3 电池 ----------
    local c3 = new_card(geo_of(2, 0), "电池 BATTERY", "4S", C.amber)
    card[3] = c3
    c3.batt = L(c3, 14, 36, 130, 52, "100%", T.f.big, C.amber, airui.TEXT_ALIGN_LEFT)
    L(c3, 150, 44, 60, 18, "电压", T.f.mini, C.dim2, airui.TEXT_ALIGN_RIGHT)
    c3.volt = L(c3, 210, 40, 100, 24, "16.7 V", T.f.mid, C.txt, airui.TEXT_ALIGN_RIGHT)
    L(c3, 150, 74, 60, 18, "电流", T.f.mini, C.dim2, airui.TEXT_ALIGN_RIGHT)
    c3.curr = L(c3, 210, 70, 100, 24, "0.0 A", T.f.mid, C.txt, airui.TEXT_ALIGN_RIGHT)
    L(c3, 16, 126, 120, 18, "剩余电量", T.f.mini, C.dim, airui.TEXT_ALIGN_LEFT)
    c3.mah = L(c3, 180, 124, 132, 20, "0 mAh", T.f.sub, C.dim,
        airui.TEXT_ALIGN_RIGHT)
    L(c3, 16, 170, 120, 18, "电调温度", T.f.mini, C.dim2, airui.TEXT_ALIGN_LEFT)
    c3.tesc = L(c3, 120, 168, 90, 20, "26 C", T.f.sub, C.dim, airui.TEXT_ALIGN_RIGHT)
    L(c3, 16, 196, 120, 18, "IMU 温度", T.f.mini, C.dim2, airui.TEXT_ALIGN_LEFT)
    c3.timu = L(c3, 120, 194, 90, 20, "28 C", T.f.sub, C.dim, airui.TEXT_ALIGN_RIGHT)

    -- ---------- 4 传感器 ----------
    local c4 = new_card(geo_of(0, 1), "传感器 SENSOR", "IMU", C.blue)
    card[4] = c4
    local srows = { "振动 VIB", "加速度 AX", "加速度 AY", "加速度 AZ" }
    c4.srows = {}
    for i = 1, 4 do
        local y = 40 + (i - 1) * 44
        L(c4, 16, y, 120, 18, srows[i], T.f.mini, C.dim, airui.TEXT_ALIGN_LEFT)
        c4.srows[i] = L(c4, 200, y - 4, 112, 24, "0.00", T.f.sub, C.blue,
            airui.TEXT_ALIGN_RIGHT)
    end

    -- ---------- 5 高度剖面 ----------
    local c5 = new_card(geo_of(1, 1), "高度剖面 ALTITUDE", "18s", C.cyan)
    card[5] = c5
    c5.amax = L(c5, 16, 38, 140, 20, "最高 0.0 m", T.f.sub, C.dim, airui.TEXT_ALIGN_LEFT)
    c5.amin = L(c5, 172, 38, 140, 20, "最低 0.0 m", T.f.sub, C.dim,
        airui.TEXT_ALIGN_RIGHT)
    L(c5, 16, 182, 120, 18, "垂直速度", T.f.mini, C.dim2, airui.TEXT_ALIGN_LEFT)
    c5.vs = L(c5, 120, 178, 192, 24, "+0.0 m/s", T.f.mid, C.green,
        airui.TEXT_ALIGN_RIGHT)
    L(c5, 16, 208, 120, 18, "对地速度", T.f.mini, C.dim2, airui.TEXT_ALIGN_LEFT)
    c5.gs = L(c5, 120, 204, 192, 24, "0.0 m/s", T.f.mid, C.cyan,
        airui.TEXT_ALIGN_RIGHT)

    -- ---------- 6 链路 ----------
    local c6 = new_card(geo_of(2, 1), "链路 LINK", "2.4G", C.pink)
    card[6] = c6
    c6.rssi = L(c6, 16, 38, 180, 24, "-60 dBm", T.f.mid, C.pink, airui.TEXT_ALIGN_LEFT)
    c6.state = L(c6, 200, 40, 112, 20, "在线", T.f.sub, C.green,
        airui.TEXT_ALIGN_RIGHT)
    L(c6, 16, 150, 100, 18, "丢包率", T.f.mini, C.dim2, airui.TEXT_ALIGN_LEFT)
    c6.loss = L(c6, 116, 148, 90, 20, "0.4 %", T.f.sub, C.dim, airui.TEXT_ALIGN_LEFT)
    L(c6, 16, 176, 100, 18, "往返延时", T.f.mini, C.dim2, airui.TEXT_ALIGN_LEFT)
    c6.lat = L(c6, 116, 174, 90, 20, "24 ms", T.f.sub, C.dim, airui.TEXT_ALIGN_LEFT)
    L(c6, 16, 204, 100, 18, "卫星数", T.f.mini, C.dim2, airui.TEXT_ALIGN_LEFT)
    c6.sats = L(c6, 116, 202, 90, 20, "14", T.f.sub, C.dim, airui.TEXT_ALIGN_LEFT)
    c6.hdop = L(c6, 210, 202, 102, 20, "HDOP 0.8", T.f.mini, C.dim2,
        airui.TEXT_ALIGN_RIGHT)
end

-- ==================== 每帧（10Hz） ====================
function M.draw(dt, t)
    local s = sim.s

    -- ---------- 1 姿态 ----------
    local c1 = card[1]
    P:reset()
    bar_center(P, 16, 66, 296, 10, s.roll / 30, C.violet)
    bar_center(P, 16, 124, 296, 10, s.pitch / 30, C.blue)
    -- 航向没有正负，用整条进度表示
    P:box(16, 182, 296, 10, C.panel2, 220, 5)
    P:box(16, 182, 296 * (s.yaw / 360), 10, C.cyan, 230, 5)
    P:dot(16 + 296 * (s.yaw / 360), 187, 5, C.cyan, 200)
    P:finish()
    c1.dyn:set_items(P.items)
    parts.text(c1.rows[1], string.format("%+.1f", s.roll))
    parts.text(c1.rows[2], string.format("%+.1f", s.pitch))
    parts.text(c1.rows[3], string.format("%03d", math.floor(s.yaw + 0.5) % 360))

    -- ---------- 2 电机 ----------
    local c2 = card[2]
    P:reset()
    for i = 1, 4 do
        local x = 22 + (i - 1) * 76
        local rpm = s.rpm[i] or 0
        parts.vbar(P, x + 14, 58, 36, 132, rpm / 8000,
            (i <= 2) and C.pink or C.green)
        -- 每根柱子上叠一条刻度参考线（满转的 50%），读起来有"标尺"感
        P:line(x + 14, 58 + 66, x + 50, 58 + 66, C.dim2, 1, 120, false)
    end
    P:finish()
    c2.dyn:set_items(P.items)
    for i = 1, 4 do
        parts.text(c2.rpm[i], string.format("%d", math.floor((s.rpm[i] or 0) + 0.5)))
    end

    -- ---------- 3 电池 ----------
    local c3 = card[3]
    P:reset()
    -- 电量条：20 段，低于 20% 变红
    local seg = 20
    local on = math.floor(s.batt / 100 * seg + 0.5)
    local bcol = (s.batt < 20) and C.red or ((s.batt < 45) and C.amber or C.green)
    for i = 1, seg do
        local x = 16 + (i - 1) * 15
        P:box(x, 150, 11, 16, (i <= on) and bcol or C.panel2, (i <= on) and 240 or 200, 2)
    end
    P:finish()
    c3.dyn:set_items(P.items)
    parts.text(c3.batt, string.format("%d%%", math.floor(s.batt + 0.5)))
    parts.text(c3.volt, string.format("%.2f V", s.volt))
    parts.text(c3.curr, string.format("%.1f A", s.curr))
    parts.text(c3.mah, string.format("%d mAh", math.floor(s.mah + 0.5)))
    parts.text(c3.tesc, string.format("%d C", math.floor(s.temp_esc + 0.5)))
    parts.text(c3.timu, string.format("%d C", math.floor(s.temp_imu + 0.5)))

    -- ---------- 4 传感器 ----------
    local c4 = card[4]
    local ax = math.sin(math.rad(s.roll)) + (fx.noise1(t * 7) - 0.5) * 0.06
    local ay = -math.sin(math.rad(s.pitch)) + (fx.noise1(t * 9 + 3) - 0.5) * 0.06
    local az = math.cos(math.rad(s.roll)) * math.cos(math.rad(s.pitch))
    P:reset()
    parts.meter(P, 16, 62, 296, 8, s.vib / 0.5, C.amber)
    bar_center(P, 16, 100, 296, 8, ax, C.blue)
    bar_center(P, 16, 144, 296, 8, ay, C.blue)
    bar_center(P, 16, 188, 296, 8, (az - 0.5) * 2, C.green)
    P:finish()
    c4.dyn:set_items(P.items)
    parts.text(c4.srows[1], string.format("%.2f g", s.vib))
    parts.text(c4.srows[2], string.format("%+.2f", ax))
    parts.text(c4.srows[3], string.format("%+.2f", ay))
    parts.text(c4.srows[4], string.format("%.2f", az))

    -- ---------- 5 高度剖面 ----------
    local c5 = card[5]
    P:reset()
    P:box(16, 62, 296, 108, 0x060B14, 235, 6)
    P:frame(16, 62, 296, 108, C.line, 1, 200, 6)
    for i = 0, 3 do
        local y = 62 + i * 36
        P:line(16, y, 311, y, C.line, 1, 90, false)
    end
    parts.spark(P, s.alt_hist, #s.alt_hist, 20, 66, 288, 100, 0, 60, C.cyan, 2, 235, true)
    P:finish()
    c5.dyn:set_items(P.items)

    local amax, amin = 0, 999
    for i = 1, #s.alt_hist do
        local v = s.alt_hist[i]
        if v > amax then amax = v end
        if v < amin then amin = v end
    end
    if amin > 900 then amin = 0 end
    parts.text(c5.amax, string.format("最高 %.1f m", amax))
    parts.text(c5.amin, string.format("最低 %.1f m", amin))
    parts.text(c5.vs, string.format("%+.1f m/s", s.vspd))
    parts.text(c5.gs, string.format("%.1f m/s", s.gs))

    -- ---------- 6 链路 ----------
    local c6 = card[6]
    P:reset()
    P:box(16, 62, 296, 78, 0x060B14, 235, 6)
    for i = 0, 2 do
        P:line(16, 62 + i * 26, 311, 62 + i * 26, C.line, 1, 80, false)
    end
    parts.spark(P, s.rssi_hist, #s.rssi_hist, 20, 66, 288, 70, -100, -40, C.pink, 2, 235, true)
    P:finish()
    c6.dyn:set_items(P.items)
    parts.text(c6.rssi, string.format("%d dBm", math.floor(s.rssi + 0.5)))
    parts.text(c6.state, s.link and "在线" or "断开")
    parts.text(c6.loss, string.format("%.1f %%", s.loss))
    parts.text(c6.lat, string.format("%d ms", math.floor(s.lat + 0.5)))
    parts.text(c6.sats, string.format("%d", s.sats))
    parts.text(c6.hdop, string.format("HDOP %.1f", s.hdop))
end

function M.on_touch(state, x, y)
    -- 这一页是纯读数，不接交互（点卡片不弹窗，避免误触打断观察）
end

function M.leave() end

return M
