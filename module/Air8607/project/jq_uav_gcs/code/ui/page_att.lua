--[[
@module  page_att
@summary UAV GCS - 姿态页（3D 机体舱 + 人工地平仪 + 遥测表 + 动作键）
@version 1.0
@date    2026.11.02

画面构成（内容区坐标 1024x496）：
  左  3D 视图 590x404：线框训练场 + 四旋翼机体 + 推力光柱 + 虚拟摇杆指示
  右下 动作键 4 枚：解锁 / 起飞 / 返航 / 降落
  右上 人工地平仪 404x290（hud.lua）：姿态球 + 罗盘环 + 速度高度带
  中右 三个大读数：ROLL / PITCH / YAW
  下右 遥测表 2x4：模式 / 锁定 / 高度 / 电压 / 卫星 / 精度 / 链路 / 时间

交互：
  按住 3D 视图拖动 = 虚拟摇杆（左右横滚、上下俯仰），松手回中
  四枚动作键直接改飞行状态，日志会同步写到功能页
]]
local fx = require "fx"
local T = require "theme"
local parts = require "parts"
local sim = require "sim"
local hud = require "hud"
local model3d = require "model3d"

local C = T.c
local M = {}

local V = T.att.view
local CAM = T.att.cam
local BTN = T.att.btn
local TP_DOWN, TP_HOLD, TP_UP = T.TP_DOWN, T.TP_HOLD, T.TP_UP

local o = {
    stick = false,
}

local P = nil          -- 3D 动态层图元池
local sP = nil         -- 整页静态层图元池
local cell = {}        -- 遥测单元格 {title=, value=}
local act = {}         -- 动作键

-- ==================== 静态层 ====================
--[[房间单独一个 shape，直接摆在视图矩形上：
投影原点是视图左上角，这样 build_room 拿到的 (cx, cy) 就是本地点，
不用再到处减 offset —— 上一版就是忘了平移，网格整体偏了 (10, 8)。]]
local function build_room_layer(parent)
    local room = airui.shape({
        parent = parent, x = V.x, y = V.y, w = V.w, h = V.h, items = {},
    })
    local rp = fx.pool()
    rp:reset()
    model3d.build_room(rp, CAM)
    rp:finish()
    room:set_items(rp.items)
    o.room = room
end

local function build_static()
    sP:reset()

    -- 3D 视图外框 + 四角括号
    local vx, vy, vw, vh = V.x, V.y, V.w, V.h
    sP:box(vx, vy, vw - 1, vh - 1, 0x070C15, 255, 10)
    sP:frame(vx, vy, vw - 1, vh - 1, C.line, 1, 255, 10)
    local c = 22
    sP:line(vx + 1, vy + 1, vx + c, vy + 1, C.cyan, 2, 210, false)
    sP:line(vx + 1, vy + 1, vx + 1, vy + c, C.cyan, 2, 210, false)
    sP:line(vx + vw - c, vy + 1, vx + vw - 1, vy + 1, C.cyan, 2, 210, false)
    sP:line(vx + vw - 1, vy + 1, vx + vw - 1, vy + c, C.cyan, 2, 210, false)
    sP:line(vx + 1, vy + vh - c, vx + 1, vy + vh - 1, C.cyan, 2, 210, false)
    sP:line(vx + 1, vy + vh - 1, vx + c, vy + vh - 1, C.cyan, 2, 210, false)
    sP:line(vx + vw - c, vy + vh - 1, vx + vw - 1, vy + vh - 1, C.cyan, 2, 210, false)
    sP:line(vx + vw - 1, vy + vh - c, vx + vw - 1, vy + vh - 1, C.cyan, 2, 210, false)

    -- 读数条底板
    local ry = T.att.read_y
    sP:box(612, ry, 403, 50, C.panel, 245, 10)
    sP:frame(612, ry, 403, 50, C.line, 1, 240, 10)
    sP:line(746, ry + 10, 746, ry + 40, C.line2, 1, 180, false)
    sP:line(880, ry + 10, 880, ry + 40, C.line2, 1, 180, false)

    -- 遥测表底板（两行）
    local ty = T.att.telem.y
    for r = 0, 1 do
        local y = ty + r * (T.att.telem.row + T.att.telem.gap)
        sP:box(612, y, 403, T.att.telem.row - 1, C.panel, 245, 8)
        sP:frame(612, y, 403, T.att.telem.row - 1, C.line, 1, 230, 8)
        for i = 1, 3 do
            local x = 612 + i * 101
            sP:line(x, y + 10, x, y + T.att.telem.row - 12, C.line, 1, 150, false)
        end
    end

    sP:finish()
    o.stat:set_items(sP.items)
end

-- ==================== 摇杆指示 ====================
local function draw_stick_indicator(PP, s)
    if not s.manual then return end
    local cx = V.w - 74
    local cy = V.h - 74
    PP:ring(cx, cy, 46, C.cyan, 1, 90)
    PP:ring(cx, cy, 30, C.line2, 1, 80)
    PP:line(cx - 52, cy, cx + 52, cy, C.line2, 1, 70, false)
    PP:line(cx, cy - 52, cx, cy + 52, C.line2, 1, 70, false)
    local px = cx + fx.clamp(s.cmd.r, -1, 1) * 46
    local py = cy - fx.clamp(s.cmd.p, -1, 1) * 46
    PP:line(cx, cy, px, py, C.cyan, 1, 150, false)
    PP:dot(px, py, 8, C.cyan, 60)
    PP:dot(px, py, 4, C.cyan, 250)
end

-- ==================== 构建 ====================
function M.build(parent)
    o.root = parent
    sP = fx.pool()
    P = fx.pool()

    o.stat = airui.shape({
        parent = parent, x = 0, y = 0, w = T.screen.w, h = T.content.h, items = {},
    })
    build_static()
    build_room_layer(parent)

    o.model = airui.shape({
        parent = parent, x = V.x, y = V.y, w = V.w, h = V.h, items = {},
    })

    -- ---------- 3D 视图上的文字 ----------
    parts.lbl(parent, V.x + 18, V.y + 12, 260, 20, "机体姿态  BODY ATTITUDE",
        T.f.mini, C.dim, airui.TEXT_ALIGN_LEFT)
    o.v_r = parts.lbl(parent, V.x + V.w - 234, V.y + 10, 70, 20, "R +0.0",
        T.f.sub, C.violet, airui.TEXT_ALIGN_RIGHT)
    o.v_p = parts.lbl(parent, V.x + V.w - 156, V.y + 10, 70, 20, "P +0.0",
        T.f.sub, C.blue, airui.TEXT_ALIGN_RIGHT)
    o.v_y = parts.lbl(parent, V.x + V.w - 78, V.y + 10, 62, 20, "Y 000",
        T.f.sub, C.cyan, airui.TEXT_ALIGN_RIGHT)

    parts.lbl(parent, V.x + 18, V.y + V.h - 30, 200, 18, "按住拖拽 虚拟摇杆",
        T.f.mini, C.dim2, airui.TEXT_ALIGN_LEFT)
    o.v_h = parts.lbl(parent, V.x + V.w - 200, V.y + V.h - 30, 182, 18, "ALT 0.0 m",
        T.f.mini, C.dim, airui.TEXT_ALIGN_RIGHT)

    -- ---------- 动作键 ----------
    local names = { "解锁", "起飞", "返航", "降落" }
    for i = 1, 4 do
        local x = BTN.x + (i - 1) * (BTN.w + BTN.gap)
        act[i] = parts.button(parent, x, BTN.y, BTN.w, BTN.h, names[i], C.cyan, T.f.mid)
        parts.button_paint(act[i], false, C.cyan)
    end

    -- ---------- 人工地平仪 ----------
    hud.build(parent, T.att)

    -- ---------- 三个大读数 ----------
    local ry = T.att.read_y
    local rds = {
        { name = "ROLL", unit = "横滚", col = C.violet },
        { name = "PITCH", unit = "俯仰", col = C.blue },
        { name = "YAW", unit = "航向", col = C.cyan },
    }
    o.rd = {}
    for i = 1, 3 do
        local x = 612 + (i - 1) * 134
        parts.lbl(parent, x + 14, ry + 8, 110, 16, rds[i].name, T.f.mini,
            C.dim2, airui.TEXT_ALIGN_LEFT)
        parts.lbl(parent, x + 84, ry + 6, 42, 16, rds[i].unit, T.f.mini,
            C.dim2, airui.TEXT_ALIGN_RIGHT)
        o.rd[i] = parts.lbl(parent, x + 12, ry + 22, 116, 26, "0.0",
            T.f.num, rds[i].col, airui.TEXT_ALIGN_LEFT)
    end

    -- ---------- 遥测表 2x4 ----------
    local titles = {
        "飞行模式", "锁定状态", "高度", "电压",
        "卫星数", "定位精度", "链路", "飞行时间",
    }
    cell = {}
    for i = 1, 8 do
        local r = (i - 1) // 4
        local c = (i - 1) % 4
        local x = 612 + c * 101
        local y = T.att.telem.y + r * (T.att.telem.row + T.att.telem.gap)
        parts.lbl(parent, x + 12, y + 6, 84, 14, titles[i], T.f.mini,
            C.dim2, airui.TEXT_ALIGN_LEFT)
        cell[i] = {
            value = parts.lbl(parent, x + 12, y + 22, 88, 24, "--",
                T.f.body, C.txt, airui.TEXT_ALIGN_LEFT),
        }
    end
end

-- ==================== 每帧 ====================
function M.draw(dt, t)
    local s = sim.s

    P:reset()
    model3d.draw(P, CAM, s, t)
    draw_stick_indicator(P, s)
    P:finish()
    o.model:set_items(P.items)

    hud.draw(s, t)

    -- 3D 视图顶部读数
    parts.text(o.v_r, string.format("R %+.1f", s.roll))
    parts.text(o.v_p, string.format("P %+.1f", s.pitch))
    parts.text(o.v_y, string.format("Y %03d", math.floor(s.yaw + 0.5) % 360))
    parts.text(o.v_h, string.format("ALT %.1f m   GS %.1f m/s", s.alt, s.gs))

    -- 大读数
    parts.text(o.rd[1], string.format("%+.1f", s.roll))
    parts.text(o.rd[2], string.format("%+.1f", s.pitch))
    parts.text(o.rd[3], string.format("%03d", math.floor(s.yaw + 0.5) % 360))

    -- 遥测表
    local link_txt = s.link and "在线" or "断开"
    parts.text(cell[1].value, sim.MODES[s.mode])
    parts.text(cell[2].value, s.armed and "解锁" or "上锁")
    parts.text(cell[3].value, string.format("%.1f m", s.alt))
    parts.text(cell[4].value, string.format("%.1f V", s.volt))
    parts.text(cell[5].value, string.format("%d", s.sats))
    parts.text(cell[6].value, string.format("%.2f", s.hdop))
    parts.text(cell[7].value, link_txt)
    parts.text(cell[8].value, sim.fmt_time(s.flight_t))

    -- 解锁键文字随状态变，颜色也随之变
    local armed = s.armed
    if o.armed_state ~= armed then
        o.armed_state = armed
        parts.text(act[1].label, armed and "上锁" or "解锁")
        parts.button_paint(act[1], armed, C.amber)
    end
end

-- ==================== 触摸 ====================
function M.on_touch(state, x, y)
    local s = sim.s
    if state == TP_DOWN then
        -- 动作键
        for i = 1, 4 do
            if parts.hit(x, y, act[i].x, act[i].y, act[i].w, act[i].h) then
                sim.touch()
                if i == 1 then
                    sim.arm(not s.armed)
                elseif i == 2 then
                    sim.takeoff(12)
                elseif i == 3 then
                    sim.rtl()
                else
                    sim.land()
                end
                return
            end
        end

        -- 3D 视图：进入虚拟摇杆
        if parts.hit(x, y, V.x, V.y, V.w, V.h) then
            sim.touch()
            o.stick = true
            M.stick_move(x, y)
            return
        end
    elseif state == TP_HOLD then
        if o.stick then
            M.stick_move(x, y)
            return
        end
    elseif state == TP_UP then
        if o.stick then
            o.stick = false
            sim.stick_neutral()
        end
    end
end

function M.stick_move(x, y)
    local cx = V.x + V.w / 2
    local cy = V.y + V.h / 2
    local r = fx.clamp((x - cx) / (V.w * 0.42), -1, 1)
    local p = fx.clamp((cy - y) / (V.h * 0.42), -1, 1)
    sim.set_stick(r, p, 0)
end

-- 页面切走时释放摇杆，避免"按住时切页"导致指令卡住
function M.leave()
    if o.stick then
        o.stick = false
        sim.stick_neutral()
    end
end

return M
